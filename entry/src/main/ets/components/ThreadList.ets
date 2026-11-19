import { EnvironmentEntry } from '../protocol/Environment';
import {
  ScopedThread, ThreadCapabilities, ThreadShelfState, relativeTime, snoozeWakeLabel,
  canMoveBeforeActiveNeighbor, effectiveSnoozed, threadCanArchive, threadCanSnooze, threadStatus
} from '../protocol/Projects';

@Component
export struct ThreadList {
  @Prop shelves: ThreadShelfState = {
    pinned: [], active: [], working: [], snoozed: [], settled: [], matches: [],
    workingShelfEnabled: true, workingCount: 0, snoozedCount: 0, settledCount: 0
  };
  @Prop query: string = '';
  @Prop searchHits: Record<string, string> = {};
  @Prop turnable: Record<string, boolean> = {};
  @Prop capabilities: Record<string, ThreadCapabilities> = {};
  @Prop selectedKey: string = '';
  @Prop nowMs: number = Date.now();
  @Prop environmentEntries: EnvironmentEntry[] = [];
  @Prop environmentFilter: string = '';
  @Prop projectFiltered: boolean = false;
  @Prop projectFilterLabel: string = '';
  @Prop loading: boolean = false;
  @Prop workingShelfExpanded: boolean = false;
  @Prop snoozedShelfExpanded: boolean = false;
  @Prop settledShelfExpanded: boolean = true;
  @Prop settledLimit: number = 10;
  onSelect: (thread: ScopedThread) => void = () => {};
  onAction: (thread: ScopedThread, action: string) => void = () => {};
  onSnooze: (thread: ScopedThread) => void = () => {};
  onMove: (thread: ScopedThread, ordered: ScopedThread[], up: boolean) => void = () => {};
  onFilterEnvironment: () => void = () => {};
  onClearFilters: () => void = () => {};
  onFilterProject: () => void = () => {};
  onSearchFocus: (focused: boolean) => void = () => {};
  onSearch: (value: string) => void = () => {};
  onNewTask: () => void = () => {};
  onSettings: () => void = () => {};
  onAddProject: () => void = () => {};
  onToggleWorking: () => void = () => {};
  onToggleSnoozed: () => void = () => {};
  onToggleSettled: () => void = () => {};
  onShowMoreSettled: () => void = () => {};

  private isSelected(thread: ScopedThread): boolean {
    return this.selectedKey === thread.localId + ':' + thread.id;
  }
  private caps(thread: ScopedThread): ThreadCapabilities {
    return this.capabilities[thread.localId] || {
      settlement: false, snooze: false, pinning: false, pinReorder: false,
      activeReorder: false, autoSettleOptOut: false, titleRegeneration: false
    };
  }
  private shift(thread: ScopedThread, up: boolean): void {
    const ordered = thread.pinnedAt ? this.shelves.pinned : this.shelves.active;
    this.onMove(thread, ordered, up);
  }
  private canMove(thread: ScopedThread, up: boolean): boolean {
    const caps = this.caps(thread);
    if (thread.pinnedAt ? !caps.pinReorder : this.shelves.workingShelfEnabled || !caps.activeReorder) return false;
    const ordered = thread.pinnedAt ? this.shelves.pinned : this.shelves.active;
    const index = ordered.findIndex((item: ScopedThread) => item.localId === thread.localId && item.id === thread.id);
    if (up ? index <= 0 : index < 0 || index >= ordered.length - 1) return false;
    return !!thread.pinnedAt || canMoveBeforeActiveNeighbor(ordered, up ? index - 1 : index + 2);
  }
  private rowTime(thread: ScopedThread): string {
    if (thread.settledOverride === 'settled') return relativeTime(thread.settledAt || thread.updatedAt, this.nowMs);
    if (thread.snoozedUntil) return snoozeWakeLabel(thread, this.nowMs);
    return relativeTime(thread.latestUserMessageAt || thread.updatedAt || thread.createdAt, this.nowMs);
  }
  private searchSnippet(thread: ScopedThread): string {
    return this.searchHits[thread.localId + ':' + thread.id] || '';
  }

