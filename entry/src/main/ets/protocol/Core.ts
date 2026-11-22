import { compactArray, compactObjects, parseModelSelection, record, RpcFailure, text, objects, sequence, serverBase } from './Wire';
import { ProjectView, ThreadView, RepositoryIdentityView, projectView, threadView, parseProjectIcon, samePath } from './Projects';

export interface Choice { id: string; label: string; projectId: string; }
export interface ModelChoice { instanceId: string; model: string; label: string; }
export function models(config: Object): ModelChoice[] {
  const result: ModelChoice[] = [];
  for (const provider of compactObjects(record(config).providers)) {
    if (provider.enabled === false || provider.installed === false) continue;
    if (typeof provider.instanceId !== 'string' || !provider.instanceId) continue;
    for (const model of compactObjects(provider.models)) {
      if (typeof model.slug !== 'string' || !model.slug) continue;
      const name = typeof model.name === 'string' && model.name ? model.name : model.slug;
      result.push({ instanceId: provider.instanceId, model: model.slug,
        label: provider.instanceId + ' / ' + name });
    }
  }
  return result;
}
export interface CachedShellEntry {
  environmentId: string;
  savedAt: number;
  scratchWorkspaceRoot: string;
  capabilities: Record<string, boolean>;
  projects: ProjectView[];
  threads: ThreadView[];
}

function cachedString(value: Object | undefined, maxLength: number = 2048): string {
  if (typeof value !== 'string') return '';
  return value.length <= maxLength ? value : value.slice(0, maxLength);
}

function cachedRepository(value: Object | undefined): RepositoryIdentityView | undefined {
  if (value === undefined || value === null || typeof value !== 'object' || Array.isArray(value)) return undefined;
  const row = value as Record<string, Object>;
  const canonicalKey = cachedString(row.canonicalKey, 512);
  if (!canonicalKey) return undefined;
  return {
    canonicalKey,
    groupingKey: cachedString(row.groupingKey, 512) || canonicalKey,
    displayName: cachedString(row.displayName, 512),
    name: cachedString(row.name, 512),
    rootPath: cachedString(row.rootPath, 1024)
  };
}

function cachedProjectView(value: Object): ProjectView {
  const row = record(value);
  const id = text(row.id);
  const label = text(row.label);
  if (!id || id.length > 256 || !label || label.length > 1024) throw new Error('缓存项目条目无效');
  const rawMode = row.defaultThreadEnvMode;
  const defaultThreadEnvMode: string | null | undefined =
    rawMode === 'local' ? 'local' : (rawMode === 'worktree' ? 'worktree' : (rawMode === null ? null : undefined));
  const defaultModelSelection = row.defaultModelSelection === undefined ? undefined :
    row.defaultModelSelection === null ? null : parseModelSelection(row.defaultModelSelection);
  return {
    defaultThreadEnvMode,
    defaultModelSelection,
    id,
    label,
    projectId: typeof row.projectId === 'string' && row.projectId ? row.projectId : id,
    workspaceRoot: cachedString(row.workspaceRoot, 1024),
    repository: cachedRepository(row.repository),
    projectIcon: parseProjectIcon(row.projectIcon),
    pinnedAt: cachedString(row.pinnedAt, 64),
    archivedAt: cachedString(row.archivedAt, 64),
    createdAt: cachedString(row.createdAt, 64),
    updatedAt: cachedString(row.updatedAt, 64),
    hasCustomTitle: row.hasCustomTitle === true
  };
}

