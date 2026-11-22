import { ChatMessage, compactObjects, record } from './Wire';
import { effectiveSnoozed, snoozeWakeLabel, ThreadView } from './Projects';
import { SubagentView, subagents as parseSubagents } from './R4';

export const BACKGROUND_WORK_STOP_RETRY_AFTER_MS = 10000;

export interface PendingBackgroundTaskView {
  taskId: string;
  kind: string;
  label: string;
  childThreadId: string;
  awaited: boolean;
}

export interface PendingBackgroundWorkView {
  title: string;
  items: PendingBackgroundTaskView[];
  waiting: boolean;
}

export interface ThreadTurnSubagentsView {
  runId: string;
  turnActive: boolean;
  latestTurn: boolean;
  subagents: SubagentView[];
  liveCount: number;
  settledCount: number;
  hasWorkflow: boolean;
}

export interface SubagentPillSegment {
  label: string;
  liveCount: number;
  totalCount: number;
  accessibilityLabel: string;
}

export interface RunStopView {
  state: string;
  runId: string;
  requestedAt: string;
  background: boolean;
}

export interface ChildInputItem {
  threadId: string;
  localId: string;
  title: string;
  hasPendingApprovals: boolean;
}

export interface BackgroundStopRequest {
  threadKey: string;
  taskIds: string[];
  retryAt: number;
}

export interface FloatingCapsuleStatus {
  kind: string;
  icon: string;
  label: string;
  tone: string;
  clickable: boolean;
  startedAt: string;
  actionKind: string;
  actionLabel: string;
  actionDisabled: boolean;
  targetRunId: string;
  targetThreadId: string;
  targetLocalId: string;
  accessibilityLabel: string;
}

export interface FloatingCapsuleModel {
  status: FloatingCapsuleStatus | undefined;
  agents: SubagentPillSegment | undefined;
  queuedCount: number;
  visible: boolean;
}

export interface FloatingCapsuleInput {
  draftMode: boolean;
  ready: boolean;
  connecting: boolean;
  offline?: boolean;
  environmentLabel: string;
  connectionError: string;
  unknown: boolean;
  pendingActionCount: number;
  canOperateThread: boolean;
  canForceStop: boolean;
  forceStopping: boolean;
  backgroundStopPending: boolean;
  nowMs: number;
  threadSynced: boolean;
  runs: Record<string, Object>[];
  turnItems: Record<string, Object>[];
  messages: ChatMessage[];
  subagents: Record<string, Object>[];
  providerThreads: Record<string, Object>[];
  nodes: Record<string, Object>[];
  details: Record<string, Object>;
  shellThread: ThreadView | undefined;
  allThreads: ThreadView[];
  selectedLocalId: string;
  queuedCount: number;
  hasWorktreeSetupCard: boolean;
  supportsSnooze: boolean;
  supportsSettlement: boolean;
}

export const RECONNECT_SHOW_DELAY_MS = 400;
export const CONNECTION_ERROR_DELAY_MS = 5000;

export interface DelayedConnectionUiState {
  wasReady: boolean;
  disconnectedSinceMs: number;
  errorSinceMs: number;
  lastError: string;
}

export interface DelayedConnectionUiInput {
  ready: boolean;
  connecting: boolean;
  offline: boolean;
  error: string;
  nowMs: number;
}

export interface DelayedConnectionUiResult {
  state: DelayedConnectionUiState;
  suppressConnecting: boolean;
  showError: boolean;
  nextTickMs: number;
}

export function initialDelayedConnectionUiState(): DelayedConnectionUiState {
  return { wasReady: false, disconnectedSinceMs: 0, errorSinceMs: 0, lastError: '' };
}

export function stepDelayedConnectionUi(
  prev: DelayedConnectionUiState,
  input: DelayedConnectionUiInput
): DelayedConnectionUiResult {
  if (input.ready) {
    return {
      state: { wasReady: true, disconnectedSinceMs: 0, errorSinceMs: 0, lastError: '' },
      suppressConnecting: false,
      showError: false,
      nextTickMs: 0
    };
  }
  const disconnectedSinceMs = prev.disconnectedSinceMs > 0 ? prev.disconnectedSinceMs : input.nowMs;
  const errorSinceMs = input.error
    ? (prev.errorSinceMs > 0 && prev.lastError === input.error ? prev.errorSinceMs : input.nowMs)
    : 0;
  const nextState: DelayedConnectionUiState = {
    wasReady: prev.wasReady,
    disconnectedSinceMs,
    errorSinceMs,
    lastError: input.error
  };
  if (input.offline || !input.connecting) {
    return {
      state: nextState,
      suppressConnecting: false,
      showError: !!input.error,
      nextTickMs: 0
    };
  }
  const elapsedDisconnected = Math.max(0, input.nowMs - disconnectedSinceMs);
  const suppressConnecting = prev.wasReady && elapsedDisconnected < RECONNECT_SHOW_DELAY_MS;
  const elapsedError = errorSinceMs > 0 ? Math.max(0, input.nowMs - errorSinceMs) : 0;
  const showError = !!input.error && elapsedError >= CONNECTION_ERROR_DELAY_MS;
  let nextTickMs = 0;
  if (suppressConnecting) {
    nextTickMs = RECONNECT_SHOW_DELAY_MS - elapsedDisconnected;
  } else if (!!input.error && !showError) {
    nextTickMs = CONNECTION_ERROR_DELAY_MS - elapsedError;
  }
  return {
    state: nextState,
    suppressConnecting,
    showError,
    nextTickMs
  };
}

