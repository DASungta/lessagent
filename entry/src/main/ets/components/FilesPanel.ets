import { TopBar } from './ui/TopBar';
import { IconButton } from './ui/IconButton';
import { GroupCard } from './ui/GroupCard';
import { AppButton } from './ui/AppButton';
import { StatusBadge } from './ui/StatusBadge';
import { FontSize, LineHeight, Radius, Sizes, Space, Weight } from '../common/Theme';
import { T3Client } from '../services/T3Client';
import { ContentMatch, directEntries, fileLines, FileLine, isAudio, isDelimited, isHtml, isImage, isMarkdown,
  matchesContentSearchLine, isPdf, isRtf, isVideo, isZip, WorkspaceEntry, WorkspaceFile } from '../protocol/Files';
import {
  DelimitedTable,
  detectCodeLanguage,
  hasOversizedMarkdownChunk,
  listZipDirectory,
  MarkdownChunk,
  MOBILE_FULL_FILE_MAX_BYTES,
  parseDelimitedPreview,
  parseRtfToText,
  parseZipEntries,
  splitMarkdown,
  withMarkdownDefinitions,
  ZipBrowserItem,
  ZipEntry
} from '../protocol/FilePreview';
import { AudioPlayerView } from './AudioPlayerView';
import { canSaveToPhotoGallery, mediaFileName } from '../protocol/MediaTransfer';
import { saveBytesToDocumentPicker, saveBytesToPhotoGallery, shareBytesWithSystemSheet } from '../services/MediaActions';
import { HtmlRenderWebView } from './HtmlRenderView';
import { MarkdownView } from './MarkdownView';
import { ResolvedMarkdownMedia, resolveRelativeMarkdownPath } from '../protocol/Markdown';
import { CodeLine } from './CodeLine';
import { DiffLineNumber } from './DiffLineNumber';
import { fileCommentContext, fileSelectionContext } from '../protocol/R5';
import { common } from '@kit.AbilityKit';

@Component
export struct FilesPanel {
  @StorageProp('t3CodeFontSize') codeFontSize: number = 13;
  @Prop @Watch('workspaceChanged') cacheScope: string = "";
  connection: T3Client | undefined = undefined;
  @Prop @Watch('workspaceChanged') cwd: string = '';
  @Prop threadId: string = '';
  @Prop title: string = '文件';
  @Prop initialPath: string = '';
  @Prop initialDir: string = '';
  @Prop initialLine: number = 0;
  @Prop directFileOnly: boolean = false;
  onBack: () => void = () => {};
  onCompose: (record: Object, label: string) => void = () => {};
  onCopy: (value: string) => void = () => {};
  onStatus: (value: string) => void = () => {};
  onOpenExternalLink: (url: string) => void = () => {};
  onOpenLink: (url: string) => void = () => {};

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
  @State htmlMode: 'preview' | 'source' = 'preview';
  @State richMode: 'preview' | 'source' = 'preview';
  @State fullTextLoading: boolean = false;
  @State markdownChunks: MarkdownChunk[] = [];
  @State markdownDefinitions: string = '';
  @State markdownFallbackSource: boolean = false;
  @State delimitedTable: DelimitedTable | undefined = undefined;
  @State rtfText: string = '';
  @State zipEntries: ZipEntry[] = [];
  @State zipDir: string = '';
  @State zipError: string = '';
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
  @State mediaBusy: boolean = false;
  private generation: number = 0;
  private alive: boolean = false;

