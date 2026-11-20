import { TopBar } from './ui/TopBar';
import { GroupCard } from './ui/GroupCard';
import { AppButton } from './ui/AppButton';
import { StatusBadge } from './ui/StatusBadge';
import { FontSize, LineHeight, Radius, Sizes, Space, Weight } from '../common/Theme';
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
    TopBar({
      title: this.view === 'commit' ? '提交' : this.view === 'branches' ? '分支' : 'Git',
      subtitle: (this.status.refName || 'Detached HEAD') + ' · ' + this.cwd,
      showBack: true,
      closeStyle: this.view === 'overview',
      backLabel: this.view === 'overview' ? '关闭 Git' : '返回 Git',
      onBack: () => {
        if (this.view !== 'overview') { this.view = 'overview'; return; }
        this.onBack();
      }
    }) {
      if (this.view === 'overview') {
        AppButton({ label: '刷新', kind: 'text', onTap: () => { void this.refreshStatus(); } })
        AppButton({ label: '分支', kind: 'text', onTap: () => { this.view = 'branches'; void this.loadRefs(); } })
      }
    }
  }

  @Builder
  statusCard() {
    GroupCard({ title: '工作区状态' }) {
      Column({ space: Space.xs }) {
        Text(this.summary()).fontSize(FontSize.body).fontWeight(Weight.medium).fontColor($r('app.color.ink')).width('100%')
        if (this.status.files.length) {
          Row({ space: Space.xs }) {
            Text('+' + this.status.insertions)
              .fontSize(FontSize.badge).fontWeight(Weight.medium).fontColor($r('app.color.diff_add_ink'))
              .backgroundColor($r('app.color.diff_add')).borderRadius(Radius.badge)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            Text('-' + this.status.deletions)
              .fontSize(FontSize.badge).fontWeight(Weight.medium).fontColor($r('app.color.diff_del_ink'))
              .backgroundColor($r('app.color.diff_del')).borderRadius(Radius.badge)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          }.width('100%')
        }
        if (this.status.prNumber > 0 && this.status.prTitle) {
          StatusBadge({ text: 'PR #' + this.status.prNumber + ' · ' + this.status.prTitle, tone: 'info' })
        }
        Row({ space: Space.xs }) {
          Column() {
            AppButton({
              label: '提交', kind: 'primary', compact: true, fill: true,
              disabled: this.busy || !this.status.hasWorkingTreeChanges,
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
              disabled: this.busy || !this.status.hasPrimaryRemote,
              onTap: () => { void this.pull(); }
            })
          }.layoutWeight(1)
        }.width('100%').padding({ top: Space.xs })
      }.padding({ left: 14, right: 14, top: Space.sm, bottom: Space.sm }).width('100%').alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  overview() {
    Column({ space: Space.sm }) {
      this.statusCard()
      if (this.status.hasWorkingTreeChanges) {
        Text('改动文件')
          .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted'))
          .padding({ left: Space.xxs, right: Space.xxs, top: Space.xxs }).width('100%')
        List({ space: 0 }) {
          ForEach(this.status.files, (file: VcsChange) => {
            ListItem() {
              Row({ space: Space.xs }) {
                Text(file.path).fontSize(FontSize.callout).fontColor($r('app.color.ink')).layoutWeight(1).maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text('+' + file.insertions).fontSize(FontSize.badge).fontColor($r('app.color.diff_add_ink'))
                Text('-' + file.deletions).fontSize(FontSize.badge).fontColor($r('app.color.diff_del_ink'))
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
      if (this.error) { Text(this.error).fontSize(FontSize.callout).fontColor($r('app.color.danger')).width('100%') }
      if (this.notice) { Text(this.notice).fontSize(FontSize.callout).fontColor($r('app.color.primary_text')).width('100%') }
    }.width('100%').padding({ left: Space.sm, right: Space.sm, bottom: Space.lg }).alignItems(HorizontalAlign.Start)
  }

  @Builder
  commitView() {
    Column({ space: Space.sm }) {
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
        disabled: this.busy || !this.commitMessage.trim() || !this.status.hasPrimaryRemote,
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
                AlertDialog.show({ title: '切换分支？', message: ref.name + (ref.worktreePath ? '\n该分支已在其他工作树占用' : ''),
                  primaryButton: { value: '取消', action: () => {} },
                  secondaryButton: { value: '切换', action: () => { this.confirmCheckout(ref); } } });
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
