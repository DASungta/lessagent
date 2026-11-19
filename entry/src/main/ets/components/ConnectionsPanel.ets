import { LinkedEnvironmentsSection, LinkedEnvironmentGroup } from './LinkedEnvironmentsSection';
import { PullRequestRoutingSettings } from './PullRequestRoutingSettings';
import { DirectRoute, EnvironmentEntry, environmentRouteKey, environmentRoutes } from '../protocol/Environment';
import { ConnectDevicesSection } from './ConnectDevicesSection';
import { CloudDevice, CloudPairingLink } from '../protocol/Cloud';

@Component
export struct ConnectionsPanel {
  @Prop entries: EnvironmentEntry[] = [];
  @Prop statuses: Record<string, string> = {};
  @Prop linkedGroups: LinkedEnvironmentGroup[] = [];
  @Prop initialized: boolean = false;
  @Prop cloudConfigured: boolean = false;
  @Prop cloudSignedIn: boolean = false;
  @Prop cloudStatus: string = '';
  @Prop deviceEnvironmentLabel: string = '';
  @Prop pendingDevices: CloudPairingLink[] = [];
  @Prop approvedDevices: CloudDevice[] = [];
  @State expanded: string = '';
  @State label: string = '';
  @State address: string = '';
  @State busy: boolean = false;
  @State error: string = '';
  onClose: () => void = () => {};
  onAdd: () => void = () => {};
  onAddRoute: (id: string) => void = () => {};
  onInitialize: () => Promise<void> = async () => {};
  onRetry: (id: string) => Promise<void> = async () => {};
  onEnabled: (id: string, enabled: boolean) => Promise<void> = async () => {};
  onEdit: (id: string, label: string, address: string) => Promise<void> = async () => {};
  onRouting: (localId: string, permission: string) => Promise<void> = async () => {};
  onRemove: (id: string) => Promise<void> = async () => {};
  onReorderRoutes: (id: string, references: string[]) => Promise<void> = async () => {};
  onRemoveRoute: (id: string, reference: string) => Promise<void> = async () => {};
  onCloudAccount: () => void = () => {};
  onLinkCloud: (id: string) => Promise<void> = async () => {};
  onApproveDevice: (id: string) => Promise<void> = async () => {};
  onDenyDevice: (id: string) => Promise<void> = async () => {};
  onRevokeDevice: (id: string) => Promise<void> = async () => {};
  private async perform(action: () => Promise<void>): Promise<void> {
    if (this.busy) return;
    this.busy = true; this.error = '';
    try { await action(); } catch (error) { this.error = (error as Error).message; }
    finally { this.busy = false; }
  }
  private expand(entry: EnvironmentEntry): void {
    this.expanded = this.expanded === entry.localId ? '' : entry.localId;
    this.label = entry.label; this.address = entry.base; this.error = '';
  }
  build() {
    Column({ space: 16 }) {
      Row({ space: 8 }) {
        Button('×').width(44).height(44).backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
          .accessibilityText('关闭环境').onClick(this.onClose)
        Text('环境').fontSize(20).fontWeight(FontWeight.Medium)
        Blank()
        Button('+').fontSize(24).backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
          .width(44).height(44).accessibilityText('添加环境').enabled(this.initialized && !this.busy).onClick(this.onAdd)
      }.width('100%')
      if (this.cloudConfigured) {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 8 }) {
            Column({ space: 3 }) {
              Text('T3 Connect').fontSize(15).fontWeight(FontWeight.Medium).width('100%')
              Text(this.cloudSignedIn ? (this.cloudStatus || '已登录') : '登录以使用托管中继')
                .fontSize(12).fontColor($r('app.color.muted')).width('100%')
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Text('›').fontSize(18).fontColor($r('app.color.muted'))
          }.width('100%')
        }.width('100%').backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).borderRadius(12)
          .padding(14).enabled(!this.busy).onClick(this.onCloudAccount)
      }
      Scroll() {
        Column({ space: 16 }) {
      if (!this.initialized) {
        Text('连接记录未加载，请解锁后重试。').fontSize(14).fontColor($r('app.color.muted')).width('100%')
        Button('重试加载').enabled(!this.busy).onClick(() => this.perform(this.onInitialize))
      } else if (!this.entries.length) {
        Column({ space: 12 }) {
          Column() {
            Image($r('app.media.ui_globe')).width(24).height(24)
          }.width(48).height(48).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
            .backgroundColor($r('app.color.canvas')).borderRadius(24)
          Text('还没有连接环境\n点 + 添加一个').fontSize(14).lineHeight(20)
            .fontColor($r('app.color.muted')).textAlign(TextAlign.Center)
        }.width('100%').padding({ top: 32, bottom: 32, left: 24, right: 24 })
          .backgroundColor($r('app.color.surface')).borderRadius(20)
      }
      ForEach(this.entries.filter((e: EnvironmentEntry) => !e.deleting), (entry: EnvironmentEntry) => {
        Column({ space: 12 }) {
          Row({ space: 8 }) {
            Button({ type: ButtonType.Normal }) {
              Column({ space: 4 }) {
                Text(entry.label).fontSize(16).fontWeight(FontWeight.Medium).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                Text(entry.base).fontSize(12).fontColor($r('app.color.muted')).width('100%')
                if (entry.kind === 'cloud') { Text('T3 Connect · 中继托管').fontSize(12).fontColor($r('app.color.muted')).width('100%') }
                Text(entry.enabled ? (this.statuses[entry.localId] || '未连接') : '已停用')
                  .fontSize(12).fontColor($r('app.color.muted')).width('100%')
              }.alignItems(HorizontalAlign.Start)
            }.layoutWeight(1).backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
              .padding(0).enabled(!this.busy).accessibilityText('管理 ' + entry.label).onClick(() => this.expand(entry))
            Toggle({ type: ToggleType.Switch, isOn: entry.enabled }).enabled(!this.busy)
              .accessibilityText('启用 ' + entry.label).onChange((enabled: boolean) => { if (enabled !== entry.enabled) void this.perform(() => this.onEnabled(entry.localId, enabled)); })
            Button(this.expanded === entry.localId ? '⌃' : '⌄').width(44).height(44).backgroundColor(Color.Transparent)
              .fontColor($r('app.color.ink')).enabled(!this.busy).accessibilityText('展开环境详情').onClick(() => this.expand(entry))
          }.width('100%')
          if (this.expanded === entry.localId) {
            if (entry.kind === 'cloud') {
              Text('此地址由 T3 Connect 管理；凭据按账号与设备隔离，不在目录中保存。')
                .fontSize(13).fontColor($r('app.color.muted')).width('100%')
              Button('打开 T3 Connect').enabled(!this.busy).onClick(this.onCloudAccount)
            } else {
              Text('连接路径').fontSize(13).fontColor($r('app.color.muted')).width('100%')
              ForEach(environmentRoutes(entry), (route: DirectRoute, index: number) => {
              Column({ space: 6 }) {
                Row({ space: 8 }) {
                  Column({ space: 2 }) {
                    Text(route.base).fontSize(14).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                    Text(index === 0 ? '优先连接' : '备用路径').fontSize(12).fontColor($r('app.color.muted'))
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  Button('↑').backgroundColor(Color.Transparent).fontColor($r('app.color.ink')).borderRadius(10).fontSize(14)
                    .constraintSize({ minHeight: 40 }).enabled(!this.busy && index > 0).accessibilityText('上移连接路径')
                    .onClick(() => this.perform(async () => {
                      const refs = environmentRoutes(entry).map((item: DirectRoute) => item.credentialRef);
                      const previous = refs[index - 1]; refs[index - 1] = refs[index]; refs[index] = previous;
                      await this.onReorderRoutes(entry.localId, refs);
                    }))
                  Button('↓').backgroundColor(Color.Transparent).fontColor($r('app.color.ink')).borderRadius(10).fontSize(14)
                    .constraintSize({ minHeight: 40 }).enabled(!this.busy && index < environmentRoutes(entry).length - 1).accessibilityText('下移连接路径')
                    .onClick(() => this.perform(async () => {
                      const refs = environmentRoutes(entry).map((item: DirectRoute) => item.credentialRef);
                      const next = refs[index + 1]; refs[index + 1] = refs[index]; refs[index] = next;
                      await this.onReorderRoutes(entry.localId, refs);
                    }))
                  if (environmentRoutes(entry).length > 1) {
                    Button('移除路径').backgroundColor(Color.Transparent).fontColor($r('app.color.danger')).borderRadius(10).fontSize(12)
                      .constraintSize({ minHeight: 40 }).enabled(!this.busy)
                      .onClick(() => { AlertDialog.show({ title: '移除连接路径？', message: '此地址的本机凭据将被删除，其他可用路径保持不变。',
                        primaryButton: { value: '取消', action: () => {} },
                        secondaryButton: { value: '移除', action: () => { void this.perform(() => this.onRemoveRoute(entry.localId, route.credentialRef)); } } }); })
                  }
                }.width('100%')
              }.width('100%').padding(10).backgroundColor($r('app.color.canvas')).borderRadius(8)
              }, (route: DirectRoute) => route.credentialRef)
              Button('添加路径').enabled(!this.busy && entry.enabled).onClick(() => this.onAddRoute(entry.localId))
              Text('名称').fontSize(13).fontColor($r('app.color.muted')).width('100%')
              TextInput({ text: this.label, placeholder: '我的电脑' }).enabled(!this.busy).onChange((v: string) => this.label = v)
              Text('URL').fontSize(13).fontColor($r('app.color.muted')).width('100%')
              TextInput({ text: this.address, placeholder: 'https://your-server' }).enabled(!this.busy).onChange((v: string) => this.address = v)
              if (this.cloudSignedIn) {
                Button('链接到 T3 Connect').enabled(!this.busy).onClick(() => {
                  void this.perform(() => this.onLinkCloud(entry.localId));
                })
              }
            }
            Row({ space: 8 }) {
              if (entry.kind === 'bearer') {
                Button('保存').enabled(!this.busy && !!this.label.trim() && !!this.address.trim())
                  .onClick(() => this.perform(async () => { await this.onEdit(entry.localId, this.label, this.address); this.expanded = ''; }))
              }
              Button('重试').enabled(!this.busy && entry.enabled).onClick(() => this.perform(() => this.onRetry(entry.localId)))
              Button('移除').enabled(!this.busy).backgroundColor(Color.Transparent).fontColor($r('app.color.danger'))
                .onClick(() => AlertDialog.show({ title: '移除环境？', message: '移除本机连接与该环境的本机数据，服务端任务继续。',
                  primaryButton: { value: '取消', action: () => {} },
                  secondaryButton: { value: '移除', action: () => { void this.perform(() => this.onRemove(entry.localId)); } } }))
            }.width('100%')
          }
        }.width('100%').padding(16).backgroundColor($r('app.color.surface')).borderRadius(12)
      }, (entry: EnvironmentEntry) => environmentRouteKey(entry))
      ConnectDevicesSection({ environmentLabel: this.deviceEnvironmentLabel, pending: this.pendingDevices,
        devices: this.approvedDevices, busy: this.busy, onApprove: this.onApproveDevice,
        onDeny: this.onDenyDevice, onRevoke: this.onRevokeDevice })
      LinkedEnvironmentsSection({ groups: this.linkedGroups })
      PullRequestRoutingSettings({ entries: this.entries.filter((entry: EnvironmentEntry) => entry.kind === 'bearer'),
        initialized: this.initialized, onChange: this.onRouting })
      if (this.error) { Text(this.error).fontSize(13).fontColor($r('app.color.danger')).width('100%') }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1)
    }.width('100%').height('100%').alignItems(HorizontalAlign.Start)
  }
}
