import { T3Client } from '../services/T3Client';
import { activityLines, ActivityLine, appendOutput } from '../protocol/ThreadItems';
import { record, text } from '../protocol/Wire';

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
        Column({ space: 5 }) {
          Button({ type: ButtonType.Normal }) {
            Row({ space: 8 }) {
              Image(this.expanded === line.itemId ? $r('app.media.ui_up') : $r('app.media.ui_down'))
                .width(16).height(16)
              Text(line.label).fontSize(13).fontColor($r('app.color.muted')).layoutWeight(1)
                .textAlign(TextAlign.Start)
            }.width('100%').padding({ top: 10, bottom: 10 })
          }.width('100%').constraintSize({ minHeight: 44 }).padding(0)
            .backgroundColor(Color.Transparent).borderRadius(8)
            .accessibilityText(line.label + (this.expanded === line.itemId ? '，已展开' : '，已折叠'))
            .onClick(() => { void this.open(line); })
          if (this.expanded === line.itemId) {
            Scroll() {
              Text(this.output).fontSize(13).lineHeight('20fp').fontFamily('monospace')
                .fontColor($r('app.color.ink')).copyOption(CopyOptions.InApp).padding(12)
            }.scrollable(ScrollDirection.Horizontal).width('100%')
              .backgroundColor($r('app.color.surface')).borderRadius(10)
            if (this.detail) {
              Text(this.detail).fontSize(11).fontColor($r('app.color.muted')).width('100%').copyOption(CopyOptions.InApp)
            }
            Button('复制输出').constraintSize({ minHeight: 44 }).fontSize(12).backgroundColor($r('app.color.canvas'))
              .fontColor($r('app.color.ink')).onClick(() => this.onCopy(this.output))
            Button('引用为上下文').constraintSize({ minHeight: 44 }).fontSize(12).backgroundColor($r('app.color.canvas'))
              .fontColor($r('app.color.ink')).onClick(() => this.onReference({
                itemId: line.itemId, kind: line.kind, label: line.label, text: this.output
              }))
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }, (line: ActivityLine) => line.itemId + this.expanded)
    }.width('100%')
  }
}

