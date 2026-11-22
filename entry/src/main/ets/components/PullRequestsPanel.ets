import { TopBar } from './ui/TopBar';
import { GroupCard } from './ui/GroupCard';
import { AppButton } from './ui/AppButton';
import { IconButton } from './ui/IconButton';
import { StatusBadge } from './ui/StatusBadge';
import { FontSize, LineHeight, Radius, Sizes, Space, Weight } from '../common/Theme';
import { EnvironmentEntry } from '../protocol/Environment';
import { ScopedProject } from '../protocol/Projects';
import { T3Client } from '../services/T3Client';
import { CodeLine } from './CodeLine';
import { DiffLineNumber } from './DiffLineNumber';
import { DiffFile, DiffHunk, DiffRow, firstPullRequestCursor, hasPullRequestCursors, LabelCandidateView,
  mergePullRequestRows, normalizePullRequestCursors, parseDiff, PullRequestDetailView, PullRequestGuideView,
  PullRequestPage, pullRequestPatch, PullRequestProjectChoice, pullRequestProjectChoices,
  PullRequestProjectSource, pullRequestRef, PullRequestRow, pullRequestStateLabel, ReviewerCandidateView,
  reviewCommentDraft, ReviewGuideExcerpt, ReviewGuideFile, ReviewGuideNote, ReviewGuideStop,
  PullRequestActivityView, PullRequestCommentView, PullRequestThreadCommentView, PullRequestThreadView,
  PullRequestCheckView, tagPullRequestRows } from '../protocol/R5';
import { record, text } from '../protocol/Wire';
import { MarkdownView } from './MarkdownView';

interface PullRequestListTarget {
  key: string;
  localId: string;
  label: string;
  client: T3Client;
  generation: number;
  projectId: string;
}

interface PullRequestTargetFetchResult {
  target: PullRequestListTarget;
  page?: PullRequestPage;
  errorMessage: string;
}

@Component
export struct PullRequestsPanel {
  @StorageProp('t3CodeFontSize') codeFontSize: number = 13;
  connection: T3Client | undefined = undefined;
  @Prop @Watch('scopeChanged') environments: EnvironmentEntry[] = [];
  @Prop @Watch('scopeChanged') projects: ScopedProject[] = [];
  @Prop activeLocalId: string = '';
  connectionFor: (localId: string) => T3Client | undefined = () => undefined;
  @Prop projectId: string = '';
  @Prop projectLabel: string = '';
  @Prop embedded: boolean = false;
  @Prop bottomInset: number = 0;
  onDetailChange: (open: boolean) => void = () => {};
  onBack: () => void = () => {};
  onStatus: (value: string) => void = () => {};
  onCopy: (value: string) => void = () => {};

  @State rows: PullRequestRow[] = [];
  @State filter: string = 'open';
  @State query: string = '';
  @State requestedQuery: string = '';
  @State nextCursor: string = '';
  @State errors: string[] = [];
  @State loading: boolean = false;
  @State error: string = '';
  @State selectedEnvLocalId: string = '';
  @State selectedProjectKey: string = '';
  @State filterSheetOpen: boolean = false;
  @State @Watch('selectedChanged') selected: PullRequestRow | undefined = undefined;
  @State detail: PullRequestDetailView | undefined = undefined;
  @State activity: PullRequestActivityView | undefined = undefined;
  @State tab: string = 'overview';
  @State busy: boolean = false;
  @State notice: string = '';
  @State patchFiles: DiffFile[] = [];
  @State diffError: string = '';
  @State selectedFile: string = '';
  @State selectedHunk: string = '';
  @State lineStart: number = -1;
  @State lineEnd: number = -1;
  @State lineComment: string = '';
  @State commenting: boolean = false;
  @State drafts: Object[] = [];
  @State reviewBody: string = '';
  @State commentBody: string = '';
  @State replyThread: string = '';
  @State replyBody: string = '';
  @State editing: boolean = false;
  @State editTitle: string = '';
  @State editBody: string = '';
  @State candidates: LabelCandidateView[] = [];
  @State reviewerCandidates: ReviewerCandidateView[] = [];
  @State panelMode: string = '';
  @State guide: PullRequestGuideView | undefined = undefined;
  @State guideBusy: boolean = false;
  @State guideError: string = '';
  @State activityError: string = '';
  @State liveChecks: PullRequestCheckView[] = [];
  @State liveChecksState: string = '';

  private alive: boolean = false;
  private readRevision: number = 0;
  private readingDetail: boolean = false;
  private nextCursorsByTarget: Map<string, Record<string, string>> = new Map<string, Record<string, string>>();
  private lastTargetsSignature: string = '';
  private detailConnection: T3Client | undefined = undefined;

  aboutToAppear(): void { this.alive = true; void this.loadList(); }
  aboutToDisappear(): void {
    this.alive = false;
    this.readRevision++;
    this.detailConnection = undefined;
    this.finishDetailRead();
  }

  private finishDetailRead(): void {
    if (this.readingDetail) this.busy = false;
    this.readingDetail = false;
    this.loading = false;
  }

  private enabledEnvironments(): EnvironmentEntry[] {
    const entries = this.environments || [];
    return entries.filter((entry: EnvironmentEntry) => entry.enabled && !entry.deleting && !entry.pendingBase);
  }

  private canFilterScope(): boolean {
    return !this.projectId && (this.enabledEnvironments().length > 0 || (this.projects || []).length > 0);
  }

  private projectChoices(envLocalId?: string): PullRequestProjectChoice[] {
    const enabled = this.enabledEnvironments();
    const enabledIds = new Set<string>(enabled.map((entry: EnvironmentEntry) => entry.localId));
    const rawProjects = this.projects || [];
    const sources: PullRequestProjectSource[] = [];
    for (const project of rawProjects) {
      if (enabled.length > 0 && !enabledIds.has(project.localId)) continue;
      sources.push({
        localId: project.localId,
        environmentId: project.environmentId,
        environmentLabel: project.environmentLabel,
        id: project.id,
        label: project.label,
        workspaceRoot: project.workspaceRoot,
        archivedAt: project.archivedAt,
        pinnedAt: project.pinnedAt,
        isScratch: project.isScratch,
        repository: project.repository ? {
          canonicalKey: project.repository.canonicalKey,
          displayName: project.repository.displayName
        } : undefined
      });
    }
    const targetEnv = envLocalId !== undefined ? envLocalId : (this.selectedEnvLocalId || '');
    return pullRequestProjectChoices(sources, targetEnv, this.selectedProjectKey || '');
  }

  private selectedProjectChoice(): PullRequestProjectChoice | undefined {
    const key = this.selectedProjectKey || '';
    if (!key) return undefined;
    return this.projectChoices('').find((choice: PullRequestProjectChoice) => choice.key === key);
  }

  private selectedEnvironmentEntry(): EnvironmentEntry | undefined {
    const localId = this.selectedEnvLocalId || '';
    if (!localId) return undefined;
    return this.enabledEnvironments().find((entry: EnvironmentEntry) => entry.localId === localId);
  }

  private resolveClient(localId: string): T3Client | undefined {
    if (localId && this.connectionFor) {
      const found = this.connectionFor(localId);
      if (found) return found;
    }
    if (!localId || localId === (this.activeLocalId || '')) return this.connection;
    return undefined;
  }

  private clientForRow(row: PullRequestRow | undefined): T3Client | undefined {
    if (row && row.localId) {
      const found = this.resolveClient(row.localId);
      if (found) return found;
    }
    return this.connection;
  }

  private activeDetailClient(): T3Client | undefined {
    return this.detailConnection || this.clientForRow(this.selected) || this.connection;
  }

  private listTargets(): PullRequestListTarget[] {
    const enabled = this.enabledEnvironments();
    if (this.projectId || enabled.length === 0) {
      if (!this.connection) return [];
      return [{
        key: 'default',
        localId: '',
        label: '',
        client: this.connection,
        generation: this.connection.generationValue(),
        projectId: this.projectId
      }];
    }
    const choice = this.selectedProjectChoice();
    if (choice) {
      const client = this.resolveClient(choice.localId);
      if (client && client.ready !== false) {
        return [{
          key: choice.localId,
          localId: choice.localId,
          label: choice.environmentLabel,
          client,
          generation: client.generationValue(),
          projectId: choice.projectId
        }];
      }
      return [];
    }
    const envEntry = this.selectedEnvironmentEntry();
    if (envEntry) {
      const client = this.resolveClient(envEntry.localId);
      if (client && client.ready !== false) {
        return [{
          key: envEntry.localId,
          localId: envEntry.localId,
          label: envEntry.label || envEntry.environmentId,
          client,
          generation: client.generationValue(),
          projectId: ''
        }];
      }
      return [];
    }
    const targets: PullRequestListTarget[] = [];
    const seen = new Set<string>();
    for (const entry of enabled) {
      if (seen.has(entry.localId)) continue;
      seen.add(entry.localId);
      const client = this.resolveClient(entry.localId);
      if (client && client.ready !== false) {
        targets.push({
          key: entry.localId,
          localId: entry.localId,
          label: entry.label || entry.environmentId,
          client,
          generation: client.generationValue(),
          projectId: ''
        });
      }
    }
    if (targets.length === 0 && this.connection && this.connection.ready !== false) {
      const fallbackLocal = this.activeLocalId || '';
      targets.push({
        key: fallbackLocal || 'default',
        localId: fallbackLocal,
        label: '',
        client: this.connection,
        generation: this.connection.generationValue(),
        projectId: ''
      });
    }
    return targets;
  }

  private targetsSignature(targets: PullRequestListTarget[]): string {
    return targets.map((target: PullRequestListTarget) =>
      target.key + ':' + target.projectId + ':' + target.generation).join('|');
  }

