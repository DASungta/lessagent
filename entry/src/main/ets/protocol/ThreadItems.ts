import { ChatMessage, record, text, objects } from './Wire';

export interface ActivityLine { label: string; text: string; kind: string; itemId: string; }

function optional(value: Object | undefined): string { return typeof value === 'string' ? value : ''; }

export function activityLines(items: Record<string, Object>[]): ActivityLine[] {
  return items.filter((item: Record<string, Object>) =>
    !['assistant_message', 'user_message', 'link_request', 'secret_request',
      'user_input_request', 'approval_request'].includes(text(item.type))).map((item: Record<string, Object>): ActivityLine => {
    const type = text(item.type);
    const id = text(item.id);
    const status = optional(item.status);
    if (type === 'command_execution') {
      const exit = typeof item.exitCode === 'number' ? ' · exit ' + item.exitCode : '';
      return { itemId: id, kind: type, label: '命令 · ' + status + exit,
        text: optional(item.input) + (optional(item.output) ? '\n' + optional(item.output) :
          item.outputOmitted === true ? '\n输出未随快照提供，展开后读取完整输出' : '') };
    }
    if (type === 'file_change') {
      return { itemId: id, kind: type, label: optional(item.fileName) + ' · +' +
        String(typeof item.additions === 'number' ? item.additions : 0) + ' −' +
        String(typeof item.deletions === 'number' ? item.deletions : 0),
        text: optional(item.diffStr) || (optional(item.oldStr) + '\n→\n' + optional(item.newStr)) };
    }
    if (type === 'file_search') {
      return { itemId: id, kind: type, label: '文件搜索 · ' + status,
        text: optional(item.pattern) + '\n' + objects(item.results || []).map((value: Object) =>
          text(record(value).fileName)).join('\n') };
    }
    if (type === 'web_search') {
      return { itemId: id, kind: type, label: '网络搜索 · ' + status,
        text: objects(item.patterns || []).map((value: Object) => text(value)).join(', ') + '\n' +
          objects(item.results || []).map((value: Object) => {
            const row = record(value);
            return (optional(row.title) || optional(row.url)) + '\n' + optional(row.url) + '\n' + optional(row.snippet);
          }).join('\n') };
    }
    if (type === 'todo_list') {
      return { itemId: id, kind: type, label: '计划步骤 · ' + status,
        text: objects(item.steps || []).map((value: Object) => {
          const step = record(value);
          return '[' + optional(step.status) + '] ' + optional(step.text);
        }).join('\n') };
    }
    if (type === 'system_notice') return { itemId: id, kind: type, label: '系统提示', text: optional(item.message) };
    if (type === 'error') {
      const failure = item.failure !== undefined ? record(item.failure) : {};
      return { itemId: id, kind: type, label: '错误 · ' + optional(failure.class),
        text: optional(failure.message) + (typeof failure.code === 'string' ? '\n' + failure.code : '') };
    }
    if (type === 'run_interrupt_request' || type === 'run_interrupt_result') {
      return { itemId: id, kind: type, label: '停止运行', text: optional(item.message) };
    }
    if (type === 'reasoning') {
      return { itemId: id, kind: type, label: '思考过程' + (status ? ' · ' + status : ''),
        text: typeof item.text === 'string' ? item.text :
          typeof item.summary === 'string' ? item.summary : '' };
    }
    if (type === 'compaction') {
      return { itemId: id, kind: type, label: '压缩上下文',
        text: optional(item.summary) + (typeof item.afterTokenCount === 'number' ? '\n' + String(item.afterTokenCount) + ' tokens' : '') };
    }
    if (type === 'handoff') return { itemId: id, kind: type, label: '上下文交接', text: optional(item.summary) };
    if (type === 'checkpoint') {
      return { itemId: id, kind: type, label: '检查点',
        text: objects(item.files || []).map((value: Object) => optional(record(value).path)).join('\n') };
    }
    if (type === 'notification') return { itemId: id, kind: type, label: '通知', text: optional(item.summary) || optional(item.text) };
    const title = optional(item.title);
    return { itemId: id, kind: type, label: type + (title ? ' · ' + title : '') + (status ? ' · ' + status : ''),
      text: optional(item.input) + (optional(item.output) ? '\n' + optional(item.output) : '') };
  });
}

