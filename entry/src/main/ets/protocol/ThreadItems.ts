import { record, text, objects } from './Wire';

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

