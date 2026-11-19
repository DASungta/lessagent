import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { coreUrl, ts, compile, data } from './load-core.mjs';
const environment = data(compile((await readFile(
  new URL('../entry/src/main/ets/protocol/Environment.ts', import.meta.url), 'utf8'))
  .replace("'./Core'", JSON.stringify(coreUrl))
  .replace("'./Wire'", JSON.stringify(new URL('../entry/src/main/ets/protocol/Wire.ts', import.meta.url).href))));
const env = await import(environment);

const bearer = {
  localId: 'local-a', environmentId: 'env-a', base: 'https://a.example.test', label: 'A',
  enabled: true, kind: 'bearer', credentialRef: 't3-v2-local-a-session', recovery: []
};
const cloud = {
  localId: 'local-cloud', environmentId: 'env-cloud', base: 'https://env-cloud.example.test',
  label: 'Cloud', enabled: true, kind: 'cloud', credentialRef: 't3-cloud-local-cloud',
  cloudAccountId: 'user-a', recovery: [{ threadId: 'thread-1', alias: 't3-v2-local-cloud-recovery-one' }]
};
const directory = selectedLocalId => ({ schemaVersion: 2, generation: 4, selectedLocalId,
  entries: [bearer, cloud] });

test('cloud entries coexist with bearer entries but carry no direct route credential', () => {
  const checked = env.environmentDirectory(directory('local-cloud'));
  assert.equal(checked.entries.length, 2);
  assert.deepEqual(env.environmentRoutes(checked.entries[1]), []);
  assert.equal(env.environmentRouteKey(checked.entries[1]),
    'local-cloud:cloud:user-a:https://env-cloud.example.test');
  assert.equal(env.environmentRouteKey({ ...checked.entries[1], base: 'https://new.example.test' }).includes('new'), true);
  assert.equal(env.environmentDirectory({ ...directory('local-cloud'),
    entries: [bearer, { ...cloud, environmentId: 'env-a' }] }).entries.length, 2);
});

test('cloud entry rejects missing/wrong account, insecure endpoint, route overrides, or bearer/cloud identity collision', () => {
  const base = directory('local-cloud');
  for (const entry of [
    { ...cloud, cloudAccountId: undefined },
    { ...cloud, cloudAccountId: '' },
    { ...cloud, base: 'http://env-cloud.example.test' },
    { ...cloud, credentialRef: 't3-v2-local-cloud-session' },
    { ...cloud, alternateRoutes: [{ base: 'https://alt.example.test', credentialRef: 't3-v2-local-cloud-route-x-session' }] },
    { ...cloud, pendingBase: 'https://new.example.test' }
  ]) assert.throws(() => env.environmentDirectory({ ...base, entries: [bearer, entry] }));
});

test('cloud recovery is verified while its session asset is intentionally absent', async () => {
  const store = value => ({ value, async load() { return structuredClone(this.value); },
    async save(next) { this.value = structuredClone(next); } });
  const dir = store({ ...directory('local-cloud'), entries: [cloud] });
  const recovery = store({ base: cloud.base, environmentId: cloud.environmentId, threadId: 'thread-1',
    pendingId: 'unknown', pendingKind: 'message' });
  const assets = {
    session() { throw new Error('cloud must not read bearer sessions'); },
    recovery(alias) {
      assert.equal(alias, cloud.recovery[0].alias);
      return recovery;
    }
  };
  const result = await env.migrateLegacy(dir, assets,
    store(undefined), store(undefined));
  assert.equal(result.entries[0].kind, 'cloud');
  assert.equal(recovery.value.pendingId, 'unknown');
});
