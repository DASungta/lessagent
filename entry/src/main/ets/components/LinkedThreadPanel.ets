import { FontSize, LineHeight, Radius, Sizes, Space, Weight } from '../common/Theme';
import { T3Client } from '../services/T3Client';
import { ChatMessage, ThreadState } from '../protocol/Wire';
import {
  isLinkedThreadWorking,
  LINKED_THREAD_RETRY_MS,
  LinkedThreadFailure,
  linkedThreadFailure,
  LinkedThreadTarget
} from '../protocol/LinkedThread';
import {
  activityLines,
  ActivityLine,
  activitySummary,
  formatMessageTimestamp,
  groupWorkByMessage,
  MessageWorkMap,
  resolveExpandedActivityBody,
  TurnWorkGroup
} from '../protocol/ThreadItems';
import { MarkdownView } from './MarkdownView';
import { AppButton } from './ui/AppButton';
import { StatusBadge } from './ui/StatusBadge';
import { TopBar } from './ui/TopBar';

@Component
export struct LinkedThreadPanel {
  @Prop @Watch('onTargetChanged') target: LinkedThreadTarget | undefined = undefined;
  viaClient: T3Client | undefined = undefined;
  @Prop @Watch('onTargetChanged') viaReady: boolean = false;
  @Prop showOpenInMain: boolean = false;
  onClose: () => void = () => {};
  onOpenInMain: () => void = () => {};
  onCopy: (text: string) => void = () => {};
  onOpenLink: (url: string) => void = () => {};
  onConnect: ((target: LinkedThreadTarget) => Promise<void>) | undefined = undefined;
  @Prop connecting: boolean = false;
  @Prop connectNotice: string = '';
  @Prop connectError: boolean = false;

  @State private threadTitle: string = '';
  @State private messages: ChatMessage[] = [];
  @State private workMap: MessageWorkMap = { byMessage: {}, trailing: undefined };
  @State private hasMoreHistory: boolean = false;
  @State private loadingOlder: boolean = false;
  @State private loading: boolean = true;
  @State private working: boolean = false;
  @State private failure: LinkedThreadFailure | undefined = undefined;
  @State private expandedGroups: Record<string, boolean> = {};
  @State private expandedItems: Record<string, boolean> = {};
  @State private itemBodies: Record<string, string> = {};
  @State private itemLoading: Record<string, boolean> = {};
  @State private resolvedLabel: string = '';

