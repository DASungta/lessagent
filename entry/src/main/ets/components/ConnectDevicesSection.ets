import { GroupCard } from './ui/GroupCard';
import { AppButton } from './ui/AppButton';
import { StatusBadge } from './ui/StatusBadge';
import { FontSize, LineHeight, Sizes, Space, Weight } from '../common/Theme';
import { CloudDevice, CloudPairingLink } from '../protocol/Cloud';

@Component
export struct ConnectDevicesSection {
  @Prop environmentLabel: string = '';
  @Prop pending: CloudPairingLink[] = [];
  @Prop devices: CloudDevice[] = [];
  @Prop busy: boolean = false;
  onApprove: (pairingLinkId: string) => Promise<void> = async () => {};
  onDeny: (pairingLinkId: string) => Promise<void> = async () => {};
  onRevoke: (proofKeyThumbprint: string) => Promise<void> = async () => {};

  private async act(action: () => Promise<void>): Promise<void> {
    if (this.busy) return;
    try { await action(); } catch (_) {}
  }

  build() {
    if (this.pending.length > 0 || this.devices.length > 0) {
      GroupCard({ title: 'T3 Connect 设备 · ' + this.environmentLabel }) {
        ForEach(this.pending, (link: CloudPairingLink, index: number) => {
          Column({ space: Space.xs }) {
            Row({ space: Space.xs }) {
              Column({ space: 2 }) {
                Text(link.clientLabel || link.clientBrowser || link.clientOs || '新设备')
                  .fontSize(FontSize.body).lineHeight(LineHeight.body).fontWeight(Weight.medium).fontColor($r('app.color.ink')).width('100%')
                Text('验证码 ' + link.verificationCode).fontSize(FontSize.caption).fontColor($r('app.color.muted')).width('100%')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              StatusBadge({ text: '等待批准', tone: 'warning' })
            }.width('100%').alignItems(VerticalAlign.Center)
            Row({ space: Space.xs }) {
              AppButton({
                label: '拒绝', kind: 'secondary', compact: true, disabled: this.busy,
                onTap: () => { void this.act(() => this.onDeny(link.id)); }
              })
              AppButton({
                label: '批准', kind: 'confirm', compact: true, disabled: this.busy,
                onTap: () => { void this.act(() => this.onApprove(link.id)); }
              })
            }.width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
          .constraintSize({ minHeight: Sizes.formRowMin })
          .justifyContent(FlexAlign.Center)
          .border({ width: { top: index === 0 ? 0 : Sizes.hairline }, color: { top: $r('app.color.separator') } })
        }, (link: CloudPairingLink) => link.id)
        ForEach(this.devices, (device: CloudDevice, index: number) => {
          Row({ space: Space.sm }) {
            Column({ space: 2 }) {
              Text(device.label).fontSize(FontSize.body).lineHeight(LineHeight.body).fontWeight(Weight.regular)
                .fontColor($r('app.color.ink')).width('100%')
              Text('验证码 ' + device.verificationCode).fontSize(FontSize.caption).lineHeight(LineHeight.caption)
                .fontColor($r('app.color.muted')).width('100%')
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            AppButton({
              label: '撤销',
              kind: 'danger',
              compact: true,
              disabled: this.busy,
              onTap: () => {
                AlertDialog.show({
                  title: '撤销设备？',
                  message: '此设备将无法继续通过 T3 Connect 连接当前环境。',
                  primaryButton: { value: '取消', action: () => {} },
                  secondaryButton: { value: '撤销', action: () => { void this.act(() => this.onRevoke(device.proofKeyThumbprint)); } }
                });
              }
            })
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
          .constraintSize({ minHeight: Sizes.formRowMin })
          .alignItems(VerticalAlign.Center)
          .border({ width: { top: (this.pending.length === 0 && index === 0) ? 0 : Sizes.hairline }, color: { top: $r('app.color.separator') } })
        }, (device: CloudDevice) => device.proofKeyThumbprint)
      }
    }
  }
}
