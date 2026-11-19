import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { compile, data } from './load-core.mjs';

test('active-client permission updates reach both worktree panels and keep live write checks', async () => {
  const source = path => readFile(new URL(`../entry/src/main/ets/${path}`, import.meta.url), 'utf8');
  const [index, settings, defaults, storage] = await Promise.all([
    source('pages/Index.ets'), source('components/SettingsPanel.ets'),
    source('components/WorktreeSettingsPanel.ets'), source('components/WorktreeStoragePanel.ets'),
  ]);
  assert.match(index, /this\.bindEnvironment\(\);[\s\S]*?this\.settingsWriteAllowed = client\.ready \? client\.canScope\('settings:write'\) : false;/);
  assert.match(index, /\bSettingsPanel\(\{[^}]+settingsWriteAllowed: this\.settingsWriteAllowed/);
  for (const [name, panel] of [['WorktreeSettingsPanel', defaults], ['WorktreeStoragePanel', storage]]) {
    assert.ok(settings.includes(`${name}({ connection: this.connection, settingsWriteAllowed: this.settingsWriteAllowed`));
    assert.match(panel, /@Prop settingsWriteAllowed:/);
    assert.match(panel, /this\.settingsWriteAllowed [!=]== (?:false|true)[\s\S]*?\.canScope\('settings:write'\)/);
  }
});

const wireUrl = new URL('../entry/src/main/ets/protocol/Wire.ts', import.meta.url).href;
const worktreeSource = await readFile(new URL('../entry/src/main/ets/protocol/WorktreeSettings.ts', import.meta.url), 'utf8');
const worktreeUrl = data(compile(worktreeSource.replace("'./Wire'", JSON.stringify(wireUrl))));
const source = await readFile(new URL('../entry/src/main/ets/protocol/WorktreeStorage.ts', import.meta.url), 'utf8');
const api = await import(data(compile(source.replace("'./Wire'", JSON.stringify(wireUrl))
  .replace("'./WorktreeSettings'", JSON.stringify(worktreeUrl)))));
const config = () => ({
  environment: { environmentId: 'test-env', platform: { os: 'darwin' },
    capabilities: { worktreesDirectory: true, storageCleanup: true, settledWorktreeCleanup: true, storageCleanupRun: true } },
  settings: { worktreesDirectory: '', worktreeCleanup: null, storageCleanup: {
    worktreeAfterDays: null, worktreeSettledAfterDays: 5, worktreeOnDelete: false, worktreeOnMerge: false,
    worktreeUnchanged: true, worktreeKeepWhen: 'uncommitted-changes', logsAfterDays: 90
  }}
});
const select = (state, key) => api.worktreeStorageField(state, key);

test('directory validates host absolute paths and roots without rewriting the stored input', () => {
  assert.equal(api.worktreeDirectory('darwin', '  /Volumes/QA/work trees  '), '/Volumes/QA/work trees');
  assert.equal(api.worktreeDirectory('linux', '~/worktrees'), '~/worktrees');
  assert.equal(api.worktreeDirectory('windows', 'D:\\worktrees'), 'D:\\worktrees');
  assert.equal(api.worktreeDirectory('windows', '\\\\server\\share\\worktrees'), '\\\\server\\share\\worktrees');
  assert.equal(api.worktreeDirectory('unknown', ' '), '');
  for (const [os, path] of [['linux', 'relative'], ['darwin', '/folder/../'], ['linux', 'C:/outside'], ['windows', 'D:\\'],
    ['windows', '\\\\server\\share'], ['windows', 'D:folder'], ['unknown', '/home']]) {
    assert.throws(() => api.worktreeDirectory(os, path), /宿主机/);
  }
});

test('worktree policy honors field capabilities, mode precedence and parent and child locks', () => {
  const state = config();
  assert.throws(() => api.worktreeStorage(state, 'other'), /身份/);
  state.managedPolicy = { organization: 'Team', lockedSettings: ['storageCleanup.worktreeAfterDays.child'] };
  let snap = api.worktreeStorage(state, 'test-env');
  assert.equal(select(snap, 'worktreeAfterDays').locked, true);
  assert.equal(select(snap, 'worktreeOnMerge').locked, false);
  assert.throws(() => api.worktreeStorageValue(snap, 'worktreeAfterDays', '7'), /组织/);
  state.managedPolicy.lockedSettings = ['worktreeCleanup.rules.worktreeOnMerge'];
  snap = api.worktreeStorage(state, 'test-env');
  assert.equal(select(snap, 'worktreeAfterDays').locked, true);
  assert.equal(select(snap, 'worktreesDirectory').locked, false);
  for (const mode of [{ mode: 'off' }, { mode: 'custom' }, { mode: 'future' }]) {
    state.settings.worktreeCleanup = mode;
    snap = api.worktreeStorage(state, 'test-env');
    assert.equal(select(snap, 'worktreeOnMerge').value, undefined);
  }
  state.settings.worktreeCleanup = null;
  delete state.environment.capabilities.settledWorktreeCleanup;
  delete state.environment.capabilities.storageCleanupRun;
  state.settings.storageCleanup.worktreeOnDelete = 'not-a-bool';
  snap = api.worktreeStorage(state, 'test-env');
  assert.equal(select(snap, 'worktreeSettledAfterDays').value, undefined);
  assert.equal(select(snap, 'worktreeKeepWhen').value, undefined);
  assert.equal(select(snap, 'worktreeOnDelete').value, undefined);
  assert.equal(select(snap, 'worktreeOnMerge').value, false);
});

test('retention validation and weakening file protection require the right confirmation', () => {
  const snap = api.worktreeStorage(config(), 'test-env');
  assert.equal(api.worktreeStorageValue(snap, 'worktreeSettledAfterDays', '0'), 0);
  assert.equal(api.worktreeStorageValue(snap, 'worktreeSettledAfterDays', ''), null);
  for (const invalid of ['0', '2.5', '3651', '-1']) assert.throws(() => api.worktreeStorageValue(snap, 'worktreeAfterDays', invalid));
  assert.equal(api.worktreeStorageNeedsConfirmation(snap, 'worktreeAfterDays', '1'), true);
  assert.equal(api.worktreeStorageNeedsConfirmation(snap, 'worktreeOnDelete', 'true'), true);
  assert.equal(api.worktreeStorageNeedsConfirmation(snap, 'worktreeSettledAfterDays', '7'), false);
  assert.equal(api.worktreeStorageNeedsConfirmation(snap, 'worktreeSettledAfterDays', '4'), true);
  assert.equal(api.worktreeStorageNeedsConfirmation(snap, 'worktreeKeepWhen', 'tracked-changes'), true);
  assert.equal(api.worktreeStorageNeedsConfirmation(snap, 'worktreeKeepWhen', 'any-local-files'), false);
});

test('fresh config checks stronger rules and sends only the confirmed field, preserving other values', async () => {
  const state = config();
  const calls = [];
  const connection = { ready: true, canScope: () => true, rpcRequest: async (method, data) => {
    calls.push([method, data]);
    if (method === 'server.updateSettings') {
      if (data.patch.storageCleanup) Object.assign(state.settings.storageCleanup, data.patch.storageCleanup);
      else Object.assign(state.settings, data.patch);
    }
    return state;
  }};
  await assert.rejects(api.writeWorktreeStorage(connection, 'test-env', 'worktreeAfterDays', '5', false, () => true), /确认/);
  await api.writeWorktreeStorage(connection, 'test-env', 'worktreeAfterDays', '5', true, () => true);
  await api.writeWorktreeStorage(connection, 'test-env', 'worktreeAfterDays', '', false, () => true);
  await api.writeWorktreeStorage(connection, 'test-env', 'worktreesDirectory', '/work/t3', false, () => true);
  assert.deepEqual(calls.filter(([method]) => method !== 'server.getConfig'), [
    ['server.updateSettings', { patch: { storageCleanup: { worktreeAfterDays: 5 } } }],
    ['server.updateSettings', { patch: { storageCleanup: { worktreeAfterDays: null } } }],
    ['server.updateSettings', { patch: { worktreesDirectory: '/work/t3' } }]
  ]);
  assert.equal(state.settings.storageCleanup.logsAfterDays, 90);
  assert.equal(state.settings.storageCleanup.worktreeSettledAfterDays, 5);
});

test('no stale or unauthorized write and no replay on uncertain results', async () => {
  let writes = 0;
  let allowed = true;
  let timeout = true;
  const connection = { ready: true, canScope: () => allowed, rpcRequest: async method => {
    if (method === 'server.updateSettings') { writes++; if (timeout) throw new Error('timeout'); }
    return config();
  }};
  const save = (selected = () => true) => api.writeWorktreeStorage(connection, 'test-env', 'worktreeOnDelete', 'true', true, selected);
  await assert.rejects(save(() => false), /变化/);
  allowed = false;
  await assert.rejects(save(), /权限/);
  allowed = true;
  assert.equal(writes, 0);
  await assert.rejects(save(), /timeout/);
  assert.equal(writes, 1);
  timeout = false;
  await assert.rejects(save(), /回读/);
  assert.equal(writes, 2);
});
