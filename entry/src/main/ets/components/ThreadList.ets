import { EnvironmentEntry } from '../protocol/Environment';
import {
  ScopedThread, ThreadCapabilities, ThreadShelfState, snoozeWakeLabel,
  canMoveBeforeActiveNeighbor, effectiveSnoozed, threadCanArchive, threadCanSnooze, threadStatus
} from '../protocol/Projects';
import { compactTime, providerGlyph, threadSubline, threadTone } from '../protocol/ThreadRow';
import { FontSize, LineHeight, Radius, Sizes, Space, Weight } from '../common/Theme';
import { ProjectMonogram } from './ui/ProjectMonogram';
import { SectionHeader } from './ui/SectionHeader';
import { AppButton } from './ui/AppButton';

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
  /** 搜索框是否展开（由首页标题栏的搜索按钮控制）。有搜索词时总是展开。 */
  @Prop searchOpen: boolean = false;
  /** 列表底部留给悬浮底栏的空间。 */
  @Prop bottomInset: number = 0;
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
  onCloseSearch: () => void = () => {};

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
    if (thread.settledOverride === 'settled') return compactTime(thread.settledAt || thread.updatedAt, this.nowMs);
    if (thread.snoozedUntil) return snoozeWakeLabel(thread, this.nowMs);
    return compactTime(thread.latestUserMessageAt || thread.updatedAt || thread.createdAt, this.nowMs);
  }
  private searchSnippet(thread: ScopedThread): string {
    return this.searchHits[thread.localId + ':' + thread.id] || '';
  }

  private filterLabel(): string {
    const parts: string[] = [];
    if (this.environmentFilter) {
      parts.push(this.environmentEntries.find((entry: EnvironmentEntry) => entry.localId === this.environmentFilter)?.label || '环境');
    }
    if (this.projectFiltered) parts.push(this.projectFilterLabel || '项目');
    return parts.join(' · ');
  }

  private statusIcon(status: string): Resource {
    const tone = threadTone(status);
    if (tone === 'run') return $r('app.media.status_run');
    if (tone === 'wait') return $r('app.media.status_wait');
    if (tone === 'danger') return $r('app.media.status_danger');
    return $r('app.media.status_neutral');
  }

  private statusColor(status: string): ResourceColor {
    const tone = threadTone(status);
    if (tone === 'run') return $r('app.color.primary_text');
    if (tone === 'wait') return $r('app.color.warning');
    if (tone === 'danger') return $r('app.color.danger');
    return $r('app.color.muted');
  }

  @Builder
  header() {
    Column({ space: Space.xs }) {
      if (this.searchOpen || this.query) {
        Row() {
          Image($r('app.media.ui_search')).width(18).height(18).margin({ left: Space.sm }).accessibilityLevel('no')
          TextInput({ placeholder: '搜索会话、项目或消息', text: this.query })
            .constraintSize({ minHeight: 40 }).layoutWeight(1).fontSize(FontSize.body).backgroundColor(Color.Transparent)
            .fontColor($r('app.color.ink')).placeholderColor($r('app.color.placeholder')).padding({ left: 6, right: Space.xs })
            .onChange((value: string) => this.onSearch(value)).accessibilityText('搜索会话').id('thread-search')
            .onFocus(() => this.onSearchFocus(true)).onBlur(() => this.onSearchFocus(false))
          Button({ type: ButtonType.Normal }) {
            Text(this.query ? '清除' : '取消').fontSize(FontSize.callout).fontWeight(Weight.medium).fontColor($r('app.color.ink'))
          }.constraintSize({ minHeight: 40 }).padding({ left: Space.sm, right: Space.sm }).backgroundColor(Color.Transparent)
            .accessibilityText(this.query ? '清除搜索' : '关闭搜索')
            .onClick(() => { if (this.query) this.onSearch(''); else this.onCloseSearch(); })
        }.width('100%').backgroundColor($r('app.color.group')).borderRadius(Radius.button)
      }
      if (this.environmentFilter || this.projectFiltered) {
        Row({ space: Space.xs }) {
          Image($r('app.media.ui_filter')).width(14).height(14).opacity(0.7).accessibilityLevel('no')
          Text(this.filterLabel()).fontSize(FontSize.callout).fontColor($r('app.color.ink')).layoutWeight(1)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Button({ type: ButtonType.Normal }) {
            Text('清除').fontSize(FontSize.callout).fontWeight(Weight.medium).fontColor($r('app.color.ink'))
          }.constraintSize({ minHeight: 32 }).padding({ left: Space.xs, right: Space.xs }).backgroundColor(Color.Transparent)
            .accessibilityText('清除筛选').onClick(this.onClearFilters)
        }.width('100%').padding({ left: Space.sm, right: Space.xxs }).constraintSize({ minHeight: 40 })
          .backgroundColor($r('app.color.group')).borderRadius(Radius.button)
          .accessibilityText('筛选：' + this.filterLabel()).onClick(this.onFilterEnvironment)
      }
    }.width('100%').padding({ left: Space.md, right: Space.md, top: (this.searchOpen || this.query || this.environmentFilter || this.projectFiltered) ? Space.xs : 0 })
  }

  @Builder
  sectionHeader(title: string, count: number, expanded: boolean, kind: string) {
    Column() {
      SectionHeader({ title: kind === 'pinned' || expanded ? title : title + ' (' + count + ')',
        collapsible: kind !== 'pinned', collapsed: !expanded,
        onToggle: () => {
          if (kind === 'working') this.onToggleWorking();
          else if (kind === 'snoozed') this.onToggleSnoozed();
          else this.onToggleSettled();
        } })
    }.padding({ left: Space.sm, right: Space.sm, top: Space.xxs })
  }

  @Builder
  providerIcon(providerInstanceId: string) {
    if (providerGlyph(providerInstanceId) === 'claude') {
      Image($r('app.media.provider_claude')).width(15).height(15).accessibilityLevel('no')
    } else if (providerGlyph(providerInstanceId) === 'openai') {
      Image($r('app.media.provider_openai')).width(15).height(15).accessibilityLevel('no')
    } else if (providerGlyph(providerInstanceId) === 'gemini') {
      Image($r('app.media.provider_gemini')).width(15).height(15).accessibilityLevel('no')
    } else if (providerGlyph(providerInstanceId) === 'cursor') {
      Image($r('app.media.provider_cursor')).width(15).height(15).accessibilityLevel('no')
    } else if (providerGlyph(providerInstanceId) === 'generic') {
      Image($r('app.media.provider_generic')).width(15).height(15).accessibilityLevel('no')
    }
  }

  private rowA11y(thread: ScopedThread): string {
    const status = threadStatus(thread, this.nowMs);
    const sub = threadSubline(status, thread.lastError, thread.environmentLabel);
    return [thread.label, thread.projectLabel, status || this.rowTime(thread), sub.text, thread.pinnedAt ? '已固定' : '']
      .filter((part: string) => !!part).join('，') + '。长按查看操作';
  }

  @Builder
  threadRow(thread: ScopedThread) {
    Column({ space: 3 }) {
      Row({ space: Space.xs }) {
        Column() {
          ProjectMonogram({ projectId: thread.projectId, name: thread.projectLabel })
        }.constraintSize({ minHeight: LineHeight.body }).justifyContent(FlexAlign.Center)
        Text(thread.label).fontSize(FontSize.body).lineHeight(LineHeight.body)
          .fontWeight(thread.settledOverride === 'settled' ? Weight.regular : Weight.medium)
          .fontColor($r('app.color.ink')).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        Row({ space: 4 }) {
          if (thread.pinnedAt) {
            Image($r('app.media.ui_pin')).width(12).height(12).accessibilityLevel('no')
          }
          if (threadStatus(thread, this.nowMs)) {
            Image(this.statusIcon(threadStatus(thread, this.nowMs))).width(13).height(13).accessibilityLevel('no')
            Text(threadStatus(thread, this.nowMs)).fontSize(FontSize.caption).fontWeight(Weight.bold)
              .fontColor(this.statusColor(threadStatus(thread, this.nowMs))).maxLines(1)
          } else {
            Text(this.rowTime(thread)).fontSize(FontSize.caption).fontColor($r('app.color.muted')).maxLines(1)
          }
        }.constraintSize({ minHeight: LineHeight.body }).alignItems(VerticalAlign.Center)
      }.width('100%').alignItems(VerticalAlign.Top)
      Row({ space: 4 }) {
        if (threadSubline(threadStatus(thread, this.nowMs), thread.lastError, thread.environmentLabel).error) {
          Text(threadSubline(threadStatus(thread, this.nowMs), thread.lastError, thread.environmentLabel).text)
            .fontSize(FontSize.caption).fontColor($r('app.color.danger')).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        } else {
          Image($r('app.media.ui_env_desktop')).width(12).height(12).accessibilityLevel('no')
          Text(thread.environmentLabel).fontSize(FontSize.caption).fontColor($r('app.color.muted')).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        }
        this.providerIcon(thread.providerInstanceId)
      }.width('100%').padding({ left: Sizes.monogram + Space.xs }).alignItems(VerticalAlign.Center)
      if (this.searchSnippet(thread)) {
        Text(this.searchSnippet(thread)).fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.ink'))
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          .padding({ left: Sizes.monogram + Space.xs })
      }
    }.width('100%').padding({ left: Space.sm, right: Space.sm, top: 10, bottom: 10 }).borderRadius(20)
      .backgroundColor(this.isSelected(thread) ? $r('app.color.card') : Color.Transparent)
      .accessibilityGroup(true).accessibilityText(this.rowA11y(thread))
      .onClick(() => this.onSelect(thread))
      .bindContextMenu(this.rowMenu(thread), ResponseType.LongPress)
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
        Column() {
          Text('唤醒').fontSize(FontSize.callout).fontWeight(Weight.medium).fontColor($r('app.color.ink'))
        }.width(64).height('100%').justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.group'))
          .onClick(() => this.onAction(thread, 'unsnooze'))
      } else if (this.caps(thread).settlement) {
        Column() {
          Text(thread.settledOverride === 'settled' ? '取消完成' : '完成').fontSize(FontSize.callout).fontWeight(Weight.medium)
            .fontColor(thread.settledOverride === 'settled' ? $r('app.color.ink') : $r('app.color.on_prominent'))
        }.width(64).height('100%').justifyContent(FlexAlign.Center)
          .backgroundColor(thread.settledOverride === 'settled' ? $r('app.color.group') : $r('app.color.prominent'))
          .onClick(() => this.onAction(thread, thread.settledOverride === 'settled' ? 'unsettle' : 'settle'))
      } else {
        Column() {
          Text('归档').fontSize(FontSize.callout).fontWeight(Weight.medium).fontColor($r('app.color.ink'))
        }.width(64).height('100%').justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.group'))
          .onClick(() => this.onAction(thread, 'archive'))
      }
      if (this.caps(thread).snooze && threadCanSnooze(thread, this.nowMs)) {
        Column() {
          Text('暂缓').fontSize(FontSize.callout).fontWeight(Weight.medium).fontColor($r('app.color.ink'))
        }.width(64).height('100%').justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.warning_bg'))
          .onClick(() => this.onSnooze(thread))
      }
    }.height('100%')
  }

  @Builder
  rowItem(thread: ScopedThread) {
    ListItem() {
      this.threadRow(thread)
    }.padding({ left: Space.xs, right: Space.xs }).swipeAction({ end: this.swipeEnd(thread), edgeEffect: SwipeEdgeEffect.Spring })
  }

  build() {
    List({ space: 0 }) {
      if (this.searchOpen || this.query || this.environmentFilter || this.projectFiltered) {
        ListItem() { this.header() }
      }
      if (this.loading) {
        ListItem() {
          Row({ space: 8 }) {
            LoadingProgress().width(18).height(18).color($r('app.color.muted'))
            Text('正在同步环境列表').fontSize(FontSize.callout).fontColor($r('app.color.muted'))
          }.padding(Space.lg)
        }
      } else if (this.query.trim()) {
        if (this.shelves.matches.length === 0) {
          ListItem() {
            Column({ space: 8 }) {
              Text('没有匹配的会话').fontSize(FontSize.headline).fontWeight(Weight.semibold)
              Text('换一个关键词，或清除搜索。').fontSize(FontSize.callout).fontColor($r('app.color.muted'))
            }.padding({ left: Space.lg, right: Space.lg, top: Space.xl, bottom: Space.xl }).width('100%')
          }
        }
        ForEach(this.shelves.matches, (thread: ScopedThread) => {
          this.rowItem(thread)
        }, (thread: ScopedThread) => thread.localId + ':' + thread.id)
      } else if (this.shelves.pinned.length + this.shelves.active.length + this.shelves.workingCount +
        this.shelves.snoozedCount + this.shelves.settledCount === 0) {
        ListItem() {
          Column({ space: Space.sm }) {
            if (this.environmentFilter || this.projectFiltered) {
              Text('当前筛选没有会话').fontSize(FontSize.headline).fontWeight(Weight.semibold)
              AppButton({ label: '清除筛选', kind: 'secondary', onTap: () => this.onClearFilters() })
            } else {
              Text('还没有会话').fontSize(FontSize.headline).fontWeight(Weight.semibold)
              Text('点右下角按钮，开始第一个任务。').fontSize(FontSize.callout).fontColor($r('app.color.muted'))
            }
          }.width('100%').padding({ left: Space.lg, right: Space.lg, top: 64, bottom: Space.xl })
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
                AppButton({ label: '显示更多已完成会话', kind: 'text', fill: true, onTap: () => this.onShowMoreSettled() })
              }
            }
          }
        }
      }
    }.width('100%').layoutWeight(1).cachedCount(6).foregroundColor($r('app.color.ink'))
      .contentStartOffset(Space.xs).contentEndOffset(this.bottomInset)
      .scrollBar(BarState.Off)
  }
}
