import { TopBar } from './ui/TopBar';
import { IconButton } from './ui/IconButton';
import { GroupCard } from './ui/GroupCard';
import { AppButton } from './ui/AppButton';
import { StatusBadge } from './ui/StatusBadge';
import { FontSize, LineHeight, Radius, Sizes, Space, Weight } from '../common/Theme';
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
    TopBar({
      title: this.selectedPath ? (this.selectedPath.split('/').pop() || this.selectedPath) : this.title,
      subtitle: this.selectedPath ? (this.selectedPath.includes('/') ? this.selectedPath.slice(0, this.selectedPath.lastIndexOf('/')) : this.cwd) : (this.currentDir ? '/' + this.currentDir : this.cwd),
      showBack: true,
      closeStyle: !this.selectedPath && !this.currentDir,
      backLabel: this.selectedPath || this.currentDir ? '返回' : '关闭文件',
      onBack: () => {
        if (this.selectedPath) { this.closeFile(); return; }
        if (this.currentDir) { void this.loadDirectory(this.parentDir()); return; }
        this.onBack();
      }
    }) {
      if (this.selectedPath) {
        IconButton({
          icon: $r('app.media.ui_more'),
          label: '文件操作',
          onTap: () => {}
        })
          .bindMenu([
            { value: '复制路径', action: () => this.onCopy(this.selectedPath) },
            { value: this.fileCommentOpen ? '关闭文件评论' : '文件评论',
              action: () => { this.fileCommentOpen = !this.fileCommentOpen; } },
            { value: '分享', action: () => { void this.shareFile(); } },
            { value: '保存到文件', action: () => { void this.saveFile(); } }
          ])
      }
    }
  }

  @Builder
  browser() {
    Column({ space: Space.xs }) {
      Row({ space: Space.xs }) {
        Image($r('app.media.ui_search')).width(16).height(16).opacity(0.6).accessibilityLevel('no')
        TextInput({ placeholder: this.searchMode === 'contents' ? '搜索文件内容' : '搜索文件名', text: this.query })
          .layoutWeight(1).height(40).fontSize(FontSize.body).fontColor($r('app.color.ink'))
          .placeholderColor($r('app.color.placeholder')).backgroundColor(Color.Transparent).padding(0)
          .onChange((value: string) => this.setQuery(value))
          .onSubmit(() => { void this.runSearch(); })
        if (this.query) {
          Button('×').width(32).height(32).backgroundColor(Color.Transparent).fontSize(FontSize.headline)
            .fontColor($r('app.color.muted')).accessibilityText('清除搜索').onClick(() => this.setQuery(''))
        }
        AppButton({
          label: '搜索',
          kind: 'secondary',
          compact: true,
          disabled: !this.query.trim() || this.loading,
          onTap: () => { void this.runSearch(); }
        })
      }.width('100%').padding({ left: Space.sm, right: 6, top: 4, bottom: 4 })
        .backgroundColor($r('app.color.card')).borderRadius(Radius.card).alignItems(VerticalAlign.Center)

      Row({ space: 2 }) {
        Button('文件名')
          .fontSize(FontSize.callout)
          .fontWeight(this.searchMode === 'entries' ? Weight.medium : Weight.regular)
          .fontColor(this.searchMode === 'entries' ? $r('app.color.ink') : $r('app.color.muted'))
          .backgroundColor(this.searchMode === 'entries' ? $r('app.color.card') : Color.Transparent)
          .borderRadius(7).layoutWeight(1).constraintSize({ minHeight: 34 })
          .onClick(() => this.setSearchMode('entries'))
        Button('文件内容')
          .fontSize(FontSize.callout)
          .fontWeight(this.searchMode === 'contents' ? Weight.medium : Weight.regular)
          .fontColor(this.searchMode === 'contents' ? $r('app.color.ink') : $r('app.color.muted'))
          .backgroundColor(this.searchMode === 'contents' ? $r('app.color.card') : Color.Transparent)
          .borderRadius(7).layoutWeight(1).constraintSize({ minHeight: 34 })
          .onClick(() => this.setSearchMode('contents'))
      }.width('100%').padding(2).backgroundColor($r('app.color.surface')).border({ width: Sizes.hairline, color: $r('app.color.border') }).borderRadius(9)

      if (this.loading) {
        Text('正在读取…').fontSize(FontSize.callout).fontColor($r('app.color.muted')).width('100%')
          .padding({ left: Space.xxs, right: Space.xxs })
      }
      if (this.error) {
        Text(this.error).fontSize(FontSize.callout).fontColor($r('app.color.danger')).width('100%')
          .padding({ left: Space.xxs, right: Space.xxs })
      }

      if (!this.query.trim() ? (this.entries.length > 0 || !!this.currentDir) :
        (this.matches.length > 0 || this.searchEntries.length > 0 || (this.searchCompleted && !this.loading && !this.error))) {
        List({ space: 0 }) {
          if (!this.query.trim()) {
            if (this.currentDir) {
              ListItem() {
                Row({ space: Space.xs }) {
                  Image($r('app.media.ui_down')).width(18).height(18).rotate({ angle: 180 }).opacity(0.75).accessibilityLevel('no')
                  Text('上一级').fontSize(FontSize.body).fontWeight(Weight.medium).fontColor($r('app.color.ink')).layoutWeight(1)
                }.constraintSize({ minHeight: Sizes.formRowMin }).width('100%').padding({ left: 14, right: 14 })
                  .onClick(() => { void this.loadDirectory(this.parentDir()); })
              }
            }
            ForEach(this.entries, (entry: WorkspaceEntry) => {
              ListItem() {
                Row({ space: Space.xs }) {
                  if (entry.kind === 'directory') {
                    Image($r('app.media.ui_folder')).width(18).height(18).accessibilityLevel('no')
                  } else {
                    StatusBadge({
                      text: isImage(entry.path) ? '图片' : isVideo(entry.path) ? '视频' : isAudio(entry.path) ? '音频' : isPdf(entry.path) ? 'PDF' : isMarkdown(entry.path) ? 'MD' : '文件',
                      tone: 'neutral'
                    })
                  }
                  Text(entry.name).fontSize(FontSize.body).fontColor($r('app.color.ink')).layoutWeight(1).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (entry.ignored) { StatusBadge({ text: '忽略', tone: 'neutral' }) }
                  if (entry.kind === 'directory') {
                    Image($r('app.media.ui_chevron_right')).width(Sizes.chevron).height(Sizes.chevron).opacity(0.6).accessibilityLevel('no')
                  }
                }.constraintSize({ minHeight: Sizes.formRowMin }).width('100%').padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
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
                  Text(match.path + ':' + match.lineNumber).fontSize(FontSize.caption).fontColor($r('app.color.muted')).width('100%')
                  Text(match.lineContent).fontSize(FontSize.mono).fontFamily('monospace').fontColor($r('app.color.ink')).width('100%').maxLines(2)
                }.padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs }).width('100%')
                  .constraintSize({ minHeight: Sizes.formRowMin }).alignItems(HorizontalAlign.Start)
                  .onClick(() => { void this.openFile(match.path, match); })
              }
            }, (match: ContentMatch) => match.path + ':' + match.lineNumber + ':' + match.lineContent)
            ForEach(this.searchEntries, (entry: WorkspaceEntry) => {
              ListItem() {
                Row({ space: Space.xs }) {
                  if (entry.kind === 'directory') {
                    Image($r('app.media.ui_folder')).width(18).height(18).accessibilityLevel('no')
                  } else {
                    StatusBadge({
                      text: isImage(entry.path) ? '图片' : isVideo(entry.path) ? '视频' : isAudio(entry.path) ? '音频' : isPdf(entry.path) ? 'PDF' : isMarkdown(entry.path) ? 'MD' : '文件',
                      tone: 'neutral'
                    })
                  }
                  Text(entry.path).fontSize(FontSize.callout).fontColor($r('app.color.ink')).layoutWeight(1).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }.constraintSize({ minHeight: Sizes.formRowMin }).padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs }).width('100%')
                  .onClick(() => { void this.openFile(entry.path); })
              }
            }, (entry: WorkspaceEntry) => entry.path)
            if (this.searchCompleted && !this.loading && !this.error && this.matches.length === 0 && this.searchEntries.length === 0) {
              ListItem() {
                Text('没有匹配结果').fontSize(FontSize.body).fontColor($r('app.color.muted'))
                  .width('100%').textAlign(TextAlign.Center).padding(Space.lg)
              }
            }
          }
        }
        .width('100%').layoutWeight(1)
        .backgroundColor($r('app.color.card')).borderRadius(Radius.card).clip(true)
        .divider({ strokeWidth: Sizes.hairline, color: $r('app.color.separator') })
      }
    }.width('100%').layoutWeight(1).padding({ left: Space.sm, right: Space.sm, top: Space.xxs, bottom: Space.sm })
  }

  @Builder
  selectionBar() {
    Row({ space: Space.xs }) {
      Text(this.selectionStart < 0 ? '点按代码行以选取' :
        (this.selectionStart === this.selectionEnd ? '已选行 ' + (this.selectionStart + 1) :
          '已选行 ' + (Math.min(this.selectionStart, this.selectionEnd) + 1) + '–' +
          (Math.max(this.selectionStart, this.selectionEnd) + 1)))
        .fontSize(FontSize.caption).fontColor($r('app.color.muted')).layoutWeight(1)
      AppButton({
        label: '复制选区', kind: 'secondary', compact: true,
        onTap: () => this.onCopy(this.selectedText())
      })
      AppButton({
        label: '加入上下文', kind: 'primary', compact: true,
        onTap: () => this.addSelectionContext()
      })
    }.width('100%').padding({ left: 12, right: 12, top: Space.xs, bottom: Space.xs })
      .backgroundColor($r('app.color.card')).borderRadius(Radius.card).alignItems(VerticalAlign.Center)
  }

  @Builder
  preview() {
    Column({ space: Space.xs }) {
      if (this.fileCommentOpen && this.selectedPath) {
        GroupCard({ title: '文件评论' }) {
          Column({ space: Space.xs }) {
            TextArea({ placeholder: '针对整个文件的评论', text: this.fileComment })
              .constraintSize({ minHeight: 80 }).width('100%').fontSize(FontSize.body).fontColor($r('app.color.ink'))
              .placeholderColor($r('app.color.placeholder')).backgroundColor($r('app.color.group')).borderRadius(Radius.tool)
              .padding(Space.xs).onChange((value: string) => { this.fileComment = value; })
            Row({ space: Space.xs }) {
              AppButton({
                label: '取消', kind: 'secondary', compact: true,
                onTap: () => { this.fileCommentOpen = false; this.fileComment = ''; }
              })
              AppButton({
                label: '加入输入', kind: 'primary', compact: true, disabled: !this.fileComment.trim(),
                onTap: () => this.submitFileComment()
              })
            }.width('100%')
          }.width('100%').padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
        }
      }
      if (this.loading) {
        Text('正在打开…').fontSize(FontSize.callout).fontColor($r('app.color.muted')).padding(Space.md)
      } else if (this.fileError) {
        GroupCard() {
          Column({ space: Space.xs }) {
            Text(this.fileError).fontSize(FontSize.callout).fontColor($r('app.color.danger')).width('100%')
            AppButton({
              label: '重试', kind: 'secondary', compact: true,
              onTap: () => { void this.openFile(this.selectedPath, this.selectedMatch); }
            })
          }.width('100%').padding(14).alignItems(HorizontalAlign.Start)
        }
      } else if (this.imageUrl && isImage(this.selectedPath)) {
        Scroll() {
          Image(this.imageUrl).width('100%').objectFit(ImageFit.Contain)
        }.width('100%').layoutWeight(1).backgroundColor($r('app.color.card')).borderRadius(Radius.card).clip(true)
      } else if (this.imageUrl && isVideo(this.selectedPath)) {
        Video({ src: this.imageUrl }).width('100%').height(320).controls(true).borderRadius(Radius.card).clip(true)
      } else if (this.imageUrl) {
        GroupCard() {
          Column({ space: Space.xs }) {
            Text('此文件类型使用系统打开/分享').fontSize(FontSize.body).fontColor($r('app.color.ink'))
            Text(this.selectedPath).fontSize(FontSize.caption).fontColor($r('app.color.muted'))
          }.padding(14).width('100%').alignItems(HorizontalAlign.Start)
        }
      } else if (this.file) {
        if (this.linesTruncated) {
          Text('文件较大，仅显示前 5000 行或服务端预览片段').fontSize(FontSize.caption).fontColor($r('app.color.danger'))
            .width('100%').padding({ left: Space.xxs, right: Space.xxs })
        }
        if (this.matchNotice) {
          Text(this.matchNotice).fontSize(FontSize.callout).fontColor($r('app.color.muted')).width('100%')
            .padding({ left: Space.xxs, right: Space.xxs })
        }
        if (isMarkdown(this.selectedPath) && !this.selectedMatch) {
          if (this.selectionStart >= 0) { this.selectionBar() }
          Scroll() {
            Column() {
              MarkdownView({ markdown: this.file.contents, selectable: true, onCopy: this.onCopy,
                onOpenLink: () => this.reportStatus('请从会话消息打开链接'),
                onOpenImage: (path: string) => { void this.openFile(path); } })
            }.padding(14)
          }.width('100%').layoutWeight(1).align(Alignment.TopStart)
            .backgroundColor($r('app.color.card')).borderRadius(Radius.card).clip(true)
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
                    index <= Math.max(this.selectionStart, this.selectionEnd) ? $r('app.color.info_bg') : Color.Transparent)
                  .onClick(() => this.selectLine(index))
              }
            }, (line: FileLine) => String(line.number))
          }.width('100%').layoutWeight(1)
            .backgroundColor($r('app.color.card')).borderRadius(Radius.card).clip(true)
        }
      }
    }.width('100%').layoutWeight(1).padding({ left: Space.sm, right: Space.sm, top: Space.xxs, bottom: Space.sm })
  }

  build() {
    Column({ space: 0 }) {
      this.header()
      if (this.actionStatus) {
        Text(this.actionStatus).fontSize(FontSize.callout).fontColor($r('app.color.primary_text'))
          .width('100%').padding({ left: Space.md, right: Space.md, bottom: Space.xs })
      }
      if (this.selectedPath) { this.preview() } else { this.browser() }
    }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
  }
}
