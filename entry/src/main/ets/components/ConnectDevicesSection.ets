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
      Column({ space: 8 }) {
        Text('T3 Connect 设备 · ' + this.environmentLabel).fontSize(14).fontWeight(FontWeight.Medium).width('100%')
        ForEach(this.pending, (link: CloudPairingLink) => {
          Column({ space: 6 }) {
            Text(link.clientLabel || link.clientBrowser || link.clientOs || '新设备').fontSize(15).width('100%')
            Text('验证码 ' + link.verificationCode + ' · 等待批准').fontSize(12).fontColor($r('app.color.muted')).width('100%')
            Row({ space: 8 }) {
              Button('拒绝').enabled(!this.busy).onClick(() => void this.act(() => this.onDeny(link.id)))
              Button('批准').enabled(!this.busy).onClick(() => void this.act(() => this.onApprove(link.id)))
            }.width('100%')
          }.width('100%').padding(10).backgroundColor($r('app.color.canvas')).borderRadius(8)
        }, (link: CloudPairingLink) => link.id)
        ForEach(this.devices, (device: CloudDevice) => {
          Row({ space: 8 }) {
            Column({ space: 3 }) {
              Text(device.label).fontSize(14).width('100%')
              Text('验证码 ' + device.verificationCode).fontSize(12).fontColor($r('app.color.muted')).width('100%')
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Button('撤销').fontSize(12).backgroundColor(Color.Transparent).fontColor($r('app.color.danger'))
              .enabled(!this.busy).onClick(() => {
                AlertDialog.show({ title: '撤销设备？', message: '此设备将无法继续通过 T3 Connect 连接当前环境。',
                  primaryButton: { value: '取消', action: () => {} },
                  secondaryButton: { value: '撤销', action: () => { void this.act(() => this.onRevoke(device.proofKeyThumbprint)); } } });
              })
          }.width('100%').padding(10).backgroundColor($r('app.color.canvas')).borderRadius(8)
        }, (device: CloudDevice) => device.proofKeyThumbprint)
      }.width('100%').alignItems(HorizontalAlign.Start)
    }
  }
}
