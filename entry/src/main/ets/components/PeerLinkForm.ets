import { TopBar } from './ui/TopBar';
import { GroupCard } from './ui/GroupCard';
import { FormRow } from './ui/FormRow';
import { AppButton } from './ui/AppButton';
import { FontSize, LineHeight, Sizes, Space } from '../common/Theme';
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
    Column({ space: 0 }) {
      TopBar({
        title: '链接 ' + (this.target().label || '一台机器'),
        showBack: true,
        closeStyle: true,
        backLabel: '关闭链接请求',
        onBack: () => { if (!this.busy) this.onClose(); }
      })
      Scroll() {
        Column({ space: 0 }) {
          Text('此环境的 Agent 可在目标环境启动、发送和等待会话。可在目标环境的共享与访问设置中撤销授权。')
            .fontSize(FontSize.callout).lineHeight(LineHeight.callout).fontColor($r('app.color.muted'))
            .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs }).width('100%')

          if (!this.request.url && !this.request.environmentId) {
            GroupCard({ title: '选择机器' }) {
              ForEach(this.machines, (machine: LinkMachine, index: number) => {
                FormRow({
                  kind: 'choice',
                  label: machine.label,
                  subtitle: machine.linked ? '已链接' : machine.connected ? '已连接' : '未连接',
                  checked: this.selected() === machine.environmentId,
                  disabled: this.busy,
                  isFirst: index === 0,
                  onTap: () => { this.choice = machine.environmentId; this.error = ''; void this.refreshMintPermission(); }
                })
              }, (machine: LinkMachine) => machine.environmentId)
              FormRow({
                kind: 'choice',
                label: '另一地址…',
                checked: this.selected() === 'another-address',
                disabled: this.busy,
                isFirst: this.machines.length === 0,
                onTap: () => { this.choice = 'another-address'; this.error = ''; void this.refreshMintPermission(); }
              })
            }
          }

          if ((this.needsAddress() && !this.request.url) || (!this.useExisting() && this.target().kind !== 'none' && !this.canMint) ||
            (this.needsAddress() && this.address.trim() && !this.useExisting())) {
            GroupCard({
              title: '连接目标',
              footnote: (!this.useExisting() && this.target().kind !== 'none' && !this.canMint)
                ? '在目标环境的共享与访问 → 已授权客户端中创建链接，然后在此粘贴配对码。' : ''
            }) {
              if (this.needsAddress() && !this.request.url) {
                Column() {
                  Row({ space: 10 }) {
                    Text('地址').fontSize(FontSize.body).fontColor($r('app.color.ink')).width(64).flexShrink(0)
                    TextInput({ text: this.address, placeholder: 'https://machine.tailnet.ts.net' })
                      .layoutWeight(1).height(40).fontSize(FontSize.body).fontColor($r('app.color.ink'))
                      .placeholderColor($r('app.color.placeholder')).backgroundColor(Color.Transparent).padding(0)
                      .enabled(!this.busy).accessibilityText('链接目标地址').onChange((value: string) => this.address = value)
                  }.width('100%').alignItems(VerticalAlign.Center)
                }
                .width('100%')
                .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
                .constraintSize({ minHeight: Sizes.formRowMin })
                .justifyContent(FlexAlign.Center)
              }
              if (this.needsAddress() && this.address.trim() && !this.useExisting()) {
                FormRow({
                  kind: 'multiline',
                  label: '请核对地址：本应用无法确认这是你的机器，粘贴的配对码会发送到此处',
                  value: linkOrigin(this.address) || '无效地址',
                  valueMuted: true,
                  isFirst: !(!this.request.url && this.needsAddress())
                })
              }
              if (!this.useExisting() && this.target().kind !== 'none' && !this.canMint) {
                Column() {
                  Row({ space: 10 }) {
                    Text('配对码').fontSize(FontSize.body).fontColor($r('app.color.ink')).width(64).flexShrink(0)
                    TextInput({ text: this.code, placeholder: '粘贴目标环境的配对码' })
                      .layoutWeight(1).height(40).fontSize(FontSize.body).fontColor($r('app.color.ink'))
                      .placeholderColor($r('app.color.placeholder')).backgroundColor(Color.Transparent).padding(0)
                      .type(InputType.Password).enableAutoFill(false)
                      .enabled(!this.busy).accessibilityText('环境链接配对码').onChange((value: string) => this.code = value)
                  }.width('100%').alignItems(VerticalAlign.Center)
                }
                .width('100%')
                .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
                .constraintSize({ minHeight: Sizes.formRowMin })
                .justifyContent(FlexAlign.Center)
                .border({ width: { top: !this.needsAddress() ? 0 : Sizes.hairline }, color: { top: $r('app.color.separator') } })
              }
            }
          }

          if (this.useExisting()) {
            GroupCard() {
              FormRow({
                kind: 'multiline',
                label: '现有链接',
                value: '该环境已有可用链接，将按现有权限交给 Agent 使用。更改权限请到环境设置。',
                valueMuted: true,
                isFirst: true
              })
            }
          } else if (this.target().kind !== 'none') {
            GroupCard({
              title: 'Agent 在目标环境的权限',
              footnote: '目标环境的权限也不会高于 Agent 在当前环境的模式；它启动的会话不能改动目标环境已有的会话、项目或设置。'
            }) {
              ForEach(linkAccessChoices, (option: LinkAccessChoice, index: number) => {
                FormRow({
                  kind: 'choice',
                  label: option.label,
                  subtitle: option.description,
                  checked: this.access === option.value,
                  disabled: this.busy,
                  isFirst: index === 0,
                  onTap: () => { this.access = option.value; }
                })
              }, (option: LinkAccessChoice) => option.value)
            }
          }

          if (this.error) {
            Text(this.error).fontSize(FontSize.callout).lineHeight(LineHeight.callout).fontColor($r('app.color.danger'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.sm }).width('100%')
          }

          Column({ space: Space.xs }) {
            AppButton({
              label: this.busy ? '链接中…' : this.useExisting() ? '使用现有链接' : '链接',
              kind: 'primary',
              fill: true,
              loading: this.busy,
              disabled: !this.canSubmit(),
              onTap: () => { void this.submit(); }
            })
            AppButton({
              label: '取消',
              kind: 'secondary',
              fill: true,
              disabled: this.busy,
              onTap: () => this.onClose()
            })
          }.width('100%').padding({ top: Space.md })
        }.width('100%').padding({ left: Space.sm, right: Space.sm, bottom: Space.lg }).alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1)
    }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
  }
}
