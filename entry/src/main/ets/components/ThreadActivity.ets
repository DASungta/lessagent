import { T3Client } from '../services/T3Client';
import {
  ActivityIcon, activityLines, ActivityLine, activitySummary, ActivitySummary, appendOutput,
  ColoredDiffLine, isActivityInProgress, MessageWorkMap, parseDiffPreviewLines, resolveExpandedActivityBody, TurnWorkGroup
} from '../protocol/ThreadItems';
import { HtmlRenderEntry } from '../protocol/HtmlRender';
import { ThreadHtmlRenderCard } from './HtmlRenderView';
import { MarkdownView } from './MarkdownView';
import { ResolvedMarkdownMedia } from '../protocol/Markdown';
import { record, text } from '../protocol/Wire';
import { FontSize, LineHeight, Radius, Space, Weight } from '../common/Theme';

export function iconForActivityKind(kind: ActivityIcon): Resource {
  if (kind === 'cmd') return $r('app.media.ui_tool_cmd');
  if (kind === 'file') return $r('app.media.ui_tool_file');
  if (kind === 'eye') return $r('app.media.ui_tool_eye');
  if (kind === 't3') return $r('app.media.ui_tool_t3');
  if (kind === 'thinking') return $r('app.media.ui_thinking');
  if (kind === 'browser') return $r('app.media.ui_globe');
  if (kind === 'pr') return $r('app.media.ui_tab_pulls');
  return $r('app.media.ui_tool_info');
}

function showActivityBadge(summary: ActivitySummary): boolean {
  if (summary.badgeTone === 'danger') return true;
  return summary.badge === '运行中' || summary.badge === '思考中' || summary.badge === '进行中';
}

function stripCommandHeader(output: string, line: ActivityLine, summary: ActivitySummary): string {
  if (!output) return '';
  if (line.kind === 'command_execution' && output === line.text) {
    const idx = output.indexOf('\n');
    if (idx < 0) return '';
    return output.slice(idx + 1).replace(/^\n+/, '');
  }
  if (line.kind === 'command_execution' && output.startsWith(summary.title + '\n')) {
    return output.slice(summary.title.length + 1).replace(/^\n+/, '');
  }
  return output;
}

@Component
struct ActivityRowView {
  @Prop line: ActivityLine = { label: '', text: '', kind: '', itemId: '' };
  @Prop isExpanded: boolean = false;
  @Prop @Watch('syncPulse') isActivePulse: boolean = false;
  @State pulseOpacity: number = 1;

  private summary(): ActivitySummary {
    return activitySummary(this.line);
  }

  private syncPulse(): void {
    if (this.isActivePulse) {
      try {
        this.getUIContext().animateTo({
          duration: 850,
          curve: Curve.EaseInOut,
          iterations: -1,
          playMode: PlayMode.Alternate
        }, () => {
          this.pulseOpacity = 0.45;
        });
      } catch (_) {}
    } else {
      try {
        this.getUIContext().animateTo({ duration: 150 }, () => {
          this.pulseOpacity = 1;
        });
      } catch (_) {
        this.pulseOpacity = 1;
      }
    }
  }

  private badgeColor(summary: ActivitySummary): ResourceColor {
    if (summary.badgeTone === 'danger') return $r('app.color.danger');
    if (summary.badge === '运行中' || summary.badge === '思考中' || summary.badge === '进行中') {
      return $r('app.color.primary_text');
    }
    return $r('app.color.muted');
  }