export function emptyFloatingCapsule(): FloatingCapsuleModel {
  return { status: undefined, agents: undefined, queuedCount: 0, visible: false };
}

function str(value: Object | undefined): string {
  return typeof value === 'string' ? value : '';
}

function num(value: Object | undefined): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

function isWorkActiveStatus(status: string): boolean {
  return status === 'pending' || status === 'running' || status === 'waiting';
}

function isTerminalSubagentStatus(status: string): boolean {
  return status === 'completed' || status === 'failed' || status === 'cancelled' || status === 'interrupted';
}

export function formatSubagentDisplayTitle(raw: string): string {
  const displayTitle = raw.replace(/^Subagent:\s*/i, '');
  const pathMatch = /^\/root\/(?:[^/]+\/)*([^/]+)\/?$/.exec(displayTitle);
  if (!pathMatch) return displayTitle;
  const name = pathMatch[1].replace(/[_\s]+/g, ' ').trim();
  const formatted = name.replace(/(^|\s)\S/g, (letter: string) => letter.toUpperCase());
  return formatted || displayTitle;
}

function compactCommandLabel(raw: string): string {
  const firstLine = raw.split('\n')[0] || '';
  return firstLine.replace(/\s+/g, ' ').trim();
}

export function formatWorkingDuration(startedAt: string, nowMs: number): string {
  const startedAtMs = Date.parse(startedAt);
  if (!Number.isFinite(startedAtMs) || nowMs <= startedAtMs) return '0s';
  const totalSeconds = Math.floor((nowMs - startedAtMs) / 1000);
  if (totalSeconds < 60) return totalSeconds + 's';
  if (totalSeconds >= 3600) {
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    return hours + 'h ' + (minutes < 10 ? '0' + minutes : String(minutes)) + 'm';
  }
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return minutes + 'm ' + (seconds < 10 ? '0' + seconds : String(seconds)) + 's';
}

function outlivedBeforeStart(run: Record<string, Object>, runs: Record<string, Object>[]): boolean {
  if (str(run.status) !== 'cancelled') return false;
  if (typeof run.startedAt === 'string' && run.startedAt) return false;
  const completedAtStr = str(run.completedAt);
  if (!completedAtStr) return false;
  const cancelledAt = Date.parse(completedAtStr);
  if (!Number.isFinite(cancelledAt)) return false;
  const ordinal = num(run.ordinal);
  return runs.some((earlier: Record<string, Object>) => {
    if (num(earlier.ordinal) >= ordinal || str(earlier.status) === 'queued') return false;
    const earlierCompleted = str(earlier.completedAt);
    if (!earlierCompleted) return true;
    const earlierMs = Date.parse(earlierCompleted);
    return !Number.isFinite(earlierMs) || earlierMs >= cancelledAt;
  });
}

function latestUnheldRun(runs: Record<string, Object>[]): Record<string, Object> | undefined {
  let latest: Record<string, Object> | undefined = undefined;
  for (const run of runs) {
    const status = str(run.status);
    if (status === 'rolled_back') continue;
    if (status === 'queued' && run.queueHeld === true) continue;
    if (outlivedBeforeStart(run, runs)) continue;
    if (!latest || num(run.ordinal) > num(latest.ordinal)) latest = run;
  }
  return latest;
}

function pullRequestWatchTasks(details: Record<string, Object>): PendingBackgroundTaskView[] {
  if (details.pullRequests === undefined || details.pullRequests === null || !Array.isArray(details.pullRequests)) {
    return [];
  }
  const tasks: PendingBackgroundTaskView[] = [];
  for (const link of compactObjects(details.pullRequests)) {
    if (link.watch === undefined || link.watch === null || typeof link.watch !== 'object' || Array.isArray(link.watch)) continue;
    if (str(link.source) === 'stack-dismissed') continue;
    const snapshot = link.snapshot !== undefined && link.snapshot !== null && typeof link.snapshot === 'object' && !Array.isArray(link.snapshot)
      ? link.snapshot as Record<string, Object> : undefined;
    if (snapshot && str(snapshot.state) === 'merged') continue;
    const watch = link.watch as Record<string, Object>;
    const host = str(link.host).toLowerCase();
    const repo = str(link.repository).toLowerCase();
    const numberVal = num(link.number);
    tasks.push({
      taskId: 'pull-request-watch:' + host + '/' + repo + '#' + numberVal,
      kind: 'monitor',
      label: '关注 PR #' + numberVal,
      childThreadId: '',
      awaited: watch.checksPending !== false
    });
  }
  return tasks;
}

