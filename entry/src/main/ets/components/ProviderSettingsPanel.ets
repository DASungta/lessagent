import { TopBar } from './ui/TopBar';
import { GroupCard } from './ui/GroupCard';
import { FormRow } from './ui/FormRow';
import { AppButton } from './ui/AppButton';
import { StatusBadge } from './ui/StatusBadge';
import { ProviderLogo } from './ui/ProviderLogo';
import { FontSize, LineHeight, Opacity, Radius, Sizes, Space, Weight } from '../common/Theme';
import { common } from '@kit.AbilityKit';
import { T3Client } from '../services/T3Client';
import { configEnvironmentId } from '../protocol/Wire';
import { ProviderView, ProviderModelView, ProviderAuthView, providerCatalog, providerStatus,
  providerAuthView, providerAuthActive, providerAuthLabel } from '../protocol/ProviderSettings';

interface ProviderAuthIdentityPayload { instanceId: string; }
interface ProviderAuthCancelPayload { instanceId: string; flowId: string; }
interface BrowserConsentResponse { type: string; action: string; }
interface ProviderBrowserConsentPayload {
  instanceId: string; flowId: string; interactionId: string; response: BrowserConsentResponse;
}

@Component
export struct ProviderSettingsPanel {
  connection: T3Client | undefined = undefined;
  onBack: () => void = () => {};
  @State providers: ProviderView[] = [];
  @State query: string = '';
  @State selectedId: string = '';
  @State auth: ProviderAuthView | undefined = undefined;
  @State busy: boolean = false;
  @State error: string = '';
  @State notice: string = '';
  @State mutationUnconfirmed: boolean = false;
  private authRevision: number = 0;
  private environmentId: string = '';
  private observedGeneration: number = -1;
  private stream: ((value: Object) => void) | undefined = undefined;
  private streamOwner: T3Client | undefined = undefined;
  private timer: number = 0;
  private alive: boolean = true;

