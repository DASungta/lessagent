import { record, text, objects, sequence, serverBase } from './Wire';
import { ProjectView, ThreadView, projectView, threadView, samePath } from './Projects';

export interface Choice { id: string; label: string; projectId: string; }
export interface ModelChoice { instanceId: string; model: string; label: string; }
export function models(config: Object): ModelChoice[] {
  const result: ModelChoice[] = [];
  for (const value of objects(record(config).providers)) {
    const provider = record(value);
    if (provider.enabled === false || provider.installed === false) continue;
    for (const item of objects(provider.models)) {
      const model = record(item);
      result.push({ instanceId: text(provider.instanceId), model: text(model.slug),
        label: text(provider.instanceId) + ' / ' + text(model.name) });
    }
  }
  return result;
}
export class ShellState {
  projects: ProjectView[] = [];
  threads: ThreadView[] = [];
  archived: ThreadView[] = [];
  cursor: number = -1;
  apply(value: Object): void {
    const item = record(value);
    if (item.kind === 'synchronized') return;
    if (item.kind === 'snapshot') {
      if (item.resolvedRepositoryIdentityRoots !== undefined) {
        const snapshot = record(item.snapshot);
        if (snapshot.projects === undefined) return;
        for (const project of objects(snapshot.projects)) {
          const next = projectView(project);
          const current = this.projects.find((row: ProjectView) => row.id === next.id && samePath(row.workspaceRoot, next.workspaceRoot));
          if (current !== undefined && next.repository !== undefined) current.repository = next.repository;
        }
        return;
      }
      const snapshot = record(item.snapshot);
      const cursor = sequence(snapshot.snapshotSequence);
      if (cursor < this.cursor) return;
      this.projects = objects(snapshot.projects).map((p: Object) => projectView(p));
      this.threads = objects(snapshot.threads).map((t: Object) => threadView(t));
      this.archived = snapshot.archivedThreads === undefined ? [] : objects(snapshot.archivedThreads).map((t: Object) => threadView(t));
      this.cursor = sequence(snapshot.snapshotSequence);
      return;
    }
    const cursor = sequence(item.sequence);
    if (cursor <= this.cursor) return;
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
    } else throw new Error('未知项目流类型');
    this.cursor = cursor;
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
export interface Question { id: string; header: string; text: string; label: string; options: string[]; descriptions: string[];
  values: string[]; multi: boolean; required: boolean; custom: boolean; initial: string; }
export interface ActionCard { id: string; requestId: string; kind: string; label: string; questions: Question[];
  enabled: boolean; responseType: string; canDismiss: boolean; approvalOptions: ApprovalChoice[]; requestKind: string;
  detail: string; reason: string; fullAccessOverride: string; secretUrl: string; secretPlaceholder: string;
  secretDelivery: string; secretReference: boolean; }
function safeSecretUrl(value: Object): string {
  if (typeof value !== 'string' || value.length > 2048 || /\s/.test(value)) return '';
  return /^https?:\/\/[^/]+/i.test(value) ? value : '';
}
export function cards(requests: Record<string, Object>[], items: Record<string, Object>[]): ActionCard[] {
  const result: ActionCard[] = [];
  for (const item of items) {
    if (item.type === 'secret_request' && item.secretStatus === 'pending') {
      const local = (item.visibility === undefined || item.visibility === 'local');
      result.push({ id: text(item.id), requestId: '', kind: 'secret',
        label: text(item.label) + '\n' + text(item.reason) + (local ? '' : '\n等待在原会话中回答'),
        questions: [], enabled: local, responseType: local ? 'secret' : 'inherited', canDismiss: false,
        approvalOptions: [], requestKind: 'secret',
        detail: text(item.reason), reason: safeSecretUrl(item.url),
        fullAccessOverride: '', secretUrl: safeSecretUrl(item.url),
        secretPlaceholder: typeof item.placeholder === 'string' ? item.placeholder : '',
        secretDelivery: typeof item.delivery === 'string' ? item.delivery : '', secretReference: true });
    } else if (item.type === 'approval_request' || item.type === 'user_input_request') {
      const request = requests.find((row: Record<string, Object>) => row.id === item.requestId);
      if (!request || request.status !== 'pending') continue;
      const questions: Question[] = item.type === 'user_input_request' ? objects(item.questions).map((value: Object) => {
        const q = record(value);
        const options = objects(q.options).map(record);
        return { id: text(q.id), header: text(q.header), text: text(q.question), label: text(q.header) + ': ' + text(q.question),
          options: options.map((o: Record<string, Object>) => text(o.label) + ' — ' + text(o.description)),
          descriptions: options.map((o: Record<string, Object>) => text(o.description)),
          values: options.map((o: Record<string, Object>) => o.value === undefined ? text(o.label) : text(o.value)),
          multi: q.multiSelect === true, required: q.required !== false, custom: q.allowCustomAnswer !== false,
          initial: typeof q.initialAnswer === 'string' ? q.initialAnswer : '' };
      }) : [];
      const approvalOptions: ApprovalChoice[] = item.type === 'approval_request' && item.options !== undefined ?
        objects(item.options).map((value: Object): ApprovalChoice => {
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
        secretUrl: '', secretPlaceholder: '', secretDelivery: '', secretReference: true });
    }
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