function normalizeBackgroundTask(raw: Record<string, Object>): PendingBackgroundTaskView | undefined {
  const taskId = str(raw.taskId) || str(raw.id);
  if (!taskId) return undefined;
  const kind = str(raw.kind) || 'background_task';
  const rawDesc = str(raw.description).trim();
  let label = '';
  if (rawDesc) {
    if (kind === 'subagent') label = formatSubagentDisplayTitle(rawDesc).trim();
    else if (kind === 'command' || kind === 'monitor') label = compactCommandLabel(rawDesc);
    else label = rawDesc;
  }
  return {
    taskId,
    kind,
    label: label || backgroundKindSingular(kind),
    childThreadId: kind === 'subagent' ? str(raw.childThreadId) : '',
    awaited: raw.awaited === true
  };
}

function backgroundKindSingular(kind: string): string {
  if (kind === 'subagent') return '子 Agent';
  if (kind === 'command') return '命令';
  if (kind === 'monitor') return '监控';
  return '后台任务';
}

function backgroundKindOrder(kind: string): number {
  if (kind === 'subagent') return 0;
  if (kind === 'command') return 1;
  if (kind === 'monitor') return 2;
  return 3;
}

function isPersistentDynamicTool(item: Record<string, Object>): boolean {
  if (str(item.type) !== 'dynamic_tool') return false;
  if (item.input === undefined || item.input === null || typeof item.input !== 'object' || Array.isArray(item.input)) {
    return false;
  }
  const input = record(item.input);
  return input.isDaemon === true || input.IsDaemon === true;
}

function taskFromTurnItem(taskId: string, item: Record<string, Object>): PendingBackgroundTaskView {
  const type = str(item.type);
  if (type === 'subagent') {
    const rawDesc = str(item.title).trim() || str(item.prompt).trim();
    const label = rawDesc ? formatSubagentDisplayTitle(rawDesc).trim() : '';
    return {
      taskId,
      kind: 'subagent',
      label: label || backgroundKindSingular('subagent'),
      childThreadId: str(item.childThreadId),
      awaited: false
    };
  }
  if (type === 'command_execution') {
    const kind = item.monitor === true ? 'monitor' : 'command';
    const rawDesc = str(item.command).trim() || str(item.input).trim();
    const label = rawDesc ? compactCommandLabel(rawDesc) : '';
    return {
      taskId,
      kind,
      label: label || backgroundKindSingular(kind),
      childThreadId: '',
      awaited: false
    };
  }
  const toolDesc = str(item.title).trim() || str(item.toolName).trim();
  return {
    taskId,
    kind: 'background_task',
    label: toolDesc || backgroundKindSingular('background_task'),
    childThreadId: '',
    awaited: false
  };
}

export function backgroundWorkHoldsCompletion(tasks: PendingBackgroundTaskView[]): boolean {
  return tasks.some((task: PendingBackgroundTaskView) =>
    task.awaited || task.kind === 'subagent' || task.kind === 'background_task');
}