  private scopeChanged(): void {
    if (!this.alive || this.selected) return;
    if (this.selectedEnvLocalId && !this.selectedEnvironmentEntry()) {
      this.selectedEnvLocalId = '';
    }
    if (this.selectedProjectKey && !this.selectedProjectChoice()) {
      this.selectedProjectKey = '';
    }
    const sig = this.targetsSignature(this.listTargets());
    if (sig !== this.lastTargetsSignature) {
      void this.loadList();
    }
  }

  private firstPendingCursor(): string {
    let first = '';
    this.nextCursorsByTarget.forEach((cursors: Record<string, string>) => {
      if (!first) first = firstPullRequestCursor(cursors);
    });
    return first;
  }

  private readCurrent(connection: T3Client, generation: number, revision: number, projectId: string): boolean {
    const expected = this.detailConnection || this.connection;
    return this.alive && this.readRevision === revision && expected === connection &&
      connection.generationValue() === generation && this.projectId === projectId;
  }

  private ref(): Object {
    const row = this.selected;
    if (!row) throw new Error('未选择 PR');
    return pullRequestRef(row.projectId || this.projectId, row.repository, row.number, row.host || '');
  }

  private async loadList(): Promise<void> {
    await this.readListPage(false);
  }

  private async loadMore(): Promise<void> {
    if (this.loading || !this.nextCursor || this.query !== this.requestedQuery) return;
    await this.readListPage(true);
  }

  private async readListPage(append: boolean): Promise<void> {
    if (!this.alive || this.selected) return;
    const targets = this.listTargets();
    const signature = this.targetsSignature(targets);
    this.lastTargetsSignature = signature;
    if (targets.length === 0) {
      if (!append) {
        this.readRevision++;
        this.rows = [];
        this.errors = [];
        this.nextCursor = '';
        this.nextCursorsByTarget.clear();
        this.loading = false;
        this.error = (this.selectedProjectKey || this.selectedEnvLocalId) ? '所选环境尚未连接，请连接后重试' : '';
      }
      return;
    }
    const fetchTargets = append ? targets.filter((target: PullRequestListTarget) => {
      const saved = this.nextCursorsByTarget.get(target.key);
      return hasPullRequestCursors(saved) || (targets.length === 1 && !!this.nextCursor);
    }) : targets;
    if (fetchTargets.length === 0) return;

    const revision = ++this.readRevision;
    const projectId = this.projectId;
    const filter = this.filter;
    const query = this.query;
    const selectedEnv = this.selectedEnvLocalId || '';
    const selectedProject = this.selectedProjectKey || '';
    this.requestedQuery = query;
    const legacyCursor = append && targets.length === 1 ? this.nextCursor : '';
    const cursorSnapshot = new Map<string, Record<string, string>>();
    if (append) {
      for (const target of fetchTargets) {
        const saved = this.nextCursorsByTarget.get(target.key);
        if (saved) cursorSnapshot.set(target.key, saved);
      }
    }
    const current = (): boolean => {
      if (!this.alive || this.readRevision !== revision || !!this.selected) return false;
      if (this.projectId !== projectId || this.filter !== filter || this.query !== query) return false;
      if ((this.selectedEnvLocalId || '') !== selectedEnv || (this.selectedProjectKey || '') !== selectedProject) return false;
      for (const target of fetchTargets) {
        if (target.client.generationValue() !== target.generation) return false;
      }
      if (this.enabledEnvironments().length === 0 && this.connection !== fetchTargets[0].client) return false;
      return true;
    };

    this.loading = true;
    if (!append) {
      this.error = '';
      this.errors = [];
      this.rows = [];
      this.nextCursor = '';
      this.nextCursorsByTarget.clear();
    }
    try {
      const multiTarget = targets.length > 1;
      const results: PullRequestTargetFetchResult[] = await Promise.all(
        fetchTargets.map(async (target: PullRequestListTarget): Promise<PullRequestTargetFetchResult> => {
          try {
            const savedCursors = append ? cursorSnapshot.get(target.key) : undefined;
            const useMap = hasPullRequestCursors(savedCursors) ? savedCursors : undefined;
            const cursorArg = append ? (firstPullRequestCursor(useMap) || legacyCursor) : '';
            const page = await target.client.listPullRequests(filter, query, cursorArg, target.projectId, useMap);
            return { target, page, errorMessage: '' };
          } catch (reason) {
            const message = (reason as Error).message || '读取失败';
            return { target, errorMessage: multiTarget && target.label ? target.label + '：' + message : message };
          }
        })
      );
      if (!current()) return;

      let incomingRows: PullRequestRow[] = [];
      const pageErrors: string[] = [];
      const failureErrors: string[] = [];
      let succeededCount = 0;

      for (const item of results) {
        if (item.page) {
          succeededCount++;
          const tagged = item.target.localId ?
            tagPullRequestRows(item.page.rows, item.target.localId, item.target.label) : item.page.rows;
          incomingRows = incomingRows.concat(tagged);
          for (const err of item.page.errors) {
            pageErrors.push(multiTarget && item.target.label ? item.target.label + '：' + err : err);
          }
          const parsedNext = normalizePullRequestCursors(item.page.nextCursors);
          if (hasPullRequestCursors(parsedNext)) {
            this.nextCursorsByTarget.set(item.target.key, parsedNext);
          } else if (item.page.nextCursor) {
            const fallback: Record<string, string> = {};
            fallback['default'] = item.page.nextCursor;
            this.nextCursorsByTarget.set(item.target.key, fallback);
          } else {
            this.nextCursorsByTarget.delete(item.target.key);
          }
        } else if (item.errorMessage) {
          failureErrors.push(item.errorMessage);
          if (!append) this.nextCursorsByTarget.delete(item.target.key);
        }
      }

      if (succeededCount === 0 && failureErrors.length > 0) {
        this.error = failureErrors.join('\n');
        this.nextCursor = this.firstPendingCursor();
        return;
      }

      this.rows = mergePullRequestRows(append ? this.rows : [], incomingRows, multiTarget, this.activeLocalId || '');
      const combinedErrors = pageErrors.concat(failureErrors);
      this.errors = append ? this.errors.concat(combinedErrors) : combinedErrors;
      this.nextCursor = this.firstPendingCursor();
    } catch (reason) {
      if (current()) this.error = (reason as Error).message;
    } finally { if (this.readRevision === revision) this.loading = false; }
  }

  private async open(row: PullRequestRow): Promise<void> {
    const connection = this.clientForRow(row);
    if (!this.alive || !connection || (this.busy && !this.readingDetail)) return;
    const revision = ++this.readRevision;
    const generation = connection.generationValue();
    const projectId = this.projectId;
    const rowProjectId = row.projectId || projectId;
    const repository = row.repository;
    const number = row.number;
    this.detailConnection = connection;
    const current = (): boolean => this.readCurrent(connection, generation, revision, projectId) &&
      !!this.selected && (this.selected.projectId || this.projectId) === rowProjectId &&
      this.selected.repository === repository && this.selected.number === number;
    this.selected = row; this.tab = 'overview'; this.detail = undefined; this.activity = undefined; this.patchFiles = []; this.diffError = '';
    this.selectedFile = ''; this.selectedHunk = ''; this.lineStart = -1; this.lineEnd = -1;
    this.drafts = []; this.error = ''; this.notice = '';
    this.guide = undefined; this.guideError = ''; this.guideBusy = false; this.activityError = '';
    this.liveChecks = []; this.liveChecksState = '';
    this.readingDetail = true; this.busy = true; this.loading = true;
    try {
      const ref = pullRequestRef(rowProjectId, repository, number, row.host || '');
      const detail = await connection.pullRequestDetail(ref);
      if (!current()) return;
      if (detail.number !== number || detail.repository !== repository ||
        (rowProjectId && detail.projectId !== rowProjectId)) throw new Error('PR 详情与所选页面不匹配');
      this.detail = detail;
      try {
        const activity = await connection.pullRequestActivity(ref);
        if (!current()) return;
        this.activity = activity;
      } catch (reason) {
        if (!current()) return;
        this.activity = detail.activity;
        this.activityError = (reason as Error).message;
      }
      try {
        const response = await connection.pullRequestDiff(ref);
        if (!current()) return;
        this.patchFiles = parseDiff(pullRequestPatch(response).patch);
      } catch (_) {
        if (!current()) return;
        this.patchFiles = [];
        this.diffError = '文件差异读取失败，请刷新后重试。';
      }
      try {
        const checks = await connection.pullRequestChecks(ref);
        if (!current()) return;
        if (checks) { this.liveChecks = checks.checks; this.liveChecksState = checks.state; }
      } catch (_) { if (!current()) return; }
      try {
        const guide = await connection.pullRequestReviewGuide(ref);
        if (!current()) return;
        this.guide = guide;
      } catch (_) {
        if (!current()) return;
        this.guide = undefined;
      }
      this.editTitle = detail.title; this.editBody = detail.body;
    } catch (reason) {
      if (current()) { this.error = (reason as Error).message; this.selected = undefined; this.detailConnection = undefined; }
    } finally { if (this.readRevision === revision) this.finishDetailRead(); }
  }

  private closeDetail(): void {
    this.readRevision++;
    this.detailConnection = undefined;
    this.finishDetailRead();
    this.selected = undefined; this.detail = undefined; this.activity = undefined;
    this.patchFiles = []; this.panelMode = ''; this.notice = ''; this.error = '';
    this.guide = undefined; this.guideError = ''; this.guideBusy = false;
    this.liveChecks = []; this.liveChecksState = '';
    void this.loadList();
  }

