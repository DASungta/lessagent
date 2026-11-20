import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { compile, data } from './load-core.mjs';
const source = (await readFile(new URL('../entry/src/main/ets/protocol/Usage.ts', import.meta.url), 'utf8'))
  .replace("'./Wire'", JSON.stringify(new URL('../entry/src/main/ets/protocol/Wire.ts', import.meta.url).href));
const api = await import(data(compile(source)));
const summary = () => ({ contractVersion: 6, readAt: '2026-11-19T00:00:00Z', pricing: { status: 'fresh' }, sources: [], buckets: [
  { day:'2026-11-19', provider:'codex', model:'gpt-6', totals:{uncachedInputTokens:10,cachedInputTokens:20,cacheCreationTokens:30,outputTokens:40,reasoningTokens:25}, costUsd:0.15,unpricedRecords:1 }
] });
test('usage uses provider costs and counts reasoning only once; filters exact provider', () => {
  const parsed = api.parseUsageSummary(summary());
  assert.equal(parsed.buckets[0].tokens,100);
  assert.equal(api.usageTotal(parsed.buckets).costUsd,0.15);
  assert.equal(api.filterUsage(parsed.buckets,'codex','GPT-6').length,1);
  assert.equal(api.filterUsage(parsed.buckets,'claude','').length,0);
  assert.throws(() => api.parseUsageSummary({...summary(),contractVersion:7}));
  const bad = summary(); bad.buckets[0].totals.outputTokens = -1;
  assert.throws(() => api.parseUsageSummary(bad));
});
test('usage date windows include today without using UTC dates', () => {
  const now = new Date(2026,10,19,0,30).getTime();
  assert.deepEqual(api.usageInput(7,'Asia/Shanghai',now), {sinceDay:'2026-11-13',untilDay:'2026-11-19',timeZone:'Asia/Shanghai',resolution:'day',awaitRefresh:true});
  assert.throws(() => api.usageInput(99,'UTC',now));
});
test('account snapshots retain source identity, failed probe status and reset time', () => {
  const limits = {checkedAt:'2026-11-19T00:00:00Z',windows:[{id:'weekly',label:'Weekly',usedPercent:12.5,resetsAt:'2026-11-20T00:00:00Z'}]};
  const rows = api.usageAccounts({providers:[{instanceId:'a',driver:'codex',usageLimits:limits}],usageLimitSources:[{id:'hub',label:'Hub',accounts:[{id:'a',driver:'codex',usageLimits:{...limits,unavailable:{reason:'probeFailed'}}}]}]});
  assert.equal(rows.length,2); assert.notEqual(rows[0].id,rows[1].id);
  assert.equal(rows[0].windows[0].remaining,88);
  assert.equal(rows[0].windows[0].resetsAt,'2026-11-20T00:00:00Z');
  assert.match(rows[1].notice,/上次/);
  const clamped = api.usageAccounts({providers:[{instanceId:'a',driver:'codex',usageLimits:{...limits,windows:[{id:'x',label:'X',usedPercent:101}]}}]});
  assert.equal(clamped[0].windows[0].remaining,0); assert.match(clamped[0].notice,/超出契约/);
});
test('read is permission gated, nonfatal and generation safe, with server filter preserved', async () => {
  let generation=1; const calls=[];
  const connection={ready:true,config:{settings:{usageModelFilter:{exclude:[{model:'x'}]}}},generationValue:()=>generation,canScope:()=>true,
    rpcRequest:async(...args)=>{calls.push(args);return summary();}};
  const result=await api.readUsageSummary(connection,api.usageInput(1,'UTC'));
  assert.equal(calls[0][0],'server.getUsageSummary');assert.equal(calls[0][3],false);
  assert.deepEqual(calls[0][1].modelFilter,connection.config.settings.usageModelFilter);
  assert.match(result.notices[0],/未确认/);
  connection.rpcRequest=async()=>{generation++;return summary();};
  await assert.rejects(api.readUsageSummary(connection,{}),/变化/);
  connection.canScope=()=>false;
  await assert.rejects(api.readUsageSummary(connection,{}),/权限/);
});