export function derivePendingBackgroundWork(
  runs: Record<string, Object>[],
  providerThreads: Record<string, Object>[],
  turnItems: Record<string, Object>[],
  details: Record<string, Object>,
  shellPendingTasks: Record<string, Object>[] = []
): PendingBackgroundTaskView[] {
  const hasActiveRun = runs.some((run: Record<string, Object>) => {
    const status = str(run.status);
    return status === 'preparing' || status === 'starting' || status === 'running';
  });
  if (hasActiveRun) return [];

  const prTasks = pullRequestWatchTasks(details);
  const latestRun = latestUnheldRun(runs);
  if (!latestRun) return prTasks;

  const latestStatus = str(latestRun.status);
  if (!['cancelled', 'completed', 'failed', 'interrupted', 'waiting'].includes(latestStatus)) {
    return [];
  }

  const byTaskId = new Map<string, PendingBackgroundTaskView>();
  const activeProviderThreadId = str(details.activeProviderThreadId);
  const matchingProviderThreads = activeProviderThreadId
    ? providerThreads.filter((pt: Record<string, Object>) => str(pt.id) === activeProviderThreadId)
    : providerThreads;

  for (const pt of matchingProviderThreads) {
    for (const rawTask of compactObjects(pt.pendingBackgroundTasks)) {
      const task = normalizeBackgroundTask(rawTask);
      if (task && !byTaskId.has(task.taskId)) byTaskId.set(task.taskId, task);
    }
  }

  for (const rawTask of compactObjects(details.pendingBackgroundTasks)) {
    const task = normalizeBackgroundTask(rawTask);
    if (task && !byTaskId.has(task.taskId)) byTaskId.set(task.taskId, task);
  }

  for (const rawTask of shellPendingTasks) {
    const task = normalizeBackgroundTask(rawTask);
    if (task && !byTaskId.has(task.taskId)) byTaskId.set(task.taskId, task);
  }

  const rolledBackIds = new Set<string>(
    runs.filter((run: Record<string, Object>) => str(run.status) === 'rolled_back')
      .map((run: Record<string, Object>) => str(run.id))
      .filter((id: string) => id !== '')
  );

  for (const item of turnItems) {
    const type = str(item.type);
    if (type !== 'command_execution' && type !== 'dynamic_tool' && type !== 'subagent') continue;
    if (!isWorkActiveStatus(str(item.status))) continue;
    if (isPersistentDynamicTool(item)) continue;
    const runId = str(item.runId);
    if (runId && rolledBackIds.has(runId)) continue;
    const nativeRef = item.nativeItemRef !== undefined && item.nativeItemRef !== null ? record(item.nativeItemRef) : undefined;
    const taskId = nativeRef && str(nativeRef.nativeId) ? str(nativeRef.nativeId) : str(item.id);
    if (!taskId || byTaskId.has(taskId)) continue;
    byTaskId.set(taskId, taskFromTurnItem(taskId, item));
  }

  for (const task of prTasks) {
    byTaskId.set(task.taskId, task);
  }

  return Array.from(byTaskId.values());
}

export function presentPendingBackgroundWork(tasks: PendingBackgroundTaskView[]): PendingBackgroundWorkView | undefined {
  if (!tasks.length) return undefined;
  const waiting = backgroundWorkHoldsCompletion(tasks);
  const sorted = tasks.slice().sort((left: PendingBackgroundTaskView, right: PendingBackgroundTaskView) =>
    backgroundKindOrder(left.kind) - backgroundKindOrder(right.kind));
  if (sorted.length === 1) {
    const only = sorted[0];
    const singular = backgroundKindSingular(only.kind);
    const named = only.label !== singular;
    const title = named
      ? (waiting ? '等待 · ' : '运行中 · ') + only.label
      : (waiting ? '等待' : '正在运行') + singular;
    return { title, items: sorted, waiting };
  }
  const order = ['subagent', 'command', 'monitor', 'background_task'];
  const counts = new Map<string, number>();
  for (const item of sorted) {
    counts.set(item.kind, (counts.get(item.kind) || 0) + 1);
  }
  const parts: string[] = [];
  for (const kind of order) {
    const count = counts.get(kind) || 0;
    if (count > 0) parts.push(count + ' 个' + backgroundKindSingular(kind));
  }
  const title = (waiting ? '等待 ' : '运行中 ') + parts.join('、');
  return { title, items: sorted, waiting };
}

function subagentOrderKey(row: SubagentView): number {
  const source = row.startedAt || row.updatedAt;
  const parsed = source ? Date.parse(source) : NaN;
  return Number.isFinite(parsed) ? parsed : 0;
}