  private async loadGuide(): Promise<void> {
    const connection = this.activeDetailClient();
    if (!this.alive || !connection || !this.selected || this.guideBusy || this.readingDetail) return;
    const revision = this.readRevision;
    const generation = connection.generationValue();
    const projectId = this.projectId;
    const current = (): boolean => this.readCurrent(connection, generation, revision, projectId);
    this.guideBusy = true; this.guideError = '';
    try {
      const guide = await connection.pullRequestReviewGuide(this.ref());
      if (current()) this.guide = guide;
    } catch (reason) { if (current()) this.guideError = (reason as Error).message; }
    finally { if (this.readRevision === revision) this.guideBusy = false; }
  }

  private async generateGuide(): Promise<void> {
    const connection = this.activeDetailClient();
    if (!connection || this.guideBusy) return;
    this.guideBusy = true; this.guideError = ''; this.notice = '正在请求 Agent 生成评审向导…';
    try {
      this.guide = await connection.generatePullRequestReviewGuide(this.ref());
      this.notice = '';
    } catch (reason) { this.guideError = (reason as Error).message; }
    finally { this.guideBusy = false; }
  }

  private selectedChanged(): void {
    this.onDetailChange(!!this.selected);
  }

  private async runAction(action: string, mergeMethod: string = ''): Promise<void> {
    const connection = this.activeDetailClient();
    if (!connection || this.busy) return;
    this.busy = true; this.error = ''; this.notice = '正在执行 ' + action + '…';
    try {
      await connection.pullRequestAction(this.ref(), action, mergeMethod);
      this.notice = '操作已提交；请刷新核对服务端状态';
      const row = this.selected;
      if (row) await this.open(row);
    } catch (reason) {
      this.error = 'PR 操作失败：' + (reason as Error).message + '。不会自动重试。';
      this.notice = '';
    } finally { this.busy = false; }
  }

  private async submitComment(): Promise<void> {
    const connection = this.activeDetailClient();
    if (!connection || !this.commentBody.trim() || this.busy) return;
    this.busy = true; this.error = '';
    try {
      await connection.pullRequestComment(this.ref(), this.commentBody);
      this.commentBody = ''; this.notice = '评论已提交';
      const row = this.selected;
      if (row) await this.open(row);
    } catch (reason) { this.error = '评论失败：' + (reason as Error).message; }
    finally { this.busy = false; }
  }

  private async submitReview(verdict: string): Promise<void> {
    const connection = this.activeDetailClient();
    if (!connection || this.busy) return;
    this.busy = true; this.error = '';
    try {
      await connection.pullRequestReview(this.ref(), verdict, this.reviewBody, this.drafts);
      this.reviewBody = ''; this.drafts = []; this.notice = '审阅已提交';
      const row = this.selected;
      if (row) await this.open(row);
    } catch (reason) { this.error = '审阅提交失败：' + (reason as Error).message + '。草稿仍保留。'; }
    finally { this.busy = false; }
  }

  private addLineDraft(hunk: DiffHunk): void {
    if (!this.lineComment.trim() || this.lineStart < 0) return;
    const file = this.patchFiles.find((item: DiffFile) => item.path === this.selectedFile);
    if (!file || hunk.rows.length === 0) return;
    const index = Math.min(this.lineStart, hunk.rows.length - 1);
    try {
      this.drafts = this.drafts.concat([reviewCommentDraft(file.path, hunk.rows[index], this.lineComment.trim())]);
      this.lineComment = ''; this.commenting = false; this.lineStart = -1; this.lineEnd = -1;
      this.notice = '已加入审阅草稿（' + this.drafts.length + '）';
    } catch (reason) { this.error = (reason as Error).message; }
  }

  private async saveEdit(): Promise<void> {
    const connection = this.activeDetailClient();
    if (!connection || this.busy) return;
    this.busy = true; this.error = '';
    try {
      await connection.pullRequestUpdate(this.ref(), this.editTitle, this.editBody);
      this.editing = false; this.notice = '已保存；请刷新核对';
      const row = this.selected;
      if (row) await this.open(row);
    } catch (reason) { this.error = '保存失败：' + (reason as Error).message; }
    finally { this.busy = false; }
  }

  private async loadLabels(): Promise<void> {
    const connection = this.activeDetailClient();
    if (!connection) return;
    this.panelMode = 'labels'; this.busy = true; this.error = '';
    try {
      const value = record(await connection.pullRequestLabelCandidates(this.ref()));
      this.candidates = (value.candidates as Object[]).map((candidate: Object): LabelCandidateView => {
        const row = record(candidate);
        return { name: text(row.name), applied: row.isApplied === true };
      });
    } catch (reason) { this.error = (reason as Error).message; }
    finally { this.busy = false; }
  }

  private async toggleLabel(name: string, applied: boolean): Promise<void> {
    const connection = this.activeDetailClient();
    if (!connection) return;
    this.busy = true;
    try {
      await connection.pullRequestSetLabels(this.ref(), [name], !applied);
      this.notice = (!applied ? '已添加标签 ' : '已移除标签 ') + name;
      await this.loadLabels();
    } catch (reason) { this.error = '标签操作失败：' + (reason as Error).message; }
    finally { this.busy = false; }
  }

  private async loadReviewers(): Promise<void> {
    const connection = this.activeDetailClient();
    if (!connection) return;
    this.panelMode = 'reviewers'; this.busy = true; this.error = '';
    try {
      const value = record(await connection.pullRequestReviewerCandidates(this.ref()));
      this.reviewerCandidates = (value.candidates as Object[]).map((candidate: Object): ReviewerCandidateView => {
        const row = record(candidate);
        return { id: text(row.id), kind: text(row.kind),
          name: typeof row.login === 'string' ? row.login : (typeof row.name === 'string' ? row.name : text(row.id)),
          requested: row.isRequested === true };
      });
    } catch (reason) { this.error = (reason as Error).message; }
    finally { this.busy = false; }
  }

  private async toggleReviewer(id: string, kind: string, requested: boolean): Promise<void> {
    const connection = this.activeDetailClient();
    if (!connection) return;
    this.busy = true;
    try {
      await connection.pullRequestRequestReviewers(this.ref(), [{ id, kind }], !requested);
      this.notice = '评审人请求已更新';
      await this.loadReviewers();
    } catch (reason) { this.error = '评审人操作失败：' + (reason as Error).message; }
    finally { this.busy = false; }
  }

  private async reply(threadId: string): Promise<void> {
    const connection = this.activeDetailClient();
    if (!connection || !this.replyBody.trim()) return;
    this.busy = true;
    try {
      await connection.pullRequestReply(this.ref(), threadId, this.replyBody);
      this.replyBody = ''; this.replyThread = ''; this.notice = '回复已提交';
      const row = this.selected;
      if (row) await this.open(row);
    } catch (reason) { this.error = '回复失败：' + (reason as Error).message; }
    finally { this.busy = false; }
  }

  private async react(subjectId: string, content: string): Promise<void> {
    const connection = this.activeDetailClient();
    if (!connection || this.busy) return;
    this.busy = true;
    try {
      await connection.setPullRequestReaction(this.ref(), subjectId, content);
      this.notice = 'Reaction 已提交';
      const row = this.selected;
      if (row) await this.open(row);
    } catch (reason) { this.error = 'Reaction 失败：' + (reason as Error).message; }
    finally { this.busy = false; }
  }

  private async resolveThread(threadId: string, resolved: boolean): Promise<void> {
    const connection = this.activeDetailClient();
    if (!connection || this.busy) return;
    this.busy = true;
    try {
      await connection.pullRequestSetThreadResolution(this.ref(), threadId, resolved);
      this.notice = resolved ? '讨论已标记解决' : '讨论已重新打开';
      const row = this.selected;
      if (row) await this.open(row);
    } catch (reason) { this.error = '讨论状态更新失败：' + (reason as Error).message; }
    finally { this.busy = false; }
  }

  private hasActiveScopeFilter(): boolean {
    return !!this.selectedProjectKey || !!this.selectedEnvLocalId;
  }

  private scopeSummary(): string {
    if (this.projectLabel) return this.projectLabel;
    if (this.projectId) return '当前项目';
    const choice = this.selectedProjectChoice();
    if (choice) return choice.title;
    const env = this.selectedEnvironmentEntry();
    if (env) return (env.label || env.environmentId) + ' · 所有项目';
    return '所有项目';
  }

  private projectFilterChipLabel(): string {
    const choice = this.selectedProjectChoice();
    if (choice) return choice.title;
    return '所有项目';
  }

  private environmentFilterChipLabel(): string {
    const env = this.selectedEnvironmentEntry();
    if (env) return env.label || env.environmentId;
    return '全部环境';
  }

  private projectChoiceSubtitle(choice: PullRequestProjectChoice): string {
    const parts: string[] = [];
    if (choice.repository) parts.push(choice.repository);
    if (this.enabledEnvironments().length > 1 && choice.environmentLabel && !choice.duplicateLabel) {
      parts.push(choice.environmentLabel);
    }
    return parts.join(' · ');
  }

  private rowSubtitle(row: PullRequestRow): string {
    if (row.repository && row.author) return row.repository + ' · ' + row.author;
    return row.repository || row.author;
  }

  private selectEnvironment(localId: string): void {
    this.selectedEnvLocalId = localId;
    if (localId && this.selectedProjectKey) {
      const choice = this.selectedProjectChoice();
      if (!choice || choice.localId !== localId) {
        this.selectedProjectKey = '';
      }
    }
    void this.loadList();
  }

  private selectProject(key: string): void {
    this.selectedProjectKey = key;
    if (key) {
      const choice = this.selectedProjectChoice();
      if (choice && this.selectedEnvLocalId && this.selectedEnvLocalId !== choice.localId) {
        this.selectedEnvLocalId = choice.localId;
      }
    }
    this.filterSheetOpen = false;
    void this.loadList();
  }

  private resetScopeFilters(): void {
    this.selectedEnvLocalId = '';
    this.selectedProjectKey = '';
    this.filterSheetOpen = false;
    void this.loadList();
  }

