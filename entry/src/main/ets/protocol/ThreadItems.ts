import { ChatMessage, compactArray, compactObjects, record, text } from './Wire';
import { HtmlRenderEntry, htmlRenderFromToolItem } from './HtmlRender';

export interface ActivityLine { label: string; text: string; kind: string; itemId: string; status?: string; toolName?: string; }

function optional(value: Object | undefined): string { return typeof value === 'string' ? value : ''; }

export const USER_MESSAGE_FOLDED_HEIGHT = 176;

// Fold only when opening at least doubles what is on screen, matching upstream CollapsibleUserMessageBody.
export function isTallEnoughToFold(height: number): boolean {
  return Number.isFinite(height) && height >= USER_MESSAGE_FOLDED_HEIGHT * 2;
}

export function toggleExpandedUserMessage(current: Record<string, boolean>, messageId: string): Record<string, boolean> {
  const next: Record<string, boolean> = {};
  for (const key of Object.keys(current)) next[key] = current[key];
  next[messageId] = next[messageId] !== true;
  return next;
}

export function isActiveItemStatus(status: string): boolean {
  const normalized = status.trim().toLowerCase();
  return normalized === 'inprogress' || normalized === 'running' ||
    normalized === 'pending' || normalized === 'waiting';
}

export function isActiveRunStatus(status: string): boolean {
  const normalized = status.trim().toLowerCase();
  return normalized === 'preparing' || normalized === 'starting' ||
    normalized === 'running' || normalized === 'waiting';
}

export function isSettledRunStatus(status: string): boolean {
  const normalized = status.trim().toLowerCase();
  return normalized === 'completed' || normalized === 'failed' ||
    normalized === 'interrupted' || normalized === 'cancelled' ||
    normalized === 'rolled_back';
}

export function isActivityInProgress(line: ActivityLine): boolean {
  const raw = (line.status || '').trim();
  if (raw) return isActiveItemStatus(raw);
  return /\b(inProgress|running|pending|waiting)\b/i.test(line.label);
}

export function activityLines(items: Record<string, Object>[]): ActivityLine[] {
  const result: ActivityLine[] = [];
  for (const item of items) {
    const type = optional(item.type);
    const id = optional(item.id);
    if (!type || !id) continue;
    if (['assistant_message', 'user_message', 'link_request', 'secret_request',
      'user_input_request', 'approval_request'].includes(type)) continue;
    if (type === 'dynamic_tool' && htmlRenderFromToolItem(item) !== undefined) continue;
    const status = optional(item.status);
    if (type === 'command_execution') {
      const exit = typeof item.exitCode === 'number' ? ' · exit ' + item.exitCode : '';
      result.push({ itemId: id, kind: type, status, label: '命令 · ' + status + exit,
        text: optional(item.input) + (optional(item.output) ? '\n' + optional(item.output) :
          item.outputOmitted === true ? '\n输出未随快照提供，展开后读取完整输出' : '') });
      continue;
    }
    if (type === 'file_change') {
      result.push({ itemId: id, kind: type, status, label: optional(item.fileName) + ' · +' +
        String(typeof item.additions === 'number' ? item.additions : 0) + ' −' +
        String(typeof item.deletions === 'number' ? item.deletions : 0),
        text: optional(item.diffStr) || (optional(item.oldStr) + '\n→\n' + optional(item.newStr)) });
      continue;
    }
    if (type === 'file_search') {
      const fileNames = compactObjects(item.results).map((row: Record<string, Object>) => optional(row.fileName))
        .filter((name: string) => name.length > 0);
      result.push({ itemId: id, kind: type, status, label: '文件搜索 · ' + status,
        text: optional(item.pattern) + '\n' + fileNames.join('\n') });
      continue;
    }
    if (type === 'web_search') {
      const patterns = compactArray(item.patterns, (value: Object) => text(value));
      const results = compactObjects(item.results).map((row: Record<string, Object>) =>
        (optional(row.title) || optional(row.url)) + '\n' + optional(row.url) + '\n' + optional(row.snippet));
      result.push({ itemId: id, kind: type, status, label: '网络搜索 · ' + status,
        text: patterns.join(', ') + '\n' + results.join('\n') });
      continue;
    }
    if (type === 'todo_list') {
      const steps = compactObjects(item.steps).map((step: Record<string, Object>) =>
        '[' + optional(step.status) + '] ' + optional(step.text));
      result.push({ itemId: id, kind: type, status, label: '计划步骤 · ' + status,
        text: steps.join('\n') });
      continue;
    }
    if (type === 'system_notice') {
      result.push({ itemId: id, kind: type, status, label: '系统提示', text: optional(item.message) });
      continue;
    }
    if (type === 'error') {
      const failure: Record<string, Object> =
        item.failure !== undefined && item.failure !== null && typeof item.failure === 'object' && !Array.isArray(item.failure)
          ? item.failure as Record<string, Object> : {};
      result.push({ itemId: id, kind: type, status, label: '错误 · ' + optional(failure.class),
        text: optional(failure.message) + (typeof failure.code === 'string' ? '\n' + failure.code : '') });
      continue;
    }
    if (type === 'run_interrupt_request' || type === 'run_interrupt_result') {
      result.push({ itemId: id, kind: type, status, label: '停止运行', text: optional(item.message) });
      continue;
    }
    if (type === 'reasoning') {
      result.push({ itemId: id, kind: type, status, label: '思考过程' + (status ? ' · ' + status : ''),
        text: typeof item.text === 'string' ? item.text :
          typeof item.summary === 'string' ? item.summary : '' });
      continue;
    }
    if (type === 'compaction') {
      result.push({ itemId: id, kind: type, status, label: '压缩上下文',
        text: optional(item.summary) + (typeof item.afterTokenCount === 'number' ? '\n' + String(item.afterTokenCount) + ' tokens' : '') });
      continue;
    }
    if (type === 'handoff') {
      result.push({ itemId: id, kind: type, status, label: '上下文交接', text: optional(item.summary) });
      continue;
    }
    if (type === 'checkpoint') {
      const paths = compactObjects(item.files).map((row: Record<string, Object>) => optional(row.path));
      result.push({ itemId: id, kind: type, status, label: '检查点', text: paths.join('\n') });
      continue;
    }
    if (type === 'notification') {
      result.push({ itemId: id, kind: type, status, label: '通知', text: optional(item.summary) || optional(item.text) });
      continue;
    }
    if (type === 'dynamic_tool') {
      const rawToolName = optional(item.toolName).trim();
      const toolTitle = optional(item.title).trim() || rawToolName;
      const line: ActivityLine = {
        itemId: id,
        kind: type,
        status,
        label: type + (toolTitle ? ' · ' + toolTitle : '') + (status ? ' · ' + status : ''),
        text: optional(item.input) + (optional(item.output) ? '\n' + optional(item.output) : '')
      };
      if (rawToolName) line.toolName = rawToolName;
      result.push(line);
      continue;
    }
    const title = optional(item.title);
    const rawToolName = optional(item.toolName).trim();
    const fallbackLine: ActivityLine = {
      itemId: id,
      kind: type,
      status,
      label: type + (title ? ' · ' + title : '') + (status ? ' · ' + status : ''),
      text: optional(item.input) + (optional(item.output) ? '\n' + optional(item.output) : '')
    };
    if (rawToolName) fallbackLine.toolName = rawToolName;
    result.push(fallbackLine);
  }
  return result;
}

export function appendOutput(previous: string, kind: string, textValue: string, truncated: boolean): string {
  const base = kind === 'replace' ? '' : previous;
  const next = base + textValue;
  if (next.length <= 200000) return next;
  return (truncated ? '' : '…') + next.slice(next.length - 200000);
}

export type ActivityIcon = 'cmd' | 'file' | 'eye' | 'info' | 't3' | 'thinking' | 'browser' | 'pr';

export interface ActivitySummary {
  icon: ActivityIcon;
  title: string;
  badge: string;
  badgeTone: 'success' | 'danger' | 'neutral';
  additions: string;
  deletions: string;
}

interface T3McpToolSpec {
  completedLabel: string;
  runningLabel: string;
  icon: ActivityIcon;
}

function t3Tool(runningLabel: string, completedLabel: string, icon: ActivityIcon = 't3'): T3McpToolSpec {
  return { completedLabel, runningLabel, icon };
}

