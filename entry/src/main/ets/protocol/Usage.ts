import { record, objects, text, sequence } from './Wire';

export const USAGE_CONTRACT_VERSION: number = 6;
export const USAGE_MERGE_COMPATIBLE_SINCE: number = 4;
export const CHATGPT_USAGE_URL: string = 'https://chatgpt.com/#settings/Usage';

export const USAGE_PROVIDER_ORDER: string[] = [
  'codex',
  'claude',
  'grok',
  'cursor',
  'opencode',
  'antigravity',
  'pi',
  'muse',
];

const PROVIDER_LABELS: Record<string, string> = {
  claude: 'Claude Code',
  claudeAgent: 'Claude Code',
  codex: 'Codex',
  grok: 'Grok Build',
  cursor: 'Cursor',
  opencode: 'OpenCode',
  antigravity: 'Antigravity',
  pi: 'Pi',
  muse: 'Muse Code',
};

const MINUTE_MS: number = 60000;
const HOUR_MS: number = 3600000;
const DAY_MS: number = 86400000;

export interface UsageWindow {
  id: string;
  label: string;
  remaining: number;
  resetsAt: string;
}

export interface UsageAccount {
  id: string;
  label: string;
  driver: string;
  checkedAt: string;
  notice: string;
  windows: UsageWindow[];
}

export interface UsageBucketView {
  day: string;
  provider: string;
  model: string;
  tokens: number;
  costUsd: number;
  unpricedRecords: number;
  hourStart?: string;
  sourcePath?: string;
  uncachedInputTokens?: number;
  cachedInputTokens?: number;
  cacheCreationTokens?: number;
  outputTokens?: number;
  reasoningTokens?: number;
  cacheSavingsUsd?: number;
  categoryCostInput?: number;
  categoryCostCacheRead?: number;
  categoryCostCacheWrite?: number;
  categoryCostOutput?: number;
  fastCostUsd?: number;
  ultrafastCostUsd?: number;
  speedPremiumUsd?: number;
  costSource?: string;
  records?: number;
  unpricedTokens?: number;
  sessions?: number;
}

export interface UsageSourceView {
  hostId: string;
  provider: string;
  resolvedHomePath: string;
  volumeId: string;
  physicalSourceId: string;
  status: string;
  scannedFiles: number;
  skippedFiles: number;
  malformedRecords: number;
  distinctSessions: number;
  message: string;
  refreshing: boolean;
}

export interface UsageSummaryView {
  readAt: string;
  pricing: string;
  buckets: UsageBucketView[];
  notices: string[];
  contractVersion?: number;
  sinceDay?: string;
  untilDay?: string;
  timeZone?: string;
  sources?: UsageSourceView[];
  modelFilterKey?: string;
}

export interface UsageReadConnection {
  ready: boolean;
  config: Record<string, Object>;
  generationValue(): number;
  canScope(scope: string): boolean | undefined;
  rpcRequest(method: string, payload: Object, timeoutMs?: number, fatalTimeout?: boolean): Promise<Object>;
}

export interface UsageDayView {
  day: string;
  tokens: number;
  costUsd: number;
  unpricedRecords: number;
}

export interface UsageWindowSpec {
  sinceDay: string;
  untilDay: string;
  timeZone: string;
  resolution: 'day' | 'hour';
  sinceTime: string;
  untilTime: string;
}

export interface UsageWindowPayloadOptions {
  awaitRefresh?: boolean;
  provisional?: boolean;
}

export interface EnvironmentUsageInput {
  environmentId: string;
  label: string;
  summary: UsageSummaryView;
}

export interface UsageProviderTotals {
  provider: string;
  costUsd: number;
  totalTokens: number;
  records: number;
  sessions: number;
  costShare: number;
  tokenShare: number;
}

export interface UsageModelTotals {
  model: string;
  provider: string;
  costUsd: number;
  totalTokens: number;
  records: number;
  unpricedRecords: number;
  unpricedTokens: number;
  costShare: number;
  tokenShare: number;
  costUnknown: boolean;
}

export interface UsagePeriodProviderValue {
  provider: string;
  costUsd: number;
  totalTokens: number;
}

export interface UsagePeriodTotals {
  period: string;
  costUsd: number;
  totalTokens: number;
  byProvider: UsagePeriodProviderValue[];
}

export interface UsageCategoryCostTotals {
  input: number;
  cacheRead: number;
  cacheWrite: number;
  output: number;
  unsplit: number;
}

export interface UsageSpeedCostTotals {
  standard: number;
  fast: number;
  ultrafast: number;
  premium: number;
}

export interface UsageContractMismatch {
  environmentId: string;
  label: string;
  direction: 'serverBehind' | 'clientBehind';
  contractVersion: number;
}

export interface MergedUsageView {
  costUsd: number;
  uncachedInputTokens: number;
  cachedInputTokens: number;
  cacheCreationTokens: number;
  outputTokens: number;
  reasoningTokens: number;
  totalTokens: number;
  records: number;
  sessions: number;
  providers: UsageProviderTotals[];
  models: UsageModelTotals[];
  daily: UsagePeriodTotals[];
  hourly: UsagePeriodTotals[];
  cacheSavingsUsd: number;
  unpricedShare: number;
  providerReportedShare: number;
  modelPricedShare: number;
  categoryCost: UsageCategoryCostTotals;
  speedCost: UsageSpeedCostTotals;
  duplicateSources: string[];
  contributingEnvironments: string[];
  contractMismatches: UsageContractMismatch[];
}

export interface UsageChartSegment {
  provider: string;
  value: number;
}

export interface UsageChartBar {
  period: string;
  values: UsageChartSegment[];
  total: number;
}

export interface LimitEnvironmentSnapshot {
  environmentId: string;
  label: string;
  config: Record<string, Object>;
}

export interface PooledLimitWindowEntry {
  id: string;
  kind: string;
  label: string;
  usedPercent: number;
  remaining: number;
  resetsAt: string;
  windowDurationMins: number;
  outOfRange: boolean;
}

export interface UsageResetCreditOption {
  creditId: string;
  label: string;
  description: string;
  availableCount: number;
  expiresAt: string;
}

export interface UsageResetCredits {
  availableCount: number;
  nextExpiresAt: string;
  nextCreditId: string;
  options: UsageResetCreditOption[];
}

export interface PooledLimitEnvironmentRef {
  environmentId: string;
  label: string;
}

export interface PooledLimitAccount {
  key: string;
  driver: string;
  displayName: string;
  email: string;
  plan: string;
  accentColor: string;
  environments: PooledLimitEnvironmentRef[];
  sourceLabel: string;
  checkedAt: string;
  zeroSpendCap: boolean;
  windows: PooledLimitWindowEntry[];
  resetCredits?: UsageResetCredits;
  redeemEnvironmentId: string;
  redeemPayload?: Record<string, Object>;
}

export interface PooledLimitColumn {
  account: PooledLimitAccount;
  window?: PooledLimitWindowEntry;
  refillPercent: number;
}

export interface PooledLimitReset {
  accountKey: string;
  resetsAt: string;
  at: number;
  restoresPercent: number;
}

export interface PooledLimitWindow {
  id: string;
  kind: string;
  label: string;
  description: string;
  hideLabel: boolean;
  columns: PooledLimitColumn[];
  remainingPercent: number;
  usedPercent: number;
  pace: string;
  resets: PooledLimitReset[];
}

export interface PooledLimitGroup {
  driver: string;
  accounts: PooledLimitAccount[];
  windows: PooledLimitWindow[];
}

export interface UsageExternalLink {
  label: string;
  url: string;
  message: string;
  accounts: string[];
}

export interface ResetCreditChoiceView {
  key: string;
  summary: string;
  actionLabel: string;
  confirmDescription: string;
  availableCount: number;
  payload: Record<string, Object>;
}

export interface ResetCreditConsumeOutcome {
  outcome: string;
  warning: string;
}

function optionalText(value: Object | undefined): string {
  return typeof value === 'string' ? value : '';
}

function finite(value: Object | undefined): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) throw new Error('用量金额格式错误');
  return value;
}

function optionalFinite(value: Object | undefined): number {
  if (value === undefined || value === null) return 0;
  return finite(value);
}

function optionalNonNegativeInt(value: Object | undefined): number {
  if (value === undefined || value === null) return 0;
  return sequence(value);
}

export function usageProviderKind(driver: string): string {
  if (driver === 'claudeAgent') return 'claude';
  return USAGE_PROVIDER_ORDER.includes(driver) ? driver : '';
}

export function usageProviderLabel(provider: string): string {
  return PROVIDER_LABELS[provider] || provider;
}

function day(date: Date): string {
  return (
    String(date.getFullYear()) +
    '-' +
    String(date.getMonth() + 1).padStart(2, '0') +
    '-' +
    String(date.getDate()).padStart(2, '0')
  );
}

