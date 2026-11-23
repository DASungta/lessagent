import { TopBar } from './ui/TopBar';
import { GroupCard } from './ui/GroupCard';
import { AppButton } from './ui/AppButton';
import { StatusBadge } from './ui/StatusBadge';
import { FontSize, LineHeight, Radius, Sizes, Space, Weight } from '../common/Theme';
import { T3Client } from '../services/T3Client';
import { RefView, VcsChange, VcsView, emptyVcs, pullRequestStateLabel } from '../protocol/R5';
import { ProjectView } from '../protocol/Projects';
import {
  PinnedThreadRepository,
  TaskFolder,
  ThreadRepositorySection,
  WorkspaceFolder,
  otherTaskFolderRepositories,
  pinThreadRepository,
  threadChangedRepositories,
  threadGitRepositories,
  threadRepositorySections,
  unpinThreadRepository
} from '../protocol/ThreadRepositories';
import { record, text } from '../protocol/Wire';

@Component
export struct GitPanel {
  connection: T3Client | undefined = undefined;
  @Prop cwd: string = '';
  @Prop threadId: string = '';
  @Prop projectId: string = '';
  @Prop worktreePath: string = '';
  @Prop project: ProjectView | undefined = undefined;
  @Prop checkpointScopes: Record<string, Object>[] = [];
  @Prop checkpoints: Record<string, Object>[] = [];
  onBack: () => void = () => {};
  onStatus: (value: string) => void = () => {};

  @State status: VcsView = emptyVcs();
  @State refs: RefView[] = [];
  @State view: string = 'overview';
  @State commitMessage: string = '';
  @State featureBranch: boolean = false;
  @State busy: boolean = false;
  @State error: string = '';
  @State notice: string = '';
  @State branchQuery: string = '';

  // Multi-repository state (unused for single-repo projects).
  @State taskFolder: TaskFolder | undefined = undefined;
  @State folders: WorkspaceFolder[] = [];
  @State pinnedRepos: PinnedThreadRepository[] = [];
  @State showAllRepos: boolean = false;
  @State repoPickerOpen: boolean = false;
  @State addingRepoName: string = '';
  @State activeRepo: ThreadRepositorySection | undefined = undefined;
  @State repoStatuses: Record<string, VcsView> = {};
  @State repoStatusTick: number = 0;

  private rootStream: ((value: Object) => void) | undefined = undefined;
  private repoStreams: Map<string, (value: Object) => void> = new Map();
  private loadGeneration: number = 0;

  aboutToAppear(): void {
    const connection = this.connection;
    if (!connection || !this.cwd) return;
    this.rootStream = connection.watchVcsStatus(this.cwd, (value: VcsView) => {
      this.status = value;
    });
    void this.loadRefs();
    void this.refreshStatus(false);
    void this.loadRepositories();
  }

  aboutToDisappear(): void {
    this.loadGeneration += 1;
    this.stopAllStreams();
  }

  private stopAllStreams(): void {
    if (this.connection && this.rootStream) this.connection.stopRpcStream(this.rootStream);
    this.rootStream = undefined;
    if (this.connection) {
      this.repoStreams.forEach((stream: (value: Object) => void) => {
        this.connection?.stopRpcStream(stream);
      });
    }
    this.repoStreams.clear();
  }

  private async loadRepositories(): Promise<void> {
    const conn = this.connection;
    const gen = ++this.loadGeneration;
    if (!conn || !conn.ready) return;
    const trackedCount = this.project?.trackedFolders?.length || 0;
    const changed = threadChangedRepositories(this.checkpoints, this.checkpointScopes);
    if (trackedCount === 0 && changed.length === 0) return;
    if (this.worktreePath && trackedCount > 0 && conn.canReadFiles()) {
      try {
        const tf = await conn.getTaskFolder(this.worktreePath);
        if (gen !== this.loadGeneration) return;
        this.taskFolder = tf;
      } catch (_) {
        if (gen !== this.loadGeneration) return;
        this.taskFolder = undefined;
      }
    }
    if (this.projectId && conn.canReadFiles()) {
      try {
        const list = await conn.listWorkspaceFolders(this.projectId);
        if (gen !== this.loadGeneration) return;
        this.folders = list;
      } catch (_) {
        if (gen !== this.loadGeneration) return;
        this.folders = [];
      }
    }
    this.syncRepoStreams();
  }

