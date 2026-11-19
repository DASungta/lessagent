import { record, objects, text, sequence } from './Wire';

export interface UsageWindow { id: string; label: string; remaining: number; resetsAt: string; }
export interface UsageAccount { id: string; label: string; driver: string; checkedAt: string; notice: string; windows: UsageWindow[]; }
export interface UsageBucketView { day: string; provider: string; model: string; tokens: number; costUsd: number; unpricedRecords: number; }
export interface UsageSummaryView { readAt: string; pricing: string; buckets: UsageBucketView[]; notices: string[]; }
export interface UsageReadConnection {
  ready: boolean;
  config: Record<string, Object>;
  generationValue(): number;
  canScope(scope: string): boolean | undefined;
  rpcRequest(method: string, payload: Object, timeoutMs?: number, fatalTimeout?: boolean): Promise<Object>;
}
function optionalText(value: Object): string { return typeof value === 'string' ? value : ''; }
function finite(value: Object): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) throw new Error('用量金额格式错误');
  return value;
}
export function usageInput(days: number, timeZone: string, now: number = Date.now()): Record<string, Object> {
  if (![1, 7, 30].includes(days) || !timeZone.trim()) throw new Error('用量日期范围无效');
  // Local calendar arithmetic keeps daily windows correct across DST changes.
  const end = new Date(now); const start = new Date(now); start.setDate(start.getDate() - days + 1);
  return { sinceDay: day(start), untilDay: day(end), timeZone, resolution: 'day', awaitRefresh: true };
}
function day(date: Date): string {
  return String(date.getFullYear()) + '-' + String(date.getMonth() + 1).padStart(2, '0') + '-' + String(date.getDate()).padStart(2, '0');
}
export function parseUsageSummary(value: Object): UsageSummaryView {
  const root = record(value);
  if (![4, 5, 6].includes(finite(root.contractVersion))) throw new Error('用量协议版本不兼容');
  const buckets = objects(root.buckets).map((value: Object): UsageBucketView => {
    const row = record(value); const totals = record(row.totals);
    const tokens = sequence(totals.uncachedInputTokens) + sequence(totals.cachedInputTokens) +
      sequence(totals.cacheCreationTokens) + sequence(totals.outputTokens);
    sequence(totals.reasoningTokens); // Reasoning is already included in output; never add it twice.
    return { day: text(row.day), provider: text(row.provider), model: text(row.model), tokens,
      costUsd: finite(row.costUsd), unpricedRecords: sequence(row.unpricedRecords) };
  });
  const notices: string[] = [];
  for (const value of objects(root.sources)) {
    const source = record(value);
    const notice = usageSourceNotice(text(source.status));
    if (notice && !notices.includes(notice)) notices.push(notice);
    const refreshing = '正在更新用量，当前显示上次读取的记录';
    if (source.refreshing === true && !notices.includes(refreshing)) notices.push(refreshing);
  }
  return { readAt: text(root.readAt), pricing: text(record(root.pricing).status), buckets, notices };
}
export function filterUsage(rows: UsageBucketView[], provider: string, model: string): UsageBucketView[] {
  return rows.filter((row: UsageBucketView) => (!provider || row.provider === provider) &&
    (!model || row.model.toLowerCase().includes(model.toLowerCase().trim())));
}
export function usageTotal(rows: UsageBucketView[]): UsageBucketView {
  const total: UsageBucketView = { day: '', provider: '', model: '', tokens: 0, costUsd: 0, unpricedRecords: 0 };
  rows.forEach((row: UsageBucketView) => { total.tokens += row.tokens; total.costUsd += row.costUsd; total.unpricedRecords += row.unpricedRecords; });
  return total;
}
export interface UsageDayView { day: string; tokens: number; costUsd: number; unpricedRecords: number; }
export function usageDays(rows: UsageBucketView[]): UsageDayView[] {
  const days = new Map<string, UsageDayView>();
  rows.forEach((row: UsageBucketView) => {
    let total = days.get(row.day);
    if (!total) { total = { day: row.day, tokens: 0, costUsd: 0, unpricedRecords: 0 }; days.set(row.day, total); }
    total.tokens += row.tokens; total.costUsd += row.costUsd; total.unpricedRecords += row.unpricedRecords;
  });
  return Array.from(days.values()).sort((a: UsageDayView, b: UsageDayView) => a.day.localeCompare(b.day));
}
export function usageDayScale(days: UsageDayView[], metric: string): number {
  return days.reduce((peak: number, day: UsageDayView) => Math.max(peak, metric === 'tokens' ? day.tokens : day.costUsd), 0);
}
function account(id: string, label: string, driver: string, value: Object): UsageAccount {
  const limits = record(value); let notice = ''; let unsupported = false;
  if (limits.unavailable !== undefined) {
    const unavailable = record(limits.unavailable);
    unsupported = unavailable.reason === 'unsupported';
    notice = unsupported ? '此账号未提供限额' : '查询失败；以下为上次已知限额';
  }
  if (limits.zeroSpendCap === true) notice += ' 月度支出上限为 $0';
  const windows: UsageWindow[] = objects(limits.windows).map((value: Object): UsageWindow => {
    const window = record(value); const used = finite(window.usedPercent);
    if (used < 0 || used > 100) notice += ' 服务端比例超出契约范围，按边界显示';
    return { id: text(window.id), label: text(window.label), remaining: Math.round(100 - Math.max(0, Math.min(100, used))), resetsAt: optionalText(window.resetsAt) };
  });
  return { id, label, driver, checkedAt: text(limits.checkedAt), notice, windows: unsupported ? [] : windows };
}
export function usageAccounts(value: Object): UsageAccount[] {
  const config = record(value); const accounts: UsageAccount[] = [];
  for (const value of objects(config.providers)) {
    const provider = record(value);
    if (provider.usageLimits !== undefined) accounts.push(account('provider:' + text(provider.instanceId),
      optionalText(provider.displayName) || text(provider.driver), text(provider.driver), provider.usageLimits));
  }
  if (config.usageLimitSources !== undefined) {
    for (const value of objects(config.usageLimitSources)) {
      const source = record(value);
      for (const value of objects(source.accounts)) {
        const row = record(value);
        const item = account(text(source.id) + ':' + text(row.id), text(source.label) + ' · ' +
          (optionalText(row.email) || text(row.id)), text(row.driver), row.usageLimits);
        if (source.error !== undefined) item.notice = '来源查询失败，显示上次快照。 ' + item.notice;
        accounts.push(item);
      }
    }
  }
  return accounts;
}
export async function readUsageSummary(connection: UsageReadConnection, input: Record<string, Object>): Promise<UsageSummaryView> {
  if (!connection.ready || connection.canScope('diagnostics:read') === false) throw new Error('需要已连接环境和诊断读取权限');
  const generation = connection.generationValue();
  const settings = record(connection.config.settings);
  const request: Record<string, Object> = { ...input };
  if (settings.usageModelFilter !== undefined && settings.usageModelFilter !== null) request.modelFilter = settings.usageModelFilter;
  const result = await connection.rpcRequest('server.getUsageSummary', request, 60000, false);
  if (!connection.ready || generation !== connection.generationValue()) throw new Error('环境已变化，请重新打开用量');
  const summary = parseUsageSummary(result);
  if (request.modelFilter !== undefined && record(result).modelFilter === undefined) {
    summary.notices.push('服务端未确认模型排除规则，当前返回可能包含被排除模型');
  }
  return summary;
}

export function compactUsageTokens(value: number): string {
  if (value >= 100000000) return (value / 100000000).toFixed(2).replace(/\.?0+$/, '') + '亿';
  if (value >= 10000) return (value / 10000).toFixed(2).replace(/\.?0+$/, '') + '万';
  return String(value);
}
export function usagePricingLabel(status: string): string {
  if (status === 'fresh') return '最新价格';
  if (status === 'cached') return '使用已缓存价格';
  if (status === 'unavailable') return '价格暂不可用，金额可能不完整';
  return '价格状态未知';
}
export function usageSourceNotice(status: string): string {
  if (status === 'ok') return '';
  if (status === 'missing') return '部分账号尚无可读取的用量记录';
  if (status === 'partial') return '部分用量记录未能读取，汇总可能不完整';
  if (status === 'failed' || status === 'error') return '部分用量读取失败，请稍后刷新';
  if (status === 'stale') return '部分用量尚未更新，当前显示上次读取的记录';
  return '部分用量状态未知，汇总可能不完整';
}