function dayInTimeZone(ms: number, timeZone: string): string {
  const date = new Date(ms);
  try {
    const formatted = new Intl.DateTimeFormat('en-CA', {
      timeZone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).format(date);
    if (/^\d{4}-\d{2}-\d{2}$/.test(formatted)) return formatted;
  } catch (_) {}
  return day(date);
}

export function usageInput(days: number, timeZone: string, now: number = Date.now()): Record<string, Object> {
  if (![1, 7, 30, 90].includes(days) || !timeZone.trim()) throw new Error('用量日期范围无效');
  const end = new Date(now);
  const start = new Date(now);
  start.setDate(start.getDate() - days + 1);
  return { sinceDay: day(start), untilDay: day(end), timeZone, resolution: 'day', awaitRefresh: true };
}

export function makeUsageWindow(
  days: number,
  timeZone: string,
  now: number = Date.now(),
): UsageWindowSpec {
  if (![1, 7, 30, 90].includes(days) || !timeZone.trim()) throw new Error('用量日期范围无效');
  if (days === 1) {
    const untilTimeMs = Math.floor(now / MINUTE_MS) * MINUTE_MS;
    const sinceTimeMs = untilTimeMs - 24 * HOUR_MS;
    return {
      sinceDay: dayInTimeZone(sinceTimeMs, timeZone),
      untilDay: dayInTimeZone(untilTimeMs, timeZone),
      timeZone,
      resolution: 'hour',
      sinceTime: new Date(sinceTimeMs).toISOString(),
      untilTime: new Date(untilTimeMs).toISOString(),
    };
  }
  const untilDay = dayInTimeZone(now, timeZone);
  const parts = untilDay.split('-').map((part: string) => Number.parseInt(part, 10));
  const year = parts[0] || 0;
  const month = parts[1] || 1;
  const dayOfMonth = parts[2] || 1;
  const start = new Date(Date.UTC(year, month - 1, dayOfMonth - (days - 1)));
  return {
    sinceDay: start.toISOString().slice(0, 10),
    untilDay,
    timeZone,
    resolution: 'day',
    sinceTime: '',
    untilTime: '',
  };
}

export function usageWindowPayload(
  window: UsageWindowSpec,
  options?: UsageWindowPayloadOptions,
): Record<string, Object> {
  const payload: Record<string, Object> = {
    sinceDay: window.sinceDay,
    untilDay: window.untilDay,
    timeZone: window.timeZone,
    resolution: window.resolution,
  };
  if (window.sinceTime) payload.sinceTime = window.sinceTime;
  if (window.untilTime) payload.untilTime = window.untilTime;
  if (options?.awaitRefresh !== undefined) payload.awaitRefresh = options.awaitRefresh;
  if (options?.provisional !== undefined) payload.provisional = options.provisional;
  return payload;
}

export function enumerateUsageDays(sinceDay: string, untilDay: string): string[] {
  const result: string[] = [];
  const start = Date.parse(sinceDay + 'T00:00:00Z');
  const end = Date.parse(untilDay + 'T00:00:00Z');
  if (!Number.isFinite(start) || !Number.isFinite(end) || end < start) return result;
  for (let cursor = start; cursor <= end; cursor += DAY_MS) {
    result.push(new Date(cursor).toISOString().slice(0, 10));
  }
  return result;
}

export function enumerateUsageHourStarts(sinceTime: string, untilTime: string): string[] {
  const result: string[] = [];
  const start = Date.parse(sinceTime);
  const end = Date.parse(untilTime);
  if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start) return result;
  for (let cursor = start; cursor < end; cursor += HOUR_MS) {
    result.push(new Date(cursor).toISOString());
  }
  return result;
}

export function parseUsageSummaryContract(value: Object): number {
  const root = record(value);
  return finite(root.contractVersion);
}

export function parseUsageSummary(value: Object): UsageSummaryView {
  const root = record(value);
  const contractVersion = finite(root.contractVersion);
  if (contractVersion < USAGE_MERGE_COMPATIBLE_SINCE || contractVersion > USAGE_CONTRACT_VERSION) {
    throw new Error('用量协议版本不兼容');
  }
  const buckets = objects(root.buckets).map((raw: Object): UsageBucketView => {
    const row = record(raw);
    const totals = record(row.totals);
    const uncachedInputTokens = sequence(totals.uncachedInputTokens);
    const cachedInputTokens = sequence(totals.cachedInputTokens);
    const cacheCreationTokens = sequence(totals.cacheCreationTokens);
    const outputTokens = sequence(totals.outputTokens);
    const reasoningTokens = sequence(totals.reasoningTokens); // Reasoning is already included in output; never add it twice.
    const tokens = uncachedInputTokens + cachedInputTokens + cacheCreationTokens + outputTokens;
    const category =
      row.categoryCostUsd !== undefined && row.categoryCostUsd !== null ? record(row.categoryCostUsd) : undefined;
    return {
      day: text(row.day),
      provider: text(row.provider),
      model: text(row.model),
      tokens,
      costUsd: finite(row.costUsd),
      unpricedRecords: sequence(row.unpricedRecords),
      hourStart: optionalText(row.hourStart),
      sourcePath: optionalText(row.sourcePath),
      uncachedInputTokens,
      cachedInputTokens,
      cacheCreationTokens,
      outputTokens,
      reasoningTokens,
      cacheSavingsUsd: optionalFinite(row.cacheSavingsUsd),
      categoryCostInput: category ? optionalFinite(category.input) : 0,
      categoryCostCacheRead: category ? optionalFinite(category.cacheRead) : 0,
      categoryCostCacheWrite: category ? optionalFinite(category.cacheWrite) : 0,
      categoryCostOutput: category ? optionalFinite(category.output) : 0,
      fastCostUsd: optionalFinite(row.fastCostUsd),
      ultrafastCostUsd: optionalFinite(row.ultrafastCostUsd),
      speedPremiumUsd: optionalFinite(row.speedPremiumUsd),
      costSource: optionalText(row.costSource),
      records: optionalNonNegativeInt(row.records),
      unpricedTokens: row.unpricedTokens !== undefined && row.unpricedTokens !== null ? sequence(row.unpricedTokens) : undefined,
      sessions: optionalNonNegativeInt(row.sessions),
    };
  });

  const notices: string[] = [];
  const sources: UsageSourceView[] = [];
  for (const raw of objects(root.sources)) {
    const source = record(raw);
    const status = text(source.status);
    const fp =
      source.fingerprint !== undefined && source.fingerprint !== null ? record(source.fingerprint) : undefined;
    sources.push({
      hostId: fp ? optionalText(fp.hostId) : '',
      provider: fp ? optionalText(fp.provider) : '',
      resolvedHomePath: fp ? optionalText(fp.resolvedHomePath) : '',
      volumeId: fp ? optionalText(fp.volumeId) : '',
      physicalSourceId: fp ? optionalText(fp.physicalSourceId) : '',
      status,
      scannedFiles: optionalNonNegativeInt(source.scannedFiles),
      skippedFiles: optionalNonNegativeInt(source.skippedFiles),
      malformedRecords: optionalNonNegativeInt(source.malformedRecords),
      distinctSessions: optionalNonNegativeInt(source.distinctSessions),
      message: optionalText(source.message),
      refreshing: source.refreshing === true,
    });
    const notice = usageSourceNotice(status);
    if (notice && !notices.includes(notice)) notices.push(notice);
    const refreshing = '正在更新用量，当前显示上次读取的记录';
    if (source.refreshing === true && !notices.includes(refreshing)) notices.push(refreshing);
  }

  return {
    contractVersion,
    readAt: text(root.readAt),
    sinceDay: optionalText(root.sinceDay),
    untilDay: optionalText(root.untilDay),
    timeZone: optionalText(root.timeZone),
    pricing: text(record(root.pricing).status),
    buckets,
    sources,
    notices,
    modelFilterKey:
      root.modelFilter !== undefined && root.modelFilter !== null ? JSON.stringify(root.modelFilter) : '',
  };
}

export function filterUsage(rows: UsageBucketView[], provider: string, model: string): UsageBucketView[] {
  return rows.filter(
    (row: UsageBucketView) =>
      (!provider || row.provider === provider) &&
      (!model || row.model.toLowerCase().includes(model.toLowerCase().trim())),
  );
}

export function usageTotal(rows: UsageBucketView[]): UsageBucketView {
  const total: UsageBucketView = { day: '', provider: '', model: '', tokens: 0, costUsd: 0, unpricedRecords: 0 };
  rows.forEach((row: UsageBucketView) => {
    total.tokens += row.tokens;
    total.costUsd += row.costUsd;
    total.unpricedRecords += row.unpricedRecords;
  });
  return total;
}

export function usageDays(rows: UsageBucketView[]): UsageDayView[] {
  const days = new Map<string, UsageDayView>();
  rows.forEach((row: UsageBucketView) => {
    let total = days.get(row.day);
    if (!total) {
      total = { day: row.day, tokens: 0, costUsd: 0, unpricedRecords: 0 };
      days.set(row.day, total);
    }
    total.tokens += row.tokens;
    total.costUsd += row.costUsd;
    total.unpricedRecords += row.unpricedRecords;
  });
  return Array.from(days.values()).sort((a: UsageDayView, b: UsageDayView) => a.day.localeCompare(b.day));
}

export function usageDayScale(days: UsageDayView[], metric: string): number {
  return days.reduce(
    (peak: number, dayItem: UsageDayView) => Math.max(peak, metric === 'tokens' ? dayItem.tokens : dayItem.costUsd),
    0,
  );
}

function account(id: string, label: string, driver: string, value: Object): UsageAccount {
  const limits = record(value);
  let notice = '';
  let unsupported = false;
  if (limits.unavailable !== undefined) {
    const unavailable = record(limits.unavailable);
    unsupported = unavailable.reason === 'unsupported';
    notice = unsupported ? '此账号未提供限额' : '查询失败；以下为上次已知限额';
  }
  if (limits.zeroSpendCap === true) notice += ' 月度支出上限为 $0';
  const windows: UsageWindow[] = objects(limits.windows).map((raw: Object): UsageWindow => {
    const window = record(raw);
    const used = finite(window.usedPercent);
    if (used < 0 || used > 100) notice += ' 服务端比例超出契约范围，按边界显示';
    return {
      id: text(window.id),
      label: text(window.label),
      remaining: Math.round(100 - Math.max(0, Math.min(100, used))),
      resetsAt: optionalText(window.resetsAt),
    };
  });
  return { id, label, driver, checkedAt: text(limits.checkedAt), notice, windows: unsupported ? [] : windows };
}

