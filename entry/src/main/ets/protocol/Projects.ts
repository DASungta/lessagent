import { compactArray, compactObjects, objects, parseModelSelection, record, sequence, text } from './Wire';
import type { ModelSelection } from './Wire';

// Upstream mobile project/* and home/* rules translated without depending on React or Effect.

export interface RepositoryIdentityView {
  canonicalKey: string;
  groupingKey: string;
  displayName: string;
  name: string;
  rootPath: string;
}

export interface ProjectIconView {
  kind: string;
  name: string;
  color: string;
  emoji: string;
  text: string;
}

export const PROJECT_ICON_COLORS: string[] = [
  'gray', 'red', 'orange', 'amber', 'yellow', 'lime', 'green', 'emerald', 'teal',
  'cyan', 'sky', 'blue', 'indigo', 'violet', 'purple', 'fuchsia', 'pink', 'rose'
];

export const PROJECT_TRACKED_FOLDERS_MAX = 128;

export interface ProjectTrackedFolder {
  path: string;
  name: string;
  discovered?: boolean;
}

export interface ProjectView {
  defaultThreadEnvMode?: string | null;
  defaultModelSelection?: ModelSelection | null;
  id: string;
  label: string;
  projectId: string;
  workspaceRoot: string;
  repository: RepositoryIdentityView | undefined;
  trackedFolders?: ProjectTrackedFolder[];
  projectIcon?: ProjectIconView;
  pinnedAt: string;
  archivedAt: string;
  createdAt: string;
  updatedAt: string;
  hasCustomTitle: boolean;
}

export interface ThreadView {
  id: string;
  label: string;
  projectId: string;
  providerInstanceId: string;
  model: string;
  interactionMode: string;
  creationSource: string;
  branch: string;
  worktreePath: string;
  status: string;
  activityRunStatus: string;
  activityRunStartedAt: string;
  blockedOnThreadWait: boolean;
  activeRunId: string;
  latestRunId: string;
  latestRunRequestedAt: string;
  latestRunStartedAt: string;
  latestRunCompletedAt: string;
  lastError: string;
  lastErrorClass: string;
  createdAt: string;
  updatedAt: string;
  archivedAt: string;
  settledOverride: string;
  settledAt: string;
  unsettledAt: string;
  snoozedUntil: string;
  snoozedAt: string;
  pinnedAt: string;
  pinOrderKey: string;
  activeOrderKey: string;
  autoSettleDisabledAt: string;
  latestUserMessageAt: string;
  latestUserAuthoredMessageAt: string;
  lastVisitedAt: string;
  pendingKind: string;
  pendingAt: string;
  pendingUserOnly: boolean;
  pendingGuestMessageCount: number;
  hasActionableProposedPlan: boolean;
  titleRegenerationRequestId: string;
  titleRegenerationStartedAt: string;
  lineageRelationship: string;
  lineageParentThreadId: string;
  lineageSideChat: boolean;
  lineageWorkflowStep: boolean;
  delegatedFromEnvironmentId: string;
  delegatedFromThreadId: string;
  lastSnoozeWakeAt: string;
  pendingBackgroundTasks: Record<string, Object>[];
  goal: Record<string, Object> | undefined;
  deletedAt: string;
}

export interface ScopedProject extends ProjectView {
  localId: string;
  environmentId: string;
  environmentLabel: string;
  isScratch: boolean;
}

export interface ScopedThread extends ThreadView {
  localId: string;
  environmentId: string;
  environmentLabel: string;
  projectLabel: string;
  projectIcon?: ProjectIconView;
  pendingSubagentRequest?: string;
}

export interface ProjectRef { localId: string; environmentId: string; projectId: string; }

export interface ThreadProjectRef { environmentId: string; projectId: string; }

export function newTaskDestination(projects: ScopedProject[], readyLocalIds: string[], useLastProject: boolean,
  current: ThreadProjectRef | undefined, filtered: ProjectGroup | undefined, preferredLocalId: string,
  last: ThreadProjectRef | undefined): ScopedProject | undefined {
  if (!useLastProject) return undefined;
  const live = projects.filter((project: ScopedProject) =>
    !!project.environmentId && !project.archivedAt && readyLocalIds.includes(project.localId));
  const find = (ref: ThreadProjectRef | undefined): ScopedProject | undefined => ref === undefined ? undefined :
    live.find((project: ScopedProject) => project.environmentId === ref.environmentId && project.id === ref.projectId);
  const currentProject = find(current);
  if (currentProject) return currentProject;
  const remembered = find(last);
  if (filtered) {
    const members = live.filter((project: ScopedProject) => !project.isScratch &&
      filtered.projects.some((copy: ScopedProject) => copy.localId === project.localId && copy.id === project.id));
    if (remembered && members.includes(remembered)) return remembered;
    const preferred = members.find((project: ScopedProject) => project.localId === preferredLocalId);
    const representative = members.find((project: ScopedProject) =>
      project.localId === filtered.representative.localId && project.id === filtered.representative.id);
    if (preferred || representative || members[0]) return preferred || representative || members[0];
  }
  return remembered && !remembered.isScratch ? remembered : undefined;
}

export interface ProjectGroup {
  key: string;
  label: string;
  representative: ScopedProject;
  projects: ScopedProject[];
  projectRefs: ProjectRef[];
  pinned: boolean;
  archived: boolean;
}

export interface SnoozePresetSetting {
  kind: string;
  minutes: number;
  day: string;
  time: string;
}

export interface SnoozePreset {
  id: string;
  label: string;
  whenLabel: string;
  snoozedUntil: string;
}

export interface CustomSnoozeInput {
  mode: string;
  date: string;
  time: string;
  amount: string;
  unit: string;
}

export interface ThreadShelfState {
  workingShelfEnabled: boolean;
  pinned: ScopedThread[];
  active: ScopedThread[];
  working: ScopedThread[];
  snoozed: ScopedThread[];
  settled: ScopedThread[];
  matches: ScopedThread[];
  workingCount: number;
  snoozedCount: number;
  settledCount: number;
}

export interface ThreadCapabilities {
  settlement: boolean;
  snooze: boolean;
  pinning: boolean;
  pinReorder: boolean;
  activeReorder: boolean;
  autoSettleOptOut: boolean;
  titleRegeneration: boolean;
}

export interface ThreadSearchHit { threadId: string; snippet: string; }

export interface ArchiveProjectGroup {
  key: string;
  project: ScopedProject;
  threads: ScopedThread[];
}

export interface ArchiveEnvironmentEntry {
  localId: string;
  environmentId: string;
  label: string;
}

export const DEFAULT_SNOOZE_PRESETS: SnoozePresetSetting[] = [
  { kind: 'after', minutes: 60, day: '', time: '' },
  { kind: 'after', minutes: 180, day: '', time: '' },
  { kind: 'at', minutes: 0, day: 'today', time: '18:00' },
  { kind: 'at', minutes: 0, day: 'tomorrow', time: '09:00' },
  { kind: 'at', minutes: 0, day: 'monday', time: '09:00' }
];

export function snoozeSettingsFrom(value: Object | undefined): SnoozePresetSetting[] {
  if (value === undefined || value === null || !Array.isArray(value)) return DEFAULT_SNOOZE_PRESETS.slice();
  const rows = value as Object[];
  if (!rows.length || rows.length > 8) return DEFAULT_SNOOZE_PRESETS.slice();
  const result: SnoozePresetSetting[] = [];
  for (const item of rows) {
    try {
      const row = record(item);
      const kind = text(row.kind);
      if (kind === 'after') {
        const minutes = row.minutes as number;
        if (!Number.isSafeInteger(minutes) || minutes < 1 || minutes > 43200) continue;
        result.push({ kind, minutes, day: '', time: '' });
      } else if (kind === 'at') {
        const day = text(row.day);
        const time = text(row.time);
        if (!WEEKDAYS.includes(day) && day !== 'today' && day !== 'tomorrow') continue;
        if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(time)) continue;
        result.push({ kind, minutes: 0, day, time });
      }
    } catch (_) {}
  }
  return result.length > 0 ? result : DEFAULT_SNOOZE_PRESETS.slice();
}

export function offeredProvidersFrom(value: Object | undefined): Record<string, boolean> {
  const result: Record<string, boolean> = {};
  if (value === undefined || value === null) return result;
  const row = record(value);
  for (const key of Object.keys(row)) result[key] = row[key] === true;
  return result;
}

function cleanId(value: Object, label: string): string {
  const result = text(value);
  if (!result || result.length > 256 || /[\u0000-\u001f\u007f]/.test(result)) throw new Error(label + '无效');
  return result;
}