  private reachesTracked(): boolean {
    const trackedCount = this.project?.trackedFolders?.length || 0;
    return trackedCount > 0 && (!this.worktreePath || this.taskFolder !== undefined);
  }

  private repoSections(): ThreadRepositorySection[] {
    const changed = threadChangedRepositories(this.checkpoints, this.checkpointScopes);
    const derived = threadRepositorySections(
      changed,
      this.pinnedRepos,
      this.cwd,
      this.showAllRepos,
      this.taskFolder,
      this.reachesTracked()
    );
    const combined = derived.visible.slice();
    // For a multi-repo project running in place, also surface tracked Git repositories immediately
    // so every repository gets a status row without requiring a prior turn change.
    if (this.taskFolder === undefined && this.reachesTracked()) {
      const seen = new Set<string>(combined.map((section: ThreadRepositorySection) => section.key));
      if (this.cwd) seen.add(this.cwd);
      const gitRepos = threadGitRepositories(changed, undefined, this.folders, this.cwd);
      for (const repo of gitRepos) {
        if (seen.has(repo.repositoryPath)) continue;
        seen.add(repo.repositoryPath);
        combined.push({ key: repo.repositoryPath, name: repo.name, cwd: repo.cwd, origin: 'tracked' });
      }
    }
    return combined;
  }

  private hiddenRepoCount(): number {
    if (this.taskFolder === undefined && this.reachesTracked()) return 0;
    const changed = threadChangedRepositories(this.checkpoints, this.checkpointScopes);
    return threadRepositorySections(
      changed,
      this.pinnedRepos,
      this.cwd,
      this.showAllRepos,
      this.taskFolder,
      this.reachesTracked()
    ).hidden.length;
  }

  private isMultiRepo(): boolean {
    return this.repoSections().length > 0 || (this.project?.trackedFolders?.length || 0) > 0;
  }

  private addableRepositories(): PinnedThreadRepository[] {
    if (this.taskFolder !== undefined) {
      return otherTaskFolderRepositories(this.folders, this.taskFolder);
    }
    const existing = new Set<string>(this.repoSections().map((section: ThreadRepositorySection) => section.key));
    if (this.cwd) existing.add(this.cwd);
    const result: PinnedThreadRepository[] = [];
    for (const folder of this.folders) {
      if (folder.state !== 'git' || existing.has(folder.path)) continue;
      result.push({ repositoryPath: folder.path, name: folder.name });
    }
    return result;
  }

  private syncRepoStreams(): void {
    const conn = this.connection;
    if (!conn || !conn.ready) return;
    const sections = this.repoSections();
    const wantedCwds = new Set<string>();
    for (const section of sections) {
      if (section.cwd && section.cwd !== this.cwd) wantedCwds.add(section.cwd);
    }
    const toRemove: string[] = [];
    this.repoStreams.forEach((stream: (value: Object) => void, repoCwd: string) => {
      if (!wantedCwds.has(repoCwd)) {
        conn.stopRpcStream(stream);
        toRemove.push(repoCwd);
      }
    });
    for (const key of toRemove) this.repoStreams.delete(key);
    wantedCwds.forEach((repoCwd: string) => {
      if (this.repoStreams.has(repoCwd)) return;
      const stream = conn.watchVcsStatus(repoCwd, (value: VcsView) => {
        const next: Record<string, VcsView> = {};
        for (const k of Object.keys(this.repoStatuses)) next[k] = this.repoStatuses[k];
        next[repoCwd] = value;
        this.repoStatuses = next;
        this.repoStatusTick += 1;
      });
      this.repoStreams.set(repoCwd, stream);
      void conn.refreshVcs(repoCwd).then((value: VcsView) => {
        const next: Record<string, VcsView> = {};
        for (const k of Object.keys(this.repoStatuses)) next[k] = this.repoStatuses[k];
        next[repoCwd] = value;
        this.repoStatuses = next;
        this.repoStatusTick += 1;
      }).catch(() => {});
    });
  }

  private targetCwd(): string {
    return this.activeRepo ? this.activeRepo.cwd : this.cwd;
  }

  private targetName(): string {
    if (this.activeRepo) return this.activeRepo.name;
    return this.project?.label || '项目根目录';
  }