const T3_MCP_SERVER_ALIASES: string[] = ['t3-code', 't3_code', 't3code', 't3-code-direct', 't3_code_direct'];

const T3_MCP_TOOLS: Record<string, T3McpToolSpec> = {
  link_pull_request: t3Tool('正在关联 PR', '已关联 PR', 'pr'),
  link_pull_requests: t3Tool('正在关联多个 PR', '已关联多个 PR', 'pr'),
  unlink_pull_request: t3Tool('正在取消关联 PR', '已取消关联 PR', 'pr'),
  unlink_pull_requests: t3Tool('正在按状态取消关联 PR', '已按状态取消关联 PR', 'pr'),
  list_thread_pull_requests: t3Tool('正在查看关联的 PR', '已查看关联的 PR', 'pr'),
  watch_pull_request: t3Tool('正在监控 PR', '正在监控 PR', 'pr'),
  unwatch_pull_request: t3Tool('正在停止监控 PR', '已停止监控 PR', 'pr'),
  write_pull_request_guides: t3Tool('正在生成审查指南', '已开始生成审查指南', 'pr'),
  read_pull_request_guide: t3Tool('正在读取审查指南', '已读取审查指南', 'pr'),
  list_issues: t3Tool('正在列出议题', '已列出议题'),
  read_issue: t3Tool('正在读取议题', '已读取议题'),
  create_issue: t3Tool('正在创建议题', '已创建议题'),
  comment_on_issue: t3Tool('正在评论议题', '已评论议题'),
  set_issue_state: t3Tool('正在修改议题状态', '已修改议题状态'),
  link_issue: t3Tool('正在关联议题', '已关联议题'),
  unlink_issue: t3Tool('正在取消关联议题', '已取消关联议题'),
  list_thread_issues: t3Tool('正在查看关联的议题', '已查看关联的议题'),
  pull_request_read: t3Tool('正在读取 PR', '已读取 PR', 'pr'),
  pull_request_list: t3Tool('正在列出 PR', '已列出 PR', 'pr'),
  pull_request_create: t3Tool('正在创建 PR', '已创建 PR', 'pr'),
  pull_request_update: t3Tool('正在更新 PR', '已更新 PR', 'pr'),
  pull_request_respond: t3Tool('正在回复 PR 评审', '已回复 PR 评审', 'pr'),
  pull_request_review: t3Tool('正在提交 PR 评审', '已提交 PR 评审', 'pr'),
  ci_logs: t3Tool('正在读取 CI 日志', '已读取 CI 日志', 'pr'),
  ci_rerun: t3Tool('正在重跑 CI', '已重跑 CI', 'pr'),
  pull_request_merge: t3Tool('正在合并 PR', '已合并 PR', 'pr'),
  orchestrator_capabilities: t3Tool('正在获取编排能力', '已获取编排能力'),
  delegate_task: t3Tool('正在委派子任务', '已委派子任务'),
  task_status: t3Tool('正在获取子任务状态', '已获取子任务状态'),
  task_cancel: t3Tool('正在取消子任务', '已请求取消子任务'),
  schedule_task: t3Tool('正在创建定时任务', '已创建定时任务'),
  list_scheduled_tasks: t3Tool('正在列出定时任务', '已列出定时任务'),
  update_scheduled_task: t3Tool('正在更新定时任务', '已更新定时任务'),
  delete_scheduled_task: t3Tool('正在删除定时任务', '已请求删除定时任务'),
  run_scheduled_task_now: t3Tool('正在运行定时任务', '已触发定时任务'),
  request_secret: t3Tool('正在请求凭据', '已请求凭据'),
  create_threads: t3Tool('正在创建 T3 会话', '已创建 T3 会话'),
  t3_thread_start: t3Tool('正在启动 T3 会话', '已启动 T3 会话'),
  t3_thread_launch: t3Tool('正在启动项目会话', '已启动项目会话'),
  t3_thread_list: t3Tool('正在列出 T3 会话', '已列出 T3 会话'),
  t3_thread_read: t3Tool('正在读取会话', '已读取会话'),
  t3_thread_send: t3Tool('正在发送到会话', '已发送到会话'),
  t3_thread_wait: t3Tool('正在等待会话', '已等待会话'),
  t3_workflow_stop: t3Tool('正在停止工作流', '已请求停止工作流'),
  t3_background_wait: t3Tool('正在更新后台等待', '已更新后台等待'),
  t3_thread_interrupt: t3Tool('正在中断会话', '已请求中断会话'),
  t3_worktree_handoff: t3Tool('正在切换会话到工作树', '已切换会话到工作树'),
  t3_worktree_status: t3Tool('正在获取工作树状态', '已获取工作树状态'),
  t3_worktree_list: t3Tool('正在列出工作区分支', '已列出工作区分支'),
  preview_status: t3Tool('正在获取预览浏览器状态', '已获取预览浏览器状态', 'browser'),
  preview_open: t3Tool('正在打开预览页面', '已打开预览页面', 'browser'),
  preview_navigate: t3Tool('正在导航预览浏览器', '已导航预览浏览器', 'browser'),
  preview_dialog: t3Tool('正在处理预览弹窗', '已处理预览弹窗', 'browser'),
  preview_snapshot: t3Tool('正在抓取预览页面快照', '已抓取预览页面快照', 'browser'),
  preview_act: t3Tool('正在操作预览浏览器', '已操作预览浏览器', 'browser'),
  preview_click: t3Tool('正在点击预览页面', '已点击预览页面', 'browser'),
  preview_press: t3Tool('正在发送按键到预览浏览器', '已发送按键到预览浏览器', 'browser'),
  preview_type: t3Tool('正在在预览页面输入', '已在预览页面输入', 'browser'),
  preview_hover: t3Tool('正在悬停预览元素', '已悬停预览元素', 'browser'),
  preview_select: t3Tool('正在选择预览选项', '已选择预览选项', 'browser'),
  preview_drag: t3Tool('正在拖拽预览元素', '已拖拽预览元素', 'browser'),
  preview_upload: t3Tool('正在上传文件到预览浏览器', '已上传文件到预览浏览器', 'browser'),
  preview_scroll: t3Tool('正在滚动预览页面', '已滚动预览页面', 'browser'),
  preview_resize: t3Tool('正在调整预览窗口大小', '已调整预览窗口大小', 'browser'),
  preview_evaluate: t3Tool('正在预览页执行脚本', '已在预览页执行脚本', 'browser'),
  preview_wait_for: t3Tool('正在等待预览页面', '已等待预览页面', 'browser'),
  preview_set_appearance: t3Tool('正在设置预览外观', '已设置预览外观', 'browser'),
  preview_recording_start: t3Tool('正在开始录制预览浏览器', '已开始录制预览浏览器', 'browser'),
  preview_recording_stop: t3Tool('正在停止录制预览浏览器', '已停止录制预览浏览器', 'browser'),
  t3_preview_list: t3Tool('正在列出预览标签页', '已列出预览标签页', 'browser'),
  t3_preview_close: t3Tool('正在关闭预览标签页', '已关闭预览标签页', 'browser'),
  device_list: t3Tool('正在列出模拟器与设备', '已列出模拟器与设备', 't3'),
  device_open: t3Tool('正在打开设备面板', '已打开设备面板', 't3'),
  device_screenshot: t3Tool('正在截取设备画面', '已截取设备画面', 't3'),
  device_close: t3Tool('正在关闭设备', '已关闭设备', 't3'),
  t3_queue: t3Tool('正在管理排队消息', '已管理排队消息'),
  t3_pending_request: t3Tool('正在处理待答问题', '已处理待答问题'),
  t3_workflow: t3Tool('正在操作工作流', '已操作工作流'),
  t3_submit_output: t3Tool('正在提交结果', '已提交结果'),
  t3_queue_list: t3Tool('正在列出排队消息', '已列出排队消息'),
  t3_queue_read: t3Tool('正在读取排队消息', '已读取排队消息'),
  t3_queue_edit: t3Tool('正在编辑排队消息', '已编辑排队消息'),
  t3_queue_cancel: t3Tool('正在取消排队任务', '已请求取消排队任务'),
  t3_queue_reorder: t3Tool('正在调整排队顺序', '已调整排队顺序'),
  t3_queue_promote_to_steer: t3Tool('正在用排队消息引导运行', '已用排队消息引导运行'),
  t3_pending_request_list: t3Tool('正在列出待答问题', '已列出待答问题'),
  t3_pending_request_read: t3Tool('正在读取待答问题', '已读取待答问题'),
  t3_pending_request_respond: t3Tool('正在回答待答问题', '已回答待答问题'),
  t3_thread_configuration: t3Tool('正在读取会话配置', '已读取会话配置'),
  t3_thread_configure: t3Tool('正在调整会话模型设置', '已调整会话模型设置'),
  t3_thread_transfer: t3Tool('正在处理会话迁移', '已处理会话迁移'),
  t3_thread_fork: t3Tool('正在分支当前会话', '已请求分支当前会话'),
  t3_thread_merge_back: t3Tool('正在合并会话上下文', '已请求合并会话上下文'),
  t3_thread_search: t3Tool('正在搜索会话内容', '已搜索会话内容'),
  t3_thread_transfers: t3Tool('正在读取会话迁移记录', '已读取会话迁移记录'),
  t3_thread_organize: t3Tool('正在整理会话', '已整理会话'),
  t3_thread_update: t3Tool('正在更新会话信息', '已更新会话信息'),
  t3_environment_read: t3Tool('正在读取环境偏好', '已读取环境偏好'),
  t3_environment_links: t3Tool('正在列出关联的环境', '已列出关联的环境'),
  t3_environment_link: t3Tool('正在请求关联环境', '已请求关联环境'),
  t3_environment_unlink: t3Tool('正在移除关联环境', '已移除关联环境'),
  t3_environment_preferences_update: t3Tool('正在更新环境偏好', '已更新环境偏好'),
  t3_theme_read: t3Tool('正在读取主题', '已读取主题'),
  t3_theme_set: t3Tool('正在设置主题', '已设置主题'),
  t3_project_list: t3Tool('正在列出项目', '已列出项目'),
  t3_project_read: t3Tool('正在读取项目', '已读取项目'),
  t3_project_create: t3Tool('正在注册项目', '已注册项目'),
  t3_project_update: t3Tool('正在更新项目', '已更新项目'),
  t3_project_delete: t3Tool('正在删除项目', '已删除项目'),
  t3_project_clone: t3Tool('正在克隆仓库', '已克隆仓库'),
  t3_attachment_prepare_upload: t3Tool('正在准备上传附件', '已准备上传附件'),
  t3_attachment_discard: t3Tool('正在丢弃待发附件', '已丢弃待发附件'),
  t3_thread_send_attachments: t3Tool('正在发送附件', '已发送附件'),
  html_preview: t3Tool('正在预览 HTML 页面', '已预览 HTML 页面'),
  html_render: t3Tool('正在渲染 HTML 页面', '已渲染 HTML 页面'),
  send_to_user: t3Tool('正在发送消息', '已发送消息')
};