function cleanDisplayText(value: Object | undefined, label: string, fallback: string = ''): string {
  if (value === undefined || value === null) {
    if (fallback) return fallback;
    throw new Error(label + '无效');
  }
  const result = text(value).replace(/[\u0000-\u001f\u007f]+/g, ' ').trim();
  if (!result) {
    if (fallback) return fallback;
    throw new Error(label + '无效');
  }
  return result.length > 1024 ? result.slice(0, 1024) : result;
}

function optionalDisplayText(value: Object | undefined): string {
  if (value === undefined || value === null || typeof value !== 'string') return '';
  const result = value.replace(/[\u0000-\u001f\u007f]+/g, ' ').trim();
  return result.length > 1024 ? result.slice(0, 1024) : result;
}

function optionalText(value: Object | undefined, label: string): string {
  if (value === undefined || value === null) return '';
  return cleanId(value, label);
}

function optionalIso(value: Object | undefined, label: string): string {
  if (value === undefined || value === null || value === '') return '';
  const result = text(value);
  if (!result || !Number.isFinite(Date.parse(result))) throw new Error(label + '无效');
  return result;
}

function optionalBoolean(value: Object | undefined): boolean {
  return value === true;
}

function repositoryIdentity(value: Object | undefined): RepositoryIdentityView | undefined {
  if (value === undefined || value === null || typeof value !== 'object' || Array.isArray(value)) return undefined;
  try {
    const row = record(value);
    const canonicalKey = cleanId(row.canonicalKey, '仓库身份');
    const origin = row.origin === undefined || row.origin === null ? undefined : record(row.origin);
    const originKey = origin === undefined ? '' : optionalText(origin.canonicalKey, '仓库来源身份');
    const displayName = origin !== undefined ? optionalDisplayText(origin.displayName) :
      optionalDisplayText(row.displayName);
    return {
      canonicalKey,
      groupingKey: originKey || canonicalKey,
      displayName,
      name: optionalDisplayText(row.name),
      rootPath: optionalDisplayText(row.rootPath)
    };
  } catch (_) {
    return undefined;
  }
}

export function parseProjectIcon(value: Object | undefined): ProjectIconView | undefined {
  if (value === undefined || value === null || typeof value !== 'object' || Array.isArray(value)) return undefined;
  const row = value as Record<string, Object>;
  const kind = typeof row.kind === 'string' ? row.kind.trim() : '';
  const rawColor = typeof row.color === 'string' ? row.color.trim().toLowerCase() : '';
  const validColor = PROJECT_ICON_COLORS.includes(rawColor) ? rawColor : '';
  if (kind === 'lucide') {
    const legacyMono = typeof row.monogramText === 'string' ? row.monogramText.trim() :
      (typeof row.monogram === 'string' ? row.monogram.trim() : '');
    if (legacyMono.length > 0 && legacyMono.length <= 32) {
      return { kind: 'monogram', name: '', color: validColor || 'blue', emoji: '', text: legacyMono };
    }
    const name = typeof row.name === 'string' ? row.name.trim().toLowerCase() : '';
    if (!name || name.length > 64 || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(name)) return undefined;
    return { kind: 'lucide', name, color: validColor || 'gray', emoji: '', text: '' };
  }
  if (kind === 'emoji') {
    const emoji = typeof row.emoji === 'string' ? row.emoji.trim() : '';
    if (!emoji || emoji.length > 32) return undefined;
    return { kind: 'emoji', name: '', color: '', emoji, text: '' };
  }
  if (kind === 'monogram') {
    const mono = typeof row.text === 'string' ? row.text.trim() : '';
    if (!mono || mono.length > 32) return undefined;
    return { kind: 'monogram', name: '', color: validColor || 'blue', emoji: '', text: mono };
  }
  return undefined;
}

export function groupProjectIcon(group: ProjectGroup | undefined): ProjectIconView | undefined {
  if (group === undefined) return undefined;
  if (group.representative.projectIcon !== undefined) return group.representative.projectIcon;
  return group.projects.find((project: ScopedProject) => project.projectIcon !== undefined)?.projectIcon;
}

export function parseProjectTrackedFolders(value: Object | undefined): ProjectTrackedFolder[] | undefined {
  if (value === undefined || value === null) return undefined;
  if (!Array.isArray(value)) return undefined;
  const result: ProjectTrackedFolder[] = [];
  const seen = new Set<string>();
  for (const entry of value as Object[]) {
    if (result.length >= PROJECT_TRACKED_FOLDERS_MAX) break;
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry)) continue;
    const row = entry as Record<string, Object>;
    if (typeof row.path !== 'string' || typeof row.name !== 'string') continue;
    const folderPath = row.path.trim();
    const folderName = row.name.replace(/[\u0000-\u001f\u007f]+/g, ' ').trim();
    if (!folderPath || folderPath.length > 2048 || /[\u0000-\u001f\u007f]/.test(folderPath)) continue;
    if (!folderName || folderName.length > 128) continue;
    if (seen.has(folderPath)) continue;
    seen.add(folderPath);
    const folder: ProjectTrackedFolder = { path: folderPath, name: folderName };
    if (row.discovered === true) folder.discovered = true;
    result.push(folder);
  }
  return result;
}

export function projectView(value: Object): ProjectView {
  const row = record(value);
  const rawMode = row.defaultThreadEnvMode;
  const defaultThreadEnvMode: string | null | undefined =
    rawMode === 'local' ? 'local' : (rawMode === 'worktree' ? 'worktree' : (rawMode === null ? null : undefined));
  const defaultModelSelection = row.defaultModelSelection === undefined ? undefined :
    row.defaultModelSelection === null ? null : parseModelSelection(row.defaultModelSelection);
  const trackedFolders = parseProjectTrackedFolders(row.trackedFolders);
  const id = cleanId(row.id, '项目标识');
  return {
    defaultThreadEnvMode,
    defaultModelSelection,
    id,
    label: cleanDisplayText(row.title, '项目名称', id),
    projectId: id,
    workspaceRoot: optionalDisplayText(row.workspaceRoot),
    repository: repositoryIdentity(row.repositoryIdentity),
    ...(trackedFolders !== undefined ? { trackedFolders } : {}),
    projectIcon: parseProjectIcon(row.projectIcon),
    pinnedAt: optionalIso(row.pinnedAt, '项目固定时间'),
    archivedAt: optionalIso(row.archivedAt, '项目归档时间'),
    createdAt: optionalIso(row.createdAt, '项目创建时间'),
    updatedAt: optionalIso(row.updatedAt, '项目更新时间'),
    hasCustomTitle: optionalBoolean(row.hasCustomTitle)
  };
}

function modelSelection(value: Object | undefined): { instanceId: string; model: string } {
  if (value === undefined || value === null) return { instanceId: '', model: '' };
  const row = record(value);
  return { instanceId: optionalText(row.instanceId, 'Provider 实例'), model: optionalText(row.model, '模型') };
}

