import { webSocket } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';
import { record, text } from '../protocol/Wire';
import { shouldBypassSystemProxy } from '../protocol/Hosts';
import { PreviewViewport, PreviewControl, previewStreamViewport, previewControl, previewCanSend,
  previewJpeg, previewSourceOversized, previewDecodeSize, previewOutputSize,
  PREVIEW_MAX_MESSAGE_CHARS, PREVIEW_MAX_CONSECUTIVE_OVERSIZE_FRAMES } from '../protocol/Preview';

interface PreviewFramePacket { bytes: ArrayBuffer; viewportRevision: number; }

export class PreviewStream {
  onFrame: (frame: image.PixelMap, size: PreviewViewport) => void = () => {};
  onFrameSkipped: () => void = () => {};
  onViewport: (viewport: PreviewViewport) => void = () => {};
  onControl: (control: PreviewControl) => void = () => {};
  onStatus: (status: string) => void = () => {};
  onFailure: (message: string) => void = () => {};
  private socket: webSocket.WebSocket | undefined = undefined;
  private control: PreviewControl | undefined = undefined;
  private generation: number = 0;
  private decoding: boolean = false;
  private viewportRevision: number = 0;
  private consecutiveOversized: number = 0;
  private pending: PreviewFramePacket | undefined = undefined;
  private alive: () => boolean;
  constructor(alive: () => boolean) { this.alive = alive; }

