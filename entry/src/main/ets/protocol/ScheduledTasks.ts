import { compactObjects, record, objects, text } from './Wire';
import { TaskSettings, validateTaskSettings } from './Composer';
import { BranchView, branches } from './R4';
import { samePath } from './Projects';

export interface ScheduledTaskView {
  id: string; title: string; prompt: string; enabled: boolean; schedule: Object;
  projectId: string; threadId: string | null; threadMode?: string;
  workspaceStrategy: Object; modelSelection: Object; runtimeMode: string; interactionMode: string;
  updatedAt: string; nextRunAt: string; lastRunStatus: string; blocked: boolean; creationSource?: string;
}
export interface ScheduledTaskSnapshot { tasks: ScheduledTaskView[]; timeZone: string; }
export interface ScheduleConnection {
  ready: boolean; config: Object;
  canScope(scope: string): boolean | undefined;
  generationValue?(): number;
  rpcRequest(method: string, payload: Object, timeoutMs?: number, fatalTimeout?: boolean): Promise<Object>;
  watchRpcStream(method: string, payload: Object, onItem: (value: Object) => void): (value: Object) => void;
  stopRpcStream(onItem: (value: Object) => void): void;
}
export interface ScheduledWorkspaceStrategy {
  type: string;
  baseRef?: string;
  startFromOrigin?: boolean;
  worktreePath?: string;
}
export interface ScheduledWorkspaceOptions { isRepo: boolean; refs: BranchView[]; checkoutPaths: string[]; truncated: boolean; }
export interface ScheduleDraft {
  title: string; prompt: string; projectId: string; instanceId: string; model: string;
  type: string; time: string; weekdays: string; minutes: string;
  modelChanged?: boolean; confirmModelOptionsReset?: boolean;
  threadId?: string | null; threadMode?: string; supportsThreadModes?: boolean;
  workspaceStrategy?: ScheduledWorkspaceStrategy;
}
function required(value: Object): string {
  const result = text(value).trim();
  if (!result) throw new Error('必填项不能为空');
  return result;
}
export function scheduleFromFields(type: string, time: string, days: string, minutes: string): Object {
  if (type === 'fixed_time') {
    if (!/^([01]?\d|2[0-3]):[0-5]\d$/.test(time)) throw new Error('时间格式应为 HH:MM');
    if (!/^[0-6](,[0-6])*$/.test(days)) throw new Error('星期需为 0 至 6，以逗号分隔');
    return { type, timeOfDay: time.padStart(5, '0'), weekdays: Array.from(new Set(days.split(',').map((day: string): number => Number(day)))).sort() };
  }
  if (type === 'interval') {
    const everyMs = Number(minutes) * 60000;
    if (!minutes.trim() || !Number.isSafeInteger(everyMs) || everyMs < 60000) throw new Error('间隔至少 1 分钟');
    return { type, everyMs };
  }
  if (type === 'once') {
    const match = /^(\d{4})-(\d{2})-(\d{2})T([01]\d|2[0-3]):[0-5]\d(:[0-5]\d(\.\d+)?)?(Z|[+-]\d{2}:\d{2})$/.exec(time);
    const timestamp = Date.parse(time);
    if (!match || !Number.isFinite(timestamp) || timestamp < Date.parse('0000-01-01T00:00:00Z') || timestamp >= Date.parse('+010000-01-01T00:00:00Z')) throw new Error('单次时间须包含日期及明确时区偏移');
    const y = Number(match[1]); const m = Number(match[2]); const d = Number(match[3]);
    const limits = [31, y % 4 === 0 && (y % 100 !== 0 || y % 400 === 0) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    if (m < 1 || m > 12 || d < 1 || d > limits[m - 1]) throw new Error('日期不存在');
    return { type, runAt: new Date(timestamp).toISOString() };
  }
  throw new Error('此调度类型仅可查看');
}
export function scheduleSnapshot(value: Object): ScheduledTaskSnapshot {
  const root = record(value); const seen: string[] = [];
  const tasks: ScheduledTaskView[] = [];
  for (const item of objects(root.tasks)) {
    try {
      const row = record(item); const id = required(row.id);
      if (seen.includes(id) || typeof row.enabled !== 'boolean') continue;
      const view: ScheduledTaskView = { id, title: required(row.title), prompt: required(row.prompt), enabled: row.enabled,
        schedule: record(row.schedule), projectId: required(row.projectId), threadId: row.threadId === null ? null : required(row.threadId),
        threadMode: row.threadMode === undefined ? undefined : text(row.threadMode), workspaceStrategy: record(row.workspaceStrategy),
        modelSelection: record(row.modelSelection), runtimeMode: required(row.runtimeMode), interactionMode: required(row.interactionMode),
        updatedAt: required(row.updatedAt), nextRunAt: typeof row.nextRunAt === 'string' ? row.nextRunAt : '',
        lastRunStatus: required(row.lastRunStatus), blocked: typeof row.blockedByPolicy === 'string',
        creationSource: typeof row.creationSource === 'string' ? row.creationSource : undefined };
      seen.push(id);
      tasks.push(view);
    } catch (_) {}
  }
  return { tasks, timeZone: typeof root.timeZone === 'string' ? root.timeZone : '' };
}
function checkConnection(connection: ScheduleConnection, environmentId: string, generation: number | undefined): void {
  if (!connection.ready || !environmentId || connection.generationValue?.() !== generation ||
    record(record(connection.config).environment).environmentId !== environmentId) throw new Error('环境已变化');
}
async function readScheduleFirst<T>(connection: ScheduleConnection, environmentId: string, method: string,
  parse: (value: Object) => T | undefined): Promise<T> {
  const generation = connection.generationValue?.();
  checkConnection(connection, environmentId, generation);
  return new Promise<T>((resolve, reject) => {
    let handle: ((value: Object) => void) | undefined = undefined;
    let done = false;
    const finish = (): void => {
      done = true; clearTimeout(timer);
      if (handle) connection.stopRpcStream(handle);
    };
    const timer = setTimeout(() => { finish(); reject(new Error('读取任务或目标会话超时')); }, 15000);
    try {
      handle = connection.watchRpcStream(method, {}, (value: Object): void => {
        if (done) return;
        try {
          checkConnection(connection, environmentId, generation);
          const result = parse(value);
          if (result !== undefined) { finish(); resolve(result); }
        } catch (error) { finish(); reject(error); }
      });
      if (done) connection.stopRpcStream(handle);
    } catch (error) { finish(); reject(error); }
  });
}

export async function readScheduledTasks(connection: ScheduleConnection, environmentId: string): Promise<ScheduledTaskSnapshot> {
  return readScheduleFirst(connection, environmentId, 'scheduledTasks.subscribe', scheduleSnapshot);
}

function creationThreadMode(threadId: string | null, input: Object | undefined, supports: boolean): string {
  const mode = input === undefined ? (threadId === null ? 'new_thread' : 'continue') : text(input);
  if (!['new_thread', 'continue', 'fresh_session'].includes(mode) || (threadId !== null && mode === 'new_thread')) {
    throw new Error('目标会话与任务模式不匹配');
  }
  if (!supports && mode !== (threadId === null ? 'new_thread' : 'continue')) throw new Error('当前服务不支持此任务模式');
  return mode;
}

async function verifyScheduleDestination(connection: ScheduleConnection, environmentId: string,
  payload: Record<string, Object>): Promise<string> {
  const projectId = required(payload.projectId);
  const threadId = payload.threadId === null ? null : required(payload.threadId);
  return readScheduleFirst(connection, environmentId, 'orchestration.subscribeShell', (value: Object): string | undefined => {
    const event = record(value);
    if (event.kind !== 'snapshot' || event.resolvedRepositoryIdentityRoots !== undefined) return undefined;
    const snapshot = record(event.snapshot);
    const project = compactObjects(snapshot.projects).find(item => item.id === projectId);
    if (!project || (project.archivedAt !== undefined && project.archivedAt !== null && project.archivedAt !== '')) {
      throw new Error('目标项目不存在或已归档');
    }
    const workspaceRoot = typeof project.workspaceRoot === 'string' ? project.workspaceRoot : '';
    if (threadId === null) return workspaceRoot;
    const thread = compactObjects(snapshot.threads).find(item => item.id === threadId);
    if (!thread || thread.projectId !== projectId ||
      (thread.archivedAt !== undefined && thread.archivedAt !== null && thread.archivedAt !== '') ||
      (thread.deletedAt !== undefined && thread.deletedAt !== null && thread.deletedAt !== '')) {
      throw new Error('目标会话不存在、已归档或不属于所选项目');
    }
    const lineage = thread.lineage === undefined || thread.lineage === null ? {} as Record<string, Object> : record(thread.lineage);
    if (lineage.relationshipToParent === 'subagent' || lineage.sideChat === true) throw new Error('此会话不可绑定');
    const savedModel = record(payload.modelSelection);
    if (thread.modelSelection === undefined || thread.modelSelection === null || Object.keys(savedModel).length !== 2 ||
      !sameScheduledModel(thread.modelSelection, required(savedModel.instanceId), required(savedModel.model))) {
      throw new Error('目标会话的模型已变化，请重新选择');
    }
    return workspaceRoot;
  });
}

function scheduledWorkspace(value: Object): ScheduledWorkspaceStrategy {
  const workspace = record(value);
  const keys = Object.keys(workspace);
  if (workspace.type === 'root' && keys.length === 1) return { type: 'root' };
  if (workspace.type === 'worktree' && keys.length === 3 && typeof workspace.startFromOrigin === 'boolean') {
    const baseRef = required(workspace.baseRef);
    if (!baseRef.startsWith('-') && baseRef.length <= 256 && !/[\x00-\x20\x7f]/.test(baseRef)) {
      return { type: 'worktree', baseRef, startFromOrigin: workspace.startFromOrigin };
    }
  }
  if (workspace.type === 'existing_worktree' && keys.length === 2) {
    const worktreePath = required(workspace.worktreePath);
    if (worktreePath.length <= 4096 && !/[\x00-\x1f\x7f]/.test(worktreePath) &&
      /^(?:\/|[A-Za-z]:[\\/]|\\\\)/.test(worktreePath)) {
      return { type: 'existing_worktree', worktreePath };
    }
  }
  throw new Error('工作区或工作树参数无效');
}

function isOtherCheckout(ref: BranchView, cwd: string): boolean {
  // Git may resolve a project symlink before reporting the current checkout path.
  return !ref.current && !!ref.worktreePath && !samePath(ref.worktreePath, cwd);
}

async function workspaceRefs(connection: ScheduleConnection, environmentId: string, cwd: string,
  query: string = '', match?: (ref: BranchView) => boolean): Promise<ScheduledWorkspaceOptions> {
  const generation = connection.generationValue?.();
  const refs: BranchView[] = [];
  const checkoutPaths: string[] = [];
  let cursor: number | undefined = undefined;
  if (!cwd.trim() || cwd.length > 4096 || /[\x00-\x1f\x7f]/.test(cwd)) throw new Error('项目工作目录不可用');
  const search = query.trim();
  if (search.length > 256 || /[\x00-\x1f\x7f]/.test(search)) throw new Error('分支搜索内容无效');
  for (let page = 0; page < 5; page++) {
    checkConnection(connection, environmentId, generation);
    if (connection.canScope('orchestration:read') === false) throw new Error('没有源码读取权限');
    const payload: Record<string, Object> = { cwd, limit: 200, refKind: 'local' };
    if (search) payload.query = search;
    if (cursor === undefined) payload.refresh = true; else payload.cursor = cursor;
    const reply = record(await connection.rpcRequest('vcs.listRefs', payload, 15000, false));
    checkConnection(connection, environmentId, generation);
    if (reply.isRepo === false) return { isRepo: false, refs: [], checkoutPaths: [], truncated: false };
    if (reply.isRepo !== true) throw new Error('服务未提供仓库状态');
    if (objects(reply.refs).length > 200) throw new Error('分支分页结果无效');
    for (const ref of branches(reply)) {
      if (ref.isRemote) continue;
      refs.push(ref);
      if (isOtherCheckout(ref, cwd) &&
        !checkoutPaths.some(path => samePath(path, ref.worktreePath))) checkoutPaths.push(ref.worktreePath);
    }
    if (reply.nextCursor === null) return { isRepo: true, refs, checkoutPaths, truncated: false };
    if (typeof reply.nextCursor !== 'number' || !Number.isSafeInteger(reply.nextCursor) ||
      reply.nextCursor <= (cursor ?? 0)) throw new Error('分支分页结果无效');
    if (match && refs.some(match)) break;
    cursor = reply.nextCursor;
  }
  return { isRepo: true, refs, checkoutPaths, truncated: true };
}

export async function readScheduledWorkspaceOptions(connection: ScheduleConnection, environmentId: string,
  projectId: string, query: string = ''): Promise<ScheduledWorkspaceOptions> {
  const generation = connection.generationValue?.();
  const cwd = await verifyScheduleDestination(connection, environmentId, { projectId, threadId: null });
  checkConnection(connection, environmentId, generation);
  return workspaceRefs(connection, environmentId, cwd, query);
}

export class ScheduledWorkspaceSelectionError extends Error {}

async function verifyWorkspaceStrategy(connection: ScheduleConnection, environmentId: string,
  projectId: Object, cwd: string, workspace: ScheduledWorkspaceStrategy, workspaceRefHint?: string): Promise<void> {
  if (workspace.type === 'root') return;
  const branch = workspace.type === 'worktree';
  const query = branch ? (workspace.baseRef ?? '') : (workspaceRefHint ?? '');
  const matches = (item: BranchView): boolean => branch ? item.name === workspace.baseRef :
    isOtherCheckout(item, cwd) && item.worktreePath === workspace.worktreePath;
  const choices = await workspaceRefs(connection, environmentId, cwd, query, matches);
  if (!choices.isRepo) throw new ScheduledWorkspaceSelectionError('当前项目不是可用的 Git 仓库');
  if (!choices.refs.some(matches)) {
    if (choices.truncated) throw new ScheduledWorkspaceSelectionError('分页上限内尚未覆盖所选目标，请按分支名缩小搜索');
    if (branch) throw new ScheduledWorkspaceSelectionError('基础分支已变化，请重新选择');
    if (query.trim()) throw new ScheduledWorkspaceSelectionError('匹配的分支中未找到所选工作树，请重新搜索选择');
    throw new ScheduledWorkspaceSelectionError('所选工作树已变化或不属于当前项目');
  }
  const currentRoot = await verifyScheduleDestination(connection, environmentId, { projectId, threadId: null });
  if (!samePath(cwd, currentRoot)) throw new ScheduledWorkspaceSelectionError('项目工作目录已变化，请重新选择');
}

function sameScheduledModel(selection: Object, instanceId: string, model: string): boolean {
  const saved = record(selection);
  return (saved.instanceId ?? saved.provider) === instanceId && saved.model === model;
}
export function scheduledTaskModelReplacementNeedsConfirmation(task: ScheduledTaskView, instanceId: string, model: string): boolean {
  if (sameScheduledModel(task.modelSelection, instanceId.trim(), model.trim())) return false;
  const options = record(task.modelSelection).options;
  if (options === undefined || options === null) return false;
  return typeof options !== 'object' || Object.keys(options).length > 0;
}
function scheduledModel(draft: ScheduleDraft, existing?: ScheduledTaskView): Object {
  if (existing && draft.modelChanged !== true) return existing.modelSelection;
  const instanceId = required(draft.instanceId);
  const model = required(draft.model);
  if (existing) {
    if (sameScheduledModel(existing.modelSelection, instanceId, model)) return existing.modelSelection;
    if (existing.threadId !== null) throw new Error('绑定会话使用该会话的当前模型，不能在这里修改');
    if (scheduledTaskModelReplacementNeedsConfirmation(existing, instanceId, model) && draft.confirmModelOptionsReset !== true) {
      throw new Error('切换模型会清除原模型选项，请确认后再保存');
    }
  }
  return { instanceId, model };
}

export function scheduledTaskInput(draft: ScheduleDraft, timeZone: string, existing?: ScheduledTaskView): Object {
  if (draft.type === 'fixed_time' && !timeZone) throw new Error('服务端未提供时区，暂不能保存固定时间');
  const threadId = existing ? existing.threadId : draft.threadId == null ? null : required(draft.threadId);
  if (threadId !== null && draft.workspaceStrategy !== undefined) throw new Error('绑定会话使用自己的工作区');
  const input: Record<string, Object> = {
    title: required(draft.title), prompt: required(draft.prompt), enabled: existing ? existing.enabled : false,
    projectId: existing ? existing.projectId : required(draft.projectId),
    threadId,
    workspaceStrategy: draft.workspaceStrategy === undefined
      ? (existing ? existing.workspaceStrategy : { type: 'root' }) : scheduledWorkspace(draft.workspaceStrategy),
    modelSelection: scheduledModel(draft, existing),
    runtimeMode: existing ? existing.runtimeMode : 'approval-required', interactionMode: existing ? existing.interactionMode : 'default',
    schedule: scheduleFromFields(draft.type, draft.time, draft.weekdays, draft.minutes)
  };
  if (existing) {
    if (!['fixed_time', 'interval', 'once'].includes(String(record(existing.schedule).type))) throw new Error('此调度类型请使用原客户端编辑');
    input.id = existing.id; input.requireExisting = true;
    if (existing.threadMode !== undefined) input.threadMode = existing.threadMode;
    if (existing.creationSource !== undefined) input.creationSource = existing.creationSource;
  } else {
    const mode = creationThreadMode(threadId, draft.threadMode, draft.supportsThreadModes === true);
    if (draft.supportsThreadModes === true) input.threadMode = mode;
    input.creationSource = 'mobile';
  }
  return input;
}
function requireCurrentTask(snapshot: ScheduledTaskSnapshot, expected: ScheduledTaskView): ScheduledTaskView {
  const current = snapshot.tasks.find((task: ScheduledTaskView): boolean => task.id === expected.id);
  if (!current || current.updatedAt !== expected.updatedAt || current.projectId !== expected.projectId ||
    current.threadId !== expected.threadId || JSON.stringify(current.modelSelection) !== JSON.stringify(expected.modelSelection) ||
    JSON.stringify(current.workspaceStrategy) !== JSON.stringify(expected.workspaceStrategy)) {
    throw new Error('任务已变化，请刷新');
  }
  return current;
}
export async function mutateScheduledTask(connection: ScheduleConnection, environmentId: string,
  action: string, input: Object, expected?: ScheduledTaskView,
  stillSelected: () => boolean = () => true, workspaceRefHint?: string): Promise<ScheduledTaskSnapshot> {
  const generation = connection.generationValue?.();
  const checkContext = (): void => {
    checkConnection(connection, environmentId, generation);
    if (!stillSelected()) throw new Error('当前任务或环境已变化');
    if (connection.canScope('orchestration:operate') === false) throw new Error('没有任务操作权限');
  };
  checkContext();
  if (!['upsert', 'setEnabled', 'delete'].includes(action)) throw new Error('不支持此操作');
  const before = await readScheduledTasks(connection, environmentId);
  const payload = record(input);
  if (expected) {
    const current = requireCurrentTask(before, expected);
    if (payload.id !== expected.id) throw new Error('任务已变化，请刷新');
    if (action === 'upsert') {
      if (payload.requireExisting !== true || payload.projectId !== current.projectId || payload.threadId !== current.threadId ||
        payload.enabled !== current.enabled || payload.runtimeMode !== current.runtimeMode ||
        payload.interactionMode !== current.interactionMode || payload.threadMode !== current.threadMode ||
        payload.creationSource !== current.creationSource) {
        throw new Error('编辑不能更改任务的目标、状态或运行设置');
      }
      if (JSON.stringify(payload.workspaceStrategy) !== JSON.stringify(current.workspaceStrategy)) {
        if (current.threadId !== null) throw new Error('绑定会话使用自己的工作区');
        if (connection.canScope('orchestration:operate') !== true) throw new Error('没有任务操作权限');
        const workspace = scheduledWorkspace(payload.workspaceStrategy);
        checkContext();
        const cwd = await verifyScheduleDestination(connection, environmentId, payload);
        checkContext();
        await verifyWorkspaceStrategy(connection, environmentId, payload.projectId, cwd, workspace, workspaceRefHint);
        requireCurrentTask(await readScheduledTasks(connection, environmentId), current);
        if (connection.canScope('orchestration:operate') !== true) throw new Error('没有任务操作权限');
      }
      if (JSON.stringify(payload.modelSelection) !== JSON.stringify(current.modelSelection)) {
        if (current.threadId !== null) throw new Error('绑定会话不能更改模型');
        if (connection.canScope('orchestration:operate') !== true) throw new Error('没有任务操作权限');
        const model = record(payload.modelSelection);
        if (Object.keys(model).length !== 2) throw new Error('新模型不能使用旧模型选项');
        const instanceId = required(model.instanceId);
        const slug = required(model.model);
        if (sameScheduledModel(current.modelSelection, instanceId, slug)) throw new Error('普通编辑必须保留原模型选项');
        checkContext();
        const config = record(await connection.rpcRequest('server.getConfig', {}, 15000, false));
        checkContext();
        if (record(config.environment).environmentId !== environmentId ||
          connection.canScope('orchestration:operate') !== true) throw new Error('模型所属环境或权限已变化');
        const settings: TaskSettings = { modelSelection: { instanceId, model: slug },
          runtimeMode: current.runtimeMode, interactionMode: current.interactionMode };
        validateTaskSettings(config, current.projectId, settings);
        requireCurrentTask(await readScheduledTasks(connection, environmentId), current);
        if (connection.canScope('orchestration:operate') !== true) throw new Error('没有任务操作权限');
      }
    }
  } else {
    if (action !== 'upsert' || payload.id !== undefined || payload.enabled !== false) throw new Error('新任务必须停用');
    const capabilities = record(connection.config).environment;
    const advertised = record(capabilities).capabilities;
    const supports = advertised !== undefined && advertised !== null && record(advertised).scheduledTaskThreadModes === true;
    if (payload.threadMode !== undefined && !supports) throw new Error('当前服务不支持指定任务模式');
    const threadId = payload.threadId === null ? null : required(payload.threadId);
    if (threadId !== null) {
      if (connection.canScope('orchestration:operate') !== true) throw new Error('没有任务操作权限');
      const workspace = record(payload.workspaceStrategy);
      if (payload.runtimeMode !== 'approval-required' || payload.interactionMode !== 'default' ||
        workspace.type !== 'root' || Object.keys(workspace).length !== 1) {
        throw new Error('新绑定任务需使用默认运行元数据');
      }
    }
    creationThreadMode(threadId, payload.threadMode, supports);
    checkContext();
    const workspace = scheduledWorkspace(payload.workspaceStrategy);
    const cwd = await verifyScheduleDestination(connection, environmentId, payload);
    checkContext();
    await verifyWorkspaceStrategy(connection, environmentId, payload.projectId, cwd, workspace, workspaceRefHint);
    if ((threadId !== null || workspace.type !== 'root') && connection.canScope('orchestration:operate') !== true) {
      throw new Error('没有任务操作权限');
    }
  }
  checkContext();
  const response = record(await connection.rpcRequest('scheduledTasks.' + action, payload, 15000, false));
  checkContext();
  const id = action === 'delete' ? required(response.id) : required(record(response.task).id);
  if (expected && id !== expected.id) throw new Error('回执任务不匹配');
  const after = await readScheduledTasks(connection, environmentId);
  checkContext();
  const saved = after.tasks.find((task: ScheduledTaskView) => task.id === id);
  if (action === 'delete') { if (saved) throw new Error('删除尚未确认'); }
  else {
    if (!saved || saved.enabled !== payload.enabled) throw new Error('任务状态尚未确认');
    if (action === 'upsert' && (saved.title !== payload.title || saved.prompt !== payload.prompt ||
      saved.projectId !== payload.projectId || saved.threadId !== payload.threadId || saved.runtimeMode !== payload.runtimeMode ||
      saved.interactionMode !== payload.interactionMode || JSON.stringify(saved.modelSelection) !== JSON.stringify(payload.modelSelection) ||
      JSON.stringify(saved.workspaceStrategy) !== JSON.stringify(payload.workspaceStrategy) ||
      (payload.threadMode !== undefined && saved.threadMode !== payload.threadMode) ||
      (!expected && payload.threadMode === undefined && saved.threadMode !== undefined &&
        saved.threadMode !== (payload.threadId === null ? 'new_thread' : 'continue')) ||
      (payload.creationSource !== undefined && saved.creationSource !== payload.creationSource) ||
      JSON.stringify(saved.schedule) !== JSON.stringify(payload.schedule))) throw new Error('保存尚未确认');
  }
  return after;
}
