import { registerSharedFile } from '../services/ShareCache';
import { T3Client } from '../services/T3Client';
import { ContentMatch, directEntries, fileLines, FileLine, isAudio, isImage, isMarkdown, matchesContentSearchLine,
  isPdf, isVideo, WorkspaceEntry, WorkspaceFile } from '../protocol/Files';
import { MarkdownView } from './MarkdownView';
import { CodeLine } from './CodeLine';
import { DiffLineNumber } from './DiffLineNumber';
import { fileCommentContext, fileSelectionContext } from '../protocol/R5';
import { picker, fileIo, fileUri } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { common } from '@kit.AbilityKit';

@Component
export struct FilesPanel {
  @StorageProp('t3CodeFontSize') codeFontSize: number = 13;
  @Prop @Watch('workspaceChanged') cacheScope: string = "";
  connection: T3Client | undefined = undefined;
  @Prop @Watch('workspaceChanged') cwd: string = '';
  @Prop threadId: string = '';
  @Prop title: string = '文件';
  onBack: () => void = () => {};
  onCompose: (record: Object, label: string) => void = () => {};
  onCopy: (value: string) => void = () => {};
  onStatus: (value: string) => void = () => {};

  @State currentDir: string = '';
  @State entries: WorkspaceEntry[] = [];
  @State loading: boolean = false;
  @State error: string = '';
  @State actionStatus: string = '';
  @State query: string = '';
  @State searchCompleted: boolean = false;
  @State searchMode: string = 'entries';
  @State searchEntries: WorkspaceEntry[] = [];
  @State matches: ContentMatch[] = [];
  @State selectedPath: string = '';
  @State file: WorkspaceFile | undefined = undefined;
  @State lines: FileLine[] = [];
  @State linesTruncated: boolean = false;
  @State fileError: string = '';
  @State imageUrl: string = '';
  @State selectionStart: number = -1;
  @State selectionEnd: number = -1;
  @State selectedMatch: ContentMatch | undefined = undefined;
  @State matchNotice: string = '';
  private matchQuery: string = '';
  private sourceLines: string[] = [];
  @State previewStartIndex: number = 0;
  @State wrap: boolean = false;
  @State fileCommentOpen: boolean = false;
  @State fileComment: string = '';
  private generation: number = 0;
  private alive: boolean = false;

  aboutToAppear(): void {
    this.alive = true;
    void this.loadDirectory(this.currentDir);
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.invalidateReads();
  }

  private invalidateReads(): void {
    this.generation++;
    this.loading = false;
  }

  private beginRead(connection: T3Client): () => boolean {
    this.invalidateReads();
    const revision = this.generation;
    const generation = connection.generationValue();
    const cwd = this.cwd;
    const scope = this.cacheScope;
    const threadId = this.threadId;
    return (): boolean => {
      if (!this.alive || this.generation !== revision) return false;
      const current = this.connection === connection && connection.generationValue() === generation &&
        this.cwd === cwd && this.cacheScope === scope && this.threadId === threadId;
      if (!current) this.loading = false;
      return current;
    };
  }

  private workspaceChanged(): void {
    if (!this.alive) return;
    this.closeFile();
    this.currentDir = ''; this.entries = []; this.clearSearchResults();
    this.query = ''; this.error = '';
    void this.loadDirectory('');
  }

  private reportStatus(value: string): void { this.actionStatus = value; this.onStatus(value); }

  private async loadDirectory(path: string): Promise<void> {
    const connection = this.connection;
    const cwd = this.cwd;
    if (!this.alive || !connection || !cwd.trim() || this.selectedPath) return;
    const current = this.beginRead(connection);
    this.loading = true; this.error = ''; this.query = ''; this.clearSearchResults();
    try {
      const rows = await connection.listWorkspaceEntries(cwd, path);
      if (!current()) return;
      this.currentDir = path;
      this.entries = directEntries(rows, path).sort((left: WorkspaceEntry, right: WorkspaceEntry) => {
        if (left.kind !== right.kind) return left.kind === 'directory' ? -1 : 1;
        return left.name.localeCompare(right.name);
      });
    } catch (reason) {
      if (current()) this.error = (reason as Error).message;
    } finally {
      if (current()) this.loading = false;
    }
  }

