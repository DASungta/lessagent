// Wire subset verified against DASungta/t3code ad1b136 and Effect 4.1.3.
export function record(value: Object): Record<string, Object> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error('协议格式错误：需要对象');
  }
  return value as Record<string, Object>;
}

export function text(value: Object): string {
  if (typeof value !== 'string') throw new Error('协议格式错误：需要字符串');
  return value;
}

export function sequence(value: Object): number {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0) {
    throw new Error('协议格式错误：无效序列号');
  }
  return value;
}

export function objects(value: Object): Object[] {
  if (!Array.isArray(value)) throw new Error('协议格式错误：需要数组');
  return value as Object[];
}

export function compactObjects(value: Object | undefined): Record<string, Object>[] {
  if (!Array.isArray(value)) return [];
  const result: Record<string, Object>[] = [];
  for (const item of value as Object[]) {
    if (item !== null && typeof item === 'object' && !Array.isArray(item)) {
      result.push(item as Record<string, Object>);
    }
  }
  return result;
}

export function compactArray<T>(value: Object | undefined, parse: (item: Object) => T): T[] {
  if (!Array.isArray(value)) return [];
  const result: T[] = [];
  for (const item of value as Object[]) {
    try {
      result.push(parse(item));
    } catch (_) {}
  }
  return result;
}

export interface OptionSelection { id: string; value: string | boolean; }
export interface ModelSelection { instanceId: string; model: string; options?: OptionSelection[]; }

export function parseOptionSelections(value: Object | undefined): OptionSelection[] {
  if (value === undefined || value === null || typeof value !== 'object') return [];
  const entries: OptionSelection[] = [];
  const upsert = (rawId: string, rawValue: Object | undefined): void => {
    const id = rawId.trim();
    if (!id || id.length > 256 || /[\u0000-\u001f\u007f]/.test(id)) return;
    let parsed: string | boolean | undefined = undefined;
    if (typeof rawValue === 'boolean') parsed = rawValue;
    else if (typeof rawValue === 'string') {
      const trimmed = rawValue.trim();
      if (trimmed && trimmed.length <= 256 && !/[\u0000-\u001f\u007f]/.test(trimmed)) parsed = trimmed;
    }
    if (parsed === undefined) return;
    const existing = entries.findIndex((item: OptionSelection) => item.id === id);
    if (existing >= 0) entries[existing] = { id, value: parsed };
    else entries.push({ id, value: parsed });
  };
  if (Array.isArray(value)) {
    for (const item of value as Object[]) {
      if (item === null || typeof item !== 'object' || Array.isArray(item)) continue;
      const option = item as Record<string, Object>;
      if (typeof option.id === 'string') upsert(option.id, option.value);
    }
    return entries;
  }
  const legacy = value as Record<string, Object>;
  for (const key of Object.keys(legacy)) upsert(key, legacy[key]);
  return entries;
}

export function parseModelSelection(value: Object | undefined): ModelSelection | undefined {
  if (value === undefined || value === null || typeof value !== 'object' || Array.isArray(value)) return undefined;
  const row = value as Record<string, Object>;
  const instanceId = typeof row.instanceId === 'string' ? row.instanceId.trim() :
    (typeof row.provider === 'string' ? row.provider.trim() : '');
  const model = typeof row.model === 'string' ? row.model.trim() : '';
  if (!instanceId || !model || instanceId.length > 256 || model.length > 256 ||
    /[\u0000-\u001f\u007f]/.test(instanceId) || /[\u0000-\u001f\u007f]/.test(model)) {
    return undefined;
  }
  const options = parseOptionSelections(row.options);
  return options.length > 0 ? { instanceId, model, options } : { instanceId, model };
}

export function serverBase(input: string): string {
  const base = input.trim().replace(/\/+$/, '');
  // Explicit HTTP matches upstream direct pairing, including LAN/tailnet; never relax TLS or redirects.
  const match = /^https?:\/\/([a-zA-Z0-9.-]+|\[[a-fA-F0-9:]+\])(?::(\d+))?$/.exec(base);
  if (!match || (match[2] && (Number(match[2]) < 1 || Number(match[2]) > 65535))) {
    throw new Error('请输入有效的 HTTP 或 HTTPS 服务根地址');
  }
  return base;
}