const READ_TOOL_NAMES: string[] = [
  'read', 'read_file', 'readfile', 'view_file', 'viewfile', 'view_file_outline',
  'view_code_item', 'read_resource', 'list_resources', 'list_dir', 'cat', 'open_file'
];

function isReadToolName(value: string): boolean {
  const normalized = (value || '').replace(/^default_api:/i, '').trim().toLowerCase();
  if (!normalized) return false;
  return READ_TOOL_NAMES.includes(normalized);
}

const T3_MCP_TOOL_KEYS: string[] = Object.keys(T3_MCP_TOOLS);

export function resolveT3McpToolId(value: string): string {
  const label = (value || '').replace(/^default_api:/i, '').replace(/\s+(?:complete|completed)\s*$/i, '').trim();
  if (!label) return '';
  const mcpMatch = /^mcp__(.+?)__(.+)$/i.exec(label);
  if (mcpMatch) {
    const server = mcpMatch[1].toLowerCase();
    const tool = mcpMatch[2];
    if (T3_MCP_SERVER_ALIASES.includes(server) && T3_MCP_TOOLS[tool] !== undefined) return tool;
    return '';
  }
  const nsMatch = /^(t3[-_]code[-_]direct|t3-code|t3_code|t3code)(?:[.:/]|\s*·\s*)(.+)$/i.exec(label);
  if (nsMatch) {
    const tool = nsMatch[2].trim();
    if (T3_MCP_TOOLS[tool] !== undefined) return tool;
    return '';
  }
  const prefixed = /^(?:mcp[-_]{1,2})?t3[-_ ]?code(?:__|[-_.:/ ])(.+)$/i.exec(label);
  const candidate = prefixed ? prefixed[1].trim() : label;
  if (T3_MCP_TOOLS[candidate] !== undefined) return candidate;
  if (/^t3-code-/i.test(label)) {
    let longest = '';
    for (const key of T3_MCP_TOOL_KEYS) {
      if (label.endsWith('_' + key) && key.length > longest.length) longest = key;
    }
    if (longest) return longest;
  }
  return '';
}

function isRawT3ToolLabel(value: string): boolean {
  const trimmed = (value || '').trim();
  if (!trimmed) return true;
  if (resolveT3McpToolId(trimmed) !== '') return true;
  return /^(?:default_api:)?(?:mcp[-_]{1,2})?t3[-_ ]?code(?:__|[-_.:/ ]|\s*·\s*)/i.test(trimmed);
}

function firstLine(value: string): string {
  for (const raw of value.split('\n')) {
    const trimmed = raw.replace(/\s+/g, ' ').trim();
    if (trimmed) return trimmed;
  }
  return '';
}

