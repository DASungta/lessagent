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
    Column({ space: 14 }) {
      Row({ space: 8 }) {
        Button('‹').width(44).height(44).backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
          .accessibilityText('返回环境').onClick(this.onClose)
        Text('T3 Connect').fontSize(20).fontWeight(FontWeight.Medium)
        Blank()
        if (this.signedIn) {
          Button(this.refreshing ? '…' : '刷新').backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
            .enabled(!this.busy && !this.refreshing).onClick(() => void this.act(this.onRefresh))
        }
      }.width('100%')
      Scroll() {
        Column({ space: 16 }) {
          if (!this.configured) {
            Text('此构建未配置 T3 Connect。需要 Clerk publishable key、JWT template 与 HTTPS 中继地址。')
              .fontSize(14).fontColor($r('app.color.muted')).width('100%')
          } else if (!this.signedIn) {
            Column({ space: 10 }) {
              Text('登录 T3 Connect').fontSize(16).fontWeight(FontWeight.Medium).width('100%')
              Text('登录后可从任意网络访问已链接的机器。登录在系统浏览器完成，回调会校验 state 与 PKCE。')
                .fontSize(13).fontColor($r('app.color.muted')).width('100%')
              if (!this.signInReady) {
                Text('尚未注册合法的鸿蒙 OAuth 客户端与回调，登录保持阻塞。请先在公开构建配置中提供 Clerk OAuth client id。')
                  .fontSize(13).fontColor($r('app.color.danger')).width('100%')
              }
              Button(this.busy ? '正在打开…' : '登录').width('100%').enabled(this.signInReady && !this.busy)
                .onClick(() => void this.act(this.onSignIn))
            }.width('100%').padding(16).backgroundColor($r('app.color.surface')).borderRadius(16)
          } else {
            Column({ space: 6 }) {
              Text('已登录').fontSize(16).fontWeight(FontWeight.Medium).width('100%')
              Text(this.accountId).fontSize(12).fontColor($r('app.color.muted')).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            }.width('100%').padding(16).backgroundColor($r('app.color.surface')).borderRadius(16)

            Text('已链接的服务器').fontSize(14).fontWeight(FontWeight.Medium).width('100%')
            if (this.environments.length === 0) {
              Text(this.refreshing ? '正在加载…' : '此账号还没有已链接的服务器。请先在机器上完成 T3 Connect 链接。')
                .fontSize(13).fontColor($r('app.color.muted')).width('100%')
            }
            ForEach(this.environments, (environment: CloudEnvironmentView) => {
              Column({ space: 6 }) {
                Row({ space: 8 }) {
                  Column({ space: 3 }) {
                    Text(environment.label).fontSize(15).fontWeight(FontWeight.Medium).width('100%')
                    Text(environment.statusText).fontSize(12).width('100%')
                      .fontColor(environment.availability === 'online' ? $r('app.color.muted') : $r('app.color.danger'))
                    if (environment.traceId) {
                      Text('Trace ID: ' + environment.traceId).fontSize(11).fontColor($r('app.color.muted')).width('100%')
                    }
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  if (this.localFor(environment.environmentId)) {
                    Text('已在本机').fontSize(12).fontColor($r('app.color.muted'))
                  } else {
                    Button('连接').fontSize(13).enabled(!this.busy && environment.availability !== 'offline')
                      .onClick(() => void this.act(() => this.onConnect(environment.environmentId)))
                  }
                }.width('100%')
                Button('解除账号链接').fontSize(12).backgroundColor(Color.Transparent).fontColor($r('app.color.danger'))
                  .enabled(!this.busy).onClick(() => {
                    AlertDialog.show({ title: '解除账号链接？', message: '此服务器将从账号移除，本机直连环境不受影响。',
                      primaryButton: { value: '取消', action: () => {} },
                      secondaryButton: { value: '解除', action: () => { void this.act(() => this.onUnlink(environment.environmentId)); } } });
                  })
              }.width('100%').padding(12).backgroundColor($r('app.color.canvas')).borderRadius(10)
            }, (environment: CloudEnvironmentView) => environment.environmentId)

            Text('本机直连环境').fontSize(14).fontWeight(FontWeight.Medium).width('100%')
            ForEach(this.entries.filter((entry: EnvironmentEntry) => entry.kind === 'bearer' && !entry.deleting),
              (entry: EnvironmentEntry) => {
                Row({ space: 8 }) {
                  Text(entry.label).fontSize(14).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (this.linked(entry.environmentId)) {
                    Text('已链接').fontSize(12).fontColor($r('app.color.muted'))
                  } else {
                    Button('链接').fontSize(13).enabled(!this.busy)
                      .onClick(() => void this.act(() => this.onLink(entry.localId)))
                  }
                }.width('100%').padding(10).backgroundColor($r('app.color.canvas')).borderRadius(8)
              }, (entry: EnvironmentEntry) => entry.localId)

            Button('退出登录').width('100%').backgroundColor(Color.Transparent).fontColor($r('app.color.danger'))
              .enabled(!this.busy).onClick(() => {
                AlertDialog.show({ title: '退出 T3 Connect？', message: '本机云环境与令牌会被清理；存在未知提交时会阻止清理。',
                  primaryButton: { value: '取消', action: () => {} },
                  secondaryButton: { value: '退出', action: () => { void this.act(this.onSignOut); } } });
              })
          }
          if (this.status) { Text(this.status).fontSize(12).fontColor($r('app.color.muted')).width('100%') }
          if (this.error) { Text(this.error).fontSize(12).fontColor($r('app.color.danger')).width('100%') }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1)
    }.padding(24).width('100%').height('100%').foregroundColor($r('app.color.ink'))
  }
}
