import { AddProjectEnvironment, CloneView, WorkspaceActions } from '../services/Workspace';
import {
  ProjectView, ScopedProject, cloneDestination, cloneDirectoryName, cloneDirectoryPath,
  inferProjectTitle, newProjectPathPreview, normalizeCloneUrl, resolveProjectPath, samePath,
  scopedProjectView
} from '../protocol/Projects';

interface ProviderRow {
  kind: string;
  label: string;
  status: string;
  hint: string;
  authStatus: string;
  ready: boolean;
}
interface BrowseRow { name: string; fullPath: string; }
interface ProjectArchivePatch { archived: boolean; }

function clean(value: Object | undefined): string {
  return value === undefined || value === null || typeof value !== 'string' ? '' : value;
}
function row(value: Object): Record<string, Object> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) throw new Error('服务返回格式无效');
  return value as Record<string, Object>;
}
function providerRows(value: Object | undefined): ProviderRow[] {
  if (value === undefined || value === null) return [];
  const providers = row(value).sourceControlProviders;
  if (!Array.isArray(providers)) return [];
  const result: ProviderRow[] = [];
  for (const item of providers as Object[]) {
    const value = row(item);
    const auth = value.auth === undefined || value.auth === null ? undefined : row(value.auth);
    const status = clean(value.status);
    const authStatus = auth === undefined ? 'unknown' : clean(auth.status);
    const ready = status === 'available' && authStatus !== 'unauthenticated';
    const provider: ProviderRow = {
      kind: clean(value.kind), label: clean(value.label) || clean(value.kind),
      status, hint: clean(value.installHint) || clean(auth === undefined ? undefined : auth.detail),
      authStatus, ready
    };
    result.push(provider);
  }
  return result.sort((left: ProviderRow, right: ProviderRow) =>
    Number(right.ready) - Number(left.ready) || left.label.localeCompare(right.label));
}
function browseRows(value: Object): BrowseRow[] {
  const entries = row(value).entries;
  if (!Array.isArray(entries)) return [];
  return (entries as Object[]).map((item: Object): BrowseRow => {
    const entry = row(item);
    return { name: clean(entry.name), fullPath: clean(entry.fullPath) };
  }).filter((entry: BrowseRow) => !!entry.name);
}
function parentPath(value: Object): string { return clean(row(value).parentPath); }

function browseBase(directory: string | undefined): string {
  if (!directory) return '~/';
  return directory.endsWith('/') || directory.endsWith('\\') ? directory : directory + '/';
}

@Component
export struct AddProjectPanel {
  @Prop @Watch('environmentsChanged') environments: AddProjectEnvironment[] = [];
  @Prop initialEnvironmentId: string = '';
  actions: WorkspaceActions | undefined = undefined;
  @State step: string = 'source';
  @State environmentId: string = '';
  @State source: string = 'url';
  @State provider: string = '';
  @State name: string = '';
  @State pathInput: string = '';
  @State repositoryInput: string = '';
  @State remoteUrl: string = '';
  @State repositoryTitle: string = '';
  @State repositoryName: string = '';
  @State publishing: boolean = false;
  @State publishKind: string = '';
  @State providers: ProviderRow[] = [];
  @State browse: BrowseRow[] = [];
  @State browseParent: string = '';
  @State error: string = '';
  @State busy: boolean = false;
  @State cloneProjectId: string = '';
  @State cloneStatus: string = '';
  @State clone: CloneView | undefined = undefined;
  private cloneCallback: ((value: Object) => void) | undefined = undefined;
  private cloneEnvironment: AddProjectEnvironment | undefined = undefined;
  onClose: () => void = () => {};
  onOpenProject: (project: ScopedProject) => void = () => {};
  onEnvironments: () => void = () => {};