export function threadView(value: Object): ThreadView {
  const row = record(value);
  const model = modelSelection(row.modelSelection);
  const pending = row.pendingRuntimeRequest === undefined || row.pendingRuntimeRequest === null ? undefined : record(row.pendingRuntimeRequest);
  const lineage = row.lineage === undefined || row.lineage === null ? undefined : record(row.lineage);
  const delegatedFrom = row.delegatedFrom === undefined || row.delegatedFrom === null ? undefined : record(row.delegatedFrom);
  const titleRegeneration = row.titleRegeneration === undefined || row.titleRegeneration === null ? undefined : record(row.titleRegeneration);
  return {
    id: cleanId(row.id, '会话标识'),
    label: cleanDisplayText(row.title, '会话名称', '新会话'),
    projectId: cleanId(row.projectId, '会话项目'),
    providerInstanceId: (typeof row.providerInstanceId === 'string' ? row.providerInstanceId : '') || model.instanceId,
    model: model.model,
    interactionMode: typeof row.interactionMode === 'string' ? row.interactionMode : '',
    creationSource: typeof row.creationSource === 'string' ? row.creationSource : '',
    branch: optionalDisplayText(row.branch),
    worktreePath: optionalDisplayText(row.worktreePath),
    status: typeof row.status === 'string' ? row.status : '',
    activityRunStatus: typeof row.activityRunStatus === 'string' ? row.activityRunStatus : '',
    activityRunStartedAt: optionalIso(row.activityRunStartedAt, '活动运行开始时间'),
    blockedOnThreadWait: optionalBoolean(row.blockedOnThreadWait),
    activeRunId: optionalText(row.activeRunId, '活动运行'),
    latestRunId: optionalText(row.latestRunId, '最近运行'),
    latestRunRequestedAt: optionalIso(row.latestRunRequestedAt, '运行请求时间'),
    latestRunStartedAt: optionalIso(row.latestRunStartedAt, '运行开始时间'),
    latestRunCompletedAt: optionalIso(row.latestRunCompletedAt, '运行完成时间'),
    lastError: typeof row.lastError === 'string' ? row.lastError : '',
    lastErrorClass: typeof row.lastErrorClass === 'string' ? row.lastErrorClass : '',
    createdAt: optionalIso(row.createdAt, '会话创建时间'),
    updatedAt: optionalIso(row.updatedAt, '会话更新时间'),
    archivedAt: optionalIso(row.archivedAt, '会话归档时间'),
    settledOverride: typeof row.settledOverride === 'string' ? row.settledOverride : '',
    settledAt: optionalIso(row.settledAt, '会话 settle 时间'),
    unsettledAt: optionalIso(row.unsettledAt, '会话 unsettle 时间'),
    snoozedUntil: optionalIso(row.snoozedUntil, '暂缓截止时间'),
    snoozedAt: optionalIso(row.snoozedAt, '暂缓时间'),
    pinnedAt: optionalIso(row.pinnedAt, '会话固定时间'),
    pinOrderKey: optionalDisplayText(row.pinOrderKey),
    activeOrderKey: optionalDisplayText(row.activeOrderKey),
    autoSettleDisabledAt: optionalIso(row.autoSettleDisabledAt, '自动 settle 设置时间'),
    latestUserMessageAt: optionalIso(row.latestUserMessageAt, '最近用户消息时间'),
    latestUserAuthoredMessageAt: optionalIso(row.latestUserAuthoredMessageAt, '最近用户编写消息时间'),
    lastVisitedAt: optionalIso(row.lastVisitedAt, '最近访问时间'),
    pendingKind: pending !== undefined && typeof pending.kind === 'string' ? pending.kind : '',
    pendingAt: pending === undefined ? '' : optionalIso(pending.createdAt, '请求时间'),
    pendingUserOnly: pending !== undefined && optionalBoolean(pending.userOnly),
    pendingGuestMessageCount: typeof row.pendingGuestMessageCount === 'number' && Number.isFinite(row.pendingGuestMessageCount) ?
      row.pendingGuestMessageCount as number : 0,
    hasActionableProposedPlan: optionalBoolean(row.hasActionableProposedPlan),
    titleRegenerationRequestId: titleRegeneration === undefined ? '' : optionalText(titleRegeneration.requestId, '重生成请求'),
    titleRegenerationStartedAt: titleRegeneration === undefined ? '' : optionalIso(titleRegeneration.startedAt, '重生成时间'),
    lineageRelationship: lineage === undefined ? '' : optionalText(lineage.relationshipToParent, '会话关系'),
    lineageParentThreadId: lineage === undefined ? '' : optionalText(lineage.parentThreadId, '父会话'),
    lineageSideChat: lineage !== undefined && optionalBoolean(lineage.sideChat),
    lineageWorkflowStep: lineage !== undefined && optionalBoolean(lineage.workflowStep),
    delegatedFromEnvironmentId: delegatedFrom === undefined ? '' : optionalText(delegatedFrom.environmentId, '委派来源环境'),
    delegatedFromThreadId: delegatedFrom === undefined ? '' : optionalText(delegatedFrom.threadId, '委派来源会话'),
    lastSnoozeWakeAt: optionalIso(row.lastSnoozeWakeAt, '暂缓唤醒时间'),
    pendingBackgroundTasks: compactObjects(row.pendingBackgroundTasks),
    goal: row.goal !== undefined && row.goal !== null && typeof row.goal === 'object' && !Array.isArray(row.goal)
      ? row.goal as Record<string, Object> : undefined,
    deletedAt: optionalIso(row.deletedAt, '会话删除时间')
  };
}

export function isListedThread(thread: ThreadView): boolean {
  return thread.lineageRelationship !== 'subagent' && !thread.lineageSideChat && !thread.lineageWorkflowStep;
}

export function hasPendingApprovals(thread: ThreadView): boolean {
  return !!thread.pendingKind && thread.pendingKind !== 'user_input' && thread.pendingKind !== 'auth_refresh';
}

export function hasPendingUserInput(thread: ThreadView): boolean {
  return thread.pendingKind === 'user_input';
}

export function threadBackgroundWorkHoldsCompletion(tasks: Record<string, Object>[] | undefined): boolean {
  if (!tasks || !tasks.length) return false;
  return tasks.some((task: Record<string, Object>) => {
    if (task.awaited === true) return true;
    const kind = typeof task.kind === 'string' ? task.kind : '';
    return kind === 'subagent' || kind === 'background_task';
  });
}

export function threadParkedOnBackgroundWork(thread: ThreadView): boolean {
  return threadBackgroundWorkHoldsCompletion(thread.pendingBackgroundTasks) && thread.status !== 'failed';
}

function threadPendingSubagentRequest(thread: ThreadView): string {
  const scoped = thread as ScopedThread;
  return typeof scoped.pendingSubagentRequest === 'string' ? scoped.pendingSubagentRequest : '';
}

function runtimeStatus(thread: ThreadView): string {
  if (threadParkedOnBackgroundWork(thread)) return 'idle';
  return thread.activityRunStatus || thread.status;
}

export function threadIsSettled(thread: ThreadView, caps?: ThreadCapabilities): boolean {
  return (caps === undefined || caps.settlement) && thread.settledOverride === 'settled';
}

export function threadHasUnseenCompletion(thread: ThreadView): boolean {
  if (thread.settledOverride === 'settled') return false;
  if (!thread.latestRunCompletedAt || !thread.lastVisitedAt) return false;
  const status = thread.activityRunStatus || thread.status;
  if (status === 'interrupted' || status === 'cancelled' || status === 'failed') return false;
  const completedAtMs = Date.parse(thread.latestRunCompletedAt);
  if (!Number.isFinite(completedAtMs)) return false;
  const lastVisitedAtMs = Date.parse(thread.lastVisitedAt);
  if (!Number.isFinite(lastVisitedAtMs)) return true;
  return completedAtMs > lastVisitedAtMs;
}

export function hasUnseenRunFailure(thread: ThreadView): boolean {
  if (!thread.latestRunCompletedAt || !thread.lastVisitedAt) return true;
  const failedAtMs = Date.parse(thread.latestRunCompletedAt);
  const visitedAtMs = Date.parse(thread.lastVisitedAt);
  if (!Number.isFinite(failedAtMs) || !Number.isFinite(visitedAtMs)) return true;
  return failedAtMs > visitedAtMs;
}

export function threadIsWorking(thread: ThreadView): boolean {
  if (hasPendingApprovals(thread) || hasPendingUserInput(thread)) return false;
  if (threadPendingSubagentRequest(thread) !== '') return false;
  if (thread.pendingGuestMessageCount > 0) return false;
  const parked = threadParkedOnBackgroundWork(thread);
  const status = parked ? 'idle' : (thread.activityRunStatus || thread.status);
  const active = ['preparing', 'queued', 'starting', 'running', 'waiting'].includes(status);
  if (!active && !parked) return false;
  const runSettled =
    thread.latestRunId !== '' &&
    !['preparing', 'queued', 'starting', 'running', 'waiting'].includes(thread.status) &&
    thread.activeRunId !== thread.latestRunId;
  if (thread.interactionMode === 'plan' && thread.hasActionableProposedPlan && runSettled) {
    return false;
  }
  return true;
}

// Upstream threadRuntimeCanArchive: queued may archive only without an active run.
export function threadCanArchive(thread: ThreadView): boolean {
  const status = runtimeStatus(thread);
  if (status === 'queued') return thread.activeRunId === '';
  return status !== 'preparing' && status !== 'starting' && status !== 'running';
}

export function threadCanSnooze(thread: ThreadView, nowMs: number): boolean {
  if (hasPendingApprovals(thread)) return false;
  if (thread.pendingKind && thread.pendingKind !== 'user_input') return false;
  if (threadPendingSubagentRequest(thread) !== '') return false;
  if (thread.pendingGuestMessageCount > 0) return false;
  if (['preparing', 'queued', 'starting'].includes(runtimeStatus(thread))) return false;
  const messageAt = Date.parse(thread.latestUserMessageAt);
  if (Number.isFinite(messageAt) && Math.abs(nowMs - messageAt) <= 2 * 60 * 1000) {
    const requested = Date.parse(thread.latestRunRequestedAt);
    const started = Date.parse(thread.latestRunStartedAt);
    const completed = Date.parse(thread.latestRunCompletedAt);
    return [requested, started, completed].some((value: number) => Number.isFinite(value) && value >= messageAt);
  }
  return true;
}