function reasoningPreviewLine(value: string): string {
  const line = firstLine(value);
  if (!line) return '';
  return line
    .replace(/^#{1,6}\s+/, '')
    .replace(/^>\s*/, '')
    .replace(/^[-*+]\s+/, '')
    .replace(/\*\*([^*]+)\*\*/g, '$1')
    .replace(/__([^_]+)__/g, '$1')
    .replace(/`([^`]+)`/g, '$1')
    .trim();
}

function statusBadge(label: string, inProgressText: string, explicitStatus?: string): { badge: string; tone: 'success' | 'danger' | 'neutral' } {
  const raw = (explicitStatus || '').trim();
  if (raw) {
    if (/^completed$/i.test(raw)) return { badge: '完成', tone: 'success' };
    if (isActiveItemStatus(raw)) return { badge: inProgressText, tone: 'neutral' };
    if (/^failed$/i.test(raw)) return { badge: '失败', tone: 'danger' };
    if (/^(cancelled|interrupted)$/i.test(raw)) return { badge: '已停止', tone: 'neutral' };
    return { badge: '', tone: 'neutral' };
  }
  if (/\bcompleted\b/i.test(label)) return { badge: '完成', tone: 'success' };
  if (/\b(inProgress|running|pending|waiting)\b/i.test(label)) return { badge: inProgressText, tone: 'neutral' };
  if (/\bfailed\b/i.test(label)) return { badge: '失败', tone: 'danger' };
  if (/\b(cancelled|interrupted)\b/i.test(label)) return { badge: '已停止', tone: 'neutral' };
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
    const status = statusBadge(line.label, '运行中', line.status);
    return { icon: 'cmd', title, badge: status.badge, badgeTone: status.tone, additions: '', deletions: '' };
  }
  if (line.kind === 'file_change') {
    const activeBadge = isActiveItemStatus(line.status || '') ? '进行中' : '';
    const match = /^(.*?)\s*·\s*(\+\d+)\s*([−-]\d+)$/.exec(line.label);
    if (match) {
      return { icon: 'file', title: match[1].trim() || '文件变更', badge: activeBadge, badgeTone: 'neutral', additions: match[2], deletions: match[3] };
    }
    return { icon: 'file', title: line.label || '文件变更', badge: activeBadge, badgeTone: 'neutral', additions: '', deletions: '' };
  }
  if (line.kind === 'file_search') {
    const pattern = firstLine(line.text);
    const status = statusBadge(line.label, '进行中', line.status);
    return { icon: 'file', title: pattern ? '搜索 ' + pattern : '文件搜索', badge: status.badge, badgeTone: status.tone, additions: '', deletions: '' };
  }
  if (line.kind === 'web_search') {
    const pattern = firstLine(line.text);
    const status = statusBadge(line.label, '进行中', line.status);
    return { icon: 'browser', title: pattern ? '搜索 ' + pattern : '网络搜索', badge: status.badge, badgeTone: status.tone, additions: '', deletions: '' };
  }
  if (line.kind === 'reasoning') {
    const status = statusBadge(line.label, '思考中', line.status);
    const preview = reasoningPreviewLine(line.text);
    return { icon: 'thinking', title: preview || '思考过程', badge: status.badge, badgeTone: status.tone, additions: '', deletions: '' };
  }
  if (line.kind === 'compaction') {
    const status = statusBadge(line.label, '进行中', line.status);
    return { icon: 'info', title: '压缩上下文', badge: status.badge, badgeTone: status.tone, additions: '', deletions: '' };
  }
  if (line.kind === 'checkpoint') {
    return { icon: 'info', title: '检查点', badge: '', badgeTone: 'neutral', additions: '', deletions: '' };
  }
  if (line.kind === 'error') {
    return { icon: 'info', title: line.label || '错误', badge: '失败', badgeTone: 'danger', additions: '', deletions: '' };
  }
  if (line.kind === 'dynamic_tool' || line.kind === 'tool_call') {
    const status = statusBadge(line.label, '进行中', line.status);
    const rawTitle = line.label.replace(/^(?:dynamic_tool|tool_call)(?:\s*·\s*)?/, '')
      .replace(/(?:^|\s*·\s*)(completed|failed|inProgress|running|pending|waiting|cancelled|interrupted|idle)\s*$/i, '').trim();
    const t3Id = resolveT3McpToolId(line.toolName || '') || resolveT3McpToolId(rawTitle);
    if (t3Id) {
      const spec = T3_MCP_TOOLS[t3Id];
      const useCustomTitle = !!rawTitle && !isRawT3ToolLabel(rawTitle);
      const displayTitle = useCustomTitle ? rawTitle : (isActivityInProgress(line) ? spec.runningLabel : spec.completedLabel);
      return { icon: spec.icon, title: displayTitle, badge: status.badge, badgeTone: status.tone, additions: '', deletions: '' };
    }
    if (/^(?:default_api:)?(?:mcp[-_]{1,2})?t3[-_ ]?code(?:__|[-_.:/ ]|\s*·\s*)/i.test(line.toolName || '') ||
      /^(?:default_api:)?(?:mcp[-_]{1,2})?t3[-_ ]?code(?:__|[-_.:/ ]|\s*·\s*)/i.test(rawTitle)) {
      const cleaned = rawTitle.replace(/^(?:default_api:)?(?:mcp[-_]{1,2})?t3[-_ ]?code(?:__|[-_.:/ ]|\s*·\s*)/i, '').trim();
      return { icon: 't3', title: cleaned || rawTitle || 'T3 工具', badge: status.badge, badgeTone: status.tone, additions: '', deletions: '' };
    }
    if (rawTitle.startsWith('Read ') || rawTitle.startsWith('View ')) {
      const rawPath = rawTitle.replace(/^(?:Read|View)\s+/, '').trim().replace(/\\/g, '/');
      const slash = rawPath.lastIndexOf('/');
      const base = slash >= 0 ? rawPath.slice(slash + 1) : rawPath;
      const prefix = isActivityInProgress(line) ? '正在读取 ' : '已读取 ';
      return { icon: 'eye', title: prefix + (base || rawPath), badge: status.badge, badgeTone: status.tone, additions: '', deletions: '' };
    }
    if (rawTitle.startsWith('已读取 ') || rawTitle.startsWith('读取 ') || rawTitle.startsWith('查看 ') || isReadToolName(line.toolName || '') || isReadToolName(rawTitle)) {
      const target = isReadToolName(rawTitle) ? firstLine(line.text) : rawTitle;
      const prefix = isActivityInProgress(line) ? '正在读取' : '已读取';
      const title = /^(?:已读取|正在读取|读取|查看)/.test(rawTitle) ? rawTitle : (target ? prefix + ' ' + target : prefix + '文件');
      return { icon: 'eye', title, badge: status.badge, badgeTone: status.tone, additions: '', deletions: '' };
    }
    if (rawTitle.startsWith('Run ')) {
      return { icon: 'cmd', title: '执行 ' + rawTitle.slice(4).trim(), badge: status.badge, badgeTone: status.tone, additions: '', deletions: '' };
    }
    return { icon: 'info', title: rawTitle || '工具调用', badge: status.badge, badgeTone: status.tone, additions: '', deletions: '' };
  }
  const fallbackT3Id = resolveT3McpToolId(line.toolName || '') || resolveT3McpToolId(line.label);
  const fallbackStatus = statusBadge(line.label, '进行中', line.status);
  const fallbackBadge = fallbackStatus.badge === '进行中' || fallbackStatus.tone === 'danger' ? fallbackStatus.badge : '';
  const fallbackTone = fallbackBadge ? fallbackStatus.tone : 'neutral';
  if (fallbackT3Id) {
    const spec = T3_MCP_TOOLS[fallbackT3Id];
    return {
      icon: spec.icon,
      title: isActivityInProgress(line) ? spec.runningLabel : spec.completedLabel,
      badge: fallbackBadge,
      badgeTone: fallbackTone,
      additions: '',
      deletions: ''
    };
  }
  if (line.kind === 'file_read' || isReadToolName(line.toolName || '')) {
    const target = firstLine(line.text);
    return {
      icon: 'eye',
      title: target ? ((isActivityInProgress(line) ? '正在读取 ' : '已读取 ') + target) : (line.label || '已读取文件'),
      badge: fallbackBadge,
      badgeTone: fallbackTone,
      additions: '',
      deletions: ''
    };
  }
  return { icon: 'info', title: line.label || line.kind, badge: fallbackBadge, badgeTone: fallbackTone, additions: '', deletions: '' };
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
  summaryIcon: ActivityIcon;
}

export interface TurnWorkGroup {
  groupId: string;
  runId: string;
  items: Record<string, Object>[];
  prominent: Record<string, Object>[];
  htmlRenders: HtmlRenderEntry[];
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
  const type = optional(item.type);
  if (!type || [
    'assistant_message', 'user_message', 'link_request', 'secret_request',
    'user_input_request', 'approval_request', 'todo_list', 'run_interrupt_request', 'checkpoint'
  ].includes(type)) {
    return true;
  }
  const status = optional(item.status);
  if (type === 'command_execution' && optional(item.input).trim() === 'Preparing workspace') {
    if (item.deferredWork === true) return false;
    if (status === 'failed' || isActiveItemStatus(status)) return false;
    if (typeof item.exitCode === 'number' && item.exitCode !== 0) return false;
    return true;
  }
  if (type === 'error' && status === 'cancelled' && failureCode(item) === 'workspace_preparation_failed') {
    return true;
  }
  if (type === 'dynamic_tool' && htmlRenderFromToolItem(item) !== undefined) {
    return true;
  }
  return false;
}

export function isProminentWorkItem(item: Record<string, Object>): boolean {
  if (isHiddenWorkItem(item)) return false;
  const type = optional(item.type);
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
    if (optional(cp.status) !== 'ready') continue;
    const runId = optional(cp.runId);
    const fileRows = compactObjects(cp.files);
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
    const cpId = optional(cp.id) || ('cp:' + runId + ':' + count);
    const badge = makeCheckpointBadge(cpId, runId, count, additions, deletions, filePaths);
    if (runId) {
      byRun[runId] = badge;
      const assistantId = lastAssistantByRun[runId];
      if (assistantId) byAssistantMessage[assistantId] = badge;
    }
  }

  for (const item of items) {
    if (optional(item.type) !== 'checkpoint') continue;
    const runId = optional(item.runId);
    if (runId && byRun[runId]) continue;
    const fileRows = compactObjects(item.files);
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
    const itemId = optional(item.id) || ('cp-item:' + runId + ':' + filePaths.length);
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

export interface RunMetaOptions {
  groupRunning?: boolean;
  groupInterrupted?: boolean;
  includeRunDuration?: boolean;
}

export function buildRunMeta(
  run: Record<string, Object> | undefined,
  stepCount: number,
  options?: RunMetaOptions
): RunMeta | undefined {
  if (!run) return undefined;
  const runId = optional(run.id);
  const status = optional(run.status);
  const startIso = optional(run.startedAt) || optional(run.requestedAt);
  const endIso = optional(run.completedAt);
  let durationMs = 0;
  if (startIso && endIso && options?.includeRunDuration !== false) {
    const startMs = Date.parse(startIso);
    const endMs = Date.parse(endIso);
    if (Number.isFinite(startMs) && Number.isFinite(endMs) && endMs >= startMs) {
      durationMs = endMs - startMs;
    }
  }
  const durationText = formatWorkDuration(durationMs);
  const runInterrupted = status === 'interrupted' || status === 'cancelled';
  const runRunning = isActiveRunStatus(status) && !endIso;
  const interrupted = options?.groupInterrupted !== undefined ? options.groupInterrupted : runInterrupted;
  const running = options?.groupRunning !== undefined ? options.groupRunning : runRunning;
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
  let reads = 0;
  let searches = 0;
  let reasoning = 0;
  let t3Tools = 0;
  let browserTools = 0;
  let prTools = 0;
  let failures = 0;
  let additions = 0;
  let deletions = 0;
  let running = false;

  for (const line of lines) {
    const summary = activitySummary(line);
    if (summary.icon === 't3') t3Tools += 1;
    else if (summary.icon === 'browser') browserTools += 1;
    else if (summary.icon === 'pr') prTools += 1;
    else if (summary.icon === 'eye') reads += 1;
    if (line.kind === 'command_execution') {
      commands += 1;
      if (summary.badgeTone === 'danger') failures += 1;
      if (summary.badge === '运行中') running = true;
    } else if (line.kind === 'file_change') {
      files += 1;
      additions += parseIntSafe(summary.additions);
      deletions += parseIntSafe(summary.deletions);
      if (summary.badge === '进行中') running = true;
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
  if (reasoning > 0 && parts.length === 0 && t3Tools === 0 && browserTools === 0 && prTools === 0 && reads === 0) {
    parts.push('思考 ' + reasoning + ' 步');
  }
  if (parts.length === 0 && lines.length > 0) parts.push(lines.length + ' 项执行步骤');

  let summaryIcon: ActivityIcon = 'cmd';
  if (commands === 0 && files === 0) {
    if (t3Tools > 0) summaryIcon = 't3';
    else if (prTools > 0) summaryIcon = 'pr';
    else if (browserTools > 0) summaryIcon = 'browser';
    else if (reads > 0) summaryIcon = 'eye';
    else if (searches > 0) summaryIcon = 'file';
    else if (reasoning > 0) summaryIcon = 'thinking';
    else summaryIcon = 'info';
  } else if (commands === 0 && files > 0) {
    summaryIcon = 'file';
  }

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
    failureLabel: failures > 0 ? failures + ' 失败' : '',
    summaryIcon
  };
}

function normalizeGroupWorkItems(
  workItems: Record<string, Object>[],
  prominentItems: Record<string, Object>[],
  runRecord: Record<string, Object> | undefined,
  isTail: boolean
): Record<string, Object>[] {
  const runStatus = runRecord ? optional(runRecord.status) : '';
  const runSettled = runRecord !== undefined && (isSettledRunStatus(runStatus) || !!optional(runRecord.completedAt));
  const settledStatus = (runStatus === 'interrupted' || runStatus === 'cancelled') ? runStatus : 'completed';
  return workItems.map((item: Record<string, Object>, index: number): Record<string, Object> => {
    const status = optional(item.status);
    if (!isActiveItemStatus(status)) return item;
    const type = optional(item.type);
    if (type === 'reasoning') {
      const isTrailingActiveReasoning = isTail && !runSettled &&
        index === workItems.length - 1 && prominentItems.length === 0;
      return isTrailingActiveReasoning ? item : Object.assign({}, item, { status: settledStatus });
    }
    if (runSettled && type !== 'subagent') {
      return Object.assign({}, item, { status: settledStatus });
    }
    return item;
  });
}

function buildWorkGroup(
  groupId: string,
  runId: string,
  workItems: Record<string, Object>[],
  prominentItems: Record<string, Object>[],
  htmlRenders: HtmlRenderEntry[],
  checkpoint: CheckpointBadge | undefined,
  runRecord: Record<string, Object> | undefined,
  isTail: boolean,
  isLastOfRun: boolean
): TurnWorkGroup | undefined {
  const normalizedWork = normalizeGroupWorkItems(workItems, prominentItems, runRecord, isTail);
  const lines = activityLines(normalizedWork);
  const summary = summarizeWork(lines);
  const runStatus = runRecord ? optional(runRecord.status) : '';
  const runEnded = runRecord !== undefined && !!optional(runRecord.completedAt);
  const runActivelyWorking = runRecord !== undefined && !runEnded &&
    (runStatus === 'preparing' || runStatus === 'starting' || runStatus === 'running');
  const runInterrupted = runRecord !== undefined && (runStatus === 'interrupted' || runStatus === 'cancelled');
  const hasInterruptItem = prominentItems.some((item: Record<string, Object>) => optional(item.type) === 'run_interrupt_result') ||
    normalizedWork.some((item: Record<string, Object>) => {
      const st = optional(item.status);
      return st === 'interrupted' || st === 'cancelled';
    });
  const groupRunning = summary.running;
  const groupInterrupted = runInterrupted && (isLastOfRun || hasInterruptItem);
  const hasWorkChrome = lines.length > 0 || prominentItems.length > 0 || checkpoint !== undefined || groupInterrupted;
  const runMeta = hasWorkChrome ? buildRunMeta(runRecord, lines.length + prominentItems.length, {
    groupRunning,
    groupInterrupted,
    includeRunDuration: isLastOfRun
  }) : undefined;
  const hasVisible = hasWorkChrome || htmlRenders.length > 0;
  if (!hasVisible) return undefined;

  const defaultExpanded = groupRunning || groupInterrupted || (isTail && runActivelyWorking);
  const revParts: string[] = [];
  for (const item of normalizedWork) {
    revParts.push(optional(item.id) + ':' + optional(item.status) + ':' + String(item.exitCode ?? ''));
  }
  for (const item of prominentItems) {
    revParts.push(optional(item.id) + ':' + optional(item.status));
  }
  for (const renderEntry of htmlRenders) {
    revParts.push('html:' + renderEntry.id + ':' + renderEntry.render.attachmentId + ':' + renderEntry.render.height);
  }
  if (checkpoint) revParts.push('cp:' + checkpoint.checkpointId + ':' + checkpoint.fileCount + ':' + checkpoint.diffLabel);
  if (runMeta) revParts.push('run:' + runMeta.status + ':' + (runMeta.running ? '1' : '0') + ':' + runMeta.headerLabel);
  const revision = revParts.join('|');

  return {
    groupId,
    runId,
    items: normalizedWork,
    prominent: prominentItems.slice(),
    htmlRenders: htmlRenders.slice(),
    checkpoint,
    runMeta,
    summary,
    defaultExpanded,
    revision
  };
}

interface PendingWorkGroupSpec {
  slot: 'before' | 'afterUser' | 'afterAssistant' | 'tail';
  slotKey: string;
  groupId: string;
  runId: string;
  workItems: Record<string, Object>[];
  prominentItems: Record<string, Object>[];
  htmlRenders: HtmlRenderEntry[];
  checkpoint?: CheckpointBadge;
  runRecord?: Record<string, Object>;
  intrinsicallyVisible: boolean;
}

export function groupWorkByMessage(items: Record<string, Object>[],
  runs: Record<string, Object>[], checkpoints: Record<string, Object>[],
  messages: ChatMessage[]): MessageWorkMap {
  const runById: Record<string, Record<string, Object>> = {};
  for (const run of runs) {
    const id = optional(run.id);
    if (id) runById[id] = run;
  }

  const derived = deriveCheckpointBadges(checkpoints, items, messages);
  const before: Record<string, TurnWorkGroup> = {};
  const afterUser: Record<string, TurnWorkGroup> = {};
  const afterAssistant: Record<string, TurnWorkGroup> = {};
  const attachedCheckpointIds: Record<string, boolean> = {};
  const hasBeforeSpec: Record<string, boolean> = {};
  const specs: PendingWorkGroupSpec[] = [];

  let pendingWork: Record<string, Object>[] = [];
  let pendingProminent: Record<string, Object>[] = [];
  let pendingHtmlRenders: HtmlRenderEntry[] = [];
  let pendingCheckpoint: CheckpointBadge | undefined = undefined;
  let pendingRunId: string = '';
  let lastUserMessageId: string = '';
  let lastAssistantMessageId: string = '';
  let seenAssistantSinceLastUser: boolean = false;
  let groupCounter: number = 0;

  let tailGroup: TurnWorkGroup | undefined = undefined;

  const flushPending = (target: 'afterUser' | 'afterAssistant' | 'tail'): void => {
    const runRecord = pendingRunId ? runById[pendingRunId] : undefined;
    const firstItemId = pendingWork.length ? optional(pendingWork[0].id) :
      pendingProminent.length ? optional(pendingProminent[0].id) :
      pendingHtmlRenders.length ? pendingHtmlRenders[0].itemId : '';
    let gId = '';
    let slot: 'afterUser' | 'afterAssistant' | 'tail' = 'tail';
    let slotKey = '';
    if (target === 'afterUser' && lastUserMessageId) {
      slot = 'afterUser';
      slotKey = lastUserMessageId;
      gId = (pendingRunId || 'user') + ':u:' + lastUserMessageId + ':' + String(groupCounter);
    } else if (target === 'afterAssistant' && lastAssistantMessageId) {
      slot = 'afterAssistant';
      slotKey = lastAssistantMessageId;
      gId = (pendingRunId || 'asst') + ':a:' + lastAssistantMessageId + ':' + String(groupCounter);
    } else {
      slot = 'tail';
      gId = pendingRunId || (lastUserMessageId ? 'user:' + lastUserMessageId : '') ||
        (firstItemId ? 'item:' + firstItemId : 'tail:' + String(groupCounter));
    }
    let cp = pendingCheckpoint || (pendingRunId && !derived.byAssistantMessage[pendingRunId] ? derived.byRun[pendingRunId] : undefined);
    if (cp && attachedCheckpointIds[cp.checkpointId]) cp = undefined;
    const intrinsicallyVisible = pendingWork.length > 0 || pendingProminent.length > 0 ||
      pendingHtmlRenders.length > 0 || cp !== undefined;
    if (intrinsicallyVisible) {
      specs.push({
        slot,
        slotKey,
        groupId: gId,
        runId: pendingRunId,
        workItems: pendingWork.slice(),
        prominentItems: pendingProminent.slice(),
        htmlRenders: pendingHtmlRenders.slice(),
        checkpoint: cp,
        runRecord,
        intrinsicallyVisible: true
      });
      groupCounter += 1;
      if (cp) attachedCheckpointIds[cp.checkpointId] = true;
    }
    pendingWork = [];
    pendingProminent = [];
    pendingHtmlRenders = [];
    pendingCheckpoint = undefined;
    pendingRunId = '';
  };

  for (const item of items) {
    const type = optional(item.type);
    if (!type) continue;
    const itemRunId = optional(item.runId);
    if (type === 'user_message') {
      if (pendingWork.length > 0 || pendingProminent.length > 0 || pendingHtmlRenders.length > 0 || pendingCheckpoint !== undefined) {
        if (!seenAssistantSinceLastUser && lastUserMessageId) {
          flushPending('afterUser');
        } else if (seenAssistantSinceLastUser && lastAssistantMessageId) {
          flushPending('afterAssistant');
        } else {
          pendingWork = [];
          pendingProminent = [];
          pendingHtmlRenders = [];
          pendingCheckpoint = undefined;
          pendingRunId = '';
        }
      } else {
        pendingRunId = '';
      }
      lastUserMessageId = optional(item.messageId) || optional(item.id);
      lastAssistantMessageId = '';
      seenAssistantSinceLastUser = false;
      continue;
    }
    if (type === 'assistant_message') {
      const msgId = optional(item.messageId) || optional(item.id);
      const effectiveRunId = itemRunId || pendingRunId;
      const runRecord = effectiveRunId ? runById[effectiveRunId] : undefined;
      let cp: CheckpointBadge | undefined = msgId ? derived.byAssistantMessage[msgId] : undefined;
      if (!cp && effectiveRunId) cp = derived.byRun[effectiveRunId];
      if (!cp) cp = pendingCheckpoint;
      if (cp && attachedCheckpointIds[cp.checkpointId]) cp = undefined;

      const intrinsicallyVisible = pendingWork.length > 0 || pendingProminent.length > 0 ||
        pendingHtmlRenders.length > 0 || cp !== undefined;
      const runStatus = runRecord ? optional(runRecord.status) : '';
      const runInterrupted = runStatus === 'interrupted' || runStatus === 'cancelled';
      if (msgId && (intrinsicallyVisible || runInterrupted)) {
        const gId = (effectiveRunId ? effectiveRunId + ':' : 'msg:') + (msgId || String(groupCounter));
        specs.push({
          slot: 'before',
          slotKey: msgId,
          groupId: gId,
          runId: effectiveRunId,
          workItems: pendingWork.slice(),
          prominentItems: pendingProminent.slice(),
          htmlRenders: pendingHtmlRenders.slice(),
          checkpoint: cp,
          runRecord,
          intrinsicallyVisible
        });
        if (intrinsicallyVisible) {
          groupCounter += 1;
          hasBeforeSpec[msgId] = true;
        }
        if (cp) attachedCheckpointIds[cp.checkpointId] = true;
      }
      pendingWork = [];
      pendingProminent = [];
      pendingHtmlRenders = [];
      pendingCheckpoint = undefined;
      pendingRunId = '';
      lastAssistantMessageId = msgId;
      seenAssistantSinceLastUser = true;
      continue;
    }
    if (type === 'checkpoint') {
      if (!itemRunId) {
        const cpFromItem = derived.byItemId[optional(item.id)];
        if (cpFromItem) pendingCheckpoint = cpFromItem;
      }
      continue;
    }
    if (type === 'dynamic_tool') {
      const render = htmlRenderFromToolItem(item);
      if (render !== undefined) {
        const id = optional(item.id) || render.attachmentId;
        if (itemRunId && !pendingRunId) pendingRunId = itemRunId;
        pendingHtmlRenders.push({
          id: 'html-render:' + id,
          itemId: id,
          runId: itemRunId || pendingRunId,
          render
        });
        continue;
      }
    }
    if (isHiddenWorkItem(item)) continue;
    if (itemRunId && !pendingRunId) pendingRunId = itemRunId;
    if (isProminentWorkItem(item)) pendingProminent.push(item);
    else pendingWork.push(item);
  }

  if (pendingWork.length > 0 || pendingProminent.length > 0 || pendingHtmlRenders.length > 0 || pendingCheckpoint !== undefined) {
    flushPending('tail');
  }

  // Ensure any ready checkpoint with changed files mapped to an assistant message without tools still surfaces.
  for (const msg of messages) {
    if (msg.role !== 'assistant' || hasBeforeSpec[msg.id]) continue;
    const cp = derived.byAssistantMessage[msg.id];
    if (!cp || attachedCheckpointIds[cp.checkpointId]) continue;
    const runRecord = msg.runId ? runById[msg.runId] : (cp.runId ? runById[cp.runId] : undefined);
    const effectiveRunId = msg.runId || cp.runId;
    specs.push({
      slot: 'before',
      slotKey: msg.id,
      groupId: effectiveRunId || ('msg:' + msg.id),
      runId: effectiveRunId,
      workItems: [],
      prominentItems: [],
      htmlRenders: [],
      checkpoint: cp,
      runRecord,
      intrinsicallyVisible: true
    });
    hasBeforeSpec[msg.id] = true;
    attachedCheckpointIds[cp.checkpointId] = true;
  }

  const lastVisibleIndexByRun: Record<string, number> = {};
  const lastAnyIndexByRun: Record<string, number> = {};
  for (let index = 0; index < specs.length; index += 1) {
    const spec = specs[index];
    if (!spec.runId) continue;
    lastAnyIndexByRun[spec.runId] = index;
    if (spec.intrinsicallyVisible) lastVisibleIndexByRun[spec.runId] = index;
  }

  for (let index = 0; index < specs.length; index += 1) {
    const spec = specs[index];
    const isTail = spec.slot === 'tail';
    const targetLastIndex = spec.runId
      ? (lastVisibleIndexByRun[spec.runId] !== undefined ? lastVisibleIndexByRun[spec.runId] : lastAnyIndexByRun[spec.runId])
      : index;
    const isLastOfRun = !spec.runId || index === targetLastIndex;
    const group = buildWorkGroup(
      spec.groupId,
      spec.runId,
      spec.workItems,
      spec.prominentItems,
      spec.htmlRenders,
      spec.checkpoint,
      spec.runRecord,
      isTail,
      isLastOfRun
    );
    if (!group) continue;
    if (spec.slot === 'before' && spec.slotKey) {
      before[spec.slotKey] = group;
    } else if (spec.slot === 'afterUser' && spec.slotKey) {
      afterUser[spec.slotKey] = group;
    } else if (spec.slot === 'afterAssistant' && spec.slotKey) {
      afterAssistant[spec.slotKey] = group;
    } else if (spec.slot === 'tail') {
      tailGroup = group;
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

/** 解析展开态工作项正文：reasoning 流式阶段优先采用实时快照正文，历史快照省略正文时再回落到单条拉取文本。 */
export function resolveExpandedActivityBody(line: ActivityLine, fetchedOutput: string): string {
  if (line.kind === 'reasoning') {
    const live = line.text || '';
    const fetched = fetchedOutput || '';
    return live.length >= fetched.length ? live : fetched;
  }
  return fetchedOutput || line.text || '';
}

export interface MessageFooterMeta {
  showFooter: boolean;
  canCopy: boolean;
  canFork: boolean;
  forkRunId: string;
  forkSourceThreadId: string;
}

export function canForkAssistantItem(
  item: Record<string, Object>,
  capabilities: Record<string, Object> | undefined
): boolean {
  if (optional(item.type) !== 'assistant_message') return false;
  if (!optional(item.runId)) return false;
  if (optional(item.status) !== 'completed') return false;
  if (capabilities === undefined) {
    // Historical and inherited items may outlive their provider-session record;
    // keep the server-side fork fallback available unless capabilities explicitly disallow it.
    return true;
  }
  const threads = capabilities.threads !== undefined && capabilities.threads !== null
    ? record(capabilities.threads) : {};
  const identity = capabilities.identity !== undefined && capabilities.identity !== null
    ? record(capabilities.identity) : {};
  const context = capabilities.context !== undefined && capabilities.context !== null
    ? record(capabilities.context) : {};
  const canForkNatively =
    threads.canForkThread === true &&
    threads.canForkFromTurn === true &&
    identity.nativeThreadIds === 'strong';
  return canForkNatively || context.supportsFullThreadHandoff === true;
}

export function buildMessageFooterMap(
  threadId: string,
  messages: ChatMessage[],
  items: Record<string, Object>[],
  runs: Record<string, Object>[],
  providerThreads: Record<string, Object>[],
  providerSessions: Record<string, Object>[]
): Record<string, MessageFooterMeta> {
  const runById: Record<string, Record<string, Object>> = {};
  for (const run of runs) {
    const id = optional(run.id);
    if (id) runById[id] = run;
  }
  const terminalAssistantByRun: Record<string, string> = {};
  for (const message of messages) {
    if (message.role === 'assistant' && message.runId) {
      terminalAssistantByRun[message.runId] = message.id;
    }
  }
  const assistantItemByMessageId: Record<string, Record<string, Object>> = {};
  for (const item of items) {
    if (optional(item.type) === 'assistant_message') {
      const msgId = optional(item.messageId);
      if (msgId) assistantItemByMessageId[msgId] = item;
    }
  }
  const providerThreadById: Record<string, Record<string, Object>> = {};
  for (const pt of providerThreads) {
    const id = optional(pt.id);
    if (id) providerThreadById[id] = pt;
  }
  const providerSessionById: Record<string, Record<string, Object>> = {};
  for (const ps of providerSessions) {
    const id = optional(ps.id);
    if (id) providerSessionById[id] = ps;
  }

  const result: Record<string, MessageFooterMeta> = {};
  for (const message of messages) {
    const hasText = message.text.trim().length > 0;
    if (message.role === 'user') {
      result[message.id] = {
        showFooter: hasText || Boolean(message.timestamp),
        canCopy: hasText,
        canFork: false,
        forkRunId: '',
        forkSourceThreadId: ''
      };
      continue;
    }
    if (message.role !== 'assistant') {
      result[message.id] = {
        showFooter: hasText || Boolean(message.timestamp),
        canCopy: hasText,
        canFork: false,
        forkRunId: '',
        forkSourceThreadId: ''
      };
      continue;
    }
    const runId = message.runId || '';
    const run = runId ? runById[runId] : undefined;
    const turnInProgress = run !== undefined && isActiveRunStatus(optional(run.status));
    const isTerminal = !runId || terminalAssistantByRun[runId] === message.id;
    const showFooter = isTerminal && !turnInProgress && !message.streaming;
    if (!showFooter) {
      result[message.id] = {
        showFooter: false,
        canCopy: false,
        canFork: false,
        forkRunId: '',
        forkSourceThreadId: ''
      };
      continue;
    }
    const item = assistantItemByMessageId[message.id];
    let canFork = false;
    let forkRunId = '';
    let forkSourceThreadId = '';
    if (item !== undefined) {
      const ptId = optional(item.providerThreadId);
      const pt = ptId ? providerThreadById[ptId] : undefined;
      const psId = pt ? optional(pt.providerSessionId) : '';
      const ps = psId ? providerSessionById[psId] : undefined;
      const capabilities = ps !== undefined && ps.capabilities !== undefined && ps.capabilities !== null
        ? record(ps.capabilities) : undefined;
      const itemRunId = optional(item.runId) || runId;
      const sourceThreadId = optional(item.sourceThreadId) || threadId;
      if (itemRunId && sourceThreadId && canForkAssistantItem(item, capabilities)) {
        canFork = true;
        forkRunId = itemRunId;
        forkSourceThreadId = sourceThreadId;
      }
    }
    result[message.id] = {
      showFooter: true,
      canCopy: hasText,
      canFork,
      forkRunId,
      forkSourceThreadId
    };
  }
  return result;
}

let cachedMsgTimeFormatter: Intl.DateTimeFormat | undefined = undefined;
let cachedMsgDateFormatter: Intl.DateTimeFormat | undefined = undefined;
let cachedMsgDateWithYearFormatter: Intl.DateTimeFormat | undefined = undefined;

export function formatMessageTimestamp(value: string | undefined, nowMs: number = Date.now()): string {
  if (!value) return '';
  const time = Date.parse(value);
  if (!Number.isFinite(time)) return '';
  const date = new Date(time);
  const now = new Date(nowMs);
  const sameDay =
    date.getFullYear() === now.getFullYear() &&
    date.getMonth() === now.getMonth() &&
    date.getDate() === now.getDate();
  try {
    if (!cachedMsgTimeFormatter) {
      cachedMsgTimeFormatter = new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' });
    }
    const formattedTime = cachedMsgTimeFormatter.format(date);
    if (sameDay) return formattedTime;
    const sameYear = date.getFullYear() === now.getFullYear();
    if (sameYear) {
      if (!cachedMsgDateFormatter) {
        cachedMsgDateFormatter = new Intl.DateTimeFormat(undefined, { month: 'numeric', day: 'numeric' });
      }
      return cachedMsgDateFormatter.format(date) + ' ' + formattedTime;
    }
    if (!cachedMsgDateWithYearFormatter) {
      cachedMsgDateWithYearFormatter = new Intl.DateTimeFormat(undefined, { year: 'numeric', month: 'numeric', day: 'numeric' });
    }
    return cachedMsgDateWithYearFormatter.format(date) + ' ' + formattedTime;
  } catch (_) {
    const hh = String(date.getHours()).padStart(2, '0');
    const mm = String(date.getMinutes()).padStart(2, '0');
    if (sameDay) return hh + ':' + mm;
    return (date.getMonth() + 1) + '/' + date.getDate() + ' ' + hh + ':' + mm;
  }
}

export type LiveThinkingKind = 'starting' | 'preparing' | 'thinking' | 'waiting-subagents';

export interface LiveThinkingRow {
  visible: boolean;
  kind: LiveThinkingKind;
  label: string;
  runId: string;
}

export interface LiveThinkingInput {
  draftMode: boolean;
  threadSynced: boolean;
  runs: Record<string, Object>[];
  items: Record<string, Object>[];
  messages: ChatMessage[];
  providerTurns: Record<string, Object>[];
  providerSessions: Record<string, Object>[];
  nodes: Record<string, Object>[];
  details: Record<string, Object>;
  tailGroup: TurnWorkGroup | undefined;
  pendingActionCount: number;
  hasPendingBackgroundWork: boolean;
  hasWorktreeSetupCard: boolean;
  isCompacting: boolean;
  isStopping: boolean;
  fallbackProviderDriver?: string;
  configProviders?: Object[];
}

export function emptyLiveThinkingRow(): LiveThinkingRow {
  return { visible: false, kind: 'thinking', label: '', runId: '' };
}

function numericField(value: Object | undefined): number {
  return typeof value === 'number' && Number.isFinite(value) ? value as number : 0;
}

export function providerDisplayName(driver: string): string {
  const normalized = driver.trim().toLowerCase();
  if (!normalized) return '';
  if (normalized === 'claude' || normalized === 'claudeagent' || normalized === 'claude_agent' || normalized === 'claude-code') {
    return 'Claude Code';
  }
  if (normalized === 'codex') return 'Codex';
  if (normalized === 'antigravity') return 'Antigravity';
  if (normalized === 'cursor') return 'Cursor';
  if (normalized === 'gemini') return 'Gemini';
  if (normalized === 'grok') return 'Grok';
  if (normalized === 'opencode' || normalized === 'opencode2') return 'OpenCode';
  if (normalized === 'pi') return 'Pi';
  if (normalized === 'muse') return 'Muse';
  if (normalized === 'kiro') return 'Kiro';
  if (normalized === 'fx') return 'Fx';
  if (normalized === 'acp') return 'ACP';
  return '';
}

function resolveRunProviderName(
  providerInstanceId: string,
  providerSessions: Record<string, Object>[],
  configProviders: Object[] | undefined,
  fallbackDriver: string | undefined
): string {
  if (providerInstanceId) {
    for (let i = providerSessions.length - 1; i >= 0; i -= 1) {
      const session = providerSessions[i];
      if (optional(session.providerInstanceId) !== providerInstanceId) continue;
      const mapped = providerDisplayName(optional(session.driver));
      if (mapped) return mapped;
    }
    if (Array.isArray(configProviders)) {
      for (const raw of configProviders) {
        if (raw === null || raw === undefined || typeof raw !== 'object' || Array.isArray(raw)) continue;
        const row = raw as Record<string, Object>;
        if (optional(row.instanceId) !== providerInstanceId) continue;
        const mapped = providerDisplayName(optional(row.driver));
        if (mapped) return mapped;
        const displayName = optional(row.displayName).trim();
        if (displayName) return displayName;
      }
    }
  }
  if (fallbackDriver) {
    const mapped = providerDisplayName(fallbackDriver);
    if (mapped) return mapped;
  }
  if (providerInstanceId) {
    const mapped = providerDisplayName(providerInstanceId);
    if (mapped) return mapped;
  }
  return '';
}

function latestProviderTurnForAttempt(
  providerTurns: Record<string, Object>[],
  attemptId: string
): Record<string, Object> | undefined {
  if (!attemptId) return undefined;
  let latest: Record<string, Object> | undefined = undefined;
  for (const turn of providerTurns) {
    if (optional(turn.runAttemptId) !== attemptId) continue;
    if (!latest || numericField(turn.ordinal) > numericField(latest.ordinal)) {
      latest = turn;
    }
  }
  return latest;
}

function isProviderNativeSubagent(details: Record<string, Object>): boolean {
  if (optional(details.creationSource) !== 'provider') return false;
  if (details.lineage === undefined || details.lineage === null) return false;
  try {
    return optional(record(details.lineage).relationshipToParent) === 'subagent';
  } catch (_) {
    return false;
  }
}

function countTrailingActiveSubagents(items: Record<string, Object>[], runId: string): number {
  if (!runId) return 0;
  let count = 0;
  for (let i = items.length - 1; i >= 0; i -= 1) {
    const item = items[i];
    if (optional(item.runId) !== runId) break;
    const type = optional(item.type);
    if (type === 'subagent') {
      if (isActiveItemStatus(optional(item.status))) count += 1;
      continue;
    }
    if (type === 'user_message' || type === 'assistant_message') break;
    if (!isHiddenWorkItem(item)) break;
  }
  return count;
}

function runHasObservedProviderWork(items: Record<string, Object>[], runId: string): boolean {
  if (!runId) return false;
  for (let i = items.length - 1; i >= 0; i -= 1) {
    const item = items[i];
    if (optional(item.runId) !== runId) continue;
    const type = optional(item.type);
    if (type === 'user_message' || type === 'checkpoint' || type === 'run_interrupt_request') continue;
    if (type === 'command_execution' && optional(item.input).trim() === 'Preparing workspace') continue;
    if (type === 'assistant_message' || !isHiddenWorkItem(item)) return true;
  }
  return false;
}

/**
 * 推导消息流尾部的实时占位思考行（对齐上游 ThreadThinkingRow）：
 * - 在 run 已创建、但尚未产生任何进行中的 turn_item 或流式 assistant_message 时立即提示；
 * - Provider 尚未开启 turn 时显示「正在启动 <Provider>…」，turn 开启后显示「正在思考…」。
 */
export function deriveLiveThinkingRow(input: LiveThinkingInput): LiveThinkingRow {
  if (input.draftMode || !input.threadSynced) return emptyLiveThinkingRow();
  if (input.isStopping || input.isCompacting) return emptyLiveThinkingRow();
  if (input.pendingActionCount > 0) return emptyLiveThinkingRow();
  if (input.messages.some((msg: ChatMessage) => msg.role === 'assistant' && msg.streaming)) {
    return emptyLiveThinkingRow();
  }
  if (input.tailGroup !== undefined && input.tailGroup.summary.running) {
    return emptyLiveThinkingRow();
  }

  let activeRun: Record<string, Object> | undefined = undefined;
  for (const run of input.runs) {
    const status = optional(run.status);
    const isInterruptible = status === 'preparing' || status === 'starting' || status === 'running';
    const isWaitingActive = status === 'waiting' && !input.hasPendingBackgroundWork;
    if (!isInterruptible && !isWaitingActive) continue;
    if (!activeRun || numericField(run.ordinal) > numericField(activeRun.ordinal)) {
      activeRun = run;
    }
  }

  if (!activeRun) {
    if (isProviderNativeSubagent(input.details)) {
      for (let i = input.nodes.length - 1; i >= 0; i -= 1) {
        const node = input.nodes[i];
        if (optional(node.kind) === 'root_turn' && optional(node.runId) === '') {
          if (isActiveItemStatus(optional(node.status))) {
            return { visible: true, kind: 'thinking', label: '正在思考…', runId: '' };
          }
          break;
        }
      }
    }
    return emptyLiveThinkingRow();
  }

  const runId = optional(activeRun.id);
  const runStatus = optional(activeRun.status);

  if (runStatus === 'preparing') {
    if (input.hasWorktreeSetupCard) return emptyLiveThinkingRow();
    return { visible: true, kind: 'preparing', label: '正在准备工作区…', runId };
  }

  const attemptId = optional(activeRun.activeAttemptId);
  const latestTurn = latestProviderTurnForAttempt(input.providerTurns, attemptId);
  const turnStatus = latestTurn ? optional(latestTurn.status) : '';
  if (turnStatus !== '' && turnStatus !== 'pending' && turnStatus !== 'running') {
    return emptyLiveThinkingRow();
  }

  const waitingSubagents = countTrailingActiveSubagents(input.items, runId);
  if (waitingSubagents > 0) {
    return {
      visible: true,
      kind: 'waiting-subagents',
      label: '等待 ' + waitingSubagents + ' 个子 Agent…',
      runId
    };
  }

  const providerStarting = turnStatus === '' &&
    (runStatus === 'starting' || (runStatus === 'running' && !runHasObservedProviderWork(input.items, runId)));
  if (providerStarting) {
    const providerName = resolveRunProviderName(
      optional(activeRun.providerInstanceId),
      input.providerSessions,
      input.configProviders,
      input.fallbackProviderDriver
    );
    return {
      visible: true,
      kind: 'starting',
      label: providerName ? '正在启动 ' + providerName + '…' : '正在启动…',
      runId
    };
  }

  return { visible: true, kind: 'thinking', label: '正在思考…', runId };
}