test('daily chart aggregates the selected buckets, sorts real days and keeps unknown-price flags', () => {
  const row = api.parseUsageSummary(summary()).buckets[0];
  const rows = [row, {...row,provider:'claude',tokens:50,costUsd:0.5,unpricedRecords:0},
    {...row,day:'2026-11-17',costUsd:0,unpricedRecords:2}, {...row,model:'other',tokens:25,costUsd:0.1}];
  const daily = api.usageDays(api.filterUsage(rows,'codex','gpt-6'));
  assert.deepEqual(daily.map(day=>day.day),['2026-11-17','2026-11-19']);
  assert.equal(daily[0].costUsd,0); assert.equal(daily[0].unpricedRecords,2);
  assert.equal(daily[1].tokens,100); assert.equal(daily[1].costUsd,0.15);
  const all = api.usageDays(rows);
  assert.equal(all[1].tokens,175); assert.equal(all[1].costUsd,0.75);
  assert.equal(api.usageDayScale(all,'cost'),0.75);
  assert.equal(api.usageDayScale(all,'tokens'),175);
  assert.deepEqual(api.usageDays([]),[]); assert.equal(api.usageDayScale([],'cost'),0);
});

test('usage compact labels keep details separate and translate pricing states', () => {
  assert.equal(api.compactUsageTokens(9999),'9999');
  assert.equal(api.compactUsageTokens(10000),'1万');
  assert.equal(api.compactUsageTokens(1234567),'123.46万');
  assert.equal(api.compactUsageTokens(100000000),'1亿');
  assert.equal(api.compactUsageTokens(110000000),'1.1亿');
  assert.equal(api.compactUsageTokens(0),'0');
  assert.equal(api.usagePricingLabel('fresh'),'最新价格');
  assert.match(api.usagePricingLabel('cached'),/缓存/);
  assert.match(api.usagePricingLabel('unavailable'),/不完整/);
  assert.equal(api.usagePricingLabel('future'),'价格状态未知');
});
test('usage source notices are deduplicated and explain missing, stale and failed records', () => {
  const value=summary();
  value.sources=[{status:'missing'},{status:'missing'},{status:'ok',refreshing:true},{status:'partial',refreshing:true},{status:'failed'}];
  const result=api.parseUsageSummary(value);
  assert.equal(result.notices.length,4);
  assert.match(result.notices[0],/尚无可读取/);
  assert.equal(result.notices.filter(notice=>notice.includes('正在更新')).length,1);
  assert.match(api.usageSourceNotice('stale'),/上次读取/);
  assert.match(api.usageSourceNotice('error'),/读取失败/);
  assert.equal(api.usageSourceNotice('ok'),'');
});

test('makeUsageWindow builds 24h hourly and 7d/30d/90d daily ranges and enumerates slots', () => {
  const now = Date.UTC(2026, 10, 20, 12, 34, 45);
  const w24 = api.makeUsageWindow(1, 'UTC', now);
  assert.equal(w24.resolution, 'hour');
  assert.equal(w24.untilTime, '2026-11-20T12:34:00.000Z');
  assert.equal(w24.sinceTime, '2026-11-19T12:34:00.000Z');
  assert.equal(api.enumerateUsageHourStarts(w24.sinceTime, w24.untilTime).length, 24);

  const w30 = api.makeUsageWindow(30, 'Asia/Shanghai', now);
  assert.equal(w30.resolution, 'day');
  assert.equal(w30.sinceTime, '');
  assert.equal(api.enumerateUsageDays(w30.sinceDay, w30.untilDay).length, 30);

  const w90 = api.makeUsageWindow(90, 'UTC', now);
  assert.equal(api.enumerateUsageDays(w90.sinceDay, w90.untilDay).length, 90);
});

test('Android-aligned formatting helpers match USD, compact tokens, percentages and dates', () => {
  assert.equal(api.formatUsageUsd(17400.3), '$17,400.30');
  assert.equal(api.formatUsageUsd(0.94), '$0.94');
  assert.equal(api.formatUsageUsd(-0.002), '$0.00');
  assert.equal(api.formatUsageUsd(-12.5), '-$12.50');

  assert.equal(api.formatUsageTokens(999), '999');
  assert.equal(api.formatUsageTokens(999999), '1M');
  assert.equal(api.formatUsageTokens(13000000000), '13B');
  assert.equal(api.formatUsageTokens(9740000000), '9.74B');
  assert.equal(api.formatUsageTokens(2500000000), '2.50B');
  assert.equal(api.formatUsageTokens(968000), '968K');

  assert.equal(api.formatUsagePercent(0.924), '92.4%');
  assert.equal(api.formatUsagePercent(0.0005), '<0.1%');
  assert.equal(api.formatUsagePercent(0), '0.0%');
  assert.equal(api.formatUsageCount(123456), '123,456');
  assert.equal(api.formatUsageDayShort('2026-10-22'), '10月22日');
  assert.equal(api.formatUsageHourShort('2026-11-20T09:00:00.000Z', 'UTC'), '09:00');
});

