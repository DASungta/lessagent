import { GroupCard } from './ui/GroupCard';
import { FontSize, LineHeight, Sizes, Space, Weight } from '../common/Theme';
import { PeerLinkView, peerLinkStatus } from '../protocol/Core';
export interface LinkedEnvironmentGroup { localId: string; label: string; links: PeerLinkView[]; }

@Component
export struct LinkedEnvironmentsSection {
  @Prop @Watch('refreshClock') groups: LinkedEnvironmentGroup[] = [];
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
            Column({ space: 2 }) {
              Text(link.label).fontSize(FontSize.body).lineHeight(LineHeight.body).fontWeight(Weight.medium)
                .fontColor($r('app.color.ink')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
              Text(peerLinkStatus(link, this.now)).fontSize(FontSize.caption).lineHeight(LineHeight.caption)
                .maxLines(2).width('100%')
                .fontColor(link.status === 'reachable' && link.lastError === undefined && link.expiresAt - this.now > 5 * 86400000
                  ? $r('app.color.muted') : $r('app.color.danger'))
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
            .constraintSize({ minHeight: Sizes.formRowMin })
            .justifyContent(FlexAlign.Center)
            .border({ width: { top: index === 0 ? 0 : Sizes.hairline }, color: { top: $r('app.color.separator') } })
          }, (link: PeerLinkView) => link.environmentId)
        }
      }, (group: LinkedEnvironmentGroup) => group.localId)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