  private state: ThreadState | undefined = undefined;
  private cancelStream: (() => void) | undefined = undefined;
  private retryTimer: number = 0;
  private streamSeq: number = 0;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.startSubscription();
  }

  aboutToDisappear(): void {
    this.stopSubscription();
  }

  private onTargetChanged(): void {
    this.startSubscription();
  }

  private stopSubscription(): void {
    this.streamSeq += 1;
    if (this.retryTimer) {
      clearTimeout(this.retryTimer);
      this.retryTimer = 0;
    }
    if (this.cancelStream) {
      const cancel = this.cancelStream;
      this.cancelStream = undefined;
      cancel();
    }
  }

  private displayEnvLabel(): string {
    if (this.resolvedLabel) return this.resolvedLabel;
    if (this.failure?.label) return this.failure.label;
    if (this.target?.label) return this.target.label;
    return this.target?.environmentId || '链接环境';
  }

  private syncViewFromState(): void {
    const state = this.state;
    if (!state) return;
    const title = typeof state.details.title === 'string' && state.details.title.trim()
      ? state.details.title.trim() : '';
    if (title) this.threadTitle = title;
    this.messages = state.messages.slice();
    this.workMap = groupWorkByMessage(state.messages, state.items, state.runs, state.messageRecords);
    this.hasMoreHistory = state.hasMoreHistory;
    this.working = isLinkedThreadWorking(state.runs);
  }

  private scheduleRetry(seq: number): void {
    if (this.retryTimer) {
      clearTimeout(this.retryTimer);
      this.retryTimer = 0;
    }
    this.retryTimer = setTimeout(() => {
      this.retryTimer = 0;
      if (seq !== this.streamSeq) return;
      this.startSubscription(true);
    }, LINKED_THREAD_RETRY_MS) as number;
  }

  private startSubscription(preserveMessages: boolean = false): void {
    this.stopSubscription();
    const seq = this.streamSeq;
    const target = this.target;
    const owner = this.viaClient;
    if (!preserveMessages) {
      this.threadTitle = '';
      this.messages = [];
      this.workMap = { byMessage: {}, trailing: undefined };
      this.hasMoreHistory = false;
      this.expandedGroups = {};
      this.expandedItems = {};
      this.itemBodies = {};
      this.itemLoading = {};
      this.resolvedLabel = target?.label || '';
    }
    this.failure = undefined;
    this.working = false;
    if (!target || !owner) {
      this.loading = false;
      this.failure = {
        reason: 'unknown',
        retryable: false,
        title: '未指定目标会话',
        detail: '缺少链接环境或会话标识。',
        label: target?.label || '链接环境'
      };
      return;
    }
    if (!this.viaReady || !owner.ready) {
      this.loading = false;
      this.failure = {
        reason: 'unreachable',
        retryable: true,
        title: '中转环境未连接',
        detail: '等待「' + (target.viaLabel || '当前环境') + '」恢复连接后将自动重试。',
        label: this.displayEnvLabel()
      };
      this.scheduleRetry(seq);
      return;
    }
    this.loading = !preserveMessages || this.messages.length === 0;
    if (!this.state || this.state.threadId !== target.threadId || !preserveMessages) {
      this.state = new ThreadState(target.threadId);
    }
    const localState = this.state;
    this.cancelStream = owner.subscribeLinkedThread(
      target.environmentId,
      target.threadId,
      (frame: Object) => {
        if (seq !== this.streamSeq) return;
        try {
          localState.apply(frame);
          this.failure = undefined;
          this.loading = false;
          this.syncViewFromState();
        } catch (error) {
          this.loading = false;
          this.failure = linkedThreadFailure(error as Object, this.displayEnvLabel());
        }
      },
      () => {
        if (seq !== this.streamSeq) return;
        this.loading = false;
        this.cancelStream = undefined;
        if (!this.failure) {
          this.failure = {
            reason: 'unreachable',
            retryable: true,
            title: '实时流已断开',
            detail: '与「' + this.displayEnvLabel() + '」的会话流已结束，稍后将自动重连。',
            label: this.displayEnvLabel()
          };
          this.scheduleRetry(seq);
        }
      },
      (error: Error) => {
        if (seq !== this.streamSeq) return;
        this.loading = false;
        this.cancelStream = undefined;
        const parsed = linkedThreadFailure(error as Object, this.displayEnvLabel());
        if (parsed.label) this.resolvedLabel = parsed.label;
        this.failure = parsed;
        if (parsed.retryable) {
          this.scheduleRetry(seq);
        }
      }
    );
  }

  private async loadOlder(): Promise<void> {
    const target = this.target;
    const owner = this.viaClient;
    const state = this.state;
    if (!target || !owner || !state || !state.historyCursor || !state.hasMoreHistory || this.loadingOlder) return;
    this.loadingOlder = true;
    const seq = this.streamSeq;
    try {
      const page = await owner.linkedThreadHistoryPage(target.environmentId, target.threadId, state.historyCursor);
      if (seq !== this.streamSeq || this.state !== state) return;
      state.prependHistory(page.items);
      state.historyCursor = page.nextCursor;
      state.hasMoreHistory = page.hasMoreHistory;
      this.syncViewFromState();
    } catch (error) {
      if (seq !== this.streamSeq) return;
      const parsed = linkedThreadFailure(error as Object, this.displayEnvLabel());
      this.failure = parsed;
    } finally {
      if (seq === this.streamSeq) this.loadingOlder = false;
    }
  }

  private toggleGroup(key: string): void {
    const next: Record<string, boolean> = {};
    for (const k of Object.keys(this.expandedGroups)) next[k] = this.expandedGroups[k];
    next[key] = !next[key];
    this.expandedGroups = next;
  }

  private toggleItem(line: ActivityLine): void {
    const key = line.itemId || line.label + ':' + line.text.slice(0, 24);
    const nextExpanded: Record<string, boolean> = {};
    for (const k of Object.keys(this.expandedItems)) nextExpanded[k] = this.expandedItems[k];
    const opening = !nextExpanded[key];
    nextExpanded[key] = opening;
    this.expandedItems = nextExpanded;
    if (opening && line.itemId && line.truncated && this.itemBodies[line.itemId] === undefined && !this.itemLoading[line.itemId]) {
      void this.loadItemDetail(line);
    }
  }

  private async loadItemDetail(line: ActivityLine): Promise<void> {
    const target = this.target;
    const owner = this.viaClient;
    if (!target || !owner || !line.itemId) return;
    const id = line.itemId;
    const loadingNext: Record<string, boolean> = {};
    for (const k of Object.keys(this.itemLoading)) loadingNext[k] = this.itemLoading[k];
    loadingNext[id] = true;
    this.itemLoading = loadingNext;
    const seq = this.streamSeq;
    try {
      const item = await owner.linkedThreadItem(target.environmentId, target.threadId, id);
      if (seq !== this.streamSeq) return;
      if (item) {
        const body = resolveExpandedActivityBody(line, item);
        const bodiesNext: Record<string, string> = {};
        for (const k of Object.keys(this.itemBodies)) bodiesNext[k] = this.itemBodies[k];
        bodiesNext[id] = body;
        this.itemBodies = bodiesNext;
      }
    } catch (_) {
    } finally {
      if (seq === this.streamSeq) {
        const doneLoading: Record<string, boolean> = {};
        for (const k of Object.keys(this.itemLoading)) {
          if (k !== id) doneLoading[k] = this.itemLoading[k];
        }
        this.itemLoading = doneLoading;
      }
    }
  }

  @Builder
  workGroupCard(groupKey: string, group: TurnWorkGroup) {
    Column({ space: Space.xs }) {
      Button({ type: ButtonType.Normal }) {
        Row({ space: Space.xs }) {
          Text((this.expandedGroups[groupKey] ? '▾ ' : '▸ ') + group.summary)
            .fontSize(FontSize.caption)
            .lineHeight(LineHeight.caption)
            .fontColor($r('app.color.muted'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(String(group.items.length) + ' 步')
            .fontSize(FontSize.badge)
            .fontColor($r('app.color.muted'))
        }.width('100%').padding({ left: Space.sm, right: Space.sm, top: Space.xs, bottom: Space.xs })
      }
      .width('100%')
      .backgroundColor($r('app.color.card'))
      .borderRadius(Radius.tool)
      .onClick(() => this.toggleGroup(groupKey))

      if (this.expandedGroups[groupKey]) {
        Column({ space: Space.xxs }) {
          ForEach(activityLines(group.items), (line: ActivityLine, idx: number) => {
            Column({ space: Space.xxs }) {
              Button({ type: ButtonType.Normal }) {
                Row({ space: Space.xs }) {
                  Text(activitySummary(line).title || line.label)
                    .fontSize(FontSize.caption)
                    .lineHeight(LineHeight.caption)
                    .fontColor($r('app.color.ink'))
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (activitySummary(line).badge) {
                    Text(activitySummary(line).badge)
                      .fontSize(FontSize.badge)
                      .fontColor($r('app.color.muted'))
                  }
                }.width('100%').padding({ left: Space.sm, right: Space.sm, top: Space.xxs, bottom: Space.xxs })
              }
              .width('100%')
              .backgroundColor(Color.Transparent)
              .onClick(() => this.toggleItem(line))

              if (this.expandedItems[line.itemId || line.label + ':' + line.text.slice(0, 24)]) {
                if (line.itemId && this.itemLoading[line.itemId]) {
                  Text('正在加载完整输出…')
                    .fontSize(FontSize.caption)
                    .fontColor($r('app.color.muted'))
                    .padding({ left: Space.sm, right: Space.sm, bottom: Space.xs })
                    .width('100%')
                } else {
                  Text((line.itemId && this.itemBodies[line.itemId] !== undefined ? this.itemBodies[line.itemId] : line.text) || '无详细输出')
                    .fontSize(FontSize.caption)
                    .lineHeight(LineHeight.caption)
                    .fontFamily('monospace')
                    .fontColor($r('app.color.muted'))
                    .padding({ left: Space.sm, right: Space.sm, bottom: Space.xs })
                    .width('100%')
                    .copyOption(CopyOptions.InApp)
                }
              }
            }
            .width('100%')
            .backgroundColor($r('app.color.group'))
            .borderRadius(Radius.tool)
          }, (line: ActivityLine, idx: number) => (line.itemId || String(idx)) + ':' + line.text.length + ':' +
            String(this.expandedItems[line.itemId || line.label + ':' + line.text.slice(0, 24)] === true) + ':' +
            String(this.itemBodies[line.itemId] !== undefined) + ':' + String(this.itemLoading[line.itemId] === true))
        }.width('100%').padding({ left: Space.xs })
      }
    }.width('100%')
  }

  build() {
    Column({ space: 0 }) {
      TopBar({
        title: this.threadTitle || '链接环境会话',
        subtitle: this.displayEnvLabel() + (this.target?.viaLabel ? ' · 经由 ' + this.target.viaLabel : ''),
        showBack: true,
        closeStyle: !this.showOpenInMain,
        backLabel: '关闭链接环境会话',
        onBack: () => this.onClose()
      }) {
        if (this.showOpenInMain) {
          Button('全屏', { type: ButtonType.Normal })
            .height(32)
            .fontSize(FontSize.caption)
            .fontColor($r('app.color.primary_text'))
            .backgroundColor(Color.Transparent)
            .padding({ left: Space.xs, right: Space.xs })
            .onClick(() => this.onOpenInMain())
        }
      }

      Scroll(this.scroller) {
        Column({ space: Space.sm }) {
          if (this.loading && this.messages.length === 0) {
            Column({ space: Space.xs }) {
              LoadingProgress().width(28).height(28).color($r('app.color.primary'))
              Text('正在经由「' + (this.target?.viaLabel || '当前环境') + '」读取远端会话…')
                .fontSize(FontSize.callout)
                .lineHeight(LineHeight.callout)
                .fontColor($r('app.color.muted'))
                .textAlign(TextAlign.Center)
            }
            .width('100%')
            .padding(Space.xl)
            .alignItems(HorizontalAlign.Center)
          }

          if (this.failure) {
            Column({ space: Space.xs }) {
              Row({ space: Space.xs }) {
                Text(this.failure.title)
                  .fontSize(FontSize.body)
                  .lineHeight(LineHeight.body)
                  .fontWeight(Weight.semibold)
                  .fontColor($r('app.color.danger'))
                  .layoutWeight(1)
                StatusBadge({
                  text: this.failure.retryable ? '将自动重试' : '不可读',
                  tone: this.failure.retryable ? 'warning' : 'danger'
                })
              }.width('100%').alignItems(VerticalAlign.Center)
              Text(this.failure.detail)
                .fontSize(FontSize.callout)
                .lineHeight(LineHeight.callout)
                .fontColor($r('app.color.muted'))
                .width('100%')
              if (this.failure.retryable) {
                Row() {
                  AppButton({
                    label: '立即重试',
                    kind: 'secondary',
                    compact: true,
                    onTap: () => this.startSubscription(this.messages.length > 0)
                  })
                }.padding({ top: Space.xxs })
              }
            }
            .width('100%')
            .padding(Space.md)
            .alignItems(HorizontalAlign.Start)
            .backgroundColor($r('app.color.card'))
            .borderRadius(Radius.card)
          }

          if (this.hasMoreHistory) {
            Row() {
              AppButton({
                label: this.loadingOlder ? '正在加载更早记录…' : '加载更早的记录',
                kind: 'secondary',
                compact: true,
                fill: true,
                disabled: this.loadingOlder,
                onTap: () => { void this.loadOlder(); }
              })
            }.width('100%')
          }

          if (!this.loading && !this.failure && this.messages.length === 0) {
            Column() {
              Text('此会话暂无可显示的消息')
                .fontSize(FontSize.body)
                .lineHeight(LineHeight.body)
                .fontColor($r('app.color.muted'))
                .textAlign(TextAlign.Center)
                .width('100%')
            }
            .padding(Space.lg)
            .width('100%')
            .backgroundColor($r('app.color.card'))
            .borderRadius(Radius.card)
          }

          ForEach(this.messages, (msg: ChatMessage) => {
            Column({ space: Space.xs }) {
              if (this.workMap.byMessage[msg.id]) {
                this.workGroupCard(msg.id, this.workMap.byMessage[msg.id])
              }
              Column({ space: Space.xxs }) {
                Row({ space: Space.xs }) {
                  Text(msg.role === 'user' ? '用户' : msg.role === 'system' ? '系统' : '助手')
                    .fontSize(FontSize.caption)
                    .fontWeight(Weight.medium)
                    .fontColor(msg.role === 'user' ? $r('app.color.primary_text') : $r('app.color.muted'))
                  if (msg.timestamp) {
                    Text(formatMessageTimestamp(msg.timestamp))
                      .fontSize(FontSize.badge)
                      .fontColor($r('app.color.muted'))
                  }
                  if (msg.streaming) {
                    StatusBadge({ text: '输出中', tone: 'info' })
                  }
                }.width('100%').alignItems(VerticalAlign.Center)
                if (msg.role === 'user') {
                  Text(msg.text)
                    .fontSize(FontSize.body)
                    .lineHeight(LineHeight.body)
                    .fontColor($r('app.color.ink'))
                    .width('100%')
                    .copyOption(CopyOptions.InApp)
                } else {
                  MarkdownView({
                    markdown: msg.text,
                    onCopy: this.onCopy,
                    onOpenLink: this.onOpenLink
                  })
                }
              }
              .width('100%')
              .padding(Space.md)
              .alignItems(HorizontalAlign.Start)
              .backgroundColor(msg.role === 'user' ? $r('app.color.user_bubble') : $r('app.color.card'))
              .borderRadius(Radius.card)
            }.width('100%').alignItems(HorizontalAlign.Start)
          }, (msg: ChatMessage) => msg.id + ':' + msg.text.length + ':' + String(msg.streaming) + ':' +
            String(this.workMap.byMessage[msg.id]?.items.length || 0))

          if (this.workMap.trailing) {
            this.workGroupCard('__trailing__', this.workMap.trailing)
          }
        }
        .padding({ left: Space.page, right: Space.page, top: Space.xs, bottom: Space.lg })
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.TopStart)

      // Bottom Read-Only Bar (ReadOnlyComposerBar)
      Column({ space: Space.xs }) {
        if (this.connectNotice) {
          Text(this.connectNotice)
            .fontSize(FontSize.caption)
            .lineHeight(LineHeight.caption)
            .fontColor(this.connectError ? $r('app.color.danger') : $r('app.color.muted'))
            .width('100%')
            .padding({ left: Space.xs, right: Space.xs })
        }
        Row({ space: Space.sm }) {
          Column({ space: 2 }) {
            Row({ space: Space.xs }) {
              Text('只读模式 · ' + this.displayEnvLabel())
                .fontSize(FontSize.callout)
                .lineHeight(LineHeight.callout)
                .fontWeight(Weight.medium)
                .fontColor($r('app.color.ink'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              if (this.working) {
                StatusBadge({ text: '运行中', tone: 'info' })
              }
            }.width('100%').alignItems(VerticalAlign.Center)
            Text('经由 ' + (this.target?.viaLabel || '当前环境') + ' 查看，此视图不可发送消息')
              .fontSize(FontSize.caption)
              .lineHeight(LineHeight.caption)
              .fontColor($r('app.color.muted'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)

          if (this.onConnect && this.target) {
            AppButton({
              label: this.connecting ? '连接中…' : '连接此环境',
              kind: 'primary',
              compact: true,
              disabled: this.connecting || !this.viaReady,
              onTap: () => {
                if (this.onConnect && this.target) void this.onConnect(this.target);
              }
            })
          }
        }
        .width('100%')
        .padding({ left: Space.md, right: Space.sm, top: Space.sm, bottom: Space.sm })
        .backgroundColor($r('app.color.card'))
        .borderRadius(Radius.card)
        .border({ width: Sizes.hairline, color: $r('app.color.separator') })
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding({ left: Space.page, right: Space.page, top: Space.xs, bottom: Space.sm })
      .backgroundColor($r('app.color.group'))
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.group'))
    .foregroundColor($r('app.color.ink'))
  }
}