export function appendOutput(previous: string, kind: string, textValue: string, truncated: boolean): string {
  const base = kind === 'replace' ? '' : previous;
  const next = base + textValue;
  if (next.length <= 200000) return next;
  return (truncated ? '' : '…') + next.slice(next.length - 200000);
}

export interface ActivitySummary {
  icon: 'cmd' | 'file' | 'info';
  title: string;
  badge: string;
  badgeTone: 'success' | 'danger' | 'neutral';
  additions: string;
  deletions: string;
}

function firstLine(value: string): string {
  for (const raw of value.split('\n')) {
    const trimmed = raw.replace(/\s+/g, ' ').trim();
    if (trimmed) return trimmed;
  }
  return '';
}

function statusBadge(label: string, inProgressText: string): { badge: string; tone: 'success' | 'danger' | 'neutral' } {
  if (/\bcompleted\b/i.test(label)) return { badge: '完成', tone: 'success' };
  if (/\binProgress\b/i.test(label)) return { badge: inProgressText, tone: 'neutral' };
  if (/\bfailed\b/i.test(label)) return { badge: '失败', tone: 'danger' };
  return { badge: '', tone: 'neutral' };
}

export function activitySummary(line: ActivityLine): ActivitySummary {
  if (line.kind === 'command_execution') {
    const exitMatch = /exit\s+(\d+)/.exec(line.label);
    const title = firstLine(line.text) || '命令';
    if (exitMatch) {
      const code = exitMatch[1];
      return { icon: 'cmd', title, badge: 'exit ' + code, badgeTone: code === '0' ? 'success' : 'danger', additions: '', deletions: '' };
    }
    const status = statusBadge(line.label, '运行中');
    return { icon: 'cmd', title, badge: status.badge, badgeTone: status.tone, additions: '', deletions: '' };
  }
  if (line.kind === 'file_change') {
    const match = /^(.*?)\s*·\s*(\+\d+)\s*([−-]\d+)$/.exec(line.label);
    if (match) {
      return { icon: 'file', title: match[1].trim() || '文件变更', badge: '', badgeTone: 'neutral', additions: match[2], deletions: match[3] };
    }
    return { icon: 'file', title: line.label || '文件变更', badge: '', badgeTone: 'neutral', additions: '', deletions: '' };
  }
  if (line.kind === 'file_search') {
    const pattern = firstLine(line.text);
    const status = statusBadge(line.label, '进行中');
    return { icon: 'file', title: pattern ? '搜索 ' + pattern : '文件搜索', badge: status.badge, badgeTone: status.tone, additions: '', deletions: '' };
  }
  if (line.kind === 'reasoning') {
    const status = statusBadge(line.label, '思考中');
    return { icon: 'info', title: '思考过程', badge: status.badge, badgeTone: status.tone, additions: '', deletions: '' };
  }
  if (line.kind === 'checkpoint') {
    return { icon: 'info', title: '检查点', badge: '', badgeTone: 'neutral', additions: '', deletions: '' };
  }
  if (line.kind === 'error') {
    return { icon: 'info', title: line.label || '错误', badge: '失败', badgeTone: 'danger', additions: '', deletions: '' };
  }
  if (line.kind === 'dynamic_tool') {
    const status = statusBadge(line.label, '进行中');
    let title = line.label.replace(/^dynamic_tool\s*·\s*/, '')
      .replace(/\s*·\s*(completed|failed|inProgress|running)\s*$/i, '').trim();
    if (title.startsWith('Read ')) {
      const rawPath = title.slice(5).trim().replace(/\\/g, '/');
      const slash = rawPath.lastIndexOf('/');
      const base = slash >= 0 ? rawPath.slice(slash + 1) : rawPath;
      return { icon: 'file', title: '读取 ' + (base || rawPath), badge: status.badge, badgeTone: status.tone, additions: '', deletions: '' };
    }
    if (title.startsWith('Run ')) {
      return { icon: 'cmd', title: '执行 ' + title.slice(4).trim(), badge: status.badge, badgeTone: status.tone, additions: '', deletions: '' };
    }
    return { icon: 'info', title: title || '工具调用', badge: status.badge, badgeTone: status.tone, additions: '', deletions: '' };
  }
  return { icon: 'info', title: line.label || line.kind, badge: '', badgeTone: 'neutral', additions: '', deletions: '' };
}

