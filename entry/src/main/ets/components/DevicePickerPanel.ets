import { FontSize, LineHeight, Radius, Sizes, Space, Weight } from '../common/Theme';
import { T3Client } from '../services/T3Client';
import { record, objects } from '../protocol/Wire';
import { DevicePreviewChoice, deviceChoices, safeDeviceHubBase } from '../protocol/DevicePreview';
import { AppButton } from './ui/AppButton';
import { StatusBadge } from './ui/StatusBadge';
import { TopBar } from './ui/TopBar';

interface DeviceConfigureInput { enabled: boolean; onboardingCompleted: boolean; }
interface DeviceInspectInput { inspectOnly: boolean; }

@Component
export struct DevicePickerPanel {
  connection: T3Client | undefined = undefined;
  @Prop threadId: string = '';
  onOpen: (device: DevicePreviewChoice, hubBasePath: string, hostKind: string) => Promise<void> = async () => {};
  onBack: () => void = () => {};
  @State devices: DevicePreviewChoice[] = [];
  @State hostNotes: string[] = [];
  @State busy: boolean = false;
  @State error: string = '';
  @State supportDisabled: boolean = false;
  @State openingDevice: boolean = false;
  private hubBasePath: string = '';
  private generation: number = 0;

  aboutToAppear(): void { void this.refresh(); }
  aboutToDisappear(): void { this.generation++; }
  private async refresh(): Promise<void> {
    const connection = this.connection;
    if (!connection || this.busy) return;
    this.busy = true; this.error = ''; this.hubBasePath = ''; this.devices = []; this.hostNotes = [];
    const generation = ++this.generation;
    try {
      const input: DeviceInspectInput = { inspectOnly: false };
      const state = record(await connection.rpcRequest('device.list', input, 30000, false));
      if (generation !== this.generation || connection !== this.connection) return;
      this.supportDisabled = state.hostStatus === 'disabled';
      const hubBasePath = safeDeviceHubBase(state.hubBasePath);
      const hosts = objects(state.hosts).slice();
      if (state.easHosts !== undefined) hosts.push(...objects(state.easHosts));
      if (state.simlockHosts !== undefined) hosts.push(...objects(state.simlockHosts));
      this.devices = deviceChoices(objects(state.devices), hosts);
      const notes: string[] = [];
      for (const value of hosts) {
        const host = record(value);
        const label = typeof host.label === 'string' ? host.label.slice(0, 256) : '未知主机';
        const platforms = host.platforms === undefined ? [] : objects(host.platforms);
        const details: string[] = [];
        for (const entry of platforms) {
          const platform = record(entry);
          if (typeof platform.platform !== 'string') continue;
          const reason = typeof platform.reason === 'string' ? platform.reason.slice(0, 500) : '';
          details.push(platform.platform + (platform.available === true ? ' 主机支持' : ' 主机不可用') + (reason ? '：' + reason : ''));
        }
        notes.push(label + (details.length ? '\n' + details.join('\n') : '：未提供平台状态'));
      }
      this.hostNotes = notes; this.hubBasePath = hubBasePath;
    } catch (reason) { if (generation === this.generation) this.error = (reason as Error).message; }
    finally { if (generation === this.generation) this.busy = false; }
  }
  private async enableSupport(): Promise<void> {
    const owner = this.connection;
    if (!owner || this.busy || owner.canScope('settings:write') === false) return;
    this.busy = true; this.error = '';
    const generation = this.generation;
    try {
      const input: DeviceConfigureInput = { enabled: true, onboardingCompleted: true };
      await owner.rpcRequest('device.configure', input, 60000, false);
      if (generation !== this.generation || owner !== this.connection) return;
      this.supportDisabled = false;
    } catch (_) { if (generation === this.generation) this.error = '启用结果未确认，请刷新核对。不会自动重试。'; }
    finally { if (generation === this.generation) this.busy = false; }
    if (generation === this.generation && !this.error) await this.refresh();
  }
  private async openDevice(device: DevicePreviewChoice): Promise<void> {
    if (this.busy || !device.supported || !this.threadId || !this.connection?.ready) return;
    this.busy = true; this.openingDevice = true; this.error = '';
    const generation = this.generation;
    try { await this.onOpen(device, safeDeviceHubBase(this.hubBasePath), device.hostKind); }
    catch (reason) { if (generation === this.generation) this.error = (reason as Error).message; }
    finally { if (generation === this.generation) { this.busy = false; this.openingDevice = false; } }
  }
  build() {
    Column() {
      TopBar({ title: '选择设备', showBack: true, onBack: () => this.onBack() }) {
        AppButton({ label: '刷新', kind: 'text', compact: true, disabled: this.busy, onTap: () => { void this.refresh(); } })
      }
      Column({ space: Space.sm }) {
        Text('普通 iOS Simulator 支持 MJPEG 操作；Android Emulator 支持原生 H.264 预览，开启控制后可操作。WebRTC 宿主与真机暂不可用。')
          .fontSize(FontSize.callout).lineHeight(LineHeight.callout).fontColor($r('app.color.muted')).width('100%')
        if (this.supportDisabled) {
          Column({ space: Space.sm }) {
            Text('当前环境尚未启用设备支持。').fontSize(FontSize.body).fontColor($r('app.color.ink')).width('100%')
            AppButton({
              label: '启用设备支持',
              kind: 'primary',
              fill: true,
              disabled: this.busy || this.connection?.canScope('settings:write') === false,
              onTap: () => {
                AlertDialog.show({
                  title: '启用设备支持？',
                  message: '将在当前环境启动设备服务，保留现有 Agent 访问设置。',
                  primaryButton: { value: '取消', action: () => {} },
                  secondaryButton: { value: '启用', action: () => { void this.enableSupport(); } }
                });
              }
            })
          }.width('100%').padding(Space.md).backgroundColor($r('app.color.card')).borderRadius(Radius.card)
        }
        if (this.error) {
          Text(this.error).fontSize(FontSize.callout).fontColor($r('app.color.danger')).width('100%')
        }
        if (this.busy) {
          Text(this.openingDevice ? '正在打开设备…' : '正在检查远端主机和设备…')
            .fontSize(FontSize.callout).fontColor($r('app.color.muted')).width('100%')
        }
        Scroll() {
          Column({ space: Space.xs }) {
            ForEach(this.hostNotes, (note: string) => {
              Text(note).fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted')).width('100%')
                .padding(Space.md).backgroundColor($r('app.color.card')).borderRadius(Radius.card)
            }, (note: string) => note)
            if (!this.busy && !this.devices.length && !this.error) {
              Column() {
                Text('未发现设备。请在远端主机准备模拟器，再刷新。')
                  .fontSize(FontSize.body).fontColor($r('app.color.muted')).width('100%')
              }.width('100%').padding(Space.md).backgroundColor($r('app.color.card')).borderRadius(Radius.card)
            }
            ForEach(this.devices, (device: DevicePreviewChoice) => {
              Button({ type: ButtonType.Normal }) {
                Row({ space: Space.sm }) {
                  Column({ space: Space.xxs }) {
                    Row({ space: Space.xs }) {
                      Text(device.name)
                        .fontSize(FontSize.body).lineHeight(LineHeight.body).fontWeight(Weight.medium)
                        .fontColor($r('app.color.ink')).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      StatusBadge({
                        text: device.booted ? '已启动' : '未启动',
                        tone: device.booted ? 'success' : 'neutral'
                      })
                    }.width('100%').alignItems(VerticalAlign.Center)
                    Text(device.hostLabel + ' · ' + device.platform + ' ' + device.version)
                      .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted')).width('100%')
                    if (device.reason) {
                      Text(device.reason)
                        .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted')).width('100%')
                    }
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  if (device.supported) {
                    Image($r('app.media.ui_chevron_right')).width(Sizes.chevron).height(Sizes.chevron).opacity(0.45).accessibilityLevel('no')
                  } else {
                    StatusBadge({ text: '暂不可用', tone: 'neutral' })
                  }
                }.width('100%').padding(Space.md)
              }.width('100%').padding(0).constraintSize({ minHeight: 72 })
                .backgroundColor($r('app.color.card')).borderRadius(Radius.card)
                .enabled(device.supported && !this.busy).onClick(() => { void this.openDevice(device); })
            }, (device: DevicePreviewChoice) => JSON.stringify([device.hostId, device.id]))
          }.width('100%').alignItems(HorizontalAlign.Start)
        }.layoutWeight(1).width('100%').align(Alignment.TopStart)
      }.layoutWeight(1).width('100%').padding({ left: Space.page, right: Space.page, top: Space.xs, bottom: Space.md })
    }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
  }
}
