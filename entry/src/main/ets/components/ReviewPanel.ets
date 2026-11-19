import { T3Client } from '../services/T3Client';
import { CodeLine } from './CodeLine';
import { DiffLineNumber } from './DiffLineNumber';
import { DiffFile, DiffHunk, DiffRow, DiffSelection, parseDiff, reviewCommentContext, ReviewSource,
  selectedDiff } from '../protocol/R5';

@Component
export struct ReviewPanel {
  @StorageProp('t3CodeFontSize') codeFontSize: number = 13;
  connection: T3Client | undefined = undefined;
  @Prop cwd: string = '';
  @Prop threadId: string = '';
  onBack: () => void = () => {};
  onCompose: (value: Object, label: string) => void = () => {};
  onCopy: (value: string) => void = () => {};
  onStatus: (value: string) => void = () => {};

  @State mode: string = 'working-tree';
  @State baseRef: string = '';
  @State sources: ReviewSource[] = [];
  @State sourceIndex: number = 0;
  @State files: DiffFile[] = [];
  @State loading: boolean = false;
  @State error: string = '';
  @State selectedPath: string = '';
  @State selectedHunk: string = '';
  @State start: number = -1;
  @State end: number = -1;
  @State comment: string = '';
  @State commenting: boolean = false;

  aboutToAppear(): void { void this.load(); }

  private async load(): Promise<void> {
    const connection = this.connection;
    if (!connection || !this.cwd) { this.error = '当前会话没有工作目录'; return; }
    if (this.mode === 'branch-range' && !this.baseRef.trim()) { this.error = '请输入对比分支'; return; }
    this.loading = true; this.error = ''; this.selectedPath = ''; this.start = -1; this.end = -1;
    try {
      const preview = await connection.reviewDiffPreview(this.cwd,
        this.mode === 'branch-range' ? this.baseRef.trim() : '', this.mode);
      this.sources = preview.sources;
      this.sourceIndex = 0;
      this.files = preview.sources.length ? parseDiff(preview.sources[0].diff) : [];
      if (preview.incomplete) this.error = '部分 Diff 无法读取；已显示可用文件';
    } catch (reason) { this.error = (reason as Error).message; }
    finally { this.loading = false; }
  }

  private selectSource(index: number): void {
    this.sourceIndex = index; this.selectedPath = ''; this.start = -1; this.end = -1;
    this.files = parseDiff(this.sources[index].diff);
  }

  private file(): DiffFile | undefined {
    return this.files.find((item: DiffFile) => item.path === this.selectedPath);
  }

  private hunks(): DiffHunk[] {
    const file = this.file();
    return file ? file.hunks : [];
  }

  private diffSelection(hunk: DiffHunk): DiffSelection | undefined {
    const file = this.file();
    if (!file || this.start < 0) return undefined;
    return selectedDiff(file, hunk, this.start, this.end);
  }

  private submitComment(hunk: DiffHunk): void {
    const selection = this.diffSelection(hunk);
    if (!selection) { this.onStatus('请先选择 Diff 行'); return; }
    try {
      const context = reviewCommentContext(selection, this.comment, 'review_' + Date.now().toString(36));
      this.onCompose(context, this.selectedPath);
      this.commenting = false; this.comment = ''; this.start = -1; this.end = -1;
      this.onStatus('评论已加入输入上下文');
      this.onBack();
    } catch (reason) { this.onStatus((reason as Error).message); }
  }

  private rowBackground(row: DiffRow): ResourceColor {
    if (row.kind === 'add') return $r('app.color.diff_add');
    if (row.kind === 'del') return $r('app.color.diff_del');
    return Color.Transparent;
  }

  private rowColor(row: DiffRow): ResourceColor {
    if (row.kind === 'add') return $r('app.color.diff_add_ink');
    if (row.kind === 'del') return $r('app.color.diff_del_ink');
    return $r('app.color.ink');
  }

  private pickRow(hunk: DiffHunk, index: number): void {
    if (this.selectedHunk !== hunk.header) {
      this.selectedHunk = hunk.header; this.start = index; this.end = index; return;
    }
    if (this.start < 0 || this.start !== this.end) { this.start = index; this.end = index; }
    else this.end = index;
  }