function pendingQuestionAt(thread: ThreadView): number {
  if (!hasPendingUserInput(thread) || !thread.pendingAt) return NaN;
  return Date.parse(thread.pendingAt);
}

function failedAt(thread: ThreadView): number {
  if (thread.status !== 'failed' && thread.lastErrorClass === '' && thread.lastError === '') return NaN;
  if (thread.latestRunCompletedAt) return Date.parse(thread.latestRunCompletedAt);
  return NaN;
}

export function threadRaisedHand(thread: ThreadView): boolean {
  if (hasPendingApprovals(thread)) return true;
  if (threadPendingSubagentRequest(thread) !== '') return true;
  const snoozedAt = Date.parse(thread.snoozedAt);
  const questionAt = pendingQuestionAt(thread);
  if (hasPendingUserInput(thread) && (!Number.isFinite(snoozedAt) || !Number.isFinite(questionAt) || questionAt > snoozedAt)) return true;
  if (thread.pendingGuestMessageCount > 0) return true;
  const failureAt = failedAt(thread);
  return Number.isFinite(failureAt) && (!Number.isFinite(snoozedAt) || failureAt > snoozedAt);
}

export function effectiveSnoozed(thread: ThreadView, nowMs: number): boolean {
  const wake = Date.parse(thread.snoozedUntil);
  return Number.isFinite(wake) && wake > nowMs && !threadRaisedHand(thread);
}

export function snoozeWakeLabel(thread: ThreadView, nowMs: number): string {
  const wake = Date.parse(thread.snoozedUntil);
  if (!Number.isFinite(wake) || wake <= nowMs) return '';
  const minutes = Math.max(1, Math.floor(wake / 60000) - Math.floor(nowMs / 60000));
  if (minutes < 60) return minutes + ' 分钟';
  if (minutes < 1440) return Math.ceil(minutes / 60) + ' 小时';
  return Math.ceil(minutes / 1440) + ' 天';
}

export function threadSortTimestamp(thread: ThreadView, sortOrder: string): number {
  if (sortOrder === 'created_at') {
    const created = Date.parse(thread.createdAt);
    return Number.isFinite(created) ? created : Date.parse(thread.updatedAt);
  }
  const authored = Date.parse(thread.latestUserAuthoredMessageAt);
  if (Number.isFinite(authored)) return authored;
  const user = Date.parse(thread.latestUserMessageAt);
  if (Number.isFinite(user)) return user;
  const updated = Date.parse(thread.updatedAt);
  return Number.isFinite(updated) ? updated : Date.parse(thread.createdAt);
}