export function isPlainUserText(value: string): boolean {
  if (!value) return true;
  if (/[`*_\[<|]|\$\$|https?:\/\//i.test(value)) return false;
  for (const line of value.split('\n')) {
    const trimmed = line.trimStart();
    if (/^(?:#{1,6}\s|>\s?|[-*+]\s|\d+\.\s|-{3,}\s*$|={3,}\s*$)/.test(trimmed)) return false;
  }
  return true;
}

export interface CheckpointBadge {
  checkpointId: string;
  runId: string;
  fileCount: number;
  additions: number;
  deletions: number;
  additionsText: string;
  deletionsText: string;
  filePaths: string[];
  label: string;
  diffLabel: string;
  accessibleLabel: string;
}

export interface DerivedCheckpoints {
  byRun: Record<string, CheckpointBadge>;
  byAssistantMessage: Record<string, CheckpointBadge>;
  byItemId: Record<string, CheckpointBadge>;
}

export interface RunMeta {
  runId: string;
  status: string;
  durationMs: number;
  headerLabel: string;
  interrupted: boolean;
  running: boolean;
}

export interface WorkSummary {
  totalSteps: number;
  commands: number;
  files: number;
  searches: number;
  reasoning: number;
  failures: number;
  additions: number;
  deletions: number;
  running: boolean;
  label: string;
  failureLabel: string;
}

export interface TurnWorkGroup {
  groupId: string;
  runId: string;
  items: Record<string, Object>[];
  prominent: Record<string, Object>[];
  checkpoint?: CheckpointBadge;
  runMeta?: RunMeta;
  summary: WorkSummary;
  defaultExpanded: boolean;
  revision: string;
}

export interface MessageWorkMap {
  before: Record<string, TurnWorkGroup>;
  afterUser: Record<string, TurnWorkGroup>;
  afterAssistant: Record<string, TurnWorkGroup>;
  tail?: TurnWorkGroup;
  hasVisible: boolean;
  revision: string;
}

export interface ColoredDiffLine {
  text: string;
  tone: 'add' | 'del' | 'hunk' | 'plain';
}

export function emptyWorkMap(): MessageWorkMap {
  return { before: {}, afterUser: {}, afterAssistant: {}, hasVisible: false, revision: '' };
}

function failureCode(item: Record<string, Object>): string {
  if (item.failure === undefined || item.failure === null) return '';
  try {
    return optional(record(item.failure).code);
  } catch (_) {
    return '';
  }
}

export function isHiddenWorkItem(item: Record<string, Object>): boolean {
  const type = text(item.type);
  if ([
    'assistant_message', 'user_message', 'link_request', 'secret_request',
    'user_input_request', 'approval_request', 'todo_list', 'run_interrupt_request', 'checkpoint'
  ].includes(type)) {
    return true;
  }
  const status = optional(item.status);
  if (type === 'command_execution' && optional(item.input).trim() === 'Preparing workspace') {
    if (item.deferredWork === true) return false;
    if (status === 'failed' || status === 'inProgress') return false;
    if (typeof item.exitCode === 'number' && item.exitCode !== 0) return false;
    return true;
  }
  if (type === 'error' && status === 'cancelled' && failureCode(item) === 'workspace_preparation_failed') {
    return true;
  }
  return false;
}

export function isProminentWorkItem(item: Record<string, Object>): boolean {
  if (isHiddenWorkItem(item)) return false;
  const type = text(item.type);
  return type === 'error' || type === 'run_interrupt_result';
}

export function visibleWorkItems(items: Record<string, Object>[]): Record<string, Object>[] {
  return items.filter((item: Record<string, Object>) => !isHiddenWorkItem(item));
}

function formatDiffText(additions: number, deletions: number): string {
  const parts: string[] = [];
  if (additions > 0) parts.push('+' + additions);
  if (deletions > 0) parts.push('−' + deletions);
  return parts.join(' ');
}

function makeCheckpointBadge(checkpointId: string, runId: string, fileCount: number,
  additions: number, deletions: number, filePaths: string[]): CheckpointBadge {
  const additionsText = additions > 0 ? '+' + additions : '';
  const deletionsText = deletions > 0 ? '−' + deletions : '';
  const diffLabel = formatDiffText(additions, deletions);
  const label = fileCount + ' 文件';
  const accessibleLabel = '查看变更，' + (diffLabel ? diffLabel + '，' : '') + fileCount + ' 个文件';
  return {
    checkpointId,
    runId,
    fileCount,
    additions,
    deletions,
    additionsText,
    deletionsText,
    filePaths,
    label,
    diffLabel,
    accessibleLabel
  };
}

export function deriveCheckpointBadges(checkpoints: Record<string, Object>[],
  items: Record<string, Object>[], messages: ChatMessage[]): DerivedCheckpoints {
  const lastAssistantByRun: Record<string, string> = {};
  for (const msg of messages) {
    if (msg.role === 'assistant' && msg.runId) {
      lastAssistantByRun[msg.runId] = msg.id;
    }
  }
  const byRun: Record<string, CheckpointBadge> = {};
  const byAssistantMessage: Record<string, CheckpointBadge> = {};
  const byItemId: Record<string, CheckpointBadge> = {};

  for (const cp of checkpoints) {
    if (text(cp.status) !== 'ready') continue;
    const runId = optional(cp.runId);
    const fileRows = cp.files !== undefined ? objects(cp.files).map(record) : [];
    let count = fileRows.length;
    let additions = 0;
    let deletions = 0;
    const filePaths: string[] = [];
    for (const file of fileRows) {
      const p = optional(file.path).trim();
      if (p) filePaths.push(p);
      if (typeof file.additions === 'number') additions += Number(file.additions);
      if (typeof file.deletions === 'number') deletions += Number(file.deletions);
    }
    if (cp.filesTotal !== undefined && cp.filesTotal !== null) {
      try {
        const totals = record(cp.filesTotal);
        if (typeof totals.count === 'number') count = Number(totals.count);
        if (typeof totals.additions === 'number') additions = Number(totals.additions);
        if (typeof totals.deletions === 'number') deletions = Number(totals.deletions);
      } catch (_) {}
    }
    if (count <= 0) continue;
    const cpId = text(cp.id) || ('cp:' + runId + ':' + count);
    const badge = makeCheckpointBadge(cpId, runId, count, additions, deletions, filePaths);
    if (runId) {
      byRun[runId] = badge;
      const assistantId = lastAssistantByRun[runId];
      if (assistantId) byAssistantMessage[assistantId] = badge;
    }
  }

  for (const item of items) {
    if (text(item.type) !== 'checkpoint') continue;
    const runId = optional(item.runId);
    if (runId && byRun[runId]) continue;
    const fileRows = item.files !== undefined ? objects(item.files).map(record) : [];
    const filePaths: string[] = [];
    let additions = 0;
    let deletions = 0;
    for (const file of fileRows) {
      const p = optional(file.path).trim();
      if (p) filePaths.push(p);
      if (typeof file.additions === 'number') additions += Number(file.additions);
      if (typeof file.deletions === 'number') deletions += Number(file.deletions);
    }
    if (filePaths.length === 0) continue;
    const itemId = text(item.id) || ('cp-item:' + runId + ':' + filePaths.length);
    const badge = makeCheckpointBadge(itemId, runId, filePaths.length, additions, deletions, filePaths);
    if (runId) {
      byRun[runId] = badge;
      const assistantId = lastAssistantByRun[runId];
      if (assistantId && !byAssistantMessage[assistantId]) byAssistantMessage[assistantId] = badge;
    } else {
      byItemId[itemId] = badge;
    }
  }

  return { byRun, byAssistantMessage, byItemId };
}

export function formatWorkDuration(ms: number): string {
  if (!Number.isFinite(ms) || ms <= 0) return '';
  if (ms < 1000) return '<1 秒';
  const totalSeconds = Math.round(ms / 1000);
  if (totalSeconds < 60) return totalSeconds + ' 秒';
  if (totalSeconds < 3600) {
    const mins = Math.floor(totalSeconds / 60);
    const secs = totalSeconds % 60;
    return secs > 0 ? mins + ' 分 ' + secs + ' 秒' : mins + ' 分';
  }
  const hours = Math.floor(totalSeconds / 3600);
  const mins = Math.floor((totalSeconds % 3600) / 60);
  return mins > 0 ? hours + ' 小时 ' + mins + ' 分' : hours + ' 小时';
}

export function buildRunMeta(run: Record<string, Object> | undefined, stepCount: number): RunMeta | undefined {
  if (!run) return undefined;
  const runId = text(run.id);
  const status = optional(run.status);
  const startIso = optional(run.startedAt) || optional(run.requestedAt);
  const endIso = optional(run.completedAt);
  let durationMs = 0;
  if (startIso && endIso) {
    const startMs = Date.parse(startIso);
    const endMs = Date.parse(endIso);
    if (Number.isFinite(startMs) && Number.isFinite(endMs) && endMs >= startMs) {
      durationMs = endMs - startMs;
    }
  }
  const durationText = formatWorkDuration(durationMs);
  const interrupted = status === 'interrupted' || status === 'cancelled';
  const running = status === 'preparing' || status === 'starting' || status === 'running' || status === 'waiting';
  let headerLabel = '';
  if (interrupted) {
    headerLabel = durationText ? '你在 ' + durationText + '后停止了' : '已停止运行';
  } else if (running) {
    headerLabel = stepCount > 0 ? '正在执行 · ' + stepCount + ' 步' : '正在执行';
  } else if (durationText) {
    headerLabel = '已工作 ' + durationText + (stepCount > 0 ? ' · ' + stepCount + ' 步' : '');
  } else if (stepCount > 0) {
    headerLabel = stepCount + ' 步执行过程';
  }
  return { runId, status, durationMs, headerLabel, interrupted, running };
}

function parseIntSafe(value: string): number {
  const digits = value.replace(/[^\d]/g, '');
  if (!digits) return 0;
  const parsed = Number(digits);
  return Number.isFinite(parsed) ? parsed : 0;
}

export function summarizeWork(lines: ActivityLine[]): WorkSummary {
  let commands = 0;
  let files = 0;
  let searches = 0;
  let reasoning = 0;
  let failures = 0;
  let additions = 0;
  let deletions = 0;
  let running = false;

  for (const line of lines) {
    const summary = activitySummary(line);
    if (line.kind === 'command_execution') {
      commands += 1;
      if (summary.badgeTone === 'danger') failures += 1;
      if (summary.badge === '运行中') running = true;
    } else if (line.kind === 'file_change') {
      files += 1;
      additions += parseIntSafe(summary.additions);
      deletions += parseIntSafe(summary.deletions);
    } else if (line.kind === 'file_search' || line.kind === 'web_search') {
      searches += 1;
      if (summary.badgeTone === 'danger') failures += 1;
      if (summary.badge === '进行中') running = true;
    } else if (line.kind === 'reasoning') {
      reasoning += 1;
      if (summary.badge === '思考中') running = true;
    } else {
      if (summary.badgeTone === 'danger') failures += 1;
      if (summary.badge === '进行中' || summary.badge === '运行中') running = true;
    }
  }

  const parts: string[] = [];
  if (commands > 0) parts.push('运行 ' + commands + ' 条命令');
  if (files > 0) parts.push('修改 ' + files + ' 个文件');
  if (searches > 0) parts.push('搜索 ' + searches + ' 次');
  if (reasoning > 0 && parts.length === 0) parts.push('思考 ' + reasoning + ' 步');
  if (parts.length === 0 && lines.length > 0) parts.push(lines.length + ' 项执行步骤');

  return {
    totalSteps: lines.length,
    commands,
    files,
    searches,
    reasoning,
    failures,
    additions,
    deletions,
    running,
    label: parts.join('，'),
    failureLabel: failures > 0 ? failures + ' 失败' : ''
  };
}

function buildWorkGroup(groupId: string, runId: string, workItems: Record<string, Object>[],
  prominentItems: Record<string, Object>[], checkpoint: CheckpointBadge | undefined,
  runRecord: Record<string, Object> | undefined): TurnWorkGroup | undefined {
  const lines = activityLines(workItems);
  const summary = summarizeWork(lines);
  const runMeta = buildRunMeta(runRecord, lines.length + prominentItems.length);
  const hasVisible = lines.length > 0 || prominentItems.length > 0 || checkpoint !== undefined ||
    (runMeta !== undefined && runMeta.interrupted);
  if (!hasVisible) return undefined;

  const defaultExpanded = (runMeta !== undefined && (runMeta.running || runMeta.interrupted)) || summary.running;
  const revParts: string[] = [];
  for (const item of workItems) {
    revParts.push(text(item.id) + ':' + optional(item.status) + ':' + String(item.exitCode ?? ''));
  }
  for (const item of prominentItems) {
    revParts.push(text(item.id) + ':' + optional(item.status));
  }
  if (checkpoint) revParts.push('cp:' + checkpoint.checkpointId + ':' + checkpoint.fileCount + ':' + checkpoint.diffLabel);
  if (runMeta) revParts.push('run:' + runMeta.status + ':' + runMeta.headerLabel);
  const revision = revParts.join('|');

  return {
    groupId,
    runId,
    items: workItems.slice(),
    prominent: prominentItems.slice(),
    checkpoint,
    runMeta,
    summary,
    defaultExpanded,
    revision
  };
}

export function groupWorkByMessage(items: Record<string, Object>[],
  runs: Record<string, Object>[], checkpoints: Record<string, Object>[],
  messages: ChatMessage[]): MessageWorkMap {
  const runById: Record<string, Record<string, Object>> = {};
  for (const run of runs) {
    const id = text(run.id);
    if (id) runById[id] = run;
  }

  const derived = deriveCheckpointBadges(checkpoints, items, messages);
  const before: Record<string, TurnWorkGroup> = {};
  const afterUser: Record<string, TurnWorkGroup> = {};
  const afterAssistant: Record<string, TurnWorkGroup> = {};
  const attachedCheckpointIds: Record<string, boolean> = {};

  let pendingWork: Record<string, Object>[] = [];
  let pendingProminent: Record<string, Object>[] = [];
  let pendingCheckpoint: CheckpointBadge | undefined = undefined;
  let pendingRunId: string = '';
  let lastUserMessageId: string = '';
  let lastAssistantMessageId: string = '';
  let seenAssistantSinceLastUser: boolean = false;
  let groupCounter: number = 0;

  let tailGroup: TurnWorkGroup | undefined = undefined;

  const flushPending = (target: 'afterUser' | 'afterAssistant' | 'tail'): void => {
    const runRecord = pendingRunId ? runById[pendingRunId] : undefined;
    const firstItemId = pendingWork.length ? text(pendingWork[0].id) :
      pendingProminent.length ? text(pendingProminent[0].id) : '';
    let gId = '';
    if (target === 'afterUser' && lastUserMessageId) {
      gId = (pendingRunId || 'user') + ':u:' + lastUserMessageId + ':' + String(groupCounter);
    } else if (target === 'afterAssistant' && lastAssistantMessageId) {
      gId = (pendingRunId || 'asst') + ':a:' + lastAssistantMessageId + ':' + String(groupCounter);
    } else {
      gId = pendingRunId || (lastUserMessageId ? 'user:' + lastUserMessageId : '') ||
        (firstItemId ? 'item:' + firstItemId : 'tail:' + String(groupCounter));
    }
    const cp = pendingCheckpoint || (pendingRunId && !derived.byAssistantMessage[pendingRunId] ? derived.byRun[pendingRunId] : undefined);
    const group = buildWorkGroup(gId, pendingRunId, pendingWork, pendingProminent, cp, runRecord);
    if (group) {
      groupCounter += 1;
      if (cp) attachedCheckpointIds[cp.checkpointId] = true;
      if (target === 'afterUser' && lastUserMessageId) {
        afterUser[lastUserMessageId] = group;
      } else if (target === 'afterAssistant' && lastAssistantMessageId) {
        afterAssistant[lastAssistantMessageId] = group;
      } else if (target === 'tail') {
        tailGroup = group;
      }
    }
    pendingWork = [];
    pendingProminent = [];
    pendingCheckpoint = undefined;
    pendingRunId = '';
  };

  for (const item of items) {
    const type = text(item.type);
    const itemRunId = optional(item.runId);
    if (type === 'user_message') {
      if (pendingWork.length > 0 || pendingProminent.length > 0 || pendingCheckpoint !== undefined) {
        if (!seenAssistantSinceLastUser && lastUserMessageId) {
          flushPending('afterUser');
        } else if (seenAssistantSinceLastUser && lastAssistantMessageId) {
          flushPending('afterAssistant');
        } else {
          pendingWork = [];
          pendingProminent = [];
          pendingCheckpoint = undefined;
          pendingRunId = '';
        }
      } else {
        pendingRunId = '';
      }
      lastUserMessageId = optional(item.messageId) || text(item.id);
      lastAssistantMessageId = '';
      seenAssistantSinceLastUser = false;
      continue;
    }
    if (type === 'assistant_message') {
      const msgId = optional(item.messageId) || text(item.id);
      const effectiveRunId = itemRunId || pendingRunId;
      const runRecord = effectiveRunId ? runById[effectiveRunId] : undefined;
      let cp: CheckpointBadge | undefined = msgId ? derived.byAssistantMessage[msgId] : undefined;
      if (!cp && effectiveRunId) cp = derived.byRun[effectiveRunId];
      if (!cp) cp = pendingCheckpoint;
      if (cp && attachedCheckpointIds[cp.checkpointId]) cp = undefined;

      const gId = (effectiveRunId ? effectiveRunId + ':' : 'msg:') + (msgId || String(groupCounter));
      const group = buildWorkGroup(gId, effectiveRunId, pendingWork, pendingProminent, cp, runRecord);
      if (group && msgId) {
        before[msgId] = group;
        groupCounter += 1;
        if (cp) attachedCheckpointIds[cp.checkpointId] = true;
      }
      pendingWork = [];
      pendingProminent = [];
      pendingCheckpoint = undefined;
      pendingRunId = '';
      lastAssistantMessageId = msgId;
      seenAssistantSinceLastUser = true;
      continue;
    }
    if (type === 'checkpoint') {
      if (!itemRunId) {
        const cpFromItem = derived.byItemId[text(item.id)];
        if (cpFromItem) pendingCheckpoint = cpFromItem;
      }
      continue;
    }
    if (isHiddenWorkItem(item)) continue;
    if (itemRunId && !pendingRunId) pendingRunId = itemRunId;
    if (isProminentWorkItem(item)) pendingProminent.push(item);
    else pendingWork.push(item);
  }

  if (pendingWork.length > 0 || pendingProminent.length > 0 || pendingCheckpoint !== undefined) {
    flushPending('tail');
  }

  // Ensure any ready checkpoint with changed files mapped to an assistant message without tools still surfaces.
  for (const msg of messages) {
    if (msg.role !== 'assistant' || before[msg.id]) continue;
    const cp = derived.byAssistantMessage[msg.id];
    if (!cp || attachedCheckpointIds[cp.checkpointId]) continue;
    const runRecord = msg.runId ? runById[msg.runId] : (cp.runId ? runById[cp.runId] : undefined);
    const effectiveRunId = msg.runId || cp.runId;
    const group = buildWorkGroup(effectiveRunId || ('msg:' + msg.id), effectiveRunId, [], [], cp, runRecord);
    if (group) {
      before[msg.id] = group;
      attachedCheckpointIds[cp.checkpointId] = true;
    }
  }

  const revisions: string[] = [];
  for (const key of Object.keys(before)) revisions.push('B:' + key + '=' + before[key].revision);
  for (const key of Object.keys(afterUser)) revisions.push('U:' + key + '=' + afterUser[key].revision);
  for (const key of Object.keys(afterAssistant)) revisions.push('A:' + key + '=' + afterAssistant[key].revision);
  if (tailGroup) revisions.push('T:' + tailGroup.revision);

  const hasVisible = Object.keys(before).length > 0 || Object.keys(afterUser).length > 0 ||
    Object.keys(afterAssistant).length > 0 || tailGroup !== undefined;
  return {
    before,
    afterUser,
    afterAssistant,
    tail: tailGroup,
    hasVisible,
    revision: revisions.join(';;')
  };
}

export function parseDiffPreviewLines(value: string): ColoredDiffLine[] {
  if (!value) return [];
  const rawLines = value.split('\n');
  const rows: ColoredDiffLine[] = [];
  for (const line of rawLines) {
    if (line.startsWith('@@')) {
      rows.push({ text: line, tone: 'hunk' });
    } else if (line.startsWith('+++') || line.startsWith('---')) {
      rows.push({ text: line, tone: 'plain' });
    } else if (line.startsWith('+')) {
      rows.push({ text: line, tone: 'add' });
    } else if (line.startsWith('-')) {
      rows.push({ text: line, tone: 'del' });
    } else {
      rows.push({ text: line, tone: 'plain' });
    }
  }
  return rows;
}

