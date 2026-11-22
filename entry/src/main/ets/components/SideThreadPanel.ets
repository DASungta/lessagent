import { FontSize, LineHeight, Radius, Sizes, Space, Weight } from '../common/Theme';
import { T3Client } from '../services/T3Client';
import { ChatMessage, ThreadState } from '../protocol/Wire';
import { isLinkedThreadWorking } from '../protocol/LinkedThread';
import { sideThreadComposer, sideThreadKindLabel, SideThreadTarget } from '../protocol/SideThread';
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
export struct SideThreadPanel {
  @Prop @Watch('onTargetChanged') target: SideThreadTarget | undefined = undefined;
  ownerClient: T3Client | undefined = undefined;
  @Prop @Watch('onTargetChanged') ownerReady: boolean = false;
  onClose: () => void = () => {};
  onOpenInMain: () => void = () => {};
  onCopy: (text: string) => void = () => {};
  onOpenLink: (url: string) => void = () => {};

  @State private threadTitle: string = '';
  @State private messages: ChatMessage[] = [];
  @State private workMap: MessageWorkMap = { byMessage: {}, trailing: undefined };
  @State private hasMoreHistory: boolean = false;
  @State private loadingOlder: boolean = false;
  @State private loading: boolean = true;
  @State private working: boolean = false;
  @State private errorText: string = '';
  @State private prompt: string = '';
  @State private sending: boolean = false;
  @State private expandedGroups: Record<string, boolean> = {};
  @State private expandedItems: Record<string, boolean> = {};
  @State private itemBodies: Record<string, string> = {};
  @State private itemLoading: Record<string, boolean> = {};

  private state: ThreadState | undefined = undefined;
  private cancelStream: (() => void) | undefined = undefined;
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
    if (this.cancelStream) {
      const cancel = this.cancelStream;
      this.cancelStream = undefined;
      cancel();
    }
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

  private startSubscription(): void {
    this.stopSubscription();
    const seq = this.streamSeq;
    const target = this.target;
    const owner = this.ownerClient;
    this.threadTitle = target?.title || '';
    this.messages = [];
    this.workMap = { byMessage: {}, trailing: undefined };
    this.hasMoreHistory = false;
    this.errorText = '';
    this.working = false;
    this.expandedGroups = {};
    this.expandedItems = {};
    this.itemBodies = {};
    this.itemLoading = {};
    if (!target || !owner) {
      this.loading = false;
      this.errorText = '未找到目标会话';
      return;
    }
    if (!this.ownerReady || !owner.ready) {
      this.loading = false;
      this.errorText = '当前环境未连接，请等待重连后重试';
      return;
    }
    this.loading = true;
    this.state = new ThreadState(target.threadId);
    const localState = this.state;
    this.cancelStream = owner.subscribeSideThread(
      target.threadId,
      (frame: Object) => {
        if (seq !== this.streamSeq) return;
        try {
          localState.apply(frame);
          this.errorText = '';
          this.loading = false;
          this.syncViewFromState();
        } catch (error) {
          this.loading = false;
          this.errorText = (error as Error).message || '读取会话失败';
        }
      },
      () => {
        if (seq !== this.streamSeq) return;
        this.loading = false;
        this.cancelStream = undefined;
      },
      (error: Error) => {
        if (seq !== this.streamSeq) return;
        this.loading = false;
        this.cancelStream = undefined;
        this.errorText = error.message || '读取会话失败';
      }
    );
  }

  private async loadOlder(): Promise<void> {
    const target = this.target;
    const owner = this.ownerClient;
    const state = this.state;
    if (!target || !owner || !state || !state.historyCursor || !state.hasMoreHistory || this.loadingOlder) return;
    this.loadingOlder = true;
    const seq = this.streamSeq;
    try {
      const page = await owner.sideThreadHistoryPage(target.threadId, state.historyCursor);
      if (seq !== this.streamSeq || this.state !== state) return;
      state.prependHistory(page.items);
      state.historyCursor = page.nextCursor;
      state.hasMoreHistory = page.hasMoreHistory;
      this.syncViewFromState();
    } catch (error) {
      if (seq === this.streamSeq) this.errorText = (error as Error).message;
    } finally {
      if (seq === this.streamSeq) this.loadingOlder = false;
    }
  }