export function bootstrapForm(credential: string): string {
  if (credential.trim() === '') throw new Error('请输入配对凭据');
  return 'grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Atoken-exchange' +
    '&subject_token=' + encodeURIComponent(credential.trim()) +
    '&subject_token_type=urn%3At3%3Aparams%3Aoauth%3Atoken-type%3Aenvironment-bootstrap' +
    '&requested_token_type=urn%3Aietf%3Aparams%3Aoauth%3Atoken-type%3Aaccess_token' +
    '&client_label=T3%20Harmony&client_device_type=mobile&client_os=HarmonyOS';
}

export function validateDescriptor(value: Object): Record<string, Object> {
  const descriptor = record(value);
  text(descriptor.environmentId);
  text(descriptor.serverVersion);
  text(descriptor.label);
  if (descriptor.orchestrationProtocolVersion !== 2) {
    throw new Error('服务端协议不兼容：本原型仅支持 orchestrationProtocol=2');
  }
  return descriptor;
}

export function socketUrl(base: string, ticket: string): string {
  return base.replace(/^http/, 'ws') + '/ws?orchestrationProtocol=2&wsTicket=' +
    encodeURIComponent(ticket) + '&clientSurface=mobile&clientOs=HarmonyOS&connectionMethod=direct&frameParts=1';
}

export interface RpcSender {
  send(frame: string): Promise<void>;
}

export class RpcFailure extends Error {
  known: boolean;
  errorTag: string;
  errorReason: string;
  constructor(message: string, known: boolean, errorTag: string = '', errorReason: string = '') {
    super(message);
    this.known = known;
    this.errorTag = errorTag;
    this.errorReason = errorReason;
  }
}

interface FailureCode { tag: string; reason: string; }

function inspectFailureReason(entry: Object | undefined): FailureCode {
  if (entry === undefined || entry === null || typeof entry !== 'object' || Array.isArray(entry)) {
    return { tag: '', reason: '' };
  }
  const row = entry as Record<string, Object>;
  if (row._tag !== 'Fail') return { tag: '', reason: '' };
  const err = row.error;
  if (err === undefined || err === null || typeof err !== 'object' || Array.isArray(err)) {
    return { tag: '', reason: '' };
  }
  const errObj = err as Record<string, Object>;
  const tag = typeof errObj._tag === 'string' && /^[A-Za-z][A-Za-z0-9_]{0,63}$/.test(errObj._tag) ? errObj._tag : '';
  const reason = typeof errObj.reason === 'string' && /^[a-z][a-z0-9_]{0,63}$/.test(errObj.reason) ? errObj.reason : '';
  return { tag, reason };
}

function extractFailureCode(cause: Object | undefined): FailureCode {
  if (cause === undefined || cause === null) return { tag: '', reason: '' };
  if (Array.isArray(cause)) {
    for (const item of cause as Object[]) {
      const found = inspectFailureReason(item);
      if (found.tag || found.reason) return found;
    }
    return { tag: '', reason: '' };
  }
  if (typeof cause === 'object') {
    const obj = cause as Record<string, Object>;
    if (Array.isArray(obj.reasons)) {
      for (const item of obj.reasons as Object[]) {
        const found = inspectFailureReason(item);
        if (found.tag || found.reason) return found;
      }
      return { tag: '', reason: '' };
    }
    return inspectFailureReason(obj);
  }
  return { tag: '', reason: '' };
}

interface Pending {
  resolve: (value: Object) => void;
  reject: (error: Error) => void;
  chunk: ((value: Object) => void) | undefined;
  timer: number;
}

export class RpcClient {
  private sender: RpcSender;
  private pending: Map<string, Pending> = new Map();
  private nextId: number = 0;
  private live: boolean = true;
  private parts: string = '';
  onFailure: (message: string) => void = () => {};

  constructor(sender: RpcSender) { this.sender = sender; }