function cachedThreadView(value: Object): ThreadView {
  const row = record(value);
  const id = text(row.id);
  const label = text(row.label);
  const projectId = text(row.projectId);
  if (!id || id.length > 256 || !label || label.length > 1024 || !projectId || projectId.length > 256) {
    throw new Error('缓存会话条目无效');
  }
  const tasks: Record<string, Object>[] = [];
  if (Array.isArray(row.pendingBackgroundTasks)) {
    for (const item of row.pendingBackgroundTasks as Object[]) {
      if (item !== null && typeof item === 'object' && !Array.isArray(item)) {
        tasks.push(item as Record<string, Object>);
      }
    }
  }
  const goal: Record<string, Object> | undefined =
    row.goal !== undefined && row.goal !== null && typeof row.goal === 'object' && !Array.isArray(row.goal)
      ? row.goal as Record<string, Object> : undefined;
  return {
    id,
    label,
    projectId,
    providerInstanceId: cachedString(row.providerInstanceId, 256),
    model: cachedString(row.model, 256),
    branch: cachedString(row.branch, 256),
    worktreePath: cachedString(row.worktreePath, 1024),
    status: cachedString(row.status, 64),
    activityRunStatus: cachedString(row.activityRunStatus, 64),
    activeRunId: cachedString(row.activeRunId, 256),
    latestRunId: cachedString(row.latestRunId, 256),
    latestRunRequestedAt: cachedString(row.latestRunRequestedAt, 64),
    latestRunStartedAt: cachedString(row.latestRunStartedAt, 64),
    latestRunCompletedAt: cachedString(row.latestRunCompletedAt, 64),
    lastError: cachedString(row.lastError, 1024),
    lastErrorClass: cachedString(row.lastErrorClass, 128),
    createdAt: cachedString(row.createdAt, 64),
    updatedAt: cachedString(row.updatedAt, 64),
    archivedAt: cachedString(row.archivedAt, 64),
    settledOverride: cachedString(row.settledOverride, 64),
    settledAt: cachedString(row.settledAt, 64),
    unsettledAt: cachedString(row.unsettledAt, 64),
    snoozedUntil: cachedString(row.snoozedUntil, 64),
    snoozedAt: cachedString(row.snoozedAt, 64),
    pinnedAt: cachedString(row.pinnedAt, 64),
    pinOrderKey: cachedString(row.pinOrderKey, 256),
    activeOrderKey: cachedString(row.activeOrderKey, 256),
    autoSettleDisabledAt: cachedString(row.autoSettleDisabledAt, 64),
    latestUserMessageAt: cachedString(row.latestUserMessageAt, 64),
    latestUserAuthoredMessageAt: cachedString(row.latestUserAuthoredMessageAt, 64),
    lastVisitedAt: cachedString(row.lastVisitedAt, 64),
    pendingKind: cachedString(row.pendingKind, 64),
    pendingAt: cachedString(row.pendingAt, 64),
    pendingGuestMessageCount: typeof row.pendingGuestMessageCount === 'number' && Number.isFinite(row.pendingGuestMessageCount)
      ? row.pendingGuestMessageCount as number : 0,
    hasActionableProposedPlan: row.hasActionableProposedPlan === true,
    titleRegenerationRequestId: cachedString(row.titleRegenerationRequestId, 256),
    titleRegenerationStartedAt: cachedString(row.titleRegenerationStartedAt, 64),
    lineageRelationship: cachedString(row.lineageRelationship, 64),
    lineageParentThreadId: cachedString(row.lineageParentThreadId, 256),
    lineageSideChat: row.lineageSideChat === true,
    delegatedFromThreadId: cachedString(row.delegatedFromThreadId, 256),
    lastSnoozeWakeAt: cachedString(row.lastSnoozeWakeAt, 64),
    pendingBackgroundTasks: tasks,
    goal,
    deletedAt: cachedString(row.deletedAt, 64)
  };
}

export function cachedShellEntry(value: Object): CachedShellEntry {
  const row = record(value);
  const environmentId = text(row.environmentId);
  if (!environmentId || environmentId.length > 256 || /[\u0000-\u001f\u007f]/.test(environmentId)) {
    throw new Error('缓存环境标识无效');
  }
  const savedAt = row.savedAt;
  if (typeof savedAt !== 'number' || !Number.isFinite(savedAt) || savedAt <= 0) {
    throw new Error('缓存时间无效');
  }
  const capabilities: Record<string, boolean> = {};
  if (row.capabilities !== undefined && row.capabilities !== null) {
    const rawCaps = record(row.capabilities);
    const keys = Object.keys(rawCaps);
    if (keys.length > 64) throw new Error('缓存能力字段超限');
    for (const key of keys) {
      if (rawCaps[key] === true) capabilities[key] = true;
    }
  }
  const projects = compactArray(objects(row.projects), (item: Object) => cachedProjectView(item));
  const threads = compactArray(objects(row.threads), (item: Object) => cachedThreadView(item))
    .filter((item: ThreadView) => !item.deletedAt);
  return {
    environmentId,
    savedAt: savedAt as number,
    scratchWorkspaceRoot: cachedString(row.scratchWorkspaceRoot, 1024),
    capabilities,
    projects,
    threads
  };
}