  @Builder
  header() {
    Row({ space: 6 }) {
      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.ui_back')).width(22).height(22)
      }.backgroundColor(Color.Transparent).width(44).height(44).accessibilityText('返回').onClick(() => {
          if (this.selectedPath) { this.selectedPath = ''; this.start = -1; this.end = -1; return; }
          this.onBack();
        })
      Column({ space: 2 }) {
        Text(this.selectedPath || '审阅').fontSize(17).fontWeight(FontWeight.Medium).width('100%')
          .maxLines(2).wordBreak(WordBreak.BREAK_ALL).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.selectedPath ? this.cwd : (this.sources.length ? this.sources[this.sourceIndex].title : this.cwd))
          .fontSize(11).fontColor($r('app.color.muted')).width('100%').maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Button('刷新').constraintSize({ minHeight: 44 }).fontSize(12).backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
        .onClick(() => { void this.load(); })
    }.width('100%').padding({ left: 8, right: 8, top: 4, bottom: 4 })
  }

  @Builder
  controls() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Button('工作区').fontSize(12)
          .backgroundColor(this.mode === 'working-tree' ? $r('app.color.primary') : $r('app.color.surface'))
          .fontColor(this.mode === 'working-tree' ? $r('app.color.on_primary') : $r('app.color.ink'))
          .onClick(() => { this.mode = 'working-tree'; void this.load(); })
        Button('分支范围').fontSize(12)
          .backgroundColor(this.mode === 'branch-range' ? $r('app.color.primary') : $r('app.color.surface'))
          .fontColor(this.mode === 'branch-range' ? $r('app.color.on_primary') : $r('app.color.ink'))
          .onClick(() => { this.mode = 'branch-range'; })
      }.width('100%')
        if (this.mode === 'branch-range') {
          TextInput({ placeholder: '对比分支，如 main', text: this.baseRef }).width('100%').height(44).fontColor($r('app.color.ink')).backgroundColor($r('app.color.surface'))
            .onChange((value: string) => { this.baseRef = value; })
            .onSubmit(() => { void this.load(); })
        }
      if (this.sources.length > 1) {
        Scroll() {
          Row({ space: 6 }) {
            ForEach(this.sources, (source: ReviewSource, index: number) => {
              Button(source.title).fontSize(11)
                .backgroundColor(index === this.sourceIndex ? $r('app.color.selected') : Color.Transparent)
                .fontColor($r('app.color.ink'))
                .onClick(() => this.selectSource(index))
            }, (source: ReviewSource, index: number) => source.id)
          }
        }.scrollable(ScrollDirection.Horizontal).width('100%')
      }
    }.width('100%').padding({ left: 12, right: 12 })
  }

  @Builder
  fileList() {
    Column({ space: 8 }) {
      if (this.loading) {
        Text('正在读取 Diff…').fontSize(13).fontColor($r('app.color.muted')).padding(20)
      } else if (this.error) {
        Text(this.error).fontSize(13).fontColor($r('app.color.danger')).padding(20)
      } else if (this.files.length === 0) {
        Text(this.mode === 'working-tree' ? '工作区没有改动' : '没有可显示的差异')
          .fontSize(14).fontColor($r('app.color.muted')).padding(24)
      }
      List({ space: 1 }) {
        ForEach(this.files, (file: DiffFile) => {
          ListItem() {
            Column({ space: 3 }) {
              Row({ space: 6 }) {
                Text(file.changeType === 'new' ? 'A' : file.changeType === 'deleted' ? 'D' :
                  file.changeType.startsWith('rename') ? 'R' : 'M')
                  .fontSize(11).fontColor($r('app.color.muted')).width(16)
                Text(file.path || file.previousPath).fontSize(14).layoutWeight(1).maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text('+' + file.additions).fontSize(11).fontColor($r('app.color.diff_add_ink'))
                Text('-' + file.deletions).fontSize(11).fontColor($r('app.color.diff_del_ink'))
              }.width('100%')
              if (file.previousPath && file.previousPath !== file.path) {
                Text('原路径 ' + file.previousPath).fontSize(10).fontColor($r('app.color.muted')).width('100%')
              }
            }.padding({ left: 12, right: 12, top: 10, bottom: 10 }).width('100%')
              .onClick(() => { this.selectedPath = file.path || file.previousPath; this.start = -1; this.end = -1; })
          }
        }, (file: DiffFile) => file.path || file.previousPath)
      }.width('100%').layoutWeight(1)
    }.width('100%').layoutWeight(1)
  }

  @Builder
  diffRow(hunk: DiffHunk, row: DiffRow, index: number) {
    Row({ space: 0 }) {
      if (hunk.lastOldLine) {
        DiffLineNumber({ line: row.oldLine, lastLine: hunk.lastOldLine })
          .onClick(() => this.pickRow(hunk, index))
      }
      if (hunk.lastNewLine) {
        DiffLineNumber({ line: row.newLine, lastLine: hunk.lastNewLine })
          .onClick(() => this.pickRow(hunk, index))
      }
      Text(row.kind === 'add' ? '+' : row.kind === 'del' ? '-' : ' ')
        .fontSize(this.codeFontSize).fontFamily('monospace').fontColor(this.rowColor(row)).width((this.codeFontSize + 2) + 'fp')
        .lineHeight((this.codeFontSize + 9) + 'fp')
      CodeLine({ text: row.text, color: this.rowColor(row) }).layoutWeight(1).onClick(() => this.pickRow(hunk, index))
    }.width('100%').constraintSize({ minHeight: (this.codeFontSize + 15) + 'fp' }).alignItems(VerticalAlign.Top).backgroundColor(
      this.start >= 0 && this.end >= 0 && index >= Math.min(this.start, this.end) &&
        index <= Math.max(this.start, this.end) ? $r('app.color.selected') : this.rowBackground(row))
      .onClick(() => this.pickRow(hunk, index))
  }

  @Builder
  diffDetail() {
    if (this.file()) {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Button('上一文件').fontSize(12).constraintSize({ minHeight: 44 }).backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).enabled(this.fileIndex() > 0)
            .onClick(() => this.stepFile(-1))
          Button('下一文件').fontSize(12).constraintSize({ minHeight: 44 }).backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink'))
            .enabled(this.fileIndex() >= 0 && this.fileIndex() < this.files.length - 1)
            .onClick(() => this.stepFile(1))
          Text((this.fileIndex() + 1) + ' / ' + this.files.length).fontSize(11)
            .fontColor($r('app.color.muted')).layoutWeight(1).textAlign(TextAlign.End)
        }.width('100%').padding({ left: 10, right: 10, top: 4 })
        if (this.start >= 0) {
          Row({ space: 8 }) {
            Text('已选 ' + (Math.min(this.start, this.end) + 1) + '–' + (Math.max(this.start, this.end) + 1) + ' 行')
              .fontSize(12).fontColor($r('app.color.muted')).layoutWeight(1)
            Button('复制').fontSize(12).backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
              .onClick(() => {
                const hunk = this.currentHunk();
                const selected = hunk ? this.diffSelection(hunk) : undefined;
                if (selected) this.onCopy(selected.text);
              })
            Button('评论').fontSize(12).backgroundColor($r('app.color.primary'))
              .fontColor($r('app.color.on_primary')).onClick(() => { this.commenting = true; })
          }.width('100%').padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .backgroundColor($r('app.color.surface')).borderRadius(8)
        }
        if (this.hunks().length === 0) {
          Text('该文件没有可显示的文本 Diff（可能是二进制或仅元数据）。')
            .fontSize(13).fontColor($r('app.color.muted')).padding(20)
        }
        List({ space: 2 }) {
          ForEach(this.hunks(), (hunk: DiffHunk) => {
            ListItem() {
              Column({ space: 0 }) {
                Text(hunk.header).fontSize(Math.max(8, this.codeFontSize - 2)).fontFamily('monospace').fontColor($r('app.color.muted'))
                  .width('100%').padding({ left: 8, top: 4, bottom: 4 }).backgroundColor($r('app.color.surface'))
                ForEach(hunk.rows, (row: DiffRow, index: number) => {
                  this.diffRow(hunk, row, index)
                }, (row: DiffRow, index: number) => hunk.header + ':' + index)
              }.width('100%')
            }
          }, (hunk: DiffHunk) => this.selectedPath + ':' + hunk.header)
        }.width('100%').layoutWeight(1)
        if (this.commenting) {
          Column({ space: 8 }) {
            TextArea({ placeholder: '说明这段改动的问题或意图', text: this.comment })
              .height(90).width('100%').onChange((value: string) => { this.comment = value; })
            Row({ space: 8 }) {
              Button('取消').fontSize(12).backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
                .onClick(() => { this.commenting = false; this.comment = ''; })
              Button('加入输入').fontSize(12).backgroundColor($r('app.color.primary'))
                .fontColor($r('app.color.on_primary')).enabled(!!this.comment.trim())
                .onClick(() => {
                  const hunk = this.currentHunk();
                  if (hunk) this.submitComment(hunk);
                })
            }.width('100%')
          }.width('100%').padding(10).backgroundColor($r('app.color.surface')).borderRadius(10)
        }
      }.width('100%').layoutWeight(1)
    }
  }

  private currentHunk(): DiffHunk | undefined {
    const file = this.file();
    return file ? file.hunks.find((hunk: DiffHunk) => hunk.header === this.selectedHunk) : undefined;
  }

  private fileIndex(): number {
    return this.files.findIndex((item: DiffFile) => item.path === this.selectedPath);
  }

  private stepFile(delta: number): void {
    const index = this.fileIndex();
    const next = Math.max(0, Math.min(this.files.length - 1, index + delta));
    if (next === index) return;
    this.selectedPath = this.files[next].path;
    this.start = -1; this.end = -1; this.selectedHunk = '';
  }

  build() {
    Column({ space: 6 }) {
      this.header()
      Divider().color($r('app.color.border'))
      if (!this.selectedPath) { this.controls() }
      if (this.selectedPath) { this.diffDetail() } else { this.fileList() }
    }.width('100%').height('100%').backgroundColor($r('app.color.canvas')).foregroundColor($r('app.color.ink'))
  }
}