function settledTimestamp(thread: ThreadView): number {
  const settled = Date.parse(thread.settledAt);
  if (Number.isFinite(settled)) return settled;
  for (const value of [thread.latestUserMessageAt, thread.latestRunRequestedAt, thread.latestRunStartedAt,
    thread.latestRunCompletedAt, thread.updatedAt]) {
    const parsed = Date.parse(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return 0;
}

function identityTiebreak(left: ScopedThread, right: ScopedThread): number {
  return left.id.localeCompare(right.id) || left.environmentId.localeCompare(right.environmentId);
}

export function sortPinned(threads: ScopedThread[]): ScopedThread[] {
  return threads.slice().sort((left: ScopedThread, right: ScopedThread) => {
    if (left.pinOrderKey !== right.pinOrderKey) return left.pinOrderKey < right.pinOrderKey ? -1 : 1;
    return Date.parse(left.createdAt) - Date.parse(right.createdAt) || identityTiebreak(left, right);
  });
}

export function sortActive(threads: ScopedThread[]): ScopedThread[] {
  return threads.slice().sort((left: ScopedThread, right: ScopedThread) => {
    if (!left.activeOrderKey && right.activeOrderKey) return -1;
    if (left.activeOrderKey && !right.activeOrderKey) return 1;
    if (left.activeOrderKey && right.activeOrderKey) {
      return (left.activeOrderKey < right.activeOrderKey ? -1 : left.activeOrderKey > right.activeOrderKey ? 1 : 0) ||
        identityTiebreak(left, right);
    }
    return newestTimestamp([right.createdAt, right.unsettledAt]) -
      newestTimestamp([left.createdAt, left.unsettledAt]) || identityTiebreak(left, right);
  });
}

function newestTimestamp(values: string[]): number {
  return Math.max(0, ...values.map((value: string) => Date.parse(value) || 0));
}

function inboxReturnAt(thread: ScopedThread): number {
  return newestTimestamp([thread.createdAt, thread.unsettledAt, thread.latestRunRequestedAt,
    thread.latestRunCompletedAt, thread.pendingAt]);
}

export function sortSettled(threads: ScopedThread[]): ScopedThread[] {
  return threads.slice().sort((left: ScopedThread, right: ScopedThread) =>
    settledTimestamp(right) - settledTimestamp(left) || identityTiebreak(left, right));
}

export function sortSnoozed(threads: ScopedThread[]): ScopedThread[] {
  return threads.slice().sort((left: ScopedThread, right: ScopedThread) =>
    Date.parse(left.snoozedUntil) - Date.parse(right.snoozedUntil) || identityTiebreak(left, right));
}

export function searchText(value: string): string {
  return value.trim().normalize('NFKD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
}

export function threadMatchesQuery(thread: ScopedThread, query: string, snippet: string = ''): boolean {
  const needle = searchText(query);
  if (!needle) return true;
  return [thread.label, thread.projectLabel, thread.environmentLabel, thread.branch, snippet]
    .some((value: string) => searchText(value).includes(needle));
}

export function threadSearchScore(thread: ScopedThread, query: string, snippet: string = ''): number {
  const needle = searchText(query);
  if (!needle) return 0;
  const title = searchText(thread.label);
  if (title === needle) return 100;
  if (title.startsWith(needle)) return 80;
  if (title.includes(needle)) return 60;
  if ([thread.projectLabel, thread.branch, thread.environmentLabel]
    .some((value: string) => searchText(value).includes(needle))) return 40;
  if (searchText(snippet).includes(needle)) return 20;
  return 10;
}

export function projectMatchesQuery(project: ScopedProject, query: string): boolean {
  const needle = searchText(query);
  return !needle || [project.label, project.workspaceRoot, project.environmentLabel]
    .some((value: string) => searchText(value).includes(needle));
}

export function normalizePathForComparison(value: string): string {
  const trimmed = value.trim().replace(/\\/g, '/').replace(/\/+$/, '');
  return /^[a-zA-Z]:/.test(trimmed) || trimmed.startsWith('//') ? trimmed.toLowerCase() : trimmed;
}

export function samePath(left: string, right: string): boolean {
  return normalizePathForComparison(left) === normalizePathForComparison(right);
}

function relativeToRoot(project: ScopedProject): string {
  const identity = project.repository;
  if (identity === undefined || !identity.rootPath) return '';
  const root = normalizePathForComparison(identity.rootPath);
  const path = normalizePathForComparison(project.workspaceRoot);
  if (path === root) return '';
  return path.startsWith(root + '/') ? path.slice(root.length + 1) : '';
}

function physicalKey(project: ScopedProject): string {
  return project.localId + ':' + normalizePathForComparison(project.workspaceRoot);
}

function logicalKey(project: ScopedProject, mode: string): string {
  if (project.isScratch) return '\u0000no-project';
  if (mode === 'separate') return physicalKey(project);
  const identity = project.repository;
  if (identity === undefined) return physicalKey(project);
  if (mode === 'repository_path') {
    const relative = relativeToRoot(project);
    return relative ? identity.groupingKey + '::' + relative : identity.groupingKey;
  }
  return identity.groupingKey;
}

function uniqueStrings(values: string[]): string[] {
  const result: string[] = [];
  for (const value of values) if (value && !result.includes(value)) result.push(value);
  return result;
}

function projectUpdatedAt(project: ScopedProject): number {
  const updated = Date.parse(project.updatedAt);
  return Number.isFinite(updated) ? updated : Date.parse(project.createdAt);
}

function groupLabel(groupKey: string, representative: ScopedProject, members: ScopedProject[]): string {
  if (members.length === 1) return representative.isScratch ? 'No project' : representative.label;
  const titles = uniqueStrings(members.map((member: ScopedProject) => member.label));
  const displayNames = uniqueStrings(members.map((member: ScopedProject) =>
    member.repository === undefined ? '' : member.repository.displayName));
  const names = uniqueStrings(members.map((member: ScopedProject) =>
    member.repository === undefined ? '' : member.repository.name));
  if (titles.length === 1 && (members.some((member: ScopedProject) => member.hasCustomTitle) ||
    (!displayNames.includes(titles[0]) && !names.includes(titles[0])))) return titles[0];
  if (displayNames.length === 1) return displayNames[0];
  if (names.length === 1) return names[0];
  const identity = representative.repository;
  if (identity !== undefined && groupKey === identity.groupingKey) {
    return identity.displayName || identity.name || representative.label;
  }
  return representative.label;
}

export function buildProjectGroups(projects: ScopedProject[], mode: string): ProjectGroup[] {
  const winners = new Map<string, ScopedProject>();
  for (const project of projects) {
    const key = physicalKey(project);
    const current = winners.get(key);
    if (current === undefined || projectUpdatedAt(project) > projectUpdatedAt(current) ||
      (projectUpdatedAt(project) === projectUpdatedAt(current) && project.id > current.id)) winners.set(key, project);
  }
  const members = new Map<string, ScopedProject[]>();
  const refs = new Map<string, ProjectRef[]>();
  for (const winner of winners.values()) {
    const key = logicalKey(winner, mode);
    const existing = members.get(key);
    if (existing === undefined) members.set(key, [winner]); else existing.push(winner);
  }
  for (const project of projects) {
    const key = logicalKey(winners.get(physicalKey(project)) || project, mode);
    const existing = refs.get(key);
    const ref: ProjectRef = { localId: project.localId, environmentId: project.environmentId, projectId: project.id };
    if (existing === undefined) refs.set(key, [ref]); else existing.push(ref);
  }
  const result: ProjectGroup[] = [];
  members.forEach((groupMembers: ScopedProject[], key: string) => {
    const representative = groupMembers[0];
    result.push({
      key,
      label: groupLabel(key, representative, groupMembers),
      representative,
      projects: groupMembers,
      projectRefs: refs.get(key) || [],
      pinned: groupMembers.some((project: ScopedProject) => !!project.pinnedAt),
      archived: groupMembers.every((project: ScopedProject) => !!project.archivedAt)
    });
  });
  return result;
}

export function pickableProjectGroups(groups: ProjectGroup[]): ProjectGroup[] {
  const open = groups.filter((group: ProjectGroup) => !group.archived && !group.representative.isScratch);
  return open.filter((group: ProjectGroup) => group.pinned)
    .concat(open.filter((group: ProjectGroup) => !group.pinned));
}

export function sortProjectGroups(groups: ProjectGroup[], threads: ScopedThread[]): ProjectGroup[] {
  const activity = new Map<string, number>();
  for (const group of groups) {
    for (const ref of group.projectRefs) activity.set(ref.localId + ':' + ref.projectId, 0);
  }
  const underParent = delegatedUnderParentKeys(threads);
  for (const thread of threads) {
    const key = thread.localId + ':' + thread.projectId;
    if (!activity.has(key) || thread.archivedAt || isShownUnderParent(thread, underParent)) continue;
    activity.set(key, Math.max(activity.get(key) || 0, threadSortTimestamp(thread, 'updated_at')));
  }
  return groups.slice().sort((left: ProjectGroup, right: ProjectGroup) => {
    const leftTime = Math.max(0, ...left.projectRefs.map((ref: ProjectRef) => activity.get(ref.localId + ':' + ref.projectId) || 0));
    const rightTime = Math.max(0, ...right.projectRefs.map((ref: ProjectRef) => activity.get(ref.localId + ':' + ref.projectId) || 0));
    return rightTime - leftTime || left.label.localeCompare(right.label) || left.key.localeCompare(right.key);
  });
}

export function projectGroupRefs(group: ProjectGroup | undefined): string[] {
  if (group === undefined) return [];
  return group.projectRefs.map((ref: ProjectRef) => ref.localId + '\u0000' + ref.projectId);
}

export function threadInProjectRefs(thread: ScopedThread, refs: string[]): boolean {
  return refs.length === 0 || refs.includes(thread.localId + '\u0000' + thread.projectId);
}

function threadScopeKey(environmentId: string, threadId: string): string {
  return environmentId + '\u0000' + threadId;
}

function isChildRunLiveForRollup(thread: ThreadView): boolean {
  if (thread.activityRunStatus) return true;
  return ['preparing', 'starting', 'running', 'waiting'].includes(thread.status);
}

function ownSubagentRollupRequest(thread: ThreadView): string {
  if (!thread.pendingKind || thread.pendingKind === 'auth_refresh') return '';
  if (thread.lineageRelationship !== 'subagent' && !thread.delegatedFromThreadId) return '';
  if (thread.creationSource === 'provider' && thread.lineageRelationship === 'subagent') return '';
  if (!isChildRunLiveForRollup(thread)) return '';
  if (thread.pendingKind !== 'user_input') return 'approval';
  return thread.pendingUserOnly ? 'user_only_input' : 'user_input';
}

function ownSideChatRollupRequest(thread: ThreadView): string {
  if (!thread.pendingKind || thread.pendingKind === 'auth_refresh' || !thread.lineageSideChat) return '';
  return thread.pendingKind === 'user_input' ? 'user_input' : 'approval';
}

export function attachPendingSubagentRequests(threads: ScopedThread[]): ScopedThread[] {
  if (!threads.length) return threads;
  const byKey = new Map<string, ScopedThread>();
  for (const thread of threads) {
    if (thread.archivedAt || thread.deletedAt) continue;
    const env = thread.environmentId || thread.localId;
    byKey.set(threadScopeKey(env, thread.id), thread);
  }
  const rolledUp = new Map<string, string>();
  const mergeFlag = (targetKey: string, req: string): boolean => {
    if (!targetKey || !req) return false;
    const current = rolledUp.get(targetKey) || '';
    if (current === 'approval' || current === req) return false;
    if (current === 'user_only_input' && req === 'user_input') return false;
    rolledUp.set(targetKey, req);
    return true;
  };
  const propagateUpLineage = (firstParentKey: string, req: string, startChildKey: string): boolean => {
    if (req === 'user_input') return false;
    let changed = false;
    const seen = new Set<string>(startChildKey ? [startChildKey] : []);
    let parentKey = firstParentKey;
    while (parentKey && !seen.has(parentKey)) {
      seen.add(parentKey);
      if (mergeFlag(parentKey, req)) changed = true;
      const parent = byKey.get(parentKey);
      if (parent && (parent.lineageRelationship === 'subagent' || parent.lineageSideChat) && parent.lineageParentThreadId) {
        parentKey = threadScopeKey(parent.environmentId || parent.localId, parent.lineageParentThreadId);
      } else {
        parentKey = '';
      }
    }
    return changed;
  };
  for (const child of threads) {
    if (child.archivedAt || child.deletedAt) continue;
    const env = child.environmentId || child.localId;
    if (child.lineageSideChat) {
      const req = ownSideChatRollupRequest(child);
      if (req && child.lineageParentThreadId) {
        mergeFlag(threadScopeKey(env, child.lineageParentThreadId), req);
      }
      continue;
    }
    if (child.lineageRelationship !== 'subagent' || !child.lineageParentThreadId) continue;
    const req = ownSubagentRollupRequest(child);
    if (req) {
      propagateUpLineage(threadScopeKey(env, child.lineageParentThreadId), req, threadScopeKey(env, child.id));
    }
  }
  let changed = true;
  while (changed) {
    changed = false;
    for (const child of threads) {
      if (child.archivedAt || child.deletedAt) continue;
      if (!child.delegatedFromThreadId || !child.delegatedFromEnvironmentId) continue;
      const env = child.environmentId || child.localId;
      if (child.delegatedFromEnvironmentId === env) continue;
      const childKey = threadScopeKey(env, child.id);
      const own = ownSubagentRollupRequest(child);
      const nested = rolledUp.get(childKey) || '';
      const req = own === 'approval' ? own : (nested || own);
      if (req && req !== 'user_input') {
        if (propagateUpLineage(threadScopeKey(child.delegatedFromEnvironmentId, child.delegatedFromThreadId), req, childKey)) {
          changed = true;
        }
      }
    }
  }
  if (rolledUp.size === 0) return threads;
  return threads.map((thread: ScopedThread): ScopedThread => {
    const key = threadScopeKey(thread.environmentId || thread.localId, thread.id);
    const rawDerived = rolledUp.get(key) || '';
    const derived = rawDerived === 'user_only_input' ? 'user_input' : rawDerived;
    const existing = typeof thread.pendingSubagentRequest === 'string' ? thread.pendingSubagentRequest : '';
    const effective = derived === 'approval' || existing === 'approval' ? 'approval' : (derived || existing);
    if (effective === existing) return thread;
    return { ...thread, pendingSubagentRequest: effective };
  });
}

export function delegatedUnderParentKeys(threads: ScopedThread[]): Set<string> {
  const activeByKey = new Set<string>();
  for (const thread of threads) {
    if (thread.archivedAt || thread.deletedAt) continue;
    activeByKey.add(threadScopeKey(thread.environmentId || thread.localId, thread.id));
  }
  const hidden = new Set<string>();
  for (const thread of threads) {
    if (!thread.delegatedFromEnvironmentId || !thread.delegatedFromThreadId) continue;
    if (activeByKey.has(threadScopeKey(thread.delegatedFromEnvironmentId, thread.delegatedFromThreadId))) {
      hidden.add(threadScopeKey(thread.environmentId || thread.localId, thread.id));
    }
  }
  return hidden;
}

export function isShownUnderParent(thread: ScopedThread, delegatedUnderParent: Set<string>): boolean {
  if (!isListedThread(thread)) return true;
  return delegatedUnderParent.has(threadScopeKey(thread.environmentId || thread.localId, thread.id));
}

export function buildThreadShelves(input: {
  threads: ScopedThread[]; environmentId: string; projectRefs: string[]; query: string;
  searchHits: Record<string, string>; nowMs: number; capabilities: Record<string, ThreadCapabilities>;
  sortOrder: string; selectedKey: string; workingShelfEnabled?: boolean;
}): ThreadShelfState {
  const workingShelfEnabled = input.workingShelfEnabled !== false;
  const annotatedThreads = attachPendingSubagentRequests(input.threads);
  const underParent = delegatedUnderParentKeys(annotatedThreads);
  const matching: ScopedThread[] = [];
  const pinned: ScopedThread[] = [];
  const active: ScopedThread[] = [];
  const working: ScopedThread[] = [];
  const snoozed: ScopedThread[] = [];
  const settled: ScopedThread[] = [];
  for (const thread of annotatedThreads) {
    if (thread.archivedAt || isShownUnderParent(thread, underParent)) continue;
    if (input.environmentId && thread.localId !== input.environmentId) continue;
    if (!threadInProjectRefs(thread, input.projectRefs)) continue;
    const hitKey = thread.localId + ':' + thread.id;
    const snippet = input.searchHits[hitKey] || '';
    const hasHit = input.searchHits[hitKey] !== undefined;
    if (!hasHit && !threadMatchesQuery(thread, input.query, snippet)) continue;
    if (input.query.trim()) { matching.push(thread); continue; }
    const caps = input.capabilities[thread.localId] || {
      settlement: false, snooze: false, pinning: false, pinReorder: false,
      activeReorder: false, autoSettleOptOut: false, titleRegeneration: false
    };
    if (caps.snooze && effectiveSnoozed(thread, input.nowMs)) { snoozed.push(thread); continue; }
    if (threadIsSettled(thread, caps)) { settled.push(thread); continue; }
    if (thread.pinnedAt) { pinned.push(thread); continue; }
    if (workingShelfEnabled && threadIsWorking(thread)) { working.push(thread); continue; }
    active.push(thread);
  }
  matching.sort((left: ScopedThread, right: ScopedThread) => {
    const leftKey = left.localId + ':' + left.id;
    const rightKey = right.localId + ':' + right.id;
    return threadSearchScore(right, input.query, input.searchHits[rightKey] || '') -
      threadSearchScore(left, input.query, input.searchHits[leftKey] || '') ||
      threadSortTimestamp(right, input.sortOrder) - threadSortTimestamp(left, input.sortOrder) ||
      identityTiebreak(left, right);
  });
  return {
    workingShelfEnabled,
    pinned: sortPinned(pinned),
    active: workingShelfEnabled
      ? active.sort((left: ScopedThread, right: ScopedThread) => inboxReturnAt(right) - inboxReturnAt(left) || identityTiebreak(left, right))
      : sortActive(active),
    working: working.slice().sort((left: ScopedThread, right: ScopedThread) =>
      threadSortTimestamp(right, input.sortOrder) - threadSortTimestamp(left, input.sortOrder)),
    snoozed: sortSnoozed(snoozed),
    settled: sortSettled(settled),
    matches: matching,
    workingCount: working.length,
    snoozedCount: snoozed.length,
    settledCount: settled.length
  };
}

export function flattenSearchResults(shelves: ThreadShelfState, query: string): ScopedThread[] {
  if (!query.trim()) return [];
  return shelves.matches;
}

export function buildArchiveGroups(input: {
  snapshots: Record<string, Object>;
  entries: ArchiveEnvironmentEntry[];
  environmentId: string;
  query: string;
  sortOrder: string;
  scratchRoots: Record<string, string>;
}): ArchiveProjectGroup[] {
  const query = input.query.trim();
  const groups: ArchiveProjectGroup[] = [];
  for (const localId of Object.keys(input.snapshots)) {
    const entry = input.entries.find((candidate) => candidate.localId === localId);
    if (entry === undefined || (input.environmentId && input.environmentId !== entry.environmentId)) continue;
    const snapshot = record(input.snapshots[localId]);
    const projects: ScopedProject[] = compactArray(snapshot.projects, (value: Object): ScopedProject => {
      const project = projectView(value);
      return scopedProjectView(project, localId, entry.environmentId, entry.label,
        !!input.scratchRoots[localId] && samePath(project.workspaceRoot, input.scratchRoots[localId]));
    });
    const archived: ScopedThread[] = compactArray(snapshot.threads, (value: Object): ScopedThread => {
      const thread = threadView(value);
      const project = projects.find((candidate: ScopedProject) => candidate.id === thread.projectId);
      return scopedThreadView(thread, localId, entry.environmentId, entry.label,
        project?.label || '项目', project?.projectIcon);
    }).filter((thread: ScopedThread) => !!thread.archivedAt);
    const byProject = new Map<string, ScopedThread[]>();
    for (const thread of archived) {
      const list = byProject.get(thread.projectId);
      if (list === undefined) byProject.set(thread.projectId, [thread]); else list.push(thread);
    }
    for (const project of projects) {
      const projectThreads = byProject.get(project.id) || [];
      if (!projectThreads.length) continue;
      const projectMatches = projectMatchesQuery(project, query);
      const matching = projectMatches ? projectThreads : projectThreads.filter((thread: ScopedThread) =>
        threadMatchesQuery(thread, query));
      if (!matching.length) continue;
      matching.sort((left: ScopedThread, right: ScopedThread) =>
        (input.sortOrder === 'oldest' ? 1 : -1) * (Date.parse(left.archivedAt) - Date.parse(right.archivedAt)) ||
        left.label.localeCompare(right.label) || left.id.localeCompare(right.id));
      groups.push({ key: localId + ':' + project.id, project, threads: matching });
    }
  }
  return groups.sort((left: ArchiveProjectGroup, right: ArchiveProjectGroup) => {
    const leftTime = Date.parse(left.threads[0]?.archivedAt || '');
    const rightTime = Date.parse(right.threads[0]?.archivedAt || '');
    return (input.sortOrder === 'oldest' ? 1 : -1) * (leftTime - rightTime) ||
      left.project.label.localeCompare(right.project.label) || left.key.localeCompare(right.key);
  });
}

export function scopedProjectView(project: ProjectView, localId: string, environmentId: string,
  environmentLabel: string, isScratch: boolean): ScopedProject {
  return {
    id: project.id, label: project.label, projectId: project.projectId,
    defaultThreadEnvMode: project.defaultThreadEnvMode,
    defaultModelSelection: project.defaultModelSelection,
    workspaceRoot: project.workspaceRoot, repository: project.repository,
    ...(project.trackedFolders !== undefined ? { trackedFolders: project.trackedFolders } : {}),
    projectIcon: project.projectIcon,
    pinnedAt: project.pinnedAt, archivedAt: project.archivedAt,
    createdAt: project.createdAt, updatedAt: project.updatedAt, hasCustomTitle: project.hasCustomTitle,
    localId, environmentId, environmentLabel, isScratch
  };
}

export function scopedThreadView(thread: ThreadView, localId: string, environmentId: string,
  environmentLabel: string, projectLabel: string, projectIcon?: ProjectIconView): ScopedThread {
  return {
    id: thread.id, label: thread.label, projectId: thread.projectId,
    providerInstanceId: thread.providerInstanceId, model: thread.model,
    interactionMode: thread.interactionMode, creationSource: thread.creationSource,
    branch: thread.branch, worktreePath: thread.worktreePath,
    status: thread.status, activityRunStatus: thread.activityRunStatus,
    activityRunStartedAt: thread.activityRunStartedAt, blockedOnThreadWait: thread.blockedOnThreadWait,
    activeRunId: thread.activeRunId, latestRunId: thread.latestRunId,
    latestRunRequestedAt: thread.latestRunRequestedAt, latestRunStartedAt: thread.latestRunStartedAt,
    latestRunCompletedAt: thread.latestRunCompletedAt, lastError: thread.lastError,
    lastErrorClass: thread.lastErrorClass, createdAt: thread.createdAt, updatedAt: thread.updatedAt,
    archivedAt: thread.archivedAt, settledOverride: thread.settledOverride,
    settledAt: thread.settledAt, unsettledAt: thread.unsettledAt,
    snoozedUntil: thread.snoozedUntil, snoozedAt: thread.snoozedAt,
    pinnedAt: thread.pinnedAt, pinOrderKey: thread.pinOrderKey,
    activeOrderKey: thread.activeOrderKey, autoSettleDisabledAt: thread.autoSettleDisabledAt,
    latestUserMessageAt: thread.latestUserMessageAt,
    latestUserAuthoredMessageAt: thread.latestUserAuthoredMessageAt,
    lastVisitedAt: thread.lastVisitedAt, pendingKind: thread.pendingKind,
    pendingAt: thread.pendingAt, pendingUserOnly: thread.pendingUserOnly,
    pendingGuestMessageCount: thread.pendingGuestMessageCount,
    hasActionableProposedPlan: thread.hasActionableProposedPlan,
    titleRegenerationRequestId: thread.titleRegenerationRequestId,
    titleRegenerationStartedAt: thread.titleRegenerationStartedAt,
    lineageRelationship: thread.lineageRelationship,
    lineageParentThreadId: thread.lineageParentThreadId,
    lineageSideChat: thread.lineageSideChat,
    lineageWorkflowStep: thread.lineageWorkflowStep,
    delegatedFromEnvironmentId: thread.delegatedFromEnvironmentId,
    delegatedFromThreadId: thread.delegatedFromThreadId,
    lastSnoozeWakeAt: thread.lastSnoozeWakeAt,
    pendingBackgroundTasks: thread.pendingBackgroundTasks,
    goal: thread.goal,
    deletedAt: thread.deletedAt, localId, environmentId, environmentLabel, projectLabel, projectIcon,
    pendingSubagentRequest: ''
  };
}

export function threadStatus(thread: ScopedThread, nowMs: number): string {
  const subagentReq = threadPendingSubagentRequest(thread);
  if (hasPendingApprovals(thread) || subagentReq === 'approval') return '等待批准';
  if (hasPendingUserInput(thread) || subagentReq === 'user_input') return '等待回答';
  if (thread.pendingGuestMessageCount > 0) return '访客消息';
  if (threadParkedOnBackgroundWork(thread)) return '等待';
  const status = runtimeStatus(thread);
  if (status === 'running' && thread.blockedOnThreadWait) return '等待';
  if (status === 'running' || status === 'starting' || status === 'preparing' || status === 'queued') return '运行中';
  if (status === 'waiting') return '等待';
  if (status === 'failed') {
    if (thread.lastErrorClass === 'usage_limit') return '用量受限';
    return hasUnseenRunFailure(thread) ? '失败' : '';
  }
  if (effectiveSnoozed(thread, nowMs)) return '暂缓 ' + snoozeWakeLabel(thread, nowMs);
  if (threadHasUnseenCompletion(thread)) return '已回复';
  return '';
}

export function relativeTime(iso: string, nowMs: number): string {
  const value = Date.parse(iso);
  if (!Number.isFinite(value)) return '';
  const seconds = Math.max(0, Math.floor((nowMs - value) / 1000));
  if (seconds < 60) return '刚刚';
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return minutes + ' 分钟前';
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return hours + ' 小时前';
  const days = Math.floor(hours / 24);
  if (days < 30) return days + ' 天前';
  return new Date(value).toLocaleDateString();
}

function two(value: number): string {
  return value < 10 ? '0' + value : String(value);
}

const WEEKDAYS = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];

function addDays(base: Date, days: number): Date {
  const next = new Date(base.getTime());
  next.setDate(next.getDate() + days);
  return next;
}

function presetLabel(setting: SnoozePresetSetting, daysAhead: number, wake: Date): string {
  if (setting.kind === 'after') {
    if (setting.minutes % 1440 === 0) return setting.minutes / 1440 + ' 天后';
    if (setting.minutes % 60 === 0) return setting.minutes / 60 + ' 小时后';
    return setting.minutes + ' 分钟后';
  }
  if (daysAhead === 0) return '今天 ' + setting.time;
  if (daysAhead === 1) return '明天 ' + setting.time;
  return '周' + ['日', '一', '二', '三', '四', '五', '六'][wake.getDay()] + ' ' + setting.time;
}

export function resolveSnoozePresets(now: Date, settings: SnoozePresetSetting[]): SnoozePreset[] {
  const result: SnoozePreset[] = [];
  for (const setting of settings) {
    if (setting.kind !== 'after' && setting.kind !== 'at') continue;
    let wake: Date;
    let daysAhead = 0;
    if (setting.kind === 'after') {
      if (!Number.isFinite(setting.minutes) || setting.minutes <= 0 || setting.minutes > 43200) continue;
      wake = new Date(now.getTime() + setting.minutes * 60000);
    } else {
      const time = /^([01]\d|2[0-3]):[0-5]\d$/.exec(setting.time);
      if (!time) continue;
      if (setting.day === 'today') daysAhead = 0;
      else if (setting.day === 'tomorrow') daysAhead = 1;
      else {
        const weekday = WEEKDAYS.indexOf(setting.day);
        if (weekday < 0) continue;
        daysAhead = (weekday - now.getDay() + 7) % 7 || 7;
      }
      wake = addDays(now, daysAhead);
      wake.setHours(Number(setting.time.slice(0, 2)), Number(setting.time.slice(3)), 0, 0);
      if (wake.getTime() <= now.getTime()) continue;
    }
    const minute = Math.floor(wake.getTime() / 60000);
    if (result.some((preset: SnoozePreset) => Math.floor(Date.parse(preset.snoozedUntil) / 60000) === minute)) continue;
    result.push({
      id: setting.kind === 'after' ? 'after:' + setting.minutes : 'at:' + setting.day + ':' + setting.time,
      label: presetLabel(setting, daysAhead, wake),
      whenLabel: two(wake.getHours()) + ':' + two(wake.getMinutes()),
      snoozedUntil: wake.toISOString()
    });
  }
  return result.sort((left: SnoozePreset, right: SnoozePreset) =>
    Date.parse(left.snoozedUntil) - Date.parse(right.snoozedUntil));
}

export function resolveCustomSnooze(input: CustomSnoozeInput, now: Date): string {
  let wake: Date;
  if (input.mode === 'duration') {
    const amount = Number(input.amount);
    if (!Number.isFinite(amount) || amount <= 0) return '';
    const unit = input.unit === 'minutes' ? 60000 : input.unit === 'days' ? 86400000 : 3600000;
    wake = new Date(now.getTime() + amount * unit);
  } else {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(input.date) || !/^\d{2}:\d{2}$/.test(input.time)) return '';
    wake = new Date(input.date + 'T' + input.time + ':00');
    if (wake.getFullYear() !== Number(input.date.slice(0, 4)) ||
      wake.getMonth() + 1 !== Number(input.date.slice(5, 7)) ||
      wake.getDate() !== Number(input.date.slice(8, 10))) return '';
  }
  return wake.getTime() > now.getTime() ? wake.toISOString() : '';
}

export function inferProjectTitle(path: string): string {
  const trimmed = path.trim().replace(/[\\/]+$/, '');
  const parts = trimmed.split(/[\\/]/);
  return parts[parts.length - 1] || trimmed;
}

export function resolveProjectPath(rawPath: string, platform: string): string {
  const path = rawPath.trim();
  if (!path) throw new Error('请输入项目目录');
  if (/^(\.\.?[/\\]|[A-Za-z0-9._-]+[/\\])/.test(path) && !path.startsWith('~/') && !path.startsWith('/')) {
    throw new Error('相对路径需要当前项目目录，请填写完整路径');
  }
  if (/^[A-Za-z]:[/\\]/.test(path) && !/^win/i.test(platform)) {
    throw new Error('Windows 路径仅适用于 Windows 环境');
  }
  return path.replace(/[\\/]+$/, '') || path;
}

export function newProjectFolderName(name: string): string {
  const slug = name.normalize('NFKD').replace(/[\u0300-\u036f]/g, '').toLowerCase()
    .replace(/[^a-z0-9]+/g, '-').replace(/^-+/, '').slice(0, 64).replace(/-+$/, '');
  if (!slug) return 'project';
  return /^(con|prn|aux|nul|com[1-9]|lpt[1-9])$/.test(slug) ? slug + '-project' : slug;
}

export function newProjectPathPreview(root: string, name: string): string {
  const base = root.replace(/[\\/]+$/, '');
  return base + '/' + newProjectFolderName(name);
}

export function cloneDirectoryName(value: string): string {
  const withoutQuery = value.trim().split(/[?#]/)[0];
  const parts = withoutQuery.replace(/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//, '').split(/[/\\:]+/).filter(Boolean);
  if (parts.length < 2) return '';
  const last = parts[parts.length - 1];
  return /^\d+$/.test(last) && parts.length === 2 ? '' : last.replace(/\.git$/, '');
}

export function normalizeCloneUrl(value: string): string {
  const trimmed = value.trim();
  if (/^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})\/[A-Za-z0-9._-]+(?:\.git)?$/.test(trimmed)) {
    return 'https://github.com/' + (trimmed.endsWith('.git') ? trimmed : trimmed + '.git');
  }
  if (/^https?:\/\/(www\.)?github\.com\/[^/]+\/[^/]+$/.test(trimmed)) return trimmed + '.git';
  return trimmed;
}

export function cloneDirectoryPath(remoteUrl: string, ghq: boolean): string {
  const name = cloneDirectoryName(remoteUrl);
  if (!ghq) return name;
  const withoutQuery = remoteUrl.trim().split(/[?#]/)[0];
  const match = /^[a-zA-Z][a-zA-Z0-9+.-]*:\/\/([^/]+)\/(.+)$/.exec(withoutQuery);
  if (!match) return name;
  const segments = match[2].split(/[/\\]/).filter(Boolean);
  if (segments.length < 2) return name;
  const repo = segments[segments.length - 1].replace(/\.git$/, '');
  return match[1] + '/' + segments.slice(0, -1).join('/') + '/' + repo;
}

export function cloneDestination(base: string, name: string): string {
  const directory = base.trim();
  if (!directory) return name;
  return directory.replace(/[\\/]+$/, '') + '/' + name;
}

export function projectCreateCommand(commandId: string, projectId: string, workspaceRoot: string): Object {
  return {
    type: 'project.create', commandId, projectId,
    title: inferProjectTitle(workspaceRoot), workspaceRoot,
    createWorkspaceRootIfMissing: true, defaultModelSelection: null
  };
}

export function projectUpdateCommand(commandId: string, projectId: string, patch: Object): Object {
  return { type: 'project.update', commandId, projectId, ...patch };
}

export function projectDeleteCommand(commandId: string, projectId: string): Object {
  return { type: 'project.delete', commandId, projectId, force: true };
}

export function threadCommand(commandId: string, type: string, threadId: string, extra: Object = {}): Object {
  return { type, commandId, threadId, ...extra };
}

export function threadMetadataCommand(commandId: string, threadId: string, title: string): Object {
  return { type: 'thread.metadata.update', commandId, threadId, title };
}

export function threadRegenerateCommand(commandId: string, threadId: string): Object {
  return { type: 'thread.metadata.update', commandId, threadId, regenerateTitle: true };
}

export function canMoveBeforeActiveNeighbor(threads: ScopedThread[], afterIndex: number): boolean {
  // shortcut: moving above an unkeyed row needs a multi-row reorder, extend when the arrangement editor supports it.
  return afterIndex >= threads.length || !!threads[afterIndex].activeOrderKey;
}

export function threadMovePayload(threads: ScopedThread[], moved: ScopedThread, up: boolean, section: string): Object {
  const key = section === 'pinned' ? 'pinOrderKey' : 'activeOrderKey';
  const index = threads.findIndex((item: ScopedThread) => item.id === moved.id && item.localId === moved.localId);
  if (index < 0) throw new Error('会话不在当前分组');
  const target = index + (up ? -1 : 1);
  if (target < 0 || target >= threads.length) throw new Error(up ? '已在顶部' : '已到底部');
  const beforeIndex = up ? index - 2 : index + 1;
  const afterIndex = up ? index - 1 : index + 2;
  if (section === 'active' && !canMoveBeforeActiveNeighbor(threads, afterIndex)) {
    throw new Error('此位置需要同时调整多个会话的顺序');
  }
  const before = beforeIndex >= 0 && beforeIndex < threads.length ? text((threads[beforeIndex] as Object)[key] as Object) : '';
  const after = afterIndex >= 0 && afterIndex < threads.length ? text((threads[afterIndex] as Object)[key] as Object) : '';
  const orderKey = pinOrderKeyBetween(before, after);
  if (!orderKey) throw new Error('会话顺序已损坏，请刷新后重试');
  return { orderKey };
}

const PIN_ORDER_DIGITS = 'abcdefghijklmnopqrstuvwxyz';

function validOrderKey(key: string): boolean {
  if (!key) return false;
  for (const char of key) if (!PIN_ORDER_DIGITS.includes(char)) return false;
  return key.charAt(key.length - 1) !== PIN_ORDER_DIGITS.charAt(0);
}

function orderMidpoint(a: string, b: string): string {
  if (b && a >= b) throw new Error('会话顺序边界无效');
  if (b) {
    let n = 0;
    while ((a.charAt(n) || PIN_ORDER_DIGITS.charAt(0)) === b.charAt(n)) n += 1;
    if (n > 0) return b.slice(0, n) + orderMidpoint(a.slice(n), b.slice(n));
  }
  const digitA = a ? PIN_ORDER_DIGITS.indexOf(a.charAt(0)) : 0;
  const digitB = b ? PIN_ORDER_DIGITS.indexOf(b.charAt(0)) : PIN_ORDER_DIGITS.length;
  if (digitB - digitA > 1) return PIN_ORDER_DIGITS.charAt(Math.round((digitA + digitB) / 2));
  if (b.length > 1) return b.charAt(0);
  return PIN_ORDER_DIGITS.charAt(digitA) + orderMidpoint(a.slice(1), '');
}

export function pinOrderKeyBetween(before: string, after: string): string {
  if ((before && !validOrderKey(before)) || (after && !validOrderKey(after)) ||
    (after && before >= after)) return '';
  return orderMidpoint(before || '', after || '');
}

export function topOfPinnedRun(threads: ScopedThread[]): string {
  let first = '';
  for (const thread of threads) {
    if (!thread.pinOrderKey) continue;
    if (!first || thread.pinOrderKey < first) first = thread.pinOrderKey;
  }
  return pinOrderKeyBetween('', first);
}

export function sessionAllows(session: Object | undefined, scope: string): boolean | undefined {
  if (session === undefined) return undefined;
  const row = record(session);
  if (row.authenticated !== true) return false;
  if (row.permissions !== undefined) {
    const permissions = objects(row.permissions);
    return permissions.some((permission: Object) => text(permission) === scope);
  }
  if (row.scopes === undefined) return false;
  const scopes = objects(row.scopes);
  if (scopes.some((value: Object) => text(value) === scope)) return true;
  const legacy = scope === 'filesystem:read' || scope === 'diagnostics:read' ? 'orchestration:read' :
    ['settings:write', 'providers:manage', 'environment:maintain', 'preview:operate',
      'source-control:write', 'filesystem:write'].includes(scope) ? 'orchestration:operate' :
      scope === 'terminal:read' ? 'terminal:operate' : '';
  return !!legacy && scopes.some((value: Object) => text(value) === legacy);
}

export function capability(row: Object, name: string): boolean {
  const capabilities = record(row).capabilities;
  return capabilities !== undefined && capabilities !== null && record(capabilities)[name] === true;
}

export function objectText(row: Object, key: string): string {
  const value = record(row)[key];
  return value === undefined || value === null ? '' : typeof value === 'string' ? value : '';
}

export function objectBool(row: Object, key: string): boolean {
  return record(row)[key] === true;
}

export function textArray(value: Object | undefined): string[] {
  if (value === undefined || value === null) return [];
  return objects(value).map((item: Object) => text(item));
}

export function objectRecords(value: Object | undefined): Record<string, Object>[] {
  if (value === undefined || value === null) return [];
  return objects(value).map((item: Object) => record(item));
}

export function sequenceOr(value: Object | undefined, fallback: number): number {
  if (value === undefined) return fallback;
  return sequence(value);
}