  private parentDir(): string {
    const parts = this.currentDir.split('/').filter((part: string) => part);
    parts.pop();
    return parts.join('/');
  }

  private clearSearchResults(): void {
    this.searchCompleted = false;
    this.matchQuery = '';
    this.searchEntries = []; this.matches = [];
  }

  private setQuery(value: string): void {
    if (this.query === value) return;
    this.invalidateReads();
    this.query = value; this.error = ''; this.clearSearchResults();
    if (!value.trim() && !this.entries.length && !this.selectedPath) void this.loadDirectory(this.currentDir);
  }

  private setSearchMode(mode: string): void {
    if ((mode !== 'entries' && mode !== 'contents') || mode === this.searchMode) return;
    this.searchMode = mode;
    if (this.query.trim()) void this.runSearch();
  }

  private async runSearch(): Promise<void> {
    const connection = this.connection;
    const cwd = this.cwd;
    const query = this.query.trim();
    const mode = this.searchMode;
    if (!this.alive || !connection || !cwd.trim() || !query || this.selectedPath) return;
    const readActive = this.beginRead(connection);
    const current = (): boolean => readActive() && this.query.trim() === query && this.searchMode === mode && !this.selectedPath;
    this.loading = true; this.error = ''; this.clearSearchResults();
    try {
      if (mode === 'contents') {
        const matches = await connection.searchWorkspaceContents(cwd, query);
        if (current()) {
          this.matchQuery = query.slice(0, 256);
          this.matches = matches;
        }
      } else {
        const paths = await connection.searchFiles(cwd, query);
        if (!current()) return;
        this.searchEntries = paths.map((path: string): WorkspaceEntry => {
          const parts = path.split('/');
          return { path, name: parts[parts.length - 1] || path, kind: 'file', ignored: false,
            depth: Math.max(0, parts.length - 1) };
        });
      }
      if (current()) this.searchCompleted = true;
    } catch (reason) { if (current()) this.error = (reason as Error).message; }
    finally { if (current()) this.loading = false; }
  }

  private async openFile(path: string, match?: ContentMatch): Promise<void> {
    const connection = this.connection;
    if (!connection) return;
    const current = this.beginRead(connection);
    const query = this.matchQuery;
    this.selectedPath = path; this.file = undefined; this.lines = []; this.linesTruncated = false;
    this.sourceLines = [];
    this.fileCommentOpen = false; this.fileComment = '';
    this.fileError = ''; this.imageUrl = '';
    this.selectedMatch = match; this.matchNotice = ''; this.previewStartIndex = 0;
    this.selectionStart = -1; this.selectionEnd = -1;
    this.loading = true;
    try {
      if (isImage(path) || isVideo(path) || isAudio(path) || isPdf(path)) {
        const url = await connection.workspaceFileUrl(this.cwd, path, true);
        if (current()) this.imageUrl = url;
      } else {
        const file = await connection.readWorkspaceFile(this.cwd, path);
        if (!current()) return;
        this.file = file;
        this.lines = fileLines(file.contents, 5000);
        this.linesTruncated = file.truncated || this.lines.length >= 5000;
        const original = file.contents.replace(/\r\n?/g, '\n').split('\n', 5001);
        // The last segment of a server-truncated preview may end mid-line.
        if (file.truncated && original.length <= 5000) original.pop();
        this.sourceLines = original.slice(0, 5000);
        if (match) {
          const line = match.lineNumber;
          if (!Number.isInteger(line) || line < 1 || line > this.sourceLines.length) {
            this.matchNotice = '搜索命中行不在当前预览中。';
          } else if (!matchesContentSearchLine(this.sourceLines[line - 1], match.lineContent, query)) {
            this.matchNotice = '当前预览与搜索命中行不一致，请重新搜索。';
          } else {
            if (this.lines[line - 1].text !== this.sourceLines[line - 1].replace(/\t/g, '    ')) {
              this.matchNotice = '预览只显示这行的开头；复制选区可保留整行原文。';
            }
            this.previewStartIndex = line - 1;
            this.selectionStart = this.previewStartIndex; this.selectionEnd = this.previewStartIndex;
          }
        }
      }
    } catch (reason) { if (current()) this.fileError = (reason as Error).message; }
    finally { if (current()) this.loading = false; }
  }

