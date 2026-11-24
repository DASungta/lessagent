import { TopBar } from './ui/TopBar';
import { GroupCard } from './ui/GroupCard';
import { FormRow } from './ui/FormRow';
import { AppButton } from './ui/AppButton';
import { StatusBadge } from './ui/StatusBadge';
import { FontSize, LineHeight, Radius, Sizes, Space, Weight } from '../common/Theme';
import { ClerkSsoProvider } from '../protocol/Cloud';
import { EnvironmentEntry } from '../protocol/Environment';
import { CloudEnvironmentView } from '../services/CloudManager';

function ssoLabelFor(strategy: string): string {
  if (strategy === 'oauth_github') return 'GitHub';
  if (strategy === 'oauth_google') return 'Google';
  if (strategy === 'oauth_apple') return 'Apple';
  if (strategy === 'oauth_microsoft') return 'Microsoft';
  return strategy;
}

function endpointKindLabel(providerKind: string): string {
  return providerKind === 'cloudflare_tunnel' ? '托管隧道' : '仅活动发布';
}

function secondFactorLabel(strategy: string): string {
  if (strategy === 'totp') return '身份验证器';
  if (strategy === 'backup_code') return '备用恢复码';
  if (strategy === 'email_code') return '邮箱验证码';
  return strategy;
}

@Component
export struct CloudAccountPanel {
  @Prop configured: boolean = false;
  @Prop signInReady: boolean = false;
  @Prop signedIn: boolean = false;
  @Prop accountId: string = '';
  @Prop accountEmail: string = '';
  @Prop accountDisplayName: string = '';
  @Prop deviceCode: string = '';
  @Prop relayUrl: string = '';
  @Prop publishableKey: string = '';
  @Prop jwtTemplate: string = '';
  @Prop isCustomConfig: boolean = false;
  @Prop showOnboarding: boolean = false;
  @Prop status: string = '';
  @Prop error: string = '';
  @Prop busy: boolean = false;
  @Prop refreshing: boolean = false;
  @Prop environments: CloudEnvironmentView[] = [];
  @Prop entries: EnvironmentEntry[] = [];
  @Prop approvalCodes: Record<string, string> = {};
  @Prop ssoProviders: ClerkSsoProvider[] = [];
  @Prop emailCodeEnabled: boolean = true;
  @Prop passwordEnabled: boolean = true;
  @Prop pendingSsoStrategy: string = '';
  @Prop signInStep: string = ''; // '' | 'needs_first_factor' | 'needs_second_factor'
  @Prop signInEmail: string = '';
  @Prop canUseEmailCode: boolean = false;
  @Prop canUsePassword: boolean = false;
  @Prop secondFactors: string[] = [];
  @Prop backLabel: string = '返回环境';

  @State emailInput: string = '';
  @State passwordInput: string = '';
  @State codeInput: string = '';
  @State secondFactorCode: string = '';
  @State factorTab: string = 'email_code';
  @State secondFactorStrategy: string = 'totp';
  @State emailCodeSent: boolean = false;
  @State configExpanded: boolean = false;
  @State customRelayUrl: string = '';
  @State customPublishableKey: string = '';
  @State customJwtTemplate: string = '';
  @State localError: string = '';

  onClose: () => void = () => {};
  onCopy: (value: string) => void = () => {};
  onBeginSso: (strategy: string) => Promise<void> = async () => {};
  onStartEmail: (email: string) => Promise<void> = async () => {};
  onSendEmailCode: () => Promise<void> = async () => {};
  onVerifyEmailCode: (code: string) => Promise<void> = async () => {};
  onVerifyPassword: (password: string) => Promise<void> = async () => {};
  onPrepareSecondFactor: (strategy: string) => Promise<void> = async () => {};
  onVerifySecondFactor: (strategy: string, code: string) => Promise<void> = async () => {};
  onCancelSignIn: () => Promise<void> = async () => {};
  onSignOut: () => Promise<void> = async () => {};
  onRefresh: () => Promise<void> = async () => {};
  onConnect: (environmentId: string) => Promise<void> = async () => {};
  onLink: (localId: string) => Promise<void> = async () => {};
  onUnlink: (environmentId: string) => Promise<void> = async () => {};
  onResetDeviceKey: () => Promise<void> = async () => {};
  onDismissOnboarding: (dontShowAgain: boolean) => void = () => {};
  onSaveCustomConfig: (publishableKey: string, jwtTemplate: string, relayUrl: string) => Promise<void> = async () => {};
  onResetCustomConfig: () => Promise<void> = async () => {};