export function deriveThreadTurnSubagents(
  runs: Record<string, Object>[],
  rawSubagents: Record<string, Object>[],
  shellThreads: ThreadView[] = []
): ThreadTurnSubagentsView | undefined {
  const rolledBackIds = new Set<string>(
    runs.filter((run: Record<string, Object>) => str(run.status) === 'rolled_back')
      .map((run: Record<string, Object>) => str(run.id))
      .filter((id: string) => id !== '')
  );
  const eligibleRaw = rawSubagents.filter((row: Record<string, Object>) => {
    const runId = str(row.runId);
    return !runId || !rolledBackIds.has(runId);
  });
  if (!eligibleRaw.length) return undefined;

  let activeRun: Record<string, Object> | undefined = undefined;
  let latestStartedRun: Record<string, Object> | undefined = undefined;
  for (const run of runs) {
    const runId = str(run.id);
    const status = str(run.status);
    if (['preparing', 'starting', 'running', 'waiting'].includes(status)) {
      if (!activeRun || num(run.ordinal) > num(activeRun.ordinal)) activeRun = run;
    }
    if (!rolledBackIds.has(runId) && typeof run.startedAt === 'string' && run.startedAt) {
      if (!latestStartedRun || num(run.ordinal) > num(latestStartedRun.ordinal)) latestStartedRun = run;
    }
  }

  let latestUpdated = eligibleRaw[0];
  let latestUpdatedMs = Date.parse(str(latestUpdated.updatedAt)) || 0;
  for (const candidate of eligibleRaw) {
    const ms = Date.parse(str(candidate.updatedAt)) || 0;
    if (ms > latestUpdatedMs) {
      latestUpdated = candidate;
      latestUpdatedMs = ms;
    }
  }

  const latestStartedId = latestStartedRun ? str(latestStartedRun.id) : '';
  const latestStartedHasAgents = latestStartedId !== '' &&
    eligibleRaw.some((row: Record<string, Object>) => str(row.runId) === latestStartedId);
  const targetRunId = activeRun
    ? str(activeRun.id)
    : (latestStartedHasAgents ? latestStartedId : str(latestUpdated.runId));

  const selectedRaw = eligibleRaw.filter((row: Record<string, Object>) =>
    str(row.runId) === targetRunId ||
    isWorkActiveStatus(str(row.status)) ||
    (row.workflow !== undefined && row.workflow !== null));
  if (!selectedRaw.length) return undefined;

  const parsed = parseSubagents(selectedRaw);
  for (const row of parsed) {
    row.title = formatSubagentDisplayTitle(row.title);
    const child = shellThreads.find((thread: ThreadView) =>
      thread.id === row.childThreadId || (row.remoteThreadId !== '' && thread.id === row.remoteThreadId));
    row.pendingKind = child ? child.pendingKind : '';
  }
  parsed.sort((left: SubagentView, right: SubagentView) =>
    subagentOrderKey(left) - subagentOrderKey(right) || left.id.localeCompare(right.id));

  let liveCount = 0;
  let settledCount = 0;
  let hasWorkflow = false;
  for (const row of parsed) {
    if (isWorkActiveStatus(row.status)) liveCount += 1;
    else if (isTerminalSubagentStatus(row.status)) settledCount += 1;
    if (row.isWorkflow) hasWorkflow = true;
  }

  return {
    runId: targetRunId,
    turnActive: activeRun !== undefined,
    latestTurn: targetRunId === '' || latestStartedRun === undefined || targetRunId === latestStartedId,
    subagents: parsed,
    liveCount,
    settledCount,
    hasWorkflow
  };
}

export function resolveSubagentPillSegment(turn: ThreadTurnSubagentsView | undefined): SubagentPillSegment | undefined {
  if (!turn) return undefined;
  if (!turn.turnActive && !turn.latestTurn && turn.liveCount === 0 && !turn.hasWorkflow) return undefined;
  const total = turn.subagents.length;
  if (turn.liveCount > 0) {
    return {
      label: turn.liveCount + '/' + total,
      liveCount: turn.liveCount,
      totalCount: total,
      accessibilityLabel: turn.liveCount + ' / ' + total + ' 个子 Agent 运行中'
    };
  }
  return {
    label: turn.settledCount + ' 已完成',
    liveCount: 0,
    totalCount: total,
    accessibilityLabel: turn.settledCount + ' 个子 Agent 已完成'
  };
}

export function presentRunStop(runs: Record<string, Object>[], turnItems: Record<string, Object>[]): RunStopView | undefined {
  let active: Record<string, Object> | undefined = undefined;
  let latest: Record<string, Object> | undefined = undefined;
  for (const candidate of runs) {
    const status = str(candidate.status);
    if (status !== 'queued' && (!latest || num(candidate.ordinal) > num(latest.ordinal))) {
      latest = candidate;
    }
    if (['preparing', 'starting', 'running'].includes(status) &&
      (!active || num(candidate.ordinal) > num(active.ordinal))) {
      active = candidate;
    }
  }
  const run = active || latest;
  if (!run) return undefined;
  const runId = str(run.id);
  let request: Record<string, Object> | undefined = undefined;
  for (const item of turnItems) {
    if (str(item.runId) !== runId) continue;
    const type = str(item.type);
    if (type === 'run_interrupt_result') return undefined;
    if (type === 'run_interrupt_request') request = item;
  }
  if (!request) return undefined;
  const hasUnresponsive = typeof request.unresponsiveAt === 'string' && request.unresponsiveAt !== '';
  if (!active && !hasUnresponsive) return undefined;
  return {
    state: hasUnresponsive ? 'unresponsive' : 'stopping',
    runId,
    requestedAt: str(request.startedAt) || str(request.updatedAt),
    background: active === undefined
  };
}

function isProviderNativeSubagentDetails(details: Record<string, Object>): boolean {
  if (str(details.creationSource) !== 'provider') return false;
  if (details.lineage === undefined || details.lineage === null) return false;
  return str(record(details.lineage).relationshipToParent) === 'subagent';
}

