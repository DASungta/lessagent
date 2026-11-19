import { T3Client } from '../services/T3Client';
import { RefView, VcsChange, VcsView, emptyVcs, pullRequestStateLabel } from '../protocol/R5';
import { record, text } from '../protocol/Wire';

@Component
export struct GitPanel {
  connection: T3Client | undefined = undefined;
  @Prop cwd: string = '';
  @Prop threadId: string = '';
  @Prop projectId: string = '';
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
  private stream: ((value: Object) => void) | undefined = undefined;

  aboutToAppear(): void {
    const connection = this.connection;
    if (!connection || !this.cwd) return;
    this.stream = connection.watchVcsStatus(this.cwd, (value: VcsView) => {
      this.status = value;
    });
    void this.loadRefs();
    void this.refreshStatus(false);
  }

  aboutToDisappear(): void {
    if (this.connection && this.stream) this.connection.stopRpcStream(this.stream);
    this.stream = undefined;
  }

  private async loadRefs(): Promise<void> {
    const connection = this.connection;
    if (!connection || !this.cwd) return;
    try { this.refs = await connection.workspaceRefs(this.cwd, this.branchQuery); }
    catch (reason) { this.error = (reason as Error).message; }
  }

  private summary(): string {
    if (!this.status.isRepo) return '不是 Git 仓库';
    const parts: string[] = [];
    parts.push(this.status.files.length ? this.status.files.length + ' 个文件已改动' : '工作区干净');
    if (this.status.ahead > 0) parts.push('领先 ' + this.status.ahead);
    if (this.status.behind > 0) parts.push('落后 ' + this.status.behind);
    if (this.status.prNumber > 0) parts.push(pullRequestStateLabel(this.status.prState, false) + ' #' + this.status.prNumber);
    return parts.join(' · ');
  }

  private async run(action: string): Promise<void> {
    const connection = this.connection;
    if (!connection || this.busy) return;
    if (!this.status.isRepo) { this.error = '不是 Git 仓库'; return; }
    if ((action === 'commit' || action === 'commit_push' || action === 'commit_push_pr') &&
      !this.commitMessage.trim()) { this.error = '请输入提交信息'; return; }
    if (action === 'push' || action === 'commit_push' || action === 'commit_push_pr') {
      if (!this.status.hasPrimaryRemote) { this.error = '仓库没有可推送的远端'; return; }
      if (this.status.isDefaultRef && !this.status.prNumber) {
        AlertDialog.show({ title: '推送到默认分支？', message: '当前在 ' + this.status.refName + '，推送会直接影响默认分支。',
          primaryButton: { value: '取消', action: () => {} },
          secondaryButton: { value: '推送', action: () => { void this.execute(action); } } });
        return;
      }
    }
    await this.execute(action);
  }

  private async execute(action: string): Promise<void> {
    const connection = this.connection;
    if (!connection) return;
    this.busy = true; this.error = ''; this.notice = '正在执行 ' + action + '…';
    try {
      const value = record(await connection.gitAction(this.cwd, action, this.commitMessage, this.featureBranch,
        [], (label: string) => { this.notice = label; }));
      this.notice = this.result(value);
      if (action !== 'create_pr') this.commitMessage = '';
      try { this.status = await connection.refreshVcs(this.cwd); } catch (_) { }
    } catch (reason) {
      this.error = 'Git 操作失败：' + (reason as Error).message + '。不会自动重试，请核对仓库状态。';
      this.notice = '';
    } finally { this.busy = false; }
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
    if (!connection || this.busy) return;
    this.busy = true; this.error = ''; this.notice = '正在拉取…';
    try {
      const value = record(await connection.pullRepository(this.cwd));
      this.notice = text(value.status) === 'pulled' ? '已拉取' : '已是最新';
    } catch (reason) {
      this.error = '拉取失败：' + (reason as Error).message + '。不会自动重试。';
      this.notice = '';
    } finally { this.busy = false; }
  }

  private async refreshStatus(showBusy: boolean = true): Promise<void> {
    const connection = this.connection;
    if (!connection || (showBusy && this.busy)) return;
    if (showBusy) this.busy = true;
    this.error = '';
    try { this.status = await connection.refreshVcs(this.cwd); }
    catch (reason) { this.error = (reason as Error).message; }
    finally { if (showBusy) this.busy = false; }
  }