  aboutToAppear(): void {
    this.environmentId = this.initialEnvironmentId ||
      (this.environments.find((environment: AddProjectEnvironment) => environment.ready)?.environmentId || this.environments[0]?.environmentId || '');
  }
  private environmentsChanged(): void {
    if (!this.environment()) {
      this.environmentId = this.environments.find((environment: AddProjectEnvironment) => environment.ready)?.environmentId ||
        this.environments[0]?.environmentId || '';
      this.providers = [];
    }
  }
  aboutToDisappear(): void {
    if (this.cloneCallback && this.cloneEnvironment?.client) this.cloneEnvironment.client.stopRpcStream(this.cloneCallback);
    this.cloneCallback = undefined;
  }
  private environment(): AddProjectEnvironment | undefined {
    return this.actions?.environment(this.environmentId) ||
      this.environments.find((entry: AddProjectEnvironment) => entry.environmentId === this.environmentId);
  }
  private scoped(value: ProjectView, environment: AddProjectEnvironment): ScopedProject {
    return scopedProjectView(value, environment.localId, environment.environmentId, environment.label,
      !!environment.scratchWorkspaceRoot && samePath(value.workspaceRoot, environment.scratchWorkspaceRoot));
  }
  private existing(environment: AddProjectEnvironment, path: string): ScopedProject | undefined {
    const project = environment.client.shell.projects.find((item: ProjectView) => samePath(item.workspaceRoot, path));
    return project ? this.scoped(project, environment) : undefined;
  }
  private suggestedDestination: string = '';
  private setPath(path: string): void {
    this.pathInput = path;
    void this.loadBrowse();
  }
  private loadProviders(): void {
    const environment = this.environment();
    if (!environment?.ready) { this.providers = []; return; }
    void environment.client.discoverSourceControl().then((value: Object) => {
      if (this.environmentId === environment.environmentId) {
        const offered = environment.client.offeredSourceControlProviders;
        const keys = Object.keys(offered);
        const rows = providerRows(value);
        this.providers = keys.length ? rows.filter((provider: ProviderRow) => offered[provider.kind] === true) : rows;
      }
    }).catch(() => { if (this.environmentId === environment.environmentId) this.providers = []; });
  }
  private async loadBrowse(): Promise<void> {
    const environment = this.environment();
    if (!environment?.ready || !environment.client.canReadFiles()) { this.browse = []; return; }
    const input = this.pathInput;
    const step = this.step;
    const current = (): boolean => this.environmentId === environment.environmentId && this.pathInput === input && this.step === step;
    // A suggested clone directory normally does not exist until the clone starts.
    const path = step === 'destination' && input === this.suggestedDestination ? browseBase(environment.baseDirectory) : input;
    try {
      const value = await environment.client.browseFilesystem(path);
      if (!current()) return;
      this.browse = browseRows(value); this.browseParent = parentPath(value); this.error = '';
    } catch (error) {
      if (!current()) return;
      this.browse = []; this.browseParent = '';
      this.error = (error as Error).message;
    }
  }
  private chooseEnvironment(environmentId: string): void {
    this.environmentId = environmentId; this.providers = []; this.error = '';
    const environment = this.environment();
    if (environment) {
      this.pathInput = browseBase(environment.baseDirectory);
    }
  }
  private startSource(kind: string, provider: string = ''): void {
    this.source = kind; this.provider = provider; this.error = ''; this.repositoryInput = '';
    this.step = kind === 'new' ? 'new' : kind === 'local' ? 'local' : 'repository';
    const environment = this.environment();
    if (kind === 'local') {
      this.pathInput = browseBase(environment?.baseDirectory);
      void this.loadBrowse();
    }
    if (kind === 'new') this.name = '';
    if (kind !== 'new') this.publishing = false;
  }
  private back(): void {
    if (this.step === 'source') { this.onClose(); return; }
    if (this.step === 'destination') { this.step = 'repository'; return; }
    this.step = 'source'; this.error = ''; this.browse = [];
  }
  private async openExisting(environment: AddProjectEnvironment, path: string): Promise<boolean> {
    const existing = this.existing(environment, path);
    if (!existing) return false;
    if (existing.archivedAt && this.actions) {
      const patch: ProjectArchivePatch = { archived: false };
      await this.actions.updateProjects([existing], patch);
    }
    this.onOpenProject(existing);
    return true;
  }
  private async resolveHome(path: string): Promise<string> {
    const environment = this.environment();
    if (!environment?.ready || !environment.client.canReadFiles() || !path.startsWith('~/')) return path;
    try {
      const home = parentPath(await environment.client.browseFilesystem('~')).replace(/[\\/]+$/, '');
      if (home) return home + path.slice(1);
    } catch (_) {}
    return path;
  }
  private async createLocal(): Promise<void> {
    const environment = this.environment();
    if (!environment || this.busy) return;
    this.error = ''; this.busy = true;
    try {
      const path = await this.resolveHome(resolveProjectPath(this.pathInput, environment.platform));
      if (await this.openExisting(environment, path)) return;
      const projectId = await this.actions?.createProject(environment, path) || '';
      if (!projectId) throw new Error('项目创建未返回标识');
      const found = await this.actions?.waitForProject(environment, projectId);
      if (!found) { this.error = '项目已创建，但尚未同步到本机；请稍后从项目选择器刷新。'; return; }
      const project = environment.client.shell.projects.find((item: ProjectView) => item.id === projectId);
      if (project) this.onOpenProject(this.scoped(project, environment));
    } catch (error) { this.error = (error as Error).message; }
    finally { this.busy = false; }
  }
  private async createNew(): Promise<void> {
    const environment = this.environment();
    const actions = this.actions;
    if (!environment || !actions || this.busy) return;
    this.error = ''; this.busy = true;
    try {
      const result = await actions.createNewProject(environment, this.name);
      const projectId = clean(result.projectId);
      if (!projectId) throw new Error('项目创建未返回标识');
      const commitError = clean(result.commitError);
      if (commitError) this.error = '项目已创建但没有首个提交：' + commitError;
      const publishKind = this.publishKind || this.providers.find((provider: ProviderRow) => provider.ready)?.kind || '';
      if (this.publishing && publishKind) {
        const workspaceRoot = clean(result.workspaceRoot);
        const repository = workspaceRoot.split(/[\\/]/).filter(Boolean).slice(-1)[0] || this.name;
        try { await actions.publish(environment, workspaceRoot, publishKind, repository); }
        catch (error) { this.error = '项目已创建，但私有仓库发布失败：' + (error as Error).message; }
      }
      const found = await actions.waitForProject(environment, projectId);
      if (!found) { this.error = '项目已创建，但尚未同步到本机；请稍后从项目选择器刷新。'; return; }
      const project = environment.client.shell.projects.find((item: ProjectView) => item.id === projectId);
      if (project) this.onOpenProject(this.scoped(project, environment));
    } catch (error) { this.error = (error as Error).message; }
    finally { this.busy = false; }
  }
  private async continueRepository(): Promise<void> {
    const environment = this.environment();
    if (!environment || this.busy) return;
    const input = this.repositoryInput.trim();
    if (!input) { this.error = '请输入仓库'; return; }
    this.error = ''; this.busy = true;
    try {
      if (this.source === 'url') {
        this.remoteUrl = normalizeCloneUrl(input);
        this.repositoryName = cloneDirectoryName(this.remoteUrl);
        this.repositoryTitle = this.repositoryName;
      } else {
        const result = row(await environment.client.lookupRepository(this.source, input));
        this.remoteUrl = clean(result.url) || clean(result.sshUrl);
        this.repositoryTitle = clean(result.nameWithOwner) || this.remoteUrl;
        this.repositoryName = cloneDirectoryName(this.repositoryTitle || this.remoteUrl);
        if (!this.remoteUrl) throw new Error('仓库地址无效');
      }
      const cloneName = cloneDirectoryPath(this.remoteUrl, environment.ghqCloneLayout);
      const base = browseBase(environment.baseDirectory);
      this.suggestedDestination = cloneDestination(base, cloneName);
      this.pathInput = this.suggestedDestination;
      this.step = 'destination';
      void this.loadBrowse();
    } catch (error) { this.error = (error as Error).message; }
    finally { this.busy = false; }
  }
  private async cloneProject(): Promise<void> {
    const environment = this.environment();
    const actions = this.actions;
    if (!environment || !actions || !this.remoteUrl || this.busy) return;
    this.error = ''; this.busy = true;
    try {
      const path = await this.resolveHome(resolveProjectPath(this.pathInput, environment.platform));
      if (await this.openExisting(environment, path)) return;
      const projectId = await actions.startClone(environment, this.remoteUrl, path,
        inferProjectTitle(path), '');
      this.cloneProjectId = projectId; this.cloneStatus = '克隆已开始';
      this.watchClone(environment);
      const found = await actions.waitForProject(environment, projectId, 30000);
      if (!found) {
        this.cloneStatus = '项目已登记，克隆仍在后台进行；可在项目列表刷新查看。';
        return;
      }
      await this.waitForClone(projectId, 15000);
      const clone = this.clone;
      if (!clone || clone.projectId !== projectId) {
        this.cloneStatus = '项目已登记，正在等待克隆状态；可取消或稍后刷新查看。';
        return;
      }
      if (clone.phase === 'failed' || clone.phase === 'cancelled') return;
      if (clone.phase !== 'done') {
        this.cloneStatus = '项目已登记，克隆仍在后台进行；可在此取消或稍后刷新查看。';
        return;
      }
      const project = environment.client.shell.projects.find((item: ProjectView) => item.id === projectId);
      if (project) this.onOpenProject(this.scoped(project, environment));
    } catch (error) { this.error = (error as Error).message; }
    finally { this.busy = false; }
  }
  private async waitForClone(projectId: string, timeoutMs: number): Promise<void> {
    const until = Date.now() + timeoutMs;
    while (Date.now() < until) {
      const clone = this.clone;
      if (clone?.projectId === projectId &&
        (clone.phase === 'done' || clone.phase === 'failed' || clone.phase === 'cancelled')) return;
      await new Promise<void>((resolve) => { setTimeout(resolve, 200); });
    }
  }
  private watchClone(environment: AddProjectEnvironment): void {
    const actions = this.actions;
    if (!actions) return;
    if (this.cloneCallback) environment.client.stopRpcStream(this.cloneCallback);
    this.cloneEnvironment = environment;
    this.cloneCallback = actions.watchClones(environment, (clones: CloneView[]) => {
      const clone = clones.find((item: CloneView) => item.projectId === this.cloneProjectId);
      if (clone) {
        this.clone = clone;
        this.cloneStatus = clone.error ? ('克隆失败：' + clone.error) :
          clone.phase === 'done' ? '克隆完成' : clone.phase + ' · ' + clone.stage +
            (clone.percent ? ' · ' + clone.percent + '%' : '') + (clone.stalled ? ' · 已停滞' : '') +
            (clone.detail ? ' · ' + clone.detail : '');
      }
    });
  }
  private openPath(fullPath: string): void {
    this.setPath(fullPath.endsWith('/') ? fullPath : fullPath + '/');
  }