  request(method: string, payload: Object, chunk?: (value: Object) => void,
    timeoutMs: number = 15000, fatalTimeout: boolean = true): Promise<Object> {
    if (!this.live) return Promise.reject(new Error('连接已断开，请重新连接后核对会话'));
    const id = String(++this.nextId);
    return new Promise<Object>((resolve, reject) => {
      const timer = setTimeout(() => {
        if (fatalTimeout) {
          void this.sender.send(JSON.stringify({ _tag: 'Interrupt', requestId: id })).catch(() => {});
          this.fail('请求超时；修改类请求的结果未知，请先核对会话，不要直接重发');
        } else {
          if (chunk) void this.sender.send(JSON.stringify({ _tag: 'Interrupt', requestId: id })).catch(() => {});
          this.pending.delete(id);
          reject(new RpcFailure('请求超时，请重试', false));
        }
      }, timeoutMs) as number;
      this.pending.set(id, { resolve, reject, chunk, timer });
      this.sender.send(JSON.stringify({ _tag: 'Request', id, tag: method, payload, headers: [] }))
        .catch(() => this.fail('发送失败；提交结果未知，请重新连接后核对会话'));
    });
  }

  receive(frame: string): void {
    if (!this.live) return;
    try {
      if (this.parts.length + frame.length > 16 * 1024 * 1024) {
        throw new Error('协议消息过大');
      }
      if (frame.startsWith('\u001e')) {
        this.parts += frame.slice(1);
        return;
      }
      const decoded = JSON.parse(this.parts + frame) as Object;
      this.parts = '';
      const batch: Object[] = Array.isArray(decoded) ? decoded as Object[] : [decoded];
      for (const value of batch) this.accept(record(value));
    } catch (_) {
      this.fail('协议消息无效或超出原型能力，请检查服务端版本');
    }
  }

  private accept(message: Record<string, Object>): void {
    const tag = text(message._tag);
    if (tag === 'Pong') return;
    if (tag === 'Ping') {
      void this.sender.send('{"_tag":"Pong"}').catch(() => this.fail('心跳发送失败'));
      return;
    }
    if (tag === 'Defect' || tag === 'ClientProtocolError') {
      this.fail('服务端报告 RPC 协议错误');
      return;
    }
    if (tag !== 'Chunk' && tag !== 'Exit') throw new Error('未知 RPC 帧');
    if (typeof message.requestId !== 'string' && typeof message.requestId !== 'number') {
      throw new Error('缺少请求编号');
    }
    const id = String(message.requestId);
    const pending = this.pending.get(id);
    if (!pending) return;
    if (tag === 'Chunk') {
      if (!pending.chunk) throw new Error('非流式请求收到数据批次');
      for (const value of objects(message.values)) pending.chunk(value);
      clearTimeout(pending.timer);
      pending.timer = 0;
      void this.sender.send(JSON.stringify({ _tag: 'Ack', requestId: message.requestId }))
        .catch(() => this.fail('流式确认失败，请重新连接同步'));
      return;
    }
    const exit = record(message.exit);
    const exitTag = text(exit._tag);
    if (exitTag !== 'Success' && exitTag !== 'Failure') throw new Error('未知结束状态');
    clearTimeout(pending.timer);
    this.pending.delete(id);
    if (exitTag === 'Success') pending.resolve(exit.value);
    else {
      const code = extractFailureCode(exit.cause);
      pending.reject(new RpcFailure('服务端拒绝请求或任务失败，请在现有 T3 客户端核对详情', true, code.tag, code.reason));
    }
  }

  cancelStream(chunk: (value: Object) => void): void {
    for (const [id, pending] of this.pending) {
      if (pending.chunk !== chunk) continue;
      clearTimeout(pending.timer);
      this.pending.delete(id);
      pending.resolve({});
      void this.sender.send(JSON.stringify({ _tag: 'Interrupt', requestId: id }))
        .catch(() => this.fail('取消订阅失败'));
    }
  }

  ping(): void {
    if (this.live) void this.sender.send('{"_tag":"Ping"}').catch(() => this.fail('心跳失败'));
  }

  fail(message: string): void {
    if (!this.live) return;
    this.live = false;
    this.parts = '';
    for (const pending of this.pending.values()) {
      clearTimeout(pending.timer);
      pending.reject(new RpcFailure(message, false));
    }
    this.pending.clear();
    this.onFailure(message);
  }
}

export interface ChatMessage {
  id: string;
  role: string;
  text: string;
  streaming: boolean;
  runId?: string;
  attachmentNames?: string[];
  timestamp?: string;
}