  private confirmCheckout(ref: RefView): void {
    this.busy = true; this.error = ''; this.notice = '正在切换分支…';
    const connection = this.connection;
    if (!connection) { this.busy = false; return; }
    void connection.checkoutRef(this.cwd, ref.name)
      .then(() => { this.notice = '已切换到 ' + ref.name; this.view = 'overview';
        void this.loadRefs(); void this.refreshStatus(); })
      .catch((reason: Error) => { this.error = '切换分支失败：' + reason.message + '。不会自动重试。'; this.notice = ''; })
      .finally(() => { this.busy = false; });
  }

  @Builder
  header() {
    Row({ space: 6 }) {
      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.ui_back')).width(22).height(22)
      }.backgroundColor(Color.Transparent).width(44).height(44).accessibilityText('返回').onClick(() => {
          if (this.view !== 'overview') { this.view = 'overview'; return; }
          this.onBack();
        })
      Column({ space: 2 }) {
        Text(this.view === 'commit' ? '提交' : this.view === 'branches' ? '分支' : 'Git')
          .fontSize(17).fontWeight(FontWeight.Medium).width('100%')
        Text((this.status.refName || 'Detached HEAD') + ' · ' + this.cwd).fontSize(11)
          .fontColor($r('app.color.muted')).width('100%').maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (this.view === 'overview') {
        Button('刷新').constraintSize({ minHeight: 44 }).fontSize(12).backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
          .onClick(() => { void this.refreshStatus(); })
        Button('分支').constraintSize({ minHeight: 44 }).fontSize(12).backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
          .onClick(() => { this.view = 'branches'; void this.loadRefs(); })
      }
    }.width('100%').padding({ left: 8, right: 8, top: 4, bottom: 4 })
  }

  @Builder
  statusCard() {
    Column({ space: 6 }) {
      Text(this.summary()).fontSize(14).fontWeight(FontWeight.Medium).width('100%')
      if (this.status.files.length) {
        Text('+' + this.status.insertions + ' / -' + this.status.deletions)
          .fontSize(11).fontColor($r('app.color.muted')).width('100%')
      }
      if (this.status.prNumber > 0 && this.status.prTitle) {
        Text('PR #' + this.status.prNumber + ' · ' + this.status.prTitle).fontSize(12)
          .fontColor($r('app.color.primary')).width('100%').maxLines(2)
      }
    }.padding(12).width('100%').backgroundColor($r('app.color.surface')).borderRadius(10)
  }

