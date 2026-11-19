import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { compile, data } from './load-core.mjs';
const directory = new URL('../entry/src/main/ets/protocol/', import.meta.url);
const wire = JSON.stringify(new URL('Wire.ts', directory).href);
const defaults = data(compile((await readFile(new URL('WorktreeSettings.ts', directory), 'utf8')).replace("'./Wire'", wire)));
const api = await import(data(compile((await readFile(new URL('ProjectWorktreeSettings.ts', directory), 'utf8'))
  .replace("'./Wire'", wire).replace("'./WorktreeSettings'", JSON.stringify(defaults)))));

function testConnection() {
  let state = {
    environment: { environmentId: 'environment', capabilities: { projectSettingsOverrides: true } },
    settings: { newWorktreesStartFromOrigin: true, worktreeSubmodules: null, branchNamingMode: 'static',
      branchNamePrefix: 'env', branchNameInstructions: 'env instructions',
      projectSettingsOverrides: { a: { newWorktreesStartFromOrigin: false, future: { value: ['keep'] },
        providerInstances: { codex: { enabled: false } }, enableAgentBrowserAccess: false }, b: { branchNamePrefix: 'other' } } }
  };
  const writes = [];
  const connection = { ready: true, generation: 1, granted: true, generationValue: () => connection.generation,
    canScope: key => key === 'settings:write' ? connection.granted : true,
    rpcRequest: async (method, params, timeout, fatal) => {
      assert.equal(fatal, false);
      if (method === 'server.getConfig') return structuredClone(state);
      assert.equal(method, 'server.updateSettings');
      writes.push(structuredClone(params));
      const [id, entry] = Object.entries(params.patch.projectSettingsOverrides)[0];
      if (Object.keys(entry).length) state.settings.projectSettingsOverrides[id] = structuredClone(entry);
      else delete state.settings.projectSettingsOverrides[id];
      return {};
    }
  };
  const read = () => api.readProjectWorktreeSettings(connection, 'environment', 'a');
  return { connection, state, writes, read };
}
const field = (snapshot, key) => api.projectWorktreeField(snapshot, key);
const selected = () => true;

test('project settings show effective values and distinguish inherited, explicit false and explicit empty', async () => {
  const { read, state } = testConnection();
  state.settings.projectSettingsOverrides.a.branchNamePrefix = '';
  const snapshot = await read();
  assert.equal(snapshot.supported, true);
  assert.deepEqual(field(snapshot, 'newWorktreesStartFromOrigin'), {
    key: 'newWorktreesStartFromOrigin', source: 'project', value: 'false', locked: false
  });
  assert.equal(field(snapshot, 'branchNamePrefix').value, '');
  assert.equal(field(snapshot, 'branchNamePrefix').source, 'project');
  assert.equal(field(snapshot, 'worktreeSubmodules').value, 'inherit');
  assert.equal(field(snapshot, 'worktreeSubmodules').source, 'environment');
  state.settings.projectSettingsOverrides.a.worktreeSubmodules = 'future';
  assert.equal(field(await read(), 'worktreeSubmodules').value, undefined);
});

test('whole-entry writes and clears preserve unrelated values, do not replace other projects', async () => {
  const { connection, state, writes, read } = testConnection();
  let snapshot = await read();
  snapshot = await api.writeProjectWorktreeSettings(connection, snapshot, 'branchNamePrefix', '   ', selected);
  assert.equal(field(snapshot, 'branchNamePrefix').source, 'project');
  snapshot = await api.writeProjectWorktreeSettings(connection, snapshot, 'worktreeSubmodules', 'none', selected);
  snapshot = await api.writeProjectWorktreeSettings(connection, snapshot, 'worktreeSubmodules', null, selected);
  assert.equal(field(snapshot, 'worktreeSubmodules').source, 'environment');
  snapshot = await api.clearProjectWorktreeSettings(connection, snapshot, selected);
  assert.equal(field(snapshot, 'branchNamePrefix').value, 'env');
  assert.equal(field(snapshot, 'newWorktreesStartFromOrigin').value, 'true');
  const unrelated = { future: { value: ['keep'] }, providerInstances: { codex: { enabled: false } }, enableAgentBrowserAccess: false };
  assert.deepEqual(state.settings.projectSettingsOverrides, { a: unrelated, b: { branchNamePrefix: 'other' } });
  assert.deepEqual(writes.at(-1), { patch: { projectSettingsOverrides: { a: unrelated } } });
  state.settings.projectSettingsOverrides.a = { branchNamePrefix: 'one' };
  await api.clearProjectWorktreeSettings(connection, await read(), selected);
  assert.deepEqual(writes.at(-1), { patch: { projectSettingsOverrides: { a: {} } } });
  assert.equal(state.settings.projectSettingsOverrides.a, undefined);
});