export class ThreadState {
  threadId: string;
  cursor: number = -1;
  resumeCursor: number = -1;
  messages: ChatMessage[] = [];
  notices: string = '';
  requests: Record<string, Object>[] = [];
  items: Record<string, Object>[] = [];
  checkpoints: Record<string, Object>[] = [];
  details: Record<string, Object> = {};
  runs: Record<string, Object>[] = [];
  messageRecords: Record<string, Object>[] = [];
  plans: Record<string, Object>[] = [];
  subagents: Record<string, Object>[] = [];
  providerTurns: Record<string, Object>[] = [];
  providerThreads: Record<string, Object>[] = [];
  providerSessions: Record<string, Object>[] = [];
  nodes: Record<string, Object>[] = [];
  historyCursor: string = '';
  hasMoreHistory: boolean = false;

  constructor(threadId: string) { this.threadId = threadId; }

  resetForReconnect(): void {
    if (this.cursor >= 0) this.resumeCursor = this.cursor;
    this.cursor = -1;
  }

  apply(value: Object): void {
    const item = record(value);
    const kind = text(item.kind);
    if (kind === 'synchronized') {
      if (this.cursor < 0 && this.resumeCursor >= 0) this.cursor = this.resumeCursor;
      return;
    }
    if (kind === 'snapshot') {
      const cursor = sequence(item.snapshotSequence);
      if (cursor < this.cursor) return;
      const projection = record(item.projection);
      if (text(record(projection.thread).id) !== this.threadId) throw new Error('会话身份不一致');
      this.details = record(projection.thread);
      this.runs = projection.runs ? compactObjects(projection.runs) : [];
      this.messageRecords = compactObjects(projection.messages);
      this.plans = projection.plans ? compactObjects(projection.plans) : [];
      this.subagents = projection.subagents ? compactObjects(projection.subagents) : [];
      this.providerTurns = projection.providerTurns ? compactObjects(projection.providerTurns) : [];
      this.providerThreads = projection.providerThreads ? compactObjects(projection.providerThreads) : [];
      this.providerSessions = projection.providerSessions ? compactObjects(projection.providerSessions) : [];
      this.nodes = projection.nodes ? compactObjects(projection.nodes) : [];
      const visible = projection.visibleTurnItems === undefined ? [] :
        compactArray(projection.visibleTurnItems, (value: Object): Record<string, Object> => {
          const row = record(value);
          const item = row.item === undefined ? row : record(row.item);
          if (row.visibility !== undefined) item.visibility = row.visibility;
          if (row.sourceThreadId !== undefined) item.sourceThreadId = row.sourceThreadId;
          return item;
        });
      this.requests = projection.runtimeRequests ? compactObjects(projection.runtimeRequests) : [];
      this.checkpoints = projection.checkpoints ? compactObjects(projection.checkpoints) : [];
      const rawItems = visible.length ? visible : (projection.turnItems ? compactObjects(projection.turnItems) : []);
      this.items = rawItems.map((entry: Record<string, Object>) => this.restoreDedupedTurnItem(entry));
      this.messages = [];
      const hasItemMessages = this.items.some((entry: Record<string, Object>) =>
        entry.type === 'user_message' || entry.type === 'assistant_message');
      if (hasItemMessages) {
        for (const item of this.items) this.upsertItemMessage(item);
      } else {
        for (const msg of this.messageRecords) {
          if (!this.isHiddenContinuationMessage(msg)) this.upsert(msg);
        }
      }
      this.historyCursor = typeof item.historyCursor === 'string' ? item.historyCursor : '';
      this.hasMoreHistory = item.hasMoreHistory === true;
      this.cursor = cursor;
      this.resumeCursor = cursor;
      return;
    }
    if (kind !== 'event') return;
    const cursor = sequence(item.sequence);
    const floor = this.cursor >= 0 ? this.cursor : this.resumeCursor;
    if (cursor <= floor) return;
    // Sequences are global; gaps do not imply a missing event in this thread.
    const event = record(item.event);
    if (text(event.threadId) !== this.threadId) throw new Error('会话事件身份不一致');
    const type = text(event.type);
    if (type === 'message.updated') {
      const payload = record(event.payload);
      this.merge(this.messageRecords, payload);
      const isQueued = typeof payload.runId === 'string' &&
        this.runs.some((r: Record<string, Object>) => r.id === payload.runId && r.status === 'queued');
      if (!this.isHiddenContinuationMessage(payload) && !isQueued) {
        this.upsert(payload);
      }
    }
    else if (type === 'turn-item.updated') {
      const payload = this.restoreDedupedTurnItem(record(event.payload));
      if (typeof payload.id === 'string' && payload.id) {
        this.mergeItemByOrdinal(payload);
        this.upsertItemMessage(payload);
      }
    }
    else if (type === 'runtime-request.updated') this.merge(this.requests, record(event.payload));
    else if (type === 'checkpoint.captured' || type === 'checkpoint.updated') this.merge(this.checkpoints, record(event.payload));
    else if (type === 'run.created' || type === 'run.updated') {
      const run = record(event.payload);
      this.merge(this.runs, run);
      const active = this.runs.find((row: Record<string, Object>) =>
        typeof row.status === 'string' && ['preparing', 'starting', 'running', 'waiting'].includes(row.status));
      const runStatus = active && typeof active.status === 'string' ? active.status :
        (typeof run.status === 'string' ? run.status : '');
      if (runStatus) this.notices = '任务状态：' + runStatus;
    }
    else if (type === 'plan.updated') this.merge(this.plans, record(event.payload));
    else if (type === 'subagent.updated') {
      const payload = record(event.payload);
      const existing = this.subagents.find((row: Record<string, Object>) => row.id === text(payload.id));
      if (existing !== undefined) {
        if (payload.promptOmitted === true && existing.prompt !== undefined) payload.prompt = existing.prompt;
        if (payload.resultOmitted === true && existing.result !== undefined) payload.result = existing.result;
      }
      this.merge(this.subagents, payload);
    }
    else if (type === 'provider-turn.updated') this.merge(this.providerTurns, record(event.payload));
    else if (type === 'provider-thread.updated') {
      const payload = record(event.payload);
      this.merge(this.providerThreads, payload);
      const isQueuedPlaceholder = payload.status === 'not_loaded' &&
        (payload.nativeThreadRef === undefined || payload.nativeThreadRef === null) &&
        (payload.firstRunOrdinal === undefined || payload.firstRunOrdinal === null);
      if (payload.appThreadId === this.threadId && !isQueuedPlaceholder) {
        this.details = Object.assign({}, this.details, { activeProviderThreadId: payload.id });
      }
    }
    else if (type === 'provider-session.attached' || type === 'provider-session.updated') {
      this.merge(this.providerSessions, record(event.payload));
    }
    else if (type === 'provider-session.detached') {
      const payload = record(event.payload);
      const detachedId = typeof payload.providerSessionId === 'string' ? payload.providerSessionId : text(payload.id);
      this.providerSessions = this.providerSessions.filter((session: Record<string, Object>) => session.id !== detachedId);
    }
    else if (type === 'node.updated') this.merge(this.nodes, record(event.payload));
    else if (type === 'thread.visit-recorded') {
      const payload = record(event.payload);
      const patch: Record<string, Object> = {};
      if (payload.lastVisitedAt !== undefined) patch.lastVisitedAt = payload.lastVisitedAt;
      if (payload.opens !== undefined) patch.opens = payload.opens;
      this.details = Object.assign({}, this.details, patch);
    }
    else if (type === 'thread.pull-request-link-updated') {
      const payload = record(event.payload);
      if (Array.isArray(payload.pullRequests)) {
        this.details = Object.assign({}, this.details, { pullRequests: payload.pullRequests });
      } else if (typeof payload.host === 'string' && typeof payload.repository === 'string' && typeof payload.number === 'number') {
        const current = Array.isArray(this.details.pullRequests) ? compactObjects(this.details.pullRequests) : [];
        const host = String(payload.host).toLowerCase();
        const repo = String(payload.repository).toLowerCase();
        const num = payload.number as number;
        const filtered = current.filter((link: Record<string, Object>) =>
          !(String(link.host || '').toLowerCase() === host &&
            String(link.repository || '').toLowerCase() === repo &&
            link.number === num));
        if (payload.action !== 'unlinked') {
          const nextLink = payload.link !== undefined && payload.link !== null ? record(payload.link) : payload;
          filtered.push(nextLink);
        }
        this.details = Object.assign({}, this.details, { pullRequests: filtered });
      }
    }
    else if ([
      'thread.metadata-updated', 'thread.model-selection-updated', 'thread.runtime-mode-updated',
      'thread.interaction-mode-updated', 'thread.updated',
      'thread.settled', 'thread.unsettled', 'thread.snoozed', 'thread.unsnoozed',
      'thread.auto-settle-set', 'thread.pinned', 'thread.unpinned',
      'thread.pin-reordered', 'thread.active-reordered',
      'thread.archived', 'thread.unarchived', 'thread.deleted',
      'thread.provider-switched', 'thread.guest-share-updated', 'thread.pull-request-synced',
      'thread.visited', 'thread.tags-updated', 'thread.marked-unread'
    ].includes(type)) {
      const payload = record(event.payload);
      this.details = Object.assign({}, this.details, payload);
    }
    this.cursor = cursor;
    this.resumeCursor = cursor;
  }