  aboutToAppear(): void {
    this.alive = true;
    if (this.initialPath) {
      void this.openFile(this.initialPath, undefined, this.initialLine > 0 ? 'source' : 'preview', this.initialLine);
      return;
    }
    if (this.initialDir) {
      this.currentDir = this.initialDir;
    }
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

  private applyTextContents(
    path: string,
    contents: string,
    truncated: boolean,
    match: ContentMatch | undefined,
    jumpLine: number,
    query: string
  ): void {
    const lineCap = truncated ? 5000 : 50000;
    this.lines = fileLines(contents, lineCap);
    this.linesTruncated = truncated || this.lines.length >= lineCap;
    const original = contents.replace(/\r\n?/g, '\n').split('\n', lineCap + 1);
    if (truncated && original.length <= lineCap) original.pop();
    this.sourceLines = original.slice(0, lineCap);
    this.markdownChunks = [];
    this.markdownDefinitions = '';
    this.markdownFallbackSource = false;
    this.delimitedTable = undefined;
    this.rtfText = '';
    if (isMarkdown(path)) {
      if (contents.length > 8192) {
        const split = splitMarkdown(contents);
        this.markdownChunks = split.chunks;
        this.markdownDefinitions = split.definitions;
        this.markdownFallbackSource = hasOversizedMarkdownChunk(split);
      } else {
        this.markdownChunks = [{ text: contents, lines: this.lines.length }];
      }
    } else if (isDelimited(path)) {
      this.delimitedTable = parseDelimitedPreview(contents, path);
    } else if (isRtf(path)) {
      this.rtfText = parseRtfToText(contents);
    }
    this.matchNotice = '';
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
        this.selectionStart = this.previewStartIndex;
        this.selectionEnd = this.previewStartIndex;
      }
    } else if (jumpLine > 0 && this.lines.length > 0) {
      const clamped = Math.max(0, Math.min(jumpLine - 1, this.lines.length - 1));
      this.previewStartIndex = clamped;
      this.selectionStart = clamped;
      this.selectionEnd = clamped;
    }
  }

  private async loadFullTextInBackground(
    connection: T3Client,
    path: string,
    current: () => boolean,
    match: ContentMatch | undefined,
    jumpLine: number,
    query: string
  ): Promise<void> {
    this.fullTextLoading = true;
    try {
      const fullContents = await connection.downloadFullWorkspaceText(this.cwd, path, MOBILE_FULL_FILE_MAX_BYTES);
      if (!current() || fullContents === undefined) return;
      const prev = this.file;
      this.file = {
        relativePath: prev ? prev.relativePath : path,
        contents: fullContents,
        truncated: false,
        byteLength: prev ? prev.byteLength : fullContents.length,
        exists: true
      };
      this.applyTextContents(path, fullContents, false, match, jumpLine, query);
    } catch (_) {
      // Keep the already loaded RPC preview slice on failure.
    } finally {
      if (current()) this.fullTextLoading = false;
    }
  }

  private fileBadgeLabel(path: string): string {
    if (isImage(path)) return '图片';
    if (isVideo(path)) return '视频';
    if (isAudio(path)) return '音频';
    if (isPdf(path)) return 'PDF';
    if (isHtml(path)) return 'HTML';
    if (isMarkdown(path)) return 'MD';
    if (isZip(path)) return 'ZIP';
    if (isDelimited(path)) return path.toLowerCase().endsWith('.tsv') ? 'TSV' : 'CSV';
    if (isRtf(path)) return 'RTF';
    return '文件';
  }

  private formatZipBytes(size: number): string {
    if (!Number.isFinite(size) || size <= 0) return '0 B';
    if (size < 1024) return size + ' B';
    if (size < 1024 * 1024) return (size / 1024).toFixed(1) + ' KB';
    return (size / (1024 * 1024)).toFixed(1) + ' MB';
  }

  private parentZipDir(): string {
    const parts = this.zipDir.split('/').filter((part: string) => part);
    parts.pop();
    return parts.join('/');
  }

  private hasRichToggle(): boolean {
    if (!this.selectedPath || !this.file || !!this.selectedMatch) return false;
    return isMarkdown(this.selectedPath) || isDelimited(this.selectedPath) || isRtf(this.selectedPath);
  }

  private async openFile(path: string, match?: ContentMatch, preferredHtmlMode?: 'preview' | 'source',
    jumpLine: number = 0): Promise<void> {
    const connection = this.connection;
    if (!connection) return;
    const current = this.beginRead(connection);
    const query = this.matchQuery;
    const useHtmlPreview = isHtml(path) && !match && (preferredHtmlMode || 'preview') === 'preview' && jumpLine <= 0;
    this.selectedPath = path; this.file = undefined; this.lines = []; this.linesTruncated = false;
    this.sourceLines = [];
    this.fileCommentOpen = false; this.fileComment = '';
    this.fileError = ''; this.imageUrl = '';
    this.htmlMode = useHtmlPreview ? 'preview' : 'source';
    this.richMode = jumpLine > 0 || !!match ? 'source' : 'preview';
    this.fullTextLoading = false;
    this.markdownChunks = []; this.markdownDefinitions = ''; this.markdownFallbackSource = false;
    this.delimitedTable = undefined; this.rtfText = '';
    this.zipEntries = []; this.zipDir = ''; this.zipError = '';
    this.selectedMatch = match; this.matchNotice = ''; this.previewStartIndex = 0;
    this.selectionStart = -1; this.selectionEnd = -1;
    this.loading = true;
    try {
      if (isZip(path)) {
        const bytes = await connection.downloadWorkspaceFile(this.cwd, path);
        if (!current()) return;
        if (bytes.byteLength > 50 * 1024 * 1024) {
          this.zipError = 'ZIP 压缩包超过 50 MB，暂不支持直接展开预览，可保存到文件查看。';
        } else {
          this.zipEntries = parseZipEntries(bytes);
        }
      } else if (isImage(path) || isVideo(path) || isAudio(path) || isPdf(path) || useHtmlPreview) {
        const url = await connection.filePreviewUrl(this.cwd, path, true);
        if (current()) this.imageUrl = url;
      } else {
        const file = await connection.readWorkspaceFile(this.cwd, path);
        if (!current()) return;
        this.file = file;
        this.applyTextContents(path, file.contents, file.truncated, match, jumpLine, query);
        if (file.truncated && file.byteLength > 0 && file.byteLength <= MOBILE_FULL_FILE_MAX_BYTES) {
          void this.loadFullTextInBackground(connection, path, current, match, jumpLine, query);
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
    this.fullTextLoading = false;
    this.markdownChunks = []; this.markdownDefinitions = ''; this.markdownFallbackSource = false;
    this.delimitedTable = undefined; this.rtfText = '';
    this.zipEntries = []; this.zipDir = ''; this.zipError = '';
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

  private selectedMediaKind(): string {
    if (isVideo(this.selectedPath)) return 'video';
    if (isImage(this.selectedPath)) return 'image';
    if (isAudio(this.selectedPath)) return 'audio';
    return '';
  }

  private async saveFile(): Promise<void> {
    const connection = this.connection;
    const selected = this.selectedPath;
    if (!connection || !selected || this.mediaBusy) return;
    this.mediaBusy = true;
    this.reportStatus('正在下载…');
    try {
      const bytes = await connection.downloadWorkspaceFile(this.cwd, selected);
      const fileName = mediaFileName(selected, '', '', '', this.selectedMediaKind());
      const outcome = await saveBytesToDocumentPicker(bytes, fileName);
      this.reportStatus(outcome === 'saved' ? '已保存到所选位置' : '已取消保存');
    } catch (reason) { this.reportStatus('保存失败：' + (reason as Error).message); }
    finally { this.mediaBusy = false; }
  }

  private async saveMediaToGallery(viaSaveButton: boolean): Promise<void> {
    const connection = this.connection;
    const selected = this.selectedPath;
    if (!connection || !selected || this.mediaBusy) return;
    const kind = this.selectedMediaKind();
    if (!canSaveToPhotoGallery(selected, '', kind)) {
      await this.saveFile();
      return;
    }
    this.mediaBusy = true;
    this.reportStatus('正在保存到相册…');
    try {
      const bytes = await connection.downloadWorkspaceFile(this.cwd, selected);
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const fileName = mediaFileName(selected, '', '', '', kind);
      const outcome = await saveBytesToPhotoGallery(context, bytes, fileName, '', kind, viaSaveButton);
      this.reportStatus(outcome === 'saved' ? '已保存到相册' : '已取消保存');
    } catch (reason) { this.reportStatus('保存失败：' + (reason as Error).message); }
    finally { this.mediaBusy = false; }
  }

  private async shareFile(): Promise<void> {
    const connection = this.connection;
    const scope = this.cacheScope;
    const generation = this.generation;
    const selected = this.selectedPath;
    if (!connection || !selected || this.mediaBusy) return;
    this.mediaBusy = true;
    this.reportStatus('正在准备分享…');
    try {
      const bytes = await connection.downloadWorkspaceFile(this.cwd, selected);
      if (generation !== this.generation || connection !== this.connection || scope !== this.cacheScope) throw new Error('分享目标已变化');
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const kind = this.selectedMediaKind();
      const fileName = mediaFileName(selected, '', '', '', kind);
      await shareBytesWithSystemSheet(context, bytes, fileName, scope, '', kind);
      this.reportStatus('已打开系统分享');
    } catch (reason) { this.reportStatus('分享失败：' + (reason as Error).message); }
    finally { this.mediaBusy = false; }
  }

  @Builder
  fileActionsMenu() {
    Menu() {
      MenuItem({ content: '复制路径' }).onClick(() => this.onCopy(this.selectedPath))
      MenuItem({ content: this.fileCommentOpen ? '关闭文件评论' : '文件评论' })
        .onClick(() => { this.fileCommentOpen = !this.fileCommentOpen; })
      if (canSaveToPhotoGallery(this.selectedPath, '', this.selectedMediaKind())) {
        MenuItem({ content: '保存到相册' }).onClick(() => { void this.saveMediaToGallery(false); })
      }
      MenuItem({ content: '分享' }).onClick(() => { void this.shareFile(); })
      MenuItem({ content: '保存到文件' }).onClick(() => { void this.saveFile(); })
    }
  }

  @Builder
  mediaActionBar() {
    Column({ space: Space.xs }) {
      Row({ space: Space.xs }) {
        if (canSaveToPhotoGallery(this.selectedPath, '', this.selectedMediaKind())) {
          Column() {
            SaveButton({
              icon: SaveIconStyle.FULL_FILLED,
              text: SaveDescription.SAVE_TO_GALLERY,
              buttonType: ButtonType.Normal
            })
              .width('100%')
              .height(Sizes.buttonHeight)
              .borderRadius(Radius.button)
              .backgroundColor($r('app.color.prominent'))
              .fontColor($r('app.color.on_prominent'))
              .iconColor($r('app.color.on_prominent'))
              .fontSize(FontSize.body)
              .iconSize(16)
              .onClick((event: ClickEvent, result: SaveButtonOnClickResult) => {
                if (this.mediaBusy) return;
                if (result === SaveButtonOnClickResult.SUCCESS) {
                  void this.saveMediaToGallery(true);
                } else if (result === SaveButtonOnClickResult.CANCELED_BY_USER) {
                  this.reportStatus('已取消保存');
                } else {
                  void this.saveMediaToGallery(false);
                }
              })
          }.layoutWeight(1)
        } else {
          Column() {
            AppButton({
              label: this.mediaBusy ? '保存中…' : '保存到文件',
              kind: 'primary',
              fill: true,
              disabled: this.mediaBusy,
              onTap: () => { void this.saveFile(); }
            })
          }.layoutWeight(1)
        }
        Column() {
          AppButton({
            label: '分享',
            kind: 'secondary',
            fill: true,
            disabled: this.mediaBusy,
            onTap: () => { void this.shareFile(); }
          })
        }.layoutWeight(1)
      }.width('100%')
      if (canSaveToPhotoGallery(this.selectedPath, '', this.selectedMediaKind())) {
        AppButton({
          label: '保存到文件',
          kind: 'secondary',
          compact: true,
          fill: true,
          disabled: this.mediaBusy,
          onTap: () => { void this.saveFile(); }
        })
      }
    }
    .width('100%')
    .padding(Space.sm)
    .backgroundColor($r('app.color.card'))
    .borderRadius(Radius.card)
  }

  @Builder
  header() {
    TopBar({
      title: this.selectedPath ? (this.selectedPath.split('/').pop() || this.selectedPath) : this.title,
      subtitle: this.selectedPath ? (this.selectedPath.includes('/') ? this.selectedPath.slice(0, this.selectedPath.lastIndexOf('/')) : this.cwd) : (this.currentDir ? '/' + this.currentDir : this.cwd),
      showBack: true,
      closeStyle: (!this.selectedPath && !this.currentDir) || (this.directFileOnly && !!this.selectedPath),
      backLabel: (this.directFileOnly && !!this.selectedPath) ? '返回会话' : (this.selectedPath || this.currentDir ? '返回' : '关闭文件'),
      onBack: () => {
        if (this.selectedPath) {
          if (this.directFileOnly) { this.onBack(); return; }
          this.closeFile();
          return;
        }
        if (this.currentDir) { void this.loadDirectory(this.parentDir()); return; }
        this.onBack();
      }
    }) {
      if (this.selectedPath) {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          Image($r('app.media.ui_more'))
            .width(Sizes.icon)
            .height(Sizes.icon)
            .objectFit(ImageFit.Contain)
            .draggable(false)
            .accessibilityLevel('no')
        }
        .width(Sizes.iconHit)
        .height(Sizes.iconHit)
        .backgroundColor(Color.Transparent)
        .accessibilityText('文件操作')
        .bindMenu(this.fileActionsMenu())
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
          kind: 'text',
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
      }.width('100%').padding(2).backgroundColor($r('app.color.group')).border({ width: Sizes.hairline, color: $r('app.color.border') }).borderRadius(9)

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
                  Row() {
                    if (entry.kind === 'directory') {
                      Image($r('app.media.ui_folder')).width(18).height(18).accessibilityLevel('no')
                    } else {
                      StatusBadge({
                        text: this.fileBadgeLabel(entry.path),
                        tone: 'neutral'
                      })
                    }
                  }.width(42).justifyContent(FlexAlign.Center).flexShrink(0)
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
                  Row() {
                    if (entry.kind === 'directory') {
                      Image($r('app.media.ui_folder')).width(18).height(18).accessibilityLevel('no')
                    } else {
                      StatusBadge({
                        text: this.fileBadgeLabel(entry.path),
                        tone: 'neutral'
                      })
                    }
                  }.width(42).justifyContent(FlexAlign.Center).flexShrink(0)
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
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .nestedScroll({ scrollForward: NestedScrollMode.SELF_ONLY, scrollBackward: NestedScrollMode.SELF_ONLY })
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
      if (this.selectedPath && isHtml(this.selectedPath)) {
        Row({ space: 2 }) {
          Button('预览')
            .fontSize(FontSize.callout)
            .fontWeight(this.htmlMode === 'preview' ? Weight.medium : Weight.regular)
            .fontColor(this.htmlMode === 'preview' ? $r('app.color.ink') : $r('app.color.muted'))
            .backgroundColor(this.htmlMode === 'preview' ? $r('app.color.card') : Color.Transparent)
            .borderRadius(7).layoutWeight(1).constraintSize({ minHeight: 34 })
            .onClick(() => {
              if (this.htmlMode !== 'preview') {
                void this.openFile(this.selectedPath, undefined, 'preview');
              }
            })
          Button('源码')
            .fontSize(FontSize.callout)
            .fontWeight(this.htmlMode === 'source' ? Weight.medium : Weight.regular)
            .fontColor(this.htmlMode === 'source' ? $r('app.color.ink') : $r('app.color.muted'))
            .backgroundColor(this.htmlMode === 'source' ? $r('app.color.card') : Color.Transparent)
            .borderRadius(7).layoutWeight(1).constraintSize({ minHeight: 34 })
            .onClick(() => {
              if (this.htmlMode !== 'source') {
                void this.openFile(this.selectedPath, undefined, 'source');
              }
            })
        }.width('100%').padding(2).backgroundColor($r('app.color.group'))
          .border({ width: Sizes.hairline, color: $r('app.color.border') }).borderRadius(9)
      }
      if (this.loading) {
        Text('正在打开…').fontSize(FontSize.callout).fontColor($r('app.color.muted')).padding(Space.md)
      } else if (this.fileError) {
        GroupCard() {
          Column({ space: Space.xs }) {
            Text(this.fileError).fontSize(FontSize.callout).fontColor($r('app.color.danger')).width('100%')
            AppButton({
              label: '重试', kind: 'secondary', compact: true,
              onTap: () => { void this.openFile(this.selectedPath, this.selectedMatch, this.htmlMode); }
            })
          }.width('100%').padding(14).alignItems(HorizontalAlign.Start)
        }
      } else if (isZip(this.selectedPath)) {
        Column({ space: Space.xs }) {
          if (this.zipError) {
            GroupCard() {
              Text(this.zipError).fontSize(FontSize.callout).fontColor($r('app.color.danger')).width('100%').padding(14)
            }
          } else {
            Row({ space: Space.xs }) {
              Text(this.zipDir ? '/' + this.zipDir : '压缩包根目录')
                .fontSize(FontSize.caption).fontColor($r('app.color.muted')).layoutWeight(1)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              Text('共 ' + this.zipEntries.length + ' 项')
                .fontSize(FontSize.caption).fontColor($r('app.color.muted'))
            }.width('100%').padding({ left: Space.xxs, right: Space.xxs })
            List({ space: 0 }) {
              if (this.zipDir) {
                ListItem() {
                  Row({ space: Space.xs }) {
                    Image($r('app.media.ui_down')).width(18).height(18).rotate({ angle: 180 }).opacity(0.75).accessibilityLevel('no')
                    Text('上一级').fontSize(FontSize.body).fontWeight(Weight.medium).fontColor($r('app.color.ink')).layoutWeight(1)
                  }.constraintSize({ minHeight: Sizes.formRowMin }).width('100%').padding({ left: 14, right: 14 })
                    .onClick(() => { this.zipDir = this.parentZipDir(); })
                }
              }
              ForEach(listZipDirectory(this.zipEntries, this.zipDir), (item: ZipBrowserItem) => {
                ListItem() {
                  Row({ space: Space.xs }) {
                    Row() {
                      if (item.isDirectory) {
                        Image($r('app.media.ui_folder')).width(18).height(18).accessibilityLevel('no')
                      } else {
                        StatusBadge({ text: this.fileBadgeLabel(item.path), tone: 'neutral' })
                      }
                    }.width(42).justifyContent(FlexAlign.Center).flexShrink(0)
                    Text(item.name).fontSize(FontSize.body).fontColor($r('app.color.ink')).layoutWeight(1)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(item.isDirectory ? (item.childCount + ' 项') : this.formatZipBytes(item.sizeBytes))
                      .fontSize(FontSize.caption).fontColor($r('app.color.muted'))
                    if (item.isDirectory) {
                      Image($r('app.media.ui_chevron_right')).width(Sizes.chevron).height(Sizes.chevron).opacity(0.6).accessibilityLevel('no')
                    }
                  }.constraintSize({ minHeight: Sizes.formRowMin }).width('100%')
                    .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
                    .onClick(() => {
                      if (item.isDirectory) this.zipDir = item.path;
                      else this.onCopy(item.path);
                    })
                }
              }, (item: ZipBrowserItem) => (item.isDirectory ? 'd:' : 'f:') + item.path)
            }
            .width('100%').layoutWeight(1)
            .backgroundColor($r('app.color.card')).borderRadius(Radius.card).clip(true)
            .divider({ strokeWidth: Sizes.hairline, color: $r('app.color.separator') })
            .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
            .nestedScroll({ scrollForward: NestedScrollMode.SELF_ONLY, scrollBackward: NestedScrollMode.SELF_ONLY })
          }
          this.mediaActionBar()
        }.width('100%').layoutWeight(1)
      } else if (this.imageUrl && isAudio(this.selectedPath)) {
        Column({ space: Space.sm }) {
          AudioPlayerView({
            uri: this.imageUrl,
            title: this.selectedPath.split('/').pop() || this.selectedPath
          })
          Blank().layoutWeight(1)
          this.mediaActionBar()
        }.width('100%').layoutWeight(1)
      } else if (this.imageUrl && isPdf(this.selectedPath)) {
        Column({ space: Space.sm }) {
          Column() {
            HtmlRenderWebView({
              uri: this.imageUrl,
              title: this.selectedPath.split('/').pop() || 'PDF',
              nested: false,
              isHtmlRender: false,
              onOpenExternalLink: this.onOpenExternalLink,
              onLoadError: () => { this.fileError = 'PDF 在线预览不可用，请点击下方保存到文件或系统分享查看'; }
            })
          }
          .width('100%').layoutWeight(1)
          .backgroundColor($r('app.color.card')).borderRadius(Radius.card).clip(true)
          this.mediaActionBar()
        }.width('100%').layoutWeight(1)
      } else if (this.imageUrl && isHtml(this.selectedPath) && this.htmlMode === 'preview') {
        Column() {
          HtmlRenderWebView({
            uri: this.imageUrl,
            title: this.selectedPath.split('/').pop() || 'HTML',
            nested: false,
            isHtmlRender: false,
            onOpenExternalLink: this.onOpenExternalLink,
            onLoadError: () => { this.fileError = 'HTML 预览加载失败，可点按重试或切换至源码视图'; }
          })
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor($r('app.color.card'))
        .borderRadius(Radius.card)
        .clip(true)
      } else if (this.imageUrl && isImage(this.selectedPath)) {
        Column({ space: Space.sm }) {
          Scroll() {
            Image(this.imageUrl).width('100%').objectFit(ImageFit.Contain)
          }.width('100%').layoutWeight(1).backgroundColor($r('app.color.card')).borderRadius(Radius.card).clip(true)
            .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
            .nestedScroll({ scrollForward: NestedScrollMode.SELF_ONLY, scrollBackward: NestedScrollMode.SELF_ONLY })
          this.mediaActionBar()
        }.width('100%').layoutWeight(1)
      } else if (this.imageUrl && isVideo(this.selectedPath)) {
        Column({ space: Space.sm }) {
          Video({ src: this.imageUrl }).width('100%').height(320).objectFit(ImageFit.Contain).controls(true)
            .backgroundColor(Color.Black).borderRadius(Radius.card).clip(true)
          this.mediaActionBar()
        }.width('100%').layoutWeight(1)
      } else if (this.imageUrl) {
        Column({ space: Space.sm }) {
          GroupCard() {
            Column({ space: Space.xs }) {
              Text('此文件类型使用系统打开/分享').fontSize(FontSize.body).fontColor($r('app.color.ink'))
              Text(this.selectedPath).fontSize(FontSize.caption).fontColor($r('app.color.muted'))
            }.padding(14).width('100%').alignItems(HorizontalAlign.Start)
          }
          Blank().layoutWeight(1)
          this.mediaActionBar()
        }.width('100%').layoutWeight(1)
      } else if (this.file) {
        if (this.hasRichToggle()) {
          Row({ space: 2 }) {
            Button('预览')
              .fontSize(FontSize.callout)
              .fontWeight(this.richMode === 'preview' ? Weight.medium : Weight.regular)
              .fontColor(this.richMode === 'preview' ? $r('app.color.ink') : $r('app.color.muted'))
              .backgroundColor(this.richMode === 'preview' ? $r('app.color.card') : Color.Transparent)
              .borderRadius(7).layoutWeight(1).constraintSize({ minHeight: 34 })
              .onClick(() => { this.richMode = 'preview'; })
            Button('源码')
              .fontSize(FontSize.callout)
              .fontWeight(this.richMode === 'source' ? Weight.medium : Weight.regular)
              .fontColor(this.richMode === 'source' ? $r('app.color.ink') : $r('app.color.muted'))
              .backgroundColor(this.richMode === 'source' ? $r('app.color.card') : Color.Transparent)
              .borderRadius(7).layoutWeight(1).constraintSize({ minHeight: 34 })
              .onClick(() => { this.richMode = 'source'; })
          }.width('100%').padding(2).backgroundColor($r('app.color.group'))
            .border({ width: Sizes.hairline, color: $r('app.color.border') }).borderRadius(9)
        }
        if (this.fullTextLoading) {
          Row({ space: Space.xs }) {
            LoadingProgress().width(14).height(14).color($r('app.color.primary'))
            Text('正在加载完整文件内容…').fontSize(FontSize.caption).fontColor($r('app.color.muted'))
          }.width('100%').padding({ left: Space.xxs, right: Space.xxs }).alignItems(VerticalAlign.Center)
        } else if (this.linesTruncated) {
          Text('文件较大，仅显示前 ' + this.lines.length + ' 行或服务端预览片段').fontSize(FontSize.caption).fontColor($r('app.color.danger'))
            .width('100%').padding({ left: Space.xxs, right: Space.xxs })
        }
        if (this.matchNotice) {
          Text(this.matchNotice).fontSize(FontSize.callout).fontColor($r('app.color.muted')).width('100%')
            .padding({ left: Space.xxs, right: Space.xxs })
        }
        if (isDelimited(this.selectedPath) && this.richMode === 'preview' && !this.selectedMatch && this.delimitedTable) {
          Column({ space: Space.xs }) {
            Text('共 ' + this.delimitedTable.totalRows + ' 行 · ' + this.delimitedTable.headers.length + ' 列' +
              (this.delimitedTable.truncated ? '（仅预览前 ' + this.delimitedTable.rows.length + ' 行）' : ''))
              .fontSize(FontSize.caption).fontColor($r('app.color.muted')).width('100%').padding({ left: Space.xxs, right: Space.xxs })
            Scroll() {
              Scroll() {
                Column({ space: 0 }) {
                  Row({ space: 0 }) {
                    ForEach(this.delimitedTable.headers, (header: string, colIdx: number) => {
                      Text(header || ('列 ' + (colIdx + 1)))
                        .fontSize(FontSize.caption).fontWeight(Weight.semibold).fontColor($r('app.color.ink'))
                        .width(140).padding({ left: 10, right: 10, top: 8, bottom: 8 })
                        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                        .border({ width: { right: Sizes.hairline, bottom: Sizes.hairline }, color: $r('app.color.border') })
                    }, (header: string, colIdx: number) => colIdx + ':' + header)
                  }.backgroundColor($r('app.color.group'))
                  ForEach(this.delimitedTable.rows, (row: string[], rowIdx: number) => {
                    Row({ space: 0 }) {
                      ForEach(row, (cell: string, colIdx: number) => {
                        Text(cell)
                          .fontSize(FontSize.caption).fontColor($r('app.color.ink')).copyOption(CopyOptions.InApp)
                          .width(140).padding({ left: 10, right: 10, top: 7, bottom: 7 })
                          .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
                          .border({ width: { right: Sizes.hairline, bottom: Sizes.hairline }, color: $r('app.color.separator') })
                      }, (_cell: string, colIdx: number) => rowIdx + ':' + colIdx)
                    }.backgroundColor(rowIdx % 2 === 0 ? $r('app.color.card') : $r('app.color.group'))
                  }, (_row: string[], rowIdx: number) => String(rowIdx))
                }.alignItems(HorizontalAlign.Start)
              }.scrollable(ScrollDirection.Horizontal).align(Alignment.TopStart).edgeEffect(EdgeEffect.Spring)
            }.scrollable(ScrollDirection.Vertical).align(Alignment.TopStart).width('100%').layoutWeight(1)
              .backgroundColor($r('app.color.card')).borderRadius(Radius.card).clip(true)
              .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
              .nestedScroll({ scrollForward: NestedScrollMode.SELF_ONLY, scrollBackward: NestedScrollMode.SELF_ONLY })
          }.width('100%').layoutWeight(1)
        } else if (isRtf(this.selectedPath) && this.richMode === 'preview' && !this.selectedMatch) {
          Scroll() {
            Text(this.rtfText || '（空 RTF 文档）')
              .fontSize(FontSize.body).lineHeight(LineHeight.body).fontColor($r('app.color.ink'))
              .copyOption(CopyOptions.InApp).width('100%').padding(14)
          }.width('100%').layoutWeight(1).align(Alignment.TopStart)
            .backgroundColor($r('app.color.card')).borderRadius(Radius.card).clip(true)
            .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
            .nestedScroll({ scrollForward: NestedScrollMode.SELF_ONLY, scrollBackward: NestedScrollMode.SELF_ONLY })
        } else if (isMarkdown(this.selectedPath) && this.richMode === 'preview' && !this.selectedMatch && !this.markdownFallbackSource) {
          if (this.selectionStart >= 0) { this.selectionBar() }
          if (this.markdownChunks.length > 1) {
            List({ space: 0 }) {
              ForEach(this.markdownChunks, (chunk: MarkdownChunk, idx: number) => {
                ListItem() {
                  Column() {
                    MarkdownView({
                      markdown: withMarkdownDefinitions(chunk.text, this.markdownDefinitions),
                      selectable: true,
                      mediaScopeKey: this.cacheScope + ':' + this.selectedPath + ':' + (this.connection ? this.connection.generationValue() : 0) + ':' + idx,
                      mediaReady: !!this.connection && this.connection.ready,
                      onCopy: this.onCopy,
                      onOpenLink: (url: string) => { this.onOpenLink(url); },
                      onOpenImage: (path: string) => { void this.openFile(resolveRelativeMarkdownPath(this.selectedPath, path)); },
                      resolveMedia: this.connection ? (source: string, refresh: boolean): Promise<ResolvedMarkdownMedia> =>
                        this.connection!.markdownMediaUrl(resolveRelativeMarkdownPath(this.selectedPath, source), this.cwd, refresh) : undefined
                    })
                  }.width('100%').padding({ left: 14, right: 14, top: idx === 0 ? 14 : 4, bottom: idx === this.markdownChunks.length - 1 ? 14 : 4 })
                }
              }, (_chunk: MarkdownChunk, idx: number) => this.selectedPath + ':md:' + idx + ':' + this.markdownChunks.length)
            }.width('100%').layoutWeight(1)
              .backgroundColor($r('app.color.card')).borderRadius(Radius.card).clip(true)
              .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
              .nestedScroll({ scrollForward: NestedScrollMode.SELF_ONLY, scrollBackward: NestedScrollMode.SELF_ONLY })
          } else {
            Scroll() {
              Column() {
                MarkdownView({ markdown: this.file.contents, selectable: true,
                  mediaScopeKey: this.cacheScope + ':' + this.selectedPath + ':' + (this.connection ? this.connection.generationValue() : 0),
                  mediaReady: !!this.connection && this.connection.ready,
                  onCopy: this.onCopy,
                  onOpenLink: (url: string) => { this.onOpenLink(url); },
                  onOpenImage: (path: string) => { void this.openFile(resolveRelativeMarkdownPath(this.selectedPath, path)); },
                  resolveMedia: this.connection ? (source: string, refresh: boolean): Promise<ResolvedMarkdownMedia> =>
                    this.connection!.markdownMediaUrl(resolveRelativeMarkdownPath(this.selectedPath, source), this.cwd, refresh) : undefined })
              }.padding(14)
            }.width('100%').layoutWeight(1).align(Alignment.TopStart)
              .backgroundColor($r('app.color.card')).borderRadius(Radius.card).clip(true)
              .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
              .nestedScroll({ scrollForward: NestedScrollMode.SELF_ONLY, scrollBackward: NestedScrollMode.SELF_ONLY })
          }
        } else {
          if (this.markdownFallbackSource && isMarkdown(this.selectedPath) && this.richMode === 'preview') {
            Text('该 Markdown 包含超大代码块，已自动切换为源码视图以保证流畅滚动。')
              .fontSize(FontSize.caption).fontColor($r('app.color.muted')).width('100%').padding({ left: Space.xxs, right: Space.xxs })
          }
          if (this.selectionStart >= 0) { this.selectionBar() }
          List({ space: 0, initialIndex: this.previewStartIndex }) {
            ForEach(this.lines, (line: FileLine, index: number) => {
              ListItem() {
                Row({ space: 0 }) {
                  DiffLineNumber({ line: line.number, lastLine: this.lines.length,
                    active: index >= Math.min(this.selectionStart < 0 ? -1 : this.selectionStart, this.selectionEnd < 0 ? -1 : this.selectionEnd) &&
                      this.selectionStart >= 0 && index <= Math.max(this.selectionStart, this.selectionEnd) })
                  CodeLine({ text: line.text, language: detectCodeLanguage(this.selectedPath) }).layoutWeight(1)
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
            .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
            .nestedScroll({ scrollForward: NestedScrollMode.SELF_ONLY, scrollBackward: NestedScrollMode.SELF_ONLY })
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
      .hitTestBehavior(HitTestMode.Default)
  }
}