export function usageAccounts(value: Object): UsageAccount[] {
  const config = record(value);
  const accounts: UsageAccount[] = [];
  for (const raw of objects(config.providers)) {
    const provider = record(raw);
    if (provider.usageLimits !== undefined) {
      accounts.push(
        account(
          'provider:' + text(provider.instanceId),
          optionalText(provider.displayName) || text(provider.driver),
          text(provider.driver),
          provider.usageLimits,
        ),
      );
    }
  }
  if (config.usageLimitSources !== undefined) {
    for (const rawSource of objects(config.usageLimitSources)) {
      const source = record(rawSource);
      for (const rawAccount of objects(source.accounts)) {
        const row = record(rawAccount);
        const item = account(
          text(source.id) + ':' + text(row.id),
          text(source.label) + ' · ' + (optionalText(row.email) || text(row.id)),
          text(row.driver),
          row.usageLimits,
        );
        if (source.error !== undefined) item.notice = '来源查询失败，显示上次快照。 ' + item.notice;
        accounts.push(item);
      }
    }
  }
  return accounts;
}

export async function readUsageSummary(
  connection: UsageReadConnection,
  input: Record<string, Object>,
): Promise<UsageSummaryView> {
  if (!connection.ready || connection.canScope('diagnostics:read') === false) {
    throw new Error('需要已连接环境和诊断读取权限');
  }
  const generation = connection.generationValue();
  const settings =
    connection.config.settings !== undefined && connection.config.settings !== null
      ? record(connection.config.settings)
      : {};
  const request: Record<string, Object> = { ...input };
  if (settings.usageModelFilter !== undefined && settings.usageModelFilter !== null) {
    request.modelFilter = settings.usageModelFilter;
  }
  const result = await connection.rpcRequest('server.getUsageSummary', request, 60000, false);
  if (!connection.ready || generation !== connection.generationValue()) {
    throw new Error('环境已变化，请重新打开用量');
  }
  const summary = parseUsageSummary(result);
  if (request.modelFilter !== undefined && record(result).modelFilter === undefined) {
    summary.notices.push('服务端未确认模型排除规则，当前返回可能包含被排除模型');
  }
  return summary;
}

export async function readUsageSummaryStep(
  connection: UsageReadConnection,
  input: Record<string, Object>,
): Promise<UsageSummaryView> {
  return readUsageSummary(connection, input);
}

export function compactUsageTokens(value: number): string {
  if (value >= 100000000) return (value / 100000000).toFixed(2).replace(/\.?0+$/, '') + '亿';
  if (value >= 10000) return (value / 10000).toFixed(2).replace(/\.?0+$/, '') + '万';
  return String(value);
}

