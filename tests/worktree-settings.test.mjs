import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { compile, data } from './load-core.mjs';
const source = (await readFile(new URL('../entry/src/main/ets/protocol/WorktreeSettings.ts', import.meta.url), 'utf8'))
  .replace("'./Wire'", JSON.stringify(new URL('../entry/src/main/ets/protocol/Wire.ts', import.meta.url).href));
const api = await import(data(compile(source)));
const config = () => ({ environment: { environmentId: 'a' }, settings: { newWorktreesStartFromOrigin: true, worktreeSubmodules: null } });

test('worktree settings reject missing, future values and wrong environment', () => {
  assert.equal(api.worktreeDefaults(config(), 'a').submodules, 'inherit');
  assert.throws(() => api.worktreeDefaults(config(), 'b'));
  assert.throws(() => api.worktreeDefaults({ ...config(), settings: {} }, 'a'));
  assert.throws(() => api.worktreeDefaults({ ...config(), settings: { ...config().settings, worktreeSubmodules: 'future' } }, 'a'));
});
test('worktree patch preserves null inheritance, validates options and organization locks', () => {
  const current = api.worktreeDefaults(config(), 'a');
  assert.deepEqual(api.worktreePatch(current, 'worktreeSubmodules', 'inherit'), { worktreeSubmodules: null });
  assert.deepEqual(api.worktreePatch(current, 'newWorktreesStartFromOrigin', 'false'), { newWorktreesStartFromOrigin: false });
  assert.throws(() => api.worktreePatch(current, 'newWorktreesStartFromOrigin', 'yes'));
  assert.throws(() => api.worktreePatch(current, 'worktreeSubmodules', 'future'));
  assert.throws(() => api.worktreePatch(current, 'providers', 'none'));
  const locked = api.worktreeDefaults({ ...config(), managedPolicy: { organization: 'Team', lockedSettings: ['worktreeSubmodules'] } }, 'a');
  assert.equal(locked.managedBy, 'Team');
  assert.throws(() => api.worktreePatch(locked, 'worktreeSubmodules', 'none'));
});
test('settings mutation re-reads policy, writes only one field and confirms readback', async () => {
  const state = config(); const calls = [];
  const connection = { ready: true, canScope: () => true, rpcRequest: async (method, payload) => {
    calls.push({method,payload});
    if (method === 'server.updateSettings') { Object.assign(state.settings, payload.patch); return state.settings; }
    return state;
  }};
  const result = await api.writeWorktreeDefault(connection, 'a', 'worktreeSubmodules', 'none');
  assert.equal(result.submodules, 'none');
  assert.deepEqual(calls.map(c => c.method), ['server.getConfig','server.updateSettings','server.getConfig']);
  assert.deepEqual(calls[1].payload, {patch:{worktreeSubmodules:'none'}});
  connection.canScope = () => false;
  await assert.rejects(api.writeWorktreeDefault(connection, 'a', 'worktreeSubmodules', 'recursive'));
  assert.equal(calls.length, 3);
});
test('failed or mismatched writes never replay automatically', async () => {
  let writes = 0;
  const connection = { ready: true, canScope: () => true, rpcRequest: async method => {
    if (method === 'server.updateSettings') { writes++; throw Error('timeout'); }
    return config();
  }};
  await assert.rejects(api.writeWorktreeDefault(connection, 'a', 'worktreeSubmodules', 'none'));
  assert.equal(writes, 1);
  connection.rpcRequest = async method => { if(method === 'server.updateSettings') writes++; return config(); };
  await assert.rejects(api.writeWorktreeDefault(connection, 'a', 'worktreeSubmodules', 'none'), /回读/);
  assert.equal(writes, 2);
  connection.rpcRequest = async () => ({ ...config(), managedPolicy:{ lockedSettings:['worktreeSubmodules'] } });
  await assert.rejects(api.writeWorktreeDefault(connection, 'a', 'worktreeSubmodules', 'none'), /组织/);
  assert.equal(writes, 2);
});

function branchConfig(mode = 'static') {
  const state = config();
  Object.assign(state.settings, { branchNamingMode: mode, branchNamePrefix: 'team', branchNameInstructions: 'Use ticket ID' });
  return state;
}

test('branch naming uses upstream modes and preserves stored values outside the active mode', async () => {
  const state = branchConfig();
  const writes = [];
  const connection = { ready: true, canScope: () => true, rpcRequest: async (method, payload) => {
    if (method === 'server.updateSettings') { writes.push(payload.patch); Object.assign(state.settings, payload.patch); }
    return state;
  }};
  await api.writeWorktreeDefault(connection, 'a', 'branchNamePrefix', '   ');
  assert.equal(state.settings.branchNamePrefix, '');
  await api.writeWorktreeDefault(connection, 'a', 'branchNamingMode', 'semantic');
  await assert.rejects(api.writeWorktreeDefault(connection, 'a', 'branchNamePrefix', 'hidden'));
  await api.writeWorktreeDefault(connection, 'a', 'branchNamingMode', 'custom');
  assert.equal(state.settings.branchNameInstructions, 'Use ticket ID');
  await api.writeWorktreeDefault(connection, 'a', 'branchNameInstructions', '  Team label\nthen ticket ID  ');
  await api.writeWorktreeDefault(connection, 'a', 'branchNamingMode', 'static');
  assert.equal(state.settings.branchNamePrefix, '');
  assert.equal(state.settings.branchNameInstructions, 'Team label\nthen ticket ID');
  assert.deepEqual(writes, [
    { branchNamePrefix: '' }, { branchNamingMode: 'semantic' }, { branchNamingMode: 'custom' },
    { branchNameInstructions: 'Team label\nthen ticket ID' }, { branchNamingMode: 'static' }
  ]);
});

test('unknown branch modes, field locks, changing permissions and switched context suppress writes', async () => {
  const old = api.worktreeDefaults(config(), 'a');
  assert.throws(() => api.worktreePatch(old, 'branchNamingMode', 'static'));
  const future = api.worktreeDefaults(branchConfig('future'), 'a');
  assert.throws(() => api.worktreePatch(future, 'branchNamingMode', 'static'));
  assert.throws(() => api.worktreePatch(future, 'branchNamePrefix', 'team'));
  const state = branchConfig();
  state.managedPolicy = { lockedSettings: ['branchNamePrefix.child'] };
  assert.equal(api.worktreeSettingLocked(['storageCleanup'], 'storageCleanup.worktreeAfterDays'), true);
  let scope = true;
  const connection = { ready: true, canScope: () => scope, rpcRequest: async method => {
    assert.equal(method, 'server.getConfig');
    return state;
  }};
  await assert.rejects(api.writeWorktreeDefault(connection, 'a', 'branchNamePrefix', 'other'), /组织/);
  await assert.rejects(api.writeWorktreeDefault(connection, 'a', 'branchNamingMode', 'custom', () => false), /环境或权限/);
  connection.rpcRequest = async method => { assert.equal(method, 'server.getConfig'); scope = undefined; return state; };
  await assert.rejects(api.writeWorktreeDefault(connection, 'a', 'branchNamingMode', 'custom'), /环境或权限/);
});