  private isHiddenContinuationMessage(payload: Record<string, Object>): boolean {
    return (payload.role === 'user' || payload.type === 'user_message') && payload.createdBy === 'agent' &&
      (payload.notification !== undefined || payload.creationSource === 'provider');
  }

  private findMessageRecord(id: string): Record<string, Object> | undefined {
    for (let index = this.messageRecords.length - 1; index >= 0; index -= 1) {
      if (this.messageRecords[index].id === id) return this.messageRecords[index];
    }
    return undefined;
  }

  private findCheckpointRecord(id: string): Record<string, Object> | undefined {
    for (let index = this.checkpoints.length - 1; index >= 0; index -= 1) {
      if (this.checkpoints[index].id === id) return this.checkpoints[index];
    }
    return undefined;
  }

  private findSubagentRecord(id: string): Record<string, Object> | undefined {
    for (let index = this.subagents.length - 1; index >= 0; index -= 1) {
      if (this.subagents[index].id === id) return this.subagents[index];
    }
    return undefined;
  }

  private restoreDedupedTurnItem(payload: Record<string, Object>): Record<string, Object> {
    if ((payload.type === 'user_message' || payload.type === 'assistant_message') &&
      (payload.textOmitted === true || payload.bodyDeduped === true) && typeof payload.messageId === 'string') {
      const matched = this.findMessageRecord(payload.messageId);
      if (matched && typeof matched.text === 'string') {
        payload.text = matched.text;
        delete payload.textOmitted;
        delete payload.bodyDeduped;
      }
      return payload;
    }
    if (payload.type === 'checkpoint' && payload.filesOmitted === true && typeof payload.checkpointId === 'string') {
      const matched = this.findCheckpointRecord(payload.checkpointId);
      if (matched && Array.isArray(matched.files)) {
        payload.files = matched.files;
        delete payload.filesOmitted;
      }
      return payload;
    }
    if (payload.type === 'subagent' && (payload.promptOmitted === true || payload.resultOmitted === true) &&
      typeof payload.subagentId === 'string') {
      const matched = this.findSubagentRecord(payload.subagentId);
      if (matched) {
        if (payload.promptOmitted === true && matched.promptOmitted !== true && matched.prompt !== undefined) {
          payload.prompt = matched.prompt;
          delete payload.promptOmitted;
        }
        if (payload.resultOmitted === true && matched.resultOmitted !== true && matched.result !== undefined) {
          payload.result = matched.result;
          delete payload.resultOmitted;
        }
      }
    }
    return payload;
  }

