import { GroupCard } from './ui/GroupCard';
import { AppButton } from './ui/AppButton';
import { FontSize, LineHeight, Sizes, Space, Weight } from '../common/Theme';
import { PeerLinkView, peerLinkStatus } from '../protocol/Core';
export interface LinkedEnvironmentGroup { localId: string; label: string; links: PeerLinkView[]; }

@Component
export struct LinkedEnvironmentsSection {
  @Prop @Watch('refreshClock') groups: LinkedEnvironmentGroup[] = [];
  @Prop busy: boolean = false;
  onRemoveLink: (sourceLocalId: string, targetEnvironmentId: string, targetLabel: string) => void = () => {};
  @StorageLink('t3Foreground') @Watch('refreshClock') foreground: boolean = true;
  @State now: number = Date.now();
  private timer: number = 0;
  private refreshClock(): void {
    this.now = Date.now(); clearInterval(this.timer); this.timer = 0;
    if (this.foreground && this.groups.some((group: LinkedEnvironmentGroup) => group.links.length > 0)) {
      this.timer = setInterval(() => { this.now = Date.now(); }, 60000);
    }
  }
  aboutToAppear(): void { this.refreshClock(); }
  aboutToDisappear(): void { clearInterval(this.timer); }
  build() {
    Column({ space: 0 }) {
      ForEach(this.groups.filter((group: LinkedEnvironmentGroup) => group.links.length > 0), (group: LinkedEnvironmentGroup) => {
        GroupCard({ title: '从 ' + group.label + ' 链接的环境' }) {
          ForEach(group.links, (link: PeerLinkView, index: number) => {
            Row({ space: Space.xs }) {
              Column({ space: 2 }) {
                Text(link.label).fontSize(FontSize.body).lineHeight(LineHeight.body).fontWeight(Weight.medium)
                  .fontColor($r('app.color.ink')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                Text(peerLinkStatus(link, this.now)).fontSize(FontSize.caption).lineHeight(LineHeight.caption)
                  .maxLines(2).width('100%')
                  .fontColor(link.status === 'reachable' && link.lastError === undefined && link.expiresAt - this.now > 5 * 86400000
                    ? $r('app.color.muted') : $r('app.color.danger'))
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              AppButton({
                label: '解除',
                kind: 'danger',
                compact: true,
                disabled: this.busy,
                a11yLabel: '解除链接 ' + link.label,
                onTap: () => {
                  AlertDialog.show({
                    title: '解除环境互链？',
                    message: '将从「' + group.label + '」移除到「' + link.label + '」的链接，并尝试结束对端会话。',
                    primaryButton: { value: '取消', action: () => {} },
                    secondaryButton: {
                      value: '解除',
                      action: () => { this.onRemoveLink(group.localId, link.environmentId, link.label); }
                    }
                  });
                }
              })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
            .constraintSize({ minHeight: Sizes.formRowMin })
            .border({ width: { top: index === 0 ? 0 : Sizes.hairline }, color: { top: $r('app.color.separator') } })
          }, (link: PeerLinkView) => link.environmentId)
        }
      }, (group: LinkedEnvironmentGroup) => group.localId)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