test('mergeUsageSummaries deduplicates shared fingerprints and aggregates breakdown metrics', () => {
  const makeFullSummary = (readAt, hostId, resolvedHomePath, physicalSourceId, costUsd, unpricedRecords) =>
    api.parseUsageSummary({
      contractVersion: 6,
      readAt,
      sinceDay: '2026-11-18',
      untilDay: '2026-11-20',
      timeZone: 'UTC',
      pricing: { status: 'fresh' },
      sources: [
        {
          fingerprint: { hostId, provider: 'codex', resolvedHomePath, volumeId: '1:2', physicalSourceId },
          status: 'ok',
          scannedFiles: 1,
          skippedFiles: 0,
          malformedRecords: 0,
          distinctSessions: 5,
          message: null,
        },
        {
          fingerprint: { hostId, provider: 'claude', resolvedHomePath: '/claude-' + hostId, volumeId: '3:4' },
          status: 'ok',
          scannedFiles: 1,
          skippedFiles: 0,
          malformedRecords: 0,
          distinctSessions: 2,
          message: null,
        },
      ],
      buckets: [
        {
          day: '2026-11-19',
          provider: 'codex',
          model: 'gpt-6-astra',
          sourcePath: resolvedHomePath,
          totals: { uncachedInputTokens: 100, cachedInputTokens: 900, cacheCreationTokens: 50, outputTokens: 200, reasoningTokens: 40 },
          costUsd,
          cacheSavingsUsd: 10,
          categoryCostUsd: { input: 1, cacheRead: 2, cacheWrite: 0.5, output: 3 },
          fastCostUsd: 4,
          ultrafastCostUsd: 0,
          speedPremiumUsd: 2,
          costSource: 'modelPriced',
          records: 10,
          unpricedRecords,
          sessions: 5,
        },
        {
          day: '2026-11-20',
          provider: 'claude',
          model: 'unpriced-model',
          sourcePath: '/claude-' + hostId,
          totals: { uncachedInputTokens: 10, cachedInputTokens: 0, cacheCreationTokens: 0, outputTokens: 20, reasoningTokens: 0 },
          costUsd: 0,
          cacheSavingsUsd: 0,
          costSource: 'unpriced',
          records: 3,
          unpricedRecords: 3,
          sessions: 2,
        },
      ],
    });

  const envA = {
    environmentId: 'env-a',
    label: 'Mac',
    summary: makeFullSummary('2026-11-20T10:00:00Z', 'host-1', '/Users/a/.codex', 'phys-1', 8.5, 0),
  };
  const envB = {
    environmentId: 'env-b',
    label: 'WSL',
    summary: makeFullSummary('2026-11-20T09:00:00Z', 'host-2', '/mnt/c/.codex', 'phys-1', 8.5, 0),
  };
  const oldEnv = {
    environmentId: 'env-old',
    label: 'Legacy',
    summary: { readAt: '2026-11-20T08:00:00Z', pricing: 'fresh', buckets: [], notices: [], contractVersion: 3 },
  };

  const merged = api.mergeUsageSummaries([envA, envB, oldEnv], 6);
  assert.equal(merged.duplicateSources.length, 1);
  assert.equal(merged.contractMismatches.length, 1);
  assert.equal(merged.contractMismatches[0].direction, 'serverBehind');
  assert.equal(merged.costUsd, 8.5);
  assert.equal(merged.cacheSavingsUsd, 10);
  assert.equal(merged.sessions, 9); // codex deduped once (5) + claude-a (2) + claude-b (2)
  assert.equal(merged.categoryCost.input, 1);
  assert.equal(merged.categoryCost.unsplit, 2); // 8.5 - (1 + 2 + 0.5 + 3)
  assert.equal(merged.speedCost.fast, 4);
  assert.equal(merged.speedCost.standard, 4.5);
  assert.equal(merged.speedCost.premium, 2);
  assert.equal(merged.models.find(m => m.model === 'unpriced-model').costUnknown, true);

  const days = api.enumerateUsageDays('2026-11-18', '2026-11-20');
  const bars = api.buildUsageChartBars(days, merged.daily, 'cost');
  assert.equal(bars.length, 3);
  assert.equal(bars[0].total, 0);
  assert.equal(bars[1].total, 8.5);
  assert.equal(bars[1].values[0].provider, 'codex');
});

test('toggleUsageEnvironmentSelection follows all environments when every id is active', () => {
  const ids = ['env-a', 'env-b'];
  const afterRemove = api.toggleUsageEnvironmentSelection(null, ids, 'env-a');
  assert.deepEqual(afterRemove, ['env-b']);
  const afterRestore = api.toggleUsageEnvironmentSelection(afterRemove, ids, 'env-a');
  assert.equal(afterRestore, null);
});

