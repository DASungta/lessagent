import { common } from '@kit.AbilityKit';
import { T3Client } from '../services/T3Client';
import { record } from '../protocol/Wire';
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
      const expected = record(owner.config.environment).environmentId;
      if (typeof expected !== 'string' || (this.environmentId && expected !== this.environmentId)) throw new Error('identity');
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
      Row({ space: 8 }) {
        Button({ type: ButtonType.Normal }) { Image($r('app.media.ui_back')).width(22).height(22) }
          .width(44).height(44).backgroundColor(Color.Transparent).accessibilityText('返回')
          .enabled(!this.busy).onClick(this.onBack)
        Text('Provider 与模型').fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button('刷新').backgroundColor(Color.Transparent).fontColor($r('app.color.primary')).enabled(!this.busy)
          .onClick(() => { void this.load(true); })
      }.width('100%').padding(8)
      Scroll() {
        Column({ space: 14 }) {
          if (this.error) { Text(this.error).fontSize(14).width('100%') }
          if (this.notice) { Text(this.notice).fontSize(13).fontColor($r('app.color.muted')).width('100%') }
          if (this.busy) { Text('正在同步…').fontSize(14).width('100%') }
          if (this.connection?.canScope('providers:manage') === false) {
            Text('当前连接仅可查看 Provider，不能修改登录状态。').fontSize(13).fontColor($r('app.color.muted')).width('100%')
          }
          if (this.selected()) {
            Button('全部 Provider').backgroundColor(Color.Transparent).fontColor($r('app.color.primary'))
              .enabled(!this.busy).onClick(() => { this.stopWatch(); this.selectedId = ''; this.query = ''; this.auth = undefined; })
            Text(this.selected()?.name || '').fontSize(20).fontWeight(FontWeight.Medium).width('100%')
            Text(providerStatus(this.selected() as ProviderView)).fontSize(15).width('100%')
            if (this.auth) {
              Text(providerAuthLabel(this.auth)).fontSize(14).width('100%')
              if (this.auth.code && providerAuthActive(this.auth)) {
                Text('设备验证码：' + this.auth.code).fontSize(18).fontWeight(FontWeight.Medium).width('100%')
              }
              if (this.auth.type && !['browser', 'deviceCode'].includes(this.auth.type)) {
                Text('此登录方式需要终端或凭据输入，请在服务端或桌面客户端完成；此处仍可查看状态或取消流程。')
                  .fontSize(13).lineHeight('20fp').fontColor($r('app.color.muted')).width('100%')
              }
              if (providerAuthActive(this.auth)) {
                if (this.auth.requiresConsent) {
                  Button('同意继续登录').width('100%').fontColor(Color.White).backgroundColor($r('app.color.primary'))
                    .enabled(this.manageable()).onClick(() => { void this.authAction('consent'); })
                } else if (this.auth.url) {
                  Button('打开登录页面').width('100%').fontColor(Color.White).backgroundColor($r('app.color.primary'))
                    .enabled(this.manageable()).onClick(() => { void this.openLogin(); })
                }
              } else if (this.auth.phase !== 'succeeded' && this.selected()?.canAuthenticate && this.selected()?.authStatus !== 'authenticated') {
                Button('登录').width('100%').fontColor(Color.White).backgroundColor($r('app.color.primary'))
                  .enabled(this.manageable()).onClick(() => this.confirmLogin())
              }
              if (this.auth.flowId && ['starting', 'waiting', 'verifying'].includes(this.auth.phase)) {
                Button('取消登录流程').width('100%').fontColor($r('app.color.ink')).backgroundColor($r('app.color.surface'))
                  .enabled(this.manageable()).onClick(() => { void this.authAction('cancel'); })
              }
            } else if (!this.selected()?.canAuthenticate) {
              Text('此 Provider 的登录由服务端管理。').fontSize(13).fontColor($r('app.color.muted')).width('100%')
            }
            Text('模型目录 · ' + String(this.selected()?.models.length || 0)).fontSize(15).width('100%')
            TextInput({ text: this.query, placeholder: '搜索模型' }).onChange(value => this.query = value)
              .backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).height(44)
            ForEach(this.visibleModels(), (model: ProviderModelView) => {
              Column({ space: 3 }) {
                Text(model.name).fontSize(15).width('100%')
                Text(model.id).fontSize(12).fontColor($r('app.color.muted')).width('100%')
              }.width('100%').padding(14).backgroundColor($r('app.color.surface')).borderRadius(12)
            }, (model: ProviderModelView) => model.id)
            if (!this.visibleModels().length) { Text('没有匹配的模型').fontSize(14).fontColor($r('app.color.muted')) }
          } else {
            Text('当前环境的模型与账号状态。模型选择仍在新任务或会话的模型面板中进行。')
              .fontSize(13).lineHeight('20fp').fontColor($r('app.color.muted')).width('100%')
            TextInput({ text: this.query, placeholder: '搜索 Provider' }).onChange(value => this.query = value)
              .backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).height(44)
            ForEach(this.visibleProviders(), (provider: ProviderView) => {
              Button({ type: ButtonType.Normal }) {
                Column({ space: 5 }) {
                  Text(provider.name).fontSize(16).fontWeight(FontWeight.Medium).width('100%')
                  Text(providerStatus(provider) + ' · ' + String(provider.models.length) + ' 个模型')
                    .fontSize(13).fontColor($r('app.color.muted')).width('100%')
                }.width('100%').padding(16)
              }.width('100%').backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).borderRadius(14)
                .enabled(!this.busy).onClick(() => this.choose(provider.id))
            }, (provider: ProviderView) => provider.id)
            if (!this.visibleProviders().length) { Text('没有匹配的 Provider').fontSize(14).fontColor($r('app.color.muted')) }
          }
        }.width('100%').padding(16).alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1).align(Alignment.TopStart)
    }.width('100%').height('100%').backgroundColor($r('app.color.canvas')).foregroundColor($r('app.color.ink'))
  }
}
