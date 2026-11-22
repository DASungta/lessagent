import { compactArray, parseOptionSelections, record, text, objects } from './Wire';
import { ModelSelection, TaskSettings } from './Composer';

export const R4_MAX_INPUT_CHARS = 120000;
export const R4_MAX_ATTACHMENTS = 100;
export const R4_MAX_IMAGE_BYTES = 10 * 1024 * 1024;
export const R4_MAX_TOTAL_IMAGE_BYTES = 80 * 1024 * 1024;
export const R4_MAX_FILE_BYTES = 50 * 1024 * 1024;
export const R4_MAX_CONTEXT_RECORDS = 200;

export interface DraftAttachment {
  type: string;
  id: string;
  name: string;
  mimeType: string;
  sizeBytes: number;
}

export interface DraftWorkspace {
  mode: string;
  branch: string;
  worktreePath: string;
  startFromOrigin: boolean;
  repositories?: string[];
}

export interface ComposerContextRecord {
  version: number;
  kind: string;
  contextId: string;
  label: string;
  payload: Record<string, Object>;
}

export interface ComposerDraft {
  version: number;
  draftId: string;
  localId: string;
  environmentId: string;
  projectId: string;
  text: string;
  modelSelection: ModelSelection;
  modelCustomized?: boolean;
  runtimeMode: string;
  interactionMode: string;
  workspace: DraftWorkspace;
  attachments: DraftAttachment[];
  context: ComposerContextRecord[];
  updatedAt: number;
}

export function composerDraftLabel(draft: ComposerDraft): string {
  const text = draft.text.trim();
  if (text) return text;
  const first = draft.attachments[0];
  if (!first) return '未命名草稿';
  return draft.attachments.length === 1 ? first.name : first.name + ' 等 ' + draft.attachments.length + ' 个附件';
}

export function emptyWorkspace(): DraftWorkspace {
  return { mode: 'local', branch: '', worktreePath: '', startFromOrigin: true };
}

function safeToken(value: string, label: string, max: number): string {
  if (!value.trim() || value.length > max || /[\x00-\x1f]/.test(value)) throw new Error(label + '无效');
  return value;
}

export function attachmentRecord(value: Object): DraftAttachment {
  const row = record(value);
  const type = text(row.type);
  if (type !== 'file' && type !== 'image') throw new Error('附件类型无效');
  const id = text(row.id);
  const name = text(row.name);
  const mimeType = text(row.mimeType);
  if (!/^[a-z0-9_-]{1,128}$/i.test(id) || !name.trim() || name.length > 255 ||
    /[\x00-\x1f]/.test(name) || !mimeType.trim() || mimeType.length > 100) throw new Error('附件名称或标识无效');
  const sizeBytes = typeof row.sizeBytes === 'number' ? row.sizeBytes : -1;
  const limit = type === 'image' ? R4_MAX_IMAGE_BYTES : R4_MAX_FILE_BYTES;
  if (!Number.isSafeInteger(sizeBytes) || sizeBytes < 1 || sizeBytes > limit) throw new Error('附件大小无效');
  if (type === 'image' && !['image/gif', 'image/jpeg', 'image/png', 'image/webp'].includes(mimeType.toLowerCase())) {
    throw new Error('仅支持 GIF/JPEG/PNG/WebP 图片');
  }
  return { type, id, name, mimeType, sizeBytes };
}

export function attachmentLimitError(attachments: DraftAttachment[]): string {
  if (attachments.length > R4_MAX_ATTACHMENTS) return '每条消息最多 ' + R4_MAX_ATTACHMENTS + ' 个附件';
  let images = 0;
  for (const item of attachments) if (item.type === 'image') images += item.sizeBytes;
  if (images > R4_MAX_TOTAL_IMAGE_BYTES) return '图片总大小不能超过 80 MiB';
  return '';
}