  private targetStatus(): VcsView {
    const _tick = this.repoStatusTick;
    if (this.activeRepo && _tick >= 0) {
      return this.repoStatuses[this.activeRepo.cwd] || emptyVcs();
    }
    return this.status;
  }

  private statusCardTitle(): string {
    if (this.activeRepo) return '工作区状态 · ' + this.activeRepo.name;
    if (this.isMultiRepo()) return '主工作区状态';
    return '工作区状态';
  }

  private async loadRefs(): Promise<void> {
    const connection = this.connection;
    const cwd = this.targetCwd();
    if (!connection || !cwd) return;
    try { this.refs = await connection.workspaceRefs(cwd, this.branchQuery); }
    catch (reason) { this.error = (reason as Error).message; }
  }

  private summaryFor(vcs: VcsView): string {
    if (!vcs.isRepo) return '不是 Git 仓库';
    const parts: string[] = [];
    parts.push(vcs.files.length ? vcs.files.length + ' 个文件已改动' : '工作区干净');
    if (vcs.ahead > 0) parts.push('领先 ' + vcs.ahead);
    if (vcs.behind > 0) parts.push('落后 ' + vcs.behind);
    if (vcs.prNumber > 0) parts.push(pullRequestStateLabel(vcs.prState, false) + ' #' + vcs.prNumber);
    return parts.join(' · ');
  }

  private async run(action: string): Promise<void> {
    const connection = this.connection;
    if (!connection || this.busy) return;
    const vcs = this.targetStatus();
    if (!vcs.isRepo) { this.error = '不是 Git 仓库'; return; }
    if ((action === 'commit' || action === 'commit_push' || action === 'commit_push_pr') &&
      !this.commitMessage.trim()) { this.error = '请输入提交信息'; return; }
    const isPushAction = action === 'push' || action === 'commit_push' || action === 'commit_push_pr';
    if (isPushAction && !vcs.hasPrimaryRemote) {
      this.error = '仓库没有可推送的远端';
      return;
    }
    const repoLabel = this.targetName();
    const branchLabel = vcs.refName || 'Detached HEAD';
    if (isPushAction && vcs.isDefaultRef && !vcs.prNumber) {
      AlertDialog.show({
        title: '推送到默认分支？',
        message: (this.isMultiRepo() ? '目标仓库：' + repoLabel + '\n' : '') +
          '当前在 ' + branchLabel + '，推送会直接影响默认分支。',
        primaryButton: { value: '取消', action: () => {} },
        secondaryButton: { value: '推送', action: () => { void this.execute(action); } }
      });
      return;
    }
    if (this.isMultiRepo() && (action === 'commit' || isPushAction)) {
      const actionLabel = action === 'push' ? '推送' : action === 'commit' ? '提交' :
        action === 'commit_push' ? '提交并推送' : '提交、推送并创建 PR';
      AlertDialog.show({
        title: '确认目标仓库',
        message: '将在仓库「' + repoLabel + '」（分支 ' + branchLabel + '）执行「' + actionLabel + '」。',
        primaryButton: { value: '取消', action: () => {} },
        secondaryButton: { value: '确认' + actionLabel, action: () => { void this.execute(action); } }
      });
      return;
    }
    await this.execute(action);
  }

  private async execute(action: string): Promise<void> {
    const connection = this.connection;
    const cwd = this.targetCwd();
    if (!connection || !cwd) return;
    this.busy = true; this.error = ''; this.notice = '正在执行 ' + action + '…';
    try {
      const value = record(await connection.gitAction(cwd, action, this.commitMessage, this.featureBranch,
        [], (label: string) => { this.notice = label; }));
      this.notice = this.result(value);
      if (action !== 'create_pr') this.commitMessage = '';
      try {
        const refreshed = await connection.refreshVcs(cwd);
        this.applyRefreshedStatus(cwd, refreshed);
      } catch (_) {}
    } catch (reason) {
      this.error = 'Git 操作失败：' + (reason as Error).message + '。不会自动重试，请核对仓库状态。';
      this.notice = '';
    } finally { this.busy = false; }
  }