  aboutToAppear(): void { this.alive = true; void this.load(false); }
  aboutToDisappear(): void { this.alive = false; this.stopWatch(); this.auth = undefined; }
  private stopWatch(): void {
    if (this.stream && this.streamOwner) this.streamOwner.stopRpcStream(this.stream);
    this.stream = undefined; this.streamOwner = undefined;
    if (this.timer) clearTimeout(this.timer);
    this.timer = 0;
  }
  private selected(): ProviderView | undefined { return this.providers.find(item => item.id === this.selectedId); }
  private manageable(): boolean {
    const provider = this.selected();
    return !!this.connection && this.connection.ready && this.connection.generationValue() === this.observedGeneration &&
      this.connection.canScope('providers:manage') !== false && !!provider && provider.allowed && provider.enabled && provider.installed && !this.busy && !this.mutationUnconfirmed;
  }
  private async load(refresh: boolean): Promise<void> {
    const owner = this.connection;
    if (!owner || !owner.ready || this.busy) { this.error = '请先连接环境'; return; }
    this.busy = true; this.error = ''; this.notice = '';
    this.stopWatch(); this.auth = undefined;
    try {
      const expected = configEnvironmentId(owner.config);
      if (!expected || (this.environmentId && expected !== this.environmentId)) throw new Error('identity');
      this.environmentId = expected;
      const generation = owner.generationValue();
      if (refresh) await owner.refreshProviders(this.selectedId);
      const empty: Record<string, Object> = {};
      const config = await owner.rpcRequest('server.getConfig', empty, 15000, false);
      if (!this.alive || owner !== this.connection || owner.generationValue() !== generation) return;
      this.providers = providerCatalog(config, expected); this.observedGeneration = generation; this.mutationUnconfirmed = false;
      if (!this.selected()) this.selectedId = '';
      if (this.selectedId) this.watchAuth();
      this.notice = '已读取当前环境状态';
    } catch (_) { if (this.alive) this.error = '读取失败，请检查连接或权限后刷新'; }
    finally { if (this.alive) this.busy = false; }
  }
  private watchAuth(): void {
    this.stopWatch(); this.auth = undefined;
    const owner = this.connection; const id = this.selectedId; const generation = this.observedGeneration;
    const provider = this.selected();
    if (!owner || !provider || !provider.canAuthenticate || !provider.allowed || !provider.enabled || !provider.installed) return;
    this.timer = setTimeout(() => {
      this.timer = 0;
      if (this.alive && this.selectedId === id && !this.auth) this.error = '尚未收到登录状态，请刷新后重试';
    }, 15000) as number;
    this.streamOwner = owner;
    const payload: ProviderAuthIdentityPayload = { instanceId: id };
    this.stream = owner.watchRpcStream('provider.auth.subscribe', payload, (value: Object): void => {
      if (!this.alive || owner !== this.connection || this.selectedId !== id || owner.generationValue() !== generation) return;
      try {
        this.auth = providerAuthView(value, id); this.authRevision++;
        if (!this.mutationUnconfirmed) this.error = '';
        if (this.timer) clearTimeout(this.timer);
        this.timer = 0;
      } catch (_) { this.error = '登录状态不可识别，请在服务端核对'; }
    });
  }
  private choose(id: string): void {
    if (this.busy) return;
    this.selectedId = id; this.query = ''; this.error = ''; this.notice = ''; this.watchAuth();
  }
  private confirmLogin(): void {
    if (!this.manageable() || !this.auth || this.auth.phase === 'succeeded' || providerAuthActive(this.auth)) return;
    AlertDialog.show({ title: '开始登录？', message: '将在当前环境启动此 Provider 的登录流程。只有服务端确认后才会显示登录成功。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '开始登录', action: () => { void this.authAction('start'); } } });
  }
  private async authAction(action: string): Promise<void> {
    const owner = this.connection; const selected = this.selected(); const state = this.auth;
    if (!owner || !selected || !state || !this.manageable()) return;
    const id = selected.id; const generation = this.observedGeneration; const revision = this.authRevision;
    this.busy = true; this.error = '';
    try {
      let value: Object;
      if (action === 'start') {
        if (!selected.canAuthenticate || state.phase === 'succeeded' || providerAuthActive(state)) throw new Error('state');
        value = await owner.startProviderAuth(id);
      } else if (action === 'cancel') {
        if (!state.flowId) throw new Error('flow');
        const payload: ProviderAuthCancelPayload = { instanceId: id, flowId: state.flowId };
        value = await owner.rpcRequest('provider.auth.cancel', payload, 15000, false);
      } else {
        if (!providerAuthActive(state) || !state.flowId || !state.interactionId || state.type !== 'browser' || !state.requiresConsent) throw new Error('challenge');
        const payload: ProviderBrowserConsentPayload = { instanceId: id, flowId: state.flowId,
          interactionId: state.interactionId, response: { type: 'browser', action: 'accept' } };
        value = await owner.rpcRequest('provider.auth.respond', payload, 15000, false);
      }
      if (this.alive && this.connection === owner && this.selectedId === id && owner.generationValue() === generation && this.authRevision === revision) {
        this.auth = providerAuthView(value, id);
      }
    } catch (_) { if (this.alive) { this.mutationUnconfirmed = true; this.error = '登录操作未确认，不会自动重试；请刷新后核对状态'; } }
    finally { if (this.alive) this.busy = false; }
  }
  private async openLogin(): Promise<void> {
    const state = this.auth;
    if (!state || !state.url || !providerAuthActive(state) || state.requiresConsent || !this.manageable()) return;
    try { await (this.getUIContext().getHostContext() as common.UIAbilityContext).openLink(state.url); }
    catch (_) { this.error = '无法打开登录页面，请在服务端完成登录'; }
  }
  private visibleProviders(): ProviderView[] {
    const query = this.query.trim().toLowerCase();
    return this.providers.filter(item => (item.name + ' ' + item.driver).toLowerCase().includes(query));
  }
  private visibleModels(): ProviderModelView[] {
    const query = this.query.trim().toLowerCase();
    return (this.selected()?.models || []).filter(item => (item.name + ' ' + item.id).toLowerCase().includes(query));
  }
  build() {
    Column({ space: 0 }) {
      TopBar({
        title: this.selected() ? (this.selected()?.name || 'Provider') : 'Provider 与模型',
        showBack: true,
        backLabel: this.selected() ? '全部 Provider' : '返回设置',
        onBack: () => {
          if (this.busy) return;
          if (this.selected()) {
            this.stopWatch(); this.selectedId = ''; this.query = ''; this.auth = undefined;
          } else {
            this.onBack();
          }
        }
      }) {
        AppButton({
          label: '刷新',
          kind: 'text',
          disabled: this.busy,
          onTap: () => { void this.load(true); }
        })
      }
      Scroll() {
        Column({ space: 0 }) {
          if (this.error) {
            Text(this.error).fontSize(FontSize.callout).lineHeight(LineHeight.callout).fontColor($r('app.color.danger'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs }).width('100%')
          }
          if (this.notice) {
            Text(this.notice).fontSize(FontSize.callout).lineHeight(LineHeight.callout).fontColor($r('app.color.primary_text'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs }).width('100%')
          }
          if (this.busy) {
            Text('正在同步…').fontSize(FontSize.callout).fontColor($r('app.color.muted'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs }).width('100%')
          }
          if (this.connection?.canScope('providers:manage') === false) {
            Text('当前连接仅可查看 Provider，不能修改登录状态。')
              .fontSize(FontSize.callout).fontColor($r('app.color.muted'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs }).width('100%')
          }

          if (this.selected()) {
            GroupCard({
              title: '状态与认证',
              footnote: !this.auth && !this.selected()?.canAuthenticate ? '此 Provider 的登录由服务端管理。' : ''
            }) {
              Row({ space: Space.sm }) {
                Text('当前状态')
                  .fontSize(FontSize.body).lineHeight(LineHeight.body).fontWeight(Weight.regular)
                  .fontColor($r('app.color.ink')).layoutWeight(1)
                StatusBadge({
                  text: providerStatus(this.selected() as ProviderView),
                  tone: this.selected()?.authStatus === 'authenticated' ? 'success' : 'neutral'
                })
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
              .constraintSize({ minHeight: Sizes.formRowMin })
              .alignItems(VerticalAlign.Center)
              if (this.auth) {
                FormRow({ kind: 'multiline', label: '认证进度', value: providerAuthLabel(this.auth), valueMuted: true })
                if (this.auth.code && providerAuthActive(this.auth)) {
                  Column({ space: 2 }) {
                    Text('设备验证码').fontSize(FontSize.caption).fontColor($r('app.color.muted'))
                    Text(this.auth?.code || '').fontSize(FontSize.headline).fontWeight(Weight.semibold).fontFamily('monospace')
                      .fontColor($r('app.color.ink')).copyOption(CopyOptions.InApp)
                  }
                  .width('100%')
                  .alignItems(HorizontalAlign.Start)
                  .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
                  .constraintSize({ minHeight: Sizes.formRowMin })
                  .justifyContent(FlexAlign.Center)
                  .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
                }
                if (this.auth.type && !['browser', 'deviceCode'].includes(this.auth.type)) {
                  FormRow({
                    kind: 'multiline',
                    label: '操作说明',
                    value: '此登录方式需要终端或凭据输入，请在服务端或桌面客户端完成；此处仍可查看状态或取消流程。',
                    valueMuted: true
                  })
                }
              }
            }

            if (this.auth) {
              Column({ space: Space.xs }) {
                if (providerAuthActive(this.auth)) {
                  if (this.auth.requiresConsent) {
                    AppButton({
                      label: '同意继续登录', kind: 'primary', fill: true, disabled: !this.manageable(),
                      onTap: () => { void this.authAction('consent'); }
                    })
                  } else if (this.auth.url) {
                    AppButton({
                      label: '打开登录页面', kind: 'primary', fill: true, disabled: !this.manageable(),
                      onTap: () => { void this.openLogin(); }
                    })
                  }
                } else if (this.auth.phase !== 'succeeded' && this.selected()?.canAuthenticate && this.selected()?.authStatus !== 'authenticated') {
                  AppButton({
                    label: '登录', kind: 'primary', fill: true, disabled: !this.manageable(),
                    onTap: () => this.confirmLogin()
                  })
                }
                if (this.auth.flowId && ['starting', 'waiting', 'verifying'].includes(this.auth.phase)) {
                  AppButton({
                    label: '取消登录流程', kind: 'secondary', fill: true, disabled: !this.manageable(),
                    onTap: () => { void this.authAction('cancel'); }
                  })
                }
              }.width('100%').padding({ top: Space.sm })
            }

            Row({ space: Space.xs }) {
              Image($r('app.media.ui_search')).width(16).height(16).opacity(0.6).accessibilityLevel('no')
              TextInput({ text: this.query, placeholder: '搜索模型' })
                .layoutWeight(1).height(40).fontSize(FontSize.body).fontColor($r('app.color.ink'))
                .placeholderColor($r('app.color.placeholder')).backgroundColor(Color.Transparent).padding(0)
                .onChange(value => this.query = value)
            }
            .width('100%').padding({ left: Space.sm, right: Space.sm }).backgroundColor($r('app.color.card'))
            .borderRadius(Radius.button).margin({ top: Space.md, bottom: Space.xxs }).alignItems(VerticalAlign.Center)

            if (!this.visibleModels().length) {
              GroupCard({ title: '模型目录 · ' + String(this.selected()?.models.length || 0) }) {
                FormRow({ kind: 'value', label: '没有匹配的模型', value: '', valueMuted: true, chevron: false, isFirst: true })
              }
            } else {
              GroupCard({ title: '模型目录 · ' + String(this.selected()?.models.length || 0) }) {
                ForEach(this.visibleModels(), (model: ProviderModelView, index: number) => {
                  FormRow({ kind: 'value', label: model.name, subtitle: model.id, value: '', chevron: false, isFirst: index === 0 })
                }, (model: ProviderModelView) => model.id)
              }
            }
          } else {
            Text('当前环境的模型与账号状态。模型选择仍在新任务或会话的模型面板中进行。')
              .fontSize(FontSize.callout).lineHeight(LineHeight.callout).fontColor($r('app.color.muted'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs, bottom: Space.xs }).width('100%')
            Row({ space: Space.xs }) {
              Image($r('app.media.ui_search')).width(16).height(16).opacity(0.6).accessibilityLevel('no')
              TextInput({ text: this.query, placeholder: '搜索 Provider' })
                .layoutWeight(1).height(40).fontSize(FontSize.body).fontColor($r('app.color.ink'))
                .placeholderColor($r('app.color.placeholder')).backgroundColor(Color.Transparent).padding(0)
                .onChange(value => this.query = value)
            }
            .width('100%').padding({ left: Space.sm, right: Space.sm }).backgroundColor($r('app.color.card'))
            .borderRadius(Radius.button).margin({ bottom: Space.xxs }).alignItems(VerticalAlign.Center)

            if (!this.visibleProviders().length) {
              GroupCard() {
                FormRow({ kind: 'value', label: '没有匹配的 Provider', value: '', valueMuted: true, chevron: false, isFirst: true })
              }
            } else {
              GroupCard({ title: 'Providers' }) {
                ForEach(this.visibleProviders(), (provider: ProviderView, index: number) => {
                  Row({ space: Space.sm }) {
                    ProviderLogo({ driver: provider.driver || provider.id, logoSize: 18 })
                    Column({ space: 2 }) {
                      Text(provider.name)
                        .fontSize(FontSize.body).lineHeight(LineHeight.body).fontColor($r('app.color.ink'))
                        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(providerStatus(provider) + ' · ' + String(provider.models.length) + ' 个模型')
                        .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted'))
                        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                    }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                    Image($r('app.media.ui_chevron_right'))
                      .width(Sizes.chevron).height(Sizes.chevron).opacity(0.6).flexShrink(0).accessibilityLevel('no')
                  }
                  .width('100%').constraintSize({ minHeight: Sizes.formRowMin })
                  .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
                  .alignItems(VerticalAlign.Center)
                  .border({ width: { top: index === 0 ? 0 : Sizes.hairline }, color: { top: $r('app.color.separator') } })
                  .enabled(!this.busy)
                  .opacity(this.busy ? Opacity.disabled : 1)
                  .accessibilityGroup(true)
                  .accessibilityText(provider.name + '，' + providerStatus(provider) + '，' + String(provider.models.length) + ' 个模型')
                  .onClick(() => { if (!this.busy) this.choose(provider.id); })
                }, (provider: ProviderView) => provider.id)
              }
            }
          }
        }.width('100%').padding({ left: Space.sm, right: Space.sm, bottom: Space.lg }).alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1).align(Alignment.TopStart).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
  }
}
