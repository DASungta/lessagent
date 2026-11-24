import { compactArray, optionalRecord, record, text } from './Wire';

export type AgentFeedbackKind = 'bug' | 'confusing' | 'missing_capability' | 'wrong_docs' | 'other';
export type AgentFeedbackStatus = 'pending' | 'sent' | 'declined' | 'cancelled';
export type AgentFeedbackMode = 'off' | 'on-request' | 'auto';
export type AgentFeedbackAnswer = 'send' | 'decline';

export interface AgentFeedbackTraceEntry {
  turn: number;
  type: 'user' | 'assistant' | 'tool';
  tool: string;
  outcome: string;
  durationMs: number;
  length: number;
  text: string;
}

export interface AgentFeedbackTrace {
  turns: number;
  textTurns: number;
  truncated: boolean;
  entries: AgentFeedbackTraceEntry[];
}

export interface AgentFeedbackPreview {
  kind: AgentFeedbackKind;
  subject: string;
  expected: string;
  actual: string;
  workaround: string;
  trace: AgentFeedbackTrace | undefined;
}

export interface AgentFeedbackRequestView {
  id: string;
  threadId: string;
  status: AgentFeedbackStatus;
  visibility: 'local' | 'inherited' | 'synthetic';
  preview: AgentFeedbackPreview;
  conversationTrace: AgentFeedbackTrace | undefined;
}

export interface AgentFeedbackDisplay {
  kind: 'pending' | 'pending-elsewhere' | 'answered';
  outcome: 'sent' | 'not-sent' | '';
  label: string;
}

const VALID_KINDS: string[] = ['bug', 'confusing', 'missing_capability', 'wrong_docs', 'other'];
const VALID_STATUSES: string[] = ['pending', 'sent', 'declined', 'cancelled'];
const VALID_MODES: string[] = ['off', 'on-request', 'auto'];

function parseTraceEntry(value: Object): AgentFeedbackTraceEntry {
  const row = record(value);
  const rawType = text(row.type);
  if (rawType !== 'user' && rawType !== 'assistant' && rawType !== 'tool') {
    throw new Error('反馈轨迹条目类型无效');
  }
  const turn = typeof row.turn === 'number' && Number.isFinite(row.turn) ? Math.floor(row.turn) : 0;
  return {
    turn,
    type: rawType as 'user' | 'assistant' | 'tool',
    tool: typeof row.tool === 'string' ? row.tool : '',
    outcome: typeof row.outcome === 'string' ? row.outcome : '',
    durationMs: typeof row.durationMs === 'number' && Number.isFinite(row.durationMs) ? Math.floor(row.durationMs) : -1,
    length: typeof row.length === 'number' && Number.isFinite(row.length) ? Math.floor(row.length) : -1,
    text: typeof row.text === 'string' ? row.text : ''
  };
}

function parseTrace(value: Object | undefined): AgentFeedbackTrace | undefined {
  const row = optionalRecord(value);
  if (!row) return undefined;
  const turns = typeof row.turns === 'number' && Number.isFinite(row.turns) ? Math.floor(row.turns) : 0;
  const textTurns = typeof row.textTurns === 'number' && Number.isFinite(row.textTurns) ? Math.floor(row.textTurns) : 0;
  return {
    turns,
    textTurns,
    truncated: row.truncated === true,
    entries: Array.isArray(row.entries) ? compactArray(row.entries, parseTraceEntry) : []
  };
}

export function parseAgentFeedbackRequest(item: Record<string, Object>, fallbackThreadId: string = ''): AgentFeedbackRequestView | undefined {
  if (item.type !== 'feedback_request') return undefined;
  const id = typeof item.id === 'string' ? item.id.trim() : '';
  if (!id) return undefined;
  const rawPreview = optionalRecord(item.preview);
  if (!rawPreview) return undefined;
  const rawKind = typeof rawPreview.kind === 'string' ? rawPreview.kind : 'other';
  const kind: AgentFeedbackKind = VALID_KINDS.includes(rawKind) ? rawKind as AgentFeedbackKind : 'other';
  const rawStatus = typeof item.feedbackStatus === 'string' ? item.feedbackStatus : 'pending';
  const status: AgentFeedbackStatus = VALID_STATUSES.includes(rawStatus) ? rawStatus as AgentFeedbackStatus : 'pending';
  const rawVis = typeof item.visibility === 'string' ? item.visibility : 'local';
  const visibility: 'local' | 'inherited' | 'synthetic' =
    rawVis === 'inherited' || rawVis === 'synthetic' ? rawVis : 'local';
  const threadId = typeof item.threadId === 'string' && item.threadId.trim() ? item.threadId.trim() : fallbackThreadId;
  return {
    id,
    threadId,
    status,
    visibility,
    preview: {
      kind,
      subject: typeof rawPreview.subject === 'string' ? rawPreview.subject : '',
      expected: typeof rawPreview.expected === 'string' ? rawPreview.expected : '',
      actual: typeof rawPreview.actual === 'string' ? rawPreview.actual : '',
      workaround: typeof rawPreview.workaround === 'string' ? rawPreview.workaround : '',
      trace: parseTrace(rawPreview.trace)
    },
    conversationTrace: parseTrace(item.conversationTrace)
  };
}

