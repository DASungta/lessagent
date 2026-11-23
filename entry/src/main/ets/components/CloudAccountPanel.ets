import { TopBar } from './ui/TopBar';
import { GroupCard } from './ui/GroupCard';
import { FormRow } from './ui/FormRow';
import { AppButton } from './ui/AppButton';
import { StatusBadge } from './ui/StatusBadge';
import { FontSize, LineHeight, Sizes, Space, Weight } from '../common/Theme';
import { EnvironmentEntry } from '../protocol/Environment';
import { CloudEnvironmentView } from '../services/CloudManager';

@Component
export struct CloudAccountPanel {
  @Prop configured: boolean = false;
  @Prop signInReady: boolean = false;
  @Prop signedIn: boolean = false;
  @Prop accountId: string = '';
  @Prop status: string = '';
  @Prop error: string = '';
  @Prop busy: boolean = false;
  @Prop refreshing: boolean = false;
  @Prop environments: CloudEnvironmentView[] = [];
  @Prop entries: EnvironmentEntry[] = [];
  onClose: () => void = () => {};
  onSignIn: () => Promise<void> = async () => {};
  onSignOut: () => Promise<void> = async () => {};
  onRefresh: () => Promise<void> = async () => {};
  onConnect: (environmentId: string) => Promise<void> = async () => {};
  onLink: (localId: string) => Promise<void> = async () => {};
  onUnlink: (environmentId: string) => Promise<void> = async () => {};

  private async act(action: () => Promise<void>): Promise<void> {
    if (this.busy) return;
    try { await action(); } catch (_) {}
  }
  private localFor(environmentId: string): EnvironmentEntry | undefined {
    return this.entries.find((entry: EnvironmentEntry) => entry.environmentId === environmentId && !entry.deleting);
  }
  private linked(environmentId: string): boolean {
    return this.environments.some((item: CloudEnvironmentView) => item.environmentId === environmentId);
  }