export function deriveWorkingStartedAt(
  runs: Record<string, Object>[],
  nodes: Record<string, Object>[],
  details: Record<string, Object>,
  hasPendingBackgroundWork: boolean
): string {
  let activeRun: Record<string, Object> | undefined = undefined;
  for (const run of runs) {
    const status = str(run.status);
    const isInterruptible = status === 'preparing' || status === 'starting' || status === 'running';
    const isWaitingActive = status === 'waiting' && !hasPendingBackgroundWork;
    if (!isInterruptible && !isWaitingActive) continue;
    if (!activeRun || num(run.ordinal) > num(activeRun.ordinal)) activeRun = run;
  }
  if (activeRun) {
    const candidate = str(activeRun.workStartedAt) || str(activeRun.startedAt) || str(activeRun.requestedAt);
    if (candidate && Number.isFinite(Date.parse(candidate))) return candidate;
  }
  if (isProviderNativeSubagentDetails(details)) {
    for (let i = nodes.length - 1; i >= 0; i -= 1) {
      const node = nodes[i];
      if (str(node.kind) === 'root_turn' && (node.runId === undefined || node.runId === null || node.runId === '')) {
        if (isWorkActiveStatus(str(node.status))) {
          const startedAt = str(node.startedAt);
          if (startedAt && Number.isFinite(Date.parse(startedAt))) return startedAt;
        }
        break;
      }
    }
  }
  return '';
}

export function isThreadCompacting(
  runs: Record<string, Object>[],
  turnItems: Record<string, Object>[],
  messages: ChatMessage[]
): boolean {
  let activeRun: Record<string, Object> | undefined = undefined;
  for (const run of runs) {
    if (['preparing', 'starting', 'running', 'waiting'].includes(str(run.status))) {
      if (!activeRun || num(run.ordinal) > num(activeRun.ordinal)) activeRun = run;
    }
  }
  if (!activeRun) return false;
  const activeRunId = str(activeRun.id);
  const compactionRunning = turnItems.some((item: Record<string, Object>) =>
    str(item.runId) === activeRunId && str(item.type) === 'compaction' && str(item.status) === 'running');
  if (compactionRunning) return true;
  const compactCommandMsg = messages.some((msg: ChatMessage) =>
    msg.role === 'user' && msg.runId === activeRunId &&
    msg.text.trim().toLowerCase() === '/compact' &&
    (!msg.attachmentNames || msg.attachmentNames.length === 0));
  if (!compactCommandMsg) return false;
  return !turnItems.some((item: Record<string, Object>) =>
    str(item.runId) === activeRunId && str(item.type) === 'compaction' &&
    ['completed', 'failed', 'interrupted', 'cancelled'].includes(str(item.status)));
}

function isChildRunLive(thread: ThreadView): boolean {
  if (thread.activityRunStatus) return true;
  return ['preparing', 'starting', 'running', 'waiting'].includes(thread.status);
}

export function deriveChildThreadInputs(threads: ThreadView[], currentThreadId: string, localId: string): ChildInputItem[] {
  if (!currentThreadId) return [];
  const items: ChildInputItem[] = [];
  for (const thread of threads) {
    const isChild = thread.lineageParentThreadId === currentThreadId || thread.delegatedFromThreadId === currentThreadId;
    if (!isChild) continue;
    if (!thread.pendingKind || thread.pendingKind === 'auth_refresh') continue;
    if (!isChildRunLive(thread)) continue;
    items.push({
      threadId: thread.id,
      localId,
      title: thread.label || '子会话',
      hasPendingApprovals: thread.pendingKind !== 'user_input'
    });
  }
  return items;
}

export function isBackgroundWorkStopPending(
  request: BackgroundStopRequest | undefined,
  threadKey: string,
  tasks: PendingBackgroundTaskView[],
  nowMs: number
): boolean {
  if (!request || request.threadKey !== threadKey) return false;
  if (request.retryAt > 0 && nowMs >= request.retryAt) return false;
  return request.retryAt === 0 || tasks.some((task: PendingBackgroundTaskView) => request.taskIds.includes(task.taskId));
}

function limitRecoveryOwnsSnooze(details: Record<string, Object>, snoozedUntil: string): boolean {
  if (!snoozedUntil) return false;
  if (details.limitRecovery === undefined || details.limitRecovery === null) return false;
  const recovery = record(details.limitRecovery);
  if (recovery.snooze !== true) return false;
  const latestRunId = str(details.latestRunId);
  const resetAt = str(details.usageLimitResetAt);
  if (!latestRunId || !resetAt) return false;
  if (str(recovery.runId) !== latestRunId || str(recovery.resetAt) !== resetAt) return false;
  return Date.parse(snoozedUntil) === Date.parse(resetAt);
}