export function uploadAttachmentTarget(value: Object, type: string, name: string, mimeType: string,
  sizeBytes: number): { path: string; attachment: DraftAttachment } {
  const attachment = attachmentRecord({ type, id: 'validation', name, mimeType, sizeBytes });
  const row = record(value);
  const path = text(row.relativeUrl);
  const id = text(row.attachmentId);
  if (!/^\/api\/attachments\/upload\/[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(path) || path.length > 4096 ||
    !/^[a-z0-9_-]{1,128}$/i.test(id) || typeof row.expiresAt !== 'number' || row.expiresAt <= Date.now()) {
    throw new Error('附件上传地址无效或已过期');
  }
  attachment.id = id;
  return { path, attachment };
}

export function contextRecord(value: Object): ComposerContextRecord {
  const row = record(value);
  const kind = text(row.kind);
  if (!/^[a-z][a-z0-9-]{0,39}$/.test(kind)) throw new Error('上下文类型无效');
  const contextId = text(row.contextId);
  if (!/^[a-z0-9_-]{1,128}$/i.test(contextId)) throw new Error('上下文标识无效');
  const label = text(row.label);
  if (label.length > 200) throw new Error('上下文标题过长');
  if (row.version !== 1) throw new Error('上下文版本无效');
  const payload: Record<string, Object> = {};
  for (const key of Object.keys(row)) {
    if (key !== 'version' && key !== 'kind' && key !== 'contextId' && key !== 'label') payload[key] = row[key];
  }
  if (JSON.stringify(payload).length > 64000) throw new Error('上下文过大');
  return { version: 1, kind, contextId, label, payload };
}

export function mentionContext(path: string, contextId: string): ComposerContextRecord {
  if (!path.trim() || path.length > 2048 || path.startsWith('/') || /[\x00-\x1f]/.test(path)) {
    throw new Error('文件引用必须是工作区相对路径');
  }
  return { version: 1, kind: 'mention', contextId, label: path, payload: { path } };
}

export function skillContext(name: string, contextId: string): ComposerContextRecord {
  safeToken(name, 'Skill 名称', 255);
  return { version: 1, kind: 'skill', contextId, label: name, payload: { name } };
}

export function terminalContext(terminalId: string, terminalLabel: string, lineStart: number,
  lineEnd: number, textValue: string, contextId: string): ComposerContextRecord {
  safeToken(terminalId, '终端标识', 255);
  safeToken(terminalLabel, '终端标题', 255);
  if (!Number.isSafeInteger(lineStart) || !Number.isSafeInteger(lineEnd) || lineStart < 0 || lineEnd < lineStart) {
    throw new Error('终端行范围无效');
  }
  if (textValue.length > 64000) throw new Error('终端引用过长');
  return { version: 1, kind: 'terminal', contextId, label: terminalLabel,
    payload: { terminalId, terminalLabel, lineStart, lineEnd, text: textValue } };
}

export function threadContext(environmentId: string, threadId: string, title: string,
  contextId: string): ComposerContextRecord {
  safeToken(environmentId, '环境标识', 128);
  safeToken(threadId, '会话标识', 128);
  return { version: 1, kind: 'thread', contextId, label: title.slice(0, 200),
    payload: { environmentId, threadId, title: title.slice(0, 200) } };
}

export function contextPayload(context: ComposerContextRecord[]): Object {
  if (context.length > R4_MAX_CONTEXT_RECORDS) throw new Error('上下文记录过多');
  if (new Set(context.map((item: ComposerContextRecord) => item.contextId)).size !== context.length) {
    throw new Error('上下文标识重复');
  }
  const records: Object[] = context.map((item: ComposerContextRecord) => {
    const row: Record<string, Object> = { version: 1, kind: item.kind, contextId: item.contextId, label: item.label };
    for (const key of Object.keys(item.payload)) row[key] = item.payload[key];
    return row;
  });
  if (JSON.stringify(records).length > 16000000) throw new Error('上下文总大小超限');
  return { version: 1, records };
}

export function composerDraft(value: Object): ComposerDraft {
  const row = record(value);
  if (row.version !== 1) throw new Error('草稿版本无效');
  const draftId = safeToken(text(row.draftId), '草稿标识', 128);
  const model = record(row.modelSelection);
  const options = parseOptionSelections(model.options);
  const modelSelection: ModelSelection = options.length > 0
    ? { instanceId: text(model.instanceId), model: text(model.model), options }
    : { instanceId: text(model.instanceId), model: text(model.model) };
  const workspace = record(row.workspace);
  const mode = text(workspace.mode);
  if (mode !== 'local' && mode !== 'worktree') throw new Error('工作区模式无效');
  let repositories: string[] | undefined = undefined;
  if (workspace.repositories !== undefined) {
    if (!Array.isArray(workspace.repositories)) throw new Error('工作区仓库列表无效');
    const seen = new Set<string>();
    repositories = [];
    for (const entry of workspace.repositories as Object[]) {
      if (typeof entry !== 'string' || !entry.trim() || entry.length > 2048 || /[\x00-\x1f]/.test(entry)) {
        throw new Error('工作区仓库路径无效');
      }
      const trimmed = entry.trim();
      if (!seen.has(trimmed)) {
        seen.add(trimmed);
        repositories.push(trimmed);
      }
    }
    if (repositories.length > 128) throw new Error('工作区仓库数量超限');
  }
  return {
    version: 1, draftId, localId: safeToken(text(row.localId), '本地环境标识', 128),
    environmentId: safeToken(text(row.environmentId), '环境标识', 128),
    projectId: safeToken(text(row.projectId), '项目标识', 128),
    text: text(row.text).slice(0, R4_MAX_INPUT_CHARS),
    modelSelection,
    ...(row.modelCustomized === true ? { modelCustomized: true } : {}),
    runtimeMode: text(row.runtimeMode), interactionMode: text(row.interactionMode),
    workspace: { mode, branch: text(workspace.branch), worktreePath: text(workspace.worktreePath),
      startFromOrigin: workspace.startFromOrigin !== false,
      ...(repositories !== undefined ? { repositories } : {}) },
    attachments: objects(row.attachments).map(attachmentRecord),
    context: objects(row.context).map(contextRecord),
    updatedAt: typeof row.updatedAt === 'number' ? row.updatedAt : Date.now()
  };
}

export function draftSettings(draft: ComposerDraft): TaskSettings {
  return { modelSelection: draft.modelSelection, runtimeMode: draft.runtimeMode,
    interactionMode: draft.interactionMode };
}

interface LaunchRepositoryEntry { path: string; }

export function launchWorkspace(draft: ComposerDraft, isGitRepo: boolean = true): Object {
  if (draft.workspace.mode === 'worktree') {
    const baseRef = draft.workspace.branch.trim() || (isGitRepo ? '' : 'HEAD');
    if (!baseRef) throw new Error('请选择新工作树的基础分支');
    const repos: LaunchRepositoryEntry[] | undefined = draft.workspace.repositories !== undefined
      ? draft.workspace.repositories.map((path: string): LaunchRepositoryEntry => ({ path }))
      : undefined;
    return {
      type: 'worktree',
      baseRef,
      startFromOrigin: draft.workspace.startFromOrigin,
      ...(repos !== undefined ? { repositories: repos } : {})
    };
  }
  if (draft.workspace.worktreePath.trim()) {
    return { type: 'existing_worktree', worktreePath: draft.workspace.worktreePath,
      ...(draft.workspace.branch.trim() ? { branch: draft.workspace.branch } : {}) };
  }
  return { type: 'root', ...(draft.workspace.branch.trim() ? { branch: draft.workspace.branch } : {}) };
}

export interface BranchView {
  name: string; isRemote: boolean; remoteName: string; current: boolean; isDefault: boolean;
  worktreePath: string;
}

export function switchDraftWorkspaceMode(workspace: DraftWorkspace, mode: string, refs: BranchView[]): DraftWorkspace {
  if (mode === workspace.mode) return workspace;
  if (mode !== 'worktree' && mode !== 'local') throw new Error('工作区模式无效');
  const branch = mode === 'worktree'
    ? workspace.branch || refs.find(ref => ref.isDefault)?.name || ''
    : refs.find(ref => ref.current)?.name || workspace.branch;
  return {
    mode, branch, worktreePath: '', startFromOrigin: workspace.startFromOrigin,
    ...(workspace.repositories !== undefined ? { repositories: workspace.repositories.slice() } : {})
  };
}

export function draftWorkspaceForBranch(workspace: DraftWorkspace, ref: BranchView): DraftWorkspace {
  if (ref.isRemote) {
    return {
      mode: 'worktree', branch: ref.name, worktreePath: '', startFromOrigin: true,
      ...(workspace.repositories !== undefined ? { repositories: workspace.repositories.slice() } : {})
    };
  }
  return {
    mode: 'local', branch: ref.name, worktreePath: ref.current ? '' : ref.worktreePath,
    startFromOrigin: workspace.startFromOrigin,
    ...(workspace.repositories !== undefined ? { repositories: workspace.repositories.slice() } : {})
  };
}

export function branches(value: Object): BranchView[] {
  const row = record(value);
  return compactArray(objects(row.refs), (item: Object): BranchView => {
    const ref = record(item);
    return { name: text(ref.name), isRemote: ref.isRemote === true,
      remoteName: typeof ref.remoteName === 'string' ? ref.remoteName : '',
      current: ref.current === true, isDefault: ref.isDefault === true,
      worktreePath: typeof ref.worktreePath === 'string' ? ref.worktreePath : '' };
  });
}

export function branchListInput(cwd: string, query: string): Object {
  safeToken(cwd, '工作目录', 4096);
  const trimmed = query.trim().slice(0, 256);
  return { cwd, ...(trimmed ? { query: trimmed } : {}), limit: 50, refKind: 'all', includeMatchingRemoteRefs: true };
}

export function requireCurrentBranch(refs: BranchView[]): string {
  const current = refs.find((item: BranchView) => item.current);
  if (!current) throw new Error('当前 checkout 不在任何分支上，请选择已有工作树或新建工作树');
  return current.name;
}

export interface PlanView { id: string; markdown: string; streaming: boolean; status: string; }
export function proposedPlans(items: Record<string, Object>[]): PlanView[] {
  return compactArray(
    items.filter((item: Record<string, Object>) => item.type === 'proposed_plan'),
    (entry: Object): PlanView => {
      const item = record(entry);
      return { id: text(item.id), markdown: text(item.markdown), streaming: item.streaming === true,
        status: text(item.status) };
    }
  );
}

export interface TokenUsage { usedTokens: number; maxTokens: number; inputTokens: number; outputTokens: number;
  cost: string; toolUses: number; durationMs: number; }
export function tokenUsage(details: Record<string, Object>): TokenUsage | undefined {
  const usage = details.tokenUsage === undefined || details.tokenUsage === null ? undefined : record(details.tokenUsage);
  if (!usage) return undefined;
  const count = (value: Object | undefined): number => typeof value === 'number' && value >= 0 ? value : 0;
  const cost = usage.cost !== undefined && usage.cost !== null ? record(usage.cost) : undefined;
  return { usedTokens: count(usage.usedTokens), maxTokens: count(usage.maxTokens),
    inputTokens: count(usage.inputTokens), outputTokens: count(usage.outputTokens),
    cost: cost && typeof cost.amount === 'number' ? cost.amount + ' ' + text(cost.currency) : '',
    toolUses: count(usage.toolUses), durationMs: count(usage.durationMs) };
}

export interface SubagentView {
  id: string;
  title: string;
  status: string;
  childThreadId: string;
  remoteThreadId: string;
  remoteEnvironmentId: string;
  remoteLabel?: string;
  detail: string;
  canStop: boolean;
  pendingKind: string;
  runId: string;
  startedAt: string;
  completedAt: string;
  updatedAt: string;
  isWorkflow: boolean;
}
export function subagents(rows: Record<string, Object>[]): SubagentView[] {
  return compactArray(rows, (entry: Object): SubagentView => {
    const row = record(entry);
    const remote = row.remoteChild !== undefined && row.remoteChild !== null && typeof row.remoteChild === 'object' && !Array.isArray(row.remoteChild)
      ? row.remoteChild as Record<string, Object> : undefined;
    const status = text(row.status);
    return {
      id: text(row.id),
      title: typeof row.title === 'string' && row.title.trim() ? row.title :
        (typeof row.prompt === 'string' ? row.prompt.slice(0, 80) : 'Subagent'),
      status,
      childThreadId: typeof row.childThreadId === 'string' ? row.childThreadId : '',
      remoteThreadId: remote && typeof remote.threadId === 'string' ? remote.threadId : '',
      remoteEnvironmentId: remote && typeof remote.environmentId === 'string' ? remote.environmentId : '',
      remoteLabel: remote && typeof remote.label === 'string' ? remote.label.trim() : '',
      detail: typeof row.progress === 'string' ? row.progress : typeof row.result === 'string' ? row.result : '',
      canStop: ['pending', 'running', 'waiting', 'idle'].includes(status),
      pendingKind: '',
      runId: typeof row.runId === 'string' ? row.runId : '',
      startedAt: typeof row.startedAt === 'string' ? row.startedAt : '',
      completedAt: typeof row.completedAt === 'string' ? row.completedAt : '',
      updatedAt: typeof row.updatedAt === 'string' ? row.updatedAt : '',
      isWorkflow: row.workflow !== undefined && row.workflow !== null
    };
  });
}

export interface BackgroundTaskView { id: string; label: string; kind: string; childThreadId: string; }
export function backgroundTasks(details: Record<string, Object>): BackgroundTaskView[] {
  if (details.pendingBackgroundTasks === undefined || details.pendingBackgroundTasks === null) return [];
  return compactArray(objects(details.pendingBackgroundTasks), (value: Object): BackgroundTaskView => {
    const row = record(value);
    return { id: text(row.taskId), label: typeof row.description === 'string' && row.description.trim() ?
      row.description : text(row.kind),
      kind: text(row.kind), childThreadId: typeof row.childThreadId === 'string' ? row.childThreadId : '' };
  });
}

export interface GuestMessageView { id: string; text: string; status: string; attachments: DraftAttachment[]; }
export interface GuestShareView { id: string; host: string; createdAt: string; expiresAt: string;
  guestName: string; messages: GuestMessageView[]; }
export function guestShare(value: Object | undefined): GuestShareView | undefined {
  if (value === undefined || value === null) return undefined;
  const row = record(value);
  return { id: text(row.id), host: text(row.host), createdAt: text(row.createdAt),
    expiresAt: text(row.expiresAt), guestName: typeof row.guestName === 'string' ? row.guestName : '',
    messages: compactArray(objects(row.messages), (item: Object): GuestMessageView => {
      const message = record(item);
      return { id: text(message.id), text: text(message.text), status: text(message.status),
        attachments: message.attachments === undefined ? [] : compactArray(message.attachments, attachmentRecord) };
    }) };
}

export function refreshStatusInput(cwd: string): Object {
  safeToken(cwd, '工作目录', 4096);
  return { cwd, localOnly: false };
}

export function createWorktreeInput(cwd: string, base: string): Object {
  safeToken(cwd, '工作目录', 4096);
  safeToken(base, '基础分支', 256);
  return { cwd, refName: base, baseRefName: base, path: null };
}

export function switchBranchInput(cwd: string, branch: string): Object {
  safeToken(cwd, '工作目录', 4096);
  safeToken(branch, '分支', 256);
  return { cwd, refName: branch };
}

export function forkThreadCommand(commandId: string, sourceThreadId: string, targetThreadId: string,
  runId: string, title: string, sideChat: boolean): Object {
  safeToken(sourceThreadId, '源会话', 128); safeToken(targetThreadId, '目标会话', 128);
  const source = runId ? { type: 'run', runId } : { type: 'latest_stable' };
  const trimmedTitle = title.trim();
  return { type: 'thread.fork', commandId, createdBy: 'user', creationSource: 'mobile',
    sourceThreadId, targetThreadId, sourcePoint: source, ...(trimmedTitle ? { title: trimmedTitle.slice(0, 200) } : {}),
    ...(sideChat ? { sideChat: true } : {}) };
}

export function forceStopCommand(commandId: string, threadId: string, runId: string): Object {
  return { threadId, ...(runId ? { runId } : {}) };
}

export function promoteCommand(commandId: string, threadId: string, queuedRunId: string, targetRunId: string): Object {
  if (!queuedRunId || !targetRunId) throw new Error('缺少运行标识');
  return { type: 'queued-message.promote-to-steer', commandId, threadId, queuedRunId, targetRunId };
}

export const MANUAL_CONTINUATION_FALLBACK_TEXT = 'Continue where you left off.';

export function manualContinuationText(textValue: string, hasAttachments: boolean,
  manualContinuationOfRunId: string = ''): string {
  if (manualContinuationOfRunId.trim() && textValue.trim().length === 0 && !hasAttachments) {
    return MANUAL_CONTINUATION_FALLBACK_TEXT;
  }
  return textValue;
}

export function latestExecutedRun(runs: Record<string, Object>[]): Record<string, Object> | undefined {
  let latest: Record<string, Object> | undefined = undefined;
  const end = (run: Record<string, Object>): number => typeof run.completedAt === 'string' ?
    Date.parse(run.completedAt) : Number.POSITIVE_INFINITY;
  for (const run of runs) {
    const status = typeof run.status === 'string' ? run.status : '';
    if (!status || status === 'queued' || (status === 'cancelled' && run.startedAt === null)) continue;
    if (!latest) { latest = run; continue; }
    const left = end(run); const right = end(latest);
    const ordinal = typeof run.ordinal === 'number' ? run.ordinal : 0;
    const latestOrdinal = typeof latest.ordinal === 'number' ? latest.ordinal : 0;
    if (left === right ? ordinal > latestOrdinal : left > right) latest = run;
  }
  return latest;
}

export interface ResumableRunProjection {
  runs: Record<string, Object>[];
  attempts: Record<string, Object>[];
  providerTurns: Record<string, Object>[];
  providerThreads: Record<string, Object>[];
  providerSessions: Record<string, Object>[];
  items?: Record<string, Object>[];
}

export function unsentManualContinuationSource(
  manualContinuationOfRunId: string,
  projection: ResumableRunProjection
): Record<string, Object> | undefined {
  let sourceId = manualContinuationOfRunId;
  if (!sourceId) return undefined;
  const runsById: Map<string, Record<string, Object>> = new Map();
  for (const source of projection.runs) {
    if (typeof source.id === 'string' && source.id) runsById.set(source.id, source);
  }
  const acceptedAttempts: Set<string> = new Set();
  for (const turn of projection.providerTurns) {
    if (typeof turn.runAttemptId === 'string' && turn.runAttemptId) {
      acceptedAttempts.add(turn.runAttemptId);
    }
  }
  const latestAttempt = (runId: string, matches: (attempt: Record<string, Object>) => boolean): number => {
    let best = 0;
    for (const attempt of projection.attempts) {
      if (attempt.runId !== runId || !matches(attempt)) continue;
      const ordinal = typeof attempt.attemptOrdinal === 'number' ? attempt.attemptOrdinal : 0;
      if (ordinal > best) best = ordinal;
    }
    return best;
  };
  const visited: Set<string> = new Set();
  while (sourceId && !visited.has(sourceId)) {
    visited.add(sourceId);
    const source = runsById.get(sourceId);
    if (!source) return undefined;
    const accepted = latestAttempt(sourceId, (attempt: Record<string, Object>) =>
      typeof attempt.id === 'string' && acceptedAttempts.has(attempt.id));
    // An accepted attempt delivered everything before it; only a later steering restart's message is unsent.
    const restarted = latestAttempt(sourceId, (attempt: Record<string, Object>) =>
      attempt.reason === 'steering_restart');
    if (restarted > accepted) return source;
    if (accepted > 0) return undefined;
    const parentId = typeof source.manualContinuationOfRunId === 'string' ? source.manualContinuationOfRunId : '';
    if (!parentId) return source;
    sourceId = parentId;
  }
  return undefined;
}

function runProviderSession(
  projection: ResumableRunProjection,
  run: Record<string, Object>
): Record<string, Object> | undefined {
  const providerThreadId = typeof run.providerThreadId === 'string' ? run.providerThreadId : '';
  let sessionId = '';
  if (providerThreadId) {
    for (const thread of projection.providerThreads) {
      if (thread.id === providerThreadId && typeof thread.providerSessionId === 'string') {
        sessionId = thread.providerSessionId;
        break;
      }
    }
  }
  if (sessionId) {
    for (const session of projection.providerSessions) {
      if (session.id === sessionId) return session;
    }
    return undefined;
  }
  const instanceId = typeof run.providerInstanceId === 'string' ? run.providerInstanceId : '';
  if (!instanceId) return undefined;
  for (let i = projection.providerSessions.length - 1; i >= 0; i -= 1) {
    if (projection.providerSessions[i].providerInstanceId === instanceId) {
      return projection.providerSessions[i];
    }
  }
  return undefined;
}

function sessionSupportsNativeResume(session: Record<string, Object> | undefined): boolean | undefined {
  if (!session) return undefined;
  const caps = session.capabilities;
  if (caps === undefined || caps === null || typeof caps !== 'object' || Array.isArray(caps)) return undefined;
  const turns = (caps as Record<string, Object>).turns;
  if (turns === undefined || turns === null || typeof turns !== 'object' || Array.isArray(turns)) return undefined;
  const value = (turns as Record<string, Object>).supportsNativeResume;
  return typeof value === 'boolean' ? value : undefined;
}

function latestRootFailureAllowsUsageLimit(run: Record<string, Object>, items: Record<string, Object>[]): boolean {
  const runId = typeof run.id === 'string' ? run.id : '';
  if (!runId) return false;
  let latestClass: string | undefined = undefined;
  let latestOrdinal = -1;
  for (const item of items) {
    if (item.type !== 'error' || item.runId !== runId) continue;
    if (item.subagentId !== undefined && item.subagentId !== null && item.subagentId !== '') continue;
    const failure = item.failure;
    if (failure === undefined || failure === null || typeof failure !== 'object' || Array.isArray(failure)) continue;
    const failureClass = (failure as Record<string, Object>).class;
    if (typeof failureClass !== 'string') continue;
    const ordinal = typeof item.ordinal === 'number' ? item.ordinal : latestOrdinal + 1;
    if (ordinal >= latestOrdinal) {
      latestOrdinal = ordinal;
      latestClass = failureClass;
    }
  }
  return latestClass === undefined ? true : latestClass === 'usage_limit';
}

export function deriveResumableRunId(projection: ResumableRunProjection, lastErrorClass: string = ''): string {
  const run = latestExecutedRun(projection.runs);
  if (!run || typeof run.id !== 'string' || !run.id) return '';
  const status = typeof run.status === 'string' ? run.status : '';
  const resumable = status === 'interrupted' ||
    (status === 'failed' && lastErrorClass === 'usage_limit' &&
      latestRootFailureAllowsUsageLimit(run, projection.items || []));
  if (!resumable) return '';
  // Without native resume the server can only resend a message the provider never received.
  if (sessionSupportsNativeResume(runProviderSession(projection, run)) === false &&
    unsentManualContinuationSource(run.id, projection) === undefined) {
    return '';
  }
  return run.id;
}

