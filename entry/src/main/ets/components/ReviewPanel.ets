import { TopBar } from './ui/TopBar';
import { GroupCard } from './ui/GroupCard';
import { AppButton } from './ui/AppButton';
import { StatusBadge } from './ui/StatusBadge';
import { FontSize, LineHeight, Radius, Sizes, Space, Weight } from '../common/Theme';
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
    TopBar({
      title: this.selectedPath || '审阅',
      subtitle: this.selectedPath ? this.cwd : (this.sources.length ? this.sources[this.sourceIndex].title : this.cwd),
      showBack: true,
      closeStyle: !this.selectedPath,
      backLabel: this.selectedPath ? '返回文件列表' : '关闭审阅',
      onBack: () => {
        if (this.selectedPath) { this.selectedPath = ''; this.start = -1; this.end = -1; return; }
        this.onBack();
      }
    }) {
      AppButton({ label: '刷新', kind: 'text', onTap: () => { void this.load(); } })
    }
  }

  @Builder
  controls() {
    Column({ space: Space.xs }) {
      Row({ space: 2 }) {
        Button('工作区')
          .fontSize(FontSize.callout)
          .fontWeight(this.mode === 'working-tree' ? Weight.medium : Weight.regular)
          .fontColor(this.mode === 'working-tree' ? $r('app.color.ink') : $r('app.color.muted'))
          .backgroundColor(this.mode === 'working-tree' ? $r('app.color.card') : Color.Transparent)
          .borderRadius(7).layoutWeight(1).constraintSize({ minHeight: 34 })
          .onClick(() => { this.mode = 'working-tree'; void this.load(); })
        Button('分支范围')
          .fontSize(FontSize.callout)
          .fontWeight(this.mode === 'branch-range' ? Weight.medium : Weight.regular)
          .fontColor(this.mode === 'branch-range' ? $r('app.color.ink') : $r('app.color.muted'))
          .backgroundColor(this.mode === 'branch-range' ? $r('app.color.card') : Color.Transparent)
          .borderRadius(7).layoutWeight(1).constraintSize({ minHeight: 34 })
          .onClick(() => { this.mode = 'branch-range'; })
      }.width('100%').padding(2).backgroundColor($r('app.color.surface'))
        .border({ width: Sizes.hairline, color: $r('app.color.border') }).borderRadius(9)

      if (this.mode === 'branch-range') {
        Row() {
          TextInput({ placeholder: '对比分支，如 main', text: this.baseRef })
            .width('100%').height(40).fontSize(FontSize.body).fontColor($r('app.color.ink'))
            .placeholderColor($r('app.color.placeholder')).backgroundColor(Color.Transparent).padding(0)
            .onChange((value: string) => { this.baseRef = value; })
            .onSubmit(() => { void this.load(); })
        }.width('100%').padding({ left: Space.sm, right: Space.sm })
          .backgroundColor($r('app.color.card')).borderRadius(Radius.button)
      }
      if (this.sources.length > 1) {
        Scroll() {
          Row({ space: Space.xs }) {
            ForEach(this.sources, (source: ReviewSource, index: number) => {
              Button(source.title)
                .fontSize(FontSize.caption)
                .fontWeight(index === this.sourceIndex ? Weight.semibold : Weight.medium)
                .constraintSize({ minHeight: 32 }).padding({ left: Space.sm, right: Space.sm }).borderRadius(Radius.tool)
                .backgroundColor(index === this.sourceIndex ? $r('app.color.info_bg') : $r('app.color.card'))
                .fontColor(index === this.sourceIndex ? $r('app.color.primary_text') : $r('app.color.ink'))
                .border({ width: 1, color: index === this.sourceIndex ? $r('app.color.primary') : Color.Transparent })
                .onClick(() => this.selectSource(index))
            }, (source: ReviewSource, index: number) => source.id)
          }
        }.scrollable(ScrollDirection.Horizontal).width('100%').align(Alignment.Start)
      }
    }.width('100%').padding({ left: Space.sm, right: Space.sm, top: Space.xxs, bottom: Space.xs })
  }

  @Builder
  fileList() {
    Column({ space: Space.xs }) {
      if (this.loading) {
        GroupCard() {
          Text('正在读取 Diff…').fontSize(FontSize.callout).fontColor($r('app.color.muted')).width('100%').padding(Space.md)
        }
      } else if (this.error) {
        GroupCard() {
          Text(this.error).fontSize(FontSize.callout).fontColor($r('app.color.danger')).width('100%').padding(Space.md)
        }
      } else if (this.files.length === 0) {
        GroupCard() {
          Text(this.mode === 'working-tree' ? '工作区没有改动' : '没有可显示的差异')
            .fontSize(FontSize.callout).fontColor($r('app.color.muted')).width('100%')
            .textAlign(TextAlign.Center).padding(Space.lg)
        }
      } else {
        List({ space: 0 }) {
          ForEach(this.files, (file: DiffFile) => {
            ListItem() {
              Column({ space: 3 }) {
                Row({ space: Space.xs }) {
                  StatusBadge({
                    text: file.changeType === 'new' ? 'A' : file.changeType === 'deleted' ? 'D' :
                      file.changeType.startsWith('rename') ? 'R' : 'M',
                    tone: file.changeType === 'new' ? 'success' : file.changeType === 'deleted' ? 'danger' : 'neutral'
                  })
                  Text(file.path || file.previousPath).fontSize(FontSize.body).fontColor($r('app.color.ink'))
                    .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text('+' + file.additions).fontSize(FontSize.badge).fontColor($r('app.color.diff_add_ink'))
                  Text('-' + file.deletions).fontSize(FontSize.badge).fontColor($r('app.color.diff_del_ink'))
                }.width('100%').alignItems(VerticalAlign.Center)
                if (file.previousPath && file.previousPath !== file.path) {
                  Text('原路径 ' + file.previousPath).fontSize(FontSize.badge).fontColor($r('app.color.muted')).width('100%')
                }
              }.padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs }).width('100%')
                .constraintSize({ minHeight: Sizes.formRowMin }).justifyContent(FlexAlign.Center)
                .onClick(() => { this.selectedPath = file.path || file.previousPath; this.start = -1; this.end = -1; })
            }
          }, (file: DiffFile) => file.path || file.previousPath)
        }.width('100%').layoutWeight(1)
          .backgroundColor($r('app.color.card')).borderRadius(Radius.card).clip(true)
          .divider({ strokeWidth: Sizes.hairline, color: $r('app.color.separator') })
      }
    }.width('100%').layoutWeight(1).padding({ left: Space.sm, right: Space.sm, bottom: Space.sm })
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
        index <= Math.max(this.start, this.end) ? $r('app.color.info_bg') : this.rowBackground(row))
      .onClick(() => this.pickRow(hunk, index))
  }

  @Builder
  diffDetail() {
    if (this.file()) {
      Column({ space: Space.xs }) {
        Row({ space: Space.xs }) {
          AppButton({
            label: '上一文件', kind: 'secondary', compact: true,
            disabled: this.fileIndex() <= 0,
            onTap: () => this.stepFile(-1)
          })
          AppButton({
            label: '下一文件', kind: 'secondary', compact: true,
            disabled: !(this.fileIndex() >= 0 && this.fileIndex() < this.files.length - 1),
            onTap: () => this.stepFile(1)
          })
          Text((this.fileIndex() + 1) + ' / ' + this.files.length).fontSize(FontSize.caption)
            .fontColor($r('app.color.muted')).layoutWeight(1).textAlign(TextAlign.End)
        }.width('100%').alignItems(VerticalAlign.Center)
        if (this.start >= 0) {
          Row({ space: Space.xs }) {
            Text('已选 ' + (Math.min(this.start, this.end) + 1) + '–' + (Math.max(this.start, this.end) + 1) + ' 行')
              .fontSize(FontSize.caption).fontColor($r('app.color.muted')).layoutWeight(1)
            AppButton({
              label: '复制', kind: 'secondary', compact: true,
              onTap: () => {
                const hunk = this.currentHunk();
                const selected = hunk ? this.diffSelection(hunk) : undefined;
                if (selected) this.onCopy(selected.text);
              }
            })
            AppButton({
              label: '评论', kind: 'primary', compact: true,
              onTap: () => { this.commenting = true; }
            })
          }.width('100%').padding({ left: 12, right: 12, top: Space.xs, bottom: Space.xs })
            .backgroundColor($r('app.color.card')).borderRadius(Radius.card).alignItems(VerticalAlign.Center)
        }
        if (this.hunks().length === 0) {
          GroupCard() {
            Text('该文件没有可显示的文本 Diff（可能是二进制或仅元数据）。')
              .fontSize(FontSize.callout).fontColor($r('app.color.muted')).padding(Space.md)
          }
        }
        List({ space: Space.xs }) {
          ForEach(this.hunks(), (hunk: DiffHunk) => {
            ListItem() {
              Column({ space: 0 }) {
                Text(hunk.header).fontSize(Math.max(8, this.codeFontSize - 2)).fontFamily('monospace').fontColor($r('app.color.muted'))
                  .width('100%').padding({ left: 10, right: 10, top: 6, bottom: 6 }).backgroundColor($r('app.color.surface'))
                ForEach(hunk.rows, (row: DiffRow, index: number) => {
                  this.diffRow(hunk, row, index)
                }, (row: DiffRow, index: number) => hunk.header + ':' + index)
              }.width('100%').backgroundColor($r('app.color.card')).borderRadius(Radius.card).clip(true)
            }
          }, (hunk: DiffHunk) => this.selectedPath + ':' + hunk.header)
        }.width('100%').layoutWeight(1)
        if (this.commenting) {
          GroupCard({ title: '行内评论' }) {
            Column({ space: Space.xs }) {
              TextArea({ placeholder: '说明这段改动的问题或意图', text: this.comment })
                .constraintSize({ minHeight: 88 }).width('100%').fontSize(FontSize.body).fontColor($r('app.color.ink'))
                .placeholderColor($r('app.color.placeholder')).backgroundColor($r('app.color.group')).borderRadius(Radius.tool)
                .padding(Space.xs).onChange((value: string) => { this.comment = value; })
              Row({ space: Space.xs }) {
                AppButton({
                  label: '取消', kind: 'secondary', compact: true,
                  onTap: () => { this.commenting = false; this.comment = ''; }
                })
                AppButton({
                  label: '加入输入', kind: 'primary', compact: true,
                  disabled: !this.comment.trim(),
                  onTap: () => {
                    const hunk = this.currentHunk();
                    if (hunk) this.submitComment(hunk);
                  }
                })
              }.width('100%')
            }.width('100%').padding(12)
          }
        }
      }.width('100%').layoutWeight(1).padding({ left: Space.sm, right: Space.sm, top: Space.xxs, bottom: Space.sm })
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
    Column({ space: 0 }) {
      this.header()
      if (!this.selectedPath) { this.controls() }
      if (this.selectedPath) { this.diffDetail() } else { this.fileList() }
    }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
  }
}
