import { T3Client } from '../services/T3Client';
import { activityLines, ActivityLine, activitySummary, ActivitySummary, appendOutput } from '../protocol/ThreadItems';
import { record, text } from '../protocol/Wire';
import { FontSize, LineHeight, Radius, Space, Weight } from '../common/Theme';
import { AppButton } from './ui/AppButton';

@Component
struct ActivityRowView {
  line: ActivityLine = { label: '', text: '', kind: '', itemId: '' };
  @Prop isExpanded: boolean = false;

  private summary(): ActivitySummary {
    return activitySummary(this.line);
  }

  private iconResource(kind: 'cmd' | 'file' | 'info'): Resource {
    if (kind === 'cmd') return $r('app.media.ui_tool_cmd');
    if (kind === 'file') return $r('app.media.ui_tool_file');
    return $r('app.media.ui_tool_info');
  }

  private badgeColor(tone: 'success' | 'danger' | 'neutral'): ResourceColor {
    if (tone === 'success') return $r('app.color.success');
    if (tone === 'danger') return $r('app.color.danger');
    return $r('app.color.muted');
  }

  build() {
    Row({ space: Space.xs }) {
      Image(this.iconResource(this.summary().icon))
        .width(15)
        .height(15)
        .objectFit(ImageFit.Contain)
        .accessibilityLevel('no')
      Text(this.summary().title)
        .fontSize(FontSize.callout)
        .lineHeight(LineHeight.callout)
        .fontFamily(this.summary().icon === 'cmd' ? 'monospace' : '')
        .fontColor($r('app.color.muted'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (this.summary().additions || this.summary().deletions) {
        Row({ space: 6 }) {
          if (this.summary().additions) {
            Text(this.summary().additions)
              .fontSize(FontSize.caption)
              .fontWeight(Weight.medium)
              .fontColor($r('app.color.success'))
          }
          if (this.summary().deletions) {
            Text(this.summary().deletions)
              .fontSize(FontSize.caption)
              .fontWeight(Weight.medium)
              .fontColor($r('app.color.danger'))
          }
        }
      } else if (this.summary().badge) {
        Text(this.summary().badge)
          .fontSize(FontSize.caption)
          .fontWeight(Weight.medium)
          .fontColor(this.badgeColor(this.summary().badgeTone))
          .maxLines(1)
      }
      Image($r('app.media.ui_chevron_down'))
        .width(14)
        .height(14)
        .opacity(0.6)
        .rotate({ angle: this.isExpanded ? 180 : 0 })
        .accessibilityLevel('no')
    }
    .width('100%')
    .constraintSize({ minHeight: 40 })
    .padding({ left: Space.sm, right: Space.sm, top: Space.xs, bottom: Space.xs })
    .borderRadius(Radius.tool)
    .backgroundColor($r('app.color.screen'))
    .border({ width: 1, color: $r('app.color.border') })
    .alignItems(VerticalAlign.Center)
  }
}

@Component
export struct ThreadActivity {
  connection: T3Client | undefined = undefined;
  @Prop items: Record<string, Object>[] = [];
  @Prop status: string = '';
  @State expanded: string = '';
  @State output: string = '';
  @State detail: string = '';
  private stream: ((value: Object) => void) | undefined = undefined;
  onCopy: (value: string) => void = () => {};
  onReference: (line: ActivityLine) => void = () => {};

  aboutToDisappear(): void { this.stopStream(); }
  private stopStream(): void {
    if (this.connection && this.stream) this.connection.stopRpcStream(this.stream);
    this.stream = undefined;
  }
  private async open(line: ActivityLine): Promise<void> {
    if (this.expanded === line.itemId) { this.stopStream(); this.expanded = ''; return; }
    this.stopStream(); this.expanded = line.itemId; this.output = line.text; this.detail = '';
    const connection = this.connection;
    if (!connection || !connection.ready) return;
    try {
      const item = await connection.turnItem(line.itemId);
      if (this.expanded !== line.itemId) return;
      if (item) {
        const output = typeof item.output === 'string' ? item.output : '';
        if (output) this.output = output;
        if (item.diffStr !== undefined || item.changes !== undefined) this.detail = JSON.stringify(item.changes || item.diffStr);
      }
      if (line.kind === 'command_execution' && line.label.indexOf('inProgress') >= 0) {
        this.stream = connection.commandOutput(line.itemId, (value: Object) => {
          const frame = record(value);
          this.output = appendOutput(this.output, text(frame.kind), text(frame.text), frame.truncated === true);
        });
      }
    } catch (error) { this.detail = (error as Error).message; }
  }

  build() {
    Column({ space: 6 }) {
      ForEach(activityLines(this.items), (line: ActivityLine) => {
        Column({ space: 6 }) {
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            ActivityRowView({ line, isExpanded: this.expanded === line.itemId })
          }.width('100%').padding(0).backgroundColor(Color.Transparent).borderRadius(Radius.tool)
            .accessibilityText(line.label + (this.expanded === line.itemId ? '，已展开' : '，已折叠'))
            .onClick(() => { void this.open(line); })
          if (this.expanded === line.itemId) {
            Scroll() {
              Text(this.output).fontSize(FontSize.mono).lineHeight(LineHeight.mono).fontFamily('monospace')
                .fontColor($r('app.color.ink')).copyOption(CopyOptions.InApp).padding(Space.sm)
            }.scrollable(ScrollDirection.Horizontal).align(Alignment.Start).width('100%')
              .backgroundColor($r('app.color.card')).borderRadius(Radius.tool)
              .border({ width: 1, color: $r('app.color.border') })
            if (this.detail) {
              Text(this.detail).fontSize(FontSize.caption).lineHeight(LineHeight.caption)
                .fontColor($r('app.color.muted')).width('100%').copyOption(CopyOptions.InApp)
            }
            Row({ space: Space.xs }) {
              AppButton({ label: '复制输出', kind: 'secondary', compact: true, onTap: () => this.onCopy(this.output) })
              AppButton({ label: '引用为上下文', kind: 'secondary', compact: true, onTap: () => this.onReference({
                itemId: line.itemId, kind: line.kind, label: line.label, text: this.output
              }) })
            }.width('100%')
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }, (line: ActivityLine) => line.itemId + ':' + this.expanded)
    }.width('100%')
  }
}

