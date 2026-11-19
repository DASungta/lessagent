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