  @Builder
  header() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Row() {
          Image($r('app.media.ui_search')).width(18).height(18).margin({ left: 12 }).accessibilityLevel('no')
          TextInput({ placeholder: '搜索会话、项目或消息', text: this.query })
            .constraintSize({ minHeight: 44 }).layoutWeight(1).fontSize(14).backgroundColor(Color.Transparent)
            .fontColor($r('app.color.ink')).padding({ left: 6, right: 8 })
            .onChange((value: string) => this.onSearch(value)).accessibilityText('搜索会话').id('thread-search')
            .onFocus(() => this.onSearchFocus(true)).onBlur(() => this.onSearchFocus(false))
          if (this.query) {
            Button('×', { type: ButtonType.Normal }).width(44).constraintSize({ minHeight: 44 })
              .backgroundColor(Color.Transparent).fontColor($r('app.color.muted')).padding(0)
              .accessibilityText('清除搜索').onClick(() => this.onSearch(''))
          }
        }.layoutWeight(1).backgroundColor($r('app.color.surface')).borderRadius(12)
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ui_settings')).width(20).height(20)
        }.width(44).height(44).backgroundColor($r('app.color.surface'))
          .accessibilityText('设置与项目').onClick(this.onSettings)
      }.width('100%')
      Row({ space: 8 }) {
        Button({ type: ButtonType.Normal }) {
          Text(this.environmentFilter
            ? (this.environmentEntries.find((entry: EnvironmentEntry) => entry.localId === this.environmentFilter)?.label || '环境')
            : '所有环境')
            .fontSize(13).fontColor($r('app.color.ink')).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.layoutWeight(1).constraintSize({ minWidth: 44, minHeight: 44 }).padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .backgroundColor(this.environmentFilter ? $r('app.color.selected') : $r('app.color.surface')).borderRadius(12).onClick(this.onFilterEnvironment)
          .accessibilityDescription('筛选环境')
        Button({ type: ButtonType.Normal }) {
          Text(this.projectFilterLabel || '所有项目')
            .fontSize(13).fontColor($r('app.color.ink')).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.layoutWeight(1).constraintSize({ minWidth: 44, minHeight: 44 }).padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .backgroundColor(this.projectFiltered ? $r('app.color.selected') : $r('app.color.surface')).borderRadius(12).onClick(this.onFilterProject)
          .accessibilityDescription('筛选项目')
      }.width('100%')
    }.width('100%').padding({ left: 16, right: 16, top: 2, bottom: 10 })
  }

  @Builder
  sectionHeader(title: string, count: number, expanded: boolean, kind: string) {
    Row({ space: 8 }) {
      Text(title).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.ink'))
      Text(String(count)).fontSize(12).fontColor($r('app.color.muted'))
      Blank()
      if (kind !== 'pinned') {
        Image(expanded ? $r('app.media.ui_up') : $r('app.media.ui_down')).width(16).height(16)
      }
    }.width('100%').padding({ left: 20, right: 20, top: 12, bottom: 10 }).constraintSize({ minHeight: 44 })
      .accessibilityText(title + '，' + count + ' 个会话' + (kind === 'pinned' ? '' : expanded ? '，已展开' : '，已折叠'))
      .onClick(() => {
        if (kind === 'pinned') return;
        if (kind === 'working') this.onToggleWorking();
        else if (kind === 'snoozed') this.onToggleSnoozed();
        else this.onToggleSettled();
      })
  }

  @Builder
  threadRow(thread: ScopedThread) {
    Row({ space: 10 }) {
      Column({ space: 3 }) {
        Row({ space: 6 }) {
          Text(thread.label).fontSize(16).fontColor($r('app.color.ink')).fontWeight(FontWeight.Medium).maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          if (thread.pinnedAt) { Text('固定').fontSize(10).fontColor($r('app.color.primary')) }
          if (thread.settledOverride === 'settled') { Text('已完成').fontSize(10).fontColor($r('app.color.muted')) }
        }.width('100%')
        Text(thread.projectLabel + (this.environmentEntries.length > 1 ? ' · ' + thread.environmentLabel : ''))
          .fontSize(13).fontColor($r('app.color.muted')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        if (this.searchSnippet(thread)) {
          Text(this.searchSnippet(thread)).fontSize(12).fontColor($r('app.color.ink')).maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        }
        Row({ space: 8 }) {
          Text(threadStatus(thread, this.nowMs) || this.rowTime(thread)).fontSize(11)
            .fontColor(threadStatus(thread, this.nowMs) ? $r('app.color.primary') : $r('app.color.muted'))
          if (thread.branch) {
            Text(thread.branch).fontSize(11).fontColor($r('app.color.muted')).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          }
        }.width('100%')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        .onClick(() => this.onSelect(thread))
        .bindContextMenu(this.rowMenu(thread), ResponseType.LongPress)
      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.ui_more')).width(18).height(18)
      }.width(44).height(44).backgroundColor(Color.Transparent)
        .accessibilityText(thread.label + '，会话操作').bindMenu(this.rowMenu(thread))
    }.width('100%').padding({ left: 20, right: 12, top: 10, bottom: 10 }).borderRadius(12)
      .backgroundColor(this.isSelected(thread) ? $r('app.color.selected') : Color.Transparent)
  }

  @Builder
  rowMenu(thread: ScopedThread) {
    Menu() {
      if (this.caps(thread).settlement) {
        MenuItem({ content: thread.settledOverride === 'settled' ? '取消 Settle' : 'Settle' })
          .onClick(() => this.onAction(thread, thread.settledOverride === 'settled' ? 'unsettle' : 'settle'))
      }
      if (this.caps(thread).snooze && thread.snoozedUntil && Date.parse(thread.snoozedUntil) > this.nowMs) {
        MenuItem({ content: '取消暂缓' }).onClick(() => this.onAction(thread, 'unsnooze'))
      } else if (this.caps(thread).snooze && threadCanSnooze(thread, this.nowMs)) {
        MenuItem({ content: '暂缓…' }).onClick(() => this.onSnooze(thread))
      }
      if (this.caps(thread).pinning) {
        MenuItem({ content: thread.pinnedAt ? '取消固定' : '固定' })
          .onClick(() => this.onAction(thread, thread.pinnedAt ? 'unpin' : 'pin'))
      }
      if (thread.pinnedAt ? this.caps(thread).pinReorder : !this.shelves.workingShelfEnabled && this.caps(thread).activeReorder) {
        MenuItem({ content: '上移' }).enabled(this.canMove(thread, true)).onClick(() => this.shift(thread, true))
        MenuItem({ content: '下移' }).enabled(this.canMove(thread, false)).onClick(() => this.shift(thread, false))
      }
      MenuItem({ content: '重命名…' }).onClick(() => this.onAction(thread, 'rename'))
      if (this.caps(thread).titleRegeneration) {
        MenuItem({ content: thread.titleRegenerationRequestId ? '正在重生成…' : '重生成名称' })
          .enabled(!thread.titleRegenerationRequestId).onClick(() => this.onAction(thread, 'regenerate'))
      }
      if (this.turnable[thread.localId + ':' + thread.id]) {
        MenuItem({ content: '转为项目' }).enabled(threadCanArchive(thread))
          .onClick(() => this.onAction(thread, 'turn-into-project'))
      }
      MenuItem({ content: '标记未读' }).onClick(() => this.onAction(thread, 'unread'))
      if (this.caps(thread).autoSettleOptOut) {
        MenuItem({ content: thread.autoSettleDisabledAt ? '自动 Settle：跟随设置' : '自动 Settle：从不' })
          .onClick(() => this.onAction(thread, thread.autoSettleDisabledAt ? 'auto-settle-on' : 'auto-settle-off'))
      }
      MenuItem({ content: '归档' }).enabled(threadCanArchive(thread))
        .onClick(() => this.onAction(thread, 'archive'))
      MenuItem({ content: '删除…' }).onClick(() => this.onAction(thread, 'delete'))
    }
  }

  @Builder
  swipeEnd(thread: ScopedThread) {
    Row() {
      if (effectiveSnoozed(thread, this.nowMs)) {
        Column({ space: 2 }) {
          Text('◷').fontSize(18).fontColor($r('app.color.ink'))
          Text('唤醒').fontSize(10).fontColor($r('app.color.ink'))
        }.width(64).height('100%').justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.surface'))
          .onClick(() => this.onAction(thread, 'unsnooze'))
      } else if (this.caps(thread).settlement) {
        Column({ space: 2 }) {
          Text(thread.settledOverride === 'settled' ? '↶' : '✓').fontSize(18)
            .fontColor(thread.settledOverride === 'settled' ? $r('app.color.ink') : $r('app.color.on_primary'))
          Text(thread.settledOverride === 'settled' ? '取消' : 'Settle').fontSize(10)
            .fontColor(thread.settledOverride === 'settled' ? $r('app.color.ink') : $r('app.color.on_primary'))
        }.width(64).height('100%').justifyContent(FlexAlign.Center)
          .backgroundColor(thread.settledOverride === 'settled' ? $r('app.color.surface') : $r('app.color.primary'))
          .onClick(() => this.onAction(thread, thread.settledOverride === 'settled' ? 'unsettle' : 'settle'))
      } else {
        Column({ space: 2 }) {
          Text('▣').fontSize(18).fontColor($r('app.color.ink'))
          Text('归档').fontSize(10).fontColor($r('app.color.ink'))
        }.width(64).height('100%').justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.surface'))
          .onClick(() => this.onAction(thread, 'archive'))
      }
      if (this.caps(thread).snooze && threadCanSnooze(thread, this.nowMs)) {
        Column({ space: 2 }) {
          Text('◷').fontSize(18).fontColor($r('app.color.ink'))
          Text('暂缓').fontSize(10).fontColor($r('app.color.ink'))
        }.width(64).height('100%').justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.surface'))
          .onClick(() => this.onSnooze(thread))
      }
    }.height('100%')
  }

  @Builder
  rowItem(thread: ScopedThread) {
    ListItem() {
      this.threadRow(thread)
    }.swipeAction({ end: this.swipeEnd(thread), edgeEffect: SwipeEdgeEffect.Spring })
  }

  build() {
    List({ space: 0 }) {
      ListItem() { this.header() }
      if (this.loading) {
        ListItem() {
          Row({ space: 8 }) {
            LoadingProgress().width(18).height(18).color($r('app.color.muted'))
            Text('正在同步环境列表').fontSize(13).fontColor($r('app.color.muted'))
          }.padding(20)
        }
      } else if (this.query.trim()) {
        if (this.shelves.matches.length === 0) {
          ListItem() {
            Column({ space: 8 }) {
              Text('没有匹配的会话').fontSize(18).fontWeight(FontWeight.Medium)
              Text('换一个关键词，或清除搜索。').fontSize(13).fontColor($r('app.color.muted'))
            }.padding({ left: 20, right: 20, top: 24, bottom: 24 }).width('100%')
          }
        }
        ForEach(this.shelves.matches, (thread: ScopedThread) => {
          this.rowItem(thread)
        }, (thread: ScopedThread) => thread.localId + ':' + thread.id)
      } else if (this.shelves.pinned.length + this.shelves.active.length + this.shelves.workingCount +
        this.shelves.snoozedCount + this.shelves.settledCount === 0) {
        ListItem() {
          Column({ space: 10 }) {
            if (this.environmentFilter || this.projectFiltered) {
              Text('当前筛选没有会话').fontSize(18).fontWeight(FontWeight.Medium)
              Button('清除筛选').backgroundColor($r('app.color.surface')).fontColor($r('app.color.primary'))
                .constraintSize({ minHeight: 44 }).onClick(this.onClearFilters)
            } else {
              Text('还没有会话').fontSize(18).fontWeight(FontWeight.Medium)
              Button('＋ 新建任务').backgroundColor($r('app.color.primary')).fontColor($r('app.color.on_primary'))
                .constraintSize({ minHeight: 44 }).onClick(this.onNewTask).accessibilityText('新建任务')
            }
          }.width('100%').padding({ left: 20, right: 20, top: 24, bottom: 24 })
        }
      } else {
        if (this.shelves.pinned.length) {
          ListItem() { this.sectionHeader('固定', this.shelves.pinned.length, true, 'pinned') }
          ForEach(this.shelves.pinned, (thread: ScopedThread) => { this.rowItem(thread) },
            (thread: ScopedThread) => thread.localId + ':' + thread.id)
        }
        ForEach(this.shelves.active, (thread: ScopedThread) => { this.rowItem(thread) },
          (thread: ScopedThread) => thread.localId + ':' + thread.id)
        if (this.shelves.workingCount > 0) {
          ListItem() { this.sectionHeader('进行中', this.shelves.workingCount, this.workingShelfExpanded, 'working') }
          if (this.workingShelfExpanded) {
            ForEach(this.shelves.working, (thread: ScopedThread) => { this.rowItem(thread) },
              (thread: ScopedThread) => thread.localId + ':' + thread.id)
          } else {
            ForEach(this.shelves.working.filter((thread: ScopedThread) => this.isSelected(thread)),
              (thread: ScopedThread) => { this.rowItem(thread) },
              (thread: ScopedThread) => thread.localId + ':' + thread.id)
          }
        }
        if (this.shelves.snoozedCount > 0) {
          ListItem() { this.sectionHeader('暂缓', this.shelves.snoozedCount, this.snoozedShelfExpanded, 'snoozed') }
          if (this.snoozedShelfExpanded) {
            ForEach(this.shelves.snoozed, (thread: ScopedThread) => { this.rowItem(thread) },
              (thread: ScopedThread) => thread.localId + ':' + thread.id)
          } else {
            ForEach(this.shelves.snoozed.filter((thread: ScopedThread) => this.isSelected(thread)),
              (thread: ScopedThread) => { this.rowItem(thread) },
              (thread: ScopedThread) => thread.localId + ':' + thread.id)
          }
        }
        if (this.shelves.settledCount > 0) {
          ListItem() { this.sectionHeader('已完成', this.shelves.settledCount, this.settledShelfExpanded, 'settled') }
          if (this.settledShelfExpanded) {
            ForEach(this.shelves.settled.slice(0, this.settledLimit), (thread: ScopedThread) => { this.rowItem(thread) },
              (thread: ScopedThread) => thread.localId + ':' + thread.id)
            if (this.shelves.settled.length > this.settledLimit) {
              ListItem() {
                Button('显示更多已完成会话').width('100%').constraintSize({ minHeight: 44 }).backgroundColor(Color.Transparent)
                  .fontColor($r('app.color.primary')).onClick(this.onShowMoreSettled)
              }
            }
          }
        }
      }
    }.width('100%').layoutWeight(1).cachedCount(6).foregroundColor($r('app.color.ink'))
  }
}
