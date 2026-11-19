import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { compile, data } from './load-core.mjs';

const source = (await readFile(new URL('../entry/src/main/ets/protocol/ServiceMaintenance.ts', import.meta.url), 'utf8'))
  .replace("'./Wire'", JSON.stringify(new URL('../entry/src/main/ets/protocol/Wire.ts', import.meta.url).href));
const api = await import(data(compile(source)));
const config = (serverVersion = '1.2.9', capabilities = {}) => ({
  environment: { environmentId: 'a', serverVersion, capabilities },
  settings: { continueThreadsAfterServerUpdate: true }
});

test('maintenance reads advertised fields without exposing paths or fabricating old-server capabilities', () => {
  const value = config('1.2.9', { serverInstallation: { kind: 't3-launcher', baseDir: '/private' },
    serverSelfUpdate: 'desktop-managed', threadRestartContinuation: true, npmReleaseLookup: true, databaseStorage: true });
  assert.deepEqual(api.maintenanceInfo(value, 'a'), {
    environmentId: 'a', version: '1.2.9', installation: 't3-launcher', updateMethod: 'desktop-managed',
    desktopCanUpdate: false, registrySpec: 'latest', databaseSupported: true, restartContinuation: true, updatesManagedBy: ''
  });
  const old = api.maintenanceInfo(config('1.2.3-preview.20261119.1', { npmReleaseLookup: true, serverInstallation: 'future' }), 'a');
  assert.equal(old.registrySpec, '');
  assert.equal(old.installation, '');
  assert.equal(old.databaseSupported, false);
  assert.equal(old.restartContinuation, undefined);
  assert.throws(() => api.maintenanceInfo(value, 'b'), /身份/);
});

test('database stream handles null and safe byte counts, stopping after one item', async () => {
  const value = config('1.2.9', { databaseStorage: true });
  const info = api.maintenanceInfo(value, 'a');
  let event;
  let stopped = 0;
  let payload = null;
  const connection = {
    ready: true, config: value, canScope: () => true,
    watchRpcStream: (method, params, listener) => {
      assert.equal(method, 'server.getDatabaseStorage');
      assert.deepEqual(params, {});
      event = listener;
      listener(payload);
      listener({ databaseBytes: -1 });
      return listener;
    },
    stopRpcStream: handle => { assert.equal(handle, event); stopped++; }
  };
  assert.equal(await api.readDatabaseStorage(connection, info), null);
  payload = { databaseBytes: 100, reclaimableBytes: 0, incrementalVacuumEnabled: false,
    compactCommand: '/secret command', reclaimFailure: 'private error' };
  assert.deepEqual(await api.readDatabaseStorage(connection, info), {
    databaseBytes: 100, reclaimableBytes: 0, incrementalVacuumEnabled: false, canReclaim: false, reclaimFailed: true
  });
  payload = { ...payload, databaseBytes: -1 };
  await assert.rejects(api.readDatabaseStorage(connection, info));
  assert.equal(stopped, 3);
  await assert.rejects(api.readDatabaseStorage(connection, { ...info, databaseSupported: false }), /未提供/);
});

test('explicit checks use the target server registry and numerically compare same-track versions', async () => {
  const calls = [];
  let reply = { version: '1.2.10' };
  const connection = {
    ready: true, config: config('1.2.9', { npmReleaseLookup: true }), canScope: () => true,
    rpcRequest: async (method, params, timeout, fatal) => {
      calls.push({ method, params, fatal });
      return method === 'server.getConfig' ? connection.config : reply;
    }
  };
  assert.deepEqual(await api.checkServiceRelease(connection, 'a'), {
    installedVersion: '1.2.9', registryVersion: '1.2.10', updateAvailable: true
  });
  assert.deepEqual(calls, [
    { method: 'server.getConfig', params: {}, fatal: false },
    { method: 'server.getNpmRelease', params: { spec: 'latest' }, fatal: false }
  ]);
  reply = { version: '1.2.9-nightly.20261119.9' };
  await assert.rejects(api.checkServiceRelease(connection, 'a'), /响应无效/);
  reply = { version: '1.2.9' };
  assert.equal((await api.checkServiceRelease(connection, 'a')).updateAvailable, false);
  connection.config.environment.serverVersion = '1.2.9-nightly.20261119.9';
  reply = { version: '1.2.9-nightly.20261119.10' };
  assert.equal((await api.checkServiceRelease(connection, 'a')).updateAvailable, true);
  assert.deepEqual(calls.at(-1).params, { spec: 'nightly' });
  reply = { version: '1.2.10' };
  await assert.rejects(api.checkServiceRelease(connection, 'a'), /响应无效/);
  reply = null;
  assert.equal((await api.checkServiceRelease(connection, 'a')).registryVersion, null);
});

