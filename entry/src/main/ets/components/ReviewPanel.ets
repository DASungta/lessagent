import { TopBar } from './ui/TopBar';
import { GroupCard } from './ui/GroupCard';
import { AppButton } from './ui/AppButton';
import { StatusBadge } from './ui/StatusBadge';
import { FontSize, LineHeight, Radius, Sizes, Space, Weight } from '../common/Theme';
import { T3Client } from '../services/T3Client';
import { setPullRequestHideTestFiles } from '../services/WorkspacePrefs';
import { CodeLine } from './CodeLine';
import { DiffLineNumber } from './DiffLineNumber';
import { ProjectView } from '../protocol/Projects';
import {
  TaskFolder,
  ThreadGitRepository,
  WorkspaceFolder,
  isRelativePathInsideFolder,
  relativeFolderPath,
  repositoryFilePath,
  threadChangedRepositories,
  threadGitRepositories
} from '../protocol/ThreadRepositories';
import {
  DiffFile,
  DiffHunk,
  DiffRow,
  DiffSelection,
  ReviewSource,
  filterDiffTestFiles,
  orderParsedDiffFilesForReview,
  parseDiff,
  reviewCommentContext,
  selectedDiff
} from '../protocol/R5';

interface RepoReviewGroup {
  key: string;
  name: string;
  cwd: string;
  relativePath: string;
  sources: ReviewSource[];
  files: DiffFile[];
  additions: number;
  deletions: number;
}

interface IndexedReviewFile {
  groupKey: string;
  groupName: string;
  relativePath: string;
  file: DiffFile;
}

@Component
export struct ReviewPanel {
  @StorageProp('t3CodeFontSize') codeFontSize: number = 13;
  @StorageProp('t3HideTestFiles') hideTestFiles: boolean = false;
  connection: T3Client | undefined = undefined;
  @Prop cwd: string = '';
  @Prop threadId: string = '';
  @Prop projectId: string = '';
  @Prop worktreePath: string = '';
  @Prop project: ProjectView | undefined = undefined;
  @Prop checkpointScopes: Record<string, Object>[] = [];
  @Prop checkpoints: Record<string, Object>[] = [];
  onBack: () => void = () => {};
  onCompose: (value: Object, label: string) => void = () => {};
  onCopy: (value: string) => void = () => {};
  onStatus: (value: string) => void = () => {};

  @State mode: string = 'working-tree';
  @State baseRef: string = '';
  @State sources: ReviewSource[] = [];
  @State sourceIndex: number = 0;
  @State files: DiffFile[] = [];
  @State repoGroups: RepoReviewGroup[] = [];
  @State selectedRepoKey: string = '';
  @State selectedFileRepoKey: string = '';
  @State loading: boolean = false;
  @State error: string = '';
  @State selectedPath: string = '';
  @State selectedHunk: string = '';
  @State start: number = -1;
  @State end: number = -1;
  @State comment: string = '';
  @State commenting: boolean = false;
  private loadGeneration: number = 0;

  aboutToAppear(): void { void this.load(); }

  private isMultiRepo(): boolean {
    return this.repoGroups.length > 0;
  }

  private async discoverMultiRepos(): Promise<ThreadGitRepository[]> {
    const conn = this.connection;
    if (!conn || !conn.ready) return [];
    const trackedCount = this.project?.trackedFolders?.length || 0;
    const changed = threadChangedRepositories(this.checkpoints, this.checkpointScopes);
    if (trackedCount === 0 && changed.length === 0) return [];
    let taskFolder: TaskFolder | undefined = undefined;
    let folders: WorkspaceFolder[] | undefined = undefined;
    if (this.worktreePath && trackedCount > 0 && conn.canReadFiles()) {
      try { taskFolder = await conn.getTaskFolder(this.worktreePath); } catch (_) {}
    }
    if (this.projectId && conn.canReadFiles()) {
      try { folders = await conn.listWorkspaceFolders(this.projectId); } catch (_) {}
    }
    return threadGitRepositories(changed, taskFolder, folders, this.cwd);
  }