  private applyRefreshedStatus(cwd: string, refreshed: VcsView): void {
    if (cwd === this.cwd) this.status = refreshed;
    if (this.activeRepo && this.activeRepo.cwd === cwd || this.repoStatuses[cwd] !== undefined) {
      const next: Record<string, VcsView> = {};
      for (const k of Object.keys(this.repoStatuses)) next[k] = this.repoStatuses[k];
      next[cwd] = refreshed;
      this.repoStatuses = next;
      this.repoStatusTick += 1;
    }
  }

  private result(value: Record<string, Object>): string {
    const commit = value.commit === undefined ? undefined : record(value.commit);
    const push = value.push === undefined ? undefined : record(value.push);
    const pr = value.pr === undefined ? undefined : record(value.pr);
    const parts: string[] = [];
    if (commit && typeof commit.status === 'string') parts.push('提交 ' + commit.status);
    if (push && typeof push.status === 'string') parts.push('推送 ' + push.status);
    if (pr && typeof pr.status === 'string') parts.push('PR ' + pr.status +
      (typeof pr.url === 'string' ? ' ' + pr.url : ''));
    return parts.join(' · ') || '操作完成';
  }

  private async pull(): Promise<void> {
    const connection = this.connection;
    const cwd = this.targetCwd();
    if (!connection || !cwd || this.busy) return;
    this.busy = true; this.error = ''; this.notice = '正在拉取…';
    try {
      const value = record(await connection.pullRepository(cwd));
      this.notice = text(value.status) === 'pulled' ? '已拉取' : '已是最新';
      try {
        const refreshed = await connection.refreshVcs(cwd);
        this.applyRefreshedStatus(cwd, refreshed);
      } catch (_) {}
    } catch (reason) {
      this.error = '拉取失败：' + (reason as Error).message + '。不会自动重试。';
      this.notice = '';
    } finally { this.busy = false; }
  }

  private async refreshStatus(showBusy: boolean = true): Promise<void> {
    const connection = this.connection;
    const cwd = this.targetCwd();
    if (!connection || !cwd || (showBusy && this.busy)) return;
    if (showBusy) this.busy = true;
    this.error = '';
    try {
      const refreshed = await connection.refreshVcs(cwd);
      this.applyRefreshedStatus(cwd, refreshed);
      if (!this.activeRepo && this.isMultiRepo()) {
        for (const section of this.repoSections()) {
          if (section.cwd && section.cwd !== this.cwd) {
            try {
              const repoVcs = await connection.refreshVcs(section.cwd);
              this.applyRefreshedStatus(section.cwd, repoVcs);
            } catch (_) {}
          }
        }
      }
    } catch (reason) {
      if (this.activeRepo || !this.isMultiRepo()) this.error = (reason as Error).message;
    } finally { if (showBusy) this.busy = false; }
  }

  private confirmCheckout(ref: RefView): void {
    this.busy = true; this.error = ''; this.notice = '正在切换分支…';
    const connection = this.connection;
    const cwd = this.targetCwd();
    if (!connection || !cwd) { this.busy = false; return; }
    void connection.checkoutRef(cwd, ref.name)
      .then(() => {
        this.notice = '已切换到 ' + ref.name;
        this.view = 'overview';
        void this.loadRefs();
        void this.refreshStatus();
      })
      .catch((reason: Error) => {
        this.error = '切换分支失败：' + reason.message + '。不会自动重试。';
        this.notice = '';
      })
      .finally(() => { this.busy = false; });
  }

  private openRepository(section: ThreadRepositorySection): void {
    this.activeRepo = section;
    this.view = 'overview';
    this.error = '';
    this.notice = '';
    this.refs = [];
    void this.loadRefs();
    void this.refreshStatus(false);
  }

  private async pickOtherRepository(repo: PinnedThreadRepository): Promise<void> {
    const conn = this.connection;
    if (this.taskFolder !== undefined) {
      if (!conn || !this.threadId || this.addingRepoName) return;
      this.addingRepoName = repo.name;
      this.repoPickerOpen = false;
      this.error = '';
      try {
        this.taskFolder = await conn.addTaskFolderRepository(this.threadId, repo.repositoryPath);
        this.showAllRepos = true;
        this.syncRepoStreams();
        this.notice = '已为仓库「' + repo.name + '」创建工作树';
      } catch (reason) {
        this.error = '无法添加仓库工作树：' + (reason as Error).message;
      } finally {
        this.addingRepoName = '';
      }
      return;
    }
    this.pinnedRepos = pinThreadRepository(this.pinnedRepos, repo);
    this.repoPickerOpen = false;
    this.syncRepoStreams();
  }