  async start(target: string): Promise<void> {
    this.stop();
    if (target.length > 16384 || !/^wss?:\/\/[^\s]+$/.test(target) || !this.alive()) throw new Error('预览连接已失效');
    const generation = this.generation;
    const socket = webSocket.createWebSocket(); this.socket = socket;
    socket.on('message', (error, data: string | ArrayBuffer) => {
      if (generation !== this.generation) return;
      if (!this.alive()) { this.fail('当前环境或会话已改变，请重新打开预览'); return; }
      if (error && error.code !== 0) { this.fail('预览消息接收失败'); return; }
      try {
        if (typeof data === 'string') this.message(data);
        else {
          previewJpeg(data);
          const packet: PreviewFramePacket = { bytes: data, viewportRevision: this.viewportRevision };
          if (this.decoding) {
            if (this.pending) void this.ack(generation);
            this.pending = packet;
          } else void this.decode(packet, generation);
        }
      } catch (reason) { this.fail((reason as Error).message); }
    });
    socket.on('error', () => { if (generation === this.generation) this.fail('预览连接失败，请重新连接取得新访问票据'); });
    socket.on('close', (_, result: webSocket.CloseResult) => {
      if (generation !== this.generation) return;
      const code = result ? result.code : 0;
      this.fail(code === 4404 ? '远端预览页已关闭' : code === 4503 ? '服务器浏览器尚未就绪，请安装或配置 Chromium' :
        code === 4401 || code === 1008 ? '预览访问已失效，请重新连接' : '预览已断开；操作结果请重连后核对');
    });
    this.onStatus('正在连接远端画面…');
    try {
      const socketOptions: webSocket.WebSocketRequestOptions | undefined =
        shouldBypassSystemProxy(target) ? { proxy: 'no-proxy' } : undefined;
      if (!(socketOptions ? await socket.connect(target, socketOptions) : await socket.connect(target))) {
        throw new Error('connect');
      }
      if (generation === this.generation) this.onStatus('已连接，等待画面');
    } catch (_) { if (generation === this.generation) this.fail('预览连接失败，请检查服务和访问权限'); }
  }
  stop(): void {
    this.generation++;
    const socket = this.socket; this.socket = undefined; this.control = undefined;
    this.pending = undefined; this.decoding = false; this.consecutiveOversized = 0;
    if (socket) void socket.close().catch(() => {});
  }
  private fail(message: string): void { this.stop(); this.onFailure(message); }
  private message(data: string): void {
    if (data.length > PREVIEW_MAX_MESSAGE_CHARS) throw new Error('预览控制消息超过限额');
    const value = record(JSON.parse(data)); const type = text(value.type);
    if (type === 'viewport') {
      this.viewportRevision++;
      this.onViewport(previewStreamViewport(value.width, value.height));
    }
    else if (type === 'control') { this.control = previewControl(value); this.onControl(this.control); }
    else if (type === 'fileChooser') this.onStatus('远端要求上传文件；当前请在桌面端处理');
    else if (type === 'download') this.onStatus('远端已产生下载；当前请在桌面端处理');
  }
  private async ack(generation: number): Promise<void> {
    if (generation !== this.generation || !this.socket || !this.alive()) return;
    try { await this.socket.send('{"type":"ack"}'); }
    catch (_) { if (generation === this.generation) this.fail('预览帧确认失败'); }
  }
  private async decode(packet: PreviewFramePacket, generation: number): Promise<void> {
    this.decoding = true;
    let source: image.ImageSource | undefined = undefined;
    let frame: image.PixelMap | undefined = undefined;
    let failure = '预览 JPEG 解码失败';
    try {
      source = image.createImageSource(packet.bytes);
      const info = await source.getImageInfo();
      if (generation !== this.generation || !this.alive()) return;
      if (packet.viewportRevision !== this.viewportRevision) { await this.ack(generation); return; }
      failure = '预览 JPEG 格式无效';
      if (info.mimeType && info.mimeType !== 'image/jpeg') throw new Error(failure);
      failure = '预览 JPEG 原图尺寸信息无效';
      if (previewSourceOversized(info.size)) {
        failure = '预览 JPEG 原图释放失败';
        await source.release();
        source = undefined;
        if (generation !== this.generation || !this.alive()) return;
        if (packet.viewportRevision !== this.viewportRevision) { await this.ack(generation); return; }
        const skipped = ++this.consecutiveOversized;
        if (skipped === 1) this.onFrameSkipped();
        await this.ack(generation);
        if (generation === this.generation && skipped >= PREVIEW_MAX_CONSECUTIVE_OVERSIZE_FRAMES) {
          this.fail('预览 JPEG 原图尺寸连续超限，请缩小远端画面后重新连接');
        }
        return;
      }
      const desiredSize = previewDecodeSize(info.size);
      failure = '预览 JPEG 解码失败';
      frame = await source.createPixelMap({ editable: false, desiredSize });
      if (generation !== this.generation || !this.alive()) return;
      if (packet.viewportRevision !== this.viewportRevision) { await this.ack(generation); return; }
      const output = (await frame.getImageInfo()).size;
      if (generation !== this.generation || !this.alive()) return;
      if (packet.viewportRevision !== this.viewportRevision) { await this.ack(generation); return; }
      failure = '预览 JPEG 输出尺寸超限或比例无效';
      if (!previewOutputSize(output, info.size)) throw new Error(failure);
      this.consecutiveOversized = 0;
      this.onFrame(frame, output); frame = undefined;
      await this.ack(generation);
    } catch (_) {
      if (generation === this.generation && this.alive()) {
        if (packet.viewportRevision !== this.viewportRevision) await this.ack(generation);
        else this.fail(failure);
      }
    } finally {
      if (frame) await frame.release().catch(() => {});
      if (source) await source.release().catch(() => {});
      if (generation === this.generation) {
        this.decoding = false;
        const next = this.pending; this.pending = undefined;
        if (next) void this.decode(next, generation);
      }
    }
  }
  async send(input: Object): Promise<void> {
    if (!this.alive() || !this.socket) { this.stop(); throw new Error('预览连接已失效'); }
    const payload = record(input);
    if (!previewCanSend(this.control, text(payload.type))) throw new Error('请先取得远端控制权');
    const data = JSON.stringify(input);
    if (data.length > 16384) throw new Error('预览输入超过限额');
    const generation = this.generation;
    try {
      if (!await this.socket.send(data)) throw new Error('send');
      if (generation !== this.generation || !this.alive()) throw new Error('changed');
    } catch (_) { this.fail('预览输入结果未知，不会自动重发'); throw new Error('预览输入结果未知，请重新连接后核对'); }
  }
}