function goalTitle(goal: Record<string, Object>, working: boolean): string {
  const status = str(goal.status);
  if (status === 'active') return working ? '目标进行中' : '已设定目标';
  if (status === 'paused') return '目标已暂停';
  if (status === 'blocked') return '目标受阻';
  if (status === 'usage_limited') return '目标已达用量限制';
  if (status === 'budget_limited') return '目标已达预算上限';
  if (status === 'complete') return '目标已完成';
  return '目标';
}

function resolveThreadGoal(providerThreads: Record<string, Object>[], details: Record<string, Object>,
  shellThread: ThreadView | undefined): Record<string, Object> | undefined {
  const activeId = str(details.activeProviderThreadId);
  if (activeId) {
    const match = providerThreads.find((pt: Record<string, Object>) => str(pt.id) === activeId);
    if (match && match.goal !== undefined && match.goal !== null) return record(match.goal);
  }
  if (details.goal !== undefined && details.goal !== null) return record(details.goal);
  return shellThread?.goal;
}

interface FloatingCapsuleStatusInit {
  kind: string;
  icon: string;
  label: string;
  tone?: string;
  clickable?: boolean;
  startedAt?: string;
  actionKind?: string;
  actionLabel?: string;
  actionDisabled?: boolean;
  targetRunId?: string;
  targetThreadId?: string;
  targetLocalId?: string;
  accessibilityLabel?: string;
}

function buildStatus(partial: FloatingCapsuleStatusInit): FloatingCapsuleStatus {
  return {
    kind: partial.kind,
    icon: partial.icon,
    label: partial.label,
    tone: partial.tone || 'normal',
    clickable: partial.clickable === true,
    startedAt: partial.startedAt || '',
    actionKind: partial.actionKind || '',
    actionLabel: partial.actionLabel || '',
    actionDisabled: partial.actionDisabled === true,
    targetRunId: partial.targetRunId || '',
    targetThreadId: partial.targetThreadId || '',
    targetLocalId: partial.targetLocalId || '',
    accessibilityLabel: partial.accessibilityLabel || partial.label
  };
}