  @Builder
  header() {
    TopBar({
      title: this.view === 'commit' ? '提交' : this.view === 'branches' ? '分支' :
        this.activeRepo ? this.activeRepo.name : 'Git',
      subtitle: this.activeRepo
        ? ((this.targetStatus().refName || 'Detached HEAD') + ' · ' + this.activeRepo.cwd)
        : (this.isMultiRepo() && !this.status.isRepo
          ? (this.repoSections().length + ' 个关联仓库 · ' + this.cwd)
          : ((this.status.refName || 'Detached HEAD') + ' · ' + this.cwd)),
      showBack: true,
      closeStyle: this.view === 'overview' && !this.activeRepo,
      backLabel: this.view !== 'overview' ? '返回仓库概览' : this.activeRepo ? '返回仓库列表' : '关闭 Git',
      onBack: () => {
        if (this.view !== 'overview') { this.view = 'overview'; return; }
        if (this.activeRepo) { this.activeRepo = undefined; this.error = ''; this.notice = ''; return; }
        this.onBack();
      }
    }) {
      if (this.view === 'overview') {
        AppButton({ label: '刷新', kind: 'text', onTap: () => { void this.refreshStatus(); } })
        if (this.targetStatus().isRepo) {
          AppButton({ label: '分支', kind: 'text', onTap: () => { this.view = 'branches'; void this.loadRefs(); } })
        }
      }
    }
  }