  private closeFile(): void {
    this.invalidateReads();
    this.selectedPath = ''; this.file = undefined; this.lines = []; this.linesTruncated = false;
    this.sourceLines = [];
    this.imageUrl = ''; this.fileError = ''; this.fileCommentOpen = false; this.fileComment = '';
    this.selectionStart = -1; this.selectionEnd = -1; this.selectedMatch = undefined;
    this.matchNotice = ''; this.previewStartIndex = 0;
  }

  private selectLine(index: number): void {
    if (index < 0 || index >= this.sourceLines.length) {
      this.reportStatus('该行在服务预览中不完整，无法选取。');
      return;
    }
    if (this.selectionStart < 0 || this.selectionStart !== this.selectionEnd) {
      this.selectionStart = index; this.selectionEnd = index;
    } else {
      this.selectionEnd = index;
    }
  }

  private selectedText(): string {
    if (!this.file || this.selectionStart < 0) return this.file ? this.file.contents : '';
    const from = Math.min(this.selectionStart, this.selectionEnd);
    const to = Math.max(this.selectionStart, this.selectionEnd);
    return this.sourceLines.slice(from, to + 1).join('\n');
  }

  private addSelectionContext(): void {
    if (!this.file || this.selectionStart < 0) { this.reportStatus('请先选择行'); return; }
    const from = Math.min(this.selectionStart, this.selectionEnd);
    const to = Math.max(this.selectionStart, this.selectionEnd);
    const text = this.selectedText();
    const contextId = 'file_' + Date.now().toString(36);
    this.onCompose(fileSelectionContext(this.selectedPath, from, to, text, contextId), this.selectedPath);
    this.selectionStart = -1; this.selectionEnd = -1;
    this.reportStatus('已加入输入上下文');
  }

  private submitFileComment(): void {
    try {
      const context = fileCommentContext(this.selectedPath, this.fileComment, 'file_' + Date.now().toString(36));
      this.onCompose(context, this.selectedPath + ' · 文件评论');
      this.fileComment = ''; this.fileCommentOpen = false;
      this.reportStatus('文件评论已加入输入上下文');
    } catch (reason) { this.reportStatus((reason as Error).message); }
  }