  private extractAttachmentNames(source: Object | undefined): string[] {
    if (!Array.isArray(source)) return [];
    const names: string[] = [];
    for (const entry of source as Object[]) {
      if (typeof entry === 'string') {
        if (entry) names.push(entry);
      } else if (entry !== null && typeof entry === 'object' && !Array.isArray(entry)) {
        const name = (entry as Record<string, Object>).name;
        if (typeof name === 'string' && name) names.push(name);
      }
    }
    return names;
  }

  private mergeItemByOrdinal(payload: Record<string, Object>): void {
    const id = text(payload.id);
    const existingIndex = this.items.findIndex((item: Record<string, Object>) => item.id === id);
    if (existingIndex >= 0) {
      const previous = this.items[existingIndex];
      if (payload.visibility === undefined && previous.visibility !== undefined) payload.visibility = previous.visibility;
      if (payload.sourceThreadId === undefined && previous.sourceThreadId !== undefined) payload.sourceThreadId = previous.sourceThreadId;
      this.items[existingIndex] = payload;
      return;
    }
    if (typeof payload.ordinal === 'number') {
      const targetOrdinal = payload.ordinal as number;
      const insertAt = this.items.findIndex((item: Record<string, Object>) =>
        typeof item.ordinal === 'number' && (item.ordinal as number) > targetOrdinal);
      if (insertAt >= 0) {
        this.items.splice(insertAt, 0, payload);
        return;
      }
    }
    this.items.push(payload);
  }

