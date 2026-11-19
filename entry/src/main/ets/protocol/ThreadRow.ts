// 首页会话行（对齐原版 Thread List V2）的纯展示逻辑。

/** 状态色调：run 主色、wait 警告色、danger 危险色、neutral 次要色。 */
export type ThreadTone = 'run' | 'wait' | 'danger' | 'neutral';

/** 首页右上角的状态文字 → 色调。空字符串表示没有状态，显示时间。 */
export function threadTone(status: string): ThreadTone {
  if (status === '运行中') return 'run';
  if (status === '等待批准' || status === '等待回答' || status === '访客消息' || status === '等待') return 'wait';
  if (status === '失败' || status === '用量受限') return 'danger';
  return 'neutral';
}

/** 紧凑相对时间：刚刚 / 8分钟 / 2小时 / 3天 / 11月2日（跨年带年份）。 */
export function compactTime(iso: string, nowMs: number): string {
  const value = Date.parse(iso);
  if (!Number.isFinite(value)) return '';
  const seconds = Math.max(0, Math.floor((nowMs - value) / 1000));
  if (seconds < 60) return '刚刚';
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return minutes + '分钟';
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return hours + '小时';
  const days = Math.floor(hours / 24);
  if (days < 7) return days + '天';
  const date = new Date(value);
  const now = new Date(nowMs);
  const day = (date.getMonth() + 1) + '月' + date.getDate() + '日';
  return date.getFullYear() === now.getFullYear() ? day : date.getFullYear() + '年' + day;
}

/** Provider 图标种类。界面只显示图标，不显示具体模型名。 */
export type ProviderGlyph = 'claude' | 'openai' | 'gemini' | 'cursor' | 'generic' | 'none';

export function providerGlyph(providerInstanceId: string): ProviderGlyph {
  const id = providerInstanceId.trim().toLowerCase();
  if (!id) return 'none';
  if (id.includes('claude') || id.includes('anthropic')) return 'claude';
  if (id.includes('codex') || id.includes('openai') || id.includes('gpt')) return 'openai';
  if (id.includes('gemini') || id.includes('antigravity') || id.includes('google')) return 'gemini';
  if (id.includes('cursor')) return 'cursor';
  return 'generic';
}

/** 第二行左侧：失败时显示错误摘要（单行），否则显示环境名。 */
export function threadSubline(status: string, lastError: string, environmentLabel: string): { text: string; error: boolean } {
  const error = lastError.replace(/\s+/g, ' ').trim();
  if ((status === '失败' || status === '用量受限') && error) return { text: error, error: true };
  return { text: environmentLabel, error: false };
}
