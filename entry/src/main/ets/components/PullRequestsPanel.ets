import { T3Client } from '../services/T3Client';
import { CodeLine } from './CodeLine';
import { DiffLineNumber } from './DiffLineNumber';
import { DiffFile, DiffHunk, DiffRow, LabelCandidateView, parseDiff, PullRequestDetailView,
  PullRequestGuideView, pullRequestPatch, pullRequestRef, PullRequestRow, pullRequestStateLabel, ReviewerCandidateView,
  reviewCommentDraft, ReviewGuideExcerpt, ReviewGuideFile, ReviewGuideNote, ReviewGuideStop,
  PullRequestActivityView, PullRequestCommentView, PullRequestThreadCommentView, PullRequestThreadView,
  PullRequestCheckView } from '../protocol/R5';
import { record, text } from '../protocol/Wire';
import { MarkdownView } from './MarkdownView';

@Component
export struct PullRequestsPanel {
  @StorageProp('t3CodeFontSize') codeFontSize: number = 13;
  connection: T3Client | undefined = undefined;
  @Prop projectId: string = '';
  @Prop projectLabel: string = '';
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
  @State selected: PullRequestRow | undefined = undefined;
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

  aboutToAppear(): void { this.alive = true; void this.loadList(); }
  aboutToDisappear(): void {
    this.alive = false;
    this.readRevision++;
    this.finishDetailRead();
  }

  private finishDetailRead(): void {
    if (this.readingDetail) this.busy = false;
    this.readingDetail = false;
    this.loading = false;
  }
  private readCurrent(connection: T3Client, generation: number, revision: number, projectId: string): boolean {
    return this.alive && this.readRevision === revision && this.connection === connection &&
      connection.generationValue() === generation && this.projectId === projectId;
  }

  private ref(): Object {
    const row = this.selected;
    if (!row) throw new Error('未选择 PR');
    return pullRequestRef(row.projectId || this.projectId, row.repository, row.number);
  }

  private async loadList(): Promise<void> {
    await this.readListPage(false);
  }

  private async loadMore(): Promise<void> {
    if (this.loading || !this.nextCursor || this.query !== this.requestedQuery) return;
    await this.readListPage(true);
  }

  private async readListPage(append: boolean): Promise<void> {
    const connection = this.connection;
    if (!this.alive || !connection || this.selected) return;
    const revision = ++this.readRevision;
    const generation = connection.generationValue();
    const projectId = this.projectId;
    const filter = this.filter;
    const query = this.query;
    this.requestedQuery = query;
    const cursor = append ? this.nextCursor : '';
    const current = (): boolean => this.readCurrent(connection, generation, revision, projectId) &&
      !this.selected && this.filter === filter && this.query === query;
    this.loading = true;
    if (!append) { this.error = ''; this.errors = []; this.rows = []; this.nextCursor = ''; }
    try {
      const page = await connection.listPullRequests(filter, query, cursor, projectId);
      if (!current()) return;
      this.rows = append ? this.rows.concat(page.rows) : page.rows;
      this.nextCursor = page.nextCursor;
      this.errors = append ? this.errors.concat(page.errors) : page.errors;
    } catch (reason) {
      if (current()) this.error = (reason as Error).message;
    } finally { if (this.readRevision === revision) this.loading = false; }
  }

