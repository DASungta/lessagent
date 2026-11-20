import { TopBar } from './ui/TopBar';
import { GroupCard } from './ui/GroupCard';
import { FormRow } from './ui/FormRow';
import { AppButton } from './ui/AppButton';
import { StatusBadge } from './ui/StatusBadge';
import { FontSize, LineHeight, Radius, Sizes, Space, Weight } from '../common/Theme';
import { T3Client } from '../services/T3Client';
import { record } from '../protocol/Wire';
import { ProjectView, ScopedProject, ThreadView, isListedThread } from '../protocol/Projects';
import { validateTaskSettings } from '../protocol/Composer';
import { BranchView } from '../protocol/R4';
import { providerCatalog, ProviderView, ProviderModelView } from '../protocol/ProviderSettings';
import { ScheduledTaskView, ScheduleDraft, readScheduledTasks, scheduledTaskInput, mutateScheduledTask,
  scheduledTaskModelReplacementNeedsConfirmation, readScheduledWorkspaceOptions, ScheduledWorkspaceOptions,
  ScheduledWorkspaceSelectionError, ScheduledWorkspaceStrategy } from '../protocol/ScheduledTasks';

export function scheduleWeekdaySelection(current: string, day: number): string {
  const days = current ? current.split(',') : ['0', '1', '2', '3', '4', '5', '6'];
  const value = String(day);
  if (days.includes(value)) return days.length === 1 ? current : days.filter((item: string) => item !== value).join(',');
  return days.concat([value]).sort().join(',');
}

interface ScheduleActionInput { id: string; enabled?: boolean; }

@Component
export struct ScheduledTasksPanel {
  connection: T3Client | undefined = undefined;
  @Prop @Watch('connectionChanged') connectionKey: string = '';
  @Prop @Watch('projectsChanged') scopedProjects: ScopedProject[] = [];
  @Prop @Watch('projectsChanged') activeLocalId: string = '';
  onBack: () => void = () => {};
  @State tasks: ScheduledTaskView[] = [];
  @State providers: ProviderView[] = [];
  @State projects: ProjectView[] = [];
  @State selected: ScheduledTaskView | undefined = undefined;
  @State editor: boolean = false;
  @State titleInput: string = '';
  @State prompt: string = '';
  @State projectId: string = '';
  @State draftThreadId: string = '';
  @State threadCandidates: ThreadView[] = [];
  @State draftThreadMode: string = 'new_thread';
  @State targetConfirmation: string = '';
  @State workspaceType: string = 'root';
  @State workspaceBaseRef: string = '';
  @State workspaceOrigin: boolean = true;
  @State workspacePath: string = '';
  @State workspaceOptions: ScheduledWorkspaceOptions | undefined = undefined;
  @State workspaceQuery: string = '';
  @State workspaceAppliedQuery: string = '';
  @State workspaceFilterAvailable: boolean = false;
  @State workspaceLoading: boolean = false;
  @State workspaceError: string = '';
  @State instanceId: string = '';
  @State model: string = '';
  @State editingModel: boolean = false;
  @State modelConfirmation: string = '';
  @State scheduleType: string = 'fixed_time';
  @State time: string = '09:00';
  @State weekdays: string = '1,2,3,4,5';
  @State minutes: string = '15';
  @State timeZone: string = '';
  @State busy: boolean = false;
  @State needsRefresh: boolean = true;
  @State error: string = '';
  @State notice: string = '';
  @State confirmation: string = '';
  private pending: Object = {} as Record<string, Object>;
  private environmentId: string = '';
  private formLocalId: string = '';
  private formEnvironmentId: string = '';
  private alive: boolean = false;
  private requestEpoch: number = 0;
  private workspaceEpoch: number = 0;
  private workspaceVerifiedBaseRef: string = '';
  private workspaceVerifiedPath: string = '';
  private workspaceRefHint: string = '';
  private loadedOwner: T3Client | undefined = undefined;
  private loadedGeneration: number = -1;