  build() {
    Column({ space: 0 }) {
      TopBar({ title: 'T3 Connect', showBack: true, backLabel: '返回环境', onBack: () => this.onClose() }) {
        if (this.signedIn) {
          AppButton({
            label: this.refreshing ? '同步中' : '刷新',
            kind: 'text',
            disabled: this.busy || this.refreshing,
            onTap: () => { void this.act(this.onRefresh); }
          })
        }
      }
      Scroll() {
        Column({ space: 0 }) {
          if (!this.configured) {
            GroupCard() {
              FormRow({
                kind: 'multiline',
                label: '未配置',
                value: '此构建未配置 T3 Connect。需要 Clerk publishable key、JWT template 与 HTTPS 中继地址。',
                valueMuted: true,
                isFirst: true
              })
            }
          } else if (!this.signedIn) {
            GroupCard({
              title: '登录 T3 Connect',
              footnote: !this.signInReady ? '尚未注册合法的鸿蒙 OAuth 客户端与回调，请先在公开构建配置中提供 Clerk OAuth client id。' : ''
            }) {
              FormRow({
                kind: 'multiline',
                label: '托管中继',
                value: '登录后可从任意网络访问已链接的机器。登录在系统浏览器完成，回调会校验 state 与 PKCE。',
                valueMuted: true,
                isFirst: true
              })
            }
            Column() {
              AppButton({
                label: this.busy ? '正在打开…' : '登录',
                kind: 'primary',
                fill: true,
                loading: this.busy,
                disabled: !this.signInReady,
                onTap: () => { void this.act(this.onSignIn); }
              })
            }.width('100%').padding({ top: Space.md })
          } else {
            GroupCard({ title: '账号' }) {
              FormRow({ kind: 'value', label: '已登录', value: this.accountId, valueMuted: true, chevron: false, isFirst: true })
            }

            if (this.environments.length === 0) {
              GroupCard({ title: '已链接的服务器' }) {
                FormRow({
                  kind: 'value',
                  label: this.refreshing ? '正在加载…' : '暂无已链接的服务器',
                  subtitle: this.refreshing ? '' : '请先在机器上完成 T3 Connect 链接。',
                  value: '',
                  valueMuted: true,
                  chevron: false,
                  isFirst: true
                })
              }
            } else {
              GroupCard({ title: '已链接的服务器' }) {
                ForEach(this.environments, (environment: CloudEnvironmentView, index: number) => {
                  Column({ space: Space.xs }) {
                    Row({ space: Space.xs }) {
                      Column({ space: 2 }) {
                        Text(environment.label).fontSize(FontSize.body).fontColor($r('app.color.ink')).width('100%')
                        Text(environment.statusText).fontSize(FontSize.caption).width('100%')
                          .fontColor(environment.availability === 'online' ? $r('app.color.muted') : $r('app.color.danger'))
                        if (environment.traceId) {
                          Text('Trace ID: ' + environment.traceId).fontSize(FontSize.badge).fontColor($r('app.color.muted')).width('100%')
                        }
                      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                      if (this.localFor(environment.environmentId)) {
                        StatusBadge({ text: '已在本机', tone: 'success' })
                      } else {
                        AppButton({
                          label: '连接', kind: 'secondary', compact: true,
                          disabled: this.busy || environment.availability === 'offline',
                          onTap: () => { void this.act(() => this.onConnect(environment.environmentId)); }
                        })
                      }
                    }.width('100%').alignItems(VerticalAlign.Center)
                    AppButton({
                      label: '解除账号链接', kind: 'danger', compact: true, disabled: this.busy,
                      onTap: () => {
                        AlertDialog.show({
                          title: '解除账号链接？',
                          message: '此服务器将从账号移除，本机直连环境不受影响。',
                          primaryButton: { value: '取消', action: () => {} },
                          secondaryButton: { value: '解除', action: () => { void this.act(() => this.onUnlink(environment.environmentId)); } }
                        });
                      }
                    })
                  }
                  .width('100%')
                  .alignItems(HorizontalAlign.Start)
                  .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
                  .constraintSize({ minHeight: Sizes.formRowMin })
                  .justifyContent(FlexAlign.Center)
                  .border({ width: { top: index === 0 ? 0 : Sizes.hairline }, color: { top: $r('app.color.separator') } })
                }, (environment: CloudEnvironmentView) => environment.environmentId)
              }
            }

            if (this.entries.some((entry: EnvironmentEntry) => entry.kind === 'bearer' && !entry.deleting)) {
              GroupCard({ title: '本机直连环境' }) {
                ForEach(this.entries.filter((entry: EnvironmentEntry) => entry.kind === 'bearer' && !entry.deleting),
                  (entry: EnvironmentEntry, index: number) => {
                    Row({ space: Space.sm }) {
                      Text(entry.label)
                        .fontSize(FontSize.body).lineHeight(LineHeight.body).fontWeight(Weight.regular)
                        .fontColor($r('app.color.ink')).layoutWeight(1)
                      if (this.linked(entry.environmentId)) {
                        StatusBadge({ text: '已链接', tone: 'success' })
                      } else {
                        AppButton({
                          label: '链接', kind: 'secondary', compact: true, disabled: this.busy,
                          onTap: () => { void this.act(() => this.onLink(entry.localId)); }
                        })
                      }
                    }
                    .width('100%')
                    .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
                    .constraintSize({ minHeight: Sizes.formRowMin })
                    .alignItems(VerticalAlign.Center)
                    .border({ width: { top: index === 0 ? 0 : Sizes.hairline }, color: { top: $r('app.color.separator') } })
                  }, (entry: EnvironmentEntry) => entry.localId)
              }
            }

            Column() {
              AppButton({
                label: '退出登录',
                kind: 'danger',
                fill: true,
                disabled: this.busy,
                onTap: () => {
                  AlertDialog.show({
                    title: '退出 T3 Connect？',
                    message: '本机云环境与令牌会被清理；存在未知提交时会阻止清理。',
                    primaryButton: { value: '取消', action: () => {} },
                    secondaryButton: { value: '退出', action: () => { void this.act(this.onSignOut); } }
                  });
                }
              })
            }.width('100%').padding({ top: Space.md })
          }
          if (this.status) {
            Text(this.status).fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.sm }).width('100%')
          }
          if (this.error) {
            Text(this.error).fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.danger'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.sm }).width('100%')
          }
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: Space.sm, right: Space.sm, bottom: Space.lg })
      }.width('100%').layoutWeight(1).align(Alignment.TopStart).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
  }
}