export function deriveFloatingCapsuleModel(input: FloatingCapsuleInput): FloatingCapsuleModel {
  if (input.draftMode) return emptyFloatingCapsule();

  const turnSubagents = deriveThreadTurnSubagents(input.runs, input.subagents, input.allThreads);
  const agents = resolveSubagentPillSegment(turnSubagents);
  const queuedCount = input.queuedCount > 0 ? input.queuedCount : 0;

  let status: FloatingCapsuleStatus | undefined = undefined;

  if (!input.ready) {
    const env = input.environmentLabel || '工作环境';
    const offline = input.offline === true;
    const label = offline
      ? '当前离线'
      : input.connecting
        ? (input.connectionError ? '重连 ' + env + ' 中…' : '正在连接 ' + env + '…')
        : (input.connectionError ? '连接失败 · ' + env : env + ' 未连接');
    status = buildStatus({
      kind: 'connection',
      icon: !offline && input.connecting ? 'spinner' : 'offline',
      label,
      tone: !offline && input.connecting ? 'normal' : 'danger',
      clickable: true,
      accessibilityLabel: offline ? '当前网络离线，点击查看连接' : (label + '，点击重连或查看连接')
    });
  } else {
    const runStop = presentRunStop(input.runs, input.turnItems);
    if (runStop) {
      const unresponsive = runStop.state === 'unresponsive';
      status = buildStatus({
        kind: 'stop',
        icon: unresponsive ? 'warning' : 'spinner',
        label: unresponsive ? '停止无响应' : '正在停止…',
        tone: unresponsive ? 'warning' : 'normal',
        actionKind: unresponsive && input.canForceStop ? 'force-stop' : '',
        actionLabel: unresponsive && input.canForceStop ? (input.forceStopping ? '强制停止中…' : '强制停止') : '',
        actionDisabled: input.forceStopping,
        targetRunId: runStop.runId
      });
    } else if (input.unknown || input.pendingActionCount > 0) {
      const label = input.unknown ? '核对提交结果' : input.pendingActionCount + ' 个请求待处理';
      status = buildStatus({
        kind: 'action-needed',
        icon: 'warning',
        label,
        tone: 'warning',
        clickable: true,
        accessibilityLabel: label + '，点击跳至底部处理'
      });
    } else {
      const childInputs = deriveChildThreadInputs(
        input.allThreads,
        str(input.details.id) || (input.shellThread ? input.shellThread.id : ''),
        input.selectedLocalId
      );
      if (childInputs.length > 0) {
        const first = childInputs[0];
        const label = childInputs.length === 1
          ? (first.hasPendingApprovals ? '子会话待批准 · ' + first.title : '子会话待回答 · ' + first.title)
          : childInputs.length + ' 个子会话待处理';
        status = buildStatus({
          kind: 'child-input',
          icon: 'chat',
          label,
          clickable: true,
          targetThreadId: first.threadId,
          targetLocalId: first.localId,
          accessibilityLabel: '打开子会话：' + first.title
        });
      } else if (isThreadCompacting(input.runs, input.turnItems, input.messages)) {
        status = buildStatus({
          kind: 'compacting',
          icon: 'compact',
          label: '压缩上下文…'
        });
      } else {
        const bgTasks = derivePendingBackgroundWork(
          input.runs,
          input.providerThreads,
          input.turnItems,
          input.details,
          input.shellThread ? input.shellThread.pendingBackgroundTasks : []
        );
        const bgPresentation = presentPendingBackgroundWork(bgTasks);
        const workingStartedAt = deriveWorkingStartedAt(
          input.runs,
          input.nodes,
          input.details,
          bgPresentation !== undefined
        );
        if (workingStartedAt) {
          status = buildStatus({
            kind: 'working',
            icon: 'none',
            label: '运行中 ' + formatWorkingDuration(workingStartedAt, input.nowMs),
            startedAt: workingStartedAt
          });
        } else if (bgPresentation) {
          status = buildStatus({
            kind: 'background',
            icon: bgPresentation.waiting ? 'subagents' : 'terminal',
            label: bgPresentation.title,
            clickable: true,
            actionKind: 'stop-background',
            actionLabel: input.backgroundStopPending ? '停止中…' : '停止',
            actionDisabled: !input.canOperateThread || input.backgroundStopPending,
            accessibilityLabel: bgPresentation.title + '，点击查看后台工作'
          });
        } else {
          const shell = input.shellThread;
          const snoozedUntil = shell ? shell.snoozedUntil : str(input.details.snoozedUntil);
          const lifecycleSnoozed = input.supportsSnooze && shell !== undefined &&
            effectiveSnoozed(shell, input.nowMs) && !limitRecoveryOwnsSnooze(input.details, snoozedUntil);
          const settled = input.supportsSettlement &&
            (shell ? shell.settledOverride === 'settled' : str(input.details.settledOverride) === 'settled');
          const wokeAt = shell ? shell.lastSnoozeWakeAt : str(input.details.lastSnoozeWakeAt);
          const lastVisited = shell ? shell.lastVisitedAt : str(input.details.lastVisitedAt);
          const latestCompleted = shell ? shell.latestRunCompletedAt : '';
          const wokeAtMs = wokeAt ? Date.parse(wokeAt) : NaN;
          const visitedMs = lastVisited ? Date.parse(lastVisited) : NaN;
          const completedMs = latestCompleted ? Date.parse(latestCompleted) : NaN;
          const wokeUnseen = input.supportsSnooze && !settled && !lifecycleSnoozed && Number.isFinite(wokeAtMs) &&
            (!Number.isFinite(visitedMs) || visitedMs < wokeAtMs) &&
            (!Number.isFinite(completedMs) || completedMs < wokeAtMs);

          if (lifecycleSnoozed && shell) {
            const wake = snoozeWakeLabel(shell, input.nowMs);
            status = buildStatus({
              kind: 'lifecycle',
              icon: 'clock',
              label: wake ? '已暂缓 · ' + wake + '后唤醒' : '已暂缓',
              actionKind: 'wake',
              actionLabel: '立即唤醒',
              actionDisabled: !input.canOperateThread
            });
          } else if (settled) {
            status = buildStatus({
              kind: 'lifecycle',
              icon: 'done',
              label: '已处理',
              actionKind: 'unsettle',
              actionLabel: '取消处理',
              actionDisabled: !input.canOperateThread
            });
          } else if (wokeUnseen) {
            status = buildStatus({
              kind: 'lifecycle',
              icon: 'clock',
              label: '暂缓已唤醒',
              actionKind: 'dismiss-woke',
              actionLabel: '知道了',
              actionDisabled: !input.canOperateThread
            });
          } else {
            const goal = resolveThreadGoal(input.providerThreads, input.details, shell);
            if (goal) {
              const title = goalTitle(goal, false);
              status = buildStatus({
                kind: 'goal',
                icon: 'target',
                label: title,
                accessibilityLabel: title + (str(goal.objective) ? '：' + str(goal.objective) : '')
              });
            } else if (!input.threadSynced) {
              status = buildStatus({
                kind: 'preparing',
                icon: 'spinner',
                label: '正在同步…'
              });
            } else if (!input.hasWorktreeSetupCard &&
              input.runs.some((run: Record<string, Object>) => str(run.status) === 'preparing')) {
              status = buildStatus({
                kind: 'preparing',
                icon: 'spinner',
                label: '正在启动…'
              });
            }
          }
        }
      }
    }
  }

  return {
    status,
    agents,
    queuedCount,
    visible: status !== undefined || agents !== undefined || queuedCount > 0
  };
}
