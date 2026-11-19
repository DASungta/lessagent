import { LinkRequestView, LinkAnswer, linkAccessChoices, LinkAccessChoice } from '../protocol/Core';
import { LinkMachine, LinkTarget, resolveLinkTarget, initialLinkMachine, linkOrigin } from '../protocol/LinkTarget';
import { T3Client } from '../services/T3Client';
import { environments } from '../services/EnvironmentRegistry';

@Component
export struct PeerLinkForm {
  @Prop request: LinkRequestView;
  @Prop @Watch('refreshMintPermission') machines: LinkMachine[] = [];
  connection: T3Client | undefined = undefined;
  onBusy: (busy: boolean) => void = () => {};
  onClose: () => void = () => {};
  @StorageLink('t3Foreground') @Watch('clearPrivateCode') foreground: boolean = true;
  @State choice: string = '';
  @State address: string = '';
  @State access: string = 'approval-required';
  @State code: string = '';
  @State busy: boolean = false;
  @State error: string = '';
  @State canMint: boolean = false;
  private failedMint: string[] = [];
  private permissionGeneration: number = 0;
  aboutToAppear(): void {
    this.address = this.request.url;
    this.access = this.request.access; void this.refreshMintPermission();
  }
  aboutToDisappear(): void { this.code = ''; this.permissionGeneration++; }
  private clearPrivateCode(): void { if (!this.foreground) this.code = ''; }
  private selected(): string { return this.choice || initialLinkMachine(this.request, this.machines); }
  private target(): LinkTarget { return resolveLinkTarget(this.request, this.machines, this.selected()); }
  private canSubmit(): boolean {
    if (!this.connection?.ready || this.connection.mutationPending || !this.connection.canManagePeerAccess()) return false;
    return this.target().kind !== 'none' && (this.useExisting() || ((!this.needsAddress() || !!linkOrigin(this.address)) && (this.canMint || !!this.code.trim())));
  }
  private needsAddress(): boolean { const target = this.target(); return target.kind === 'address' || (target.kind === 'machine' && !target.urls.length); }
  private useExisting(): boolean { const target = this.target(); return target.kind === 'machine' && target.linked; }
  private async refreshMintPermission(): Promise<void> {
    const generation = ++this.permissionGeneration; this.canMint = false;
    const target = this.target();
    const connection = environments?.clients.get(target.localId);
    if (!connection?.ready || this.needsAddress() || this.failedMint.includes(target.localId)) return;
    try {
      await connection.refreshPeerAccess();
      if (generation === this.permissionGeneration) this.canMint = connection.canManagePeerAccess();
    } catch (_) {}
  }
  private async submit(): Promise<void> {
    if (this.busy || !this.canSubmit()) return;
    this.busy = true; this.onBusy(true); this.error = '';
    try {
      const target = this.target(); let answer: LinkAnswer;
      if (this.useExisting()) answer = { type: 'use-existing', environmentId: target.environmentId };
      else {
        let code = this.code;
        if (this.canMint) {
          try {
            const connection = environments?.clients.get(target.localId);
            if (!connection) throw new Error('missing');
            code = await connection.mintPeerPairingCode(this.access);
          } catch (_) {
            this.failedMint.push(target.localId); this.canMint = false;
            this.error = '无法获取配对码，请从该环境获取后粘贴。'; return;
          }
        }
        const urls = this.needsAddress() ? [linkOrigin(this.address)] : target.urls;
        if (!urls.length || urls.some((base: string) => !base)) throw new Error('invalid');
        answer = { type: 'link', urls, access: this.access, pairingCode: code };
        if (!this.needsAddress() && target.kind === 'machine') { answer.environmentId = target.environmentId; answer.label = target.label; }
      }
      const source = this.connection; if (!source) throw new Error('missing source');
      await source.answerLinkRequest(this.request.id, answer);
      this.code = ''; this.onClose();
    } catch (_) { this.error = '无法完成链接，请同步请求状态后重试。配对码不会自动重发。'; }
    finally { this.busy = false; this.onBusy(false); }
  }
  build() {
    Column({ space: 12 }) {
      Row() {
        Text('链接 ' + (this.target().label || '一台机器')).fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button('×').width(44).height(44).backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
          .accessibilityText('关闭链接请求').enabled(!this.busy).onClick(this.onClose)
      }.width('100%')
      Scroll() {
        Column({ space: 16 }) {
          Text('此环境的 Agent 可在目标环境启动、发送和等待会话。可在目标环境的共享与访问设置中撤销授权。').fontSize(14).width('100%')
          if (!this.request.url && !this.request.environmentId) {
            Text('选择机器').fontSize(14).width('100%')
            ForEach(this.machines, (machine: LinkMachine) => {
              Button((this.selected() === machine.environmentId ? '✓ ' : '') + machine.label + (machine.linked ? ' · 已链接' : machine.connected ? '' : ' · 未连接'))
                .width('100%').enabled(!this.busy).onClick(() => { this.choice = machine.environmentId; this.error = ''; void this.refreshMintPermission(); })
            }, (machine: LinkMachine) => machine.environmentId)
            Button((this.selected() === 'another-address' ? '✓ ' : '') + '另一地址…').width('100%').enabled(!this.busy)
              .onClick(() => { this.choice = 'another-address'; this.error = ''; void this.refreshMintPermission(); })
          }
          if (this.needsAddress() && this.address.trim() && !this.useExisting()) {
            Text('请核对地址：本应用无法确认这是你的机器，粘贴的配对码会发送到此处。').fontSize(14).width('100%')
            Text(linkOrigin(this.address) || '无效地址').fontSize(13).width('100%').copyOption(CopyOptions.InApp)
          }
          if (this.needsAddress() && !this.request.url) {
            TextInput({ text: this.address, placeholder: 'https://machine.tailnet.ts.net' }).enabled(!this.busy)
              .accessibilityText('链接目标地址').onChange((value: string) => this.address = value)
          }
          if (this.useExisting()) {
            Text('该环境已有可用链接，将按现有权限交给 Agent 使用。更改权限请到环境设置。').fontSize(14).width('100%')
          } else if (this.target().kind !== 'none') {
            if (!this.canMint) {
              TextInput({ text: this.code, placeholder: '粘贴目标环境的配对码' }).type(InputType.Password).enableAutoFill(false)
                .enabled(!this.busy).accessibilityText('环境链接配对码').onChange((value: string) => this.code = value)
              Text('在目标环境的共享与访问 → 已授权客户端中创建链接，然后在此粘贴配对码。').fontSize(13).width('100%')
            }
            Text('Agent 在目标环境的权限').fontSize(14).width('100%')
            ForEach(linkAccessChoices, (option: LinkAccessChoice) => {
              Button({ type: ButtonType.Normal }) {
                Column({ space: 4 }) {
                  Text((this.access === option.value ? '✓ ' : '') + option.label).fontSize(15).width('100%')
                  Text(option.description).fontSize(13).fontColor($r('app.color.muted')).width('100%')
                }.padding(12).width('100%').alignItems(HorizontalAlign.Start)
              }.width('100%').backgroundColor(this.access === option.value ? $r('app.color.selected') : $r('app.color.surface'))
                .fontColor($r('app.color.ink')).enabled(!this.busy).onClick(() => this.access = option.value)
            }, (option: LinkAccessChoice) => option.value)
            Text('目标环境的权限也不会高于 Agent 在当前环境的模式；它启动的会话不能改动目标环境已有的会话、项目或设置。').fontSize(13).width('100%')
          }
          if (this.error) { Text(this.error).fontSize(13).fontColor($r('app.color.danger')).width('100%') }
          Button(this.busy ? '链接中…' : this.useExisting() ? '使用现有链接' : '链接').width('100%').enabled(!this.busy && this.canSubmit()).onClick(() => this.submit())
          Button('取消').width('100%').enabled(!this.busy).onClick(this.onClose)
        }.width('100%').padding({ bottom: 20 }).alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1)
    }.width('100%').height('100%').padding(24).foregroundColor($r('app.color.ink'))
  }
}