  build() {
    Row({ space: 6 }) {
      Row() {
        Image(iconForActivityKind(this.summary().icon))
          .width(this.summary().icon === 't3' ? 17 : 15)
          .height(this.summary().icon === 't3' ? 11 : 15)
          .objectFit(ImageFit.Contain)
          .opacity(this.summary().icon === 't3' ? 0.92 : 0.85)
          .accessibilityLevel('no')
      }
      .width(18)
      .height(16)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      Text(this.summary().title)
        .fontSize(FontSize.callout)
        .lineHeight(LineHeight.callout)
        .fontFamily(this.summary().icon === 'cmd' ? 'monospace' : '')
        .fontColor(this.isActivePulse ? $r('app.color.ink') : $r('app.color.muted'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (this.summary().additions || this.summary().deletions) {
        Row({ space: 6 }) {
          if (this.summary().additions) {
            Text(this.summary().additions)
              .fontSize(FontSize.caption)
              .fontWeight(Weight.medium)
              .fontColor($r('app.color.diff_add_ink'))
          }
          if (this.summary().deletions) {
            Text(this.summary().deletions)
              .fontSize(FontSize.caption)
              .fontWeight(Weight.medium)
              .fontColor($r('app.color.diff_del_ink'))
          }
        }
      } else if (showActivityBadge(this.summary())) {
        Text(this.summary().badge)
          .fontSize(FontSize.caption)
          .fontWeight(Weight.medium)
          .fontColor(this.badgeColor(this.summary()))
          .maxLines(1)
      }
      if (this.isExpanded || this.line.kind === 'reasoning') {
        Image($r('app.media.ui_chevron_down'))
          .width(12)
          .height(12)
          .opacity(this.isExpanded ? 0.55 : 0.45)
          .rotate({ angle: this.isExpanded ? 180 : 0 })
          .accessibilityLevel('no')
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 28 })
    .padding({ left: 2, right: 2, top: 3, bottom: 3 })
    .opacity(this.pulseOpacity)
    .alignItems(VerticalAlign.Center)
    .onAppear(() => { this.syncPulse(); })
  }
}

@Component
struct ProminentWorkRow {
  @Prop line: ActivityLine = { label: '', text: '', kind: '', itemId: '' };
  @State open: boolean = false;
  onCopy: (value: string) => void = () => {};

  private isError(): boolean {
    return this.line.kind === 'error';
  }

  private titleText(): string {
    if (this.isError()) return this.line.label || '执行错误';
    return this.line.label || '停止运行';
  }

  build() {
    Column({ space: 4 }) {
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Row({ space: 6 }) {
          Image(this.isError() ? $r('app.media.status_danger') : $r('app.media.status_neutral'))
            .width(15)
            .height(15)
            .objectFit(ImageFit.Contain)
            .accessibilityLevel('no')
          Text(this.titleText() + (this.line.text ? ' · ' + this.line.text.split('\n')[0] : ''))
            .fontSize(FontSize.callout)
            .lineHeight(LineHeight.callout)
            .fontWeight(Weight.medium)
            .fontColor(this.isError() ? $r('app.color.danger') : $r('app.color.ink'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (this.line.text) {
            Image($r('app.media.ui_chevron_down'))
              .width(12)
              .height(12)
              .opacity(0.6)
              .rotate({ angle: this.open ? 180 : 0 })
              .accessibilityLevel('no')
          }
        }.width('100%').alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .constraintSize({ minHeight: 34 })
      .padding({ left: Space.sm, right: Space.sm, top: 6, bottom: 6 })
      .backgroundColor(Color.Transparent)
      .borderRadius(Radius.tool)
      .accessibilityText(this.titleText() + (this.line.text ? '，' + this.line.text : ''))
      .onClick(() => {
        if (this.line.text) this.open = !this.open;
      })
      if (this.open && this.line.text) {
        Row({ space: Space.xs }) {
          Scroll() {
            Text(this.line.text)
              .fontSize(FontSize.mono)
              .lineHeight(LineHeight.mono)
              .fontFamily('monospace')
              .fontColor($r('app.color.ink'))
              .copyOption(CopyOptions.InApp)
          }.scrollable(ScrollDirection.Vertical).constraintSize({ maxHeight: 160 }).layoutWeight(1)
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            Image($r('app.media.ui_copy')).width(14).height(14).accessibilityLevel('no')
          }.width(28).height(28).backgroundColor(Color.Transparent)
            .accessibilityText('复制错误详情')
            .onClick(() => this.onCopy(this.line.text))
        }
        .width('100%')
        .padding({ left: Space.sm, right: Space.xs, bottom: Space.xs })
        .alignItems(VerticalAlign.Top)
      }
    }
    .width('100%')
    .backgroundColor(this.isError() ? $r('app.color.danger_bg') : $r('app.color.group'))
    .borderRadius(Radius.tool)
    .border({ width: 1, color: this.isError() ? $r('app.color.danger_border') : $r('app.color.border') })
  }
}

@Component
export struct ThreadActivity {
  connection: T3Client | undefined = undefined;
  @Prop groupId: string = '';
  @Prop items: Record<string, Object>[] = [];
  @Prop prominentItems: Record<string, Object>[] = [];
  @Prop htmlRenders: HtmlRenderEntry[] = [];
  @Prop htmlRenderScopeKey: string = '';
  @Prop headerLabel: string = '';
  @Prop summaryLabel: string = '';
  @Prop summaryIcon: ActivityIcon = 'cmd';
  @Prop failureLabel: string = '';
  @Prop checkpointText: string = '';
  @Prop checkpointAdditions: string = '';
  @Prop checkpointDeletions: string = '';
  @Prop checkpointFiles: string = '';
  @Prop checkpointAccessible: string = '';
  @Prop isRunning: boolean = false;
  @Prop isInterrupted: boolean = false;
  @Prop defaultExpanded: boolean = false;
  @Prop canOpenDiff: boolean = false;
  @Prop revision: string = '';
  @Consume('t3ExpandedWork') expandedWorkGroups: Record<string, boolean>;
  @State expanded: string = '';
  @State output: string = '';
  @State detail: string = '';
  @State showCheckpointFiles: boolean = false;
  private stream: ((value: Object) => void) | undefined = undefined;
  onToggleGroup: () => void = () => {};
  onCopy: (value: string) => void = () => {};
  onReference: (line: ActivityLine) => void = () => {};
  onOpenDiff: () => void = () => {};
  onOpenHtmlFullscreen: (entry: HtmlRenderEntry, uri: string) => void = () => {};
  onOpenExternalLink: (url: string) => void = () => {};

  aboutToDisappear(): void { this.stopStream(); }

  private stopStream(): void {
    if (this.connection && this.stream) this.connection.stopRpcStream(this.stream);
    this.stream = undefined;
  }

  private isGroupOpen(): boolean {
    if (this.groupId && this.expandedWorkGroups && this.expandedWorkGroups[this.groupId] !== undefined) {
      return this.expandedWorkGroups[this.groupId] === true;
    }
    return this.defaultExpanded;
  }

  private async open(line: ActivityLine): Promise<void> {
    if (this.expanded === line.itemId) { this.stopStream(); this.expanded = ''; return; }
    this.stopStream();
    this.expanded = line.itemId;
    this.output = line.text;
    this.detail = '';
    const connection = this.connection;
    if (!connection || !connection.ready) return;
    try {
      const item = await connection.turnItem(line.itemId);
      if (this.expanded !== line.itemId) return;
      if (item) {
        if (line.kind === 'file_change') {
          if (typeof item.diffStr === 'string' && item.diffStr) this.output = item.diffStr;
          else if (typeof item.oldStr === 'string' || typeof item.newStr === 'string') {
            this.output = (typeof item.oldStr === 'string' ? item.oldStr : '') + '\n→\n' +
              (typeof item.newStr === 'string' ? item.newStr : '');
          }
          if (!this.output && item.changes !== undefined) this.detail = JSON.stringify(item.changes);
        } else if (line.kind === 'reasoning') {
          const fetchedReasoning = typeof item.text === 'string' && item.text ? item.text :
            (typeof item.summary === 'string' ? item.summary : '');
          if (fetchedReasoning) this.output = fetchedReasoning;
        } else {
          const fetchedOutput = typeof item.output === 'string' ? item.output : '';
          if (fetchedOutput) this.output = fetchedOutput;
        }
      }
      if (line.kind === 'command_execution' && isActivityInProgress(line)) {
        this.stream = connection.commandOutput(line.itemId, (value: Object) => {
          const frame = record(value);
          this.output = appendOutput(this.output, text(frame.kind), text(frame.text), frame.truncated === true);
        });
      }
    } catch (error) { this.detail = (error as Error).message; }
  }

  private expandedHeaderTitle(line: ActivityLine): string {
    const summary = activitySummary(line);
    if (line.kind === 'command_execution') return '$ ' + summary.title;
    return summary.title;
  }

  private expandedBodyText(line: ActivityLine): string {
    const summary = activitySummary(line);
    const body = resolveExpandedActivityBody(line, this.output);
    return stripCommandHeader(body, line, summary);
  }

  private diffLineColor(tone: 'add' | 'del' | 'hunk' | 'plain'): ResourceColor {
    if (tone === 'add') return $r('app.color.diff_add_ink');
    if (tone === 'del') return $r('app.color.diff_del_ink');
    if (tone === 'hunk') return $r('app.color.primary_text');
    return $r('app.color.ink');
  }

  private diffLineBackground(tone: 'add' | 'del' | 'hunk' | 'plain'): ResourceColor {
    if (tone === 'add') return $r('app.color.diff_add');
    if (tone === 'del') return $r('app.color.diff_del');
    return Color.Transparent;
  }

  @Builder
  stepRow(line: ActivityLine, isActivePulse: boolean) {
    Column({ space: 4 }) {
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        ActivityRowView({
          line,
          isExpanded: this.expanded === line.itemId,
          isActivePulse
        })
      }
      .width('100%')
      .padding(0)
      .backgroundColor(Color.Transparent)
      .borderRadius(Radius.tool)
      .accessibilityText(line.label + (this.expanded === line.itemId ? '，已展开' : '，已折叠'))
      .onClick(() => { void this.open(line); })

      if (this.expanded === line.itemId) {
        if (line.kind === 'reasoning') {
          Column({ space: 4 }) {
            if (this.expandedBodyText(line)) {
              MarkdownView({
                markdown: this.expandedBodyText(line),
                selectable: true,
                compact: true,
                mediaScopeKey: this.groupId + ':' + (this.connection ? this.connection.generationValue() : 0),
                mediaReady: !!this.connection && this.connection.ready,
                onCopy: this.onCopy,
                resolveMedia: this.connection ? (source: string, refresh: boolean): Promise<ResolvedMarkdownMedia> =>
                  this.connection!.markdownMediaUrl(source, this.connection!.threadCwd(), refresh) : undefined
              })
            } else {
              Text(isActivityInProgress(line) ? '正在思考…' : '（无思考内容）')
                .fontSize(FontSize.callout)
                .lineHeight(LineHeight.callout)
                .fontColor($r('app.color.muted'))
            }
            if (this.detail) {
              Text(this.detail)
                .fontSize(FontSize.caption)
                .lineHeight(LineHeight.caption)
                .fontColor($r('app.color.muted'))
                .width('100%')
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 12, right: 4, top: 2, bottom: 6 })
          .margin({ left: 7 })
          .border({ width: { left: 2 }, color: { left: $r('app.color.border') } })
        } else {
          Column({ space: 4 }) {
            Row({ space: Space.xs }) {
              Text(this.expandedHeaderTitle(line))
                .fontSize(FontSize.caption)
                .lineHeight(LineHeight.caption)
                .fontFamily(line.kind === 'command_execution' || line.kind === 'file_change' ? 'monospace' : '')
                .fontColor($r('app.color.muted'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              Button({ type: ButtonType.Circle, stateEffect: true }) {
                Image($r('app.media.ui_copy')).width(14).height(14).accessibilityLevel('no')
              }
              .width(28).height(28).backgroundColor(Color.Transparent)
              .accessibilityText('复制输出')
              .onClick(() => this.onCopy(this.expandedBodyText(line) || activitySummary(line).title))
              Button({ type: ButtonType.Circle, stateEffect: true }) {
                Image($r('app.media.ui_quote')).width(14).height(14).accessibilityLevel('no')
              }
              .width(28).height(28).backgroundColor(Color.Transparent)
              .accessibilityText('引用为上下文')
              .onClick(() => this.onReference({
                itemId: line.itemId, kind: line.kind, label: line.label, text: this.expandedBodyText(line)
              }))
            }
            .width('100%')
            .padding({ left: Space.xs, right: 2, top: 2 })
            .alignItems(VerticalAlign.Center)

            if (line.kind === 'file_change' || line.kind === 'command_execution') {
              Scroll() {
                Scroll() {
                  if (line.kind === 'file_change' && this.expandedBodyText(line)) {
                    Column({ space: 0 }) {
                      ForEach(parseDiffPreviewLines(this.expandedBodyText(line)), (diffLine: ColoredDiffLine, idx: number) => {
                        Text(diffLine.text || ' ')
                          .fontSize(FontSize.mono)
                          .lineHeight(LineHeight.mono)
                          .fontFamily('monospace')
                          .fontColor(this.diffLineColor(diffLine.tone))
                          .backgroundColor(this.diffLineBackground(diffLine.tone))
                          .padding({ left: 6, right: 6 })
                          .copyOption(CopyOptions.InApp)
                      }, (diffLine: ColoredDiffLine, idx: number) => idx + ':' + diffLine.tone + ':' + diffLine.text)
                    }.alignItems(HorizontalAlign.Start).padding({ left: 2, right: 2, bottom: Space.xs })
                  } else {
                    Text(this.expandedBodyText(line) || '（无输出）')
                      .fontSize(FontSize.mono)
                      .lineHeight(LineHeight.mono)
                      .fontFamily('monospace')
                      .fontColor(this.expandedBodyText(line) ? $r('app.color.ink') : $r('app.color.muted'))
                      .copyOption(CopyOptions.InApp)
                      .padding({ left: Space.xs, right: Space.xs, top: 2, bottom: Space.xs })
                  }
                }.scrollable(ScrollDirection.Horizontal).align(Alignment.Start).width('100%')
              }.scrollable(ScrollDirection.Vertical).constraintSize({ maxHeight: 240 }).width('100%')
            } else {
              Scroll() {
                Text(this.expandedBodyText(line) || '（无输出）')
                  .fontSize(FontSize.callout)
                  .lineHeight(LineHeight.callout)
                  .fontColor(this.expandedBodyText(line) ? $r('app.color.ink') : $r('app.color.muted'))
                  .copyOption(CopyOptions.InApp)
                  .width('100%')
                  .padding({ left: Space.xs, right: Space.xs, top: 2, bottom: Space.xs })
              }.scrollable(ScrollDirection.Vertical).constraintSize({ maxHeight: 240 }).width('100%')
            }

            if (this.detail) {
              Text(this.detail)
                .fontSize(FontSize.caption)
                .lineHeight(LineHeight.caption)
                .fontColor($r('app.color.muted'))
                .padding({ left: Space.xs, right: Space.xs, bottom: Space.xxs })
                .width('100%')
                .copyOption(CopyOptions.InApp)
            }
          }
          .width('100%')
          .padding({ top: 4, bottom: 4, left: 4, right: 4 })
          .backgroundColor($r('app.color.card'))
          .borderRadius(Radius.tool)
          .border({ width: 1, color: $r('app.color.border') })
        }
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: 6 }) {
      if (this.headerLabel || this.checkpointText || this.checkpointAdditions || this.checkpointDeletions) {
        Column({ space: 4 }) {
          Row({ space: Space.xs }) {
            if (this.isRunning) {
              Circle().width(6).height(6).fill($r('app.color.primary')).accessibilityLevel('no')
            }
            if (this.headerLabel) {
              Text(this.headerLabel)
                .fontSize(FontSize.caption)
                .lineHeight(LineHeight.caption)
                .fontWeight(Weight.medium)
                .fontColor(this.isInterrupted ? $r('app.color.danger') : $r('app.color.muted'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            } else {
              Blank()
            }
            if (this.checkpointText || this.checkpointAdditions || this.checkpointDeletions) {
              Button({ type: ButtonType.Normal, stateEffect: true }) {
                Row({ space: 5 }) {
                  if (this.checkpointAdditions) {
                    Text(this.checkpointAdditions)
                      .fontSize(FontSize.caption)
                      .fontWeight(Weight.medium)
                      .fontColor($r('app.color.diff_add_ink'))
                  }
                  if (this.checkpointDeletions) {
                    Text(this.checkpointDeletions)
                      .fontSize(FontSize.caption)
                      .fontWeight(Weight.medium)
                      .fontColor($r('app.color.diff_del_ink'))
                  }
                  if (this.checkpointText) {
                    Text((this.checkpointAdditions || this.checkpointDeletions ? '· ' : '') + this.checkpointText)
                      .fontSize(FontSize.caption)
                      .fontColor($r('app.color.muted'))
                  }
                  Image($r('app.media.ui_chevron_right'))
                    .width(12)
                    .height(12)
                    .opacity(0.6)
                    .accessibilityLevel('no')
                }.alignItems(VerticalAlign.Center)
              }
              .constraintSize({ minHeight: 28 })
              .padding({ left: 6, right: 2 })
              .backgroundColor(Color.Transparent)
              .borderRadius(Radius.badge)
              .accessibilityText(this.checkpointAccessible || '查看检查点变更')
              .onClick(() => {
                if (this.canOpenDiff) this.onOpenDiff();
                else if (this.checkpointFiles) this.showCheckpointFiles = !this.showCheckpointFiles;
              })
            }
          }
          .width('100%')
          .constraintSize({ minHeight: 28 })
          .padding({ bottom: 4 })
          .border({ width: { bottom: 1 }, color: $r('app.color.border_subtle') })
          .alignItems(VerticalAlign.Center)

          if (this.showCheckpointFiles && this.checkpointFiles) {
            Text(this.checkpointFiles)
              .fontSize(FontSize.mono)
              .lineHeight(LineHeight.mono)
              .fontFamily('monospace')
              .fontColor($r('app.color.muted'))
              .padding(Space.xs)
              .width('100%')
              .backgroundColor($r('app.color.card'))
              .borderRadius(Radius.tool)
              .border({ width: 1, color: $r('app.color.border') })
              .copyOption(CopyOptions.InApp)
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }

      if (activityLines(this.items).length === 1) {
        this.stepRow(
          activityLines(this.items)[0],
          this.isRunning && isActivityInProgress(activityLines(this.items)[0])
        )
      } else if (activityLines(this.items).length >= 2) {
        Column({ space: 4 }) {
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Row({ space: 6 }) {
              Row() {
                Image(iconForActivityKind(this.summaryIcon))
                  .width(this.summaryIcon === 't3' ? 16 : 14)
                  .height(this.summaryIcon === 't3' ? 10 : 14)
                  .objectFit(ImageFit.Contain)
                  .opacity(this.summaryIcon === 't3' ? 0.85 : 0.7)
                  .accessibilityLevel('no')
              }
              .width(18)
              .height(16)
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Center)
              Text(this.summaryLabel || (activityLines(this.items).length + ' 项执行步骤'))
                .fontSize(FontSize.callout)
                .lineHeight(LineHeight.callout)
                .fontColor($r('app.color.muted'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              if (this.failureLabel) {
                Text(this.failureLabel)
                  .fontSize(FontSize.caption)
                  .fontWeight(Weight.medium)
                  .fontColor($r('app.color.danger'))
                  .maxLines(1)
              }
              Image($r('app.media.ui_chevron_down'))
                .width(12)
                .height(12)
                .opacity(0.6)
                .rotate({ angle: this.isGroupOpen() ? 180 : 0 })
                .accessibilityLevel('no')
            }.width('100%').alignItems(VerticalAlign.Center)
          }
          .width('100%')
          .constraintSize({ minHeight: 28 })
          .padding({ left: 0, right: 0 })
          .backgroundColor(Color.Transparent)
          .borderRadius(Radius.badge)
          .accessibilityText(
            (this.summaryLabel || '执行过程') +
            (this.failureLabel ? '，' + this.failureLabel : '') +
            (this.isGroupOpen() ? '，已展开' : '，已折叠')
          )
          .onClick(() => this.onToggleGroup())

          if (this.isGroupOpen()) {
            Column() {
              Column({ space: 2 }) {
                ForEach(activityLines(this.items), (line: ActivityLine) => {
                  this.stepRow(
                    line,
                    this.isRunning && isActivityInProgress(line)
                  )
                }, (line: ActivityLine) => line.itemId + ':' + line.label + ':' + (line.status || '') + ':' +
                  line.text.length + ':' + (this.isRunning && isActivityInProgress(line) ? '1' : '0'))
              }
              .width('100%')
              .padding({ left: 10, top: 2, bottom: 2 })
              .border({ width: { left: 1 }, color: $r('app.color.border') })
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding({ left: 8 })
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }

      if (activityLines(this.prominentItems).length > 0) {
        Column({ space: 4 }) {
          ForEach(activityLines(this.prominentItems), (line: ActivityLine) => {
            ProminentWorkRow({ line, onCopy: this.onCopy })
          }, (line: ActivityLine) => 'p:' + line.itemId)
        }.width('100%')
      }

      if (this.htmlRenders.length > 0) {
        Column({ space: 8 }) {
          ForEach(this.htmlRenders, (entry: HtmlRenderEntry) => {
            ThreadHtmlRenderCard({
              connection: this.connection,
              entry,
              scopeKey: this.htmlRenderScopeKey,
              onOpenFullscreen: this.onOpenHtmlFullscreen,
              onOpenExternalLink: this.onOpenExternalLink
            })
          }, (entry: HtmlRenderEntry) => entry.id + ':' + entry.render.attachmentId)
        }.width('100%')
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct MessageWorkSlot {
  connection: T3Client | undefined = undefined;
  @Prop messageId: string = '';
  @Prop slotKind: 'before' | 'afterUser' | 'afterAssistant' = 'before';
  @Prop htmlRenderScopeKey: string = '';
  @Consume('t3WorkMap') workMap: MessageWorkMap;
  @Consume('t3CanOpenDiff') canOpenDiff: boolean;
  onToggleGroup: (group: TurnWorkGroup) => void = () => {};
  onCopy: (value: string) => void = () => {};
  onReference: (line: ActivityLine) => void = () => {};
  onOpenDiff: () => void = () => {};
  onOpenHtmlFullscreen: (entry: HtmlRenderEntry, uri: string) => void = () => {};
  onOpenExternalLink: (url: string) => void = () => {};

  private currentGroup(): TurnWorkGroup | undefined {
    if (!this.messageId || !this.workMap) return undefined;
    if (this.slotKind === 'before') return this.workMap.before[this.messageId];
    if (this.slotKind === 'afterAssistant') return this.workMap.afterAssistant[this.messageId];
    return this.workMap.afterUser[this.messageId];
  }

  build() {
    Column() {
      if (this.currentGroup()) {
        Column() {
          ThreadActivity({
            connection: this.connection,
            groupId: this.currentGroup()!.groupId,
            items: this.currentGroup()!.items,
            prominentItems: this.currentGroup()!.prominent,
            htmlRenders: this.currentGroup()!.htmlRenders,
            htmlRenderScopeKey: this.htmlRenderScopeKey,
            headerLabel: this.currentGroup()!.runMeta ? this.currentGroup()!.runMeta!.headerLabel : '',
            summaryLabel: this.currentGroup()!.summary.label,
            summaryIcon: this.currentGroup()!.summary.summaryIcon,
            failureLabel: this.currentGroup()!.summary.failureLabel,
            checkpointText: this.currentGroup()!.checkpoint ? this.currentGroup()!.checkpoint!.label : '',
            checkpointAdditions: this.currentGroup()!.checkpoint ? this.currentGroup()!.checkpoint!.additionsText : '',
            checkpointDeletions: this.currentGroup()!.checkpoint ? this.currentGroup()!.checkpoint!.deletionsText : '',
            checkpointFiles: this.currentGroup()!.checkpoint ? this.currentGroup()!.checkpoint!.filePaths.join('\n') : '',
            checkpointAccessible: this.currentGroup()!.checkpoint ? this.currentGroup()!.checkpoint!.accessibleLabel : '',
            isRunning: this.currentGroup()!.runMeta ? this.currentGroup()!.runMeta!.running : this.currentGroup()!.summary.running,
            isInterrupted: this.currentGroup()!.runMeta ? this.currentGroup()!.runMeta!.interrupted : false,
            defaultExpanded: this.currentGroup()!.defaultExpanded,
            canOpenDiff: this.canOpenDiff,
            revision: this.currentGroup()!.revision,
            onToggleGroup: () => {
              const g = this.currentGroup();
              if (g) this.onToggleGroup(g);
            },
            onCopy: this.onCopy,
            onReference: this.onReference,
            onOpenDiff: this.onOpenDiff,
            onOpenHtmlFullscreen: this.onOpenHtmlFullscreen,
            onOpenExternalLink: this.onOpenExternalLink
          })
        }
        .width('100%')
        .padding(this.slotKind === 'before' ? { top: 2, bottom: 8 } : { top: 8, bottom: 2 })
      }
    }.width('100%')
  }
}

@Component
export struct ThreadThinkingRow {
  @Prop label: string = '正在思考…';
  @Prop @Watch('syncPulse') active: boolean = true;
  @State private pulseOpacity: number = 1;

  private syncPulse(): void {
    if (this.active) {
      try {
        this.getUIContext().animateTo({
          duration: 850,
          curve: Curve.EaseInOut,
          iterations: -1,
          playMode: PlayMode.Alternate
        }, () => {
          this.pulseOpacity = 0.45;
        });
      } catch (_) {}
    } else {
      try {
        this.getUIContext().animateTo({ duration: 150 }, () => {
          this.pulseOpacity = 1;
        });
      } catch (_) {
        this.pulseOpacity = 1;
      }
    }
  }

  build() {
    Row({ space: 6 }) {
      Image($r('app.media.ui_thinking'))
        .width(15)
        .height(15)
        .objectFit(ImageFit.Contain)
        .opacity(0.85)
        .accessibilityLevel('no')
      Text(this.label || '正在思考…')
        .fontSize(FontSize.callout)
        .lineHeight(LineHeight.callout)
        .fontWeight(Weight.medium)
        .fontColor($r('app.color.ink'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .constraintSize({ minHeight: 28 })
    .padding({ left: 2, right: 2, top: 3, bottom: 3 })
    .opacity(this.pulseOpacity)
    .alignItems(VerticalAlign.Center)
    .accessibilityGroup(true)
    .accessibilityText(this.label || '正在思考…')
    .onAppear(() => { this.syncPulse(); })
  }
}
