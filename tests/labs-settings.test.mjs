import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { agentFeedbackUrl, compile, data } from './load-core.mjs';

const source = (await readFile(new URL('../entry/src/main/ets/protocol/LabsSettings.ts', import.meta.url), 'utf8'))
  .replace("'./Wire'", JSON.stringify(new URL('../entry/src/main/ets/protocol/Wire.ts', import.meta.url).href))
  .replace("'./AgentFeedback'", JSON.stringify(agentFeedbackUrl));
const api = await import(data(compile(source)));
const linked = 'linkedEnvironmentsEnabled';
const fast = 'fastWorktreeCheckout';
const config = (environmentId, capabilities = { peerLinks: true, fastWorktreeCheckout: true }) => ({
  environment: { environmentId, capabilities },
  settings: { [linked]: false, [fast]: false }
});

test('Labs exposes only typed fields with their own advertised capability and policy', () => {
  const state = config('a', { peerLinks: true });
  state.managedPolicy = { organization: 'Team', lockedSettings: [linked + '.child'] };
  const result = api.labsSettings(state, 'a');
  assert.deepEqual(result[linked], { value: false, locked: true });
  assert.deepEqual(result[fast], { value: undefined, locked: false });
  assert.equal(result.managedBy, 'Team');
  assert.throws(() => api.labsSettings(state, 'b'), /身份/);
  state.environment.capabilities = { peerLinks: 'true', fastWorktreeCheckout: true };
  state.settings[fast] = 'true';
  const partial = api.labsSettings(state, 'a');
  assert.equal(partial[linked].value, undefined);
  assert.equal(partial[fast].value, undefined);
  delete state.environment.capabilities;
  assert.equal(api.labsSettings(state, 'a')[linked].value, undefined);
});

test('Labs switches independently read and write only their target environment and field', async () => {
  const a = config('a');
  const b = config('b', { peerLinks: true });
  const calls = [];
  const connectionFor = state => ({
    ready: true,
    canScope: scope => scope === 'settings:write',
    rpcRequest: async (method, payload, timeout, fatal) => {
      calls.push({ id: state.environment.environmentId, method, payload, fatal });
      if (method === 'server.updateSettings') Object.assign(state.settings, payload.patch);
      return state;
    }
  });
  const connectionA = connectionFor(a);
  const connectionB = connectionFor(b);
  assert.equal((await api.writeLabsSetting(connectionB, 'b', linked, true))[linked].value, true);
  assert.equal((await api.writeLabsSetting(connectionA, 'a', fast, true))[fast].value, true);
  assert.deepEqual(calls, [
    { id: 'b', method: 'server.getConfig', payload: {}, fatal: false },
    { id: 'b', method: 'server.updateSettings', payload: { patch: { [linked]: true } }, fatal: false },
    { id: 'b', method: 'server.getConfig', payload: {}, fatal: false },
    { id: 'a', method: 'server.getConfig', payload: {}, fatal: false },
    { id: 'a', method: 'server.updateSettings', payload: { patch: { [fast]: true } }, fatal: false },
    { id: 'a', method: 'server.getConfig', payload: {}, fatal: false }
  ]);
  assert.equal(a.settings[linked], false);
  assert.equal(b.settings[fast], false);
  await assert.rejects(api.writeLabsSetting(connectionB, 'a', linked, false), /身份/);
  await assert.rejects(api.writeLabsSetting(connectionB, 'b', fast, true), /支持/);
  await assert.rejects(api.writeLabsSetting(connectionB, 'b', 'guestSharingEnabled', true), /支持/);
  await assert.rejects(api.writeLabsSetting(connectionB, 'b', linked, 'false'), /支持/);
  assert.equal(calls.filter(call => call.method === 'server.updateSettings').length, 2);
});

test('fresh policy, revoked scope and dropped connection suppress mutation', async () => {
  const state = config('a');
  let writable = true;
  let revoke = false;
  let disconnect = false;
  const connection = {
    ready: true,
    canScope: () => writable,
    rpcRequest: async method => {
      assert.equal(method, 'server.getConfig');
      if (revoke) writable = false;
      if (disconnect) connection.ready = false;
      return state;
    }
  };
  state.managedPolicy = { organization: 'Team', lockedSettings: [fast] };
  await assert.rejects(api.writeLabsSetting(connection, 'a', fast, true), /组织/);
  revoke = true;
  await assert.rejects(api.writeLabsSetting(connection, 'a', linked, true), /权限/);
  writable = true;
  revoke = false;
  disconnect = true;
  await assert.rejects(api.writeLabsSetting(connection, 'a', linked, true), /断开/);
});

test('writes have no replay on RPC failure or mismatched readback', async () => {
  let writes = 0;
  let fail = true;
  const connection = {
    ready: true, canScope: () => true,
    rpcRequest: async method => {
      if (method === 'server.updateSettings') {
        writes++;
        if (fail) throw new Error('timeout');
      }
      return config('a');
    }
  };
  await assert.rejects(api.writeLabsSetting(connection, 'a', fast, true), /timeout/);
  assert.equal(writes, 1);
  fail = false;
  await assert.rejects(api.writeLabsSetting(connection, 'a', fast, true), /回读/);
  assert.equal(writes, 2);
});
