import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { compile, data } from './load-core.mjs';

const directory = new URL('../entry/src/main/ets/protocol/', import.meta.url);
const wire = JSON.stringify(new URL('Wire.ts', directory).href);
const defaults = data(compile((await readFile(new URL('WorktreeSettings.ts', directory), 'utf8')).replace("'./Wire'", wire)));
const api = await import(data(compile((await readFile(new URL('SourceControlSettings.ts', directory), 'utf8'))
  .replace("'./Wire'", wire).replace("'./WorktreeSettings'", JSON.stringify(defaults)))));

function fixture() {
  const config = { environment: { environmentId: 'environment' }, settings: {
    defaultAutoPull: false, ghqCloneLayout: false, addProjectBaseDirectory: '~/repos', removeAgentCreditsOnMerge: false
  }};
  const calls = [];
  const adopted = [];
  const connection = { ready: true, generation: 1, scope: true, generationValue: () => connection.generation,
    canScope: key => key === 'settings:write' ? connection.scope : true,
    rpcRequest: async (method, payload, timeout, fatal) => {
      assert.equal(fatal, false);
      calls.push({ method, payload });
      if (method === 'server.getConfig') return structuredClone(config);
      assert.equal(method, 'server.updateSettings');
      Object.assign(config.settings, payload.patch);
      return {};
    },
    applyVerifiedSettingsConfig: (value, id, generation) => adopted.push({ value, id, generation })
  };
  const read = () => api.readSourceControlSettings(connection, 'environment');
  return { config, connection, calls, adopted, read };
}
const selected = () => true;
const field = (snapshot, key) => api.sourceControlField(snapshot, key);

test('settings are exposed only when the server returns the real field wire types', async () => {
  const { config, read } = fixture();
  const snapshot = await read();
  assert.equal(field(snapshot, 'defaultAutoPull').value, false);
  assert.equal(field(snapshot, 'removeAgentCreditsOnMerge').value, false);
  assert.equal(field(snapshot, 'addProjectBaseDirectory').value, '~/repos');
  config.settings.ghqCloneLayout = 'true';
  delete config.settings.defaultAutoPull;
  config.settings.addProjectBaseDirectory = '';
  const old = await read();
  assert.equal(field(old, 'ghqCloneLayout').value, undefined);
  assert.equal(field(old, 'defaultAutoPull').value, undefined);
  assert.equal(field(old, 'addProjectBaseDirectory').value, '');
});

test('checks and readback send only the chosen field and publish verified clone defaults', async () => {
  const { connection, calls, adopted, read } = fixture();
  let snapshot = await read();
  for (const [key, value] of [
    ['defaultAutoPull', true], ['ghqCloneLayout', true], ['addProjectBaseDirectory', '  '], ['removeAgentCreditsOnMerge', true]
  ]) snapshot = await api.writeSourceControlSetting(connection, snapshot, key, value, selected);
  assert.deepEqual(calls.filter(call => call.method !== 'server.getConfig'), [
    { method: 'server.updateSettings', payload: { patch: { defaultAutoPull: true } } },
    { method: 'server.updateSettings', payload: { patch: { ghqCloneLayout: true } } },
    { method: 'server.updateSettings', payload: { patch: { addProjectBaseDirectory: '' } } },
    { method: 'server.updateSettings', payload: { patch: { removeAgentCreditsOnMerge: true } } }
  ]);
  assert.deepEqual(adopted.map(item => [item.id, item.generation, item.value.settings.addProjectBaseDirectory]),
    [['environment', 1, '~/repos'], ['environment', 1, '']]);
});

test('context and permission changes, locks and a stale value do not write', async () => {
  const { config, connection, calls, read } = fixture();
  const snapshot = await read();
  const save = (key, value, current = selected) => api.writeSourceControlSetting(connection, snapshot, key, value, current);
  await assert.rejects(save('ghqCloneLayout', 'true'), /无效/);
  await assert.rejects(save('providers', true), /无效/);
  await assert.rejects(save('ghqCloneLayout', true, () => false), /变化/);
  config.managedPolicy = { organization: 'Team', lockedSettings: ['ghqCloneLayout.child'] };
  await assert.rejects(save('ghqCloneLayout', true), /组织/);
  delete config.managedPolicy;
  config.settings.addProjectBaseDirectory = '~/other';
  await assert.rejects(save('addProjectBaseDirectory', '~/overwrite'), /变化/);
  connection.scope = undefined;
  await assert.rejects(save('defaultAutoPull', true), /权限/);
  connection.scope = true;
  connection.generation++;
  await assert.rejects(save('defaultAutoPull', true), /变化/);
  assert.equal(calls.some(call => call.method === 'server.updateSettings'), false);
});

test('uncertain write and mismatched readback are never replayed or applied to the client', async () => {
  const { connection, adopted, read } = fixture();
  const snapshot = await read();
  const original = connection.rpcRequest;
  let writes = 0;
  let timeout = true;
  connection.rpcRequest = async (...args) => {
    if (args[0] === 'server.getConfig') return original(...args);
    writes++;
    if (timeout) throw Error('timeout');
    return {};
  };
  const save = () => api.writeSourceControlSetting(connection, snapshot, 'ghqCloneLayout', true, selected);
  await assert.rejects(save(), /timeout/);
  assert.equal(writes, 1);
  timeout = false;
  await assert.rejects(save(), /回读/);
  assert.equal(writes, 2);
  assert.equal(adopted.length, 0);
});