  @Builder
  sourceRow(title: string, subtitle: string, enabled: boolean, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        Text('›').fontSize(18).fontColor($r('app.color.muted'))
        Column({ space: 3 }) {
          Text(title).fontSize(15).fontWeight(FontWeight.Medium).width('100%')
          Text(subtitle).fontSize(12).fontColor($r('app.color.muted')).maxLines(2).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%').padding(14)
    }.width('100%').backgroundColor($r('app.color.surface')).borderRadius(12)
      .enabled(enabled && !this.busy).onClick(action)
  }
  @Builder
  browseList() {
    if (this.browseParent) {
      this.sourceRow('..', this.browseParent, true, () => this.setPath(this.browseParent))
    }
    ForEach(this.browse, (entry: BrowseRow) => {
      this.sourceRow(entry.name, entry.fullPath, true, () => this.openPath(entry.fullPath))
    }, (entry: BrowseRow) => entry.fullPath)
  }

  @Builder
  sourcePage() {
    Column({ space: 10 }) {
      if (this.environments.length > 1) {
        Select(this.environments.map((environment: AddProjectEnvironment) => {
          return { value: environment.label + (environment.ready ? '' : '（未连接）') } as SelectOption;
        })).value(this.environments.find((environment: AddProjectEnvironment) => environment.environmentId === this.environmentId)?.label || '选择环境')
          .onSelect((index: number) => this.chooseEnvironment(this.environments[index]?.environmentId || ''))
          .width('100%').height(40).font({ size: 13 }).backgroundColor($r('app.color.surface'))
      }
      if (this.environment()?.newProjectsRoot) {
        this.sourceRow('新建项目', '从名称创建新的 Git 仓库', !!this.environment()?.ready, () => this.startSource('new'))
      }
      this.sourceRow('本地文件夹', '浏览环境机器上的目录', !!this.environment()?.ready, () => this.startSource('local'))
      this.sourceRow('Git URL', '从远程 URL 克隆仓库', !!this.environment()?.ready && !!this.environment()?.client.canWriteSourceControl(),
        () => this.startSource('url'))
      Button(this.providers.length ? '刷新代码托管来源' : '检测代码托管来源').height(36).width('100%')
        .backgroundColor(Color.Transparent).fontColor($r('app.color.primary')).enabled(!this.busy)
        .onClick(() => this.loadProviders())
      ForEach(this.providers, (provider: ProviderRow) => {
        this.sourceRow(provider.label + ' 仓库',
          provider.ready ? '克隆 ' + provider.label + ' 仓库' :
            (provider.hint || '来源控制未安装或未登录'),
          !!this.environment()?.ready && provider.ready && !!this.environment()?.client.canWriteSourceControl(),
          () => this.startSource(provider.kind, provider.kind))
      }, (provider: ProviderRow) => provider.kind)
      if (!this.environment()?.ready) {
        Text('环境未连接，添加项目暂不可用。').fontSize(13).fontColor($r('app.color.muted')).width('100%')
        Button('管理环境与连接').height(44).width('100%').backgroundColor($r('app.color.surface'))
          .fontColor($r('app.color.ink')).onClick(this.onEnvironments)
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
  @Builder
  newPage() {
    Column({ space: 12 }) {
      TextInput({ placeholder: '项目名称', text: this.name }).height(48).fontSize(15)
        .onChange((value: string) => this.name = value).accessibilityText('项目名称')
      if (this.environment()?.newProjectsRoot) {
        Text(this.name.trim() ? '将创建 ' + newProjectPathPreview(this.environment()?.newProjectsRoot || '', this.name) :
          '位于 ' + this.environment()?.newProjectsRoot)
          .fontSize(12).fontColor($r('app.color.muted')).width('100%')
      }
      if (this.providers.some((provider: ProviderRow) => provider.ready)) {
        Row() {
          Column({ space: 3 }) {
            Text('创建私有远程仓库').fontSize(14).fontWeight(FontWeight.Medium).width('100%')
            Text(this.publishKind || this.providers.find((provider: ProviderRow) => provider.ready)?.label || '')
              .fontSize(12).fontColor($r('app.color.muted')).width('100%')
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Toggle({ type: ToggleType.Switch, isOn: this.publishing })
            .onChange((value: boolean) => this.publishing = value)
        }.width('100%').padding(12).backgroundColor($r('app.color.surface')).borderRadius(12)
        if (this.publishing) {
          Select(this.providers.filter((provider: ProviderRow) => provider.ready)
            .map((provider: ProviderRow) => { return { value: provider.label } as SelectOption; }))
            .value(this.publishKind || this.providers.find((provider: ProviderRow) => provider.ready)?.label || '')
            .onSelect((index: number) => {
              const ready = this.providers.filter((provider: ProviderRow) => provider.ready);
              this.publishKind = ready[index]?.kind || '';
            }).width('100%').height(40).font({ size: 13 })
        }
      }
      Button(this.busy ? '创建中…' : '创建项目').height(48).width('100%')
        .backgroundColor($r('app.color.primary')).fontColor($r('app.color.on_primary'))
        .enabled(!this.busy && !!this.name.trim()).onClick(() => void this.createNew())
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
  @Builder
  localPage() {
    Column({ space: 10 }) {
      TextInput({ placeholder: '~/projects/my-app', text: this.pathInput }).height(48).fontSize(14)
        .onChange((value: string) => this.pathInput = value).accessibilityText('项目目录')
      Row({ space: 8 }) {
        Button(this.busy ? '添加中…' : '添加项目').height(44).layoutWeight(1)
          .backgroundColor($r('app.color.primary')).fontColor($r('app.color.on_primary'))
          .enabled(!this.busy && !!this.environment()?.ready).onClick(() => void this.createLocal())
        Button('刷新目录').height(44).layoutWeight(1).backgroundColor($r('app.color.surface'))
          .fontColor($r('app.color.ink')).onClick(() => void this.loadBrowse())
      }.width('100%')
      Text('浏览文件夹').fontSize(12).fontColor($r('app.color.muted')).width('100%')
      this.browseList()
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
  @Builder
  repositoryPage() {
    Column({ space: 10 }) {
      TextInput({
        placeholder: this.source === 'url' ? 'https://example.com/org/repo.git' : this.provider + ' owner/repository',
        text: this.repositoryInput
      }).height(48).fontSize(14).onChange((value: string) => this.repositoryInput = value)
        .accessibilityText('仓库地址')
      Button(this.busy ? '查询中…' : this.source === 'url' ? '继续' : '查询仓库').height(48).width('100%')
        .backgroundColor($r('app.color.primary')).fontColor($r('app.color.on_primary'))
        .enabled(!this.busy && !!this.repositoryInput.trim()).onClick(() => void this.continueRepository())
      if (this.source === 'url') {
        Text('支持 owner/repo 简写和 GitHub 页面 URL；不会自动读取凭据。')
          .fontSize(12).fontColor($r('app.color.muted')).width('100%')
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
  @Builder
  destinationPage() {
    Column({ space: 10 }) {
      if (this.repositoryTitle) {
        Column({ space: 3 }) {
          Text(this.repositoryTitle).fontSize(15).fontWeight(FontWeight.Medium).width('100%')
          Text(this.remoteUrl).fontSize(11).fontColor($r('app.color.muted')).maxLines(2).width('100%')
        }.width('100%').padding(12).backgroundColor($r('app.color.surface')).borderRadius(12)
      }
      TextInput({ placeholder: '克隆目标目录', text: this.pathInput }).height(48).fontSize(14)
        .onChange((value: string) => this.pathInput = value).accessibilityText('克隆目标目录')
      Row({ space: 8 }) {
        Button(this.busy ? '克隆中…' : '克隆项目').height(44).layoutWeight(1)
          .backgroundColor($r('app.color.primary')).fontColor($r('app.color.on_primary'))
          .enabled(!this.busy && !!this.remoteUrl && !!this.environment()?.ready).onClick(() => void this.cloneProject())
        Button('刷新目录').height(44).layoutWeight(1).backgroundColor($r('app.color.surface'))
          .fontColor($r('app.color.ink')).onClick(() => void this.loadBrowse())
      }.width('100%')
      if (this.cloneStatus) {
        Text(this.cloneStatus).fontSize(13).fontColor(this.clone?.error ? $r('app.color.danger') : $r('app.color.muted')).width('100%')
      }
      if (this.clone && (this.clone.phase === 'running' || this.clone.phase === 'failed' || !!this.clone.error)) {
        Row({ space: 8 }) {
          if (this.clone.phase === 'running') {
            Button('取消克隆').height(40).layoutWeight(1).backgroundColor($r('app.color.surface'))
              .fontColor($r('app.color.danger')).onClick(() => {
                const environment = this.environment();
                if (environment) void environment.client.cancelProjectClone(this.cloneProjectId).then(() => this.cloneStatus = '已请求取消').catch((error: Error) => this.error = error.message);
              })
          }
          if (this.clone.phase === 'failed' || !!this.clone.error) {
            Button('重试克隆').height(40).layoutWeight(1).backgroundColor($r('app.color.surface'))
              .fontColor($r('app.color.ink')).onClick(() => {
                const environment = this.environment();
                if (environment) void environment.client.retryProjectClone(this.cloneProjectId).then(() => this.cloneStatus = '已请求重试').catch((error: Error) => this.error = error.message);
              })
          }
        }.width('100%')
      }
      Text('浏览目标文件夹').fontSize(12).fontColor($r('app.color.muted')).width('100%')
      this.browseList()
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: 0 }) {
      Row({ space: 6 }) {
        Button('‹').width(44).height(44).backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
          .fontSize(26).accessibilityText('返回').onClick(() => this.back())
        Text(this.step === 'source' ? '添加项目' : this.step === 'new' ? '新建项目' :
          this.step === 'local' ? '本地文件夹' : this.step === 'repository' ?
            (this.source === 'url' ? 'Git URL' : this.provider + ' 仓库') : '克隆目标')
          .fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
      }.width('100%').padding({ left: 8, right: 12, top: 8, bottom: 6 })
      Scroll() {
        Column({ space: 12 }) {
          if (this.error) {
            Text(this.error).fontSize(13).fontColor($r('app.color.danger')).width('100%')
              .padding(12).backgroundColor($r('app.color.surface')).borderRadius(10)
          }
          if (this.step === 'source') this.sourcePage()
          else if (this.step === 'new') this.newPage()
          else if (this.step === 'local') this.localPage()
          else if (this.step === 'repository') this.repositoryPage()
          else this.destinationPage()
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 16, right: 16, bottom: 20 })
      }.width('100%').layoutWeight(1).align(Alignment.TopStart)
    }.width('100%').height('100%').foregroundColor($r('app.color.ink')).backgroundColor($r('app.color.canvas'))
  }
}