  private async load(): Promise<void> {
    const connection = this.connection;
    const gen = ++this.loadGeneration;
    if (!connection || !this.cwd) { this.error = '当前会话没有工作目录'; return; }
    if (this.mode === 'branch-range' && !this.baseRef.trim()) { this.error = '请输入对比分支'; return; }
    this.loading = true; this.error = ''; this.selectedPath = ''; this.selectedFileRepoKey = '';
    this.start = -1; this.end = -1;
    try {
      const extraRepos = await this.discoverMultiRepos();
      if (gen !== this.loadGeneration) return;
      if (extraRepos.length === 0) {
        this.repoGroups = [];
        this.selectedRepoKey = '';
        const preview = await connection.reviewDiffPreview(this.cwd,
          this.mode === 'branch-range' ? this.baseRef.trim() : '', this.mode);
        if (gen !== this.loadGeneration) return;
        this.sources = preview.sources;
        this.sourceIndex = 0;
        this.files = preview.sources.length ? orderParsedDiffFilesForReview(parseDiff(preview.sources[0].diff)) : [];
        if (preview.incomplete) this.error = '部分 Diff 无法读取；已显示可用文件';
        return;
      }

      const targets: ThreadGitRepository[] = [];
      const seenCwds = new Set<string>();
      const rootName = this.project?.label || '项目根目录';
      targets.push({ repositoryPath: '.', name: rootName, cwd: this.cwd });
      seenCwds.add(this.cwd);
      for (const repo of extraRepos) {
        if (!repo.cwd || seenCwds.has(repo.cwd)) continue;
        seenCwds.add(repo.cwd);
        targets.push(repo);
      }

      const groups: RepoReviewGroup[] = [];
      let anyIncomplete = false;
      for (const target of targets) {
        try {
          const preview = await connection.reviewDiffPreview(target.cwd,
            this.mode === 'branch-range' ? this.baseRef.trim() : '', this.mode);
          if (gen !== this.loadGeneration) return;
          if (preview.incomplete) anyIncomplete = true;
          const parsed = preview.sources.length
            ? orderParsedDiffFilesForReview(parseDiff(preview.sources[0].diff))
            : [];
          let additions = 0;
          let deletions = 0;
          for (const f of parsed) { additions += f.additions; deletions += f.deletions; }
          const rel = target.repositoryPath === '.' ? '' : (relativeFolderPath(this.cwd, target.cwd) || '');
          const cleanRel = rel && isRelativePathInsideFolder(rel) ? rel : '';
          groups.push({
            key: target.repositoryPath,
            name: target.name,
            cwd: target.cwd,
            relativePath: cleanRel,
            sources: preview.sources,
            files: parsed,
            additions,
            deletions
          });
        } catch (_) {
          // A plain project root folder is not a git repo; skip it when extra repos exist.
        }
      }
      if (gen !== this.loadGeneration) return;
      this.repoGroups = groups;
      if (this.selectedRepoKey && !groups.some((g: RepoReviewGroup) => g.key === this.selectedRepoKey)) {
        this.selectedRepoKey = '';
      }
      this.sources = groups.length > 0 ? groups[0].sources : [];
      this.sourceIndex = 0;
      const flat: DiffFile[] = [];
      for (const g of groups) {
        for (const f of g.files) flat.push(f);
      }
      this.files = flat;
      if (anyIncomplete) this.error = '部分仓库 Diff 无法读取；已显示可用文件';
    } catch (reason) {
      if (gen === this.loadGeneration) this.error = (reason as Error).message;
    } finally {
      if (gen === this.loadGeneration) this.loading = false;
    }
  }

  private selectSource(index: number): void {
    this.sourceIndex = index; this.selectedPath = ''; this.selectedFileRepoKey = '';
    this.start = -1; this.end = -1;
    this.files = orderParsedDiffFilesForReview(parseDiff(this.sources[index].diff));
  }

  private activeGroups(): RepoReviewGroup[] {
    if (!this.selectedRepoKey) return this.repoGroups;
    return this.repoGroups.filter((group: RepoReviewGroup) => group.key === this.selectedRepoKey);
  }