  @Builder
  statusCard() {
    GroupCard({ title: this.statusCardTitle() }) {
      Column({ space: Space.xs }) {
        if (this.isMultiRepo()) {
          Text('目标仓库：' + this.targetName() + (this.targetStatus().refName ? (' · ' + this.targetStatus().refName) : ''))
            .fontSize(FontSize.caption).fontColor($r('app.color.primary_text')).fontWeight(Weight.medium).width('100%')
        }
        Text(this.summaryFor(this.targetStatus())).fontSize(FontSize.body).fontWeight(Weight.medium).fontColor($r('app.color.ink')).width('100%')
        if (this.targetStatus().insertions > 0 || this.targetStatus().deletions > 0) {
          Row({ space: Space.xs }) {
            if (this.targetStatus().insertions > 0) {
              Text('+' + this.targetStatus().insertions)
                .fontSize(FontSize.badge).fontWeight(Weight.medium).fontColor($r('app.color.diff_add_ink'))
                .backgroundColor($r('app.color.diff_add')).borderRadius(Radius.badge)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            }
            if (this.targetStatus().deletions > 0) {
              Text('-' + this.targetStatus().deletions)
                .fontSize(FontSize.badge).fontWeight(Weight.medium).fontColor($r('app.color.diff_del_ink'))
                .backgroundColor($r('app.color.diff_del')).borderRadius(Radius.badge)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            }
          }.width('100%')
        }
        if (this.targetStatus().prNumber > 0 && this.targetStatus().prTitle) {
          StatusBadge({ text: 'PR #' + this.targetStatus().prNumber + ' · ' + this.targetStatus().prTitle, tone: 'info' })
        }
        Row({ space: Space.xs }) {
          Column() {
            AppButton({
              label: '提交', kind: 'primary', compact: true, fill: true,
              disabled: this.busy || !this.targetStatus().hasWorkingTreeChanges,
              onTap: () => { this.view = 'commit'; }
            })
          }.layoutWeight(1)
          Column() {
            AppButton({
              label: '推送', kind: 'secondary', compact: true, fill: true,
              disabled: this.busy,
              onTap: () => { void this.run('push'); }
            })
          }.layoutWeight(1)
          Column() {
            AppButton({
              label: '拉取', kind: 'secondary', compact: true, fill: true,
              disabled: this.busy || !this.targetStatus().hasPrimaryRemote,
              onTap: () => { void this.pull(); }
            })
          }.layoutWeight(1)
        }.width('100%').padding({ top: Space.xs })
      }.padding({ left: 14, right: 14, top: Space.sm, bottom: Space.sm }).width('100%').alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  repositoriesSection() {
    GroupCard({ title: '关联仓库（' + this.repoSections().length + '）' }) {
      Column({ space: 0 }) {
        if (this.repoSections().length === 0) {
          Text(this.taskFolder !== undefined ? '此会话暂未添加仓库工作树。' : '此项目暂未检测到可用关联 Git 仓库。')
            .fontSize(FontSize.callout).fontColor($r('app.color.muted'))
            .width('100%').padding(14)
        } else {
          ForEach(this.repoSections(), (section: ThreadRepositorySection, index: number) => {
            Button({ type: ButtonType.Normal }) {
              Row({ space: Space.xs }) {
                Column({ space: 3 }) {
                  Row({ space: Space.xs }) {
                    Text(section.name)
                      .fontSize(FontSize.body).fontWeight(Weight.medium).fontColor($r('app.color.ink'))
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                    if (this.repoStatuses[section.cwd]?.refName) {
                      StatusBadge({ text: this.repoStatuses[section.cwd].refName, tone: 'info' })
                    }
                  }.width('100%').alignItems(VerticalAlign.Center)
                  Row({ space: Space.xs }) {
                    Text(this.repoStatuses[section.cwd]
                      ? this.summaryFor(this.repoStatuses[section.cwd])
                      : '正在读取仓库状态…')
                      .fontSize(FontSize.caption).fontColor($r('app.color.muted'))
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                    if ((this.repoStatuses[section.cwd]?.insertions || 0) > 0) {
                      Text('+' + this.repoStatuses[section.cwd].insertions)
                        .fontSize(FontSize.badge).fontColor($r('app.color.diff_add_ink'))
                    }
                    if ((this.repoStatuses[section.cwd]?.deletions || 0) > 0) {
                      Text('-' + this.repoStatuses[section.cwd].deletions)
                        .fontSize(FontSize.badge).fontColor($r('app.color.diff_del_ink'))
                    }
                  }.width('100%').alignItems(VerticalAlign.Center)
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Image($r('app.media.ui_chevron_right')).width(Sizes.chevron).height(Sizes.chevron).opacity(0.55).accessibilityLevel('no')
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
              .constraintSize({ minHeight: Sizes.formRowMin })
              .alignItems(VerticalAlign.Center)
            }
            .width('100%').padding(0).backgroundColor(Color.Transparent)
            .border({ width: { top: index === 0 ? 0 : Sizes.hairline }, color: { top: $r('app.color.separator') } })
            .accessibilityText('管理仓库 ' + section.name)
            .onClick(() => this.openRepository(section))
          }, (section: ThreadRepositorySection) => section.key + ':' + this.repoStatusTick)
        }

        if (this.hiddenRepoCount() > 0 || (this.showAllRepos && this.repoSections().length > 4)) {
          Row() {
            AppButton({
              label: this.showAllRepos ? '收起仓库' : ('展开其余 ' + this.hiddenRepoCount() + ' 个仓库'),
              kind: 'text',
              compact: true,
              onTap: () => { this.showAllRepos = !this.showAllRepos; this.syncRepoStreams(); }
            })
          }.width('100%').padding({ left: 14, right: 14, top: Space.xxs, bottom: Space.xxs })
            .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
        }

        if (this.addableRepositories().length > 0) {
          Column({ space: Space.xs }) {
            AppButton({
              label: this.addingRepoName ? ('正在添加 ' + this.addingRepoName + '…') :
                (this.taskFolder !== undefined ? '添加其他仓库工作树…' : '固定其他关联仓库…'),
              kind: 'secondary',
              compact: true,
              disabled: this.busy || !!this.addingRepoName,
              onTap: () => { this.repoPickerOpen = !this.repoPickerOpen; }
            })
            if (this.repoPickerOpen) {
              ForEach(this.addableRepositories(), (repo: PinnedThreadRepository) => {
                Row({ space: Space.xs }) {
                  Text(repo.name).fontSize(FontSize.callout).fontColor($r('app.color.ink')).layoutWeight(1)
                  AppButton({
                    label: this.taskFolder !== undefined ? '创建工作树' : '显示',
                    kind: 'primary',
                    compact: true,
                    onTap: () => { void this.pickOtherRepository(repo); }
                  })
                }.width('100%').padding({ top: 4, bottom: 4 }).alignItems(VerticalAlign.Center)
              }, (repo: PinnedThreadRepository) => 'add:' + repo.repositoryPath)
            }
          }
          .width('100%').alignItems(HorizontalAlign.Start)
          .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
          .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
        }
      }.width('100%').alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  overview() {
    Column({ space: Space.sm }) {
      if (this.activeRepo) {
        this.statusCard()
        if (this.activeRepo.origin === 'pinned') {
          AppButton({
            label: '取消固定此仓库',
            kind: 'secondary',
            compact: true,
            onTap: () => {
              this.pinnedRepos = unpinThreadRepository(this.pinnedRepos, this.activeRepo!.key);
              this.activeRepo = undefined;
              this.syncRepoStreams();
            }
          })
        }
      } else if (this.isMultiRepo()) {
        if (this.status.isRepo) {
          this.statusCard()
        }
        this.repositoriesSection()
      } else {
        this.statusCard()
      }

      if (this.activeRepo || this.status.isRepo || !this.isMultiRepo()) {
        if (this.targetStatus().hasWorkingTreeChanges) {
          Text('改动文件')
            .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted'))
            .padding({ left: Space.xxs, right: Space.xxs, top: Space.xxs }).width('100%')
          List({ space: 0 }) {
            ForEach(this.targetStatus().files, (file: VcsChange) => {
              ListItem() {
                Row({ space: Space.xs }) {
                  Text(file.path).fontSize(FontSize.callout).fontColor($r('app.color.ink')).layoutWeight(1).maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (file.insertions > 0) {
                    Text('+' + file.insertions).fontSize(FontSize.badge).fontColor($r('app.color.diff_add_ink'))
                  }
                  if (file.deletions > 0) {
                    Text('-' + file.deletions).fontSize(FontSize.badge).fontColor($r('app.color.diff_del_ink'))
                  }
                }.constraintSize({ minHeight: Sizes.formRowMin }).padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs }).width('100%')
              }
            }, (file: VcsChange) => file.path)
          }.width('100%').constraintSize({ maxHeight: 320 })
            .backgroundColor($r('app.color.card')).borderRadius(Radius.card).clip(true)
            .divider({ strokeWidth: Sizes.hairline, color: $r('app.color.separator') })
        } else {
          GroupCard() {
            Text('没有未提交改动').fontSize(FontSize.callout).fontColor($r('app.color.muted'))
              .width('100%').padding(14)
          }
        }
      }
      if (this.error) { Text(this.error).fontSize(FontSize.callout).fontColor($r('app.color.danger')).width('100%') }
      if (this.notice) { Text(this.notice).fontSize(FontSize.callout).fontColor($r('app.color.primary_text')).width('100%') }
    }.width('100%').padding({ left: Space.sm, right: Space.sm, bottom: Space.lg }).alignItems(HorizontalAlign.Start)
  }

  @Builder
  commitView() {
    Column({ space: Space.sm }) {
      if (this.isMultiRepo()) {
        GroupCard({ title: '目标仓库' }) {
          Column({ space: 2 }) {
            Text(this.targetName() + (this.targetStatus().refName ? (' · ' + this.targetStatus().refName) : ''))
              .fontSize(FontSize.body).fontWeight(Weight.semibold).fontColor($r('app.color.ink')).width('100%')
            Text(this.targetCwd())
              .fontSize(FontSize.caption).fontColor($r('app.color.muted')).maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          }.width('100%').padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs }).alignItems(HorizontalAlign.Start)
        }
      }
      GroupCard({ title: '提交说明' }) {
        Column({ space: Space.xs }) {
          TextArea({ placeholder: '提交信息', text: this.commitMessage })
            .constraintSize({ minHeight: 110 }).width('100%').enabled(!this.busy)
            .fontSize(FontSize.body).fontColor($r('app.color.ink')).placeholderColor($r('app.color.placeholder'))
            .backgroundColor(Color.Transparent).padding(0)
            .onChange((value: string) => { this.commitMessage = value; })
        }.width('100%').padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
        Row({ space: Space.sm }) {
          Text('创建新功能分支').fontSize(FontSize.body).fontColor($r('app.color.ink')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.featureBranch })
            .selectedColor($r('app.color.primary')).switchPointColor(Color.White)
            .onChange((value: boolean) => { this.featureBranch = value; })
        }.width('100%').padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
          .constraintSize({ minHeight: Sizes.formRowMin })
          .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
      }
      AppButton({
        label: '提交', kind: 'primary', fill: true,
        disabled: this.busy || !this.commitMessage.trim(),
        onTap: () => { void this.run('commit'); }
      })
      AppButton({
        label: '提交并推送', kind: 'secondary', fill: true,
        disabled: this.busy || !this.commitMessage.trim() || !this.targetStatus().hasPrimaryRemote,
        onTap: () => { void this.run('commit_push'); }
      })
      AppButton({
        label: '提交、推送并创建 PR', kind: 'secondary', fill: true,
        disabled: this.busy || !this.commitMessage.trim(),
        onTap: () => { void this.run('commit_push_pr'); }
      })
      if (this.error) { Text(this.error).fontSize(FontSize.callout).fontColor($r('app.color.danger')).width('100%') }
      if (this.notice) { Text(this.notice).fontSize(FontSize.callout).fontColor($r('app.color.primary_text')).width('100%') }
    }.width('100%').padding({ left: Space.sm, right: Space.sm, bottom: Space.lg }).alignItems(HorizontalAlign.Start)
  }

  @Builder
  branchesView() {
    Column({ space: Space.xs }) {
      Row({ space: Space.xs }) {
        Image($r('app.media.ui_search')).width(16).height(16).opacity(0.6).accessibilityLevel('no')
        TextInput({ placeholder: '搜索分支', text: this.branchQuery })
          .layoutWeight(1).height(40).fontSize(FontSize.body).fontColor($r('app.color.ink'))
          .placeholderColor($r('app.color.placeholder')).backgroundColor(Color.Transparent).padding(0)
          .onChange((value: string) => { this.branchQuery = value; })
          .onSubmit(() => { void this.loadRefs(); })
      }.width('100%').padding({ left: Space.sm, right: Space.sm }).backgroundColor($r('app.color.card'))
        .borderRadius(Radius.button).alignItems(VerticalAlign.Center)

      List({ space: 0 }) {
        ForEach(this.refs, (ref: RefView) => {
          ListItem() {
            Row({ space: Space.xs }) {
              StatusBadge({
                text: ref.current ? '当前' : ref.isRemote ? '远端' : '分支',
                tone: ref.current ? 'info' : 'neutral'
              })
              Text(ref.name).fontSize(FontSize.body).fontColor($r('app.color.ink')).layoutWeight(1).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (ref.worktreePath && !ref.current) {
                StatusBadge({ text: '工作树占用', tone: 'warning' })
              }
            }.constraintSize({ minHeight: Sizes.formRowMin }).padding({ left: 14, right: 14 }).width('100%')
              .onClick(() => {
                if (ref.current || this.busy) return;
                AlertDialog.show({
                  title: '切换分支？',
                  message: (this.isMultiRepo() ? '仓库：' + this.targetName() + '\n' : '') +
                    ref.name + (ref.worktreePath ? '\n该分支已在其他工作树占用' : ''),
                  primaryButton: { value: '取消', action: () => {} },
                  secondaryButton: { value: '切换', action: () => { this.confirmCheckout(ref); } }
                });
              })
          }
        }, (ref: RefView) => ref.name)
      }.width('100%').layoutWeight(1)
        .backgroundColor($r('app.color.card')).borderRadius(Radius.card).clip(true)
        .divider({ strokeWidth: Sizes.hairline, color: $r('app.color.separator') })

      if (this.error) { Text(this.error).fontSize(FontSize.callout).fontColor($r('app.color.danger')).width('100%') }
      if (this.notice) { Text(this.notice).fontSize(FontSize.callout).fontColor($r('app.color.primary_text')).width('100%') }
    }.width('100%').padding({ left: Space.sm, right: Space.sm, top: Space.xxs, bottom: Space.sm }).layoutWeight(1)
  }

  build() {
    Column({ space: 0 }) {
      this.header()
      if (this.view === 'commit') {
        Scroll() { this.commitView() }.width('100%').layoutWeight(1).align(Alignment.TopStart)
      }
      else if (this.view === 'branches') { this.branchesView() }
      else {
        Scroll() { this.overview() }.width('100%').layoutWeight(1).align(Alignment.TopStart)
      }
      if (this.busy) { LoadingProgress().width(24).height(24).margin({ bottom: Space.xs }) }
    }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
  }
}