  private upsertItemMessage(payload: Record<string, Object>): void {
    if (payload.type !== 'assistant_message' && payload.type !== 'user_message') return;
    if (payload.type === 'user_message' && payload.inputIntent === 'queued_turn' && payload.status === 'pending') return;
    if (payload.type === 'user_message' && this.isHiddenContinuationMessage(payload)) return;
    if (typeof payload.messageId !== 'string') return;
    const matched = this.findMessageRecord(payload.messageId);
    const bodyOmitted = payload.textOmitted === true || payload.bodyDeduped === true;
    const textValue = typeof payload.text === 'string' && (payload.text.length > 0 || !bodyOmitted)
      ? payload.text
      : (matched && typeof matched.text === 'string' ? matched.text : undefined);
    if (typeof textValue !== 'string') return;
    const role = payload.type === 'user_message' ? 'user' : 'assistant';
    const streaming = payload.type === 'assistant_message' && payload.streaming === true;
    const createdAt = (matched && typeof matched.createdAt === 'string' ? matched.createdAt : undefined) ||
      (typeof payload.startedAt === 'string' ? payload.startedAt : undefined) ||
      (typeof payload.createdAt === 'string' ? payload.createdAt : undefined) ||
      (typeof payload.completedAt === 'string' ? payload.completedAt : undefined);
    const attachmentsSource = payload.attachments !== undefined ? payload.attachments : matched?.attachments;
    const msgRecord: Record<string, Object> = {
      id: payload.messageId,
      threadId: this.threadId,
      role,
      text: textValue,
      streaming,
      runId: typeof payload.runId === 'string' ? payload.runId : ''
    };
    if (createdAt) msgRecord.createdAt = createdAt;
    if (Array.isArray(attachmentsSource)) {
      msgRecord.attachmentNames = this.extractAttachmentNames(attachmentsSource);
    }
    this.upsert(msgRecord);
  }

  prependHistory(items: Record<string, Object>[]): void {
    const older: ChatMessage[] = [];
    const unseenItems: Record<string, Object>[] = [];
    for (const item of items) {
      if (item.type === 'user_message' && typeof item.messageId === 'string' && typeof item.text === 'string') {
        const isQueued = item.inputIntent === 'queued_turn' && item.status === 'pending';
        if (!isQueued && !this.isHiddenContinuationMessage(item)) {
          const names = this.extractAttachmentNames(item.attachments);
          if (item.text.trim() || names.length) {
            const matched = this.findMessageRecord(item.messageId);
            const ts = (matched && typeof matched.createdAt === 'string' ? matched.createdAt : undefined) ||
              (typeof item.createdAt === 'string' ? item.createdAt : undefined) ||
              (typeof item.startedAt === 'string' ? item.startedAt : undefined);
            const entry: ChatMessage = { id: item.messageId, role: 'user', text: item.text,
              streaming: false, timestamp: ts,
              attachmentNames: names };
            if (typeof item.runId === 'string' && item.runId) entry.runId = item.runId;
            older.push(entry);
          }
        }
      } else if (item.type === 'assistant_message' && typeof item.messageId === 'string' && typeof item.text === 'string') {
        const matched = this.findMessageRecord(item.messageId);
        const ts = (matched && typeof matched.createdAt === 'string' ? matched.createdAt : undefined) ||
          (typeof item.startedAt === 'string' ? item.startedAt : undefined) ||
          (typeof item.createdAt === 'string' ? item.createdAt : undefined) ||
          (typeof item.completedAt === 'string' ? item.completedAt : undefined);
        const entry: ChatMessage = { id: item.messageId, role: 'assistant', text: item.text, streaming: item.streaming === true,
          timestamp: ts,
          attachmentNames: this.extractAttachmentNames(item.attachments) };
        if (typeof item.runId === 'string' && item.runId) entry.runId = item.runId;
        older.push(entry);
      }
      if (typeof item.id !== 'string' || !item.id) continue;
      const itemId = item.id;
      const existingItemIndex = this.items.findIndex((row: Record<string, Object>) => row.id === itemId);
      if (existingItemIndex >= 0) {
        const previous = this.items[existingItemIndex];
        if (item.visibility === undefined && previous.visibility !== undefined) item.visibility = previous.visibility;
        if (item.sourceThreadId === undefined && previous.sourceThreadId !== undefined) item.sourceThreadId = previous.sourceThreadId;
        this.items[existingItemIndex] = item;
      } else if (!unseenItems.some((row: Record<string, Object>) => row.id === itemId)) {
        unseenItems.push(item);
      }
    }
    if (unseenItems.length) this.items = unseenItems.concat(this.items);
    const existing = new Set<string>(this.messages.map((message: ChatMessage) => message.id));
    this.messages = older.filter((message: ChatMessage) => !existing.has(message.id)).concat(this.messages);
  }