export class ShellState {
  projects: ProjectView[] = [];
  threads: ThreadView[] = [];
  archived: ThreadView[] = [];
  cursor: number = -1;
  resumeCursor: number = -1;
  hasSnapshot: boolean = false;
  liveSynced: boolean = false;
  hydrateCache(projects: ProjectView[], threads: ThreadView[]): void {
    if (this.liveSynced) return;
    this.projects = projects.slice();
    this.threads = threads.slice();
    this.archived = [];
    this.cursor = -1;
    this.resumeCursor = -1;
    this.hasSnapshot = true;
    this.liveSynced = false;
  }
  resetForReconnect(): void {
    if (this.cursor >= 0) this.resumeCursor = this.cursor;
    this.cursor = -1;
    this.liveSynced = false;
  }
  clear(): void {
    this.projects = [];
    this.threads = [];
    this.archived = [];
    this.cursor = -1;
    this.resumeCursor = -1;
    this.hasSnapshot = false;
    this.liveSynced = false;
  }
  apply(value: Object): void {
    const item = record(value);
    if (item.kind === 'synchronized') {
      if (this.cursor < 0 && this.resumeCursor >= 0) this.cursor = this.resumeCursor;
      if (this.hasSnapshot) this.liveSynced = true;
      return;
    }
    if (item.kind === 'snapshot') {
      if (item.resolvedRepositoryIdentityRoots !== undefined) {
        const snapshot = record(item.snapshot);
        if (snapshot.projects === undefined) return;
        for (const next of compactArray(objects(snapshot.projects), (p: Object) => projectView(p))) {
          const current = this.projects.find((row: ProjectView) => row.id === next.id && samePath(row.workspaceRoot, next.workspaceRoot));
          if (current !== undefined && next.repository !== undefined) current.repository = next.repository;
        }
        return;
      }
      const snapshot = record(item.snapshot);
      const cursor = sequence(snapshot.snapshotSequence);
      if (cursor < this.cursor) return;
      this.projects = compactArray(objects(snapshot.projects), (p: Object) => projectView(p));
      this.threads = compactArray(objects(snapshot.threads), (t: Object) => threadView(t));
      this.archived = snapshot.archivedThreads === undefined ? [] :
        compactArray(objects(snapshot.archivedThreads), (t: Object) => threadView(t));
      this.cursor = cursor;
      this.resumeCursor = cursor;
      this.hasSnapshot = true;
      this.liveSynced = true;
      return;
    }
    if (item.kind !== 'project.updated' && item.kind !== 'project.removed' &&
      item.kind !== 'thread.updated' && item.kind !== 'thread.removed') {
      return;
    }
    const cursor = sequence(item.sequence);
    const floor = this.cursor >= 0 ? this.cursor : this.resumeCursor;
    if (cursor <= floor) return;
    if (item.kind === 'project.updated') {
      const next = projectView(item.project);
      this.projects = this.projects.filter((p: ProjectView) => p.id !== next.id);
      this.projects.push(next);
    } else if (item.kind === 'project.removed') {
      this.projects = this.projects.filter((p: ProjectView) => p.id !== text(item.projectId));
    } else if (item.kind === 'thread.updated') {
      const next = threadView(item.thread);
      this.threads = this.threads.filter((t: ThreadView) => t.id !== next.id);
      this.archived = this.archived.filter((t: ThreadView) => t.id !== next.id);
      if (item.location === 'active') this.threads.push(next); else this.archived.push(next);
    } else if (item.kind === 'thread.removed') {
      // The shell names the list the removal came from; keep the other list intact.
      if (item.location === 'active') this.threads = this.threads.filter((t: ThreadView) => t.id !== text(item.threadId));
      else this.archived = this.archived.filter((t: ThreadView) => t.id !== text(item.threadId));
    }
    this.cursor = cursor;
    this.resumeCursor = cursor;
  }
}