  private async sendMessage(): Promise<void> {
    const target = this.target;
    const owner = this.ownerClient;
    const text = this.prompt.trim();
    if (!target || !owner || !text || this.sending || !this.ownerReady) return;
    this.sending = true;
    this.errorText = '';
    try {
      await owner.sendToSideThread(target.threadId, text);
      this.prompt = '';
    } catch (error) {
      this.errorText = (error as Error).message || '发送失败';
    } finally {
      this.sending = false;
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
    const owner = this.ownerClient;
    if (!target || !owner || !line.itemId) return;
    const id = line.itemId;
    const loadingNext: Record<string, boolean> = {};
    for (const k of Object.keys(this.itemLoading)) loadingNext[k] = this.itemLoading[k];
    loadingNext[id] = true;
    this.itemLoading = loadingNext;
    const seq = this.streamSeq;
    try {
      const item = await owner.sideThreadItem(target.threadId, id);
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
        title: this.threadTitle || (this.target ? sideThreadKindLabel(this.target.kind) : '子会话'),
        subtitle: (this.target ? sideThreadKindLabel(this.target.kind) : '') +
          (this.target?.environmentLabel ? ' · ' + this.target.environmentLabel : ''),
        showBack: true,
        closeStyle: true,
        backLabel: '关闭子会话面板',
        onBack: () => this.onClose()
      }) {
        Button('主视图', { type: ButtonType.Normal })
          .height(32)
          .fontSize(FontSize.caption)
          .fontColor($r('app.color.primary_text'))
          .backgroundColor(Color.Transparent)
          .padding({ left: Space.xs, right: Space.xs })
          .onClick(() => this.onOpenInMain())
      }

      Scroll(this.scroller) {
        Column({ space: Space.sm }) {
          if (this.loading && this.messages.length === 0) {
            Column({ space: Space.xs }) {
              LoadingProgress().width(28).height(28).color($r('app.color.primary'))
              Text('正在同步子会话…')
                .fontSize(FontSize.callout)
                .fontColor($r('app.color.muted'))
            }
            .width('100%')
            .padding(Space.xl)
            .alignItems(HorizontalAlign.Center)
          }

          if (this.errorText) {
            Column({ space: Space.xs }) {
              Text(this.errorText)
                .fontSize(FontSize.callout)
                .lineHeight(LineHeight.callout)
                .fontColor($r('app.color.danger'))
                .width('100%')
            }
            .width('100%')
            .padding(Space.md)
            .backgroundColor($r('app.color.card'))
            .borderRadius(Radius.card)
          }

          if (this.hasMoreHistory) {
            AppButton({
              label: this.loadingOlder ? '正在加载更早记录…' : '加载更早的记录',
              kind: 'secondary',
              compact: true,
              fill: true,
              disabled: this.loadingOlder,
              onTap: () => { void this.loadOlder(); }
            })
          }

          if (!this.loading && !this.errorText && this.messages.length === 0) {
            Column() {
              Text('暂无消息，可在下方直接发消息或切到主视图继续。')
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

      if (this.target && sideThreadComposer(this.target.kind) === 'read-only') {
        Row({ space: Space.sm }) {
          Column({ space: 2 }) {
            Row({ space: Space.xs }) {
              Text('只读 · ' + sideThreadKindLabel(this.target.kind))
                .fontSize(FontSize.callout)
                .fontWeight(Weight.medium)
                .fontColor($r('app.color.ink'))
                .layoutWeight(1)
              if (this.working) {
                StatusBadge({ text: '运行中', tone: 'info' })
              }
            }.width('100%').alignItems(VerticalAlign.Center)
            Text('由 Provider 创建的子会话仅支持查看，不接受直接发送消息。')
              .fontSize(FontSize.caption)
              .fontColor($r('app.color.muted'))
              .width('100%')
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding({ left: Space.page, right: Space.page, top: Space.xs, bottom: Space.sm })
        .backgroundColor($r('app.color.card'))
        .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
      } else {
        Row({ space: Space.xs }) {
          TextInput({ text: this.prompt, placeholder: '在此子会话中继续对话…' })
            .layoutWeight(1)
            .height(40)
            .fontSize(FontSize.body)
            .fontColor($r('app.color.ink'))
            .placeholderColor($r('app.color.placeholder'))
            .backgroundColor($r('app.color.card'))
            .borderRadius(Radius.button)
            .padding({ left: Space.sm, right: Space.sm })
            .enabled(!this.sending && this.ownerReady)
            .onChange((v: string) => { this.prompt = v; })
          AppButton({
            label: this.sending ? '发送中' : '发送',
            kind: 'primary',
            compact: true,
            disabled: this.sending || !this.ownerReady || !this.prompt.trim(),
            onTap: () => { void this.sendMessage(); }
          })
        }
        .width('100%')
        .padding({ left: Space.page, right: Space.page, top: Space.xs, bottom: Space.sm })
        .backgroundColor($r('app.color.group'))
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.group'))
    .foregroundColor($r('app.color.ink'))
  }
}
