import { image } from '@kit.ImageKit';
import { DevicePreviewStream } from '../services/DevicePreviewStream';
import { DeviceStreamAccess, DeviceScreen, DevicePoint, devicePoint, deviceTouch, deviceButton,
  deviceKey, deviceNextOrientation } from '../protocol/DevicePreview';

interface DeviceQueuedInput { tag: number; payload: Object; move: boolean; }

@Component
export struct DevicePreviewPanel {
  @StorageLink('t3Foreground') @Watch('foregroundChanged') foreground: boolean = true;
  @Prop deviceName: string = '';
  @Prop hostLabel: string = '';
  @Prop platform: string = 'ios';
  getAccess: () => Promise<DeviceStreamAccess> = async () => { throw new Error('设备媒体访问尚未接入'); };
  prepareConnection: () => void = () => {};
  isCurrent: () => boolean = () => false;
  onBack: () => void = () => {};
  @State frame: image.PixelMap | undefined = undefined;
  @State status: string = '仅普通 iOS Simulator 的 MJPEG 流可用';
  @State error: string = '';
  @State ready: boolean = false;
  @State busy: boolean = false;
  @State count: number = 0;
  private stream: DevicePreviewStream | undefined = undefined;
  private screen: DeviceScreen | undefined = undefined;
  private retired: image.PixelMap | undefined = undefined;
  private generation: number = 0;
  private areaWidth: number = 1;
  private areaHeight: number = 1;
  private rendered: boolean = false;
  private touching: boolean = false;
  private lastPoint: DevicePoint = { x: 0, y: 0 };
  private queue: DeviceQueuedInput[] = [];
  private sending: boolean = false;