test('policy, capabilities and revoked scope stop lookup before contacting the registry', async () => {
  const value = config('1.2.9', { npmReleaseLookup: true });
  const connection = {
    ready: true, config: value, canScope: () => true,
    rpcRequest: async method => { assert.equal(method, 'server.getConfig'); return value; }
  };
  value.managedPolicy = { organization: 'Team', limits: { updates: { mode: 'off' } } };
  assert.equal(api.maintenanceInfo(value, 'a').updatesManagedBy, 'Team');
  await assert.rejects(api.checkServiceRelease(connection, 'a'), /无法检查/);
  delete value.managedPolicy;
  delete value.environment.capabilities.npmReleaseLookup;
  await assert.rejects(api.checkServiceRelease(connection, 'a'), /无法检查/);
  value.environment.capabilities.npmReleaseLookup = true;
  connection.rpcRequest = async () => { connection.canScope = scope => scope !== 'environment:maintain'; return value; };
  await assert.rejects(api.checkServiceRelease(connection, 'a'), /权限已变化/);
});

function reclaimConnection() {
  const calls = [];
  const connection = {
    ready: true, generation: 1, writable: true, config: config('1.2.9', { databaseStorage: true }),
    database: { databaseBytes: 100, reclaimableBytes: 25, incrementalVacuumEnabled: false, canReclaim: true },
    generationValue: () => connection.generation,
    canScope: scope => scope !== 'environment:maintain' || connection.writable,
    rpcRequest: async (method, payload, timeout, fatal) => {
      calls.push([method, payload, fatal]);
      if (method === 'server.getConfig') return connection.config;
      assert.equal(method, 'server.reclaimDatabaseSpace');
      return undefined;
    },
    watchRpcStream: (method, payload, listener) => {
      calls.push([method, payload]);
      listener(connection.database);
      return listener;
    },
    stopRpcStream: () => { calls.push(['stop']); }
  };
  return { connection, calls };
}

test('reclaim refreshes capabilities and storage, submits Void once, and verifies storage after reconnect', async () => {
  const { connection, calls } = reclaimConnection();
  const generation = await api.requestDatabaseReclaim(connection, 'a', () => true);
  assert.equal(generation, 1);
  assert.deepEqual(calls, [
    ['server.getConfig', {}, false], ['server.getDatabaseStorage', {}], ['stop'],
    ['server.reclaimDatabaseSpace', {}, false]
  ]);
  connection.generation++;
  connection.database = { ...connection.database, reclaimableBytes: 0, incrementalVacuumEnabled: true };
  assert.equal((await api.verifyDatabaseReclaim(connection, 'a', generation, () => true)).incrementalVacuumEnabled, true);
  assert.deepEqual(calls.slice(-3), [['server.getConfig', {}, false], ['server.getDatabaseStorage', {}], ['stop']]);
});

test('reclaim refuses unsupported, stale, malformed, empty or already automatic storage and lost permissions', async () => {
  const { connection, calls } = reclaimConnection();
  const database = connection.database;
  for (const status of [
    null, { ...database, canReclaim: undefined }, { ...database, reclaimableBytes: 0 },
    { ...database, reclaimableBytes: 101 }, { ...database, incrementalVacuumEnabled: true }
  ]) {
    connection.database = status;
    await assert.rejects(api.requestDatabaseReclaim(connection, 'a', () => true));
  }
  connection.database = database;
  await assert.rejects(api.requestDatabaseReclaim(connection, 'a', () => false), /已变化/);
  const watch = connection.watchRpcStream;
  connection.watchRpcStream = (...args) => { connection.generation++; return watch(...args); };
  await assert.rejects(api.requestDatabaseReclaim(connection, 'a', () => true), /已变化/);
  connection.watchRpcStream = (...args) => { connection.writable = false; return watch(...args); };
  await assert.rejects(api.requestDatabaseReclaim(connection, 'a', () => true), /已变化/);
  assert.equal(calls.some(([method]) => method === 'server.reclaimDatabaseSpace'), false);
});

test('failed submission and abandoned verification do not replay reclaim', async () => {
  const { connection, calls } = reclaimConnection();
  const rpc = connection.rpcRequest;
  connection.rpcRequest = async (...args) => {
    const result = await rpc(...args);
    if (args[0] === 'server.reclaimDatabaseSpace') throw new Error('timeout');
    return result;
  };
  await assert.rejects(api.requestDatabaseReclaim(connection, 'a', () => true), /timeout/);
  await assert.rejects(api.verifyDatabaseReclaim(connection, 'a', 1, () => false), /刷新/);
  assert.equal(calls.filter(([method]) => method === 'server.reclaimDatabaseSpace').length, 1);
});
