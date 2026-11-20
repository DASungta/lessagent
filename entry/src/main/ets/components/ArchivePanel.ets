import { TopBar } from './ui/TopBar';
import { GroupCard } from './ui/GroupCard';
import { FormRow } from './ui/FormRow';
import { AppButton } from './ui/AppButton';
import { SectionHeader } from './ui/SectionHeader';
import { FontSize, LineHeight, Radius, Sizes, Space, Weight } from '../common/Theme';
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
  row(thread: ScopedThread, isFirst: boolean) {
    Row({ space: Space.sm }) {
      Column({ space: 2 }) {
        Text(thread.label)
          .fontSize(FontSize.body).lineHeight(LineHeight.body).fontWeight(Weight.medium)
          .fontColor($r('app.color.ink')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        Text([thread.environmentLabel, thread.branch].filter((value: string) => !!value).join(' · ') || '已归档')
          .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted')).maxLines(1).width('100%')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text(relativeTime(thread.archivedAt || thread.updatedAt, this.nowMs))
        .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted'))
      Image($r('app.media.ui_chevron_right')).width(Sizes.chevron).height(Sizes.chevron).opacity(0.6).accessibilityLevel('no')
    }
    .width('100%')
    .constraintSize({ minHeight: Sizes.listRowMin })
    .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
    .backgroundColor($r('app.color.card'))
    .border({ width: { top: isFirst ? 0 : Sizes.hairline }, color: { top: $r('app.color.separator') } })
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
        Text('恢复').fontSize(FontSize.callout).fontWeight(Weight.medium).fontColor($r('app.color.ink'))
      }.width(68).height('100%').justifyContent(FlexAlign.Center).backgroundColor($r('app.color.card'))
        .onClick(() => this.onUnarchive(thread))
      Column({ space: 2 }) {
        Text('删除').fontSize(FontSize.callout).fontWeight(Weight.medium).fontColor($r('app.color.on_primary_fill'))
      }.width(68).height('100%').justifyContent(FlexAlign.Center).backgroundColor($r('app.color.danger'))
        .onClick(() => this.onDelete(thread))
    }.height('100%')
  }

  build() {
    Column({ space: 0 }) {
      TopBar({ title: '归档会话', showBack: true, backLabel: '返回设置', onBack: () => this.onBack() }) {
        AppButton({ label: '刷新', kind: 'text', onTap: () => this.onRefresh() })
      }
      Row({ space: Space.xs }) {
        Select([{ value: '所有环境' } as SelectOption].concat(this.environments.map((entry: EnvironmentEntry) => {
          return { value: entry.label } as SelectOption;
        }))).value(this.environments.find((entry: EnvironmentEntry) => entry.environmentId === this.environmentId)?.label || '所有环境')
          .height(38).font({ size: FontSize.caption }).backgroundColor($r('app.color.card')).fontColor($r('app.color.ink'))
          .onSelect((index: number) => this.onEnvironment(index === 0 ? '' : (this.environments[index - 1]?.environmentId || '')))
        TextInput({ placeholder: '搜索归档会话', text: this.query }).layoutWeight(1).height(38)
          .fontSize(FontSize.callout).backgroundColor($r('app.color.card')).borderRadius(Radius.button)
          .padding({ left: Space.sm, right: Space.sm })
          .onChange((value: string) => this.onQuery(value)).accessibilityText('搜索归档会话')
        AppButton({
          label: this.sortOrder === 'oldest' ? '最早' : '最新',
          kind: 'secondary',
          compact: true,
          onTap: () => this.onSort(this.sortOrder === 'oldest' ? 'newest' : 'oldest')
        })
      }.width('100%').padding({ left: Space.sm, right: Space.sm, top: Space.xxs, bottom: Space.xs })

      if (this.loading) {
        Row({ space: Space.xs }) {
          LoadingProgress().width(18).height(18).color($r('app.color.muted'))
          Text('正在加载归档').fontSize(FontSize.callout).fontColor($r('app.color.muted'))
        }.width('100%').padding(Space.md)
      }

      List({ space: 0 }) {
        if (this.groups.length === 0 && !this.loading) {
          ListItem() {
            Column() {
              GroupCard() {
                FormRow({
                  kind: 'value',
                  label: this.query || this.environmentId ? '没有匹配的归档会话' : '没有归档会话',
                  subtitle: '归档的会话会出现在这里。',
                  value: '',
                  valueMuted: true,
                  chevron: false,
                  isFirst: true
                })
              }
            }.padding({ left: Space.sm, right: Space.sm })
          }
        }
        ForEach(this.groups, (group: ArchiveProjectGroup) => {
          ListItem() {
            Column() {
              SectionHeader({ title: group.project.label + (group.project.environmentLabel ? ' · ' + group.project.environmentLabel : '') })
            }.padding({ left: Space.sm, right: Space.sm })
          }
          ForEach(group.threads, (thread: ScopedThread, index: number) => {
            ListItem() {
              Column() {
                this.row(thread, index === 0)
              }
              .margin({ left: Space.sm, right: Space.sm })
              .borderRadius({
                topLeft: index === 0 ? Radius.card : 0,
                topRight: index === 0 ? Radius.card : 0,
                bottomLeft: index === group.threads.length - 1 ? Radius.card : 0,
                bottomRight: index === group.threads.length - 1 ? Radius.card : 0
              })
              .clip(true)
            }
            .swipeAction({ end: this.swipe(thread), edgeEffect: SwipeEdgeEffect.Spring })
          }, (thread: ScopedThread) => thread.localId + ':' + thread.id)
        }, (group: ArchiveProjectGroup) => group.key)
      }.width('100%').layoutWeight(1).padding({ bottom: Space.lg })
    }.width('100%').height('100%').foregroundColor($r('app.color.ink')).backgroundColor($r('app.color.group'))
  }
}
