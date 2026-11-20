import { FontSize, Radius, Space } from '../common/Theme';
import { AndroidDeviceStream } from '../services/AndroidDeviceStream';
import { AndroidVideoSize, AndroidControlPoint, androidControlPoint, androidTouch, androidButton, androidKey, androidTextInputs } from '../protocol/AndroidVideo';
import { DecoderStats } from 'libt3device.so';
import { AppButton } from './ui/AppButton';
import { TopBar } from './ui/TopBar';

@Component
export struct AndroidDevicePanel {
  @StorageLink('t3Foreground') @Watch('foregroundChanged') foreground: boolean = true;
  @Prop deviceName: string = '';
  @Prop hostLabel: string = '';
  getStreamUrl: () => Promise<string> = async () => { throw new Error('设备媒体票据尚未接入'); };
  prepareConnection: () => void = () => {};
  isCurrent: () => boolean = () => false;
  canOperate: () => boolean = () => false;
  setOrientation: (value: string) => Promise<void> = async () => { throw new Error('设备旋转尚未接入'); };
  onBack: () => void = () => {};
  @State status: string = '原生 H.264 视频 · 连接后可开启控制';
  @State error: string = '';
  @State busy: boolean = false;
  @State surfaceReady: boolean = false;
  @State frameCount: number = 0;
  @State dropped: number = 0;
  @State inputReady: boolean = false;
  @State controlling: boolean = false;
  @State controlBusy: boolean = false;
  @State input: string = '';
  private touching: boolean = false;
  private touchWidth: number = 1;
  private touchHeight: number = 1;
  private touchPoint: AndroidControlPoint = { x: 0, y: 0 };
  @State videoWidth: number = 9;
  @State videoHeight: number = 16;
  @State availableWidth: number = 1;
  @State availableHeight: number = 1;
  private surface: XComponentController = new XComponentController();
  private stream: AndroidDeviceStream | undefined = undefined;
  private generation: number = 0;
  private foregroundChanged(): void {
    if (this.foreground) return;
    this.disconnect();
    this.status = '应用进入后台，画面已断开；返回后请手动连接';
  }
  aboutToDisappear(): void { this.disconnect(); }
  private disconnect(): void { this.generation++; this.stream?.stop(); this.stream = undefined; this.busy = false; this.inputReady = false; this.controlling = false; this.touching = false; this.controlBusy = false; this.input = ''; }
  private async connect(): Promise<void> {
    if (!this.surfaceReady || this.busy || !this.foreground) return;
    this.disconnect(); this.busy = true; this.error = ''; this.frameCount = 0; this.dropped = 0;
    const generation = this.generation;
    try {
      this.prepareConnection();
      if (!this.isCurrent()) throw new Error('当前环境或设备已改变');
      const url = await this.getStreamUrl();
      if (generation !== this.generation || !this.foreground || !this.isCurrent()) return;
      const stream = new AndroidDeviceStream((): boolean => generation === this.generation && this.foreground && this.isCurrent(), (): boolean => this.canOperate());
      this.stream = stream;
      stream.onInputReady = (ready: boolean): void => {
        if (generation !== this.generation) return;
        this.inputReady = ready;
        if (!ready) { this.controlling = false; this.touching = false; }
      };
      stream.onVideoReset = (): void => {
        if (generation !== this.generation) return;
        this.inputReady = false; this.controlling = false; this.touching = false;
      };
      stream.onSize = (size: AndroidVideoSize): void => { if (generation !== this.generation) return; this.videoWidth = size.width; this.videoHeight = size.height; };
      stream.onStats = (stats: DecoderStats): void => {
        if (generation !== this.generation) return;
        this.frameCount = stats.rendered; this.dropped = stats.dropped;
        if (stats.rendered) this.status = this.controlling ? '原生 H.264 实时画面 · 控制已开启' : '原生 H.264 实时画面 · 观看中';
        if (stats.width > 0 && stats.height > 0) { this.videoWidth = stats.width; this.videoHeight = stats.height; }
      };
      stream.onStatus = (status: string): void => { if (generation !== this.generation) return; this.status = status; };
      stream.onFailure = (message: string): void => { if (generation !== this.generation) return; this.error = message; this.status = '设备视频已停止'; };
      await stream.start(url, this.surface.getXComponentSurfaceId());
    } catch (reason) { this.error = (reason as Error).message; }
    finally { if (generation === this.generation) this.busy = false; }
  }
  private async toggleControl(): Promise<void> {
    if (!this.stream || !this.inputReady || this.controlBusy || !this.canOperate()) return;
    const generation = this.generation;
    this.controlBusy = true;
    try {
      if (this.controlling) { await this.stream.releaseTouch(); this.touching = false; }
      if (generation === this.generation && this.inputReady) this.controlling = !this.controlling;
    } catch (reason) { if (generation === this.generation) this.error = (reason as Error).message; }
    finally { if (generation === this.generation) this.controlBusy = false; }
  }
  private touch(event: TouchEvent): void {
    if (!this.controlling || !this.inputReady || !this.foreground || this.controlBusy || !this.stream) return;
    const size: AndroidVideoSize = { width: this.videoWidth, height: this.videoHeight };
    let action = '';
    if (event.type === TouchType.Down && event.touches.length === 1 && !this.touching) {
      const point = androidControlPoint(event.touches[0].x, event.touches[0].y, this.touchWidth, this.touchHeight, size);
      if (!point) return;
      this.touchPoint = point; this.touching = true; action = 'down';
    } else if (this.touching) {
      const ending = event.type === TouchType.Up || event.type === TouchType.Cancel || event.touches.length > 1;
      const current = event.changedTouches.length ? event.changedTouches[0] : undefined;
      if (current) {
        const point = androidControlPoint(current.x, current.y, this.touchWidth, this.touchHeight, size, true);
        if (point) this.touchPoint = point;
      }
      action = ending ? 'up' : 'move'; if (ending) this.touching = false;
    }
    if (!action) return;
    const generation = this.generation;
    void this.stream.sendInput(androidTouch(action, this.touchPoint)).catch((reason: Error) => {
      if (generation === this.generation && this.inputReady) this.error = reason.message;
    });
  }
  private async press(button: string): Promise<void> {
    const stream = this.stream;
    if (!stream || !this.controlling || !this.inputReady || this.controlBusy) return;
    const generation = this.generation; this.controlBusy = true; this.error = '';
    try {
      await stream.releaseTouch(); this.touching = false;
      await stream.sendInput(button === 'enter' ? androidKey(66) : androidButton(button));
    } catch (reason) { if (generation === this.generation) this.error = (reason as Error).message; }
    finally { if (generation === this.generation) this.controlBusy = false; }
  }
  private async sendText(): Promise<void> {
    const stream = this.stream;
    if (!stream || !this.controlling || !this.inputReady || this.controlBusy || !this.input) return;
    const generation = this.generation;
    try {
      const chunks = androidTextInputs(this.input);
      this.controlBusy = true; this.error = ''; this.input = '';
      for (const chunk of chunks) {
        if (generation !== this.generation || !this.foreground) return;
        await stream.sendInput(chunk);
      }
    } catch (reason) { if (generation === this.generation) this.error = (reason as Error).message + '；已发送部分不会自动补发'; }
    finally { if (generation === this.generation) this.controlBusy = false; }
  }
  private async rotateDevice(): Promise<void> {
    const stream = this.stream;
    if (!stream || !this.controlling || !this.inputReady || this.controlBusy || !this.canOperate()) return;
    const generation = this.generation; this.controlBusy = true; this.error = '';
    try {
      await stream.releaseTouch(); this.touching = false; this.controlling = false;
      if (generation !== this.generation || !this.foreground || !this.isCurrent()) return;
      await this.setOrientation(this.videoWidth > this.videoHeight ? 'portrait' : 'landscape_left');
      if (generation === this.generation) this.status = '旋转请求已提交，请确认新画面后重新开启控制';
    } catch (reason) { if (generation === this.generation) this.error = (reason as Error).message + '；旋转结果请核对，不自动重试'; }
    finally { if (generation === this.generation) this.controlBusy = false; }
  }
  private surfaceWidth(): number { return Math.max(1, Math.min(this.availableWidth, this.availableHeight * this.videoWidth / this.videoHeight)); }
  private surfaceHeight(): number { return Math.max(1, Math.min(this.availableHeight, this.availableWidth * this.videoHeight / this.videoWidth)); }
  build() {
    Column() {
      TopBar({
        title: this.deviceName || 'Android 设备',
        subtitle: this.hostLabel,
        showBack: true,
        onBack: () => this.onBack()
      }) {
        AppButton({
          label: '连接',
          kind: 'primary',
          compact: true,
          disabled: !(this.foreground && this.surfaceReady && !this.busy),
          onTap: () => { void this.connect(); }
        })
      }
      Column({ space: Space.xs }) {
        Text(this.status).fontSize(FontSize.callout).fontColor($r('app.color.ink')).width('100%')
        Text('当前已验证竖屏控制；画面侧倒时请先在主机恢复竖屏。')
          .fontSize(FontSize.caption).fontColor($r('app.color.muted')).width('100%')
        if (this.error) {
          Text(this.error).fontSize(FontSize.callout).fontColor($r('app.color.danger')).width('100%')
        }
        Stack() {
          XComponent({ id: 'androidDeviceSurface', type: XComponentType.SURFACE, controller: this.surface })
            .width(this.surfaceWidth()).height(this.surfaceHeight())
            .onLoad(() => { this.surfaceReady = true; })
            .onDestroy(() => { this.surfaceReady = false; this.disconnect(); })
          Column().width('100%').height('100%').backgroundColor(Color.Transparent).hitTestBehavior(HitTestMode.Block)
            .onAreaChange((_, area: Area) => { this.touchWidth = Number(area.width); this.touchHeight = Number(area.height); })
            .onTouch((event: TouchEvent) => this.touch(event))
        }.width('100%').layoutWeight(1).backgroundColor('#101114').borderRadius(Radius.card).clip(true)
          .onAreaChange((_, area: Area) => { this.availableWidth = Number(area.width); this.availableHeight = Number(area.height); })
        Text('已渲染 ' + this.frameCount + ' 帧 · 丢弃 ' + this.dropped + ' 帧')
          .fontSize(FontSize.caption).fontColor($r('app.color.muted'))
        Row({ space: Space.xs }) {
          Button(this.controlling ? '停止控制' : '开启控制')
            .height(42).fontSize(FontSize.callout).borderRadius(Radius.button).layoutWeight(1)
            .backgroundColor(this.controlling ? $r('app.color.info_bg') : $r('app.color.card'))
            .fontColor(this.controlling ? $r('app.color.primary_text') : $r('app.color.ink'))
            .enabled(this.inputReady && !this.controlBusy).onClick(() => { void this.toggleControl(); })
          Button('返回键').height(42).fontSize(FontSize.callout).borderRadius(Radius.button).layoutWeight(1)
            .backgroundColor($r('app.color.card')).fontColor($r('app.color.ink'))
            .enabled(this.controlling && !this.controlBusy).onClick(() => { void this.press('back'); })
          Button('主屏幕').height(42).fontSize(FontSize.callout).borderRadius(Radius.button).layoutWeight(1)
            .backgroundColor($r('app.color.card')).fontColor($r('app.color.ink'))
            .enabled(this.controlling && !this.controlBusy).onClick(() => { void this.press('home'); })
        }.width('100%')
        Row({ space: Space.xs }) {
          Button('最近任务').height(42).fontSize(FontSize.callout).borderRadius(Radius.button).layoutWeight(1)
            .backgroundColor($r('app.color.card')).fontColor($r('app.color.ink'))
            .onClick(() => { void this.press('recents'); })
          Button('横竖屏').height(42).fontSize(FontSize.callout).borderRadius(Radius.button).layoutWeight(1)
            .backgroundColor($r('app.color.card')).fontColor($r('app.color.ink'))
            .onClick(() => { void this.rotateDevice(); })
        }.width('100%').enabled(this.controlling && !this.controlBusy && this.inputReady)
        Row({ space: Space.xs }) {
          TextInput({ placeholder: '点选远端输入框后输入文字', text: this.input })
            .layoutWeight(1).height(42).maxLength(4096)
            .fontSize(FontSize.body).fontColor($r('app.color.ink')).placeholderColor($r('app.color.placeholder'))
            .backgroundColor($r('app.color.card')).borderRadius(Radius.button).padding({ left: Space.sm, right: Space.sm })
            .onChange((value: string) => { this.input = value; })
          AppButton({
            label: '输入',
            kind: 'primary',
            compact: true,
            onTap: () => { void this.sendText(); }
          })
          AppButton({
            label: '↵',
            kind: 'secondary',
            compact: true,
            onTap: () => { void this.press('enter'); }
          })
        }.width('100%').alignItems(VerticalAlign.Center).enabled(this.controlling && !this.controlBusy && this.inputReady)
      }.layoutWeight(1).width('100%').padding({ left: Space.page, right: Space.page, top: Space.xxs, bottom: Space.md })
    }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
  }
}