  private merge(rows: Record<string, Object>[], row: Record<string, Object>): void {
    const id = text(row.id);
    const index = rows.findIndex((item: Record<string, Object>) => item.id === id);
    if (index < 0) rows.push(row);
    else {
      const previous = rows[index];
      if (row.visibility === undefined && previous.visibility !== undefined) row.visibility = previous.visibility;
      if (row.sourceThreadId === undefined && previous.sourceThreadId !== undefined) row.sourceThreadId = previous.sourceThreadId;
      rows[index] = row;
    }
  }

  private upsert(message: Record<string, Object>): void {
    const role = text(message.role);
    if (role !== 'user' && role !== 'assistant' && role !== 'system') throw new Error('无效消息角色');
    const body = text(message.text);
    if (role === 'user' && !body.trim() &&
      (message.attachments === undefined || objects(message.attachments).length === 0)) return;
    if (text(message.threadId) !== this.threadId || typeof message.streaming !== 'boolean') {
      throw new Error('无效消息身份或流式状态');
    }
    const index = this.messages.findIndex((entry: ChatMessage) => entry.id === text(message.id));
    const existing = index >= 0 ? this.messages[index] : undefined;
    const attachmentNames = message.attachments !== undefined ? this.extractAttachmentNames(message.attachments) :
      Array.isArray(message.attachmentNames) ? this.extractAttachmentNames(message.attachmentNames) :
      (existing?.attachmentNames || []);
    const next: ChatMessage = {
      id: text(message.id),
      role,
      text: body,
      streaming: message.streaming === true,
      timestamp: typeof message.createdAt === 'string' ? message.createdAt :
        (typeof message.timestamp === 'string' ? message.timestamp : existing?.timestamp),
      attachmentNames
    };
    const runId = typeof message.runId === 'string' && message.runId ? message.runId : existing?.runId;
    if (runId) next.runId = runId;
    if (index < 0) this.messages.push(next);
    else this.messages[index] = next;
  }
}

export function createThread(commandId: string, threadId: string, projectId: string,
  instanceId: string, model: string): Object {
  if (!projectId.trim() || !instanceId.trim() || !model.trim()) throw new Error('请填写项目、Provider 实例和模型');
  return {
    type: 'thread.create', commandId, threadId, projectId: projectId.trim(),
    title: 'Harmony 新会话', modelSelection: { instanceId: instanceId.trim(), model: model.trim() },
    runtimeMode: 'approval-required', interactionMode: 'default', branch: null, worktreePath: null,
    createdBy: 'user', creationSource: 'mobile'
  };
}

export function sendMessage(commandId: string, threadId: string, messageId: string, prompt: string): Object {
  if (!prompt.trim()) throw new Error('请输入指令');
  return {
    type: 'message.dispatch', commandId, threadId, messageId, text: prompt, attachments: [],
    createdBy: 'user', creationSource: 'mobile', dispatchMode: { type: 'start_immediately' }
  };
}
