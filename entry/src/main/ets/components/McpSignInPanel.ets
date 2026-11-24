import { FontSize, LineHeight, Radius, Space, Weight } from '../common/Theme';
import { McpSignInNoticeView } from '../protocol/McpApp';
import { T3Client } from '../services/T3Client';
import { AppButton } from './ui/AppButton';
import { GroupCard } from './ui/GroupCard';
import { TopBar } from './ui/TopBar';

@Component
export struct McpSignInPanel {
  connection: T3Client | undefined = undefined;
  @Prop target: McpSignInNoticeView | undefined = undefined;
  onOpenExternalUrl: (url: string) => Promise<void> = async () => {};
  onSignedIn: (server: string) => void = () => {};
  onClose: () => void = () => {};

  @State authUrl: string = '';
  @State callbackUrl: string = '';
  @State busy: boolean = false;
  @State error: string = '';
  @State status: string = '';
  private closed: boolean = false;

  aboutToDisappear(): void {
    this.closed = true;
  }

  private async openSignInPage(): Promise<void> {
    const conn = this.connection;
    const t = this.target;
    if (!conn || !t || this.busy) return;
    if (!t.providerThreadId) {
      this.error = '缺少关联的 Provider 会话标识，无法发起 MCP 登录';
      return;
    }
    this.busy = true;
    this.error = '';
    this.status = '';
    try {
      let page = this.authUrl;
      if (!page) {
        const started = await conn.mcpSignInStart(t.threadId, t.providerThreadId, t.server);
        if (this.closed) return;
        if (!started.authorizationUrl) {
          this.status = '该 MCP 服务已完成登录';
          this.onSignedIn(t.server);
          return;
        }
        page = started.authorizationUrl;
        this.authUrl = page;
      }
      await this.onOpenExternalUrl(page);
      if (!this.closed) {
        this.status = '已在浏览器打开授权页，完成后请粘贴回调地址';
      }
    } catch (reason) {
      if (!this.closed) {
        this.error = (reason as Error).message || '无法发起 MCP 登录，请重试';
      }
    } finally {
      if (!this.closed) this.busy = false;
    }
  }

  private async completeSignIn(): Promise<void> {
    const conn = this.connection;
    const t = this.target;
    const pasted = this.callbackUrl.trim();
    if (!conn || !t || !pasted || this.busy) return;
    if (!t.providerThreadId) {
      this.error = '缺少关联的 Provider 会话标识';
      return;
    }
    this.busy = true;
    this.error = '';
    this.status = '';
    try {
      await conn.mcpSignInComplete(t.threadId, t.providerThreadId, t.server, pasted);
      if (this.closed) return;
      this.onSignedIn(t.server);
    } catch (reason) {
      if (!this.closed) {
        this.error = (reason as Error).message || 'MCP 回调完成失败，请核对完整地址后重试';
      }
    } finally {
      if (!this.closed) this.busy = false;
    }
  }

  build() {
    Column({ space: 0 }) {
      TopBar({
        title: '登录到 ' + (this.target?.server || 'MCP 服务'),
        showBack: true,
        closeStyle: true,
        backLabel: '关闭',
        onBack: () => { this.closed = true; this.onClose(); }
      })
      Scroll() {
        Column({ space: Space.md }) {
          GroupCard({ title: '步骤 1 · 浏览器授权' }) {
            Column({ space: Space.sm }) {
              Text('在系统浏览器中批准访问。授权后浏览器会跳转到一个本地或回调页面（该页面在手机上可能无法打开），请复制浏览器地址栏中的完整 URL 并粘贴到下方。')
                .fontSize(FontSize.callout)
                .lineHeight(LineHeight.callout)
                .fontColor($r('app.color.muted'))
                .width('100%')
              AppButton({
                label: this.busy && !this.authUrl ? '正在获取授权链接…' : (this.authUrl ? '重新打开授权页面' : '打开授权页面'),
                kind: 'primary',
                fill: true,
                disabled: this.busy,
                onTap: () => { void this.openSignInPage(); }
              })
            }.width('100%').padding(14).alignItems(HorizontalAlign.Start)
          }

          GroupCard({ title: '步骤 2 · 粘贴回调地址' }) {
            Column({ space: Space.sm }) {
              TextInput({ placeholder: 'http://localhost:.../callback?code=...', text: this.callbackUrl })
                .width('100%')
                .height(42)
                .fontSize(FontSize.body)
                .fontColor($r('app.color.ink'))
                .placeholderColor($r('app.color.placeholder'))
                .backgroundColor($r('app.color.group'))
                .borderRadius(Radius.tool)
                .padding({ left: 10, right: 10 })
                .enabled(!this.busy)
                .onChange((value: string) => { this.callbackUrl = value; })
              AppButton({
                label: this.busy && !!this.callbackUrl.trim() ? '正在完成登录…' : '完成登录',
                kind: 'primary',
                fill: true,
                disabled: this.busy || !this.callbackUrl.trim(),
                onTap: () => { void this.completeSignIn(); }
              })
            }.width('100%').padding(14).alignItems(HorizontalAlign.Start)
          }

          if (this.status) {
            Text(this.status)
              .fontSize(FontSize.callout)
              .lineHeight(LineHeight.callout)
              .fontColor($r('app.color.primary_text'))
              .width('100%')
              .padding({ left: Space.xxs, right: Space.xxs })
          }
          if (this.error) {
            Text(this.error)
              .fontSize(FontSize.callout)
              .lineHeight(LineHeight.callout)
              .fontColor($r('app.color.danger'))
              .width('100%')
              .padding({ left: Space.xxs, right: Space.xxs })
          }
        }
        .width('100%')
        .padding({ left: Space.sm, right: Space.sm, top: Space.xs, bottom: Space.lg })
        .alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1).align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.group'))
    .foregroundColor($r('app.color.ink'))
  }
}