test('missing capability or map, unknown field, missing permission and lock all fail before a write', async () => {
  const { connection, state, read, writes } = testConnection();
  const save = async (key = 'branchNamingMode', value = 'semantic') =>
    api.writeProjectWorktreeSettings(connection, await read(), key, value, selected);
  state.environment.capabilities = {};
  await assert.rejects(save(), /不支持项目/);
  state.environment.capabilities.projectSettingsOverrides = true;
  const map = state.settings.projectSettingsOverrides;
  delete state.settings.projectSettingsOverrides;
  await assert.rejects(save(), /不支持项目/);
  state.settings.projectSettingsOverrides = map;
  await assert.rejects(save('worktreeCleanup', 'off'), /不支持/);
  await assert.rejects(save('branchNameInstructions', 'custom instructions'), /模式/);
  await assert.rejects(save('newWorktreesStartFromOrigin', 'unknown'), /无效/);
  for (const lock of ['branchNamingMode.child', 'projectSettingsOverrides', 'projectSettingsOverrides.a',
    'projectSettingsOverrides.a.branchNamingMode.nested']) {
    state.managedPolicy = { lockedSettings: [lock] };
    await assert.rejects(save(), /组织/);
  }
  state.managedPolicy = { lockedSettings: ['newWorktreesStartFromOrigin'] };
  await assert.rejects(api.clearProjectWorktreeSettings(connection, await read(), selected), /组织/);
  connection.granted = undefined;
  await assert.rejects(save(), /权限/);
  assert.equal(writes.length, 0);
});

test('stale snapshots, connection changes, and overlap cannot overwrite project data', async () => {
  const { connection, state, read, writes } = testConnection();
  const snapshot = await read();
  state.settings.projectSettingsOverrides.a.future.value.push('outside edit');
  await assert.rejects(api.clearProjectWorktreeSettings(connection, snapshot, selected), /覆盖已变化/);
  let finish;
  const previous = connection.rpcRequest;
  const next = await read();
  connection.rpcRequest = async (...args) => {
    if (args[0] === 'server.getConfig') await new Promise(resolve => { finish = resolve; });
    return previous(...args);
  };
  const pending = api.clearProjectWorktreeSettings(connection, next, selected);
  await assert.rejects(api.clearProjectWorktreeSettings(connection, next, selected), /正在保存/);
  connection.generation++;
  finish();
  await assert.rejects(pending, /连接.*变化/);
  assert.equal(writes.length, 0);
});

test('uncertain writes never replay and failed readback is reported', async () => {
  const { connection, read } = testConnection();
  const snapshot = await read();
  let writes = 0;
  let fail = true;
  const previous = connection.rpcRequest;
  connection.rpcRequest = async (...args) => {
    if (args[0] === 'server.getConfig') return previous(...args);
    writes++;
    if (fail) throw Error('timeout');
    return {};
  };
  await assert.rejects(api.clearProjectWorktreeSettings(connection, snapshot, selected), /timeout/);
  assert.equal(writes, 1);
  fail = false;
  await assert.rejects(api.clearProjectWorktreeSettings(connection, snapshot, selected), /回读/);
  assert.equal(writes, 2);
});
