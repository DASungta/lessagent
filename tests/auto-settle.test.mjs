import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { compile, data } from './load-core.mjs';

const source = (await readFile(new URL('../entry/src/main/ets/protocol/AutoSettle.ts', import.meta.url), 'utf8'))
  .replace("'./Wire'", JSON.stringify(new URL('../entry/src/main/ets/protocol/Wire.ts', import.meta.url).href));
const api = await import(data(compile(source)));
const merge = 'sidebarAutoSettleOnMerge';
const days = 'sidebarAutoSettleAfterDays';
const keep = 'sidebarAutoSettleKeepPullRequests';
const config = () => ({
  environment: { environmentId: 'a', capabilities: { threadAutoSettlement: true, threadAutoSettlementScope: true } },
  settings: { [merge]: true, [days]: 7, [keep]: false }
});

test('advertised capabilities and typed values are required independently', () => {
  const state = config();
  delete state.environment.capabilities.threadAutoSettlementScope;
  state.settings[days] = null;
  assert.deepEqual(api.autoSettleSettings(state, 'a').fields.map(field => field.value), [true, null, undefined]);
  delete state.environment.capabilities;
  assert.deepEqual(api.autoSettleSettings(state, 'a').fields.map(field => field.value), [undefined, undefined, undefined]);
  state.environment.capabilities = { threadAutoSettlement: true };
  state.settings[merge] = 'false';
  state.settings[days] = 91;
  assert.deepEqual(api.autoSettleSettings(state, 'a').fields.map(field => field.value), [undefined, undefined, undefined]);
  assert.throws(() => api.autoSettleSettings(state, 'b'), /身份/);
});

test('confirmed RPCs preserve fraction, null and boolean values in single-field patches', async () => {
  const state = config();
  const calls = [];
  const connection = {
    ready: true, canScope: () => true,
    rpcRequest: async (method, payload, timeout, fatal) => {
      calls.push({ method, payload, fatal });
      if (method === 'server.updateSettings') Object.assign(state.settings, payload.patch);
      return state;
    }
  };
  for (const [key, value] of [[days, 3.5], [days, null], [merge, false], [keep, true]]) {
    calls.length = 0;
    assert.equal(api.autoSettleField(await api.writeAutoSettleSetting(connection, 'a', key, value), key).value, value);
    assert.deepEqual(calls, [
      { method: 'server.getConfig', payload: {}, fatal: false },
      { method: 'server.updateSettings', payload: { patch: { [key]: value } }, fatal: false },
      { method: 'server.getConfig', payload: {}, fatal: false }
    ]);
  }
  for (const invalid of [0, 91, NaN, Infinity, '2', true]) {
    calls.length = 0;
    await assert.rejects(api.writeAutoSettleSetting(connection, 'a', days, invalid), /无效/);
    assert.deepEqual(calls.map(call => call.method), ['server.getConfig']);
  }
});

test('fresh locks, permissions and connection changes prevent writes', async () => {
  const state = config();
  let permission = true;
  const connection = {
    ready: true, canScope: () => permission,
    rpcRequest: async (method) => {
      assert.equal(method, 'server.getConfig');
      return state;
    }
  };
  state.managedPolicy = { organization: 'Team', lockedSettings: [merge + '.child'] };
  let snapshot = api.autoSettleSettings(state, 'a');
  assert.equal(snapshot.managedBy, 'Team');
  assert.equal(api.autoSettleField(snapshot, merge).locked, true);
  assert.equal(api.autoSettleField(snapshot, days).locked, false);
  await assert.rejects(api.writeAutoSettleSetting(connection, 'a', merge, false), /组织/);
  connection.rpcRequest = async () => { permission = false; return state; };
  await assert.rejects(api.writeAutoSettleSetting(connection, 'a', days, 2), /权限/);
  permission = true;
  connection.rpcRequest = async () => { connection.ready = false; return state; };
  await assert.rejects(api.writeAutoSettleSetting(connection, 'a', days, 2), /断开/);
});

test('timeout and readback mismatch leave at most one mutation per attempt', async () => {
  let attempts = 0;
  let fail = true;
  const connection = {
    ready: true, canScope: () => true,
    rpcRequest: async (method) => {
      if (method === 'server.updateSettings') {
        attempts++;
        if (fail) throw new Error('timeout');
      }
      return config();
    }
  };
  await assert.rejects(api.writeAutoSettleSetting(connection, 'a', merge, false), /timeout/);
  assert.equal(attempts, 1);
  fail = false;
  await assert.rejects(api.writeAutoSettleSetting(connection, 'a', merge, false), /回读/);
  assert.equal(attempts, 2);
});