  aboutToAppear(): void {
    this.alive = true;
    this.connectionChanged();
  }
  aboutToDisappear(): void { this.alive = false; this.requestEpoch++; this.invalidateWorkspaceOptions(); }
  private connectionChanged(): void {
    if (!this.alive) return;
    this.requestEpoch++;
    this.invalidateWorkspaceOptions();
    this.workspaceVerifiedBaseRef = ''; this.workspaceVerifiedPath = ''; this.workspaceRefHint = '';
    this.busy = false; this.needsRefresh = true;
    if (this.editor || this.confirmation) {
      this.error = '环境连接或权限已变化。当前表单已保留，提交前请放弃并刷新核对。';
    } else if (this.connection?.ready) {
      void this.refresh();
    } else {
      this.error = '正在等待当前环境连接，恢复后将自动刷新。';
    }
  }
  private writable(): boolean {
    const owner = this.connection;
    // Read observable flags first so ArkUI tracks the button even while the transport is offline.
    return !this.busy && !this.needsRefresh && !!owner?.ready && owner === this.loadedOwner &&
      owner.generationValue() === this.loadedGeneration && owner.canScope('orchestration:operate') !== false;
  }
  private requestRefresh(): void {
    if (!this.editor && !this.confirmation) { void this.refresh(); return; }
    const task = this.selected;
    AlertDialog.show({
      title: '放弃编辑并刷新？', message: '刷新会丢弃表单中尚未保存的修改。',
      primaryButton: { value: '继续编辑', action: () => {} },
      secondaryButton: { value: '放弃并刷新', action: () => {
        if (!this.alive || this.busy || (!this.editor && !this.confirmation) || this.selected !== task) return;
        this.invalidateWorkspaceOptions();
        this.editor = false; this.confirmation = ''; this.notice = '';
        void this.refresh();
      } }
    });
  }
  private async refresh(): Promise<void> {
    const owner = this.connection;
    if (!this.alive || !owner?.ready || this.busy || this.editor || this.confirmation) return;
    const environmentId = String(record(owner.config.environment).environmentId || '');
    const generation = owner.generationValue();
    const epoch = ++this.requestEpoch;
    const current = (): boolean => this.alive && this.requestEpoch === epoch && this.connection === owner &&
      owner.ready && owner.generationValue() === generation;
    this.busy = true; this.confirmation = '';
    try {
      const snapshot = await readScheduledTasks(owner, environmentId);
      if (!current()) return;
      this.providers = providerCatalog(owner.config, environmentId).filter((p: ProviderView) => p.enabled && p.installed && p.allowed);
      this.environmentId = environmentId;
      this.loadedOwner = owner; this.loadedGeneration = generation;
      this.tasks = snapshot.tasks; this.timeZone = snapshot.timeZone;
      this.projectsChanged();
      if (this.selected) this.selected = this.tasks.find((t: ScheduledTaskView) => t.id === this.selected?.id);
      this.needsRefresh = false; this.error = '';
    } catch (_) { if (current()) { this.error = '读取失败，请检查连接、权限或服务端能力后刷新'; this.needsRefresh = true; } }
    finally { if (current()) this.busy = false; }
  }
  private edit(task?: ScheduledTaskView): void {
    this.selected = task; this.editor = true; this.confirmation = ''; this.error = ''; this.notice = '';
    this.formLocalId = this.activeLocalId; this.formEnvironmentId = this.environmentId;
    this.titleInput = task?.title || ''; this.prompt = task?.prompt || '';
    this.projectId = task?.projectId || '';
    this.projects = [];
    this.projectsChanged();
    this.draftThreadId = '';
    this.threadCandidates = [];
    this.draftThreadMode = 'new_thread';
    this.targetConfirmation = '';
    this.editingModel = !task;
    this.modelConfirmation = '';
    this.resetModelChoice();
    this.resetWorkspace(task);
    const schedule = task ? record(task.schedule) : {} as Record<string, Object>;
    this.scheduleType = typeof schedule.type === 'string' ? schedule.type : 'fixed_time';
    this.time = typeof schedule.runAt === 'string' ? schedule.runAt : typeof schedule.timeOfDay === 'string' ? schedule.timeOfDay : '09:00';
    this.weekdays = Array.isArray(schedule.weekdays) && schedule.weekdays.length ? (schedule.weekdays as number[]).join(',') : '0,1,2,3,4,5,6';
    this.minutes = typeof schedule.everyMs === 'number' ? String(schedule.everyMs / 60000) : '15';
  }
  private invalidateWorkspaceOptions(): void {
    this.workspaceEpoch++;
    this.workspaceLoading = false; this.workspaceOptions = undefined; this.workspaceError = '';
  }
  private resetWorkspace(task?: ScheduledTaskView): void {
    this.invalidateWorkspaceOptions();
    this.workspaceQuery = ''; this.workspaceAppliedQuery = ''; this.workspaceFilterAvailable = false;
    this.workspaceVerifiedBaseRef = ''; this.workspaceVerifiedPath = ''; this.workspaceRefHint = '';
    const strategy = task ? record(task.workspaceStrategy) : undefined;
    this.workspaceType = typeof strategy?.type === 'string' ? strategy.type : 'root';
    this.workspaceBaseRef = typeof strategy?.baseRef === 'string' ? strategy.baseRef : '';
    this.workspacePath = typeof strategy?.worktreePath === 'string' ? strategy.worktreePath : '';
    this.workspaceOrigin = typeof strategy?.startFromOrigin === 'boolean' ? strategy.startFromOrigin : true;
    if (!task?.threadId && this.workspaceType !== 'root') void this.loadWorkspaceOptions();
  }
  private async loadWorkspaceOptions(): Promise<void> {
    const owner = this.connection;
    const projectId = this.projectId;
    if (!owner || !this.writable() || !projectId || !this.editor || this.draftThreadId || this.selected?.threadId ||
      (this.workspaceType !== 'worktree' && this.workspaceType !== 'existing_worktree')) return;
    const query = this.workspaceQuery.trim().slice(0, 256);
    this.invalidateWorkspaceOptions();
    this.workspaceAppliedQuery = query;
    const epoch = this.workspaceEpoch;
    const generation = owner.generationValue();
    const active = (): boolean => this.alive && this.editor && this.workspaceEpoch === epoch && this.connection === owner &&
      owner.generationValue() === generation && this.projectId === projectId && !this.draftThreadId && !this.selected?.threadId;
    this.workspaceLoading = true;
    try {
      const options = await readScheduledWorkspaceOptions(owner, this.environmentId, projectId, query);
      if (!active()) return;
      this.workspaceOptions = options;
      if (options.truncated) this.workspaceFilterAvailable = true;
      if (this.workspaceType === 'worktree' && !this.workspaceBaseRef && !query) {
        this.workspaceBaseRef = options.refs.find((ref: BranchView) => ref.isDefault && !ref.isRemote)?.name ||
          options.refs.find((ref: BranchView) => ref.current)?.name || '';
        this.workspaceVerifiedBaseRef = this.workspaceBaseRef;
      }
    } catch (_) {
      if (active()) this.workspaceError = '无法读取当前项目的分支或工作树。';
    } finally {
      if (active()) this.workspaceLoading = false;
    }
  }
  private selectWorkspace(index: number): void {
    const type = ['root', 'worktree', 'existing_worktree'][index];
    if (!type || type === this.workspaceType) return;
    this.workspaceType = type;
    this.invalidateWorkspaceOptions();
    if (type !== 'root') void this.loadWorkspaceOptions();
  }
  private selectWorkspaceBranch(index: number): void {
    const ref = this.workspaceOptions?.refs[index - 1];
    if (!ref) return;
    this.workspaceBaseRef = ref.name;
    this.workspaceVerifiedBaseRef = ref.name;
    if (ref.isRemote) this.workspaceOrigin = true;
  }
  private selectWorkspacePath(index: number): void {
    const path = this.workspaceOptions?.checkoutPaths[index - 1];
    if (!path) return;
    this.workspacePath = path;
    this.workspaceVerifiedPath = path;
    this.workspaceRefHint = this.workspaceOptions?.refs.find((ref: BranchView) => ref.worktreePath === path)?.name || '';
  }
  private draftWorkspace(): ScheduledWorkspaceStrategy | undefined {
    if (this.draftThreadId || this.selected?.threadId) return undefined;
    const saved = this.selected ? record(this.selected.workspaceStrategy) : undefined;
    if (!saved && this.workspaceType === 'root') return undefined;
    if (saved?.type === this.workspaceType &&
      (!['worktree', 'existing_worktree'].includes(this.workspaceType) ||
        (this.workspaceType === 'worktree' && (saved.baseRef || '') === this.workspaceBaseRef &&
          (typeof saved.startFromOrigin === 'boolean' ? saved.startFromOrigin : true) === this.workspaceOrigin) ||
        (this.workspaceType === 'existing_worktree' && saved.worktreePath === this.workspacePath))) return undefined;
    if (this.workspaceType === 'root') return { type: 'root' };
    if (this.workspaceType === 'worktree') {
      const ref = this.workspaceOptions?.refs.find((item: BranchView) => item.name === this.workspaceBaseRef);
      if (!ref && (!this.workspaceBaseRef || this.workspaceVerifiedBaseRef !== this.workspaceBaseRef)) {
        throw new Error('请选择当前项目中可用的基准分支。');
      }
      return { type: 'worktree', baseRef: this.workspaceBaseRef, startFromOrigin: ref?.isRemote === true || this.workspaceOrigin };
    }
    if (this.workspaceType === 'existing_worktree' && this.workspacePath &&
      (this.workspaceVerifiedPath === this.workspacePath || this.workspaceOptions?.checkoutPaths.includes(this.workspacePath))) {
      return { type: 'existing_worktree', worktreePath: this.workspacePath };
    }
    throw new Error('请选择当前项目中可用的工作树。');
  }
  private resetModelChoice(): void {
    const selection = this.selected ? record(this.selected.modelSelection) : undefined;
    this.instanceId = typeof selection?.instanceId === 'string' ? selection.instanceId :
      typeof selection?.provider === 'string' ? selection.provider : '';
    this.model = typeof selection?.model === 'string' ? selection.model : '';
  }
  private modelLabel(instanceId: string, model: string): string {
    const provider = this.providers.find((item: ProviderView) => item.id === instanceId);
    return (provider?.name || instanceId || '未知 Provider') + ' / ' +
      (provider?.models.find((item: ProviderModelView) => item.id === model)?.name || model || '未知模型');
  }
  private shownModel(task: ScheduledTaskView): string {
    if (task.threadId) {
      const thread = this.connection?.shell.threads.find(item => item.id === task.threadId);
      return thread?.model ? this.modelLabel(thread.providerInstanceId, thread.model) : '以绑定会话的当前模型为准';
    }
    const selection = record(task.modelSelection);
    return this.modelLabel(String(selection.instanceId || selection.provider || ''), String(selection.model || ''));
  }
  private projectOptions(): SelectOption[] {
    const options: SelectOption[] = [{ value: '请选择项目' }];
    const labels = new Map<string, string>();
    this.currentProjects().forEach((entry: ScopedProject) => { labels.set(entry.id, entry.label); });
    return options.concat(this.projects.map((p: ProjectView): SelectOption =>
      ({ value: labels.get(p.id) || p.label + '（不可用）' })));
  }
  private currentProjects(): ScopedProject[] {
    const owner = this.connection;
    if (!owner?.ready || owner !== this.loadedOwner || owner.generationValue() !== this.loadedGeneration || !this.activeLocalId ||
      this.activeLocalId !== this.formLocalId || this.environmentId !== this.formEnvironmentId) return [];
    return this.scopedProjects.filter((project: ScopedProject) => project.localId === this.activeLocalId &&
      project.environmentId === this.environmentId && !project.archivedAt && !project.isScratch);
  }
  private projectsChanged(): void {
    if (!this.alive || !this.editor || this.selected) return;
    const existing = new Set<string>(this.projects.map((project: ProjectView) => project.id));
    const added = this.currentProjects().filter((project: ScopedProject) => !existing.has(project.id));
    // Keep the Select indices stable for the lifetime of the form.
    if (added.length) this.projects = this.projects.concat(added);
  }
  private selectProject(index: number): void {
    const projectId = this.projects[index - 1]?.id || '';
    if (index > 0 && (!projectId || !this.currentProjects().some((project: ScopedProject) => project.id === projectId))) {
      this.error = '所选项目已不可用，请重新选择。';
      return;
    }
    if (projectId === this.projectId) return;
    this.projectId = projectId;
    this.error = '';
    this.resetWorkspace();
    this.draftThreadId = '';
    this.draftThreadMode = 'new_thread';
    this.threadCandidates = (this.connection?.shell.threads || [])
      .filter((thread: ThreadView) => this.isAvailableThread(thread))
      .sort((left: ThreadView, right: ThreadView): number => right.updatedAt.localeCompare(left.updatedAt));
  }
  private isAvailableThread(thread: ThreadView): boolean {
    return !!this.projectId && thread.projectId === this.projectId && !thread.archivedAt &&
      isListedThread(thread) && !!thread.providerInstanceId && !!thread.model;
  }
  private threadOptions(): SelectOption[] {
    return [{ value: this.supportsThreadModes() ? '首次运行时创建会话' : '每次新建会话' } as SelectOption].concat(this.threadCandidates
      .map((thread: ThreadView): SelectOption => ({ value: thread.label || '未命名会话' })));
  }
  private draftTarget(): ThreadView | undefined {
    return this.connection?.shell.threads.find((thread: ThreadView) =>
      thread.id === this.draftThreadId && this.isAvailableThread(thread));
  }
  private draftTargetModel(): string {
    const target = this.draftTarget();
    return target ? this.modelLabel(target.providerInstanceId, target.model) : '';
  }
  private selectThread(index: number): void {
    if (this.supportsThreadModes() && this.draftThreadMode === 'new_thread') return;
    const thread = this.threadCandidates[index - 1];
    if (index !== 0 && !thread) return;
    this.draftThreadId = thread?.id || '';
    this.invalidateWorkspaceOptions();
    if (!thread) void this.loadWorkspaceOptions();
    if (!this.supportsThreadModes()) this.draftThreadMode = thread ? 'continue' : 'new_thread';
    this.error = thread && !this.draftTarget() ? '所选会话已不可用，请重新选择。' : '';
  }
  private supportsThreadModes(): boolean {
    return this.connection?.supports('scheduledTaskThreadModes') === true;
  }
  private selectThreadMode(index: number): void {
    const value = ['new_thread', 'continue', 'fresh_session'][index];
    if (!value) return;
    this.draftThreadMode = value;
    if (value === 'new_thread' && this.draftThreadId) {
      this.draftThreadId = '';
      void this.loadWorkspaceOptions();
    }
  }
  private runModeLabel(mode: string): string {
    return mode === 'continue' ? '继续同一会话' : mode === 'fresh_session' ? '同一会话内每次使用新上下文' : '每次新建会话';
  }
  private targetLabel(threadId: string | null, mode: string): string {
    if (threadId) {
      const label = this.connection?.shell.threads.find((thread: ThreadView) => thread.id === threadId)?.label || '已绑定会话';
      return label + ' · ' + this.runModeLabel(mode);
    }
    return mode === 'new_thread' ? this.runModeLabel(mode) : '首次运行创建会话 · ' + this.runModeLabel(mode);
  }
  private providerOptions(): SelectOption[] {
    const options: SelectOption[] = [{ value: '请选择 Provider' }];
    return options.concat(this.providers.map((p: ProviderView): SelectOption => { return { value: p.name }; }));
  }
  private modelRows(): ProviderModelView[] {
    return this.providers.find((p: ProviderView) => p.id === this.instanceId)?.models || [];
  }
  private modelOptions(): SelectOption[] {
    const options: SelectOption[] = [{ value: '请选择模型' }];
    return options.concat(this.modelRows().map((m: ProviderModelView): SelectOption => { return { value: m.name }; }));
  }
  private weekdayLabel(day: number): string { return ['周日', '周一', '周二', '周三', '周四', '周五', '周六'][day]; }
  private prepareSave(): void {
    if (!this.writable()) return;
    try {
      const task = this.selected;
      const target = task ? undefined : this.draftTarget();
      if (!task && this.draftThreadId && (!target || this.draftThreadMode === 'new_thread')) {
        throw new Error('所选会话已不可用，请重新选择。');
      }
      if (!task && !this.currentProjects().some((p: ScopedProject) => p.id === this.projectId)) throw new Error('请选择当前环境的可用项目');
      const before = task ? record(task.modelSelection) : undefined;
      const modelChanged = !!task && !task.threadId && this.editingModel &&
        ((before?.instanceId || before?.provider) !== this.instanceId || before?.model !== this.model);
      const resetOptions = !!task && modelChanged && scheduledTaskModelReplacementNeedsConfirmation(task, this.instanceId, this.model);
      const draft: ScheduleDraft = { title: this.titleInput, prompt: this.prompt, projectId: this.projectId,
        instanceId: target?.providerInstanceId || this.instanceId, model: target?.model || this.model,
        type: this.scheduleType, time: this.time, weekdays: this.weekdays, minutes: this.minutes,
        modelChanged, confirmModelOptionsReset: resetOptions, threadId: target?.id || null,
        threadMode: this.draftThreadMode, supportsThreadModes: this.supportsThreadModes(),
        workspaceStrategy: this.draftWorkspace() };
      if ((!task && !target) || modelChanged) {
        if (!this.connection ||
          !this.providers.some((p: ProviderView) => p.id === this.instanceId && p.models.some((m: ProviderModelView) => m.id === this.model))) {
          throw new Error('请选择当前环境的项目与模型');
        }
        validateTaskSettings(this.connection.config, task?.projectId || this.projectId, {
          modelSelection: { instanceId: this.instanceId, model: this.model },
          runtimeMode: task?.runtimeMode || 'approval-required', interactionMode: task?.interactionMode || 'default'
        });
      }
      this.pending = scheduledTaskInput(draft, this.timeZone, task);
      this.targetConfirmation = '目标：' + this.targetLabel(task?.threadId || target?.id || null,
        task ? task.threadMode || (task.threadId ? 'continue' : 'new_thread') : this.draftThreadMode) +
        '\n调度：' + this.scheduleLabel(record(this.pending).schedule) +
        '\n工作区：' + (task?.threadId || target ? '绑定会话的工作区' : this.workspaceSummary(record(this.pending).workspaceStrategy));
      this.modelConfirmation = !task ? (target ? '模型：' + this.modelLabel(target.providerInstanceId, target.model) + '\n运行时使用绑定会话的当前模型。' :
        '模型：' + this.modelLabel(this.instanceId, this.model) + '，使用默认选项。') :
        modelChanged ? '原模型：' + this.shownModel(task) + '\n新模型：' + this.modelLabel(this.instanceId, this.model) +
          (resetOptions ? '\n确认后将清除原模型的专属选项，新模型使用默认选项。' : '\n新模型使用默认选项。') :
          task.threadId ? '模型：' + this.shownModel(task) + '\n任务继续使用绑定会话的当前模型。' :
            '模型：' + this.shownModel(task) + '\n保留原模型及专属选项。';
      this.confirmation = 'upsert'; this.error = '';
    } catch (error) { this.error = (error as Error).message; }
  }
  private prepareAction(action: string): void {
    if (!this.selected || !this.writable()) return;
    const input: ScheduleActionInput = action === 'delete' ? { id: this.selected.id } : { id: this.selected.id, enabled: !this.selected.enabled };
    this.pending = input;
    this.confirmation = action;
  }
  private async commit(): Promise<void> {
    if (!this.connection || !this.confirmation || !this.writable()) return;
    const action = this.confirmation;
    const owner = this.connection;
    const task = this.selected;
    const input = this.pending;
    const epoch = ++this.requestEpoch;
    const generation = owner.generationValue();
    const current = (): boolean => this.alive && this.requestEpoch === epoch && this.connection === owner &&
      owner.ready && owner.generationValue() === generation && this.selected === task && this.pending === input;
    this.confirmation = ''; this.busy = true;
    try {
      const snapshot = await mutateScheduledTask(owner, this.environmentId, action, input, task, current,
        this.workspaceVerifiedPath && this.workspaceVerifiedPath === this.workspacePath ? this.workspaceRefHint : undefined);
      if (!current()) return;
      this.tasks = snapshot.tasks; this.timeZone = snapshot.timeZone; this.editor = false;
      this.selected = undefined; this.error = ''; this.notice = action === 'delete' ? '已删除并回读确认' : '已保存并回读确认';
    } catch (reason) {
      if (!current()) return;
      if (reason instanceof ScheduledWorkspaceSelectionError) {
        this.error = reason.message;
        this.workspaceVerifiedPath = ''; this.workspaceVerifiedBaseRef = ''; this.workspaceRefHint = '';
        this.invalidateWorkspaceOptions();
        this.workspaceError = '请重新读取可用的分支与工作树。';
      } else {
        this.needsRefresh = true; this.error = '操作结果未确认，请刷新核对后再决定。不会自动重发。';
      }
    } finally {
      if (this.alive && this.requestEpoch === epoch && this.connection === owner && owner.generationValue() === generation) this.busy = false;
    }
  }
  private projectName(task: ScheduledTaskView): string {
    return this.connection?.shell.projects.find((project: ProjectView) => project.id === task.projectId)?.label || '未在当前项目列表中';
  }
  private workspaceLabel(task: ScheduledTaskView): string {
    if (task.threadId) return '绑定会话的工作区';
    return this.workspaceSummary(task.workspaceStrategy);
  }
  private workspaceSummary(value: Object): string {
    const strategy = record(value);
    if (strategy.type === 'root') return '项目根工作区';
    if (strategy.type === 'existing_worktree') return '已有工作树 · ' + String(strategy.worktreePath || '');
    if (strategy.type === 'worktree') return '新工作树 · ' + String(strategy.baseRef || '服务端默认分支') +
      (strategy.startFromOrigin === true ? ' · 尝试从远端更新起点' :
        strategy.startFromOrigin === false ? ' · 使用本地分支起点' : ' · 使用服务端默认起点');
    return '服务端工作区策略';
  }
  private runLabel(value: string): string {
    if (value === 'never') return '尚未运行';
    if (value === 'running') return '运行中';
    if (value === 'succeeded') return '已成功';
    if (value === 'failed') return '失败';
    return value;
  }
  private scheduleLabel(value: Object): string {
    const schedule = record(value);
    if (schedule.type === 'fixed_time') return String(schedule.timeOfDay) + ' · ' + (Array.isArray(schedule.weekdays) && schedule.weekdays.length && schedule.weekdays.length < 7 ? (schedule.weekdays as number[]).map((day: number) => this.weekdayLabel(day)).join('、') : '每天');
    if (schedule.type === 'interval') return '每 ' + String(Number(schedule.everyMs) / 60000) + ' 分钟';
    if (schedule.type === 'once') return '单次 ' + String(schedule.runAt);
    return 'Webhook / 其他调度（仅查看）';
  }
  build() {
    Column({ space: 0 }) {
      TopBar({
        title: this.confirmation ? '确认操作' : this.editor ? (this.selected ? '编辑定时任务' : '新建定时任务') :
          this.selected ? (this.selected.title || '任务详情') : '定时任务',
        showBack: true,
        backLabel: this.confirmation || this.editor || this.selected ? '返回' : '返回设置',
        onBack: () => {
          if (this.busy) return;
          if (this.confirmation) {
            this.confirmation = '';
          } else if (this.editor || this.selected) {
            this.invalidateWorkspaceOptions(); this.editor = false; this.selected = undefined; this.confirmation = '';
          } else this.onBack();
        }
      }) {
        if (!this.confirmation && !this.editor) {
          AppButton({
            label: '刷新',
            kind: 'text',
            disabled: this.busy,
            onTap: () => this.requestRefresh()
          })
        }
      }

      Scroll() {
        Column({ space: 0 }) {
          if (this.busy) {
            Text('正在同步…')
              .fontSize(FontSize.callout).lineHeight(LineHeight.callout).fontColor($r('app.color.muted'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs }).width('100%')
          }
          if (this.error && (!this.editor || this.confirmation)) {
            Column({ space: 4 }) {
              Text(this.error)
                .fontSize(FontSize.callout).lineHeight(LineHeight.callout).fontColor($r('app.color.danger')).width('100%')
            }
            .width('100%').padding(Space.sm).margin({ top: Space.xs })
            .backgroundColor($r('app.color.danger_bg')).borderRadius(Radius.button)
            .border({ width: Sizes.hairline, color: $r('app.color.danger_border') })
          }
          if (this.notice) {
            Text(this.notice)
              .fontSize(FontSize.callout).lineHeight(LineHeight.callout).fontColor($r('app.color.primary_text'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs }).width('100%')
          }

          if (this.confirmation) {
            GroupCard({
              title: '确认变更',
              footnote: this.confirmation === 'delete'
                ? '不会停止已经开始的运行。'
                : this.confirmation === 'setEnabled'
                  ? (this.selected?.enabled ? '停用后已开始的运行不会停止。' : '启用后服务端将按计划自动运行任务。')
                  : (this.selected?.enabled ? '此任务已启用，新计划将自动执行。' : '任务保持停用，启用需要另行确认。')
            }) {
              Column({ space: Space.xs }) {
                Text(this.confirmation === 'upsert' ? this.titleInput.trim() : this.selected?.title || '定时任务')
                  .fontSize(FontSize.headline).lineHeight(LineHeight.headline).fontWeight(Weight.semibold)
                  .fontColor($r('app.color.ink')).width('100%')
                Text(this.confirmation === 'delete' ? '确认永久删除此任务？'
                  : this.confirmation === 'setEnabled' ? (this.selected?.enabled ? '确认停用此定时任务？' : '确认启用此定时任务？')
                  : '确认保存此定时任务配置？')
                  .fontSize(FontSize.body).lineHeight(LineHeight.body).fontColor($r('app.color.ink')).width('100%')
                if (this.confirmation === 'upsert') {
                  Text(this.targetConfirmation)
                    .fontSize(FontSize.callout).lineHeight(LineHeight.callout).fontColor($r('app.color.muted'))
                    .width('100%').wordBreak(WordBreak.BREAK_ALL)
                  Text(this.modelConfirmation)
                    .fontSize(FontSize.callout).lineHeight(LineHeight.callout).fontColor($r('app.color.muted'))
                    .width('100%').wordBreak(WordBreak.BREAK_ALL)
                }
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
              .constraintSize({ minHeight: Sizes.formRowMin })
              .justifyContent(FlexAlign.Center)
            }
            Column({ space: Space.xs }) {
              AppButton({
                label: this.confirmation === 'upsert' ? (this.selected ? '保存修改' : '创建任务') :
                  this.confirmation === 'delete' ? '永久删除' : this.selected?.enabled ? '确认停用' : '确认启用',
                kind: this.confirmation === 'delete' ? 'danger' : 'primary',
                fill: true,
                disabled: !this.writable(),
                onTap: () => { void this.commit(); }
              })
              AppButton({
                label: '取消',
                kind: 'secondary',
                fill: true,
                disabled: this.busy,
                onTap: () => { this.confirmation = ''; }
              })
            }.width('100%').padding({ top: Space.md })

          } else if (this.editor) {
            GroupCard({ title: '内容' }) {
              Row({ space: 10 }) {
                Text('标题').fontSize(FontSize.body).fontColor($r('app.color.ink')).width(64).flexShrink(0)
                TextInput({ text: this.titleInput, placeholder: '任务标题' })
                  .layoutWeight(1).height(40).fontSize(FontSize.body).fontColor($r('app.color.ink'))
                  .placeholderColor($r('app.color.placeholder')).backgroundColor(Color.Transparent).padding(0)
                  .accessibilityText('标题')
                  .onChange((v: string) => { this.titleInput = v; })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
              .constraintSize({ minHeight: Sizes.formRowMin })
              Column() {
                TextArea({ text: this.prompt, placeholder: '任务执行内容' })
                  .width('100%').constraintSize({ minHeight: 96 }).fontSize(FontSize.body).lineHeight(LineHeight.body)
                  .fontColor($r('app.color.ink')).placeholderColor($r('app.color.placeholder'))
                  .backgroundColor(Color.Transparent).padding(0)
                  .accessibilityText('任务执行内容')
                  .onChange((v: string) => { this.prompt = v; })
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
              .constraintSize({ minHeight: Sizes.formRowMin })
              .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
            }

            GroupCard({
              title: '运行位置',
              footnote: !this.selected && !this.currentProjects().length
                ? '当前没有可用项目。项目同步后将自动显示。'
                : this.draftTarget()
                  ? '运行时使用绑定会话的当前模型：' + this.draftTargetModel()
                  : (!this.selected && !this.draftThreadId)
                    ? '每次新建会话默认采用需要审批的权限模式。'
                    : ''
            }) {
              if (!this.selected) {
                Row({ space: 10 }) {
                  Text('项目').fontSize(FontSize.body).fontColor($r('app.color.ink')).flexShrink(0)
                  Select(this.projectOptions()).layoutWeight(1).constraintSize({ minHeight: 38 })
                    .selected(this.projects.findIndex((p: ProjectView) => p.id === this.projectId) + 1)
                    .value(this.currentProjects().find((p: ScopedProject) => p.id === this.projectId)?.label ||
                      (this.projectId ? '所选项目不可用' : '请选择项目'))
                    .backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
                    .onSelect((index: number) => this.selectProject(index))
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
                .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
                .constraintSize({ minHeight: Sizes.formRowMin })
                if (this.supportsThreadModes()) {
                  Row({ space: 10 }) {
                    Text('运行方式').fontSize(FontSize.body).fontColor($r('app.color.ink')).flexShrink(0)
                    Select([{ value: '每次新建会话' }, { value: '继续同一会话' }, { value: '同一会话内每次使用新上下文' }])
                      .layoutWeight(1).constraintSize({ minHeight: 38 }).enabled(!!this.projectId && this.writable())
                      .selected(['new_thread', 'continue', 'fresh_session'].indexOf(this.draftThreadMode))
                      .value(this.runModeLabel(this.draftThreadMode))
                      .backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
                      .onSelect((index: number) => this.selectThreadMode(index))
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)
                  .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
                  .constraintSize({ minHeight: Sizes.formRowMin })
                  .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
                }
                if (!this.supportsThreadModes() || this.draftThreadMode !== 'new_thread') {
                  Column({ space: 4 }) {
                    Row({ space: 10 }) {
                      Text('目标会话').fontSize(FontSize.body).fontColor($r('app.color.ink')).flexShrink(0)
                      Select(this.threadOptions()).layoutWeight(1).constraintSize({ minHeight: 38 })
                        .enabled(!!this.projectId && (this.threadCandidates.length > 0 || !!this.draftThreadId) && this.writable())
                        .selected(this.threadCandidates.findIndex((thread: ThreadView) => thread.id === this.draftThreadId) + 1)
                        .value(this.draftTarget()?.label || (this.draftThreadId ? '所选会话不可用' :
                          this.supportsThreadModes() ? '首次运行时创建会话' : '每次新建会话'))
                        .backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
                        .onSelect((index: number) => this.selectThread(index))
                    }.width('100%').alignItems(VerticalAlign.Center)
                    if (this.projectId && !this.threadCandidates.length) {
                      Text('该项目没有可绑定的会话。').fontSize(FontSize.caption).fontColor($r('app.color.muted')).width('100%')
                    }
                  }
                  .width('100%')
                  .alignItems(HorizontalAlign.Start)
                  .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
                  .constraintSize({ minHeight: Sizes.formRowMin })
                  .justifyContent(FlexAlign.Center)
                  .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
                }
              } else {
                FormRow({
                  kind: 'value',
                  label: '当前模型',
                  value: this.shownModel(this.selected),
                  subtitle: this.selected.threadId ? '任务绑定会话，运行时使用该会话的当前模型。' : '',
                  chevron: !this.selected.threadId,
                  disabled: !!this.selected.threadId || !this.writable(),
                  isFirst: true,
                  onTap: () => {
                    if (!this.selected?.threadId && this.writable()) {
                      this.resetModelChoice();
                      this.editingModel = !this.editingModel;
                    }
                  }
                })
              }

              if (this.editingModel && !this.selected?.threadId && !this.draftThreadId) {
                Row({ space: 10 }) {
                  Text('Provider').fontSize(FontSize.body).fontColor($r('app.color.ink')).flexShrink(0)
                  Select(this.providerOptions()).layoutWeight(1).constraintSize({ minHeight: 38 }).enabled(this.writable())
                    .selected(this.providers.findIndex((p: ProviderView) => p.id === this.instanceId) + 1)
                    .value(this.providers.find((p: ProviderView) => p.id === this.instanceId)?.name || '请选择 Provider')
                    .backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
                    .onSelect((index: number) => {
                      const id = this.providers[index - 1]?.id || '';
                      if (id !== this.instanceId) { this.instanceId = id; this.model = ''; }
                    })
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
                .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
                .constraintSize({ minHeight: Sizes.formRowMin })
                .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
                Row({ space: 10 }) {
                  Text('模型').fontSize(FontSize.body).fontColor($r('app.color.ink')).flexShrink(0)
                  Select(this.modelOptions()).layoutWeight(1).constraintSize({ minHeight: 38 }).enabled(this.writable() && !!this.instanceId)
                    .selected(this.modelRows().findIndex((m: ProviderModelView) => m.id === this.model) + 1)
                    .value(this.modelRows().find((m: ProviderModelView) => m.id === this.model)?.name || '请选择模型')
                    .backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
                    .onSelect((index: number) => { this.model = this.modelRows()[index - 1]?.id || ''; })
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
                .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
                .constraintSize({ minHeight: Sizes.formRowMin })
                .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
              }

              if (this.selected?.threadId || this.draftThreadId) {
                FormRow({
                  kind: 'value',
                  label: '工作区',
                  value: '绑定会话的工作区',
                  valueMuted: true,
                  chevron: false,
                  isFirst: false
                })
              } else {
                Row({ space: 10 }) {
                  Text('工作区').fontSize(FontSize.body).fontColor($r('app.color.ink')).flexShrink(0)
                  Select([{ value: '项目根工作区' }, { value: '新工作树' }, { value: '已有工作树' }])
                    .layoutWeight(1).constraintSize({ minHeight: 38 }).enabled(!!this.projectId && this.writable())
                    .selected(['root', 'worktree', 'existing_worktree'].indexOf(this.workspaceType))
                    .value(this.workspaceType === 'root' ? '项目根工作区' : this.workspaceType === 'worktree' ? '新工作树' :
                      this.workspaceType === 'existing_worktree' ? '已有工作树' : '服务端工作区策略')
                    .backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
                    .onSelect((index: number) => this.selectWorkspace(index))
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
                .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
                .constraintSize({ minHeight: Sizes.formRowMin })
                .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
                if (this.workspaceType === 'worktree' || this.workspaceType === 'existing_worktree') {
                  if (this.workspaceFilterAvailable || this.workspaceQuery) {
                    Row({ space: Space.xs }) {
                      TextInput({ text: this.workspaceQuery, placeholder: '按分支名筛选' })
                        .layoutWeight(1).height(40).fontSize(FontSize.body).fontColor($r('app.color.ink'))
                        .placeholderColor($r('app.color.placeholder')).backgroundColor(Color.Transparent).padding(0)
                        .maxLength(256).accessibilityText('按分支名筛选')
                        .onChange((query: string) => { this.workspaceQuery = query; })
                        .onSubmit(() => { void this.loadWorkspaceOptions(); })
                      AppButton({
                        label: this.workspaceQuery.trim() ? '筛选' : '读取候选',
                        kind: 'secondary',
                        compact: true,
                        disabled: !this.writable(),
                        onTap: () => { void this.loadWorkspaceOptions(); }
                      })
                    }
                    .width('100%')
                    .alignItems(VerticalAlign.Center)
                    .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
                    .constraintSize({ minHeight: Sizes.formRowMin })
                    .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
                  }
                  if (this.workspaceLoading || this.workspaceError || this.workspaceOptions?.isRepo === false ||
                    this.workspaceOptions?.truncated || (this.workspaceOptions && this.workspaceAppliedQuery)) {
                    Column({ space: 4 }) {
                      if (this.workspaceLoading) {
                        Text('正在读取项目分支与工作树…').fontSize(FontSize.caption).fontColor($r('app.color.muted'))
                      } else if (this.workspaceError) {
                        Row({ space: Space.xs }) {
                          Text(this.workspaceError).fontSize(FontSize.caption).fontColor($r('app.color.danger')).layoutWeight(1)
                          AppButton({
                            label: '重新读取', kind: 'text', disabled: !this.writable(),
                            onTap: () => { void this.loadWorkspaceOptions(); }
                          })
                        }.width('100%').alignItems(VerticalAlign.Center)
                      } else if (this.workspaceOptions?.isRepo === false) {
                        Text('当前项目不是 Git 仓库，请选择项目根工作区。').fontSize(FontSize.caption).fontColor($r('app.color.muted'))
                      }
                      if (this.workspaceOptions?.truncated) {
                        Text('只显示部分候选，请按分支名缩小范围。').fontSize(FontSize.caption).fontColor($r('app.color.muted'))
                      } else if (this.workspaceOptions && this.workspaceAppliedQuery) {
                        Text('分支筛选 · ' + this.workspaceAppliedQuery).fontSize(FontSize.caption).fontColor($r('app.color.muted'))
                          .wordBreak(WordBreak.BREAK_ALL)
                      }
                    }
                    .width('100%')
                    .alignItems(HorizontalAlign.Start)
                    .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
                    .constraintSize({ minHeight: Sizes.formRowMin })
                    .justifyContent(FlexAlign.Center)
                    .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
                  }
                  if (this.workspaceType === 'worktree') {
                    Column({ space: 4 }) {
                      Row({ space: 10 }) {
                        Text('基准分支').fontSize(FontSize.body).fontColor($r('app.color.ink')).flexShrink(0)
                        Select([{ value: '请选择基准分支' } as SelectOption].concat((this.workspaceOptions?.refs || [])
                          .map((ref: BranchView): SelectOption => ({ value: ref.name }))))
                          .layoutWeight(1).constraintSize({ minHeight: 38 }).value(this.workspaceBaseRef || '请选择基准分支')
                          .enabled(!!this.workspaceOptions?.refs.length && this.writable())
                          .backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
                          .onSelect((index: number) => this.selectWorkspaceBranch(index))
                      }.width('100%').alignItems(VerticalAlign.Center)
                      if (this.workspaceOptions?.isRepo && !this.workspaceOptions.refs.length) {
                        Text(this.workspaceAppliedQuery ? '未找到匹配的分支。' : '当前项目没有可选分支。')
                          .fontSize(FontSize.caption).fontColor($r('app.color.muted')).width('100%')
                      }
                    }
                    .width('100%')
                    .alignItems(HorizontalAlign.Start)
                    .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
                    .constraintSize({ minHeight: Sizes.formRowMin })
                    .justifyContent(FlexAlign.Center)
                    .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
                    FormRow({
                      kind: 'switch',
                      label: '从远端更新起点',
                      checked: this.workspaceOrigin,
                      disabled: !(this.writable() &&
                        (this.workspaceOptions?.refs.some((ref: BranchView) => ref.name === this.workspaceBaseRef && !ref.isRemote) === true ||
                          (!!this.workspaceBaseRef && this.workspaceVerifiedBaseRef === this.workspaceBaseRef))),
                      isFirst: false,
                      onToggle: (on: boolean) => { this.workspaceOrigin = on; }
                    })
                  } else {
                    Column({ space: 4 }) {
                      Row({ space: 10 }) {
                        Text('现有工作树').fontSize(FontSize.body).fontColor($r('app.color.ink')).flexShrink(0)
                        Select([{ value: '请选择工作树' } as SelectOption].concat((this.workspaceOptions?.checkoutPaths || [])
                          .map((path: string): SelectOption => ({ value: path }))))
                          .layoutWeight(1).constraintSize({ minHeight: 38 }).value(this.workspacePath || '请选择工作树')
                          .enabled(!!this.workspaceOptions?.checkoutPaths.length && this.writable())
                          .backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
                          .onSelect((index: number) => this.selectWorkspacePath(index))
                      }.width('100%').alignItems(VerticalAlign.Center)
                      if (this.workspacePath) {
                        Text(this.workspacePath).fontSize(FontSize.caption).fontColor($r('app.color.muted'))
                          .width('100%').wordBreak(WordBreak.BREAK_ALL)
                      }
                      if (this.workspaceOptions?.isRepo && !this.workspaceOptions.checkoutPaths.length) {
                        Text(this.workspaceAppliedQuery ? '匹配的分支没有已有工作树。' : '当前项目没有可选的已有工作树。')
                          .fontSize(FontSize.caption).fontColor($r('app.color.muted')).width('100%')
                      }
                    }
                    .width('100%')
                    .alignItems(HorizontalAlign.Start)
                    .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
                    .constraintSize({ minHeight: Sizes.formRowMin })
                    .justifyContent(FlexAlign.Center)
                    .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
                  }
                }
              }
            }

            GroupCard({
              title: '调度' + (this.scheduleType === 'fixed_time' ? ' · ' + (this.timeZone || '服务端时区') : '')
            }) {
              Row({ space: 8 }) {
                Text('方式').fontSize(FontSize.body).fontColor($r('app.color.ink')).flexShrink(0)
                Blank()
                Row({ space: 2 }) {
                  Button('固定时间')
                    .fontSize(FontSize.callout)
                    .fontWeight(this.scheduleType === 'fixed_time' ? Weight.medium : Weight.regular)
                    .fontColor(this.scheduleType === 'fixed_time' ? $r('app.color.ink') : $r('app.color.muted'))
                    .backgroundColor(this.scheduleType === 'fixed_time' ? $r('app.color.card') : Color.Transparent)
                    .borderRadius(7).constraintSize({ minHeight: 30 }).padding({ left: 10, right: 10 })
                    .onClick(() => { this.scheduleType = 'fixed_time'; this.time = '09:00'; })
                  Button('间隔')
                    .fontSize(FontSize.callout)
                    .fontWeight(this.scheduleType === 'interval' ? Weight.medium : Weight.regular)
                    .fontColor(this.scheduleType === 'interval' ? $r('app.color.ink') : $r('app.color.muted'))
                    .backgroundColor(this.scheduleType === 'interval' ? $r('app.color.card') : Color.Transparent)
                    .borderRadius(7).constraintSize({ minHeight: 30 }).padding({ left: 10, right: 10 })
                    .onClick(() => { this.scheduleType = 'interval'; this.time = '09:00'; })
                  Button('单次')
                    .fontSize(FontSize.callout)
                    .fontWeight(this.scheduleType === 'once' ? Weight.medium : Weight.regular)
                    .fontColor(this.scheduleType === 'once' ? $r('app.color.ink') : $r('app.color.muted'))
                    .backgroundColor(this.scheduleType === 'once' ? $r('app.color.card') : Color.Transparent)
                    .borderRadius(7).constraintSize({ minHeight: 30 }).padding({ left: 10, right: 10 })
                    .onClick(() => { this.scheduleType = 'once'; this.time = ''; })
                }.padding(2).backgroundColor($r('app.color.group')).borderRadius(9)
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
              .constraintSize({ minHeight: Sizes.formRowMin })

              if (this.scheduleType === 'interval') {
                Row({ space: 10 }) {
                  Text('间隔分钟').fontSize(FontSize.body).fontColor($r('app.color.ink')).flexShrink(0)
                  TextInput({ text: this.minutes, placeholder: '至少 1 分钟' })
                    .layoutWeight(1).height(40).fontSize(FontSize.body).textAlign(TextAlign.End)
                    .fontColor($r('app.color.ink')).placeholderColor($r('app.color.placeholder'))
                    .backgroundColor(Color.Transparent).padding(0)
                    .type(InputType.Number)
                    .accessibilityText('间隔分钟')
                    .onChange((v: string) => { this.minutes = v; })
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
                .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
                .constraintSize({ minHeight: Sizes.formRowMin })
                .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
              } else {
                Row({ space: 10 }) {
                  Text(this.scheduleType === 'once' ? '执行时间' : '本地时间')
                    .fontSize(FontSize.body).fontColor($r('app.color.ink')).flexShrink(0)
                  TextInput({
                    text: this.time,
                    placeholder: this.scheduleType === 'once' ? '2027-01-20T09:00:00+08:00' : 'HH:MM'
                  })
                    .layoutWeight(1).height(40).fontSize(FontSize.body).textAlign(TextAlign.End)
                    .fontColor($r('app.color.ink')).placeholderColor($r('app.color.placeholder'))
                    .backgroundColor(Color.Transparent).padding(0)
                    .accessibilityText(this.scheduleType === 'once' ? '单次执行时间' : '本地时间 HH:MM')
                    .onChange((v: string) => { this.time = v; })
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
                .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
                .constraintSize({ minHeight: Sizes.formRowMin })
                .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
                if (this.scheduleType === 'fixed_time') {
                  Column({ space: Space.xs }) {
                    Text('重复日期 · 至少选择一天')
                      .fontSize(FontSize.callout).fontColor($r('app.color.muted')).width('100%')
                    Flex({ wrap: FlexWrap.Wrap }) {
                      ForEach([1, 2, 3, 4, 5, 6, 0], (day: number) => {
                        Button(this.weekdayLabel(day))
                          .fontSize(FontSize.callout)
                          .fontWeight(this.weekdays.split(',').includes(String(day)) ? Weight.semibold : Weight.regular)
                          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                          .constraintSize({ minWidth: 42, minHeight: 36 }).margin({ right: 6, bottom: 6 })
                          .borderRadius(Radius.badge)
                          .backgroundColor(this.weekdays.split(',').includes(String(day)) ? $r('app.color.prominent') : $r('app.color.group'))
                          .fontColor(this.weekdays.split(',').includes(String(day)) ? $r('app.color.on_prominent') : $r('app.color.ink'))
                          .accessibilityText(this.weekdayLabel(day) + (this.weekdays.split(',').includes(String(day)) ? '，已选择' : '，未选择'))
                          .onClick(() => { this.weekdays = scheduleWeekdaySelection(this.weekdays, day); })
                      }, (day: number) => String(day))
                    }.width('100%')
                  }
                  .width('100%')
                  .alignItems(HorizontalAlign.Start)
                  .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
                  .constraintSize({ minHeight: Sizes.formRowMin })
                  .justifyContent(FlexAlign.Center)
                  .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
                }
              }
            }

          } else if (this.selected) {
            GroupCard() {
              Column({ space: Space.xs }) {
                Row({ space: Space.xs }) {
                  Text(this.selected.title)
                    .fontSize(FontSize.headline).lineHeight(LineHeight.headline).fontWeight(Weight.semibold)
                    .fontColor($r('app.color.ink')).layoutWeight(1)
                  StatusBadge({
                    text: this.selected.enabled ? '已启用' : '已停用',
                    tone: this.selected.enabled ? 'success' : 'neutral'
                  })
                }.width('100%').alignItems(VerticalAlign.Center)
                Text(this.scheduleLabel(this.selected.schedule) +
                  (record(this.selected.schedule).type === 'fixed_time' && this.timeZone ? ' · ' + this.timeZone : ''))
                  .fontSize(FontSize.callout).lineHeight(LineHeight.callout).fontColor($r('app.color.muted')).width('100%')
                Text(this.selected.prompt)
                  .fontSize(FontSize.body).lineHeight(LineHeight.body).fontColor($r('app.color.ink'))
                  .padding({ top: Space.xxs }).width('100%').copyOption(CopyOptions.InApp)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
              .constraintSize({ minHeight: Sizes.formRowMin })
              .justifyContent(FlexAlign.Center)
            }

            GroupCard({ title: '运行配置' }) {
              FormRow({ kind: 'value', label: '项目', value: this.projectName(this.selected), valueMuted: true, chevron: false, isFirst: true })
              FormRow({ kind: 'value', label: '模型', value: this.shownModel(this.selected), valueMuted: true, chevron: false })
              FormRow({
                kind: 'multiline',
                label: '会话与工作区',
                value: this.targetLabel(this.selected.threadId, this.selected.threadMode || (this.selected.threadId ? 'continue' : 'new_thread')) +
                  ' · ' + this.workspaceLabel(this.selected)
              })
              if (this.selected.nextRunAt) {
                FormRow({ kind: 'value', label: '下次运行', value: this.selected.nextRunAt, valueMuted: true, chevron: false })
              }
              FormRow({ kind: 'value', label: '最近运行', value: this.runLabel(this.selected.lastRunStatus), valueMuted: true, chevron: false })
            }

            if (this.selected.blocked) {
              Text('组织策略阻止此任务运行')
                .fontSize(FontSize.callout).fontColor($r('app.color.danger'))
                .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs }).width('100%')
            }

            Column({ space: Space.xs }) {
              AppButton({
                label: '编辑',
                kind: 'primary',
                fill: true,
                disabled: !(this.writable() && ['fixed_time', 'interval', 'once'].includes(String(record(this.selected.schedule).type))),
                onTap: () => { this.edit(this.selected); }
              })
              AppButton({
                label: this.selected.enabled ? '停用' : '启用',
                kind: 'secondary',
                fill: true,
                disabled: !(this.writable() && (!this.selected.blocked || this.selected.enabled)),
                onTap: () => { this.prepareAction('setEnabled'); }
              })
              AppButton({
                label: '删除',
                kind: 'danger',
                fill: true,
                disabled: !this.writable(),
                onTap: () => { this.prepareAction('delete'); }
              })
            }.width('100%').padding({ top: Space.md })

          } else {
            if (!this.tasks.length && !this.needsRefresh) {
              GroupCard() {
                Text('暂无定时任务')
                  .width('100%').textAlign(TextAlign.Center).padding({ top: Space.lg, bottom: Space.lg })
                  .fontSize(FontSize.body).fontColor($r('app.color.muted'))
              }
            } else if (this.tasks.length > 0) {
              GroupCard({ title: '已配置计划' }) {
                ForEach(this.tasks, (task: ScheduledTaskView, index: number) => {
                  Row({ space: 10 }) {
                    Column({ space: 3 }) {
                      Text(task.title)
                        .fontSize(FontSize.body).lineHeight(LineHeight.body).fontWeight(Weight.medium)
                        .fontColor($r('app.color.ink')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                      Text(this.projectName(task) + ' · ' + this.scheduleLabel(task.schedule))
                        .fontSize(FontSize.caption).lineHeight(LineHeight.caption)
                        .fontColor($r('app.color.muted')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                    StatusBadge({
                      text: task.enabled ? '启用' : '停用',
                      tone: task.enabled ? 'success' : 'neutral'
                    })
                    Image($r('app.media.ui_chevron_right')).width(Sizes.chevron).height(Sizes.chevron).opacity(0.6).accessibilityLevel('no')
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)
                  .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
                  .constraintSize({ minHeight: Sizes.formRowMin })
                  .border({ width: { top: index === 0 ? 0 : Sizes.hairline }, color: { top: $r('app.color.separator') } })
                  .onClick(() => {
                    this.selected = this.tasks.find((item: ScheduledTaskView) => item.id === task.id);
                    this.notice = '';
                  })
                }, (task: ScheduledTaskView) => task.id + ':' + task.updatedAt)
              }
            }
          }
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: Space.sm, right: Space.sm, bottom: Space.lg })
      }.width('100%').layoutWeight(1).align(Alignment.TopStart)

      if (this.editor && !this.confirmation) {
        Divider().strokeWidth(Sizes.hairline).color($r('app.color.separator'))
        Column({ space: Space.xs }) {
          if (this.error) {
            Text(this.error).fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.danger')).width('100%')
          }
          AppButton({
            label: '检查并保存',
            kind: 'primary',
            fill: true,
            disabled: !this.writable(),
            onTap: () => { this.prepareSave(); }
          })
        }.width('100%').padding({ left: Space.sm, right: Space.sm, top: Space.xs, bottom: Space.sm })
      } else if (!this.confirmation && !this.selected && !this.editor) {
        Column() {
          AppButton({
            label: '新建任务',
            kind: 'primary',
            fill: true,
            disabled: !this.writable(),
            onTap: () => { this.edit(); }
          })
        }.width('100%').padding({ left: Space.sm, right: Space.sm, top: Space.xs, bottom: Space.sm })
      }
    }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
  }
}