export function formatUsageCount(value: number): string {
  const rounded = Math.round(value);
  const sign = rounded < 0 ? '-' : '';
  return sign + String(Math.abs(rounded)).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

export function formatUsageUsd(value: number): string {
  if (!Number.isFinite(value)) return '$0.00';
  if (Math.abs(value) < 0.005) return '$0.00';
  const sign = value < 0 ? '-$' : '$';
  const parts = Math.abs(value).toFixed(2).split('.');
  const intPart = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  return sign + intPart + '.' + parts[1];
}

function trimCompactTokenNumber(value: number): string {
  const abs = Math.abs(value);
  const digits = abs >= 100 ? 0 : abs >= 10 ? 1 : 2;
  return value.toFixed(digits).replace(/\.0+$/, '');
}

export function formatUsageTokens(value: number): string {
  if (!Number.isFinite(value)) return '0';
  if (Math.abs(Math.round(value)) < 1000) return formatUsageCount(value);
  let scaled = value / 1000;
  let unit = 0;
  const suffixes: string[] = ['K', 'M', 'B', 'T'];
  while (Math.abs(Number(trimCompactTokenNumber(scaled))) >= 1000 && unit < suffixes.length - 1) {
    scaled /= 1000;
    unit += 1;
  }
  return trimCompactTokenNumber(scaled) + suffixes[unit];
}

export function formatUsagePercent(share: number, digits: number = 1): string {
  if (!Number.isFinite(share)) return '0%';
  const percent = share * 100;
  const smallest = Math.pow(10, -digits);
  if (percent > 0 && percent < smallest) return '<' + smallest.toFixed(digits) + '%';
  return percent.toFixed(digits) + '%';
}

export function formatUsageDayShort(dayStr: string): string {
  const parts = dayStr.split('-');
  if (parts.length !== 3) return dayStr;
  const month = Number.parseInt(parts[1], 10);
  const dayOfMonth = Number.parseInt(parts[2], 10);
  if (!Number.isFinite(month) || !Number.isFinite(dayOfMonth)) return dayStr;
  return month + '月' + dayOfMonth + '日';
}

export function formatUsageHourShort(iso: string, timeZone: string = ''): string {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return iso;
  try {
    const formatter = new Intl.DateTimeFormat('en-GB', {
      ...(timeZone ? { timeZone } : {}),
      hour: '2-digit',
      hourCycle: 'h23',
    });
    const hourText = formatter.format(date).replace(/[^\d]/g, '');
    if (hourText.length > 0) return hourText.padStart(2, '0') + ':00';
  } catch (_) {}
  return String(date.getHours()).padStart(2, '0') + ':00';
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

export function usageSourceMessages(sources: UsageSourceView[]): string[] {
  const messages: string[] = [];
  const malformedKeys: string[] = [];
  const malformedCounts: number[] = [];
  for (const source of sources) {
    if (
      source.status !== 'partial' &&
      source.status !== 'failed' &&
      source.provider !== 'cursor' &&
      !(source.status === 'missing' && source.malformedRecords > 0)
    ) {
      continue;
    }
    let msg = source.message;
    if (source.malformedRecords > 0) {
      const key = JSON.stringify([source.hostId, source.provider, source.resolvedHomePath, source.volumeId]);
      const idx = malformedKeys.indexOf(key);
      if (idx < 0) {
        malformedKeys.push(key);
        malformedCounts.push(source.malformedRecords);
      } else {
        malformedCounts[idx] = Math.max(malformedCounts[idx], source.malformedRecords);
      }
      const suffix =
        source.malformedRecords +
        ' malformed or inconsistent usage record(s) were skipped; usage may be incomplete.';
      if (msg.endsWith(suffix)) msg = msg.slice(0, msg.length - suffix.length).trim();
    }
    if (msg && !messages.includes(msg)) messages.push(msg);
  }
  const totalMalformed = malformedCounts.reduce((acc: number, count: number) => acc + count, 0);
  if (totalMalformed > 0) {
    messages.push('已跳过 ' + totalMalformed + ' 条格式异常的用量记录，汇总可能不完整。');
  }
  return messages;
}

function sourceFingerprintKey(source: UsageSourceView): string {
  return [source.hostId, source.provider, source.resolvedHomePath, source.volumeId].join(' ');
}

function createSourceIdentityResolver(
  environments: EnvironmentUsageInput[],
): (source: UsageSourceView) => string {
  const parent = new Map<string, string>();
  const find = (key: string): string => {
    const next = parent.get(key);
    if (next === undefined || next === key) return key;
    const root = find(next);
    parent.set(key, root);
    return root;
  };
  for (const env of environments) {
    for (const source of env.summary.sources || []) {
      if (!source.physicalSourceId) continue;
      const legacy = find(sourceFingerprintKey(source));
      const physical = find('\u0000' + source.provider + '\u0000' + source.physicalSourceId);
      if (legacy !== physical) parent.set(legacy, physical);
    }
  }
  return (source: UsageSourceView): string => find(sourceFingerprintKey(source));
}

function hasFingerprintedSources(summary: UsageSummaryView): boolean {
  const list = summary.sources || [];
  return list.some((s: UsageSourceView) => !!s.hostId || !!s.resolvedHomePath);
}

function bucketsForSource(summary: UsageSummaryView, source: UsageSourceView): UsageBucketView[] {
  const providerSources = (summary.sources || []).filter(
    (entry: UsageSourceView) => entry.provider === source.provider,
  );
  return summary.buckets.filter(
    (bucket: UsageBucketView) =>
      bucket.provider === source.provider &&
      (bucket.sourcePath === source.resolvedHomePath ||
        (!bucket.sourcePath && providerSources.length === 1)),
  );
}

function mergeBucketCellKey(bucket: UsageBucketView): string {
  return JSON.stringify([bucket.day, bucket.hourStart || null, bucket.provider, bucket.model]);
}

interface PeriodAccumulator {
  period: string;
  costUsd: number;
  totalTokens: number;
  byProvider: Map<string, UsagePeriodProviderValue>;
}

interface ProviderAccumulator {
  costUsd: number;
  totalTokens: number;
  records: number;
  sessions: number;
}

interface ModelAccumulator {
  provider: string;
  model: string;
  costUsd: number;
  totalTokens: number;
  records: number;
  unpricedRecords: number;
  unpricedTokens: number;
}

function upsertPeriodValue(
  map: Map<string, PeriodAccumulator>,
  period: string,
  provider: string,
  costUsd: number,
  tokens: number,
): void {
  let entry = map.get(period);
  if (!entry) {
    entry = { period, costUsd: 0, totalTokens: 0, byProvider: new Map<string, UsagePeriodProviderValue>() };
    map.set(period, entry);
  }
  entry.costUsd += costUsd;
  entry.totalTokens += tokens;
  let provEntry = entry.byProvider.get(provider);
  if (!provEntry) {
    provEntry = { provider, costUsd: 0, totalTokens: 0 };
    entry.byProvider.set(provider, provEntry);
  }
  provEntry.costUsd += costUsd;
  provEntry.totalTokens += tokens;
}

function finalizePeriods(map: Map<string, PeriodAccumulator>): UsagePeriodTotals[] {
  return Array.from(map.values())
    .map((entry: PeriodAccumulator): UsagePeriodTotals => ({
      period: entry.period,
      costUsd: entry.costUsd,
      totalTokens: entry.totalTokens,
      byProvider: Array.from(entry.byProvider.values()),
    }))
    .sort((a: UsagePeriodTotals, b: UsagePeriodTotals) => a.period.localeCompare(b.period));
}

export function mergeUsageSummaries(
  environments: EnvironmentUsageInput[],
  expectedContractVersion: number = USAGE_CONTRACT_VERSION,
): MergedUsageView {
  const empty: MergedUsageView = {
    costUsd: 0,
    uncachedInputTokens: 0,
    cachedInputTokens: 0,
    cacheCreationTokens: 0,
    outputTokens: 0,
    reasoningTokens: 0,
    totalTokens: 0,
    records: 0,
    sessions: 0,
    providers: [],
    models: [],
    daily: [],
    hourly: [],
    cacheSavingsUsd: 0,
    unpricedShare: 0,
    providerReportedShare: 0,
    modelPricedShare: 0,
    categoryCost: { input: 0, cacheRead: 0, cacheWrite: 0, output: 0, unsplit: 0 },
    speedCost: { standard: 0, fast: 0, ultrafast: 0, premium: 0 },
    duplicateSources: [],
    contributingEnvironments: [],
    contractMismatches: [],
  };
  if (environments.length === 0) return empty;

  const current: EnvironmentUsageInput[] = [];
  const contractMismatches: UsageContractMismatch[] = [];
  for (const env of environments) {
    const version =
      env.summary.contractVersion !== undefined ? env.summary.contractVersion : expectedContractVersion;
    if (version >= USAGE_MERGE_COMPATIBLE_SINCE && version <= expectedContractVersion) {
      current.push(env);
    } else {
      contractMismatches.push({
        environmentId: env.environmentId,
        label: env.label,
        direction: version < expectedContractVersion ? 'serverBehind' : 'clientBehind',
        contractVersion: version,
      });
    }
  }

  const sourceKey = createSourceIdentityResolver(current);
  const ownerScanByFingerprint = new Map<string, { env: EnvironmentUsageInput; source: UsageSourceView }>();
  const seenBucketKeysByFingerprint = new Map<string, Set<string>>();
  const supplementalBucketsByEnvironment = new Map<string, Set<UsageBucketView>>();
  const sessionsByFingerprint = new Map<string, number>();
  const duplicates: string[] = [];

  const ordered = [...current].sort(
    (a: EnvironmentUsageInput, b: EnvironmentUsageInput) =>
      (Date.parse(b.summary.readAt) || 0) - (Date.parse(a.summary.readAt) || 0) ||
      a.environmentId.localeCompare(b.environmentId),
  );

  for (const status of ['ok', 'partial', 'failed']) {
    for (const env of ordered) {
      for (const source of env.summary.sources || []) {
        if ((!source.hostId && !source.resolvedHomePath) || source.status !== status) continue;
        const key = sourceKey(source);
        if (ownerScanByFingerprint.has(key)) {
          duplicates.push(env.label + ': ' + source.resolvedHomePath);
          continue;
        }
        ownerScanByFingerprint.set(key, { env, source });
        sessionsByFingerprint.set(key, source.distinctSessions);
      }
    }
  }

  for (const env of ordered) {
    for (const source of env.summary.sources || []) {
      if ((!source.hostId && !source.resolvedHomePath) || source.status !== 'partial') continue;
      const key = sourceKey(source);
      const owner = ownerScanByFingerprint.get(key);
      if (
        !owner ||
        owner.source.status !== 'ok' ||
        Date.parse(env.summary.readAt) <= Date.parse(owner.env.summary.readAt) ||
        (env.summary.modelFilterKey || '') !== (owner.env.summary.modelFilterKey || '')
      ) {
        continue;
      }
      let seen = seenBucketKeysByFingerprint.get(key);
      if (!seen) {
        seen = new Set<string>(
          bucketsForSource(owner.env.summary, owner.source).map(mergeBucketCellKey),
        );
        seenBucketKeysByFingerprint.set(key, seen);
      }
      let supplemental = supplementalBucketsByEnvironment.get(env.environmentId);
      if (!supplemental) {
        supplemental = new Set<UsageBucketView>();
      }
      let added = false;
      for (const bucket of bucketsForSource(env.summary, source)) {
        const cell = mergeBucketCellKey(bucket);
        if (seen.has(cell)) continue;
        seen.add(cell);
        supplemental.add(bucket);
        added = true;
      }
      if (!added) continue;
      supplementalBucketsByEnvironment.set(env.environmentId, supplemental);
      sessionsByFingerprint.set(
        key,
        Math.max(sessionsByFingerprint.get(key) || 0, source.distinctSessions),
      );
    }
  }

  let costUsd = 0;
  let uncachedInputTokens = 0;
  let cachedInputTokens = 0;
  let cacheCreationTokens = 0;
  let outputTokens = 0;
  let reasoningTokens = 0;
  let totalTokensSum = 0;
  let records = 0;
  let sessions = 0;
  let cacheSavingsUsd = 0;
  let providerReportedRecords = 0;
  let unpricedRecords = 0;
  let catInput = 0;
  let catCacheRead = 0;
  let catCacheWrite = 0;
  let catOutput = 0;
  let fastCost = 0;
  let ultrafastCost = 0;
  let premiumCost = 0;

  const providerAccumulator = new Map<string, ProviderAccumulator>();
  const modelAccumulator = new Map<string, ModelAccumulator>();
  const dailyAccumulator = new Map<string, PeriodAccumulator>();
  const hourlyAccumulator = new Map<string, PeriodAccumulator>();
  const contributingEnvironments: string[] = [];

  for (const env of current) {
    let ownedBuckets: UsageBucketView[];
    const sessionsByProvider = new Map<string, number>();

    if (hasFingerprintedSources(env.summary)) {
      const ownedProviders = new Set<string>();
      const ownedSources = new Set<string>();
      for (const source of env.summary.sources || []) {
        if (source.status === 'missing' || (!source.hostId && !source.resolvedHomePath)) continue;
        const key = sourceKey(source);
        const winner = ownerScanByFingerprint.get(key);
        if (winner && winner.source === source) {
          ownedProviders.add(source.provider);
          ownedSources.add(source.provider + '\u0000' + source.resolvedHomePath);
          const count = sessionsByFingerprint.get(key) ?? source.distinctSessions;
          sessionsByProvider.set(source.provider, (sessionsByProvider.get(source.provider) || 0) + count);
        }
      }
      const supplemental = supplementalBucketsByEnvironment.get(env.environmentId) || new Set<UsageBucketView>();
      ownedBuckets = env.summary.buckets.filter(
        (bucket: UsageBucketView) =>
          supplemental.has(bucket) ||
          (!bucket.sourcePath
            ? ownedProviders.has(bucket.provider)
            : ownedSources.has(bucket.provider + '\u0000' + bucket.sourcePath)),
      );
    } else {
      ownedBuckets = env.summary.buckets;
      for (const source of env.summary.sources || []) {
        if (source.status === 'missing') continue;
        if (source.provider) {
          sessionsByProvider.set(
            source.provider,
            (sessionsByProvider.get(source.provider) || 0) + source.distinctSessions,
          );
        }
      }
    }

    if (ownedBuckets.length > 0) contributingEnvironments.push(env.environmentId);

    sessionsByProvider.forEach((providerSessions: number, providerKind: string) => {
      sessions += providerSessions;
      if (providerSessions === 0) return;
      let prov = providerAccumulator.get(providerKind);
      if (!prov) {
        prov = { costUsd: 0, totalTokens: 0, records: 0, sessions: 0 };
        providerAccumulator.set(providerKind, prov);
      }
      prov.sessions += providerSessions;
    });

    for (const bucket of ownedBuckets) {
      const tokens = bucket.tokens;
      const bucketRecords = bucket.records || 0;
      costUsd += bucket.costUsd;
      cacheSavingsUsd += bucket.cacheSavingsUsd || 0;
      uncachedInputTokens += bucket.uncachedInputTokens || 0;
      cachedInputTokens += bucket.cachedInputTokens || 0;
      cacheCreationTokens += bucket.cacheCreationTokens || 0;
      outputTokens += bucket.outputTokens || 0;
      reasoningTokens += bucket.reasoningTokens || 0;
      totalTokensSum += tokens;
      records += bucketRecords;
      unpricedRecords += bucket.unpricedRecords;
      if (bucket.costSource === 'providerReported') providerReportedRecords += bucketRecords;
      catInput += bucket.categoryCostInput || 0;
      catCacheRead += bucket.categoryCostCacheRead || 0;
      catCacheWrite += bucket.categoryCostCacheWrite || 0;
      catOutput += bucket.categoryCostOutput || 0;
      fastCost += bucket.fastCostUsd || 0;
      ultrafastCost += bucket.ultrafastCostUsd || 0;
      premiumCost += bucket.speedPremiumUsd || 0;

      let prov = providerAccumulator.get(bucket.provider);
      if (!prov) {
        prov = { costUsd: 0, totalTokens: 0, records: 0, sessions: 0 };
        providerAccumulator.set(bucket.provider, prov);
      }
      prov.costUsd += bucket.costUsd;
      prov.totalTokens += tokens;
      prov.records += bucketRecords;

      const modelKey = bucket.provider + ' ' + bucket.model;
      let model = modelAccumulator.get(modelKey);
      if (!model) {
        model = {
          provider: bucket.provider,
          model: bucket.model,
          costUsd: 0,
          totalTokens: 0,
          records: 0,
          unpricedRecords: 0,
          unpricedTokens: 0,
        };
        modelAccumulator.set(modelKey, model);
      }
      model.costUsd += bucket.costUsd;
      model.totalTokens += tokens;
      model.records += bucketRecords;
      model.unpricedRecords += bucket.unpricedRecords;
      if (bucket.unpricedTokens !== undefined) {
        model.unpricedTokens += bucket.unpricedTokens;
      } else if (bucketRecords > 0) {
        model.unpricedTokens += (tokens * bucket.unpricedRecords) / bucketRecords;
      }

      upsertPeriodValue(dailyAccumulator, bucket.day, bucket.provider, bucket.costUsd, tokens);
      if (bucket.hourStart) {
        upsertPeriodValue(hourlyAccumulator, bucket.hourStart, bucket.provider, bucket.costUsd, tokens);
      }
    }
  }

  const providers: UsageProviderTotals[] = Array.from(providerAccumulator.entries())
    .map((pair: [string, ProviderAccumulator]): UsageProviderTotals => ({
      provider: pair[0],
      costUsd: pair[1].costUsd,
      totalTokens: pair[1].totalTokens,
      records: pair[1].records,
      sessions: pair[1].sessions,
      costShare: costUsd === 0 ? 0 : pair[1].costUsd / costUsd,
      tokenShare: totalTokensSum === 0 ? 0 : pair[1].totalTokens / totalTokensSum,
    }))
    .sort((a: UsageProviderTotals, b: UsageProviderTotals) => b.costUsd - a.costUsd);

  const models: UsageModelTotals[] = Array.from(modelAccumulator.values())
    .map((m: ModelAccumulator): UsageModelTotals => ({
      model: m.model,
      provider: m.provider,
      costUsd: m.costUsd,
      totalTokens: m.totalTokens,
      records: m.records,
      unpricedRecords: m.unpricedRecords,
      unpricedTokens: m.unpricedTokens,
      costShare: costUsd === 0 ? 0 : m.costUsd / costUsd,
      tokenShare: totalTokensSum === 0 ? 0 : m.totalTokens / totalTokensSum,
      costUnknown: m.records > 0 && m.unpricedRecords >= m.records,
    }))
    .sort(
      (a: UsageModelTotals, b: UsageModelTotals) =>
        b.costUsd - a.costUsd || b.totalTokens - a.totalTokens,
    );

  return {
    costUsd,
    uncachedInputTokens,
    cachedInputTokens,
    cacheCreationTokens,
    outputTokens,
    reasoningTokens,
    totalTokens: totalTokensSum,
    records,
    sessions,
    providers,
    models,
    daily: finalizePeriods(dailyAccumulator),
    hourly: finalizePeriods(hourlyAccumulator),
    cacheSavingsUsd,
    unpricedShare: records === 0 ? 0 : unpricedRecords / records,
    providerReportedShare: records === 0 ? 0 : providerReportedRecords / records,
    modelPricedShare: records === 0 ? 0 : (records - providerReportedRecords - unpricedRecords) / records,
    categoryCost: {
      input: catInput,
      cacheRead: catCacheRead,
      cacheWrite: catCacheWrite,
      output: catOutput,
      unsplit: Math.max(0, costUsd - catInput - catCacheRead - catCacheWrite - catOutput),
    },
    speedCost: {
      standard: Math.max(0, costUsd - fastCost - ultrafastCost),
      fast: fastCost,
      ultrafast: ultrafastCost,
      premium: premiumCost,
    },
    duplicateSources: duplicates,
    contributingEnvironments,
    contractMismatches,
  };
}

export function buildUsageChartBars(
  periods: string[],
  data: UsagePeriodTotals[],
  metric: 'cost' | 'tokens',
): UsageChartBar[] {
  const byPeriod = new Map<string, UsagePeriodTotals>();
  for (const row of data) byPeriod.set(row.period, row);

  return periods.map((period: string): UsageChartBar => {
    const entry = byPeriod.get(period);
    const providerMap = new Map<string, UsagePeriodProviderValue>();
    if (entry) {
      for (const pv of entry.byProvider) providerMap.set(pv.provider, pv);
    }
    const values: UsageChartSegment[] = USAGE_PROVIDER_ORDER.map((provider: string): UsageChartSegment => {
      const pv = providerMap.get(provider);
      const val = !pv ? 0 : metric === 'cost' ? pv.costUsd : pv.totalTokens;
      return { provider, value: val };
    });
    const total = values.reduce((sum: number, seg: UsageChartSegment) => sum + seg.value, 0);
    return { period, values, total };
  });
}

export function toggleUsageEnvironmentSelection(
  selected: string[] | null,
  environmentIds: string[],
  toggledId: string,
): string[] | null {
  const next = new Set<string>(
    environmentIds.filter((id: string) => selected === null || selected.includes(id)),
  );
  if (environmentIds.includes(toggledId)) {
    if (next.has(toggledId)) next.delete(toggledId);
    else next.add(toggledId);
  }
  return environmentIds.every((id: string) => next.has(id)) ? null : Array.from(next);
}

// ---------- Pooled Subscription Limits Engine ----------

const WINDOW_KIND_ORDER: Record<string, number> = {
  session: 0,
  weekly: 1,
  monthly: 2,
  other: 3,
};

const CODEX_PLAN_CAPACITY: Record<string, number> = {
  'ChatGPT Plus Subscription': 1,
  'ChatGPT Pro 100 Subscription': 5,
  'ChatGPT Pro 200 Subscription': 20,
};

const CLAUDE_SESSION_CAPACITY: Record<string, number> = {
  Pro: 1,
  Max: 5,
  Ultra: 20,
};

interface CursorWindowMeta {
  id: string;
  label: string;
  description: string;
}

const CURSOR_USAGE_WINDOWS: CursorWindowMeta[] = [
  { id: 'totalPercentUsed', label: '总用量', description: '当前账单周期内的全部用量。' },
  { id: 'autoPercentUsed', label: 'Cursor 模型', description: 'Grok、Composer 和 Auto 使用此额度。' },
  { id: 'apiPercentUsed', label: '其他模型', description: 'Claude、GPT 和 Gemini 等第三方模型的用量额度。' },
];

export function normalizeHexAccentColor(value: string): string {
  const trimmed = value.trim();
  return /^#[0-9a-fA-F]{6}$/.test(trimmed) ? trimmed : '';
}

export function maskAccountEmail(email: string): string {
  return email.includes('@') ? '••••••@••••••' : email;
}

function emailInitials(email: string): string {
  const parts = email.split('@');
  const local = parts[0] || '';
  const domain = parts[1] || '';
  return ((local[0] || '') + (domain[0] || '')).toUpperCase();
}

export function accountDisplayName(account: PooledLimitAccount): string {
  if (account.displayName) return account.displayName;
  if (!account.email) return usageProviderLabel(account.driver);
  return emailInitials(account.email) || '账号';
}

function hubAccountName(id: string): string {
  return id.replace(/\.json$/i, '');
}

function isLocalLoopbackOrWildcardHost(host: string): boolean {
  const normalized = host.toLowerCase().replace(/^\[|\]$/g, '').replace(/\.+$/, '');
  if (normalized === 'localhost' || normalized === '::1' || normalized === '0.0.0.0' || normalized === '::') {
    return true;
  }
  if (/\.localhost$/i.test(normalized) || /^::ffff:(?:127\.|7f[\da-f]{2}:)/i.test(normalized)) {
    return true;
  }
  const parts = normalized.split('.');
  return parts.length === 4 && parts[0] === '127' && parts.every((p: string) => /^\d+$/.test(p) && Number(p) <= 255);
}

function hubIdentity(environmentId: string, source: Record<string, Object>): string {
  const endpoint = optionalText(source.endpoint);
  const match = endpoint.match(/^https?:\/\/(\[[\da-fA-F:.]+\]|[^:/?#@]+)(?::\d+)?(?:\/|$)/);
  const host = match ? match[1] : '';
  if (endpoint && host && !isLocalLoopbackOrWildcardHost(host)) return endpoint;
  return environmentId + ':' + optionalText(source.id);
}

function parseLimitNotice(limits: Record<string, Object>): string {
  if (limits.unavailable !== undefined && limits.unavailable !== null) {
    const unavailable = record(limits.unavailable);
    const reason = optionalText(unavailable.reason);
    const customMsg = optionalText(unavailable.message);
    if (reason === 'unsupported') return customMsg || '此账号无订阅限额。';
    if (reason === 'probeFailed') return customMsg || '无法读取限额。';
  }
  const windows = limits.windows !== undefined && limits.windows !== null ? objects(limits.windows) : [];
  return windows.length === 0 ? '未上报限额信息。' : '';
}

function parseResetCredits(raw: Object | undefined): UsageResetCredits | undefined {
  if (raw === undefined || raw === null) return undefined;
  const obj = record(raw);
  const options: UsageResetCreditOption[] =
    obj.options !== undefined && obj.options !== null
      ? objects(obj.options).map((item: Object): UsageResetCreditOption => {
          const opt = record(item);
          return {
            creditId: text(opt.creditId),
            label: text(opt.label),
            description: text(opt.description),
            availableCount: optionalNonNegativeInt(opt.availableCount),
            expiresAt: optionalText(opt.expiresAt),
          };
        })
      : [];
  return {
    availableCount: optionalNonNegativeInt(obj.availableCount),
    nextExpiresAt: optionalText(obj.nextExpiresAt),
    nextCreditId: optionalText(obj.nextCreditId),
    options,
  };
}

function parseLimitWindows(limits: Record<string, Object>): PooledLimitWindowEntry[] {
  if (limits.windows === undefined || limits.windows === null) return [];
  return objects(limits.windows).map((item: Object): PooledLimitWindowEntry => {
    const w = record(item);
    const used = finite(w.usedPercent);
    const clamped = Math.max(0, Math.min(100, used));
    return {
      id: text(w.id),
      kind: optionalText(w.kind) || 'other',
      label: text(w.label),
      usedPercent: used,
      remaining: Math.round(100 - clamped),
      resetsAt: optionalText(w.resetsAt),
      windowDurationMins:
        typeof w.windowDurationMins === 'number' && Number.isFinite(w.windowDurationMins) && w.windowDurationMins >= 0
          ? w.windowDurationMins
          : 0,
      outOfRange: used < 0 || used > 100,
    };
  });
}

function isProviderEntryWithLimits(provider: Record<string, Object>): boolean {
  return (
    provider.enabled !== false &&
    provider.installed !== false &&
    provider.availability !== 'unavailable' &&
    provider.usageLimits !== undefined &&
    provider.usageLimits !== null
  );
}

interface AccountIdentityReport {
  driver: string;
  email: string;
  workspaceId: string;
  credentialFingerprint: string;
}

function baseAccountKey(report: AccountIdentityReport): string {
  const email = report.email.trim().toLowerCase();
  if (email) return report.driver + ':' + email;
  if (report.credentialFingerprint) return report.driver + ':credential:' + report.credentialFingerprint;
  return '';
}

function createAccountKeyResolver(reports: AccountIdentityReport[]): (report: AccountIdentityReport) => string {
  const workspaces = new Map<string, Set<string>>();
  for (const report of reports) {
    const key = baseAccountKey(report);
    if (key && report.workspaceId) {
      let set = workspaces.get(key);
      if (!set) {
        set = new Set<string>();
        workspaces.set(key, set);
      }
      set.add(report.workspaceId);
    }
  }
  return (report: AccountIdentityReport): string => {
    const key = baseAccountKey(report);
    if (!key) return '';
    if (report.workspaceId) return key + ':' + report.workspaceId;
    const known = workspaces.get(key);
    if (!known) return key;
    return known.size === 1 ? key + ':' + Array.from(known.values())[0] : '';
  };
}

export function collectPooledLimitAccounts(snapshots: LimitEnvironmentSnapshot[]): PooledLimitAccount[] {
  const reports: AccountIdentityReport[] = [];
  for (const snap of snapshots) {
    const providers = snap.config.providers !== undefined && snap.config.providers !== null ? objects(snap.config.providers) : [];
    for (const raw of providers) {
      const p = record(raw);
      if (p.enabled === false) continue;
      const auth = p.auth !== undefined && p.auth !== null ? record(p.auth) : {};
      const limits = p.usageLimits !== undefined && p.usageLimits !== null ? record(p.usageLimits) : {};
      reports.push({
        driver: text(p.driver),
        email: optionalText(auth.email),
        workspaceId: optionalText(auth.workspaceId),
        credentialFingerprint: optionalText(limits.credentialFingerprint),
      });
    }
    const sources =
      snap.config.usageLimitSources !== undefined && snap.config.usageLimitSources !== null
        ? objects(snap.config.usageLimitSources)
        : [];
    for (const rawSource of sources) {
      const source = record(rawSource);
      const accts = source.accounts !== undefined && source.accounts !== null ? objects(source.accounts) : [];
      for (const rawAcct of accts) {
        const a = record(rawAcct);
        const limits = a.usageLimits !== undefined && a.usageLimits !== null ? record(a.usageLimits) : {};
        reports.push({
          driver: text(a.driver),
          email: optionalText(a.email),
          workspaceId: optionalText(a.workspaceId),
          credentialFingerprint: optionalText(limits.credentialFingerprint),
        });
      }
    }
  }

  const resolveKey = createAccountKeyResolver(reports);
  const accounts = new Map<string, PooledLimitAccount>();
  const creditSources = new Map<string, PooledLimitAccount>();
  const hubRedeems = new Map<string, PooledLimitAccount>();
  const planSources = new Map<string, PooledLimitAccount>();

  const mergeAccount = (dedupeKey: string, next: PooledLimitAccount): void => {
    const prevHub = hubRedeems.get(dedupeKey);
    const nextTime = Date.parse(next.checkedAt) || 0;
    if (
      next.redeemPayload &&
      next.redeemPayload.sourceId !== undefined &&
      (!prevHub || nextTime > (Date.parse(prevHub.checkedAt) || 0))
    ) {
      hubRedeems.set(dedupeKey, next);
    }
    const prevCredit = creditSources.get(dedupeKey);
    if (next.resetCredits && (!prevCredit || nextTime > (Date.parse(prevCredit.checkedAt) || 0))) {
      creditSources.set(dedupeKey, next);
    }
    const prevPlan = planSources.get(dedupeKey);
    if (next.plan && (!prevPlan || nextTime > (Date.parse(prevPlan.checkedAt) || 0))) {
      planSources.set(dedupeKey, next);
    }

    const previous = accounts.get(dedupeKey);
    if (!previous) {
      accounts.set(dedupeKey, next);
      return;
    }

    const fresher = nextTime > (Date.parse(previous.checkedAt) || 0);
    const mergedEnvs: PooledLimitEnvironmentRef[] = [...previous.environments];
    for (const candidate of next.environments) {
      if (!mergedEnvs.some((seen: PooledLimitEnvironmentRef) => seen.environmentId === candidate.environmentId)) {
        mergedEnvs.push(candidate);
      }
    }
    const winner = fresher ? next : previous;
    const creditSource = creditSources.get(dedupeKey);
    const hubEmail = [previous, next].some((acct: PooledLimitAccount) => acct.environments.length === 0 && !!acct.email);
    let displayName = previous.displayName || next.displayName;
    if (hubEmail && displayName.toLowerCase() === usageProviderLabel(previous.driver).toLowerCase()) {
      displayName = '';
    }
    const hubRedeem = hubRedeems.get(dedupeKey);
    accounts.set(dedupeKey, {
      key: previous.key,
      driver: previous.driver,
      displayName,
      email: previous.email || next.email,
      plan: planSources.get(dedupeKey)?.plan || previous.plan || next.plan,
      accentColor: previous.accentColor || next.accentColor,
      environments: mergedEnvs,
      sourceLabel: mergedEnvs.length > 0 ? '' : previous.sourceLabel || next.sourceLabel,
      checkedAt: winner.checkedAt,
      zeroSpendCap: winner.zeroSpendCap,
      windows: winner.windows,
      resetCredits: creditSource ? creditSource.resetCredits : undefined,
      redeemEnvironmentId: hubRedeem
        ? hubRedeem.redeemEnvironmentId
        : creditSource
          ? creditSource.redeemEnvironmentId
          : winner.redeemEnvironmentId || previous.redeemEnvironmentId || next.redeemEnvironmentId,
      redeemPayload: hubRedeem
        ? hubRedeem.redeemPayload
        : creditSource
          ? creditSource.redeemPayload
          : winner.redeemPayload || previous.redeemPayload || next.redeemPayload,
    });
  };

  for (const snap of snapshots) {
    const providers = snap.config.providers !== undefined && snap.config.providers !== null ? objects(snap.config.providers) : [];
    for (const raw of providers) {
      const p = record(raw);
      if (!isProviderEntryWithLimits(p)) continue;
      const limits = record(p.usageLimits);
      if (parseLimitNotice(limits)) continue;
      const driver = text(p.driver);
      const instanceId = text(p.instanceId);
      const auth = p.auth !== undefined && p.auth !== null ? record(p.auth) : {};
      const email = optionalText(auth.email);
      const workspaceId = optionalText(auth.workspaceId);
      const resolved = resolveKey({
        driver,
        email,
        workspaceId,
        credentialFingerprint: optionalText(limits.credentialFingerprint),
      });
      const fallbackKey = snap.environmentId + ':' + instanceId;
      mergeAccount(resolved || fallbackKey, {
        key: fallbackKey,
        driver,
        displayName: optionalText(p.displayName).trim(),
        email,
        plan: optionalText(auth.label),
        accentColor: normalizeHexAccentColor(optionalText(p.accentColor)),
        environments: [{ environmentId: snap.environmentId, label: snap.label }],
        sourceLabel: '',
        checkedAt: optionalText(limits.checkedAt),
        zeroSpendCap: limits.zeroSpendCap === true,
        windows: parseLimitWindows(limits),
        resetCredits: parseResetCredits(limits.resetCredits),
        redeemEnvironmentId: snap.environmentId,
        redeemPayload: { instanceId },
      });
    }
  }

  const labelEnvironment = snapshots.length > 1;
  for (const snap of snapshots) {
    const sources =
      snap.config.usageLimitSources !== undefined && snap.config.usageLimitSources !== null
        ? objects(snap.config.usageLimitSources)
        : [];
    for (const rawSource of sources) {
      const source = record(rawSource);
      const sourceId = text(source.id);
      const sourceTitle = text(source.label);
      const sourceLabel = labelEnvironment ? snap.label + ' · ' + sourceTitle : sourceTitle;
      const accts = source.accounts !== undefined && source.accounts !== null ? objects(source.accounts) : [];
      for (const rawAcct of accts) {
        const a = record(rawAcct);
        const limits = record(a.usageLimits);
        if (parseLimitNotice(limits)) continue;
        const driver = text(a.driver);
        const accountId = text(a.id);
        const email = optionalText(a.email);
        const workspaceId = optionalText(a.workspaceId);
        const resolved = resolveKey({
          driver,
          email,
          workspaceId,
          credentialFingerprint: optionalText(limits.credentialFingerprint),
        });
        const hub = resolved ? snap.environmentId + ':' + sourceId : hubIdentity(snap.environmentId, source);
        const key = hub + ':' + accountId + (workspaceId ? ':' + workspaceId : '');
        const resetCredits = parseResetCredits(limits.resetCredits);
        mergeAccount(resolved || key, {
          key,
          driver,
          displayName: email ? '' : hubAccountName(accountId),
          email,
          plan: optionalText(a.plan),
          accentColor: '',
          environments: [],
          sourceLabel,
          checkedAt: optionalText(limits.checkedAt),
          zeroSpendCap: limits.zeroSpendCap === true,
          windows: parseLimitWindows(limits),
          resetCredits,
          redeemEnvironmentId: resetCredits && resetCredits.nextCreditId ? snap.environmentId : '',
          redeemPayload:
            resetCredits && resetCredits.nextCreditId
              ? { sourceId, accountId, creditId: resetCredits.nextCreditId }
              : undefined,
        });
      }
    }
  }

  return Array.from(accounts.values());
}

function resetMillisOf(resetsAt: string): number | null {
  if (!resetsAt) return null;
  const at = Date.parse(resetsAt);
  return Number.isFinite(at) ? at : null;
}

function elapsedShare(window: PooledLimitWindowEntry, now: number): number | null {
  const resetsAt = resetMillisOf(window.resetsAt);
  if (resetsAt === null || window.windowDurationMins <= 0) return null;
  const length = window.windowDurationMins * MINUTE_MS;
  if (length <= 0) return null;
  return Math.max(0, Math.min(1, (length - (resetsAt - now)) / length));
}

export function paceRemainingPercent(window: PooledLimitWindowEntry, now: number): number | null {
  const elapsed = elapsedShare(window, now);
  return elapsed === null ? null : Math.round((1 - elapsed) * 100);
}

function paceOfShares(usedPercent: number, elapsed: number): string {
  const gap = usedPercent - elapsed * 100;
  if (gap > 5) return 'ahead';
  if (gap < -5) return 'under';
  return 'on';
}

export function paceOfWindow(window: PooledLimitWindowEntry, now: number): string {
  const elapsed = elapsedShare(window, now);
  return elapsed === null ? '' : paceOfShares(window.usedPercent, elapsed);
}

export function formatLimitDuration(ms: number): string {
  const remaining = Math.max(0, ms);
  const days = Math.floor(remaining / DAY_MS);
  const hours = Math.floor((remaining % DAY_MS) / HOUR_MS);
  const minutes = Math.floor((remaining % HOUR_MS) / MINUTE_MS);
  if (days > 0) return days + 'd ' + hours + 'h';
  if (hours > 0) return hours + 'h ' + minutes + 'm';
  return minutes + 'm';
}

export function formatResetsIn(resetsAt: string, now: number, compact: boolean = false): string {
  const at = resetMillisOf(resetsAt);
  if (at === null) return '';
  if (at <= now) return compact ? '现在' : '即将重置';
  if (at - now < MINUTE_MS) return compact ? '<1m' : '即将重置';
  const duration = formatLimitDuration(at - now);
  return compact ? duration : duration + ' 后重置';
}

function poolKeyForWindow(driver: string, window: PooledLimitWindowEntry): string {
  return driver === 'codex' ? window.kind : window.kind + ':' + window.id;
}

function planCapacityForAccount(account: PooledLimitAccount, kind: string): number | undefined {
  if (!account.plan) return undefined;
  if (account.driver === 'codex' && (kind === 'session' || kind === 'weekly')) {
    return CODEX_PLAN_CAPACITY[account.plan];
  }
  if (account.driver === 'claudeAgent' && kind === 'session') {
    return CLAUDE_SESSION_CAPACITY[account.plan];
  }
  return undefined;
}

interface PoolMemberEntry {
  account: PooledLimitAccount;
  window: PooledLimitWindowEntry;
  refillPercent: number;
}

function resolvePoolMember(
  account: PooledLimitAccount,
  reported: PooledLimitWindowEntry,
  now: number,
): PoolMemberEntry {
  const spentWeekly =
    reported.kind === 'session'
      ? account.windows.find(
          (w: PooledLimitWindowEntry) =>
            w.usedPercent >= 100 &&
            (account.driver === 'claudeAgent'
              ? w.id === 'seven_day'
              : account.driver === 'codex' && w.kind === 'weekly'),
        )
      : undefined;
  if (!spentWeekly) {
    return { account, window: reported, refillPercent: reported.usedPercent };
  }

  const weeklyReset = resetMillisOf(spentWeekly.resetsAt);
  const sessionReset = resetMillisOf(reported.resetsAt);
  const cutoff = Math.max(now, Date.parse(account.checkedAt) || 0);
  let resetsAt = '';
  let refillPercent = 0;
  if (
    weeklyReset !== null &&
    sessionReset !== null &&
    weeklyReset > cutoff &&
    sessionReset > cutoff
  ) {
    if (sessionReset <= weeklyReset) {
      resetsAt = spentWeekly.resetsAt;
      refillPercent = 100;
    } else if (reported.usedPercent >= 100) {
      resetsAt = reported.resetsAt;
      refillPercent = 100;
    } else {
      resetsAt = spentWeekly.resetsAt;
      refillPercent = 100 - Math.max(0, Math.min(100, reported.usedPercent));
    }
  }
  return {
    account,
    window: {
      id: reported.id,
      kind: reported.kind,
      label: reported.label,
      usedPercent: 100,
      remaining: 0,
      resetsAt,
      windowDurationMins: 0,
      outOfRange: reported.outOfRange,
    },
    refillPercent,
  };
}

function hasDuplicateCursorTotalWindow(windows: PooledLimitWindow[]): boolean {
  if (windows.length !== 2) return false;
  const total = windows.find((w: PooledLimitWindow) => w.id === 'totalPercentUsed');
  const auto = windows.find((w: PooledLimitWindow) => w.id === 'autoPercentUsed');
  if (!total || !auto) return false;
  const totalMembers = total.columns.filter((c: PooledLimitColumn) => !!c.window);
  const autoMembers = auto.columns.filter((c: PooledLimitColumn) => !!c.window);
  if (totalMembers.length !== autoMembers.length) return false;
  return totalMembers.every((col: PooledLimitColumn) =>
    col.account.windows.some(
      (candidate: PooledLimitWindowEntry) =>
        candidate.id === auto.id &&
        candidate.kind === auto.kind &&
        candidate.usedPercent === col.window?.usedPercent &&
        candidate.resetsAt === col.window?.resetsAt,
    ),
  );
}

function cursorWindowRank(id: string): number {
  const idx = CURSOR_USAGE_WINDOWS.findIndex((item: CursorWindowMeta) => item.id === id);
  return idx < 0 ? CURSOR_USAGE_WINDOWS.length : idx;
}

export function collectPooledLimitGroups(
  accounts: PooledLimitAccount[],
  now: number,
): PooledLimitGroup[] {
  const byDriver = new Map<string, PooledLimitAccount[]>();
  for (const account of accounts) {
    let list = byDriver.get(account.driver);
    if (!list) {
      list = [];
      byDriver.set(account.driver, list);
    }
    list.push(account);
  }

  const groups: PooledLimitGroup[] = [];
  byDriver.forEach((members: PooledLimitAccount[], driver: string) => {
    const allWindows: PooledLimitWindowEntry[] = [];
    for (const m of members) {
      for (const w of m.windows) allWindows.push(w);
    }
    allWindows.sort(
      (a: PooledLimitWindowEntry, b: PooledLimitWindowEntry) =>
        (WINDOW_KIND_ORDER[a.kind] ?? 3) - (WINDOW_KIND_ORDER[b.kind] ?? 3),
    );
    const orderWindow = allWindows[0];

    const orderReset = (acct: PooledLimitAccount): number => {
      if (!orderWindow) return Number.POSITIVE_INFINITY;
      const targetKey = poolKeyForWindow(driver, orderWindow);
      const matched = acct.windows.find(
        (w: PooledLimitWindowEntry) => poolKeyForWindow(driver, w) === targetKey,
      );
      if (!matched) return Number.POSITIVE_INFINITY;
      const resolved = resolvePoolMember(acct, matched, now);
      return resetMillisOf(resolved.window.resetsAt) ?? Number.POSITIVE_INFINITY;
    };

    const sortedAccounts = [...members].sort((left: PooledLimitAccount, right: PooledLimitAccount) => {
      const diff = orderReset(left) - orderReset(right);
      if (diff !== 0) return diff;
      const leftName = (left.displayName || left.email || left.key).toLowerCase();
      const rightName = (right.displayName || right.email || right.key).toLowerCase();
      return leftName.localeCompare(rightName) || left.key.localeCompare(right.key);
    });

    const byKey = new Map<string, PoolMemberEntry[]>();
    for (const acct of sortedAccounts) {
      for (const reported of acct.windows) {
        const member = resolvePoolMember(acct, reported, now);
        const pooled = poolKeyForWindow(driver, member.window);
        const existingList = byKey.get(pooled);
        const key =
          existingList && existingList.some((entry: PoolMemberEntry) => entry.account === acct)
            ? member.window.kind + ':' + member.window.id
            : pooled;
        let list = byKey.get(key);
        if (!list) {
          list = [];
          byKey.set(key, list);
        }
        list.push(member);
      }
    }

    let windows: PooledLimitWindow[] = Array.from(byKey.entries()).map(
      (pair: [string, PoolMemberEntry[]]): PooledLimitWindow => {
        const key = pair[0];
        const poolMembers = pair[1];
        const memberByAccount = new Map<string, PoolMemberEntry>();
        for (const pm of poolMembers) memberByAccount.set(pm.account.key, pm);
        const first = poolMembers[0].window;
        const id = driver === 'codex' ? key : first.id;

        const capacities = poolMembers.map((pm: PoolMemberEntry) =>
          planCapacityForAccount(pm.account, first.kind),
        );
        const usePlanWeights = capacities.every((c: number | undefined) => c !== undefined);
        const weights = poolMembers.map((_: PoolMemberEntry, idx: number) =>
          usePlanWeights ? (capacities[idx] as number) : 1,
        );
        const totalWeight = weights.reduce((sum: number, w: number) => sum + w, 0) || 1;

        let usedWeighted = 0;
        let timedWeight = 0;
        let timedUsedWeighted = 0;
        let timedElapsedWeighted = 0;
        let timedCount = 0;

        for (let i = 0; i < poolMembers.length; i++) {
          const pm = poolMembers[i];
          const w = weights[i];
          usedWeighted += pm.window.usedPercent * w;
          const share = elapsedShare(pm.window, now);
          if (share !== null) {
            timedCount += 1;
            timedWeight += w;
            timedUsedWeighted += pm.window.usedPercent * w;
            timedElapsedWeighted += share * w;
          }
        }

        const usedPercent = usedWeighted / totalWeight;
        const pace =
          timedCount > 0 && timedWeight > 0
            ? paceOfShares(timedUsedWeighted / timedWeight, timedElapsedWeighted / timedWeight)
            : '';

        const resets: PooledLimitReset[] = [];
        for (let i = 0; i < poolMembers.length; i++) {
          const pm = poolMembers[i];
          const at = resetMillisOf(pm.window.resetsAt);
          if (at !== null) {
            resets.push({
              accountKey: pm.account.key,
              resetsAt: pm.window.resetsAt,
              at,
              restoresPercent: Math.round((pm.refillPercent * weights[i]) / totalWeight),
            });
          }
        }
        resets.sort((a: PooledLimitReset, b: PooledLimitReset) => a.at - b.at);

        const columns: PooledLimitColumn[] = sortedAccounts.map((acct: PooledLimitAccount): PooledLimitColumn => {
          const matched = memberByAccount.get(acct.key);
          if (!matched) return { account: acct, refillPercent: 0 };
          return { account: acct, window: matched.window, refillPercent: matched.refillPercent };
        });

        return {
          id,
          kind: first.kind,
          label: first.label,
          description: '',
          hideLabel: false,
          columns,
          usedPercent: Math.round(usedPercent),
          remainingPercent: Math.round(100 - usedPercent),
          pace,
          resets,
        };
      },
    );

    windows.sort(
      (a: PooledLimitWindow, b: PooledLimitWindow) =>
        (WINDOW_KIND_ORDER[a.kind] ?? 3) - (WINDOW_KIND_ORDER[b.kind] ?? 3),
    );

    if (driver === 'antigravity') {
      windows = [...windows].sort((left: PooledLimitWindow, right: PooledLimitWindow) => {
        const leftNonGemini = left.id.startsWith('gemini-') ? 0 : 1;
        const rightNonGemini = right.id.startsWith('gemini-') ? 0 : 1;
        if (leftNonGemini !== rightNonGemini) return leftNonGemini - rightNonGemini;
        const leftBase = left.id.replace(/-(5h|weekly|quota)$/, '');
        const rightBase = right.id.replace(/-(5h|weekly|quota)$/, '');
        const cmp = leftBase.localeCompare(rightBase);
        if (cmp !== 0) return cmp;
        return (WINDOW_KIND_ORDER[left.kind] ?? 3) - (WINDOW_KIND_ORDER[right.kind] ?? 3);
      });
    } else if (driver === 'cursor') {
      const hasAuto = windows.some((w: PooledLimitWindow) => w.id === 'autoPercentUsed');
      const hasApi = windows.some((w: PooledLimitWindow) => w.id === 'apiPercentUsed');
      const dupTotal = hasDuplicateCursorTotalWindow(windows);
      const hideTotal = (hasAuto && hasApi) || dupTotal;
      const singleTotal = windows.length === 1;
      windows = windows
        .filter((w: PooledLimitWindow) => !hideTotal || w.id !== 'totalPercentUsed')
        .sort(
          (left: PooledLimitWindow, right: PooledLimitWindow) =>
            cursorWindowRank(left.id) - cursorWindowRank(right.id),
        )
        .map((w: PooledLimitWindow): PooledLimitWindow => {
          const meta = CURSOR_USAGE_WINDOWS.find((item: CursorWindowMeta) => item.id === w.id);
          if (!meta) return w;
          const suppressLabel = (singleTotal && w.id === 'totalPercentUsed') || dupTotal;
          return {
            id: w.id,
            kind: w.kind,
            label: suppressLabel ? '' : meta.label,
            description: suppressLabel ? '' : meta.description,
            hideLabel: suppressLabel,
            columns: w.columns,
            remainingPercent: w.remainingPercent,
            usedPercent: w.usedPercent,
            pace: w.pace,
            resets: w.resets,
          };
        });
    }

    groups.push({ driver, accounts: sortedAccounts, windows });
  });

  return groups;
}

export function collectPooledLimitNotices(snapshots: LimitEnvironmentSnapshot[]): string[] {
  const multiEnv = snapshots.length > 1;
  const formatSubject = (envLabel: string, subject: string): string =>
    multiEnv ? envLabel + ' · ' + subject : subject;
  const notices: string[] = [];
  const addNotice = (value: string): void => {
    if (value && !notices.includes(value)) notices.push(value);
  };

  for (const snap of snapshots) {
    const providers =
      snap.config.providers !== undefined && snap.config.providers !== null ? objects(snap.config.providers) : [];
    for (const raw of providers) {
      const p = record(raw);
      if (!isProviderEntryWithLimits(p)) continue;
      const limits = record(p.usageLimits);
      if (limits.unavailable !== undefined && limits.unavailable !== null) {
        if (optionalText(record(limits.unavailable).reason) === 'unsupported') continue;
      }
      const notice = parseLimitNotice(limits);
      const name = optionalText(p.displayName).trim() || optionalText(p.driver);
      if (notice) addNotice(formatSubject(snap.label, name) + ': ' + notice);
    }

    const sources =
      snap.config.usageLimitSources !== undefined && snap.config.usageLimitSources !== null
        ? objects(snap.config.usageLimitSources)
        : [];
    for (const rawSource of sources) {
      const source = record(rawSource);
      const sourceLabel = text(source.label);
      const sourceErr = optionalText(source.error);
      const accts = source.accounts !== undefined && source.accounts !== null ? objects(source.accounts) : [];
      if (sourceErr) {
        addNotice(formatSubject(snap.label, sourceLabel) + ': ' + sourceErr);
      } else if (accts.length === 0) {
        addNotice(formatSubject(snap.label, sourceLabel) + ': 未上报账号。');
      }
    }
  }
  return notices;
}

export function collectExternalUsageLinks(snapshots: LimitEnvironmentSnapshot[]): UsageExternalLink[] {
  const byUrl = new Map<string, UsageExternalLink>();
  for (const snap of snapshots) {
    const providers =
      snap.config.providers !== undefined && snap.config.providers !== null ? objects(snap.config.providers) : [];
    for (const raw of providers) {
      const p = record(raw);
      if (!isProviderEntryWithLimits(p)) continue;
      const auth = p.auth !== undefined && p.auth !== null ? record(p.auth) : {};
      if (optionalText(auth.status) !== 'authenticated') continue;
      const limits = record(p.usageLimits);
      if (limits.externalUsage === undefined || limits.externalUsage === null) continue;
      const ext = record(limits.externalUsage);
      const url = optionalText(ext.url);
      const label = optionalText(ext.label);
      if (!url || !label) continue;
      const accountDesc =
        (optionalText(p.displayName).trim() || optionalText(p.instanceId)) + ' · ' + snap.label;
      const unavailableMsg =
        limits.unavailable !== undefined && limits.unavailable !== null
          ? optionalText(record(limits.unavailable).message)
          : '';
      const existing = byUrl.get(url);
      if (!existing) {
        byUrl.set(url, { label, url, message: unavailableMsg, accounts: [accountDesc] });
      } else {
        if (!existing.accounts.includes(accountDesc)) existing.accounts.push(accountDesc);
        if (!existing.message && unavailableMsg) existing.message = unavailableMsg;
      }
    }
  }
  return Array.from(byUrl.values());
}

export function resetCreditChoicesForAccount(
  credits: UsageResetCredits,
  basePayload: Record<string, Object>,
  now: number,
): ResetCreditChoiceView[] {
  const expiresLabel = (expiresAt: string): string => {
    const at = resetMillisOf(expiresAt);
    return at !== null ? formatLimitDuration(at - now) : '';
  };
  if (credits.options.length > 0 && basePayload.instanceId !== undefined) {
    return credits.options.map((opt: UsageResetCreditOption): ResetCreditChoiceView => {
      const exp = expiresLabel(opt.expiresAt);
      const payload: Record<string, Object> = {
        instanceId: basePayload.instanceId,
        creditId: opt.creditId,
      };
      return {
        key: opt.creditId,
        summary: opt.label + ' · 剩余 ' + opt.availableCount + ' 次' + (exp ? ' · ' + exp + ' 后过期' : ''),
        actionLabel: '使用',
        confirmDescription: opt.label + '：' + opt.description + ' 使用后不可撤销。',
        availableCount: opt.availableCount,
        payload,
      };
    });
  }
  const count = credits.availableCount;
  const exp = expiresLabel(credits.nextExpiresAt);
  return [
    {
      key: 'next',
      summary:
        count === 0
          ? '暂无可用重置额度'
          : '可用 ' + count + ' 次重置额度' + (exp ? ' · 下次 ' + exp + ' 后过期' : ''),
      actionLabel: '使用重置',
      confirmDescription: '将消耗 1 次账号重置额度并清空当前限额窗口，操作不可撤销。',
      availableCount: count,
      payload: basePayload,
    },
  ];
}

export async function consumeUsageResetCredit(
  connection: UsageReadConnection,
  payload: Record<string, Object>,
): Promise<ResetCreditConsumeOutcome> {
  if (!connection.ready || connection.canScope('providers:manage') === false) {
    throw new Error('此连接不能管理 Provider 账号');
  }
  const result = record(await connection.rpcRequest('provider.consumeResetCredit', payload, 30000, false));
  return {
    outcome: optionalText(result.outcome),
    warning: optionalText(result.warning),
  };
}
