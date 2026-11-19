import { webSocket } from '@kit.NetworkKit';
import nativeVideo, { DecoderStats } from 'libt3device.so';
import { record } from '../protocol/Wire';
import { androidVideoPacket, androidSpsSize, androidKeyframe, AndroidVideoSize, AndroidControlInput, AndroidControlPoint, androidTouch, androidControlJson } from '../protocol/AndroidVideo';

interface AndroidQueuedInput {
  input: AndroidControlInput;
  data: string;
  epoch: number;
  resolve: () => void;
  reject: (error: Error) => void;
}

export class AndroidDeviceStream {
  onSize: (size: AndroidVideoSize) => void = () => {};
  onStats: (stats: DecoderStats) => void = () => {};
  onStatus: (status: string) => void = () => {};
  onInputReady: (ready: boolean) => void = () => {};
  onVideoReset: () => void = () => {};
  onFailure: (message: string) => void = () => {};
  private socket: webSocket.WebSocket | undefined = undefined;
  private generation: number = 0;
  private epoch: number = 0;
  private sps: Uint8Array | undefined = undefined;
  private pps: Uint8Array | undefined = undefined;
  private spsIdentity: string = '';
  private waitingKey: boolean = true;
  private surfaceId: string = '';
  private timer: number = -1;
  private lastKeyRequest: number = 0;
  private startedAt: number = 0;
  private alive: () => boolean;
  private canOperate: () => boolean;
  private connected: boolean = false;
  private frameReady: boolean = false;
  private inputReady: boolean = false;
  private inputQueue: AndroidQueuedInput[] = [];
  private sending: boolean = false;
  private pressed: AndroidControlPoint | undefined = undefined;
  constructor(alive: () => boolean, canOperate: () => boolean = () => false) {
    this.alive = alive; this.canOperate = canOperate;
  }
  async start(url: string, surfaceId: string): Promise<void> {
    this.stop();
    if (!/^wss?:\/\/[^\s]+$/.test(url) || !/^\d{1,20}$/.test(surfaceId) || !this.alive()) throw new Error('设备视频连接或 Surface 已失效');
    this.surfaceId = surfaceId; this.startedAt = Date.now();
    const generation = this.generation;
    const socket = webSocket.createWebSocket(); this.socket = socket;
    socket.on('message', (error, value: string | ArrayBuffer): void => {
      if (!this.current(generation)) return;
      if (error && error.code !== 0) { this.fail('Android 视频接收失败'); return; }
      try {
        if (typeof value === 'string') {
          if (value.length > 65536) throw new Error('视频控制消息超限');
          if (record(JSON.parse(value)).type === 'video-session') {
            this.resetDecoder(); this.onStatus('视频尺寸已改变，等待新关键帧'); this.requestKeyframe();
          }
          return;
        }
        const packet = androidVideoPacket(value, (Date.now() - this.startedAt) * 1000);
        if (packet.sps) {
          const identity = Array.from(packet.sps).join(',');
          if (identity !== this.spsIdentity) {
            this.resetDecoder(); this.sps = packet.sps; this.spsIdentity = identity;
          }
        }
        if (packet.pps) this.pps = packet.pps;
        if (!this.sps || !this.pps || this.waitingKey && !packet.key) { this.requestKeyframe(); return; }
        if (!this.epoch) {
          const size = androidSpsSize(this.sps);
          this.epoch = nativeVideo.start(this.surfaceId, size.width, size.height);
          this.onSize(size); this.onStatus('正在启动原生 H.264 解码器');
        }
        const bytes = packet.key ? androidKeyframe(packet.data, this.sps, this.pps) : packet.data.slice().buffer;
        const accepted = nativeVideo.push(this.epoch, bytes, packet.timestamp, packet.key);
        if (accepted === 1) { this.waitingKey = true; this.requestKeyframe(); }
        else if (accepted === 2) {
          const stats = nativeVideo.stats();
          throw new Error(stats.error || '原生视频会话已失效（期望 ' + this.epoch + '，当前 ' + stats.epoch + '）');
        }
        else this.waitingKey = false;
      } catch (reason) { this.fail((reason as Error).message); }
    });
    socket.on('error', (): void => { if (generation === this.generation) this.fail('设备视频连接失败，请重新取得媒体票据'); });
    socket.on('close', (): void => { if (generation === this.generation) this.fail('设备视频已断开，不会自动重连或重放操作'); });
    this.timer = setInterval((): void => {
      if (!this.current(generation)) return;
      if (this.epoch) {
        const stats = nativeVideo.stats();
        if (stats.epoch !== this.epoch) { this.fail('原生解码器已被其他画面接管'); return; }
        this.frameReady = stats.rendered > 0; this.refreshInputReady();
        this.onStats(stats);
        if (stats.error) { this.fail(stats.error); return; }
        if (stats.rendered > 0) return;
      }
      if (Date.now() - this.startedAt > 15000) this.fail('未收到可渲染的 H.264 关键帧，请检查设备和编码器');
    }, 250);
    try {
      this.onStatus('正在连接 Android 视频流…');
      if (!await socket.connect(url)) throw new Error('connect');
      if (this.current(generation)) { this.connected = true; this.refreshInputReady(); this.requestKeyframe(); }
    } catch (_) { if (generation === this.generation) this.fail('Android 视频连接失败'); }
  }
  private resetDecoder(): void {
    this.frameReady = false; this.refreshInputReady(); this.onVideoReset();
    if (this.epoch) nativeVideo.stop(this.epoch);
    this.epoch = 0; this.sps = undefined; this.pps = undefined; this.spsIdentity = '';
    this.waitingKey = true; this.startedAt = Date.now();
  }
  private current(generation: number): boolean {
    if (generation !== this.generation) return false;
    if (!this.alive()) { this.fail('环境或设备已改变'); return false; }
    return true;
  }
  private requestKeyframe(): void {
    if (!this.socket || Date.now() - this.lastKeyRequest < 500) return;
    this.lastKeyRequest = Date.now(); const generation = this.generation;
    void this.socket.send('{"type":"reset-video","ack":false}').catch(() => {
      if (generation === this.generation) this.fail('无法请求设备关键帧');
    });
  }
  private refreshInputReady(): void {
    const ready = this.connected && this.frameReady && this.alive() && this.canOperate();
    if (ready === this.inputReady) return;
    this.inputReady = ready;
    if (!ready) { this.cancelInputs('设备输入已暂停'); this.releasePressed(false); }
    this.onInputReady(ready);
  }
  private cancelInputs(message: string): void {
    const queued = this.inputQueue; this.inputQueue = [];
    for (const item of queued) item.reject(new Error(message));
  }
  private releasePressed(close: boolean): void {
    const socket = this.socket; const point = this.pressed; this.pressed = undefined;
    if (!socket) return;
    if (!point) { if (close) void socket.close().catch(() => {}); return; }
    // Only release the existing touch on its original socket; never retry it on a replacement connection.
    const generation = this.generation;
    const timeout = close ? setTimeout(() => { void socket.close().catch(() => {}); }, 250) : -1;
    void socket.send(JSON.stringify(androidTouch('up', point))).then(() => {
      if (timeout >= 0) clearTimeout(timeout);
      if (close) void socket.close().catch(() => {});
    }).catch(() => {
      if (timeout >= 0) clearTimeout(timeout);
      if (close) void socket.close().catch(() => {});
      else if (generation === this.generation) this.fail('设备抬手结果未知，请核对设备');
    });
  }
  async releaseTouch(): Promise<void> {
    const point = this.pressed;
    if (point) await this.sendInput(androidTouch('up', point));
  }
  sendInput(input: AndroidControlInput): Promise<void> {
    if (!this.current(this.generation) || !this.inputReady || !this.canOperate() || !this.socket) {
      return Promise.reject(new Error('设备尚未准入控制或操作权限已失效'));
    }
    let data: string;
    try { data = androidControlJson(input); } catch (reason) { return Promise.reject(reason as Error); }
    const safeInput = JSON.parse(data) as AndroidControlInput;
    return new Promise<void>((resolve, reject) => {
      const item: AndroidQueuedInput = { input: safeInput, data, epoch: this.epoch, resolve, reject };
      const tail = this.inputQueue[this.inputQueue.length - 1];
      if (input.type === 'touch' && input.action === 'move' && tail?.input.type === 'touch' && tail.input.action === 'move') {
        tail.resolve(); this.inputQueue[this.inputQueue.length - 1] = item;
      } else this.inputQueue.push(item);
      if (this.inputQueue.length > 64) { this.fail('设备输入队列超限，已停止且不会自动重发'); return; }
      if (!this.sending) void this.flushInput();
    });
  }
  private async flushInput(): Promise<void> {
    const generation = this.generation; const socket = this.socket;
    if (!socket) return;
    this.sending = true;
    try {
      while (this.inputQueue.length && generation === this.generation) {
        const item = this.inputQueue.shift(); if (!item) continue;
        if (item.epoch !== this.epoch) { item.reject(new Error('设备画面已变化，旧输入未发送')); continue; }
        if (!this.alive() || !this.canOperate() || !this.inputReady) { item.reject(new Error('设备输入权限已失效')); this.fail('设备输入权限已失效'); return; }
        try {
          if (item.input.type === 'touch' && item.input.x !== undefined && item.input.y !== undefined) {
            this.pressed = item.input.action === 'up' ? undefined : { x: item.input.x, y: item.input.y };
          }
          if (!await socket.send(item.data)) throw new Error('send');
          if (generation !== this.generation || !this.alive()) throw new Error('changed');
          if (item.epoch !== this.epoch) { item.reject(new Error('设备画面已变化，请核对旧输入结果')); continue; }
          item.resolve();
        } catch (_) {
          item.reject(new Error('设备输入结果未知，不会自动重发'));
          if (generation === this.generation) this.fail('设备输入结果未知，不会自动重发');
          return;
        }
      }
    } finally { if (generation === this.generation) this.sending = false; }
  }
  stop(): void {
    this.generation++;
    if (this.timer >= 0) clearInterval(this.timer); this.timer = -1;
    this.cancelInputs('设备连接已关闭，输入未重放');
    this.releasePressed(true);
    this.socket = undefined; this.connected = false; this.inputReady = false; this.sending = false;
    this.onInputReady(false); this.resetDecoder(); this.lastKeyRequest = 0;
  }
  private fail(message: string): void { this.stop(); this.onFailure(message); }
}
