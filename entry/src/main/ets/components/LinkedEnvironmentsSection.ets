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
    Column({ space: 12 }) {
      ForEach(this.groups.filter((group: LinkedEnvironmentGroup) => group.links.length > 0), (group: LinkedEnvironmentGroup) => {
        Column({ space: 0 }) {
          Text('从 ' + group.label + ' 链接的环境').fontSize(14).fontWeight(FontWeight.Medium).width('100%').padding({ bottom: 8 })
          ForEach(group.links, (link: PeerLinkView) => {
            Column({ space: 4 }) {
              Text(link.label).fontSize(16).fontWeight(FontWeight.Medium).maxLines(1).width('100%')
              Text(peerLinkStatus(link, this.now)).fontSize(12).maxLines(2).width('100%')
                .fontColor(link.status === 'reachable' && link.lastError === undefined && link.expiresAt - this.now > 5 * 86400000 ? $r('app.color.muted') : $r('app.color.danger'))
            }.padding(16).width('100%').alignItems(HorizontalAlign.Start)
          }, (link: PeerLinkView) => link.environmentId)
        }.width('100%').alignItems(HorizontalAlign.Start)
      }, (group: LinkedEnvironmentGroup) => group.localId)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