  private emptyHint(): string {
    if (this.query.trim()) return '';
    const hasScopedProject = !!this.projectId || !!this.selectedProjectKey;
    if (!hasScopedProject) return '';
    if (this.filter !== 'all') {
      return '可切换到“全部”查看已关闭或已合并的 PR，或确认远端仓库已有 Pull Request。';
    }
    return '该项目远端仓库目前没有 Pull Request 记录（仅展示 PR/MR，不含普通 Git 提交）。';
  }

  @Builder
  scopeFilterSheet() {
    Column({ space: 0 }) {
      TopBar({
        title: '筛选拉取请求',
        showBack: true,
        closeStyle: true,
        backLabel: '关闭筛选',
        onBack: () => { this.filterSheetOpen = false; }
      })
      Scroll() {
        Column({ space: Space.md }) {
          if (this.enabledEnvironments().length > 1) {
            GroupCard({ title: '环境' }) {
              Row({ space: Space.sm }) {
                Text('全部环境')
                  .fontSize(FontSize.body).fontColor($r('app.color.ink')).layoutWeight(1)
                if (!this.selectedEnvLocalId) {
                  Text('✓')
                    .fontSize(FontSize.headline).fontWeight(Weight.semibold).fontColor($r('app.color.primary_text'))
                }
              }
              .width('100%').constraintSize({ minHeight: Sizes.formRowMin })
              .padding({ left: Space.md, right: Space.md, top: Space.xs, bottom: Space.xs })
              .alignItems(VerticalAlign.Center)
              .onClick(() => { this.selectEnvironment(''); })

              ForEach(this.enabledEnvironments(), (env: EnvironmentEntry) => {
                Row({ space: Space.sm }) {
                  Column({ space: 2 }) {
                    Text(env.label || env.environmentId)
                      .fontSize(FontSize.body).fontColor($r('app.color.ink'))
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                    Text(this.resolveClient(env.localId)?.ready ? '已连接' : '未连接')
                      .fontSize(FontSize.caption).fontColor($r('app.color.muted')).width('100%')
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  if (this.selectedEnvLocalId === env.localId) {
                    Text('✓')
                      .fontSize(FontSize.headline).fontWeight(Weight.semibold).fontColor($r('app.color.primary_text'))
                  }
                }
                .width('100%').constraintSize({ minHeight: Sizes.formRowMin })
                .padding({ left: Space.md, right: Space.md, top: Space.xs, bottom: Space.xs })
                .alignItems(VerticalAlign.Center)
                .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
                .onClick(() => { this.selectEnvironment(env.localId); })
              }, (env: EnvironmentEntry) => env.localId + ':' + (this.selectedEnvLocalId === env.localId ? '1' : '0') + ':' +
                (this.resolveClient(env.localId)?.ready ? '1' : '0'))
            }
          }

          GroupCard({ title: '项目' }) {
            Row({ space: Space.sm }) {
              Text('所有项目')
                .fontSize(FontSize.body).fontColor($r('app.color.ink')).layoutWeight(1)
              if (!this.selectedProjectKey) {
                Text('✓')
                  .fontSize(FontSize.headline).fontWeight(Weight.semibold).fontColor($r('app.color.primary_text'))
              }
            }
            .width('100%').constraintSize({ minHeight: Sizes.formRowMin })
            .padding({ left: Space.md, right: Space.md, top: Space.xs, bottom: Space.xs })
            .alignItems(VerticalAlign.Center)
            .onClick(() => { this.selectProject(''); })

            ForEach(this.projectChoices(), (choice: PullRequestProjectChoice) => {
              Row({ space: Space.sm }) {
                Column({ space: 2 }) {
                  Text(choice.title)
                    .fontSize(FontSize.body).fontColor($r('app.color.ink'))
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                  if (this.projectChoiceSubtitle(choice)) {
                    Text(this.projectChoiceSubtitle(choice))
                      .fontSize(FontSize.caption).fontColor($r('app.color.muted'))
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                  }
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                if (this.selectedProjectKey === choice.key) {
                  Text('✓')
                    .fontSize(FontSize.headline).fontWeight(Weight.semibold).fontColor($r('app.color.primary_text'))
                }
              }
              .width('100%').constraintSize({ minHeight: Sizes.formRowMin })
              .padding({ left: Space.md, right: Space.md, top: Space.xs, bottom: Space.xs })
              .alignItems(VerticalAlign.Center)
              .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
              .onClick(() => { this.selectProject(choice.key); })
            }, (choice: PullRequestProjectChoice) => choice.key + ':' + choice.title + ':' +
              (this.selectedProjectKey === choice.key ? '1' : '0'))

            if (this.projectChoices().length === 0) {
              Text('当前范围内没有可筛选的项目')
                .fontSize(FontSize.caption).fontColor($r('app.color.muted'))
                .width('100%').padding({ left: Space.md, right: Space.md, top: Space.sm, bottom: Space.sm })
                .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
            }
          }

          Column({ space: Space.xs }) {
            if (this.hasActiveScopeFilter()) {
              AppButton({
                label: '清除项目与环境筛选',
                kind: 'secondary',
                fill: true,
                onTap: () => { this.resetScopeFilters(); }
              })
            }
            AppButton({
              label: '立即刷新',
              kind: 'secondary',
              fill: true,
              onTap: () => {
                this.filterSheetOpen = false;
                void this.loadList();
              }
            })
          }.width('100%')
        }
        .width('100%').padding({ left: Space.sm, right: Space.sm, top: Space.xs, bottom: Space.lg })
      }.width('100%').layoutWeight(1).align(Alignment.TopStart)
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
  }

  @Builder
  header() {
    if (!this.embedded || !!this.selected) {
      TopBar({
        title: this.detail ? '#' + this.detail.number : this.selected ? '#' + this.selected.number : '拉取请求',
        subtitle: this.detail?.repository || this.selected?.repository || this.scopeSummary(),
        showBack: true,
        closeStyle: !this.selected,
        backLabel: this.selected ? '返回 PR 列表' : '关闭拉取请求',
        onBack: () => {
          if (this.selected) { this.closeDetail(); return; }
          this.onBack();
        }
      }) {
        if (this.selected) {
          AppButton({
            label: '刷新', kind: 'text',
            onTap: () => { if (this.selected) void this.open(this.selected); }
          })
        }
      }
    } else {
      Row({ space: Space.xs }) {
        Column({ space: 2 }) {
          Text('拉取请求')
            .fontSize(FontSize.title).lineHeight(LineHeight.title).fontWeight(Weight.semibold)
            .fontColor($r('app.color.ink')).width('100%')
          Row({ space: 4 }) {
            Text(this.scopeSummary())
              .fontSize(FontSize.caption).lineHeight(LineHeight.caption)
              .fontColor(this.hasActiveScopeFilter() ? $r('app.color.primary_text') : $r('app.color.muted'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: '88%' })
            if (this.canFilterScope()) {
              Image($r('app.media.ui_chevron_down')).width(10).height(10).opacity(0.6).accessibilityLevel('no')
            }
          }.alignItems(VerticalAlign.Center)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          .onClick(() => { if (this.canFilterScope()) this.filterSheetOpen = true; })
        if (this.canFilterScope()) {
          Stack({ alignContent: Alignment.TopEnd }) {
            IconButton({
              icon: $r('app.media.ui_filter'),
              label: this.hasActiveScopeFilter() ? '筛选项目与环境（已启用）' : '筛选项目与环境',
              onTap: () => { this.filterSheetOpen = true; }
            })
            if (this.hasActiveScopeFilter()) {
              Circle()
                .width(6).height(6).fill($r('app.color.primary'))
                .margin({ top: 7, right: 7 })
                .hitTestBehavior(HitTestMode.None)
            }
          }
        }
      }
      .width('100%')
      .constraintSize({ minHeight: Sizes.topBar })
      .padding({ left: Space.page, right: Space.sm, top: Space.xs, bottom: Space.xs })
      .alignItems(VerticalAlign.Center)
    }
  }

  @Builder
  listView() {
    Column({ space: Space.xs }) {
      Row({ space: 2 }) {
        ForEach(['open', 'closed', 'merged', 'all'], (state: string) => {
          Button(state === 'open' ? '开放' : state === 'closed' ? '关闭' : state === 'merged' ? '合并' : '全部')
            .fontSize(FontSize.callout)
            .fontWeight(this.filter === state ? Weight.medium : Weight.regular)
            .fontColor(this.filter === state ? $r('app.color.ink') : $r('app.color.muted'))
            .backgroundColor(this.filter === state ? $r('app.color.card') : Color.Transparent)
            .borderRadius(7).layoutWeight(1).constraintSize({ minHeight: 34 })
            .onClick(() => { this.filter = state; void this.loadList(); })
        }, (state: string) => state)
      }.width('100%').padding(2).backgroundColor($r('app.color.group'))
        .border({ width: Sizes.hairline, color: $r('app.color.border') }).borderRadius(9)

      if (this.canFilterScope()) {
        Scroll() {
          Row({ space: Space.xs }) {
            Row({ space: 5 }) {
              Image($r('app.media.ui_folder')).width(13).height(13).opacity(0.75).accessibilityLevel('no')
              Text(this.projectFilterChipLabel())
                .fontSize(FontSize.caption)
                .fontWeight(this.selectedProjectKey ? Weight.semibold : Weight.medium)
                .fontColor(this.selectedProjectKey ? $r('app.color.primary_text') : $r('app.color.ink'))
                .maxLines(1)
              Image($r('app.media.ui_chevron_down')).width(10).height(10).opacity(0.6).accessibilityLevel('no')
            }
            .height(32).padding({ left: 10, right: 10 })
            .backgroundColor(this.selectedProjectKey ? $r('app.color.info_bg') : $r('app.color.card'))
            .border({ width: Sizes.hairline, color: this.selectedProjectKey ? $r('app.color.primary') : $r('app.color.border') })
            .borderRadius(Radius.full).alignItems(VerticalAlign.Center)
            .accessibilityText('按项目筛选：' + this.projectFilterChipLabel())
            .onClick(() => { this.filterSheetOpen = true; })

            if (this.enabledEnvironments().length > 1) {
              Row({ space: 5 }) {
                Image($r('app.media.ui_env_desktop')).width(13).height(13).opacity(0.75).accessibilityLevel('no')
                Text(this.environmentFilterChipLabel())
                  .fontSize(FontSize.caption)
                  .fontWeight(this.selectedEnvLocalId ? Weight.semibold : Weight.medium)
                  .fontColor(this.selectedEnvLocalId ? $r('app.color.primary_text') : $r('app.color.ink'))
                  .maxLines(1)
                Image($r('app.media.ui_chevron_down')).width(10).height(10).opacity(0.6).accessibilityLevel('no')
              }
              .height(32).padding({ left: 10, right: 10 })
              .backgroundColor(this.selectedEnvLocalId ? $r('app.color.info_bg') : $r('app.color.card'))
              .border({ width: Sizes.hairline, color: this.selectedEnvLocalId ? $r('app.color.primary') : $r('app.color.border') })
              .borderRadius(Radius.full).alignItems(VerticalAlign.Center)
              .accessibilityText('按环境筛选：' + this.environmentFilterChipLabel())
              .onClick(() => { this.filterSheetOpen = true; })
            }

            if (this.hasActiveScopeFilter()) {
              Row() {
                Text('清除')
                  .fontSize(FontSize.caption).fontWeight(Weight.medium).fontColor($r('app.color.muted'))
              }
              .height(32).padding({ left: 10, right: 10 })
              .backgroundColor($r('app.color.card'))
              .border({ width: Sizes.hairline, color: $r('app.color.border') })
              .borderRadius(Radius.full).alignItems(VerticalAlign.Center)
              .accessibilityText('清除项目与环境筛选')
              .onClick(() => { this.resetScopeFilters(); })
            }
          }.alignItems(VerticalAlign.Center)
        }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).align(Alignment.Start).width('100%')
      }

      Row({ space: Space.xs }) {
        Image($r('app.media.ui_search')).width(16).height(16).opacity(0.6).accessibilityLevel('no')
        TextInput({ placeholder: '搜索 PR', text: this.query })
          .layoutWeight(1).height(40).fontSize(FontSize.body).fontColor($r('app.color.ink'))
          .placeholderColor($r('app.color.placeholder')).backgroundColor(Color.Transparent).padding(0)
          .onChange((value: string) => { this.query = value; })
          .onSubmit(() => { void this.loadList(); })
        AppButton({
          label: '搜索', kind: 'text', compact: true,
          disabled: this.loading && this.query === this.requestedQuery,
          onTap: () => { void this.loadList(); }
        })
      }.width('100%').padding({ left: Space.sm, right: 6, top: 4, bottom: 4 })
        .backgroundColor($r('app.color.card')).borderRadius(Radius.card).alignItems(VerticalAlign.Center)

      if (this.loading && this.rows.length > 0) {
        Text('正在读取…').fontSize(FontSize.callout).fontColor($r('app.color.muted')).width('100%')
      }
      if (this.error) { Text(this.error).fontSize(FontSize.callout).fontColor($r('app.color.danger')).width('100%') }
      ForEach(this.errors, (value: string) => {
        Text(value).fontSize(FontSize.caption).fontColor($r('app.color.danger')).width('100%')
      }, (value: string) => value)

      if (this.rows.length > 0 || (this.nextCursor && this.query === this.requestedQuery)) {
        List({ space: 0 }) {
          ForEach(this.rows, (row: PullRequestRow) => {
            ListItem() {
              Column({ space: 4 }) {
                Row({ space: Space.xs }) {
                  Text('#' + row.number).fontSize(FontSize.caption).fontColor($r('app.color.muted')).maxLines(1)
                  Text(row.title).fontSize(FontSize.body).fontWeight(Weight.medium).fontColor($r('app.color.ink'))
                    .layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (row.stackSize > 1) {
                    StatusBadge({ text: row.stackPosition + '/' + row.stackSize, tone: 'neutral' })
                  }
                }.width('100%').alignItems(VerticalAlign.Top)
                Row({ space: Space.xs }) {
                  Text(this.rowSubtitle(row))
                    .fontSize(FontSize.caption).fontColor($r('app.color.muted')).layoutWeight(1).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  StatusBadge({
                    text: pullRequestStateLabel(row.state, row.draft) + (row.checksState ? ' · ' + row.checksState : ''),
                    tone: row.state === 'merged' ? 'info' : row.state === 'open' ? 'success' : 'neutral'
                  })
                }.width('100%').alignItems(VerticalAlign.Center)
                if (row.labels.length) {
                  Text(row.labels.join(' · ')).fontSize(FontSize.badge).fontColor($r('app.color.primary_text')).width('100%')
                }
              }.padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs }).width('100%')
                .constraintSize({ minHeight: Sizes.formRowMin })
                .onClick(() => { void this.open(row); })
            }
          }, (row: PullRequestRow) => (row.localId || '') + ':' + (row.host || row.provider) + ':' + row.projectId + ':' + row.repository + ':' + row.number)
          if (this.nextCursor && this.query === this.requestedQuery) {
            ListItem() {
              Column() {
                AppButton({ label: '加载更多', kind: 'secondary', compact: true, fill: true, onTap: () => { void this.loadMore(); } })
              }.padding(12).width('100%')
            }
          }
        }.width('100%').layoutWeight(1)
          .backgroundColor($r('app.color.card')).borderRadius(Radius.card).clip(true)
          .divider({ strokeWidth: Sizes.hairline, color: $r('app.color.separator') })
          .contentEndOffset(this.embedded && !this.selected ? this.bottomInset : 0)
      } else if (this.loading) {
        GroupCard() {
          Row({ space: Space.xs }) {
            LoadingProgress().width(18).height(18).color($r('app.color.muted'))
            Text('正在读取…').fontSize(FontSize.callout).fontColor($r('app.color.muted'))
          }.width('100%').justifyContent(FlexAlign.Center).padding(Space.lg)
        }
      } else if (!this.error && this.errors.length === 0) {
        GroupCard() {
          Column({ space: Space.xs }) {
            Text('没有符合当前筛选条件的拉取请求').fontSize(FontSize.callout).fontColor($r('app.color.muted'))
              .width('100%').textAlign(TextAlign.Center)
            if (this.emptyHint()) {
              Text(this.emptyHint()).fontSize(FontSize.caption).lineHeight(LineHeight.caption)
                .fontColor($r('app.color.muted')).width('100%').textAlign(TextAlign.Center)
            }
          }.width('100%').padding(Space.lg)
        }
      }
    }.width('100%').layoutWeight(1).padding({ left: Space.sm, right: Space.sm, top: Space.xxs, bottom: Space.sm })
  }

  private checkList(): PullRequestCheckView[] {
    if (this.liveChecks.length) return this.liveChecks;
    if (!this.detail) return [];
    return this.detail.checks.map((check): PullRequestCheckView => ({
      name: check.name, status: check.state, url: check.url, description: check.description
    }));
  }

  private checksState(): string {
    return this.liveChecksState || (this.detail ? this.detail.checksState : '');
  }

  @Builder
  overviewTab() {
    if (this.detail) {
      Scroll() {
        Column({ space: Space.sm }) {
          GroupCard() {
            Column({ space: Space.xs }) {
              Text(this.detail.title).fontSize(FontSize.headline).lineHeight(LineHeight.headline)
                .fontWeight(Weight.semibold).fontColor($r('app.color.ink')).width('100%')
              Text(pullRequestStateLabel(this.detail.state, this.detail.draft) + ' · ' +
                this.detail.headBranch + ' → ' + this.detail.baseBranch + ' · +' + this.detail.additions +
                ' -' + this.detail.deletions + ' · ' + this.detail.changedFiles + ' 文件')
                .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted')).width('100%')
              if (this.detail.labels.length) {
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(this.detail.labels, (label: string) => {
                    Text(label).fontSize(FontSize.badge).fontColor($r('app.color.primary_text'))
                      .padding({ left: 8, right: 8, top: 3, bottom: 3 }).margin({ right: 6, bottom: 4 })
                      .backgroundColor($r('app.color.info_bg')).borderRadius(Radius.badge)
                      .onClick(() => { void this.loadLabels(); })
                  }, (label: string) => label)
                }.width('100%')
              }
              if (this.detail.reviewers.length) {
                Text('评审人：' + this.detail.reviewers.join('、')).fontSize(FontSize.caption).fontColor($r('app.color.muted'))
                  .width('100%').onClick(() => { void this.loadReviewers(); })
              }
            }.width('100%').padding(14).alignItems(HorizontalAlign.Start)
          }

          if (this.detail.body.trim()) {
            GroupCard({ title: '描述' }) {
              Column() {
                MarkdownView({ markdown: this.detail.body, selectable: true, onCopy: this.onCopy,
                  onOpenLink: (url: string) => this.onCopy(url), onOpenImage: (url: string) => this.onCopy(url) })
              }.padding(14).width('100%').alignItems(HorizontalAlign.Start)
            }
          }

          if (this.checkList().length) {
            GroupCard({ title: 'Checks · ' + this.checksState() }) {
              ForEach(this.checkList(), (check: PullRequestCheckView, index: number) => {
                Row({ space: Space.xs }) {
                  StatusBadge({
                    text: check.status,
                    tone: check.status.toLowerCase().includes('pass') || check.status === 'success' ? 'success'
                      : check.status.toLowerCase().includes('fail') || check.status === 'failure' ? 'danger' : 'neutral'
                  })
                  Text(check.name).fontSize(FontSize.callout).fontColor($r('app.color.ink')).layoutWeight(1).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (check.url) {
                    AppButton({ label: '打开', kind: 'text', compact: true, onTap: () => this.onCopy(check.url) })
                  }
                }.width('100%').padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
                  .constraintSize({ minHeight: Sizes.formRowMin }).alignItems(VerticalAlign.Center)
                  .border({ width: { top: index === 0 ? 0 : Sizes.hairline }, color: { top: $r('app.color.separator') } })
              }, (check: PullRequestCheckView, index: number) => check.name + index)
            }
          }

          GroupCard({ title: 'PR 操作' }) {
            Column({ space: Space.xs }) {
              Flex({ wrap: FlexWrap.Wrap }) {
                if (this.detail.draft && this.detail.actions.includes('ready')) {
                  Button('标记就绪').fontSize(FontSize.callout).fontWeight(Weight.medium)
                    .backgroundColor($r('app.color.group')).fontColor($r('app.color.ink')).borderRadius(Radius.button)
                    .constraintSize({ minHeight: 38 }).padding({ left: Space.sm, right: Space.sm }).margin({ right: 6, bottom: 6 })
                    .onClick(() => { void this.runAction('ready'); })
                }
                if (!this.detail.draft && this.detail.actions.includes('draft')) {
                  Button('转草稿').fontSize(FontSize.callout).fontWeight(Weight.medium)
                    .backgroundColor($r('app.color.group')).fontColor($r('app.color.ink')).borderRadius(Radius.button)
                    .constraintSize({ minHeight: 38 }).padding({ left: Space.sm, right: Space.sm }).margin({ right: 6, bottom: 6 })
                    .onClick(() => { void this.runAction('draft'); })
                }
                if (this.detail.actions.includes('close')) {
                  Button('关闭').fontSize(FontSize.callout).fontWeight(Weight.medium)
                    .backgroundColor($r('app.color.danger_bg')).fontColor($r('app.color.danger')).borderRadius(Radius.button)
                    .constraintSize({ minHeight: 38 }).padding({ left: Space.sm, right: Space.sm }).margin({ right: 6, bottom: 6 })
                    .onClick(() => { void this.runAction('close'); })
                }
                if (this.detail.actions.includes('reopen')) {
                  Button('重新打开').fontSize(FontSize.callout).fontWeight(Weight.medium)
                    .backgroundColor($r('app.color.group')).fontColor($r('app.color.ink')).borderRadius(Radius.button)
                    .constraintSize({ minHeight: 38 }).padding({ left: Space.sm, right: Space.sm }).margin({ right: 6, bottom: 6 })
                    .onClick(() => { void this.runAction('reopen'); })
                }
                Button('编辑').fontSize(FontSize.callout).fontWeight(Weight.medium)
                  .backgroundColor($r('app.color.group')).fontColor($r('app.color.ink')).borderRadius(Radius.button)
                  .constraintSize({ minHeight: 38 }).padding({ left: Space.sm, right: Space.sm }).margin({ right: 6, bottom: 6 })
                  .onClick(() => { this.editing = true; })
              }.width('100%')
              if (this.detail.mergeMethods.length && this.detail.actions.includes('merge')) {
                Text('合并方式').fontSize(FontSize.caption).fontColor($r('app.color.muted')).width('100%')
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(this.detail.mergeMethods, (method: string, index: number) => {
                    Button(method)
                      .fontSize(FontSize.callout).fontWeight(index === 0 ? Weight.semibold : Weight.medium)
                      .backgroundColor(index === 0 ? $r('app.color.prominent') : $r('app.color.group'))
                      .fontColor(index === 0 ? $r('app.color.on_prominent') : $r('app.color.ink'))
                      .borderRadius(Radius.button).constraintSize({ minHeight: 38 })
                      .padding({ left: Space.sm, right: Space.sm }).margin({ right: 6, bottom: 6 })
                      .enabled(this.detail?.mergeable === 'mergeable' && !this.busy)
                      .onClick(() => {
                        AlertDialog.show({ title: '合并 PR？', message: '方式：' + method,
                          primaryButton: { value: '取消', action: () => {} },
                          secondaryButton: { value: '合并', action: () => { void this.runAction('merge', method); } } });
                      })
                  }, (method: string) => method)
                }.width('100%')
              }
            }.padding(14).width('100%').alignItems(HorizontalAlign.Start)
          }

          if (this.editing) {
            GroupCard({ title: '编辑标题与描述' }) {
              Column({ space: Space.xs }) {
                TextInput({ text: this.editTitle }).height(40).width('100%').fontSize(FontSize.body).fontColor($r('app.color.ink'))
                  .backgroundColor($r('app.color.group')).borderRadius(Radius.tool).padding({ left: 10, right: 10 })
                  .onChange((value: string) => { this.editTitle = value; })
                TextArea({ text: this.editBody }).constraintSize({ minHeight: 110 }).width('100%').fontSize(FontSize.body)
                  .fontColor($r('app.color.ink')).backgroundColor($r('app.color.group')).borderRadius(Radius.tool).padding(Space.xs)
                  .onChange((value: string) => { this.editBody = value; })
                Row({ space: Space.xs }) {
                  AppButton({ label: '取消', kind: 'secondary', compact: true, onTap: () => { this.editing = false; } })
                  AppButton({ label: '保存', kind: 'primary', compact: true, disabled: this.busy, onTap: () => { void this.saveEdit(); } })
                }.width('100%')
              }.width('100%').padding(14)
            }
          }
          if (this.error) { Text(this.error).fontSize(FontSize.callout).fontColor($r('app.color.danger')).width('100%') }
          if (this.notice) { Text(this.notice).fontSize(FontSize.callout).fontColor($r('app.color.primary_text')).width('100%') }
        }.width('100%').padding({ left: Space.sm, right: Space.sm, bottom: Space.lg }).alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1)
    }
  }

  @Builder
  filesTab() {
    if (this.selectedFile) {
      Column({ space: Space.xs }) {
        Row({ space: Space.xs }) {
          AppButton({
            label: '‹ 文件列表', kind: 'text', compact: true,
            a11yLabel: '返回文件列表',
            onTap: () => { this.selectedFile = ''; this.lineStart = -1; this.lineEnd = -1; }
          })
          Text(this.drafts.length + ' 条审阅草稿').fontSize(FontSize.caption).fontColor($r('app.color.muted'))
            .layoutWeight(1).textAlign(TextAlign.End)
        }.width('100%').padding({ left: Space.xs, right: Space.sm })
        List({ space: Space.xs }) {
          ListItem() {
            Text(this.selectedFile).fontSize(FontSize.body).fontWeight(Weight.medium).fontColor($r('app.color.ink'))
              .wordBreak(WordBreak.BREAK_ALL).width('100%').padding({ left: 12, right: 12, top: Space.xs, bottom: Space.xs })
              .backgroundColor($r('app.color.card')).borderRadius(Radius.card)
          }
          ForEach(this.currentFileHunks(), (hunk: DiffHunk) => {
            ListItem() {
              Column({ space: 0 }) {
                Text(hunk.header).fontSize(Math.max(8, this.codeFontSize - 2)).fontFamily('monospace').fontColor($r('app.color.muted'))
                  .width('100%').padding({ left: 10, right: 10, top: 6, bottom: 6 }).backgroundColor($r('app.color.group'))
                ForEach(hunk.rows, (row: DiffRow, index: number) => {
                  Row({ space: 0 }) {
                    if (hunk.lastOldLine) {
                      DiffLineNumber({ line: row.oldLine, lastLine: hunk.lastOldLine })
                    }
                    if (hunk.lastNewLine) {
                      DiffLineNumber({ line: row.newLine, lastLine: hunk.lastNewLine })
                    }
                    Text(row.kind === 'add' ? '+' : row.kind === 'del' ? '-' : ' ')
                      .fontSize(this.codeFontSize).fontFamily('monospace').width((this.codeFontSize + 2) + 'fp')
                      .lineHeight((this.codeFontSize + 9) + 'fp')
                    CodeLine({ text: row.text, color: row.kind === 'add' ? $r('app.color.diff_add_ink') :
                      row.kind === 'del' ? $r('app.color.diff_del_ink') : $r('app.color.ink') }).layoutWeight(1)
                  }.width('100%').constraintSize({ minHeight: (this.codeFontSize + 9) + 'fp' })
                    .alignItems(VerticalAlign.Top)
                    .backgroundColor(this.selectedHunk === hunk.header && this.lineStart >= 0 &&
                      index >= Math.min(this.lineStart, this.lineEnd) && index <= Math.max(this.lineStart, this.lineEnd) ?
                      $r('app.color.info_bg') : row.kind === 'add' ? $r('app.color.diff_add') :
                      row.kind === 'del' ? $r('app.color.diff_del') : Color.Transparent)
                    .onClick(() => {
                      if (this.selectedHunk !== hunk.header) { this.selectedHunk = hunk.header; this.lineStart = index; this.lineEnd = index; }
                      else { this.lineStart = index; this.lineEnd = index; }
                    })
                }, (row: DiffRow, index: number) => hunk.header + ':' + index)
              }.width('100%').backgroundColor($r('app.color.card')).borderRadius(Radius.card).clip(true)
            }
          }, (hunk: DiffHunk) => this.selectedFile + ':' + hunk.header)
        }.width('100%').layoutWeight(1)
        if (this.lineStart >= 0) {
          Row({ space: Space.xs }) {
            Text('行 ' + (this.lineStart + 1)).fontSize(FontSize.caption).fontColor($r('app.color.muted')).layoutWeight(1)
            AppButton({ label: '行评论', kind: 'primary', compact: true, onTap: () => { this.commenting = true; } })
          }.width('100%').padding({ left: 12, right: 12, top: Space.xs, bottom: Space.xs })
            .backgroundColor($r('app.color.card')).borderRadius(Radius.card).alignItems(VerticalAlign.Center)
        }
        if (this.commenting) {
          GroupCard({ title: '行内评论' }) {
            Column({ space: Space.xs }) {
              TextArea({ placeholder: '行内评论', text: this.lineComment }).constraintSize({ minHeight: 80 }).width('100%')
                .fontSize(FontSize.body).fontColor($r('app.color.ink')).backgroundColor($r('app.color.group'))
                .borderRadius(Radius.tool).padding(Space.xs).onChange((value: string) => { this.lineComment = value; })
              Row({ space: Space.xs }) {
                AppButton({ label: '取消', kind: 'secondary', compact: true, onTap: () => { this.commenting = false; } })
                AppButton({
                  label: '加入草稿', kind: 'primary', compact: true, disabled: !this.lineComment.trim(),
                  onTap: () => {
                    const hunk = this.currentFileHunks().find((item: DiffHunk) => item.header === this.selectedHunk);
                    if (hunk) this.addLineDraft(hunk);
                  }
                })
              }.width('100%')
            }.width('100%').padding(12)
          }
        }
        if (this.error) { Text(this.error).fontSize(FontSize.callout).fontColor($r('app.color.danger')).width('100%') }
        if (this.notice) { Text(this.notice).fontSize(FontSize.callout).fontColor($r('app.color.primary_text')).width('100%') }
      }.width('100%').layoutWeight(1).padding({ left: Space.sm, right: Space.sm, bottom: Space.sm })
    } else {
      Column() {
        List({ space: 0 }) {
          ForEach(this.patchFiles, (file: DiffFile) => {
            ListItem() {
              Row({ space: Space.xs }) {
                Column({ space: 3 }) {
                  Text(file.path.slice(file.path.lastIndexOf('/') + 1)).fontSize(FontSize.body).fontWeight(Weight.medium)
                    .fontColor($r('app.color.ink')).width('100%').wordBreak(WordBreak.BREAK_ALL)
                  if (file.path.includes('/')) {
                    Text(file.path.slice(0, file.path.lastIndexOf('/'))).fontSize(FontSize.caption).fontColor($r('app.color.muted'))
                      .width('100%').wordBreak(WordBreak.BREAK_ALL).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Text('+' + file.additions).fontSize(FontSize.badge).fontColor($r('app.color.diff_add_ink'))
                Text('-' + file.deletions).fontSize(FontSize.badge).fontColor($r('app.color.diff_del_ink'))
              }.constraintSize({ minHeight: Sizes.formRowMin }).padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs }).width('100%')
                .accessibilityText(file.path + '，新增 ' + file.additions + ' 行，删除 ' + file.deletions + ' 行')
                .onClick(() => { this.selectedFile = file.path; this.selectedHunk = ''; })
            }
          }, (file: DiffFile) => file.path)
          if (!this.patchFiles.length) {
            ListItem() {
              Text(this.diffError || (this.loading ? '正在读取文件差异…' : '没有可显示的文件差异')).fontSize(FontSize.callout)
                .fontColor(this.diffError ? $r('app.color.danger') : $r('app.color.muted')).width('100%')
                .textAlign(TextAlign.Center).padding(Space.lg)
            }
          }
        }.width('100%').layoutWeight(1)
          .backgroundColor($r('app.color.card')).borderRadius(Radius.card).clip(true)
          .divider({ strokeWidth: Sizes.hairline, color: $r('app.color.separator') })
      }.width('100%').layoutWeight(1).padding({ left: Space.sm, right: Space.sm, bottom: Space.sm })
    }
  }

  private currentFileHunks(): DiffHunk[] {
    const file = this.patchFiles.find((item: DiffFile) => item.path === this.selectedFile);
    return file ? file.hunks : [];
  }

  @Builder
  discussionTab() {
    Scroll() {
      Column({ space: Space.sm }) {
        if (this.activityError) {
          Text('讨论读取失败：' + this.activityError).fontSize(FontSize.callout).fontColor($r('app.color.danger')).width('100%')
        }
        if (this.activity) {
          ForEach(this.activity.comments,
            (comment: PullRequestCommentView) => {
              GroupCard() {
                Column({ space: Space.xs }) {
                  Text(comment.author + ' · ' + comment.createdAt)
                    .fontSize(FontSize.caption).fontColor($r('app.color.muted')).width('100%')
                  MarkdownView({ markdown: comment.body, selectable: true, onCopy: this.onCopy,
                    onOpenLink: (url: string) => this.onCopy(url), onOpenImage: (url: string) => this.onCopy(url) })
                  Row({ space: Space.xs }) {
                    ForEach([['thumbs-up', '👍'], ['heart', '❤️'], ['laugh', '😄']], (entry: string[]) => {
                      Button(entry[1]).fontSize(FontSize.callout).backgroundColor($r('app.color.group'))
                        .borderRadius(Radius.badge).constraintSize({ minHeight: 32 }).padding({ left: 10, right: 10 })
                        .onClick(() => { void this.react(comment.id, entry[0]); })
                    }, (entry: string[]) => entry[0])
                  }.width('100%')
                }.width('100%').padding(14).alignItems(HorizontalAlign.Start)
              }
            }, (comment: PullRequestCommentView) => comment.id)
          ForEach(this.activity.threads,
            (thread: PullRequestThreadView) => {
              GroupCard() {
                Column({ space: Space.xs }) {
                  Row({ space: Space.xs }) {
                    Text(thread.path).fontSize(FontSize.caption).fontColor($r('app.color.primary_text'))
                      .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    StatusBadge({ text: thread.resolved ? '已解决' : '待处理', tone: thread.resolved ? 'success' : 'warning' })
                  }.width('100%').alignItems(VerticalAlign.Center)
                  ForEach(thread.comments, (comment: PullRequestThreadCommentView) => {
                    Text(comment.author + ': ' + comment.body).fontSize(FontSize.callout).fontColor($r('app.color.ink')).width('100%')
                  }, (comment: PullRequestThreadCommentView) => comment.id)
                  if (this.replyThread === thread.id) {
                    TextArea({ placeholder: '回复讨论', text: this.replyBody }).constraintSize({ minHeight: 68 }).width('100%')
                      .fontSize(FontSize.body).fontColor($r('app.color.ink')).backgroundColor($r('app.color.group'))
                      .borderRadius(Radius.tool).padding(Space.xs).onChange((value: string) => { this.replyBody = value; })
                    Row({ space: Space.xs }) {
                      AppButton({ label: '取消', kind: 'secondary', compact: true, onTap: () => { this.replyThread = ''; this.replyBody = ''; } })
                      AppButton({ label: '回复', kind: 'primary', compact: true, disabled: !this.replyBody.trim(), onTap: () => { void this.reply(thread.id); } })
                    }.width('100%')
                  } else {
                    Row({ space: Space.xs }) {
                      AppButton({ label: '回复', kind: 'secondary', compact: true, onTap: () => { this.replyThread = thread.id; } })
                      AppButton({
                        label: thread.resolved ? '重新打开讨论' : '标记已解决',
                        kind: 'secondary', compact: true, disabled: this.busy,
                        onTap: () => { void this.resolveThread(thread.id, !thread.resolved); }
                      })
                    }.width('100%')
                  }
                }.width('100%').padding(14).alignItems(HorizontalAlign.Start)
              }
            }, (thread: PullRequestThreadView) => thread.id)
        } else {
          GroupCard() {
            Text(this.activityError ? '讨论读取失败：' + this.activityError : '讨论暂不可读')
              .fontSize(FontSize.callout).fontColor($r('app.color.muted')).width('100%').padding(14)
          }
        }
        if (this.detail && this.detail.comment) {
          GroupCard({ title: '添加讨论评论' }) {
            Column({ space: Space.xs }) {
              TextArea({ placeholder: '添加讨论评论', text: this.commentBody }).constraintSize({ minHeight: 80 }).width('100%')
                .fontSize(FontSize.body).fontColor($r('app.color.ink')).backgroundColor($r('app.color.group'))
                .borderRadius(Radius.tool).padding(Space.xs).onChange((value: string) => { this.commentBody = value; })
              AppButton({
                label: '提交评论', kind: 'primary', compact: true, fill: true,
                disabled: !this.commentBody.trim() || this.busy,
                onTap: () => { void this.submitComment(); }
              })
            }.width('100%').padding(14)
          }
        }
        if (this.error) { Text(this.error).fontSize(FontSize.callout).fontColor($r('app.color.danger')).width('100%') }
        if (this.notice) { Text(this.notice).fontSize(FontSize.callout).fontColor($r('app.color.primary_text')).width('100%') }
      }.width('100%').padding({ left: Space.sm, right: Space.sm, bottom: Space.lg }).alignItems(HorizontalAlign.Start)
    }.width('100%').layoutWeight(1)
  }

  @Builder
  reviewTab() {
    if (this.detail) {
      Scroll() {
        Column({ space: Space.sm }) {
          GroupCard({ title: '提交评审' }) {
            Column({ space: Space.xs }) {
              Text('行内草稿 ' + this.drafts.length + ' 条').fontSize(FontSize.caption).fontColor($r('app.color.muted')).width('100%')
              TextArea({ placeholder: '审阅说明（可留空）', text: this.reviewBody }).constraintSize({ minHeight: 100 }).width('100%')
                .fontSize(FontSize.body).fontColor($r('app.color.ink')).backgroundColor($r('app.color.group'))
                .borderRadius(Radius.tool).padding(Space.xs).onChange((value: string) => { this.reviewBody = value; })
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.detail.reviewVerdicts, (verdict: string) => {
                  Button(verdict === 'approve' ? '批准' : verdict === 'request-changes' ? '请求修改' : '评论')
                    .fontSize(FontSize.callout).fontWeight(Weight.medium)
                    .backgroundColor(verdict === 'approve' ? $r('app.color.prominent') : $r('app.color.group'))
                    .fontColor(verdict === 'approve' ? $r('app.color.on_prominent') : $r('app.color.ink'))
                    .borderRadius(Radius.button).constraintSize({ minHeight: 38 })
                    .padding({ left: Space.sm, right: Space.sm }).margin({ right: 6, bottom: 6 })
                    .enabled(!this.busy).onClick(() => { void this.submitReview(verdict); })
                }, (verdict: string) => verdict)
              }.width('100%')
            }.width('100%').padding(14).alignItems(HorizontalAlign.Start)
          }

          GroupCard({ title: '标签与评审人', footnote: '行内评论在“文件”页选择行后加入草稿，再在此提交。' }) {
            Row({ space: Space.xs }) {
              Column() {
                AppButton({ label: '打开标签', kind: 'secondary', compact: true, fill: true, onTap: () => { void this.loadLabels(); } })
              }.layoutWeight(1)
              Column() {
                AppButton({ label: '请求评审人', kind: 'secondary', compact: true, fill: true, onTap: () => { void this.loadReviewers(); } })
              }.layoutWeight(1)
            }.width('100%').padding(12)
            if (this.panelMode === 'labels') {
              Column({ space: 0 }) {
                ForEach(this.candidates, (candidate: Object) => {
                  Row({ space: Space.xs }) {
                    Text(String(record(candidate).name)).fontSize(FontSize.body).fontColor($r('app.color.ink')).layoutWeight(1)
                    Text(record(candidate).applied === true ? '✓ 已添加' : '添加').fontSize(FontSize.callout)
                      .fontColor(record(candidate).applied === true ? $r('app.color.primary_text') : $r('app.color.muted'))
                  }.constraintSize({ minHeight: Sizes.formRowMin }).padding({ left: 14, right: 14 }).width('100%')
                    .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
                    .onClick(() => {
                      void this.toggleLabel(String(record(candidate).name), record(candidate).applied === true);
                    })
                }, (candidate: Object) => String(record(candidate).name))
              }.width('100%')
            }
            if (this.panelMode === 'reviewers') {
              Column({ space: 0 }) {
                ForEach(this.reviewerCandidates, (candidate: Object) => {
                  Row({ space: Space.xs }) {
                    Text(String(record(candidate).name)).fontSize(FontSize.body).fontColor($r('app.color.ink')).layoutWeight(1)
                    Text(record(candidate).requested === true ? '✓ 已请求' : '请求').fontSize(FontSize.callout)
                      .fontColor(record(candidate).requested === true ? $r('app.color.primary_text') : $r('app.color.muted'))
                  }.constraintSize({ minHeight: Sizes.formRowMin }).padding({ left: 14, right: 14 }).width('100%')
                    .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
                    .onClick(() => {
                      void this.toggleReviewer(String(record(candidate).id), String(record(candidate).kind),
                        record(candidate).requested === true);
                    })
                }, (candidate: Object) => String(record(candidate).id))
              }.width('100%')
            }
          }
          if (this.error) { Text(this.error).fontSize(FontSize.callout).fontColor($r('app.color.danger')).width('100%') }
          if (this.notice) { Text(this.notice).fontSize(FontSize.callout).fontColor($r('app.color.primary_text')).width('100%') }
        }.width('100%').padding({ left: Space.sm, right: Space.sm, bottom: Space.lg }).alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1)
    }
  }

  @Builder
  guideTab() {
    Column({ space: Space.xs }) {
      GroupCard() {
        Row({ space: Space.xs }) {
          Text(this.guideBusy && !this.guide ? '正在加载评审向导…' :
            this.guide === undefined || (this.guide.headSha === '' && this.guide.stops.length === 0) ?
              '还没有保存的评审向导' :
            this.guide.running ? 'Agent 正在生成评审向导…' :
            this.guide.stale ? '有新提交，向导可能已过期' :
            this.guide.runDetail ? '上次生成失败：' + this.guide.runDetail :
            '向导基于 ' + this.guide.headSha.slice(0, 8))
            .fontSize(FontSize.callout).fontColor($r('app.color.muted')).layoutWeight(1)
          AppButton({ label: '刷新', kind: 'secondary', compact: true, disabled: this.guideBusy, onTap: () => { void this.loadGuide(); } })
          AppButton({ label: this.guide && this.guide.stops.length > 0 ? '重新生成' : '生成', kind: 'primary', compact: true, disabled: this.guideBusy, onTap: () => { void this.generateGuide(); } })
        }.width('100%').padding(12).alignItems(VerticalAlign.Center)
      }
      if (this.guideError) { Text(this.guideError).fontSize(FontSize.callout).fontColor($r('app.color.danger')).width('100%') }
      if (this.guide && this.guide.stops.length > 0) {
        List({ space: Space.xs }) {
          ForEach(this.guide.stops, (stop: ReviewGuideStop, index: number) => {
            ListItem() {
              Column({ space: 4 }) {
                Text((index + 1) + '. ' + stop.title).fontSize(FontSize.body).fontWeight(Weight.semibold).fontColor($r('app.color.ink')).width('100%')
                if (stop.summary) { Text(stop.summary).fontSize(FontSize.callout).fontColor($r('app.color.muted')).width('100%') }
                if (stop.attentionNote) {
                  Text(stop.attentionKind + '：' + stop.attentionNote).fontSize(FontSize.callout)
                    .fontColor($r('app.color.danger')).width('100%')
                }
                ForEach(stop.files, (file: ReviewGuideFile) => {
                  Text('文件 ' + file.path + (file.note ? ' · ' + file.note : ''))
                    .fontSize(FontSize.caption).fontColor($r('app.color.ink')).width('100%')
                }, (file: ReviewGuideFile) => file.path)
                ForEach(stop.excerpts, (excerpt: ReviewGuideExcerpt) => {
                  Text('摘录 ' + excerpt.path + ':' + excerpt.start + '–' + excerpt.end + ' (' + excerpt.side + ')' +
                    (excerpt.caption ? ' · ' + excerpt.caption : ''))
                    .fontSize(FontSize.caption).fontColor($r('app.color.muted')).width('100%')
                }, (excerpt: ReviewGuideExcerpt, index: number) =>
                  excerpt.path + ':' + excerpt.start + ':' + index)
                ForEach(stop.notes, (note: ReviewGuideNote) => {
                  Column({ space: 2 }) {
                    Text(note.title + ' · ' + note.path + ':' + note.line).fontSize(FontSize.callout).fontColor($r('app.color.ink')).width('100%')
                    if (note.body) { Text(note.body).fontSize(FontSize.caption).fontColor($r('app.color.muted')).width('100%') }
                  }.width('100%')
                }, (note: ReviewGuideNote, index: number) =>
                  note.path + ':' + note.line + ':' + index)
                ForEach(stop.questions, (question: string, index: number) => {
                  Text('？ ' + question).fontSize(FontSize.caption).fontColor($r('app.color.primary_text')).width('100%')
                }, (question: string, index: number) => index + ':' + question)
              }.width('100%').padding(14).backgroundColor($r('app.color.card')).borderRadius(Radius.card)
            }
          }, (stop: ReviewGuideStop, index: number) => index + ':' + stop.title)
        }.width('100%').layoutWeight(1)
      } else if (!this.guideBusy) {
        GroupCard() {
          Text('评审向导会由 Agent 读取这次改动，给出阅读顺序、代码摘录和需要重点关注的问题。')
            .fontSize(FontSize.callout).fontColor($r('app.color.muted')).width('100%').padding(14)
        }
      }
    }.width('100%').layoutWeight(1).padding({ left: Space.sm, right: Space.sm, bottom: Space.sm })
  }

  @Builder
  detailView() {
    Column({ space: Space.xs }) {
      Row({ space: Space.xxs }) {
        ForEach([['overview', '概览'], ['files', '文件'], ['discussion', '讨论'], ['review', '评审'], ['guide', '向导']],
          (entry: string[]) => {
            Button(entry[1], { type: ButtonType.Normal })
              .fontSize(FontSize.caption)
              .fontWeight(this.tab === entry[0] ? Weight.semibold : Weight.medium)
              .layoutWeight(1).constraintSize({ minHeight: 34 })
              .backgroundColor(this.tab === entry[0] ? $r('app.color.info_bg') : $r('app.color.card'))
              .fontColor(this.tab === entry[0] ? $r('app.color.primary_text') : $r('app.color.ink'))
              .border({ width: Sizes.hairline, color: this.tab === entry[0] ? $r('app.color.primary') : Color.Transparent, radius: Radius.tool })
              .borderRadius(Radius.tool)
              .onClick(() => { this.tab = entry[0]; })
          }, (entry: string[]) => entry[0])
      }.width('100%').padding({ left: Space.sm, right: Space.sm })
      if (this.loading) { Text('正在读取 PR…').fontSize(FontSize.callout).fontColor($r('app.color.muted')).padding({ left: Space.md, right: Space.md }) }
      if (this.tab === 'overview') { this.overviewTab() }
      else if (this.tab === 'files') { this.filesTab() }
      else if (this.tab === 'discussion') { this.discussionTab() }
      else if (this.tab === 'guide') { this.guideTab() }
      else { this.reviewTab() }
    }.width('100%').layoutWeight(1)
  }

  build() {
    Column({ space: 0 }) {
      this.header()
      if (this.selected) { this.detailView() } else { this.listView() }
    }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
      .bindSheet($$this.filterSheetOpen, this.scopeFilterSheet(), {
        height: '66%',
        showClose: false,
        backgroundColor: $r('app.color.group')
      })
  }
}