  private visibleFilesForGroup(group: RepoReviewGroup): DiffFile[] {
    return filterDiffTestFiles(group.files, this.hideTestFiles).files;
  }

  private visibleIndexedFiles(): IndexedReviewFile[] {
    if (!this.isMultiRepo()) {
      return filterDiffTestFiles(this.files, this.hideTestFiles).files.map((file: DiffFile): IndexedReviewFile => ({
        groupKey: '',
        groupName: '',
        relativePath: '',
        file
      }));
    }
    const result: IndexedReviewFile[] = [];
    for (const group of this.activeGroups()) {
      for (const file of this.visibleFilesForGroup(group)) {
        result.push({
          groupKey: group.key,
          groupName: group.name,
          relativePath: group.relativePath,
          file
        });
      }
    }
    return result;
  }

  private totalFileCount(): number {
    if (!this.isMultiRepo()) return this.files.length;
    let total = 0;
    for (const group of this.activeGroups()) total += group.files.length;
    return total;
  }

  private visibleFiles(): DiffFile[] {
    return this.visibleIndexedFiles().map((entry: IndexedReviewFile) => entry.file);
  }

  private hiddenTestFileCount(): number {
    if (!this.isMultiRepo()) return filterDiffTestFiles(this.files, this.hideTestFiles).hiddenCount;
    let total = 0;
    for (const group of this.activeGroups()) {
      total += filterDiffTestFiles(group.files, this.hideTestFiles).hiddenCount;
    }
    return total;
  }

  private updateHideTestFiles(next: boolean): void {
    void setPullRequestHideTestFiles(next).catch((reason: Error) => {
      this.onStatus(reason.message);
    });
  }

  private currentEntry(): IndexedReviewFile | undefined {
    const entries = this.visibleIndexedFiles();
    const matched = entries.find((entry: IndexedReviewFile) =>
      (entry.file.path || entry.file.previousPath) === this.selectedPath &&
      (!this.selectedFileRepoKey || entry.groupKey === this.selectedFileRepoKey));
    if (matched) return matched;
    if (!this.isMultiRepo()) {
      const fallback = this.files.find((item: DiffFile) => (item.path || item.previousPath) === this.selectedPath);
      return fallback ? { groupKey: '', groupName: '', relativePath: '', file: fallback } : undefined;
    }
    for (const group of this.repoGroups) {
      if (this.selectedFileRepoKey && group.key !== this.selectedFileRepoKey) continue;
      const fallback = group.files.find((item: DiffFile) => (item.path || item.previousPath) === this.selectedPath);
      if (fallback) {
        return { groupKey: group.key, groupName: group.name, relativePath: group.relativePath, file: fallback };
      }
    }
    return undefined;
  }

  private file(): DiffFile | undefined {
    return this.currentEntry()?.file;
  }

  private hunks(): DiffHunk[] {
    const file = this.file();
    return file ? file.hunks : [];
  }

  private diffSelection(hunk: DiffHunk): DiffSelection | undefined {
    const entry = this.currentEntry();
    if (!entry || this.start < 0) return undefined;
    const raw = selectedDiff(entry.file, hunk, this.start, this.end);
    if (!entry.relativePath) return raw;
    const qualified = repositoryFilePath(entry.relativePath, raw.filePath);
    return {
      filePath: qualified,
      sectionId: 'review:' + qualified + ':' + hunk.header,
      sectionTitle: qualified,
      startIndex: raw.startIndex,
      endIndex: raw.endIndex,
      rangeLabel: raw.rangeLabel,
      text: raw.text,
      diff: raw.diff
    };
  }

