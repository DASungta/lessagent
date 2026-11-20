import { TopBar } from './ui/TopBar';
import { IconButton } from './ui/IconButton';
import { GroupCard } from './ui/GroupCard';
import { FormRow } from './ui/FormRow';
import { AppButton } from './ui/AppButton';
import { StatusBadge, BadgeTone } from './ui/StatusBadge';
import { FontSize, LineHeight, Radius, Sizes, Space, Weight } from '../common/Theme';
import { LinkedEnvironmentsSection, LinkedEnvironmentGroup } from './LinkedEnvironmentsSection';
import { PullRequestRoutingSettings } from './PullRequestRoutingSettings';
import { DirectRoute, EnvironmentEntry, environmentRouteKey, environmentRoutes } from '../protocol/Environment';
import { ConnectDevicesSection } from './ConnectDevicesSection';
import { CloudDevice, CloudPairingLink } from '../protocol/Cloud';

@Component
export struct ConnectionsPanel {
  @Prop entries: EnvironmentEntry[] = [];
  @Prop statuses: Record<string, string> = {};
  @Prop readyMap: Record<string, boolean> = {};
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
  private isConnected(status: string, entry: EnvironmentEntry): boolean {
    return this.readyMap[entry.localId] === true || status === '已连接' || status === '会话已同步' ||
      status === '正在同步会话' || status.startsWith('任务状态');
  }
  private statusBadgeText(entry: EnvironmentEntry): string {
    if (!entry.enabled) return '已停用';
    const status = this.statuses[entry.localId] || '';
    if (this.isConnected(status, entry)) return '已连接';
    if (status.includes('正在连接') || status.includes('连接中')) return '连接中';
    if (status.includes('解锁')) return '需解锁';
    if (status.includes('失败') || status.includes('错误')) return '连接失败';
    return '未连接';
  }
  private statusBadgeTone(entry: EnvironmentEntry): BadgeTone {
    if (!entry.enabled) return 'neutral';
    const status = this.statuses[entry.localId] || '';
    if (this.isConnected(status, entry)) return 'success';
    if (status.includes('正在连接') || status.includes('连接中')) return 'info';
    if (status.includes('失败') || status.includes('错误')) return 'danger';
    return 'warning';
  }
  private expand(entry: EnvironmentEntry): void {
    this.expanded = this.expanded === entry.localId ? '' : entry.localId;
    this.label = entry.label; this.address = entry.base; this.error = '';
  }
  build() {
    Column({ space: 0 }) {
      TopBar({
        title: '环境',
        showBack: true,
        closeStyle: true,
        backLabel: '关闭环境',
        onBack: () => this.onClose()
      }) {
        IconButton({
          icon: $r('app.media.ui_plus'),
          label: '添加环境',
          disabled: !(this.initialized && !this.busy),
          onTap: () => this.onAdd()
        })
      }
      Scroll() {
        Column({ space: 0 }) {
          if (this.cloudConfigured) {
            GroupCard() {
              FormRow({
                kind: 'value',
                label: 'T3 Connect',
                subtitle: this.cloudSignedIn ? (this.cloudStatus || '已登录') : '登录以使用托管中继',
                value: '',
                disabled: this.busy,
                isFirst: true,
                onTap: () => this.onCloudAccount()
              })
            }
          }
          if (!this.initialized) {
            GroupCard() {
              Column({ space: Space.xs }) {
                Text('连接记录未加载，请解锁后重试。')
                  .fontSize(FontSize.body).lineHeight(LineHeight.body).fontColor($r('app.color.muted')).width('100%')
                AppButton({
                  label: '重试加载',
                  kind: 'secondary',
                  compact: true,
                  disabled: this.busy,
                  onTap: () => { void this.perform(this.onInitialize); }
                })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
              .constraintSize({ minHeight: Sizes.formRowMin })
              .justifyContent(FlexAlign.Center)
            }
          } else if (!this.entries.length) {
            GroupCard() {
              Column({ space: Space.sm }) {
                Column() {
                  Image($r('app.media.ui_globe')).width(24).height(24).accessibilityLevel('no')
                }.width(48).height(48).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
                  .backgroundColor($r('app.color.group')).borderRadius(24)
                Text('还没有连接环境\n点右上角 + 添加一个')
                  .fontSize(FontSize.body).lineHeight(LineHeight.body)
                  .fontColor($r('app.color.muted')).textAlign(TextAlign.Center)
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: Space.lg, bottom: Space.lg })
              .alignItems(HorizontalAlign.Center)
            }
          }

          if (this.entries.some((e: EnvironmentEntry) => !e.deleting)) {
            Text('已配置环境')
              .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.sm, bottom: 5 }).width('100%')
            Column({ space: Space.xs }) {
              ForEach(this.entries.filter((e: EnvironmentEntry) => !e.deleting), (entry: EnvironmentEntry) => {
                Column({ space: 0 }) {
                  Row({ space: Space.xs }) {
                    Button({ type: ButtonType.Normal }) {
                      Column({ space: 2 }) {
                        Row({ space: Space.xs }) {
                          Text(entry.label)
                            .fontSize(FontSize.body).lineHeight(LineHeight.body).fontWeight(Weight.medium)
                            .fontColor($r('app.color.ink')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                          StatusBadge({
                            text: this.statusBadgeText(entry),
                            tone: this.statusBadgeTone(entry)
                          })
                        }.width('100%').alignItems(VerticalAlign.Center)
                        Text(entry.base + (entry.kind === 'cloud' ? ' · T3 Connect' : ''))
                          .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted'))
                          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                        if (entry.enabled && this.statuses[entry.localId] && this.statuses[entry.localId] !== '已连接') {
                          Text(this.statuses[entry.localId])
                            .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted'))
                            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                        }
                      }.width('100%').alignItems(HorizontalAlign.Start)
                    }.layoutWeight(1).backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
                      .padding(0).enabled(!this.busy).accessibilityText('管理 ' + entry.label).onClick(() => this.expand(entry))
                    Toggle({ type: ToggleType.Switch, isOn: entry.enabled })
                      .selectedColor($r('app.color.primary')).switchPointColor(Color.White)
                      .enabled(!this.busy)
                      .accessibilityText('启用 ' + entry.label)
                      .onChange((enabled: boolean) => { if (enabled !== entry.enabled) void this.perform(() => this.onEnabled(entry.localId, enabled)); })
                    Button({ type: ButtonType.Circle, stateEffect: true }) {
                      Image($r('app.media.ui_chevron_down')).width(Sizes.chevron).height(Sizes.chevron)
                        .opacity(0.6).rotate({ angle: this.expanded === entry.localId ? 180 : 0 }).accessibilityLevel('no')
                    }.width(36).height(36).backgroundColor(Color.Transparent)
                      .enabled(!this.busy).accessibilityText('展开环境详情').onClick(() => this.expand(entry))
                  }.width('100%').padding({ left: 14, right: 10, top: Space.sm, bottom: Space.sm }).alignItems(VerticalAlign.Center)

                  if (this.expanded === entry.localId) {
                    Column({ space: Space.xs }) {
                      Divider().strokeWidth(Sizes.hairline).color($r('app.color.separator'))
                      if (entry.kind === 'cloud') {
                        Text('此地址由 T3 Connect 管理；凭据按账号与设备隔离，不在目录中保存。')
                          .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted')).width('100%')
                        AppButton({
                          label: '打开 T3 Connect', kind: 'secondary', compact: true, disabled: this.busy,
                          onTap: () => this.onCloudAccount()
                        })
                      } else {
                        Text('连接路径').fontSize(FontSize.caption).fontColor($r('app.color.muted')).width('100%').padding({ top: Space.xxs })
                        ForEach(environmentRoutes(entry), (route: DirectRoute, index: number) => {
                          Row({ space: Space.xs }) {
                            Column({ space: 2 }) {
                              Text(route.base).fontSize(FontSize.callout).lineHeight(LineHeight.callout).fontColor($r('app.color.ink'))
                                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                              Text(index === 0 ? '优先连接' : '备用路径').fontSize(FontSize.badge).fontColor($r('app.color.muted'))
                            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                            Button({ type: ButtonType.Circle, stateEffect: true }) {
                              Image($r('app.media.ui_down')).width(14).height(14).rotate({ angle: 180 }).accessibilityLevel('no')
                            }.width(34).height(34).backgroundColor(Color.Transparent).enabled(!this.busy && index > 0)
                              .opacity(index > 0 ? 1 : 0.35).accessibilityText('上移连接路径')
                              .onClick(() => this.perform(async () => {
                                const refs = environmentRoutes(entry).map((item: DirectRoute) => item.credentialRef);
                                const previous = refs[index - 1]; refs[index - 1] = refs[index]; refs[index] = previous;
                                await this.onReorderRoutes(entry.localId, refs);
                              }))
                            Button({ type: ButtonType.Circle, stateEffect: true }) {
                              Image($r('app.media.ui_down')).width(14).height(14).accessibilityLevel('no')
                            }.width(34).height(34).backgroundColor(Color.Transparent)
                              .enabled(!this.busy && index < environmentRoutes(entry).length - 1)
                              .opacity(index < environmentRoutes(entry).length - 1 ? 1 : 0.35).accessibilityText('下移连接路径')
                              .onClick(() => this.perform(async () => {
                                const refs = environmentRoutes(entry).map((item: DirectRoute) => item.credentialRef);
                                const next = refs[index + 1]; refs[index + 1] = refs[index]; refs[index] = next;
                                await this.onReorderRoutes(entry.localId, refs);
                              }))
                            if (environmentRoutes(entry).length > 1) {
                              AppButton({
                                label: '移除', kind: 'danger', compact: true, disabled: this.busy,
                                a11yLabel: '移除路径',
                                onTap: () => {
                                  AlertDialog.show({
                                    title: '移除连接路径？',
                                    message: '此地址的本机凭据将被删除，其他可用路径保持不变。',
                                    primaryButton: { value: '取消', action: () => {} },
                                    secondaryButton: { value: '移除', action: () => { void this.perform(() => this.onRemoveRoute(entry.localId, route.credentialRef)); } }
                                  });
                                }
                              })
                            }
                          }.width('100%').padding(Space.xs).backgroundColor($r('app.color.group')).borderRadius(Radius.tool)
                        }, (route: DirectRoute) => route.credentialRef)
                        AppButton({
                          label: '添加路径', kind: 'secondary', compact: true, disabled: this.busy || !entry.enabled,
                          onTap: () => this.onAddRoute(entry.localId)
                        })

                        Text('名称').fontSize(FontSize.caption).fontColor($r('app.color.muted')).width('100%').padding({ top: Space.xxs })
                        TextInput({ text: this.label, placeholder: '我的电脑' }).height(40).fontSize(FontSize.body)
                          .backgroundColor($r('app.color.group')).borderRadius(Radius.tool).padding({ left: 10, right: 10 })
                          .enabled(!this.busy).onChange((v: string) => this.label = v)
                        Text('URL').fontSize(FontSize.caption).fontColor($r('app.color.muted')).width('100%')
                        TextInput({ text: this.address, placeholder: 'https://your-server' }).height(40).fontSize(FontSize.body)
                          .backgroundColor($r('app.color.group')).borderRadius(Radius.tool).padding({ left: 10, right: 10 })
                          .enabled(!this.busy).onChange((v: string) => this.address = v)
                        if (this.cloudSignedIn) {
                          AppButton({
                            label: '链接到 T3 Connect', kind: 'secondary', compact: true, disabled: this.busy,
                            onTap: () => { void this.perform(() => this.onLinkCloud(entry.localId)); }
                          })
                        }
                      }
                      Row({ space: Space.xs }) {
                        if (entry.kind === 'bearer') {
                          AppButton({
                            label: '保存', kind: 'primary', compact: true,
                            disabled: this.busy || !this.label.trim() || !this.address.trim(),
                            onTap: () => { void this.perform(async () => { await this.onEdit(entry.localId, this.label, this.address); this.expanded = ''; }); }
                          })
                        }
                        AppButton({
                          label: '重试', kind: 'secondary', compact: true, disabled: this.busy || !entry.enabled,
                          onTap: () => { void this.perform(() => this.onRetry(entry.localId)); }
                        })
                        AppButton({
                          label: '移除', kind: 'danger', compact: true, disabled: this.busy,
                          onTap: () => {
                            AlertDialog.show({
                              title: '移除环境？',
                              message: '移除本机连接与该环境的本机数据，服务端任务继续。',
                              primaryButton: { value: '取消', action: () => {} },
                              secondaryButton: { value: '移除', action: () => { void this.perform(() => this.onRemove(entry.localId)); } }
                            });
                          }
                        })
                      }.width('100%').padding({ top: Space.xxs })
                    }.width('100%').padding({ left: 14, right: 14, bottom: 14 }).alignItems(HorizontalAlign.Start)
                  }
                }.width('100%').backgroundColor($r('app.color.card')).borderRadius(Radius.card).clip(true)
              }, (entry: EnvironmentEntry) => environmentRouteKey(entry) + ':' + (entry.enabled ? '1' : '0') + ':' +
                (this.readyMap[entry.localId] ? '1' : '0') + ':' + (this.statuses[entry.localId] || '') + ':' +
                entry.label + ':' + entry.base + ':' + (entry.prRouting || ''))
            }.width('100%')
          }

          ConnectDevicesSection({ environmentLabel: this.deviceEnvironmentLabel, pending: this.pendingDevices,
            devices: this.approvedDevices, busy: this.busy, onApprove: this.onApproveDevice,
            onDeny: this.onDenyDevice, onRevoke: this.onRevokeDevice })
          LinkedEnvironmentsSection({ groups: this.linkedGroups })
          PullRequestRoutingSettings({ entries: this.entries.filter((entry: EnvironmentEntry) => entry.kind === 'bearer'),
            initialized: this.initialized, onChange: this.onRouting })
          if (this.error) {
            Text(this.error).fontSize(FontSize.callout).lineHeight(LineHeight.callout).fontColor($r('app.color.danger'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.sm }).width('100%')
          }
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: Space.sm, right: Space.sm, bottom: Space.lg })
      }.width('100%').layoutWeight(1).align(Alignment.TopStart)
    }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
  }
}