export function parseAgentFeedbackRequests(items: Record<string, Object>[], threadId: string = ''): AgentFeedbackRequestView[] {
  const result: AgentFeedbackRequestView[] = [];
  for (const item of items) {
    const parsed = parseAgentFeedbackRequest(item, threadId);
    if (parsed) result.push(parsed);
  }
  return result;
}

export function feedbackKindLabel(kind: AgentFeedbackKind): string {
  if (kind === 'bug') return '缺陷';
  if (kind === 'confusing') return '体验困惑';
  if (kind === 'missing_capability') return '缺少能力';
  if (kind === 'wrong_docs') return '文档有误';
  return '其他反馈';
}

export function feedbackRequestDisplay(item: AgentFeedbackRequestView): AgentFeedbackDisplay {
  if (item.status === 'pending') {
    if (item.visibility === 'local') {
      return { kind: 'pending', outcome: '', label: '待确认发送' };
    }
    return { kind: 'pending-elsewhere', outcome: '', label: '等待原会话处理' };
  }
  if (item.status === 'sent') {
    return { kind: 'answered', outcome: 'sent', label: '已发送' };
  }
  if (item.status === 'declined') {
    return { kind: 'answered', outcome: 'not-sent', label: '未发送' };
  }
  return { kind: 'answered', outcome: 'not-sent', label: '已关闭未发送' };
}

export function feedbackCardPreview(item: AgentFeedbackRequestView, includeConversation: boolean): AgentFeedbackPreview {
  const trace = includeConversation && item.conversationTrace !== undefined
    ? item.conversationTrace
    : item.preview.trace;
  return {
    kind: item.preview.kind,
    subject: item.preview.subject,
    expected: item.preview.expected,
    actual: item.preview.actual,
    workaround: item.preview.workaround,
    trace
  };
}

export function agentFeedbackAnswerPayload(
  threadId: string,
  turnItemId: string,
  answer: AgentFeedbackAnswer,
  includeConversation: boolean = false
): Record<string, Object> {
  const tid = threadId.trim();
  const iid = turnItemId.trim();
  if (!tid || !iid) throw new Error('反馈请求参数无效');
  if (answer !== 'send' && answer !== 'decline') throw new Error('反馈操作无效');
  const payload: Record<string, Object> = {
    threadId: tid,
    turnItemId: iid,
    answer
  };
  if (answer === 'send' && includeConversation) {
    payload.includeConversation = true;
  }
  return payload;
}

export function parseAgentFeedbackMode(value: Object | undefined): AgentFeedbackMode | undefined {
  const row = optionalRecord(value);
  if (!row) return undefined;
  const raw = typeof row.mode === 'string' ? row.mode : '';
  return VALID_MODES.includes(raw) ? raw as AgentFeedbackMode : undefined;
}

export function agentFeedbackErrorMessage(error: Object): string {
  const row = optionalRecord(error);
  const reason = row && typeof row.reason === 'string' ? row.reason : '';
  if (reason === 'load_failed') return '无法加载该反馈报告。';
  if (reason === 'not_found') return '该反馈报告已不存在。';
  if (reason === 'already_answered') return '该反馈报告已被处理。';
  if (reason === 'feedback_off') return '当前环境已关闭 Agent 反馈，报告未发送。';
  if (reason === 'record_failed') return '无法保存反馈答复，请稍后重试。';
  if (error instanceof Error && error.message) return error.message;
  return '反馈操作失败，请稍后重试。';
}