  private foregroundChanged(): void {
    if (this.foreground) return;
    this.disconnect();
    this.status = '应用进入后台，画面已断开；返回后请手动连接';
  }
  aboutToDisappear(): void { this.disconnect(); }
  private disconnect(): void {
    this.generation++; this.busy = false;
    this.stream?.stop(); this.stream = undefined;
    this.ready = false; this.touching = false; this.rendered = false;
    this.queue = []; this.sending = false;
    if (this.frame) void this.frame.release().catch(() => {});
    if (this.retired) void this.retired.release().catch(() => {});
    this.frame = undefined; this.retired = undefined;
  }
  private async connect(): Promise<void> {
    if (this.busy || !this.foreground) return;
    if (this.platform !== 'ios') { this.error = 'Android 设备需要 H.264/WebRTC，当前版本尚未接入'; return; }
    this.disconnect(); this.busy = true; this.error = ''; this.count = 0;
    const generation = this.generation;
    try {
      this.prepareConnection();
      if (!this.isCurrent()) throw new Error('环境或设备已改变');
      const access = await this.getAccess();
      if (generation !== this.generation || !this.foreground || !this.isCurrent()) return;
      const stream = new DevicePreviewStream((): boolean => generation === this.generation && this.foreground && this.isCurrent());
      this.stream = stream;
      stream.onFrame = (frame: image.PixelMap): void => {
        if (generation !== this.generation || !this.foreground) { void frame.release(); return; }
        if (this.retired) void this.retired.release().catch(() => {});
        this.retired = this.frame; this.frame = frame; this.rendered = true; this.count++;
        this.status = this.ready ? '实时画面 · 可操作' : '实时画面 · 等待输入准入';
      };
      stream.onScreen = (screen: DeviceScreen): void => {
        if (generation !== this.generation) return;
        if (this.touching) this.enqueue(3, deviceTouch('end', this.lastPoint));
        this.touching = false; this.rendered = false; this.screen = screen;
      };
      stream.onInput = (ready: boolean): void => { if (generation !== this.generation) return; this.ready = ready; if (!ready) { this.queue = []; this.touching = false; } };
      stream.onFailure = (message: string): void => { if (generation !== this.generation) return; this.ready = false; this.error = message; this.status = '设备画面已停止'; this.queue = []; };
      this.status = '正在连接设备画面…'; await stream.start(access);
    } catch (reason) { this.error = (reason as Error).message; }
    finally { if (generation === this.generation) this.busy = false; }
  }
  private enqueue(tag: number, payload: Object, move: boolean = false): void {
    if (!this.ready || !this.stream || !this.isCurrent()) return;
    const packet: DeviceQueuedInput = { tag, payload, move };
    if (move && this.queue.length && this.queue[this.queue.length - 1].move) this.queue[this.queue.length - 1] = packet;
    else this.queue.push(packet);
    if (this.queue.length > 32) { this.disconnect(); this.error = '设备输入队列超限，请重连后核对'; return; }
    if (!this.sending) void this.flush();
  }
  private async flush(): Promise<void> {
    const generation = this.generation; const stream = this.stream;
    if (!stream) return;
    this.sending = true;
    try {
      while (this.queue.length && generation === this.generation && this.foreground && this.isCurrent()) {
        const input = this.queue.shift(); if (input) await stream.send(input.tag, input.payload);
      }
    } catch (reason) {
      if (generation === this.generation) { this.queue = []; this.ready = false; this.error = (reason as Error).message; }
    } finally { if (generation === this.generation) this.sending = false; }
  }
  private touch(event: TouchEvent): void {
    if (!this.ready || !this.rendered || !this.screen) return;
    if (event.type === TouchType.Down && event.touches.length === 1 && !this.touching) {
      const point = devicePoint(event.touches[0].x, event.touches[0].y, this.areaWidth, this.areaHeight, this.screen);
      if (!point) return;
      this.touching = true; this.lastPoint = point; this.enqueue(3, deviceTouch('begin', point)); return;
    }
    if (!this.touching) return;
    const ending = event.type === TouchType.Up || event.type === TouchType.Cancel || event.touches.length > 1;
    const touch = event.changedTouches.length ? event.changedTouches[0] : undefined;
    const point = touch ? devicePoint(touch.x, touch.y, this.areaWidth, this.areaHeight, this.screen) : undefined;
    if (point) this.lastPoint = point;
    this.enqueue(3, deviceTouch(ending ? 'end' : 'move', this.lastPoint), !ending);
    if (ending) this.touching = false;
  }
  private sendKey(usage: number): void { this.enqueue(6, deviceKey(usage, true)); this.enqueue(6, deviceKey(usage, false)); }
  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Button('返回', { type: ButtonType.Normal }).height(44).backgroundColor(Color.Transparent)
          .fontColor($r('app.color.ink')).onClick(() => this.onBack())
        Column({ space: 2 }) {
          Text(this.deviceName || '设备预览').fontSize(18).fontColor($r('app.color.ink')).maxLines(1)
          Text(this.hostLabel).fontSize(12).fontColor($r('app.color.muted')).maxLines(1)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button('连接').height(44).backgroundColor($r('app.color.primary')).fontColor($r('app.color.on_primary'))
          .enabled(this.foreground && !this.busy && this.platform === 'ios').onClick(() => { void this.connect(); })
      }.width('100%')
      Text(this.status + (this.count ? ' · ' + this.count + ' 帧' : '')).fontSize(12).fontColor($r('app.color.muted'))
      if (this.error) Text(this.error).fontSize(13).fontColor($r('app.color.danger'))
      Stack() {
        if (this.frame) Image(this.frame).width('100%').height('100%').objectFit(ImageFit.Contain)
        else Text('连接后显示远端设备的连续画面\nAndroid / WebRTC 设备尚未支持')
          .fontSize(14).fontColor($r('app.color.muted')).textAlign(TextAlign.Center).padding(24)
      }.width('100%').layoutWeight(1).backgroundColor($r('app.color.surface')).borderRadius(12)
        .onAreaChange((_, area: Area) => { this.areaWidth = Number(area.width); this.areaHeight = Number(area.height); })
        .onTouch((event: TouchEvent) => this.touch(event))
      Row({ space: 8 }) {
        Button('主屏幕').height(44).layoutWeight(1).backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink'))
          .onClick(() => this.enqueue(4, deviceButton('home')))
        Button('切换应用').height(44).layoutWeight(1).backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink'))
          .onClick(() => this.enqueue(4, deviceButton('app_switcher')))
        Button('旋转').height(44).layoutWeight(1).backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink'))
          .onClick(() => { if (this.screen) this.enqueue(7, deviceNextOrientation(this.screen)); })
      }.width('100%').enabled(this.ready && !this.busy && !this.touching)
      Row({ space: 8 }) {
        Button('Esc').height(44).layoutWeight(1).backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink'))
          .onClick(() => this.sendKey(41))
        Button('Tab').height(44).layoutWeight(1).backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink'))
          .onClick(() => this.sendKey(43))
        Button('删除').height(44).layoutWeight(1).backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink'))
          .onClick(() => this.sendKey(42))
        Button('回车').height(44).layoutWeight(1).backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink'))
          .onClick(() => this.sendKey(40))
      }.width('100%').enabled(this.ready && !this.busy && !this.touching)
    }.padding(16).width('100%').height('100%').backgroundColor($r('app.color.canvas'))
  }
}