  @Builder
  overview() {
    Column({ space: 12 }) {
      this.statusCard()
      Row({ space: 8 }) {
        Button('提交').layoutWeight(1).constraintSize({ minHeight: 44 }).borderRadius(12)
          .backgroundColor($r('app.color.primary')).fontColor($r('app.color.on_primary')).enabled(!this.busy && this.status.hasWorkingTreeChanges)
          .onClick(() => { this.view = 'commit'; })
        Button('推送').layoutWeight(1).constraintSize({ minHeight: 44 }).borderRadius(12)
          .backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).enabled(!this.busy)
          .onClick(() => { void this.run('push'); })
        Button('拉取').layoutWeight(1).constraintSize({ minHeight: 44 }).borderRadius(12)
          .backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).enabled(!this.busy && this.status.hasPrimaryRemote)
          .onClick(() => { void this.pull(); })
      }.width('100%')
      if (this.status.hasWorkingTreeChanges) {
        Text('改动文件').fontSize(13).fontWeight(FontWeight.Medium).width('100%')
        List({ space: 1 }) {
          ForEach(this.status.files, (file: VcsChange) => {
            ListItem() {
              Row({ space: 8 }) {
                Text(file.path).fontSize(13).layoutWeight(1).maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text('+' + file.insertions).fontSize(11).fontColor($r('app.color.diff_add_ink'))
                Text('-' + file.deletions).fontSize(11).fontColor($r('app.color.diff_del_ink'))
              }.constraintSize({ minHeight: 48 }).padding({ left: 10, right: 10, top: 8, bottom: 8 }).width('100%')
            }
          }, (file: VcsChange) => file.path)
        }.width('100%').height(220)
      } else {
        Text('没有未提交改动').fontSize(13).fontColor($r('app.color.muted')).width('100%')
      }
      if (this.error) { Text(this.error).fontSize(12).fontColor($r('app.color.danger')).width('100%') }
      if (this.notice) { Text(this.notice).fontSize(12).fontColor($r('app.color.muted')).width('100%') }
    }.width('100%').padding(12)
  }

  @Builder
  commitView() {
    Column({ space: 12 }) {
      TextArea({ placeholder: '提交信息', text: this.commitMessage })
        .height(110).width('100%').enabled(!this.busy)
        .onChange((value: string) => { this.commitMessage = value; })
      Row({ space: 8 }) {
        Toggle({ type: ToggleType.Checkbox, isOn: this.featureBranch })
          .onChange((value: boolean) => { this.featureBranch = value; })
        Text('创建新功能分支').fontSize(13).layoutWeight(1)
      }.width('100%')
      Button('提交').width('100%').constraintSize({ minHeight: 44 }).borderRadius(12)
        .backgroundColor($r('app.color.primary')).fontColor($r('app.color.on_primary')).enabled(!this.busy && !!this.commitMessage.trim())
        .onClick(() => { void this.run('commit'); })
      Button('提交并推送').width('100%').constraintSize({ minHeight: 44 }).borderRadius(12)
        .backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).enabled(!this.busy && !!this.commitMessage.trim() && this.status.hasPrimaryRemote)
        .onClick(() => { void this.run('commit_push'); })
      Button('提交、推送并创建 PR').width('100%').constraintSize({ minHeight: 44 }).borderRadius(12)
        .backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).enabled(!this.busy && !!this.commitMessage.trim())
        .onClick(() => { void this.run('commit_push_pr'); })
      if (this.error) { Text(this.error).fontSize(12).fontColor($r('app.color.danger')).width('100%') }
      if (this.notice) { Text(this.notice).fontSize(12).fontColor($r('app.color.muted')).width('100%') }
    }.width('100%').padding(12)
  }

  @Builder
  branchesView() {
    Column({ space: 8 }) {
      TextInput({ placeholder: '搜索分支', text: this.branchQuery }).height(40).width('100%')
        .onChange((value: string) => { this.branchQuery = value; })
        .onSubmit(() => { void this.loadRefs(); })
      List({ space: 1 }) {
        ForEach(this.refs, (ref: RefView) => {
          ListItem() {
            Row({ space: 8 }) {
              Text(ref.current ? '当前' : '分支').fontSize(11)
                .fontColor(ref.current ? $r('app.color.primary') : $r('app.color.muted'))
              Text(ref.name).fontSize(13).layoutWeight(1).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (ref.worktreePath && !ref.current) { Text('工作树占用').fontSize(10).fontColor($r('app.color.muted')) }
              if (ref.isRemote) { Text('远端').fontSize(10).fontColor($r('app.color.muted')) }
            }.constraintSize({ minHeight: 48 }).padding({ left: 10, right: 10 }).width('100%')
              .onClick(() => {
                if (ref.current || this.busy) return;
                AlertDialog.show({ title: '切换分支？', message: ref.name + (ref.worktreePath ? '\n该分支已在其他工作树占用' : ''),
                  primaryButton: { value: '取消', action: () => {} },
                  secondaryButton: { value: '切换', action: () => this.confirmCheckout(ref) } });
              })
          }
        }, (ref: RefView) => ref.name)
      }.width('100%').layoutWeight(1)
      if (this.error) { Text(this.error).fontSize(12).fontColor($r('app.color.danger')).width('100%') }
      if (this.notice) { Text(this.notice).fontSize(12).fontColor($r('app.color.muted')).width('100%') }
    }.width('100%').padding(12).layoutWeight(1)
  }

  build() {
    Column({ space: 6 }) {
      this.header()
      Divider().color($r('app.color.border'))
      if (this.view === 'commit') {
        Scroll() { this.commitView() }.width('100%').layoutWeight(1).align(Alignment.TopStart)
      }
      else if (this.view === 'branches') { this.branchesView() }
      else {
        Scroll() { this.overview() }.width('100%').layoutWeight(1).align(Alignment.TopStart)
      }
      if (this.busy) { LoadingProgress().width(28).height(28) }
    }.width('100%').height('100%').backgroundColor($r('app.color.canvas')).foregroundColor($r('app.color.ink'))
  }
}
