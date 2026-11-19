import { EnvironmentEntry } from '../protocol/Environment';
import { ArchiveProjectGroup, ScopedThread, relativeTime } from '../protocol/Projects';

@Component
export struct ArchivePanel {
  @Prop groups: ArchiveProjectGroup[] = [];
  @Prop environments: EnvironmentEntry[] = [];
  @Prop environmentId: string = '';
  @Prop query: string = '';
  @Prop sortOrder: string = 'newest';
  @Prop loading: boolean = false;
  @Prop busy: boolean = false;
  @Prop nowMs: number = Date.now();
  onBack: () => void = () => {};
  onEnvironment: (environmentId: string) => void = () => {};
  onQuery: (value: string) => void = () => {};
  onSort: (value: string) => void = () => {};
  onRefresh: () => void = () => {};
  onOpen: (thread: ScopedThread) => void = () => {};
  onUnarchive: (thread: ScopedThread) => void = () => {};
  onDelete: (thread: ScopedThread) => void = () => {};

  @Builder
  row(thread: ScopedThread) {
    Row({ space: 10 }) {
      Text('▣').fontSize(18).fontColor($r('app.color.muted'))
      Column({ space: 4 }) {
        Text(thread.label).fontSize(15).fontWeight(FontWeight.Medium).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        Text([thread.environmentLabel, thread.branch].filter((value: string) => !!value).join(' · '))
          .fontSize(11).fontColor($r('app.color.muted')).maxLines(1).width('100%')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text(relativeTime(thread.archivedAt || thread.updatedAt, this.nowMs))
        .fontSize(11).fontColor($r('app.color.muted'))
    }.width('100%').padding({ left: 18, right: 14, top: 12, bottom: 12 })
      .onClick(() => this.onOpen(thread))
      .bindContextMenu(this.menu(thread), ResponseType.LongPress)
  }
  @Builder
  menu(thread: ScopedThread) {
    Menu() {
      MenuItem({ content: '取消归档' }).onClick(() => this.onUnarchive(thread))
      MenuItem({ content: '删除…' }).onClick(() => this.onDelete(thread))
    }
  }
  @Builder
  swipe(thread: ScopedThread) {
    Row() {
      Column({ space: 2 }) {
        Text('↶').fontSize(18).fontColor($r('app.color.ink'))
        Text('恢复').fontSize(10).fontColor($r('app.color.ink'))
      }.width(64).height('100%').justifyContent(FlexAlign.Center).backgroundColor($r('app.color.surface'))
        .onClick(() => this.onUnarchive(thread))
      Column({ space: 2 }) {
        Text('×').fontSize(18).fontColor($r('app.color.on_primary'))
        Text('删除').fontSize(10).fontColor($r('app.color.on_primary'))
      }.width(64).height('100%').justifyContent(FlexAlign.Center).backgroundColor($r('app.color.danger'))
        .onClick(() => this.onDelete(thread))
    }.height('100%')
  }

  build() {
    Column({ space: 0 }) {
      Row({ space: 6 }) {
        Button('‹').width(44).height(44).backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
          .fontSize(26).accessibilityText('返回设置').onClick(this.onBack)
        Text('归档会话').fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button('刷新').height(36).backgroundColor(Color.Transparent).fontColor($r('app.color.primary'))
          .onClick(this.onRefresh)
      }.width('100%').padding({ left: 8, right: 12, top: 8, bottom: 4 })
      Row({ space: 8 }) {
        Select([{ value: '所有环境' } as SelectOption].concat(this.environments.map((entry: EnvironmentEntry) => {
          return { value: entry.label } as SelectOption;
        }))).value(this.environments.find((entry: EnvironmentEntry) => entry.environmentId === this.environmentId)?.label || '所有环境')
          .height(36).font({ size: 12 }).backgroundColor($r('app.color.surface'))
          .onSelect((index: number) => this.onEnvironment(index === 0 ? '' : (this.environments[index - 1]?.environmentId || '')))
        TextInput({ placeholder: '搜索归档会话', text: this.query }).layoutWeight(1).height(38)
          .fontSize(13).backgroundColor($r('app.color.surface')).borderRadius(19)
          .onChange((value: string) => this.onQuery(value)).accessibilityText('搜索归档会话')
        Button(this.sortOrder === 'oldest' ? '最早' : '最新').height(36).fontSize(12)
          .backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink'))
          .onClick(() => this.onSort(this.sortOrder === 'oldest' ? 'newest' : 'oldest'))
      }.width('100%').padding({ left: 16, right: 16, bottom: 8 })
      if (this.loading) {
        Row({ space: 8 }) {
          LoadingProgress().width(18).height(18).color($r('app.color.muted'))
          Text('正在加载归档').fontSize(13).fontColor($r('app.color.muted'))
        }.width('100%').padding(20)
      }
      List({ space: 4 }) {
        if (this.groups.length === 0 && !this.loading) {
          ListItem() {
            Column({ space: 8 }) {
              Text(this.query || this.environmentId ? '没有匹配的归档会话' : '没有归档会话').fontSize(18)
                .fontWeight(FontWeight.Medium)
              Text('归档的会话会出现在这里。').fontSize(13).fontColor($r('app.color.muted'))
            }.width('100%').padding(32)
          }
        }
        ForEach(this.groups, (group: ArchiveProjectGroup) => {
          ListItem() {
            Row({ space: 6 }) {
              Text(group.project.label).fontSize(11).fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.muted')).maxLines(1).layoutWeight(1)
              Text(group.project.environmentLabel).fontSize(10).fontColor($r('app.color.muted'))
            }.width('100%').padding({ left: 18, right: 18, top: 14, bottom: 6 })
          }
          ForEach(group.threads, (thread: ScopedThread) => {
            ListItem() { this.row(thread) }
              .swipeAction({ end: this.swipe(thread), edgeEffect: SwipeEdgeEffect.Spring })
          }, (thread: ScopedThread) => thread.localId + ':' + thread.id)
        }, (group: ArchiveProjectGroup) => group.key)
      }.width('100%').layoutWeight(1)
    }.width('100%').height('100%').foregroundColor($r('app.color.ink')).backgroundColor($r('app.color.canvas'))
  }
}