  aboutToAppear(): void {
    this.syncConfigInputs();
    if (this.signInEmail && !this.emailInput) this.emailInput = this.signInEmail;
  }

  private syncConfigInputs(): void {
    this.customRelayUrl = this.relayUrl || 'https://relay.t3.codes';
    this.customPublishableKey = this.publishableKey || '';
    this.customJwtTemplate = this.jwtTemplate || 't3-relay';
  }

  private async act(action: () => Promise<void>): Promise<void> {
    if (this.busy) return;
    this.localError = '';
    try { await action(); } catch (err) {
      const msg = err instanceof Error ? err.message : '';
      if (msg) this.localError = msg;
    }
  }

  private localCloudFor(environmentId: string): EnvironmentEntry | undefined {
    return this.entries.find((entry: EnvironmentEntry) =>
      entry.kind === 'cloud' && entry.environmentId === environmentId && !entry.deleting);
  }

  private linked(environmentId: string): boolean {
    return this.environments.some((item: CloudEnvironmentView) => item.environmentId === environmentId);
  }

  private activeFirstFactor(): string {
    if (this.canUseEmailCode && this.canUsePassword) return this.factorTab;
    if (this.canUseEmailCode) return 'email_code';
    if (this.canUsePassword) return 'password';
    return this.factorTab;
  }

  private activeSecondFactor(): string {
    if (this.secondFactors.includes(this.secondFactorStrategy)) return this.secondFactorStrategy;
    return this.secondFactors.length > 0 ? this.secondFactors[0] : 'totp';
  }

