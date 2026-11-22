import { http, webSocket } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { record } from '../protocol/Wire';
import { shouldBypassSystemProxy } from '../protocol/Hosts';
import { DeviceStreamAccess, DeviceScreen, DeviceMjpegParser, deviceScreen, deviceRotation } from '../protocol/DevicePreview';

export class DevicePreviewStream {
  onFrame: (frame: image.PixelMap) => void = () => {};
  onScreen: (screen: DeviceScreen) => void = () => {};
  onInput: (ready: boolean) => void = () => {};
  onFailure: (message: string) => void = () => {};
  private request: http.HttpRequest | undefined = undefined;
  private socket: webSocket.WebSocket | undefined = undefined;
  private parser: DeviceMjpegParser | undefined = undefined;
  private screen: DeviceScreen | undefined = undefined;
  private admitted: boolean = false;
  private generation: number = 0;
  private screenGeneration: number = 0;
  private decoding: boolean = false;
  private pending: ArrayBuffer | undefined = undefined;
  private timer: number = -1;
  private alive: () => boolean;
  constructor(alive: () => boolean) { this.alive = alive; }
  async start(access: DeviceStreamAccess): Promise<void> {
    this.stop();
    if (!this.alive() || !/^https?:\/\/[^\s]+$/.test(access.mjpegUrl) || !/^wss?:\/\/[^\s]+$/.test(access.inputUrl)) {
      throw new Error('设备流访问已失效');
    }
    const generation = this.generation;
    const request = http.createHttp(); this.request = request;
    const socket = webSocket.createWebSocket(); this.socket = socket;
    this.timer = setTimeout(() => { if (generation === this.generation) this.fail('设备未返回视频，请检查 MJPEG 支持及宿主状态'); }, 15000);
    request.on('headersReceive', (headers: Object): void => {
      if (!this.current(generation)) return;
      try {
        const values = record(headers); let contentType = '';
        for (const key of Object.keys(values)) if (key.toLowerCase() === 'content-type' && typeof values[key] === 'string') contentType = values[key] as string;
        this.parser = new DeviceMjpegParser(contentType);
      } catch (_) { this.fail('此设备未提供 MJPEG；可能仅支持 H.264/WebRTC 或访问票据已失效'); }
    });
    request.on('dataReceive', (data: ArrayBuffer): void => {
      if (!this.current(generation)) return;
      try {
        if (!this.parser) throw new Error('设备流缺少类型信息');
        const frames = this.parser.push(data);
        for (const frame of frames) {
          if (this.decoding) this.pending = frame;
          else void this.decode(frame, generation);
        }
      } catch (reason) { this.fail((reason as Error).message); }
    });
    request.on('dataEnd', (): void => { if (this.current(generation)) this.fail('设备画面已断开，请重新连接'); });
    socket.on('message', (error, data: string | ArrayBuffer): void => {
      if (!this.current(generation)) return;
      if (error && error.code !== 0) { this.fail('设备控制消息失败'); return; }
      if (typeof data === 'string') return;
      try {
        const bytes = new Uint8Array(data);
        if (!bytes.length || bytes.length > 65536) throw new Error('设备控制包无效');
        if (bytes[0] === 0x83) { this.admitted = true; this.onInput(!!this.screen && !this.screen.inputUnavailable); }
        else if (bytes[0] === 0x82) {
          this.screen = deviceScreen(record(JSON.parse(new util.TextDecoder().decodeToString(bytes.slice(1)))));
          this.screenGeneration++; this.onScreen(this.screen); this.onInput(this.admitted && !this.screen.inputUnavailable);
        }
      } catch (_) { this.fail('设备屏幕配置无效'); }
    });
    socket.on('error', (): void => { if (generation === this.generation) this.fail('设备控制连接失败，请重新取得访问票据'); });
    socket.on('close', (): void => { if (generation === this.generation) this.fail('设备控制已断开；不会重发触控或按键'); });
    const streamOptions: http.HttpRequestOptions = { method: http.RequestMethod.GET, usingCache: false,
      maxRedirects: 0, connectTimeout: 10000, readTimeout: 60000 };
    if (shouldBypassSystemProxy(access.mjpegUrl)) streamOptions.usingProxy = false;
    void request.requestInStream(access.mjpegUrl, streamOptions).then((status: number): void => {
      if (generation === this.generation && status !== 200) this.fail(status === 401 || status === 403 ?
        '设备访问票据失效，请重新连接' : status === 409 ? '设备仅支持 WebRTC，当前 MJPEG 路径不可用' : '设备画面请求失败');
    }).catch(() => { if (generation === this.generation) this.fail('设备画面接收失败，请重新连接'); });
    try {
      const socketOptions: webSocket.WebSocketRequestOptions | undefined =
        shouldBypassSystemProxy(access.inputUrl) ? { proxy: 'no-proxy' } : undefined;
      if (!(socketOptions ? await socket.connect(access.inputUrl, socketOptions) : await socket.connect(access.inputUrl))) {
        throw new Error('connect');
      }
    }
    catch (_) { if (generation === this.generation) this.fail('设备控制连接失败'); }
  }
  private current(generation: number): boolean {
    if (generation !== this.generation) return false;
    if (!this.alive()) { this.fail('环境或设备已改变，请重新打开'); return false; }
    return true;
  }
  stop(): void {
    this.generation++; this.screenGeneration++;
    if (this.timer >= 0) clearTimeout(this.timer); this.timer = -1;
    this.request?.destroy(); this.request = undefined;
    const socket = this.socket; this.socket = undefined;
    if (socket) void socket.close().catch(() => {});
    this.parser = undefined; this.screen = undefined; this.admitted = false;
    this.pending = undefined; this.decoding = false;
  }
  private fail(message: string): void { this.stop(); this.onInput(false); this.onFailure(message); }
  private async decode(data: ArrayBuffer, generation: number): Promise<void> {
    this.decoding = true;
    const screenGeneration = this.screenGeneration;
    const angle = this.screen ? deviceRotation(this.screen) : 0;
    let source: image.ImageSource | undefined = undefined;
    let frame: image.PixelMap | undefined = undefined;
    try {
      source = image.createImageSource(data);
      const info = await source.getImageInfo();
      if (info.size.width < 1 || info.size.height < 1 || info.size.width > 4096 || info.size.height > 4096 ||
        info.size.width * info.size.height > 10000000) throw new Error('size');
      const scale = Math.min(1, 1920 / Math.max(info.size.width, info.size.height));
      frame = await source.createPixelMap({ editable: true,
        desiredSize: { width: Math.max(1, Math.floor(info.size.width * scale)), height: Math.max(1, Math.floor(info.size.height * scale)) } });
      if (angle) await frame.rotate(angle);
      if (!this.current(generation) || screenGeneration !== this.screenGeneration) { await frame.release(); return; }
      if (this.timer >= 0) clearTimeout(this.timer); this.timer = -1;
      this.onFrame(frame); frame = undefined;
    } catch (_) {
      if (frame) await frame.release().catch(() => {});
      if (generation === this.generation) this.fail('设备 JPEG 解码失败或超过尺寸限制');
    } finally {
      if (source) await source.release().catch(() => {});
      if (generation === this.generation) {
        this.decoding = false; const next = this.pending; this.pending = undefined;
        if (next) void this.decode(next, generation);
      }
    }
  }
  async send(tag: number, payload: Object): Promise<void> {
    if (!this.current(this.generation) || !this.socket || !this.admitted || !this.screen || this.screen.inputUnavailable) {
      throw new Error('设备尚未准入输入');
    }
    if (![3, 4, 6, 7].includes(tag)) throw new Error('设备输入类型无效');
    const json = new util.TextEncoder().encodeInto(JSON.stringify(payload));
    if (json.length > 2048) throw new Error('设备输入超过限额');
    const packet = new Uint8Array(json.length + 1); packet[0] = tag; packet.set(json, 1);
    const generation = this.generation;
    try {
      if (!await this.socket.send(packet.buffer)) throw new Error('send');
      if (!this.current(generation)) throw new Error('changed');
    } catch (_) {
      if (generation === this.generation) this.fail('设备输入结果未知，不会自动重发');
      throw new Error('设备输入结果未知，请核对设备');
    }
  }
}
