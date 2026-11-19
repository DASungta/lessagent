import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { cloudUrl } from './load-cloud.mjs';
import { compile, data } from './load-core.mjs';
const cloud = await import(cloudUrl);

async function setup() {
  const records = new Map();
  let locked = false;
  let failWrite = '';
  let failRead = '';
  const key = value => new TextDecoder().decode(value);
  const asset = {
    Tag: { ALIAS: 'alias', SECRET: 'secret', RETURN_TYPE: 'return', ACCESSIBILITY: 'accessibility', CONFLICT_RESOLUTION: 'conflict' },
    ReturnType: { ALL: 'all' },
    Accessibility: { DEVICE_UNLOCKED: 'unlocked' },
    ConflictResolution: { OVERWRITE: 'overwrite' },
    async add(tags) {
      const name = key(tags.get('alias'));
      if (failWrite && name.includes(failWrite)) throw Error('write');
      records.set(name, new Uint8Array(tags.get('secret')));
    },
    async query(tags) {
      const name = key(tags.get('alias'));
      if (failRead && name.includes(failRead)) throw Error('read');
      if (!records.has(name)) throw Object.assign(Error('missing'), { code: 24000002 });
      return [new Map([['secret', new Uint8Array(records.get(name))]])];
    },
    async remove(tags) {
      const name = key(tags.get('alias'));
      if (!records.delete(name)) throw Object.assign(Error('missing'), { code: 24000002 });
    }
  };
  class SessionStore {
    constructor(name) { this.name = name; }
    async load() { const value = records.get(this.name); return value ? JSON.parse(new TextDecoder().decode(value)) : undefined; }
    async save(value) { records.set(this.name, new TextEncoder().encode(JSON.stringify(value))); }
    async clear() { records.delete(this.name); }
  }
  globalThis.__cloudStores = {
    asset, SessionStore,
    util: { TextEncoder: class { encodeInto(value) { return new TextEncoder().encode(value); } },
      TextDecoder: class { decodeToString(value) { return new TextDecoder().decode(value); } } },
    screenLock: { isScreenLocked: async () => locked },
    BusinessError: class {}, cloud
  };
  const source = (await readFile(new URL('../entry/src/main/ets/storage/CloudStores.ets', import.meta.url), 'utf8'))
    .replace(/^import .*? from .*?;\n/gm, '')
    .replace('export class CloudSessionStore', 'const { asset, SessionStore, util, screenLock, cloud } = globalThis.__cloudStores;\nconst { base64UrlEncode, cloudAccountSession, cloudEnvironmentToken, relayTokenCache } = cloud;\nexport class CloudSessionStore');
  const module = await import(data(compile(source) + '\n//' + Math.random()));
  return { store: new module.CloudSessionStore(), records, setLocked: value => locked = value,
    setFailWrite: value => failWrite = value, setFailRead: value => failRead = value };
}

const session = token => ({ accountId: 'user-a', accessToken: token, expiresAt: Date.now() + 60000,
  relayUrl: 'https://relay.example.test', clientId: 't3-harmony',
  redirectUri: 't3code://auth/callback', jwtTemplate: 't3-mobile' });

test('large Clerk sessions commit only after every chunk reads back exactly', async () => {
  const s = await setup();
  const value = session('T'.repeat(2500));
  await s.store.save(value);
  assert.ok(s.records.has('t3-cloud-account-manifest-v1'));
  const manifest = JSON.parse(new TextDecoder().decode(s.records.get('t3-cloud-account-manifest-v1')));
  assert.ok(manifest.chunks >= 3);
  assert.equal((await s.store.load()).accessToken, value.accessToken);
  await s.store.save(session('U'.repeat(900)));
  assert.equal((await s.store.load()).accessToken, 'U'.repeat(900));
  const left = [...s.records.keys()].filter(name => name.startsWith('t3-cloud-account-session-'));
  assert.equal(left.length, 2);
});

test('failed chunk or manifest writes leave the previous account session readable', async () => {
  const s = await setup();
  await s.store.save(session('OLD'));
  s.setFailRead('t3-cloud-account-session-2-0');
  await assert.rejects(s.store.save(session('NEW'.repeat(500))));
  assert.equal((await s.store.load()).accessToken, 'OLD');
  s.setFailRead('');
  s.setFailWrite('t3-cloud-account-manifest-v1');
  await assert.rejects(s.store.save(session('NEW')));
  assert.equal((await s.store.load()).accessToken, 'OLD');
});

test('locked storage rejects read, write and clear without destroying the committed session', async () => {
  const s = await setup();
  await s.store.save(session('SAFE'));
  s.setLocked(true);
  await assert.rejects(s.store.load(), /解锁/);
  await assert.rejects(s.store.save(session('NEW')), /解锁/);
  await assert.rejects(s.store.clear(), /解锁/);
  s.setLocked(false);
  assert.equal((await s.store.load()).accessToken, 'SAFE');
  await s.store.clear();
  assert.equal(await s.store.load(), undefined);
});
