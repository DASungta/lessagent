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
    encodeURIComponent(ticket) + '&clientSurface=mobile&clientOs=HarmonyOS&connectionMethod=direct';
}

export interface RpcSender {
  send(frame: string): Promise<void>;
}

export class RpcFailure extends Error {
  known: boolean;
  constructor(message: string, known: boolean) { super(message); this.known = known; }
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
    else pending.reject(new RpcFailure('服务端拒绝请求或任务失败，请在现有 T3 客户端核对详情', true));
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
  historyCursor: string = '';
  hasMoreHistory: boolean = false;

  constructor(threadId: string) { this.threadId = threadId; }

  apply(value: Object): void {
    const item = record(value);
    const kind = text(item.kind);
    if (kind === 'synchronized') return;
    if (kind === 'snapshot') {
      const cursor = sequence(item.snapshotSequence);
      if (cursor < this.cursor) return;
      const projection = record(item.projection);
      if (text(record(projection.thread).id) !== this.threadId) throw new Error('会话身份不一致');
      this.details = record(projection.thread);
      this.runs = projection.runs ? objects(projection.runs).map(record) : [];
      this.messageRecords = objects(projection.messages).map(record);
      this.plans = projection.plans ? objects(projection.plans).map(record) : [];
      this.subagents = projection.subagents ? objects(projection.subagents).map(record) : [];
      this.providerTurns = projection.providerTurns ? objects(projection.providerTurns).map(record) : [];
      const visible = projection.visibleTurnItems === undefined ? [] :
        objects(projection.visibleTurnItems).map((value: Object) => {
          const row = record(value);
          const item = row.item === undefined ? row : record(row.item);
          if (row.visibility !== undefined) item.visibility = row.visibility;
          if (row.sourceThreadId !== undefined) item.sourceThreadId = row.sourceThreadId;
          return item;
        });
      this.requests = projection.runtimeRequests ? objects(projection.runtimeRequests).map(record) : [];
      this.checkpoints = projection.checkpoints ? objects(projection.checkpoints).map(record) : [];
      this.items = visible.length ? visible : (projection.turnItems ? objects(projection.turnItems).map(record) : []);
      this.messages = [];
      const hasItemMessages = this.items.some((entry: Record<string, Object>) =>
        entry.type === 'user_message' || entry.type === 'assistant_message');
      if (hasItemMessages) {
        for (const item of this.items) this.upsertItemMessage(item);
      } else {
        const messages = objects(projection.messages);
        for (const raw of messages) {
          const msg = record(raw);
          if (!this.isHiddenContinuationMessage(msg)) this.upsert(msg);
        }
      }
      this.historyCursor = typeof item.historyCursor === 'string' ? item.historyCursor : '';
      this.hasMoreHistory = item.hasMoreHistory === true;
      this.cursor = cursor;
      return;
    }
    if (kind !== 'event') throw new Error('未知会话流类型');
    const cursor = sequence(item.sequence);
    if (cursor <= this.cursor) return;
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
      const payload = record(event.payload);
      this.mergeItemByOrdinal(payload);
      this.upsertItemMessage(payload);
    }
    else if (type === 'runtime-request.updated') this.merge(this.requests, record(event.payload));
    else if (type === 'checkpoint.captured' || type === 'checkpoint.updated') this.merge(this.checkpoints, record(event.payload));
    else if (type === 'run.created' || type === 'run.updated') {
      const run = record(event.payload);
      this.merge(this.runs, run);
      const active = this.runs.find((row: Record<string, Object>) =>
        ['preparing', 'starting', 'running', 'waiting'].includes(text(row.status)));
      this.notices = '任务状态：' + (active ? text(active.status) : text(run.status));
    }
    else if (type === 'plan.updated') this.merge(this.plans, record(event.payload));
    else if (type === 'subagent.updated') this.merge(this.subagents, record(event.payload));
    else if (type === 'provider-turn.updated') this.merge(this.providerTurns, record(event.payload));
    else if (['thread.metadata-updated', 'thread.model-selection-updated', 'thread.runtime-mode-updated', 'thread.interaction-mode-updated'].includes(type)) {
      const payload = record(event.payload);
      this.details = Object.assign({}, this.details, payload);
    } else if (type === 'thread.updated') this.details = Object.assign({}, this.details, record(event.payload));
    this.cursor = cursor;
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
    const textValue = typeof payload.text === 'string' && (payload.text.length > 0 || payload.bodyDeduped !== true)
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
      msgRecord.attachmentNames = objects(attachmentsSource).map((a: Object) => text(record(a).name));
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
          const names = item.attachments ? objects(item.attachments).map((a: Object) => text(record(a).name)) : [];
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
          attachmentNames: item.attachments ? objects(item.attachments).map((a: Object) => text(record(a).name)) : [] };
        if (typeof item.runId === 'string' && item.runId) entry.runId = item.runId;
        older.push(entry);
      }
      const itemId = text(item.id);
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
    const attachmentNames = message.attachments ? objects(message.attachments).map((a: Object) => text(record(a).name)) :
      Array.isArray(message.attachmentNames) ? (message.attachmentNames as Object[]).map((name: Object) => text(name)) :
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
