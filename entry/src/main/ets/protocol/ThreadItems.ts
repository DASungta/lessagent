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