  private submitComment(hunk: DiffHunk): void {
    const selection = this.diffSelection(hunk);
    if (!selection) { this.onStatus('请先选择 Diff 行'); return; }
    try {
      const context = reviewCommentContext(selection, this.comment, 'review_' + Date.now().toString(36));
      this.onCompose(context, selection.filePath);
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

  private headerSubtitle(): string {
    if (this.selectedPath) {
      const entry = this.currentEntry();
      return entry && entry.groupName ? (entry.groupName + ' · ' + this.cwd) : this.cwd;
    }
    if (this.isMultiRepo()) {
      return this.repoGroups.length + ' 个仓库 · ' + this.cwd;
    }
    return this.sources.length ? this.sources[this.sourceIndex].title : this.cwd;
  }

  @Builder
  header() {
    TopBar({
      title: this.selectedPath || '审阅',
      subtitle: this.headerSubtitle(),
      showBack: true,
      closeStyle: !this.selectedPath,
      backLabel: this.selectedPath ? '返回文件列表' : '关闭审阅',
      onBack: () => {
        if (this.selectedPath) {
          this.selectedPath = '';
          this.selectedFileRepoKey = '';
          this.start = -1;
          this.end = -1;
          return;
        }
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
      }.width('100%').padding(2).backgroundColor($r('app.color.group'))
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

      if (this.isMultiRepo() && this.repoGroups.length > 1) {
        Scroll() {
          Row({ space: Space.xs }) {
            Button('全部仓库（' + this.repoGroups.length + '）', { type: ButtonType.Normal })
              .fontSize(FontSize.caption)
              .fontWeight(!this.selectedRepoKey ? Weight.semibold : Weight.medium)
              .constraintSize({ minHeight: 32 }).padding({ left: Space.sm, right: Space.sm })
              .backgroundColor(!this.selectedRepoKey ? $r('app.color.info_bg') : $r('app.color.card'))
              .fontColor(!this.selectedRepoKey ? $r('app.color.primary_text') : $r('app.color.ink'))
              .border({ width: Sizes.hairline, color: !this.selectedRepoKey ? $r('app.color.primary') : Color.Transparent, radius: Radius.tool })
              .borderRadius(Radius.tool)
              .onClick(() => { this.selectedRepoKey = ''; })
            ForEach(this.repoGroups, (group: RepoReviewGroup) => {
              Button(group.name + ' · ' + group.files.length, { type: ButtonType.Normal })
                .fontSize(FontSize.caption)
                .fontWeight(this.selectedRepoKey === group.key ? Weight.semibold : Weight.medium)
                .constraintSize({ minHeight: 32 }).padding({ left: Space.sm, right: Space.sm })
                .backgroundColor(this.selectedRepoKey === group.key ? $r('app.color.info_bg') : $r('app.color.card'))
                .fontColor(this.selectedRepoKey === group.key ? $r('app.color.primary_text') : $r('app.color.ink'))
                .border({
                  width: Sizes.hairline,
                  color: this.selectedRepoKey === group.key ? $r('app.color.primary') : Color.Transparent,
                  radius: Radius.tool
                })
                .borderRadius(Radius.tool)
                .onClick(() => { this.selectedRepoKey = group.key; })
            }, (group: RepoReviewGroup) => group.key + ':' + group.files.length + ':' + (this.selectedRepoKey === group.key ? '1' : '0'))
          }
        }.scrollable(ScrollDirection.Horizontal).width('100%').align(Alignment.Start)
      } else if (!this.isMultiRepo() && this.sources.length > 1) {
        Scroll() {
          Row({ space: Space.xs }) {
            ForEach(this.sources, (source: ReviewSource, index: number) => {
              Button(source.title, { type: ButtonType.Normal })
                .fontSize(FontSize.caption)
                .fontWeight(index === this.sourceIndex ? Weight.semibold : Weight.medium)
                .constraintSize({ minHeight: 32 }).padding({ left: Space.sm, right: Space.sm })
                .backgroundColor(index === this.sourceIndex ? $r('app.color.info_bg') : $r('app.color.card'))
                .fontColor(index === this.sourceIndex ? $r('app.color.primary_text') : $r('app.color.ink'))
                .border({ width: Sizes.hairline, color: index === this.sourceIndex ? $r('app.color.primary') : Color.Transparent, radius: Radius.tool })
                .borderRadius(Radius.tool)
                .onClick(() => this.selectSource(index))
            }, (source: ReviewSource) => source.id)
          }
        }.scrollable(ScrollDirection.Horizontal).width('100%').align(Alignment.Start)
      }

      Row({ space: Space.xs }) {
        Button(this.hideTestFiles ? '✓ 隐藏测试文件' : '隐藏测试文件', { type: ButtonType.Normal })
          .fontSize(FontSize.caption)
          .fontWeight(this.hideTestFiles ? Weight.semibold : Weight.medium)
          .constraintSize({ minHeight: 32 }).padding({ left: Space.sm, right: Space.sm })
          .backgroundColor(this.hideTestFiles ? $r('app.color.info_bg') : $r('app.color.card'))
          .fontColor(this.hideTestFiles ? $r('app.color.primary_text') : $r('app.color.ink'))
          .border({ width: Sizes.hairline, color: this.hideTestFiles ? $r('app.color.primary') : $r('app.color.border'), radius: Radius.tool })
          .borderRadius(Radius.tool)
          .accessibilityText(this.hideTestFiles ? '取消隐藏测试文件' : '隐藏测试文件')
          .onClick(() => { this.updateHideTestFiles(!this.hideTestFiles); })
        if (this.hiddenTestFileCount() > 0) {
          Text('已隐藏 ' + this.hiddenTestFileCount() + ' 个测试文件')
            .fontSize(FontSize.caption).fontColor($r('app.color.muted')).layoutWeight(1)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }.width('100%').alignItems(VerticalAlign.Center)
    }.width('100%').padding({ left: Space.sm, right: Space.sm, top: Space.xxs, bottom: Space.xs })
  }

  @Builder
  fileRow(file: DiffFile, repoKey: string, isFirst: boolean) {
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
    }
    .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
    .width('100%')
    .constraintSize({ minHeight: Sizes.formRowMin })
    .justifyContent(FlexAlign.Center)
    .border({ width: { top: isFirst ? 0 : Sizes.hairline }, color: { top: $r('app.color.separator') } })
    .onClick(() => {
      this.selectedPath = file.path || file.previousPath;
      this.selectedFileRepoKey = repoKey;
      this.start = -1;
      this.end = -1;
    })
  }

  @Builder
  fileList() {
    Column({ space: Space.xs }) {
      if (this.loading) {
        GroupCard() {
          Text('正在读取 Diff…').fontSize(FontSize.callout).fontColor($r('app.color.muted')).width('100%').padding(Space.md)
        }
      } else if (this.error && this.totalFileCount() === 0) {
        GroupCard() {
          Text(this.error).fontSize(FontSize.callout).fontColor($r('app.color.danger')).width('100%').padding(Space.md)
        }
      } else if (this.totalFileCount() === 0) {
        GroupCard() {
          Text(this.mode === 'working-tree' ? '工作区没有改动' : '没有可显示的差异')
            .fontSize(FontSize.callout).fontColor($r('app.color.muted')).width('100%')
            .textAlign(TextAlign.Center).padding(Space.lg)
        }
      } else if (this.visibleFiles().length === 0) {
        GroupCard() {
          Column({ space: Space.xs }) {
            Text('仅变更了测试文件')
              .fontSize(FontSize.headline).fontWeight(Weight.semibold).fontColor($r('app.color.ink'))
              .width('100%').textAlign(TextAlign.Center)
            Text('此审阅中已隐藏测试文件。')
              .fontSize(FontSize.callout).fontColor($r('app.color.muted'))
              .width('100%').textAlign(TextAlign.Center)
            AppButton({
              label: '显示测试文件', kind: 'secondary', compact: true,
              onTap: () => { this.updateHideTestFiles(false); }
            })
          }.width('100%').alignItems(HorizontalAlign.Center).padding(Space.lg)
        }
      } else if (this.isMultiRepo()) {
        Scroll() {
          Column({ space: Space.sm }) {
            ForEach(this.activeGroups(), (group: RepoReviewGroup) => {
              if (this.visibleFilesForGroup(group).length > 0 || this.activeGroups().length === 1) {
                Column({ space: 0 }) {
                  Row({ space: Space.xs }) {
                    Text(group.name)
                      .fontSize(FontSize.caption).fontWeight(Weight.semibold).fontColor($r('app.color.ink'))
                      .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(this.visibleFilesForGroup(group).length + ' 个文件')
                      .fontSize(FontSize.caption).fontColor($r('app.color.muted'))
                    if (group.additions > 0) {
                      Text('+' + group.additions).fontSize(FontSize.badge).fontColor($r('app.color.diff_add_ink'))
                    }
                    if (group.deletions > 0) {
                      Text('-' + group.deletions).fontSize(FontSize.badge).fontColor($r('app.color.diff_del_ink'))
                    }
                  }.width('100%').padding({ left: Space.xxs, right: Space.xxs, bottom: 4 }).alignItems(VerticalAlign.Center)

                  if (this.visibleFilesForGroup(group).length === 0) {
                    GroupCard() {
                      Text('此仓库无改动文件')
                        .fontSize(FontSize.callout).fontColor($r('app.color.muted')).width('100%').padding(Space.md)
                    }
                  } else {
                    Column({ space: 0 }) {
                      ForEach(this.visibleFilesForGroup(group), (file: DiffFile, idx: number) => {
                        this.fileRow(file, group.key, idx === 0)
                      }, (file: DiffFile, idx: number) => group.key + ':' + (file.path || file.previousPath) + ':' + file.changeType + ':' + idx)
                    }.width('100%').backgroundColor($r('app.color.card')).borderRadius(Radius.card).clip(true)
                  }
                }.width('100%').alignItems(HorizontalAlign.Start)
              }
            }, (group: RepoReviewGroup) => group.key + ':' + group.files.length + ':' + (this.hideTestFiles ? '1' : '0'))
            if (this.error) {
              Text(this.error).fontSize(FontSize.caption).fontColor($r('app.color.danger')).width('100%')
            }
          }.width('100%').alignItems(HorizontalAlign.Start).padding({ bottom: Space.md })
        }.width('100%').layoutWeight(1).align(Alignment.TopStart)
      } else {
        List({ space: 0 }) {
          ForEach(this.visibleFiles(), (file: DiffFile, index: number) => {
            ListItem() {
              this.fileRow(file, '', true)
            }
          }, (file: DiffFile, index: number) => (file.path || file.previousPath) + ':' + file.changeType + ':' + index)
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
            disabled: !(this.fileIndex() >= 0 && this.fileIndex() < this.visibleIndexedFiles().length - 1),
            onTap: () => this.stepFile(1)
          })
          Text((this.fileIndex() + 1) + ' / ' + this.visibleIndexedFiles().length).fontSize(FontSize.caption)
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
                  .width('100%').padding({ left: 10, right: 10, top: 6, bottom: 6 }).backgroundColor($r('app.color.group'))
                ForEach(hunk.rows, (row: DiffRow, index: number) => {
                  this.diffRow(hunk, row, index)
                }, (row: DiffRow, index: number) => hunk.header + ':' + index)
              }.width('100%').backgroundColor($r('app.color.card')).borderRadius(Radius.card).clip(true)
            }
          }, (hunk: DiffHunk) => this.selectedFileRepoKey + ':' + this.selectedPath + ':' + hunk.header)
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
    return this.visibleIndexedFiles().findIndex((entry: IndexedReviewFile) =>
      (entry.file.path || entry.file.previousPath) === this.selectedPath &&
      (!this.selectedFileRepoKey || entry.groupKey === this.selectedFileRepoKey));
  }

  private stepFile(delta: number): void {
    const visible = this.visibleIndexedFiles();
    const index = this.fileIndex();
    const next = Math.max(0, Math.min(visible.length - 1, index + delta));
    if (next === index || next < 0) return;
    this.selectedPath = visible[next].file.path || visible[next].file.previousPath;
    this.selectedFileRepoKey = visible[next].groupKey;
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