  private async saveFile(): Promise<void> {
    const connection = this.connection;
    if (!connection || !this.selectedPath) return;
    try {
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [this.selectedPath.split('/').pop() || 'file'];
      const target = await new picker.DocumentViewPicker().save(options);
      if (!target.length) { this.reportStatus('已取消保存'); return; }
      const bytes = await connection.downloadWorkspaceFile(this.cwd, this.selectedPath);
      const handle = fileIo.openSync(target[0], fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try { fileIo.writeSync(handle.fd, bytes); fileIo.fsyncSync(handle.fd); } finally { fileIo.closeSync(handle); }
      this.reportStatus('已保存到所选位置');
    } catch (reason) { this.reportStatus('保存失败：' + (reason as Error).message); }
  }

  private async shareFile(): Promise<void> {
    const connection = this.connection;
    const scope = this.cacheScope;
    const generation = this.generation;
    if (!connection || !this.selectedPath) return;
    try {
      const bytes = await connection.downloadWorkspaceFile(this.cwd, this.selectedPath);
      if (generation !== this.generation || connection !== this.connection || scope !== this.cacheScope) throw new Error('分享目标已变化');
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const name = (this.selectedPath.split('/').pop() || 'file').replace(/[\\/:*?"<>|\x00-\x1f]/g, '_');
      const path = context.cacheDir + '/share-' + Date.now() + '-' + name;
      const handle = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try { fileIo.writeSync(handle.fd, bytes); fileIo.fsyncSync(handle.fd); } finally { fileIo.closeSync(handle); }
      registerSharedFile(context.cacheDir, path.substring(context.cacheDir.length + 1), scope);
      const shared = new systemShare.SharedData({ utd: 'general.file', uri: fileUri.getUriFromPath(path), title: name });
      await new systemShare.ShareController(shared).show(context, {});
      this.reportStatus('已打开系统分享');
    } catch (reason) { this.reportStatus('分享失败：' + (reason as Error).message); }
  }

  @Builder
  header() {
    Row({ space: 6 }) {
      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.ui_back')).width(22).height(22)
      }.backgroundColor(Color.Transparent).width(44).height(44).accessibilityText('返回').onClick(() => {
          if (this.selectedPath) { this.closeFile(); return; }
          if (this.currentDir) { void this.loadDirectory(this.parentDir()); return; }
          this.onBack();
        })
      Column({ space: 2 }) {
        Text(this.selectedPath ? (this.selectedPath.split('/').pop() || this.selectedPath) : this.title)
          .fontSize(17).fontWeight(FontWeight.Medium).width('100%').maxLines(2).wordBreak(WordBreak.BREAK_ALL)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.selectedPath ? (this.selectedPath.includes('/') ? this.selectedPath.slice(0, this.selectedPath.lastIndexOf('/')) : this.cwd) : (this.currentDir ? '/' + this.currentDir : this.cwd))
          .fontSize(11).fontColor($r('app.color.muted')).width('100%').maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (this.selectedPath) {
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ui_more')).width(22).height(22)
        }.width(44).height(44).backgroundColor(Color.Transparent).accessibilityText('文件操作')
          .bindMenu([
            { value: '复制路径', action: () => this.onCopy(this.selectedPath) },
            { value: this.fileCommentOpen ? '关闭文件评论' : '文件评论',
              action: () => { this.fileCommentOpen = !this.fileCommentOpen; } },
            { value: '分享', action: () => { void this.shareFile(); } },
            { value: '保存到文件', action: () => { void this.saveFile(); } }
          ])
      }
    }.width('100%').padding({ left: 8, right: 8, top: 4, bottom: 4 })
  }

  @Builder
  browser() {
    Column({ space: 10 }) {
      Row({ space: 6 }) {
        Row() {
          TextInput({ placeholder: this.searchMode === 'contents' ? '搜索文件内容' : '搜索文件名', text: this.query })
            .layoutWeight(1).constraintSize({ minHeight: 44 }).backgroundColor(Color.Transparent)
            .fontColor($r('app.color.ink')).onChange((value: string) => this.setQuery(value))
            .onSubmit(() => { void this.runSearch(); })
          if (this.query) {
            Button('×').width(44).constraintSize({ minHeight: 44 }).backgroundColor(Color.Transparent)
              .fontColor($r('app.color.muted')).accessibilityText('清除搜索').onClick(() => this.setQuery(''))
          }
        }.layoutWeight(1).backgroundColor($r('app.color.surface')).borderRadius(12)
        Button('搜索').fontSize(14).constraintSize({ minHeight: 44 }).backgroundColor($r('app.color.surface'))
          .fontColor($r('app.color.ink')).enabled(!!this.query.trim() && !this.loading)
          .onClick(() => { void this.runSearch(); })
      }.width('100%')
      Row({ space: 6 }) {
        Button(this.searchMode === 'entries' ? '✓ 文件名' : '文件名').fontSize(14).layoutWeight(1)
          .constraintSize({ minHeight: 44 }).backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink'))
          .onClick(() => this.setSearchMode('entries'))
        Button(this.searchMode === 'contents' ? '✓ 文件内容' : '文件内容').fontSize(14).layoutWeight(1)
          .constraintSize({ minHeight: 44 }).backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink'))
          .onClick(() => this.setSearchMode('contents'))
      }.width('100%')
      if (this.loading) { Text('正在读取…').fontSize(13).fontColor($r('app.color.muted')).width('100%') }
      if (this.error) { Text(this.error).fontSize(13).fontColor($r('app.color.danger')).width('100%') }
      List({ space: 1 }) {
        if (!this.query.trim()) {
          if (this.currentDir) {
            ListItem() {
              Row({ space: 8 }) {
                Image($r('app.media.ui_up')).width(20).height(20)
                Text('上一级').fontSize(15).layoutWeight(1)
              }.constraintSize({ minHeight: 48 }).width('100%').padding({ left: 12, right: 12 })
                .onClick(() => { void this.loadDirectory(this.parentDir()); })
            }
          }
          ForEach(this.entries, (entry: WorkspaceEntry) => {
            ListItem() {
              Row({ space: 8 }) {
                if (entry.kind === 'directory') {
                  Image($r('app.media.ui_folder')).width(20).height(20)
                } else {
                  Text(isImage(entry.path) ? '图片' : isVideo(entry.path) ? '视频' : isAudio(entry.path) ? '音频' : isPdf(entry.path) ? 'PDF' : isMarkdown(entry.path) ? 'MD' : '文件')
                    .fontSize(10).fontColor($r('app.color.muted')).width(28)
                }
                Text(entry.name).fontSize(15).layoutWeight(1).maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (entry.ignored) { Text('忽略').fontSize(10).fontColor($r('app.color.muted')) }
                if (entry.kind === 'directory') { Image($r('app.media.ui_back')).width(16).height(16).rotate({ angle: 180 }) }
              }.constraintSize({ minHeight: 48 }).width('100%').padding({ left: 12, right: 12 })
                .onClick(() => {
                  if (entry.kind === 'directory') void this.loadDirectory(entry.path);
                  else void this.openFile(entry.path);
                })
            }
          }, (entry: WorkspaceEntry) => entry.path)
        } else {
          ForEach(this.matches, (match: ContentMatch) => {
            ListItem() {
              Column({ space: 3 }) {
                Text(match.path + ':' + match.lineNumber).fontSize(12).fontColor($r('app.color.muted')).width('100%')
                Text(match.lineContent).fontSize(13).fontFamily('monospace').width('100%').maxLines(2)
              }.padding(10).width('100%').onClick(() => { void this.openFile(match.path, match); })
            }
          }, (match: ContentMatch) => match.path + ':' + match.lineNumber + ':' + match.lineContent)
          ForEach(this.searchEntries, (entry: WorkspaceEntry) => {
            ListItem() {
              Row({ space: 8 }) {
                if (entry.kind === 'directory') {
                  Image($r('app.media.ui_folder')).width(20).height(20)
                } else {
                  Text(isImage(entry.path) ? '图片' : isVideo(entry.path) ? '视频' : isAudio(entry.path) ? '音频' : isPdf(entry.path) ? 'PDF' : isMarkdown(entry.path) ? 'MD' : '文件')
                    .fontSize(10).fontColor($r('app.color.muted')).width(28)
                }
                Text(entry.path).fontSize(14).layoutWeight(1).maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }.constraintSize({ minHeight: 48 }).padding({ left: 12, right: 12 }).width('100%')
                .onClick(() => { void this.openFile(entry.path); })
            }
          }, (entry: WorkspaceEntry) => entry.path)
          if (this.searchCompleted && !this.loading && !this.error && this.matches.length === 0 && this.searchEntries.length === 0) {
            ListItem() { Text('没有匹配结果').fontSize(13).fontColor($r('app.color.muted')).padding(20) }
          }
        }
      }.width('100%').layoutWeight(1)
    }.width('100%').layoutWeight(1)
  }

  @Builder
  selectionBar() {
    Row({ space: 8 }) {
      Text(this.selectionStart < 0 ? '点按代码行以选取' :
        (this.selectionStart === this.selectionEnd ? '已选行 ' + (this.selectionStart + 1) :
          '已选行 ' + (Math.min(this.selectionStart, this.selectionEnd) + 1) + '–' +
          (Math.max(this.selectionStart, this.selectionEnd) + 1)))
        .fontSize(12).fontColor($r('app.color.muted')).layoutWeight(1)
      Button('复制选区').fontSize(12).backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
        .onClick(() => this.onCopy(this.selectedText()))
      Button('加入上下文').fontSize(12).backgroundColor($r('app.color.primary'))
        .fontColor($r('app.color.on_primary')).onClick(() => this.addSelectionContext())
    }.width('100%').padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor($r('app.color.surface')).borderRadius(10)
  }

  @Builder
  preview() {
    Column({ space: 8 }) {
      if (this.fileCommentOpen && this.selectedPath) {
        Column({ space: 8 }) {
          TextArea({ placeholder: '针对整个文件的评论', text: this.fileComment })
            .height(80).width('100%').onChange((value: string) => { this.fileComment = value; })
          Row({ space: 8 }) {
            Button('取消').fontSize(12).onClick(() => { this.fileCommentOpen = false; this.fileComment = ''; })
            Button('加入输入').fontSize(12).enabled(!!this.fileComment.trim())
              .onClick(() => this.submitFileComment())
          }.width('100%')
        }.width('100%').padding(10).backgroundColor($r('app.color.surface')).borderRadius(10)
      }
      if (this.loading) {
        Text('正在打开…').fontSize(13).fontColor($r('app.color.muted')).padding(20)
      } else if (this.fileError) {
        Text(this.fileError).fontSize(13).fontColor($r('app.color.danger')).padding(20)
        Button('重试').onClick(() => { void this.openFile(this.selectedPath, this.selectedMatch); })
      } else if (this.imageUrl && isImage(this.selectedPath)) {
        Scroll() {
          Image(this.imageUrl).width('100%').objectFit(ImageFit.Contain)
        }.width('100%').layoutWeight(1)
      } else if (this.imageUrl && isVideo(this.selectedPath)) {
        Video({ src: this.imageUrl }).width('100%').height(320).controls(true)
      } else if (this.imageUrl) {
        Column({ space: 10 }) {
          Text('此文件类型使用系统打开/分享').fontSize(13).fontColor($r('app.color.muted'))
          Text(this.selectedPath).fontSize(12).fontColor($r('app.color.muted'))
        }.padding(20).width('100%')
      } else if (this.file) {
        if (this.linesTruncated) {
          Text('文件较大，仅显示前 5000 行或服务端预览片段').fontSize(11).fontColor($r('app.color.danger'))
            .width('100%').padding({ left: 12, right: 12 })
        }
        if (this.matchNotice) {
          Text(this.matchNotice).fontSize(13).fontColor($r('app.color.muted')).width('100%')
            .padding({ left: 12, right: 12 })
        }
        if (isMarkdown(this.selectedPath) && !this.selectedMatch) {
          Scroll() {
            Column() {
              if (this.selectionStart >= 0) { this.selectionBar() }
              MarkdownView({ markdown: this.file.contents, selectable: true, onCopy: this.onCopy,
                onOpenLink: () => this.reportStatus('请从会话消息打开链接'),
                onOpenImage: (path: string) => { void this.openFile(path); } })
            }.padding(14)
          }.width('100%').layoutWeight(1).align(Alignment.TopStart)
        } else {
          if (this.selectionStart >= 0) { this.selectionBar() }
          List({ space: 0, initialIndex: this.previewStartIndex }) {
            ForEach(this.lines, (line: FileLine, index: number) => {
              ListItem() {
                Row({ space: 0 }) {
                  DiffLineNumber({ line: line.number, lastLine: this.lines.length,
                    active: index >= Math.min(this.selectionStart < 0 ? -1 : this.selectionStart, this.selectionEnd < 0 ? -1 : this.selectionEnd) &&
                      this.selectionStart >= 0 && index <= Math.max(this.selectionStart, this.selectionEnd) })
                  CodeLine({ text: line.text }).layoutWeight(1)
                }.width('100%').constraintSize({ minHeight: (this.codeFontSize + 15) + 'fp' })
                  .alignItems(VerticalAlign.Top)
                  .backgroundColor(this.selectionStart >= 0 &&
                    index >= Math.min(this.selectionStart, this.selectionEnd) &&
                    index <= Math.max(this.selectionStart, this.selectionEnd) ? $r('app.color.selected') : Color.Transparent)
                  .onClick(() => this.selectLine(index))
              }
            }, (line: FileLine) => String(line.number))
          }.width('100%').layoutWeight(1)
        }
      }
    }.width('100%').layoutWeight(1)
  }

  build() {
    Column({ space: 4 }) {
      this.header()
      if (this.actionStatus) { Text(this.actionStatus).fontSize(13).fontColor($r('app.color.muted')).width('100%').padding({ left: 16, right: 16, bottom: 8 }) }
      Divider().color($r('app.color.border'))
      if (this.selectedPath) { this.preview() } else { this.browser() }
    }.width('100%').height('100%').backgroundColor($r('app.color.canvas')).foregroundColor($r('app.color.ink'))
  }
}