test('pooled limits dedupe across environments, suppress spent-weekly sessions, and compute pace', () => {
  const now = Date.UTC(2026, 10, 20, 12, 0, 0);
  const resetSession = new Date(now + 2 * 3600000).toISOString();
  const resetWeekly = new Date(now + 48 * 3600000).toISOString();

  const snapshots = [
    {
      environmentId: 'env-1',
      label: 'MacBook',
      config: {
        providers: [
          {
            instanceId: 'codex-1',
            driver: 'codex',
            displayName: 'Work Codex',
            auth: { status: 'authenticated', email: 'User@Example.com', label: 'ChatGPT Plus Subscription' },
            usageLimits: {
              checkedAt: '2026-11-20T11:00:00Z',
              externalUsage: { label: 'ChatGPT shared usage', url: api.CHATGPT_USAGE_URL },
              windows: [
                { id: 'primary', kind: 'session', label: '5小时额度', usedPercent: 20, resetsAt: resetSession, windowDurationMins: 300 },
                { id: 'secondary', kind: 'weekly', label: '周额度', usedPercent: 100, resetsAt: resetWeekly, windowDurationMins: 10080 },
              ],
            },
          },
          {
            instanceId: 'cursor-1',
            driver: 'cursor',
            auth: { status: 'authenticated' },
            usageLimits: {
              checkedAt: '2026-11-20T11:30:00Z',
              windows: [
                { id: 'totalPercentUsed', kind: 'monthly', label: 'Total', usedPercent: 40 },
                { id: 'autoPercentUsed', kind: 'monthly', label: 'Auto', usedPercent: 30 },
                { id: 'apiPercentUsed', kind: 'monthly', label: 'API', usedPercent: 50 },
              ],
            },
          },
          {
            instanceId: 'ag-1',
            driver: 'antigravity',
            auth: { status: 'authenticated' },
            usageLimits: {
              checkedAt: '2026-11-20T11:30:00Z',
              windows: [
                { id: 'claude-5h', kind: 'session', label: 'Claude', usedPercent: 10 },
                { id: 'gemini-5h', kind: 'session', label: 'Gemini', usedPercent: 20 },
              ],
            },
          },
        ],
      },
    },
    {
      environmentId: 'env-2',
      label: 'Linux',
      config: {
        providers: [
          {
            instanceId: 'codex-2',
            driver: 'codex',
            displayName: 'Work Codex',
            auth: { status: 'authenticated', email: 'user@example.com', label: 'ChatGPT Pro 100 Subscription' },
            usageLimits: {
              checkedAt: '2026-11-20T11:50:00Z',
              windows: [
                { id: 'primary', kind: 'session', label: '5小时额度', usedPercent: 10, resetsAt: resetSession, windowDurationMins: 300 },
                { id: 'secondary', kind: 'weekly', label: '周额度', usedPercent: 20, resetsAt: resetWeekly, windowDurationMins: 10080 },
              ],
            },
          },
        ],
        usageLimitSources: [
          { id: 'hub-1', label: 'CLI Proxy', accounts: [], error: 'timeout' },
        ],
      },
    },
  ];

  const accounts = api.collectPooledLimitAccounts(snapshots);
  const codexAccounts = accounts.filter(a => a.driver === 'codex');
  assert.equal(codexAccounts.length, 1);
  assert.equal(codexAccounts[0].environments.length, 2);
  assert.equal(codexAccounts[0].windows[1].remaining, 80); // fresher snapshot wins

  // Verify weekly-spent suppression on a separate single account
  const suppressedAccounts = api.collectPooledLimitAccounts([snapshots[0]]);
  const suppressedGroups = api.collectPooledLimitGroups(suppressedAccounts, now);
  const suppressedCodex = suppressedGroups.find(g => g.driver === 'codex');
  assert.equal(suppressedCodex.windows[0].remainingPercent, 0); // weekly=100% suppresses session
  assert.equal(suppressedCodex.windows[0].resets[0].resetsAt, resetWeekly);

  const cursorGroup = suppressedGroups.find(g => g.driver === 'cursor');
  assert.deepEqual(cursorGroup.windows.map(w => w.id), ['autoPercentUsed', 'apiPercentUsed']);
  assert.equal(cursorGroup.windows[0].label, 'Cursor 模型');

  const agGroup = suppressedGroups.find(g => g.driver === 'antigravity');
  assert.equal(agGroup.windows[0].id, 'gemini-5h');

  const notices = api.collectPooledLimitNotices(snapshots);
  assert.equal(notices.length, 1);
  assert.match(notices[0], /CLI Proxy: timeout/);

  const links = api.collectExternalUsageLinks(snapshots);
  assert.equal(links.length, 1);
  assert.equal(links[0].url, api.CHATGPT_USAGE_URL);
});