  private deploymentSummary(): string {
    const host = this.relayUrl ? this.relayUrl.replace(/^https?:\/\//, '') : '未配置';
    return (this.isCustomConfig ? '自定义部署' : '官方生产环境') + ' · ' + host;
  }

  private saveCustom(): void {
    const run = async (): Promise<void> => {
      await this.onSaveCustomConfig(this.customPublishableKey, this.customJwtTemplate, this.customRelayUrl);
      this.configExpanded = false;
    };
    if (this.signedIn) {
      AlertDialog.show({
        title: '切换 T3 Connect 部署？',
        message: '切换中继与 Clerk 配置前会先退出当前账号并清理本机云环境。',
        primaryButton: { value: '取消', action: () => {} },
        secondaryButton: { value: '退出并切换', action: () => { void this.act(run); } }
      });
    } else {
      void this.act(run);
    }
  }

  private resetCustom(): void {
    const run = async (): Promise<void> => {
      await this.onResetCustomConfig();
      this.syncConfigInputs();
      this.configExpanded = false;
    };
    if (this.signedIn) {
      AlertDialog.show({
        title: '恢复官方默认配置？',
        message: '恢复配置前会先退出当前账号并清理本机云环境。',
        primaryButton: { value: '取消', action: () => {} },
        secondaryButton: { value: '退出并恢复', action: () => { void this.act(run); } }
      });
    } else {
      void this.act(run);
    }
  }

  @Builder
  deploymentConfigSection() {
    GroupCard({
      title: '部署配置',
      footnote: '默认使用官方 T3 Connect（relay.t3.codes）。如自建中继，可在此覆盖公开配置（不含任何服务端密钥）。'
    }) {
      FormRow({
        kind: 'value',
        label: this.isCustomConfig ? '自定义部署' : '官方生产环境',
        subtitle: this.relayUrl || '未配置',
        value: this.configExpanded ? '收起' : '自定义',
        valueMuted: true,
        chevron: false,
        disabled: this.busy,
        isFirst: true,
        onTap: () => {
          if (!this.configExpanded) this.syncConfigInputs();
          this.configExpanded = !this.configExpanded;
        }
      })
      if (this.configExpanded) {
        Column({ space: Space.xs }) {
          Divider().strokeWidth(Sizes.hairline).color($r('app.color.separator'))
          Text('Relay URL（HTTPS 根地址）').fontSize(FontSize.caption).fontColor($r('app.color.muted')).width('100%').padding({ top: Space.xxs })
          TextInput({ placeholder: 'https://relay.t3.codes', text: this.customRelayUrl })
            .height(40).fontSize(FontSize.body).fontColor($r('app.color.ink'))
            .placeholderColor($r('app.color.placeholder')).backgroundColor($r('app.color.group'))
            .borderRadius(Radius.tool).padding({ left: 10, right: 10 })
            .enabled(!this.busy).onChange((v: string) => this.customRelayUrl = v)
          Text('Clerk Publishable Key').fontSize(FontSize.caption).fontColor($r('app.color.muted')).width('100%')
          TextInput({ placeholder: 'pk_live_...', text: this.customPublishableKey })
            .height(40).fontSize(FontSize.body).fontColor($r('app.color.ink'))
            .placeholderColor($r('app.color.placeholder')).backgroundColor($r('app.color.group'))
            .borderRadius(Radius.tool).padding({ left: 10, right: 10 })
            .enabled(!this.busy).onChange((v: string) => this.customPublishableKey = v)
          Text('Clerk JWT Template').fontSize(FontSize.caption).fontColor($r('app.color.muted')).width('100%')
          TextInput({ placeholder: 't3-relay', text: this.customJwtTemplate })
            .height(40).fontSize(FontSize.body).fontColor($r('app.color.ink'))
            .placeholderColor($r('app.color.placeholder')).backgroundColor($r('app.color.group'))
            .borderRadius(Radius.tool).padding({ left: 10, right: 10 })
            .enabled(!this.busy).onChange((v: string) => this.customJwtTemplate = v)
          Row({ space: Space.xs }) {
            AppButton({
              label: '保存自定义配置',
              kind: 'primary',
              compact: true,
              disabled: this.busy || !this.customRelayUrl.trim() || !this.customPublishableKey.trim() || !this.customJwtTemplate.trim(),
              onTap: () => this.saveCustom()
            })
            if (this.isCustomConfig) {
              AppButton({
                label: '恢复官方默认',
                kind: 'secondary',
                compact: true,
                disabled: this.busy,
                onTap: () => this.resetCustom()
              })
            }
          }.width('100%').padding({ top: Space.xxs })
        }.width('100%').padding({ left: 14, right: 14, bottom: 14 }).alignItems(HorizontalAlign.Start)
      }
    }
  }

  build() {
    Column({ space: 0 }) {
      TopBar({ title: 'T3 Connect', showBack: true, backLabel: this.backLabel, onBack: () => this.onClose() }) {
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
                value: '当前未配置 T3 Connect。请在下方部署配置中填入 Relay 地址、Clerk Publishable Key 与 JWT Template。',
                valueMuted: true,
                isFirst: true
              })
            }
          } else if (!this.signedIn) {
            if (this.pendingSsoStrategy) {
              GroupCard({
                title: '等待第三方授权',
                footnote: '请在系统浏览器中完成 ' + ssoLabelFor(this.pendingSsoStrategy) + ' 授权，完成后会自动返回本应用。'
              }) {
                Column({ space: Space.sm }) {
                  Row({ space: Space.xs }) {
                    Text('正在通过 ' + ssoLabelFor(this.pendingSsoStrategy) + ' 登录')
                      .fontSize(FontSize.body).fontWeight(Weight.medium).fontColor($r('app.color.ink')).layoutWeight(1)
                    StatusBadge({ text: '等待返回', tone: 'info' })
                  }.width('100%')
                  Row({ space: Space.xs }) {
                    AppButton({
                      label: '重新打开浏览器',
                      kind: 'secondary',
                      compact: true,
                      disabled: this.busy,
                      onTap: () => { void this.act(() => this.onBeginSso(this.pendingSsoStrategy)); }
                    })
                    AppButton({
                      label: '取消登录',
                      kind: 'danger',
                      compact: true,
                      disabled: this.busy,
                      onTap: () => { void this.act(this.onCancelSignIn); }
                    })
                  }.width('100%')
                }.width('100%').padding({ left: 14, right: 14, top: Space.sm, bottom: Space.sm }).alignItems(HorizontalAlign.Start)
              }
            } else if (this.signInStep === 'needs_second_factor') {
              GroupCard({
                title: '两步验证',
                footnote: '你的 T3 Connect 账号开启了两步验证，请输入验证码完成登录。'
              }) {
                Column({ space: Space.sm }) {
                  if (this.secondFactors.length > 1) {
                    Row({ space: Space.xs }) {
                      ForEach(this.secondFactors, (strategy: string) => {
                        AppButton({
                          label: secondFactorLabel(strategy),
                          kind: this.activeSecondFactor() === strategy ? 'primary' : 'secondary',
                          compact: true,
                          disabled: this.busy,
                          onTap: () => { this.secondFactorStrategy = strategy; }
                        })
                      }, (strategy: string) => strategy)
                    }.width('100%')
                  }
                  if (this.activeSecondFactor() === 'email_code') {
                    AppButton({
                      label: '发送二次验证码到邮箱',
                      kind: 'secondary',
                      compact: true,
                      disabled: this.busy,
                      onTap: () => { void this.act(() => this.onPrepareSecondFactor('email_code')); }
                    })
                  }
                  TextInput({
                    placeholder: this.activeSecondFactor() === 'backup_code' ? '输入备用恢复码' : '输入 6 位动态验证码',
                    text: this.secondFactorCode
                  })
                    .height(42).fontSize(FontSize.body).fontColor($r('app.color.ink'))
                    .placeholderColor($r('app.color.placeholder')).backgroundColor($r('app.color.group'))
                    .borderRadius(Radius.tool).padding({ left: 12, right: 12 })
                    .enabled(!this.busy).onChange((v: string) => this.secondFactorCode = v)
                    .onSubmit(() => {
                      if (!this.busy && this.secondFactorCode.trim()) {
                        const strategy = this.activeSecondFactor();
                        const code = this.secondFactorCode;
                        void this.act(async () => {
                          await this.onVerifySecondFactor(strategy, code);
                          this.secondFactorCode = '';
                        });
                      }
                    })
                  Row({ space: Space.xs }) {
                    AppButton({
                      label: '返回',
                      kind: 'secondary',
                      compact: true,
                      disabled: this.busy,
                      onTap: () => {
                        this.secondFactorCode = '';
                        void this.act(this.onCancelSignIn);
                      }
                    })
                    AppButton({
                      label: this.busy ? '验证中…' : '完成验证',
                      kind: 'primary',
                      compact: true,
                      loading: this.busy,
                      disabled: this.busy || !this.secondFactorCode.trim(),
                      onTap: () => {
                        const strategy = this.activeSecondFactor();
                        const code = this.secondFactorCode;
                        void this.act(async () => {
                          await this.onVerifySecondFactor(strategy, code);
                          this.secondFactorCode = '';
                        });
                      }
                    })
                  }.width('100%')
                }.width('100%').padding({ left: 14, right: 14, top: Space.sm, bottom: Space.sm }).alignItems(HorizontalAlign.Start)
              }
            } else if (this.signInStep === 'needs_first_factor') {
              GroupCard({
                title: '验证账号',
                footnote: '正在登录 ' + (this.signInEmail || this.emailInput)
              }) {
                Column({ space: Space.sm }) {
                  Row({ space: Space.xs }) {
                    Text(this.signInEmail || this.emailInput)
                      .fontSize(FontSize.body).fontWeight(Weight.medium).fontColor($r('app.color.ink')).layoutWeight(1)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    AppButton({
                      label: '更换邮箱',
                      kind: 'text',
                      compact: true,
                      disabled: this.busy,
                      onTap: () => {
                        this.passwordInput = '';
                        this.codeInput = '';
                        this.emailCodeSent = false;
                        void this.act(this.onCancelSignIn);
                      }
                    })
                  }.width('100%').alignItems(VerticalAlign.Center)

                  if (this.canUseEmailCode && this.canUsePassword) {
                    Row({ space: Space.xs }) {
                      AppButton({
                        label: '邮箱验证码',
                        kind: this.activeFirstFactor() === 'email_code' ? 'primary' : 'secondary',
                        compact: true,
                        disabled: this.busy,
                        onTap: () => { this.factorTab = 'email_code'; }
                      })
                      AppButton({
                        label: '密码登录',
                        kind: this.activeFirstFactor() === 'password' ? 'primary' : 'secondary',
                        compact: true,
                        disabled: this.busy,
                        onTap: () => { this.factorTab = 'password'; }
                      })
                    }.width('100%')
                  }

                  if (this.activeFirstFactor() === 'email_code' && this.canUseEmailCode) {
                    Row({ space: Space.xs }) {
                      AppButton({
                        label: this.emailCodeSent ? '重新发送验证码' : '发送邮箱验证码',
                        kind: 'secondary',
                        compact: true,
                        disabled: this.busy,
                        onTap: () => {
                          void this.act(async () => {
                            await this.onSendEmailCode();
                            this.emailCodeSent = true;
                          });
                        }
                      })
                    }.width('100%')
                    TextInput({ placeholder: '输入邮箱收到的验证码', text: this.codeInput })
                      .height(42).fontSize(FontSize.body).fontColor($r('app.color.ink'))
                      .placeholderColor($r('app.color.placeholder')).backgroundColor($r('app.color.group'))
                      .borderRadius(Radius.tool).padding({ left: 12, right: 12 })
                      .enabled(!this.busy).onChange((v: string) => this.codeInput = v)
                      .onSubmit(() => {
                        if (!this.busy && this.codeInput.trim()) {
                          const code = this.codeInput;
                          void this.act(async () => {
                            await this.onVerifyEmailCode(code);
                            this.codeInput = '';
                          });
                        }
                      })
                    AppButton({
                      label: this.busy ? '验证中…' : '验证并登录',
                      kind: 'primary',
                      fill: true,
                      loading: this.busy,
                      disabled: this.busy || !this.codeInput.trim(),
                      onTap: () => {
                        const code = this.codeInput;
                        void this.act(async () => {
                          await this.onVerifyEmailCode(code);
                          this.codeInput = '';
                        });
                      }
                    })
                  } else if (this.canUsePassword) {
                    TextInput({ placeholder: '输入账号密码', text: this.passwordInput })
                      .type(InputType.Password).enableAutoFill(false)
                      .height(42).fontSize(FontSize.body).fontColor($r('app.color.ink'))
                      .placeholderColor($r('app.color.placeholder')).backgroundColor($r('app.color.group'))
                      .borderRadius(Radius.tool).padding({ left: 12, right: 12 })
                      .enabled(!this.busy).onChange((v: string) => this.passwordInput = v)
                      .onSubmit(() => {
                        if (!this.busy && this.passwordInput) {
                          const pwd = this.passwordInput;
                          void this.act(async () => {
                            await this.onVerifyPassword(pwd);
                            this.passwordInput = '';
                          });
                        }
                      })
                    AppButton({
                      label: this.busy ? '登录中…' : '登录',
                      kind: 'primary',
                      fill: true,
                      loading: this.busy,
                      disabled: this.busy || !this.passwordInput,
                      onTap: () => {
                        const pwd = this.passwordInput;
                        void this.act(async () => {
                          await this.onVerifyPassword(pwd);
                          this.passwordInput = '';
                        });
                      }
                    })
                  } else {
                    Text('该邮箱账号仅支持第三方登录，请返回使用 GitHub / Google 等方式登录。')
                      .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted')).width('100%')
                  }
                }.width('100%').padding({ left: 14, right: 14, top: Space.sm, bottom: Space.sm }).alignItems(HorizontalAlign.Start)
              }
            } else {
              if (this.ssoProviders.length > 0) {
                GroupCard({
                  title: '第三方快捷登录',
                  footnote: '在系统浏览器完成授权后将通过 t3code://app/ 自动返回本应用。'
                }) {
                  Column({ space: Space.xs }) {
                    ForEach(this.ssoProviders, (provider: ClerkSsoProvider) => {
                      AppButton({
                        label: '使用 ' + provider.label + ' 登录',
                        kind: provider.strategy === 'oauth_github' ? 'primary' : 'secondary',
                        fill: true,
                        disabled: this.busy || !this.signInReady,
                        onTap: () => { void this.act(() => this.onBeginSso(provider.strategy)); }
                      })
                    }, (provider: ClerkSsoProvider) => provider.strategy)
                  }.width('100%').padding({ left: 14, right: 14, top: Space.sm, bottom: Space.sm })
                }
              }

              if (this.emailCodeEnabled || this.passwordEnabled) {
                GroupCard({
                  title: '使用邮箱登录',
                  footnote: '原生对接 Clerk Native API，支持邮箱验证码、密码与两步验证（TOTP / 备用码）。'
                }) {
                  Column({ space: Space.sm }) {
                    TextInput({ placeholder: 'name@example.com', text: this.emailInput })
                      .type(InputType.Email)
                      .height(42).fontSize(FontSize.body).fontColor($r('app.color.ink'))
                      .placeholderColor($r('app.color.placeholder')).backgroundColor($r('app.color.group'))
                      .borderRadius(Radius.tool).padding({ left: 12, right: 12 })
                      .accessibilityText('T3 Connect 邮箱地址')
                      .enabled(!this.busy && this.signInReady).onChange((v: string) => this.emailInput = v)
                      .onSubmit(() => {
                        if (!this.busy && this.signInReady && this.emailInput.trim()) {
                          this.emailCodeSent = false;
                          void this.act(() => this.onStartEmail(this.emailInput));
                        }
                      })
                    AppButton({
                      label: this.busy ? '正在查询…' : '继续',
                      kind: 'primary',
                      fill: true,
                      loading: this.busy,
                      disabled: this.busy || !this.signInReady || !this.emailInput.trim(),
                      onTap: () => {
                        this.emailCodeSent = false;
                        void this.act(() => this.onStartEmail(this.emailInput));
                      }
                    })
                  }.width('100%').padding({ left: 14, right: 14, top: Space.sm, bottom: Space.sm })
                }
              }
            }
          } else {
            if (this.showOnboarding) {
              GroupCard({ title: '开始使用 T3 Connect' }) {
                Column({ space: Space.xs }) {
                  Text('登录成功。点击下方已链接服务器的「连接」即可跨网络远程访问；若机器要求首次设备批准，请在电脑端核对本机验证码。')
                    .fontSize(FontSize.callout).lineHeight(LineHeight.callout).fontColor($r('app.color.ink')).width('100%')
                  Row({ space: Space.xs }) {
                    AppButton({
                      label: '知道了',
                      kind: 'secondary',
                      compact: true,
                      onTap: () => this.onDismissOnboarding(false)
                    })
                    AppButton({
                      label: '不再提示',
                      kind: 'text',
                      compact: true,
                      onTap: () => this.onDismissOnboarding(true)
                    })
                  }.width('100%')
                }.width('100%').padding({ left: 14, right: 14, top: Space.sm, bottom: Space.sm }).alignItems(HorizontalAlign.Start)
              }
            }

            GroupCard({ title: '账号' }) {
              FormRow({
                kind: 'value',
                label: this.accountDisplayName || '已登录',
                subtitle: this.accountEmail && this.accountEmail !== this.accountDisplayName ? this.accountEmail : this.accountId,
                value: '已登录',
                valueMuted: true,
                chevron: false,
                isFirst: true
              })
              FormRow({
                kind: 'value',
                label: '当前部署',
                value: this.deploymentSummary(),
                valueMuted: true,
                chevron: false,
                isFirst: false
              })
              if (this.deviceCode) {
                FormRow({
                  kind: 'value',
                  label: '本机设备验证码',
                  subtitle: '首次通过 T3 Connect 连接新主机时用于核对批准',
                  value: this.deviceCode,
                  chevron: false,
                  isFirst: false,
                  onTap: () => this.onCopy(this.deviceCode)
                })
              }
            }

            if (this.environments.length === 0) {
              GroupCard({ title: '已链接的服务器' }) {
                FormRow({
                  kind: 'value',
                  label: this.refreshing ? '正在加载…' : '暂无已链接的服务器',
                  subtitle: this.refreshing ? '' : '请先在电脑端 T3 Code 设置中开启 T3 Connect，或将下方本机直连环境链接到账号。',
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
                        Text(environment.label).fontSize(FontSize.body).fontWeight(Weight.medium).fontColor($r('app.color.ink')).width('100%')
                        Text(endpointKindLabel(environment.providerKind) + ' · ' + environment.statusText)
                          .fontSize(FontSize.caption).lineHeight(LineHeight.caption).width('100%')
                          .fontColor(environment.availability === 'online' ? $r('app.color.muted') : $r('app.color.danger'))
                        if (environment.traceId) {
                          Row({ space: Space.xs }) {
                            Text('Trace ID: ' + environment.traceId).fontSize(FontSize.badge).fontColor($r('app.color.muted')).layoutWeight(1)
                              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                            AppButton({
                              label: '复制',
                              kind: 'text',
                              compact: true,
                              onTap: () => this.onCopy(environment.traceId)
                            })
                          }.width('100%').alignItems(VerticalAlign.Center)
                        }
                      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                      if (this.localCloudFor(environment.environmentId)) {
                        StatusBadge({
                          text: this.approvalCodes[this.localCloudFor(environment.environmentId)!.localId] ? '待主机批准' : '已在本机',
                          tone: this.approvalCodes[this.localCloudFor(environment.environmentId)!.localId] ? 'warning' : 'success'
                        })
                      } else {
                        AppButton({
                          label: '连接', kind: 'secondary', compact: true,
                          disabled: this.busy || environment.availability === 'offline',
                          onTap: () => { void this.act(() => this.onConnect(environment.environmentId)); }
                        })
                      }
                    }.width('100%').alignItems(VerticalAlign.Center)
                    if (this.localCloudFor(environment.environmentId) &&
                      this.approvalCodes[this.localCloudFor(environment.environmentId)!.localId]) {
                      Row({ space: Space.xs }) {
                        Text('请在主机上核对并批准本机验证码：' +
                          this.approvalCodes[this.localCloudFor(environment.environmentId)!.localId])
                          .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.ink')).layoutWeight(1)
                        AppButton({
                          label: '复制',
                          kind: 'text',
                          compact: true,
                          onTap: () => this.onCopy(this.approvalCodes[this.localCloudFor(environment.environmentId)!.localId])
                        })
                      }.width('100%').padding(Space.xs).backgroundColor($r('app.color.group')).borderRadius(Radius.tool)
                        .alignItems(VerticalAlign.Center)
                    }
                    Row({ space: Space.xs }) {
                      if (this.localCloudFor(environment.environmentId)) {
                        AppButton({
                          label: '重新连接', kind: 'secondary', compact: true, disabled: this.busy,
                          onTap: () => { void this.act(() => this.onConnect(environment.environmentId)); }
                        })
                      }
                      AppButton({
                        label: '解除账号链接', kind: 'danger', compact: true, disabled: this.busy,
                        onTap: () => {
                          AlertDialog.show({
                            title: '解除账号链接？',
                            message: '此服务器将从账号移除，托管隧道会关闭；本机直连环境不受影响。',
                            primaryButton: { value: '取消', action: () => {} },
                            secondaryButton: { value: '解除', action: () => { void this.act(() => this.onUnlink(environment.environmentId)); } }
                          });
                        }
                      })
                    }.width('100%')
                  }
                  .width('100%')
                  .alignItems(HorizontalAlign.Start)
                  .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
                  .constraintSize({ minHeight: Sizes.formRowMin })
                  .justifyContent(FlexAlign.Center)
                  .border({ width: { top: index === 0 ? 0 : Sizes.hairline }, color: { top: $r('app.color.separator') } })
                }, (environment: CloudEnvironmentView) => environment.environmentId + ':' + environment.availability + ':' +
                  environment.statusText + ':' + (this.localCloudFor(environment.environmentId)?.localId || '') + ':' +
                  (this.localCloudFor(environment.environmentId) ? (this.approvalCodes[this.localCloudFor(environment.environmentId)!.localId] || '') : ''))
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
                  }, (entry: EnvironmentEntry) => entry.localId + ':' + (this.linked(entry.environmentId) ? '1' : '0'))
              }
            }

            GroupCard({ title: '设备密钥', footnote: 'DPoP P-256 私钥保存在系统安全存储（Asset）中。重置后需在各主机重新批准此设备。' }) {
              Row({ space: Space.sm }) {
                Column({ space: 2 }) {
                  Text('本机 DPoP 密钥').fontSize(FontSize.body).fontColor($r('app.color.ink')).width('100%')
                  Text(this.deviceCode ? '验证码 ' + this.deviceCode : '将在首次连接时生成')
                    .fontSize(FontSize.caption).fontColor($r('app.color.muted')).width('100%')
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                AppButton({
                  label: '重置密钥',
                  kind: 'danger',
                  compact: true,
                  disabled: this.busy,
                  onTap: () => {
                    AlertDialog.show({
                      title: '重置本机设备密钥？',
                      message: '将生成新的 P-256 DPoP 密钥并清理本机云令牌缓存，各主机需重新批准此设备。',
                      primaryButton: { value: '取消', action: () => {} },
                      secondaryButton: { value: '重置', action: () => { void this.act(this.onResetDeviceKey); } }
                    });
                  }
                })
              }
              .width('100%').padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
              .constraintSize({ minHeight: Sizes.formRowMin }).alignItems(VerticalAlign.Center)
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

          this.deploymentConfigSection()

          if (this.status && this.status !== (this.localError || this.error)) {
            Text(this.status).fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.sm }).width('100%')
          }
          if (this.error || this.localError) {
            Text(this.localError || this.error).fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.danger'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.sm }).width('100%')
          }
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: Space.sm, right: Space.sm, bottom: Space.lg })
      }.width('100%').layoutWeight(1).align(Alignment.TopStart).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
  }
}