export interface MarkdownBlock { kind: string; text: string; }
// shortcut: block Markdown only; add inline spans and tables when core flow is accepted.
export function markdown(source: string): MarkdownBlock[] {
  const blocks: MarkdownBlock[] = [];
  let code: string[] | undefined = undefined;
  for (const line of source.split('\n')) {
    if (/^\s*```/.test(line)) {
      if (code) { blocks.push({ kind: 'code', text: code.join('\n') }); code = undefined; }
      else code = [];
    } else if (code) code.push(line);
    else if (/^#{1,6} /.test(line)) blocks.push({ kind: 'heading', text: line.replace(/^#+ /, '') });
    else if (/^> /.test(line)) blocks.push({ kind: 'quote', text: line.slice(2) });
    else blocks.push({ kind: 'text', text: line });
  }
  if (code) blocks.push({ kind: 'code', text: code.join('\n') });
  return blocks;
}

export interface ApprovalChoice { decision: string; label: string; warning: string; }
export interface QuestionOption {
  label: string;
  description: string;
  preview: string;
  value: string;
  recommended: boolean;
}
export interface Question {
  id: string;
  header: string;
  text: string;
  label: string;
  options: string[];
  optionItems: QuestionOption[];
  descriptions: string[];
  values: string[];
  multi: boolean;
  required: boolean;
  custom: boolean;
  initial: string;
}
export interface QuestionDisplay {
  question: Question;
  companion: boolean;
  ordinal: number;
  primaryTotal: number;
  eyebrow: string;
  title: string;
  placeholder: string;
}
const RECOMMENDED_OPTION_PREFIX = /^\(recommended\)\s*/i;
const GENERIC_AGENT_QUESTIONS_RE = /^the agent has \d+ questions?\.?$/i;
const COMPANION_OTHER_PROMPT_RE = /^optional free-form answer to:/i;

function parseQuestionOption(o: Record<string, Object>): QuestionOption {
  const rawLabel = text(o.label).trim();
  const rawDescription = typeof o.description === 'string' ? o.description.trim() : '';
  const preview = typeof o.preview === 'string' ? o.preview.trim() : '';
  const value = typeof o.value === 'string' ? o.value : text(o.label);
  const hasRecommended = RECOMMENDED_OPTION_PREFIX.test(rawLabel);
  const stripped = hasRecommended ? rawLabel.replace(RECOMMENDED_OPTION_PREFIX, '').trim() : rawLabel;
  const label = stripped.length > 0 ? stripped : rawLabel;
  const description = rawDescription && rawDescription !== rawLabel && rawDescription !== label ? rawDescription : '';
  return { label, description, preview, value, recommended: hasRecommended && stripped.length > 0 };
}

function isCompanionOtherQuestion(q: Question, prev: Question | undefined): boolean {
  if (!prev) return false;
  if (q.optionItems.length > 0 || !q.custom || q.required) return false;
  return q.header.trim().toLowerCase() === 'other' && COMPANION_OTHER_PROMPT_RE.test(q.text.trim());
}

export function questionDisplays(questions: Question[]): QuestionDisplay[] {
  const companions: boolean[] = [];
  let primaryTotal = 0;
  for (let i = 0; i < questions.length; i++) {
    const companion = isCompanionOtherQuestion(questions[i], i > 0 ? questions[i - 1] : undefined);
    companions.push(companion);
    if (!companion) primaryTotal++;
  }
  const result: QuestionDisplay[] = [];
  let ordinal = 0;
  for (let i = 0; i < questions.length; i++) {
    const q = questions[i];
    const companion = companions[i];
    if (companion) {
      result.push({
        question: q,
        companion: true,
        ordinal: 0,
        primaryTotal,
        eyebrow: '',
        title: '补充说明（可选）',
        placeholder: '可补充说明或填写其他想法（可选）'
      });
      continue;
    }
    ordinal++;
    const header = q.header.trim();
    const body = q.text.trim();
    const dropBody = !body || body === header || GENERIC_AGENT_QUESTIONS_RE.test(body);
    const eyebrow = !dropBody && header.length > 0 ? header : '';
    const title = dropBody ? (header || body) : body;
    result.push({
      question: q,
      companion: false,
      ordinal,
      primaryTotal,
      eyebrow,
      title,
      placeholder: q.optionItems.length > 0 ? '或输入自定义回答…' : '请输入回答…'
    });
  }
  return result;
}

export interface SecretField {
  name: string;
  label: string;
  placeholder: string;
  secret: boolean;
}
export function parseSecretFields(value: Object | undefined): SecretField[] {
  if (!Array.isArray(value)) return [];
  const result: SecretField[] = [];
  const seen = new Set<string>();
  for (const entry of value as Object[]) {
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry)) continue;
    const row = entry as Record<string, Object>;
    if (typeof row.name !== 'string' || typeof row.label !== 'string') continue;
    const name = row.name.trim();
    const label = row.label.trim();
    if (!name || !label || seen.has(name)) continue;
    if (row.placeholder !== undefined && typeof row.placeholder !== 'string') continue;
    if (row.secret !== undefined && typeof row.secret !== 'boolean') continue;
    seen.add(name);
    result.push({
      name,
      label,
      placeholder: typeof row.placeholder === 'string' ? row.placeholder : '',
      secret: row.secret !== false
    });
  }
  return result;
}
export interface ActionCard { id: string; requestId: string; kind: string; label: string; questions: Question[];
  enabled: boolean; responseType: string; canDismiss: boolean; approvalOptions: ApprovalChoice[]; requestKind: string;
  detail: string; reason: string; fullAccessOverride: string; secretUrl: string; secretPlaceholder: string;
  secretDelivery: string; secretReference: boolean; secretFields: SecretField[]; }
function safeSecretUrl(value: Object): string {
  if (typeof value !== 'string' || value.length > 2048 || /\s/.test(value)) return '';
  return /^https?:\/\/[^/]+/i.test(value) ? value : '';
}
export function cards(requests: Record<string, Object>[], items: Record<string, Object>[]): ActionCard[] {
  const result: ActionCard[] = [];
  for (const item of items) {
    try {
      if (item.type === 'secret_request' && item.secretStatus === 'pending') {
        const local = (item.visibility === undefined || item.visibility === 'local');
        const secretFields = parseSecretFields(item.fields);
        result.push({ id: text(item.id), requestId: '', kind: 'secret',
          label: text(item.label) + '\n' + text(item.reason) + (local ? '' : '\n等待在原会话中回答'),
          questions: [], enabled: local, responseType: local ? 'secret' : 'inherited', canDismiss: false,
          approvalOptions: [], requestKind: 'secret',
          detail: text(item.reason), reason: safeSecretUrl(item.url),
          fullAccessOverride: '', secretUrl: safeSecretUrl(item.url),
          secretPlaceholder: typeof item.placeholder === 'string' ? item.placeholder : '',
          secretDelivery: typeof item.delivery === 'string' ? item.delivery : '',
          secretReference: item.fields === undefined,
          secretFields });
      } else if (item.type === 'approval_request' || item.type === 'user_input_request') {
        const request = requests.find((row: Record<string, Object>) => row.id === item.requestId);
        if (!request || request.status !== 'pending') continue;
        const questions: Question[] = item.type === 'user_input_request' ? compactArray(item.questions, (value: Object): Question => {
          const q = record(value);
          const optionItems = compactArray(q.options, (opt: Object): QuestionOption => parseQuestionOption(record(opt)));
          const header = text(q.header).trim();
          const body = text(q.question).trim();
          const combinedLabel = header && body && header !== body ? header + ': ' + body : (body || header);
          return {
            id: text(q.id),
            header,
            text: body,
            label: combinedLabel,
            options: optionItems.map((o: QuestionOption) => o.description ? o.label + ' — ' + o.description : o.label),
            optionItems,
            descriptions: optionItems.map((o: QuestionOption) => o.description),
            values: optionItems.map((o: QuestionOption) => o.value),
            multi: q.multiSelect === true,
            required: q.required !== false,
            custom: q.allowCustomAnswer !== false,
            initial: typeof q.initialAnswer === 'string' ? q.initialAnswer : ''
          };
        }) : [];
        const approvalOptions: ApprovalChoice[] = item.type === 'approval_request' && item.options !== undefined ?
          compactArray(item.options, (value: Object): ApprovalChoice => {
            const option = record(value);
            return { decision: text(option.decision), label: text(option.label),
              warning: typeof option.warning === 'string' ? option.warning : '' };
          }) : [];
        result.push({ id: text(item.id), requestId: text(request.id), kind: item.type === 'user_input_request' ? 'input' : 'approval',
          label: item.type === 'approval_request' ? text(item.requestKind) + '\n' + (typeof item.prompt === 'string' ? item.prompt : '') + '\n' + (typeof item.reason === 'string' ? item.reason : '') : '需要你的回答',
          questions, enabled: record(request.responseCapability).type !== 'not_resumable',
          responseType: text(record(request.responseCapability).type),
          canDismiss: item.type === 'user_input_request' &&
            (item.responseMode === 'message' || record(request.responseCapability).type === 'message'),
          approvalOptions, requestKind: item.type === 'approval_request' ? text(item.requestKind) : '',
          detail: item.type === 'approval_request' && typeof item.prompt === 'string' ? item.prompt : '',
          reason: typeof item.reason === 'string' ? item.reason : '',
          fullAccessOverride: typeof item.fullAccessOverride === 'string' ? item.fullAccessOverride : '',
          secretUrl: '', secretPlaceholder: '', secretDelivery: '', secretReference: true, secretFields: [] });
      }
    } catch (_) {}
  }
  return result;
}

export interface SavedSession { base: string; environmentId: string; token: string; expiresAt: number; }
export interface SessionStorage {
  load(base?: string): Promise<SavedSession | undefined>;
  save(value: SavedSession): Promise<void>;
  clear(): Promise<void>;
}
export function stopCommand(commandId: string, threadId: string): Object {
  return { type: 'thread.stop', commandId, threadId };
}
export function secretAnswer(threadId: string, turnItemId: string, value: string, decline: boolean): Object {
  return { threadId, turnItemId, answer: decline ? { type: 'decline' } : { type: 'save', secret: value } };
}
export function secretValuesFromMap(fields: SecretField[], values: Map<string, string>): Record<string, string> {
  const entries: [string, string][] = [];
  for (const field of fields) {
    const raw = values.get(field.name);
    entries.push([field.name, raw !== undefined ? raw : '']);
  }
  return Object.fromEntries(entries) as Record<string, string>;
}
export function secretValuesAnswer(threadId: string, turnItemId: string, values: Record<string, string>,
  expectedFields?: SecretField[]): Object {
  if (values === null || typeof values !== 'object' || Array.isArray(values)) {
    throw new Error('请输入所有敏感字段');
  }
  const entries: [string, string][] = [];
  if (expectedFields !== undefined) {
    if (expectedFields.length === 0) throw new Error('此敏感输入请求不支持多字段提交');
    const keys = Object.keys(values);
    if (keys.length !== expectedFields.length) throw new Error('提交字段与请求不匹配');
    for (const field of expectedFields) {
      if (!Object.prototype.hasOwnProperty.call(values, field.name) || typeof values[field.name] !== 'string') {
        throw new Error('请填写所有敏感字段');
      }
      const trimmed = values[field.name].trim();
      if (!trimmed) throw new Error('请填写所有敏感字段');
      entries.push([field.name, trimmed]);
    }
  } else {
    const keys = Object.keys(values);
    if (keys.length === 0) throw new Error('请填写所有敏感字段');
    for (const key of keys) {
      if (!key.trim() || typeof values[key] !== 'string') throw new Error('请填写所有敏感字段');
      const trimmed = values[key].trim();
      if (!trimmed) throw new Error('请填写所有敏感字段');
      entries.push([key, trimmed]);
    }
  }
  return { threadId, turnItemId, answer: { type: 'save', values: Object.fromEntries(entries) } };
}
const SECRET_REQUEST_ERROR_MESSAGES: Record<string, string> = {
  fields_mismatch: '此请求需要的字段与当前版本不一致，请更新应用后重试',
  already_answered: '此敏感输入请求已被回答',
  not_found: '此敏感输入请求已不存在',
  agent_stopped: '发起请求的智能体已停止，无法再使用该敏感值',
  reference_unreadable: '无法从秘密来源读取该引用，请解锁后重试或直接输入',
  store_failed: '无法保存敏感值，请重试',
  record_failed: '敏感值已保存，但未能更新请求状态',
  load_failed: '无法加载此敏感输入请求'
};
export function secretRequestErrorMessage(error: Object | undefined): string {
  if (error !== undefined && error !== null && typeof error === 'object') {
    const row = error as Record<string, Object>;
    const tag = typeof row.errorTag === 'string' ? row.errorTag : '';
    const reason = typeof row.errorReason === 'string' ? row.errorReason : '';
    if ((tag === 'SecretRequestError' || reason === 'fields_mismatch') &&
      Object.prototype.hasOwnProperty.call(SECRET_REQUEST_ERROR_MESSAGES, reason)) {
      return SECRET_REQUEST_ERROR_MESSAGES[reason];
    }
  }
  if (error instanceof Error) {
    if (error.message.includes('fields_mismatch')) {
      return SECRET_REQUEST_ERROR_MESSAGES.fields_mismatch;
    }
    return error.message;
  }
  return '提交失败，请重试';
}
export function mapSecretRequestError(error: Object): Error {
  const mapped = secretRequestErrorMessage(error);
  if (error instanceof RpcFailure) {
    if (mapped !== error.message) return new RpcFailure(mapped, error.known, error.errorTag, error.errorReason);
    return error;
  }
  if (error instanceof Error) {
    return mapped !== error.message ? new Error(mapped) : error;
  }
  return new Error(mapped);
}
export function secretReferenceAnswer(threadId: string, turnItemId: string, provider: string,
  reference: string): Object {
  if (!/^[a-z0-9][a-z0-9_-]{0,63}$/i.test(provider) || !reference.trim() || reference.length > 1024 ||
    /[\r\n]/.test(reference)) {
    throw new Error('秘密引用无效');
  }
  return { threadId, turnItemId, answer: { type: 'reference', reference: { provider, reference } } };
}
export function dismissInputCommand(commandId: string, threadId: string, requestId: string): Object {
  return { type: 'thread.user-input.dismiss', commandId, threadId, requestId };
}

export function respondCommand(commandId: string, threadId: string, requestId: string, decision: string, answers: Object): Object {
  if (decision && !['accept', 'acceptForSession', 'acceptAlways', 'decline', 'cancel'].includes(decision)) throw new Error('无效审批决定');
  return { type: 'runtime-request.respond', commandId, threadId, requestId,
    ...(decision ? { decision } : { answers }) };
}

export function answerSelected(answer: Object | undefined, value: string): boolean {
  return Array.isArray(answer) ? answer.includes(value) : answer === value;
}

export function inputAnswers(values: Map<string, Object>): Record<string, Object> {
  return Object.fromEntries(values);
}

// Metadata only: never persist prompts, answers, secrets or signed upload URLs.
export interface RecoveryState {
  base: string; environmentId: string; threadId: string;
  pendingId: string; pendingKind: string;
}
export interface RecoveryStorage {
  load(): Promise<RecoveryState | undefined>;
  save(value: RecoveryState): Promise<void>;
  clear(): Promise<void>;
}
export function recoveryState(value: Object, base: string, environmentId: string): RecoveryState {
  const row = record(value);
  if (row.base !== base || row.environmentId !== environmentId) throw new Error('恢复记录服务器身份不一致');
  const state = { base, environmentId, threadId: text(row.threadId),
    pendingId: typeof row.pendingId === 'string' ? row.pendingId : '',
    pendingKind: typeof row.pendingKind === 'string' ? row.pendingKind : '' };
  if (state.threadId.length > 128 || state.pendingId.length > 512 ||
    !['', 'message', 'create', 'stop', 'response', 'secret'].includes(state.pendingKind) ||
    (!!state.pendingId !== !!state.pendingKind)) throw new Error('恢复记录无效');
  return state;
}

export interface Attachment { type: string; id: string; name: string; mimeType: string; sizeBytes: number; }
export function uploadTarget(value: Object, sizeBytes: number, name: string): { path: string; attachment: Attachment } {
  if (!name.trim() || name.length > 255 || /[\x00-\x1f]/.test(name) || !Number.isSafeInteger(sizeBytes) || sizeBytes < 1 || sizeBytes > 10 * 1024 * 1024) {
    throw new Error('附件名称或大小无效');
  }
  const row = record(value);
  const path = text(row.relativeUrl);
  const id = text(row.attachmentId);
  if (!/^\/api\/attachments\/upload\/[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(path) || path.length > 4096 ||
    !/^[a-z0-9_-]{1,128}$/i.test(id) || typeof row.expiresAt !== 'number' || row.expiresAt <= Date.now()) {
    throw new Error('附件上传地址无效或已过期');
  }
  return { path, attachment: { type: 'file', id, name, mimeType: 'application/octet-stream', sizeBytes } };
}

export interface PeerLinkView { environmentId: string; label: string; status: string; expiresAt: number; lastError?: string; }
// Access scopes have no legacy parent; an explicit permissions array is authoritative.
export function peerAccessGranted(value: Object | undefined, write: boolean): boolean {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const state = record(value);
  if (state.authenticated !== true) return false;
  const permissions = state.permissions !== undefined ? state.permissions : state.scopes;
  return Array.isArray(permissions) && permissions.every((permission: Object) => typeof permission === 'string') &&
    permissions.includes(write ? 'access:write' : 'access:read');
}
export function peerLinkViews(value: Object): PeerLinkView[] {
  return objects(record(value).links).map((item: Object): PeerLinkView => {
    const row = record(item); const environmentId = text(row.environmentId);
    const expiresAt = Date.parse(text(row.expiresAt)); const status = text(row.status);
    if (!environmentId.trim() || !Number.isFinite(expiresAt) || !['reachable', 'unreachable', 'expired'].includes(status)) throw new Error('环境链接响应无效');
    return { environmentId, label: text(row.label), status, expiresAt,
      lastError: row.lastError === null ? undefined : text(row.lastError) };
  });
}
export function peerLinkStatus(link: PeerLinkView, now: number): string {
  if (link.status === 'expired' || link.expiresAt <= now) return '已过期，请使用新的配对码重新链接。';
  if (link.status === 'unreachable') return link.lastError === undefined ? '暂时无法连接。' : link.lastError;
  if (link.lastError !== undefined) return link.lastError;
  const days = Math.ceil((link.expiresAt - now) / 86400000);
  return days <= 5 ? days + ' 天后过期' : '可连接';
}

export interface LinkRequestView {
  id: string; threadId: string; reason: string; status: string; visibility: string;
  url: string; environmentId: string; hint: string; access: string;
  linkedLabel: string; linkedAccess: string; failure: string;
}
export interface LinkAccessChoice { value: string; label: string; description: string; }
export const linkAccessChoices: LinkAccessChoice[] = [
  { value: 'read-only', label: '只读', description: '读取项目和会话，不启动、发送或修改任何内容。' },
  { value: 'approval-required', label: '监督', description: '执行命令和修改文件前询问。' },
  { value: 'auto-accept-edits', label: '自动接受编辑', description: '自动批准编辑，其他操作仍询问。' },
  { value: 'auto', label: '自动', description: '支持的 Provider 自动批准常规操作，其他仍询问。' },
  { value: 'full-access', label: '完全访问', description: '允许执行命令和编辑，无需提示。' }
];
export function linkRequests(items: Record<string, Object>[], threadId: string): LinkRequestView[] {
  return items.filter((item: Record<string, Object>) => item.type === 'link_request').map((item: Record<string, Object>): LinkRequestView => {
    const id = text(item.id); const ownThreadId = text(item.threadId); const status = text(item.linkStatus);
    if (!id || id.length > 128 || !ownThreadId || !['pending', 'linked', 'declined', 'cancelled', 'failed'].includes(status)) throw new Error('环境链接请求无效');
    const optional = (key: string): string => item[key] === undefined ? '' : text(item[key]);
    const access = optional('requestedAccess') || 'approval-required';
    if (!linkAccessChoices.some((choice: LinkAccessChoice) => choice.value === access)) throw new Error('未知的链接权限');
    return { id, threadId: ownThreadId, reason: text(item.reason), status,
      visibility: ownThreadId === threadId && (item.visibility === undefined || item.visibility === 'local') ? 'local' : 'inherited',
      url: optional('url'), environmentId: optional('environmentId'), hint: optional('hint'), access,
      linkedLabel: optional('linkedLabel'), linkedAccess: optional('linkedAccess'), failure: optional('failure') };
  });
}
export interface LinkAnswer { type: string; environmentId?: string; label?: string; urls?: string[]; access?: string; pairingCode?: string; }
export function linkAnswerPayload(threadId: string, turnItemId: string, answer: LinkAnswer): Object {
  if (!threadId || !turnItemId || threadId.length > 128 || turnItemId.length > 128) throw new Error('环境链接请求身份无效');
  let value: Object;
  if (answer.type === 'decline') value = { type: 'decline' } as LinkAnswer;
  else if (answer.type === 'use-existing' && answer.environmentId?.trim()) value = { type: 'use-existing', environmentId: answer.environmentId } as LinkAnswer;
  else if (answer.type === 'link' && answer.urls?.length && answer.pairingCode?.trim() &&
    linkAccessChoices.some((choice: LinkAccessChoice) => choice.value === answer.access)) {
    if (answer.pairingCode.length > 4096 || /[\u0000-\u001f\u007f]/.test(answer.pairingCode)) throw new Error('配对码无效');
    const checked: LinkAnswer = { type: 'link', urls: answer.urls.map((base: string) => serverBase(base)),
      access: answer.access, pairingCode: answer.pairingCode.trim() };
    if (answer.environmentId) checked.environmentId = answer.environmentId;
    if (answer.label) checked.label = answer.label;
    value = checked;
  } else throw new Error('链接目标、配对码或权限无效');
  return { threadId, turnItemId, answer: value };
}
export function peerPairingScopes(access: string): string[] {
  if (!linkAccessChoices.some((choice: LinkAccessChoice) => choice.value === access)) throw new Error('链接权限无效');
  if (access === 'read-only') return ['orchestration:read'];
  return access === 'full-access' ? ['orchestration:read', 'orchestration:operate', 'settings:write', 'source-control:write'] : ['orchestration:read', 'orchestration:operate'];
}