  private async open(row: PullRequestRow): Promise<void> {
    const connection = this.connection;
    if (!this.alive || !connection || (this.busy && !this.readingDetail)) return;
    const revision = ++this.readRevision;
    const generation = connection.generationValue();
    const projectId = this.projectId;
    const rowProjectId = row.projectId || projectId;
    const repository = row.repository;
    const number = row.number;
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
      const ref = pullRequestRef(rowProjectId, repository, number);
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
      if (current()) { this.error = (reason as Error).message; this.selected = undefined; }
    } finally { if (this.readRevision === revision) this.finishDetailRead(); }
  }

  private closeDetail(): void {
    this.readRevision++;
    this.finishDetailRead();
    this.selected = undefined; this.detail = undefined; this.activity = undefined;
    this.patchFiles = []; this.panelMode = ''; this.notice = ''; this.error = '';
    this.guide = undefined; this.guideError = ''; this.guideBusy = false;
    this.liveChecks = []; this.liveChecksState = '';
    void this.loadList();
  }

  private async loadGuide(): Promise<void> {
    const connection = this.connection;
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
    const connection = this.connection;
    if (!connection || this.guideBusy) return;
    this.guideBusy = true; this.guideError = ''; this.notice = '正在请求 Agent 生成评审向导…';
    try {
      this.guide = await connection.generatePullRequestReviewGuide(this.ref());
      this.notice = '';
    } catch (reason) { this.guideError = (reason as Error).message; }
    finally { this.guideBusy = false; }
  }

  private async runAction(action: string, mergeMethod: string = ''): Promise<void> {
    const connection = this.connection;
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
    const connection = this.connection;
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
    const connection = this.connection;
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
    const connection = this.connection;
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
    const connection = this.connection;
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
    const connection = this.connection;
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
    const connection = this.connection;
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
    const connection = this.connection;
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
    const connection = this.connection;
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
    const connection = this.connection;
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
    const connection = this.connection;
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

  @Builder
  header() {
    Row({ space: 6 }) {
      Button('‹').backgroundColor(Color.Transparent).fontColor($r('app.color.ink')).fontSize(24)
        .width(40).height(40).onClick(() => {
          if (this.selected) { this.closeDetail(); return; }
          this.onBack();
        })
      Column({ space: 2 }) {
        Text(this.detail ? '#' + this.detail.number : this.selected ? '#' + this.selected.number : '拉取请求')
          .fontSize(17).fontWeight(FontWeight.Medium).width('100%').maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.detail?.repository || this.selected?.repository || this.projectLabel || (this.projectId ? '当前项目' : '所有项目')).fontSize(11)
          .fontColor($r('app.color.muted')).width('100%')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (this.selected) {
        Button('刷新').fontSize(12).backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
          .onClick(() => { if (this.selected) void this.open(this.selected); })
      }
    }.width('100%').padding({ left: 8, right: 8, top: 4, bottom: 4 })
  }

  @Builder
  listView() {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        ForEach(['open', 'closed', 'merged', 'all'], (state: string) => {
          Button(state === 'open' ? '开放' : state === 'closed' ? '关闭' : state === 'merged' ? '合并' : '全部')
            .fontSize(11)
            .backgroundColor(this.filter === state ? $r('app.color.primary') : $r('app.color.surface'))
            .fontColor(this.filter === state ? $r('app.color.on_primary') : $r('app.color.ink'))
            .onClick(() => { this.filter = state; void this.loadList(); })
        }, (state: string) => state)
      }.width('100%')
      Row({ space: 8 }) {
        TextInput({ placeholder: '搜索 PR', text: this.query }).layoutWeight(1).constraintSize({ minHeight: 44 })
          .onChange((value: string) => { this.query = value; })
          .onSubmit(() => { void this.loadList(); })
        Button('搜索').constraintSize({ minHeight: 44 }).fontSize(14)
          .backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink'))
          .enabled(!this.loading || this.query !== this.requestedQuery).onClick(() => { void this.loadList(); })
      }.width('100%')
      if (this.loading) { Text('正在读取…').fontSize(12).fontColor($r('app.color.muted')).width('100%') }
      if (this.error) { Text(this.error).fontSize(12).fontColor($r('app.color.danger')).width('100%') }
      ForEach(this.errors, (value: string) => {
        Text(value).fontSize(11).fontColor($r('app.color.danger')).width('100%')
      }, (value: string) => value)
      if (!this.loading && !this.error && this.rows.length === 0 && this.errors.length === 0) {
        Text('没有符合当前筛选条件的拉取请求').fontSize(12).fontColor($r('app.color.muted'))
          .width('100%').padding(12)
      }
      List({ space: 1 }) {
        ForEach(this.rows, (row: PullRequestRow) => {
          ListItem() {
            Column({ space: 3 }) {
              Row({ space: 6 }) {
                Text('#' + row.number).fontSize(11).fontColor($r('app.color.muted')).maxLines(1)
                Text(row.title).fontSize(14).layoutWeight(1).maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (row.stackSize > 1) {
                  Text(row.stackPosition + '/' + row.stackSize).fontSize(10).fontColor($r('app.color.muted'))
                }
              }.width('100%')
              Text(row.repository + ' · ' + row.author + ' · ' + pullRequestStateLabel(row.state, row.draft) +
                (row.checksState ? ' · ' + row.checksState : '')).fontSize(10).fontColor($r('app.color.muted'))
                .width('100%').maxLines(1)
              if (row.labels.length) {
                Text(row.labels.join(' · ')).fontSize(10).fontColor($r('app.color.primary')).width('100%')
              }
            }.padding({ left: 10, right: 10, top: 10, bottom: 10 }).width('100%')
              .onClick(() => { void this.open(row); })
          }
        }, (row: PullRequestRow) => row.provider + ':' + row.projectId + ':' + row.repository + ':' + row.number)
        if (this.nextCursor && this.query === this.requestedQuery) {
          ListItem() {
            Button('加载更多').fontSize(12).onClick(() => { void this.loadMore(); })
          }
        }
      }.width('100%').layoutWeight(1)
    }.width('100%').layoutWeight(1).padding(10)
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
        Column({ space: 10 }) {
          Text(this.detail.title).fontSize(19).fontWeight(FontWeight.Medium).width('100%')
          Text(pullRequestStateLabel(this.detail.state, this.detail.draft) + ' · ' +
            this.detail.headBranch + ' → ' + this.detail.baseBranch + ' · +' + this.detail.additions +
            ' -' + this.detail.deletions + ' · ' + this.detail.changedFiles + ' 文件')
            .fontSize(11).fontColor($r('app.color.muted')).width('100%')
          if (this.detail.body.trim()) {
            MarkdownView({ markdown: this.detail.body, selectable: true, onCopy: this.onCopy,
              onOpenLink: (url: string) => this.onCopy(url), onOpenImage: (url: string) => this.onCopy(url) })
          }
          if (this.detail.labels.length) {
            Row({ space: 6 }) {
              ForEach(this.detail.labels, (label: string) => {
                Text(label).fontSize(10).padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .backgroundColor($r('app.color.surface')).borderRadius(8)
                  .onClick(() => { void this.loadLabels(); })
              }, (label: string) => label)
            }.width('100%')
          }
          if (this.detail.reviewers.length) {
            Text('评审人：' + this.detail.reviewers.join('、')).fontSize(11).fontColor($r('app.color.muted'))
              .width('100%').onClick(() => { void this.loadReviewers(); })
          }
          if (this.checkList().length) {
            Column({ space: 4 }) {
              Text('Checks · ' + this.checksState()).fontSize(12).fontWeight(FontWeight.Medium).width('100%')
              ForEach(this.checkList(), (check: PullRequestCheckView) => {
                Row({ space: 6 }) {
                  Text(check.status).fontSize(10).fontColor($r('app.color.muted')).width(78)
                  Text(check.name).fontSize(12).layoutWeight(1).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (check.url) {
                    Button('打开').fontSize(10).backgroundColor(Color.Transparent).fontColor($r('app.color.primary'))
                      .onClick(() => this.onCopy(check.url))
                  }
                }.width('100%')
              }, (check: PullRequestCheckView, index: number) => check.name + index)
            }.width('100%').padding(10).backgroundColor($r('app.color.surface')).borderRadius(8)
          }
          Row({ space: 8 }) {
            if (this.detail.draft && this.detail.actions.includes('ready')) {
              Button('标记就绪').fontSize(12).onClick(() => { void this.runAction('ready'); })
            }
            if (!this.detail.draft && this.detail.actions.includes('draft')) {
              Button('转草稿').fontSize(12).onClick(() => { void this.runAction('draft'); })
            }
            if (this.detail.actions.includes('close')) {
              Button('关闭').fontSize(12).onClick(() => { void this.runAction('close'); })
            }
            if (this.detail.actions.includes('reopen')) {
              Button('重新打开').fontSize(12).onClick(() => { void this.runAction('reopen'); })
            }
            Button('编辑').fontSize(12).onClick(() => { this.editing = true; })
          }.width('100%')
          if (this.detail.mergeMethods.length && this.detail.actions.includes('merge')) {
            Text('合并方式').fontSize(12).fontColor($r('app.color.muted')).width('100%')
            Row({ space: 8 }) {
              ForEach(this.detail.mergeMethods, (method: string) => {
                Button(method).fontSize(11).enabled(this.detail?.mergeable === 'mergeable' && !this.busy)
                  .onClick(() => {
                    AlertDialog.show({ title: '合并 PR？', message: '方式：' + method,
                      primaryButton: { value: '取消', action: () => {} },
                      secondaryButton: { value: '合并', action: () => { void this.runAction('merge', method); } } });
                  })
              }, (method: string) => method)
            }.width('100%')
          }
          if (this.editing) {
            Column({ space: 8 }) {
              TextInput({ text: this.editTitle }).height(40).width('100%')
                .onChange((value: string) => { this.editTitle = value; })
              TextArea({ text: this.editBody }).height(120).width('100%')
                .onChange((value: string) => { this.editBody = value; })
              Row({ space: 8 }) {
                Button('取消').fontSize(12).onClick(() => { this.editing = false; })
                Button('保存').fontSize(12).enabled(!this.busy).onClick(() => { void this.saveEdit(); })
              }.width('100%')
            }.width('100%').padding(10).backgroundColor($r('app.color.surface')).borderRadius(8)
          }
          if (this.error) { Text(this.error).fontSize(12).fontColor($r('app.color.danger')).width('100%') }
          if (this.notice) { Text(this.notice).fontSize(12).fontColor($r('app.color.muted')).width('100%') }
        }.width('100%').padding(12).alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1)
    }
  }

  @Builder
  filesTab() {
    if (this.selectedFile) {
      Column({ space: 6 }) {
        Row({ space: 8 }) {
          Button('‹ 文件').fontSize(12).constraintSize({ minHeight: 44 })
            .backgroundColor(Color.Transparent).fontColor($r('app.color.ink')).accessibilityText('返回文件列表')
            .onClick(() => { this.selectedFile = ''; this.lineStart = -1; this.lineEnd = -1; })
          Text(this.drafts.length + ' 条审阅草稿').fontSize(11).fontColor($r('app.color.muted')).layoutWeight(1)
        }.width('100%').padding({ left: 8, right: 8 })
        List({ space: 2 }) {
          ListItem() {
            Text(this.selectedFile).fontSize(14).fontWeight(FontWeight.Medium).wordBreak(WordBreak.BREAK_ALL)
              .width('100%').padding({ left: 10, right: 10, top: 6, bottom: 6 })
          }
          ForEach(this.currentFileHunks(), (hunk: DiffHunk) => {
            ListItem() {
              Column({ space: 0 }) {
                Text(hunk.header).fontSize(Math.max(8, this.codeFontSize - 2)).fontFamily('monospace').fontColor($r('app.color.muted'))
                  .width('100%').padding(4).backgroundColor($r('app.color.surface'))
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
                      $r('app.color.selected') : row.kind === 'add' ? $r('app.color.diff_add') :
                      row.kind === 'del' ? $r('app.color.diff_del') : Color.Transparent)
                    .onClick(() => {
                      if (this.selectedHunk !== hunk.header) { this.selectedHunk = hunk.header; this.lineStart = index; this.lineEnd = index; }
                      else { this.lineStart = index; this.lineEnd = index; }
                    })
                }, (row: DiffRow, index: number) => hunk.header + ':' + index)
              }
            }
          }, (hunk: DiffHunk) => this.selectedFile + ':' + hunk.header)
        }.width('100%').layoutWeight(1)
        if (this.lineStart >= 0) {
          Row({ space: 8 }) {
            Text('行 ' + (this.lineStart + 1)).fontSize(12).fontColor($r('app.color.muted')).layoutWeight(1)
            Button('行评论').fontSize(12).onClick(() => { this.commenting = true; })
          }.width('100%').padding(8)
        }
        if (this.commenting) {
          Column({ space: 8 }) {
            TextArea({ placeholder: '行内评论', text: this.lineComment }).height(80).width('100%')
              .onChange((value: string) => { this.lineComment = value; })
            Row({ space: 8 }) {
              Button('取消').fontSize(12).onClick(() => { this.commenting = false; })
              Button('加入草稿').fontSize(12).enabled(!!this.lineComment.trim())
                .onClick(() => {
                  const hunk = this.currentFileHunks().find((item: DiffHunk) => item.header === this.selectedHunk);
                  if (hunk) this.addLineDraft(hunk);
                })
            }.width('100%')
          }.width('100%').padding(10).backgroundColor($r('app.color.surface')).borderRadius(8)
        }
        if (this.error) { Text(this.error).fontSize(12).fontColor($r('app.color.danger')).width('100%') }
        if (this.notice) { Text(this.notice).fontSize(12).fontColor($r('app.color.muted')).width('100%') }
      }.width('100%').layoutWeight(1)
    } else {
      List({ space: 1 }) {
        ForEach(this.patchFiles, (file: DiffFile) => {
          ListItem() {
            Row({ space: 8 }) {
              Column({ space: 3 }) {
                Text(file.path.slice(file.path.lastIndexOf('/') + 1)).fontSize(14).fontWeight(FontWeight.Medium)
                  .width('100%').wordBreak(WordBreak.BREAK_ALL)
                if (file.path.includes('/')) {
                  Text(file.path.slice(0, file.path.lastIndexOf('/'))).fontSize(12).fontColor($r('app.color.muted'))
                    .width('100%').wordBreak(WordBreak.BREAK_ALL).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Text('+' + file.additions).fontSize(10).fontColor($r('app.color.diff_add_ink'))
              Text('-' + file.deletions).fontSize(10).fontColor($r('app.color.diff_del_ink'))
            }.constraintSize({ minHeight: 44 }).padding({ left: 10, right: 10, top: 8, bottom: 8 }).width('100%')
              .accessibilityText(file.path + '，新增 ' + file.additions + ' 行，删除 ' + file.deletions + ' 行')
              .onClick(() => { this.selectedFile = file.path; this.selectedHunk = ''; })
          }
        }, (file: DiffFile) => file.path)
        if (!this.patchFiles.length) {
          ListItem() { Text(this.diffError || (this.loading ? '正在读取文件差异…' : '没有可显示的文件差异')).fontSize(13)
            .fontColor(this.diffError ? $r('app.color.danger') : $r('app.color.muted')).padding(20) }
        }
      }.width('100%').layoutWeight(1)
    }
  }

  private currentFileHunks(): DiffHunk[] {
    const file = this.patchFiles.find((item: DiffFile) => item.path === this.selectedFile);
    return file ? file.hunks : [];
  }

  @Builder
  discussionTab() {
    Scroll() {
      Column({ space: 10 }) {
        if (this.activityError) {
          Text('讨论读取失败：' + this.activityError).fontSize(12).fontColor($r('app.color.danger'))
            .width('100%')
        }
        if (this.activity) {
          ForEach(this.activity.comments,
            (comment: PullRequestCommentView) => {
              Column({ space: 4 }) {
                Text(comment.author + ' · ' + comment.createdAt)
                  .fontSize(10).fontColor($r('app.color.muted')).width('100%')
                MarkdownView({ markdown: comment.body, selectable: true, onCopy: this.onCopy,
                  onOpenLink: (url: string) => this.onCopy(url), onOpenImage: (url: string) => this.onCopy(url) })
                Row({ space: 10 }) {
                  ForEach([['thumbs-up', '👍'], ['heart', '❤️'], ['laugh', '😄']], (entry: string[]) => {
                    Button(entry[1]).fontSize(12).backgroundColor(Color.Transparent)
                      .onClick(() => { void this.react(comment.id, entry[0]); })
                  }, (entry: string[]) => entry[0])
                }.width('100%')
              }.width('100%').padding(10).backgroundColor($r('app.color.surface')).borderRadius(8)
            }, (comment: PullRequestCommentView) => comment.id)
          ForEach(this.activity.threads,
            (thread: PullRequestThreadView) => {
              Column({ space: 4 }) {
                Text(thread.path + (thread.resolved ? ' · 已解决' : ''))
                  .fontSize(10).fontColor($r('app.color.primary')).width('100%')
                ForEach(thread.comments, (comment: PullRequestThreadCommentView) => {
                  Text(comment.author + ': ' + comment.body).fontSize(13)
                    .width('100%')
                }, (comment: PullRequestThreadCommentView) => comment.id)
                if (this.replyThread === thread.id) {
                  TextArea({ placeholder: '回复讨论', text: this.replyBody }).height(60).width('100%')
                    .onChange((value: string) => { this.replyBody = value; })
                  Row({ space: 8 }) {
                    Button('取消').fontSize(11).onClick(() => { this.replyThread = ''; this.replyBody = ''; })
                    Button('回复').fontSize(11).enabled(!!this.replyBody.trim())
                      .onClick(() => { void this.reply(thread.id); })
                  }.width('100%')
                } else {
                  Button('回复').fontSize(11).onClick(() => { this.replyThread = thread.id; })
                }
                Button(thread.resolved ? '重新打开讨论' : '标记已解决').fontSize(11)
                  .enabled(!this.busy)
                  .onClick(() => {
                    void this.resolveThread(thread.id, !thread.resolved);
                  })
              }.width('100%').padding(10).border({ width: 1, color: $r('app.color.border') }).borderRadius(8)
            }, (thread: PullRequestThreadView) => thread.id)
        } else {
          Text(this.activityError ? '讨论读取失败：' + this.activityError : '讨论暂不可读')
            .fontSize(13).fontColor($r('app.color.muted')).width('100%')
        }
        if (this.detail && this.detail.comment) {
          TextArea({ placeholder: '添加讨论评论', text: this.commentBody }).height(80).width('100%')
            .onChange((value: string) => { this.commentBody = value; })
          Button('提交评论').fontSize(12).enabled(!!this.commentBody.trim() && !this.busy)
            .onClick(() => { void this.submitComment(); })
        }
        if (this.error) { Text(this.error).fontSize(12).fontColor($r('app.color.danger')).width('100%') }
        if (this.notice) { Text(this.notice).fontSize(12).fontColor($r('app.color.muted')).width('100%') }
      }.width('100%').padding(12).alignItems(HorizontalAlign.Start)
    }.width('100%').layoutWeight(1)
  }

  @Builder
  reviewTab() {
    if (this.detail) {
      Scroll() {
        Column({ space: 10 }) {
          Text('行内草稿 ' + this.drafts.length + ' 条').fontSize(12).fontColor($r('app.color.muted')).width('100%')
          TextArea({ placeholder: '审阅说明（可留空）', text: this.reviewBody }).height(100).width('100%')
            .onChange((value: string) => { this.reviewBody = value; })
          Row({ space: 8 }) {
            ForEach(this.detail.reviewVerdicts, (verdict: string) => {
              Button(verdict === 'approve' ? '批准' : verdict === 'request-changes' ? '请求修改' : '评论')
                .fontSize(12).enabled(!this.busy)
                .onClick(() => { void this.submitReview(verdict); })
            }, (verdict: string) => verdict)
          }.width('100%')
          Button('打开标签').fontSize(12).onClick(() => { void this.loadLabels(); })
          Button('请求评审人').fontSize(12).onClick(() => { void this.loadReviewers(); })
          if (this.panelMode === 'labels') {
            Column({ space: 2 }) {
              ForEach(this.candidates, (candidate: Object) => {
                Row({ space: 8 }) {
                  Text(String(record(candidate).name)).fontSize(13).layoutWeight(1)
                  Text(record(candidate).applied === true ? '已添加' : '添加').fontSize(11)
                    .fontColor(record(candidate).applied === true ? $r('app.color.muted') : $r('app.color.primary'))
                }.height(40).width('100%').onClick(() => {
                  void this.toggleLabel(String(record(candidate).name), record(candidate).applied === true);
                })
              }, (candidate: Object) => String(record(candidate).name))
            }.width('100%')
          }
          if (this.panelMode === 'reviewers') {
            Column({ space: 2 }) {
              ForEach(this.reviewerCandidates, (candidate: Object) => {
                Row({ space: 8 }) {
                  Text(String(record(candidate).name)).fontSize(13).layoutWeight(1)
                  Text(record(candidate).requested === true ? '已请求' : '请求').fontSize(11)
                    .fontColor(record(candidate).requested === true ? $r('app.color.muted') : $r('app.color.primary'))
                }.height(40).width('100%').onClick(() => {
                  void this.toggleReviewer(String(record(candidate).id), String(record(candidate).kind),
                    record(candidate).requested === true);
                })
              }, (candidate: Object) => String(record(candidate).id))
            }.width('100%')
          }
          Text('提示：行内评论在“文件”页选择行后加入草稿，再在此提交。').fontSize(11)
            .fontColor($r('app.color.muted')).width('100%')
          if (this.error) { Text(this.error).fontSize(12).fontColor($r('app.color.danger')).width('100%') }
          if (this.notice) { Text(this.notice).fontSize(12).fontColor($r('app.color.muted')).width('100%') }
        }.width('100%').padding(12).alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1)
    }
  }

  @Builder
  guideTab() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(this.guideBusy && !this.guide ? '正在加载评审向导…' :
          this.guide === undefined || (this.guide.headSha === '' && this.guide.stops.length === 0) ?
            '还没有保存的评审向导' :
          this.guide.running ? 'Agent 正在生成评审向导…' :
          this.guide.stale ? '有新提交，向导可能已过期' :
          this.guide.runDetail ? '上次生成失败：' + this.guide.runDetail :
          '向导基于 ' + this.guide.headSha.slice(0, 8))
          .fontSize(12).fontColor($r('app.color.muted')).layoutWeight(1)
        Button('刷新').fontSize(11).enabled(!this.guideBusy).onClick(() => { void this.loadGuide(); })
        Button(this.guide && this.guide.stops.length > 0 ? '重新生成' : '生成')
          .fontSize(11).enabled(!this.guideBusy).onClick(() => { void this.generateGuide(); })
      }.width('100%')
      if (this.guideError) { Text(this.guideError).fontSize(12).fontColor($r('app.color.danger')).width('100%') }
      if (this.guide && this.guide.stops.length > 0) {
        List({ space: 10 }) {
          ForEach(this.guide.stops, (stop: ReviewGuideStop, index: number) => {
            ListItem() {
              Column({ space: 4 }) {
                Text((index + 1) + '. ' + stop.title).fontSize(14).fontWeight(FontWeight.Medium).width('100%')
                if (stop.summary) { Text(stop.summary).fontSize(12).fontColor($r('app.color.muted')).width('100%') }
                if (stop.attentionNote) {
                  Text(stop.attentionKind + '：' + stop.attentionNote).fontSize(12)
                    .fontColor($r('app.color.danger')).width('100%')
                }
                ForEach(stop.files, (file: ReviewGuideFile) => {
                  Text('文件 ' + file.path + (file.note ? ' · ' + file.note : ''))
                    .fontSize(11).fontColor($r('app.color.ink')).width('100%')
                }, (file: ReviewGuideFile) => file.path)
                ForEach(stop.excerpts, (excerpt: ReviewGuideExcerpt) => {
                  Text('摘录 ' + excerpt.path + ':' + excerpt.start + '–' + excerpt.end + ' (' + excerpt.side + ')' +
                    (excerpt.caption ? ' · ' + excerpt.caption : ''))
                    .fontSize(11).fontColor($r('app.color.muted')).width('100%')
                }, (excerpt: ReviewGuideExcerpt, index: number) =>
                  excerpt.path + ':' + excerpt.start + ':' + index)
                ForEach(stop.notes, (note: ReviewGuideNote) => {
                  Column({ space: 2 }) {
                    Text(note.title + ' · ' + note.path + ':' + note.line).fontSize(12).width('100%')
                    if (note.body) { Text(note.body).fontSize(11).fontColor($r('app.color.muted')).width('100%') }
                  }.width('100%')
                }, (note: ReviewGuideNote, index: number) =>
                  note.path + ':' + note.line + ':' + index)
                ForEach(stop.questions, (question: string, index: number) => {
                  Text('？ ' + question).fontSize(11).fontColor($r('app.color.primary')).width('100%')
                }, (question: string, index: number) => index + ':' + question)
              }.width('100%').padding(10).backgroundColor($r('app.color.surface')).borderRadius(10)
            }
          }, (stop: ReviewGuideStop, index: number) => index + ':' + stop.title)
        }.width('100%').layoutWeight(1)
      } else if (!this.guideBusy) {
        Text('评审向导会由 Agent 读取这次改动，给出阅读顺序、代码摘录和需要重点关注的问题。')
          .fontSize(12).fontColor($r('app.color.muted')).width('100%').padding(10)
      }
    }.width('100%').layoutWeight(1).padding(10)
  }

  @Builder
  detailView() {
    Column({ space: 6 }) {
      Row({ space: 4 }) {
        ForEach([['overview', '概览'], ['files', '文件'], ['discussion', '讨论'], ['review', '评审'], ['guide', '向导']],
          (entry: string[]) => {
            Button(entry[1]).fontSize(12)
              .backgroundColor(this.tab === entry[0] ? $r('app.color.primary') : Color.Transparent)
              .fontColor(this.tab === entry[0] ? $r('app.color.on_primary') : $r('app.color.ink'))
              .onClick(() => { this.tab = entry[0]; })
          }, (entry: string[]) => entry[0])
      }.width('100%').padding({ left: 8, right: 8 })
      if (this.loading) { Text('正在读取 PR…').fontSize(12).fontColor($r('app.color.muted')).padding(10) }
      if (this.tab === 'overview') { this.overviewTab() }
      else if (this.tab === 'files') { this.filesTab() }
      else if (this.tab === 'discussion') { this.discussionTab() }
      else if (this.tab === 'guide') { this.guideTab() }
      else { this.reviewTab() }
    }.width('100%').layoutWeight(1)
  }

  build() {
    Column({ space: 4 }) {
      this.header()
      Divider().color($r('app.color.border'))
      if (this.selected) { this.detailView() } else { this.listView() }
    }.width('100%').height('100%').backgroundColor($r('app.color.canvas'))
  }
}
