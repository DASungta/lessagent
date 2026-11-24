import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { cloudUrl } from './load-cloud.mjs';
import { compile, data } from './load-core.mjs';
const cloud = await import(cloudUrl);

const key = 'pk_test_' + Buffer.from('clerk.example.test$').toString('base64');

async function setup() {
  const records = new Map();
  let locked = false;
  let failWrite = '';
  let failRead = '';
  const decodeKey = value => new TextDecoder().decode(value);
  const asset = {
    Tag: { ALIAS: 'alias', SECRET: 'secret', RETURN_TYPE: 'return', ACCESSIBILITY: 'accessibility', CONFLICT_RESOLUTION: 'conflict' },
    ReturnType: { ALL: 'all' },
    Accessibility: { DEVICE_UNLOCKED: 'unlocked' },
    ConflictResolution: { OVERWRITE: 'overwrite' },
    async add(tags) {
      const name = decodeKey(tags.get('alias'));
      const secret = new Uint8Array(tags.get('secret'));
      if (secret.length > 1024) throw Error('HarmonyOS Asset secret limit exceeded: ' + secret.length);
      if (failWrite && name.includes(failWrite)) throw Error('write');
      records.set(name, secret);
    },
    async query(tags) {
      const name = decodeKey(tags.get('alias'));
      if (failRead && name.includes(failRead)) throw Error('read');
      if (!records.has(name)) throw Object.assign(Error('missing'), { code: 24000002 });
      return [new Map([['secret', new Uint8Array(records.get(name))]])];
    },
    async remove(tags) {
      const name = decodeKey(tags.get('alias'));
      if (!records.delete(name)) throw Object.assign(Error('missing'), { code: 24000002 });
    }
  };
  class SessionStore {
    constructor(name) { this.name = name; }
    async load() { const value = records.get(this.name); return value ? JSON.parse(new TextDecoder().decode(value)) : undefined; }
    async save(value) {
      const bytes = new TextEncoder().encode(JSON.stringify(value));
      if (bytes.length > 1024) throw Error('凭据超过系统安全存储大小限制，未保存');
      records.set(this.name, bytes);
    }
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
    .replace('class ChunkedAssetStore', 'const { asset, SessionStore, util, screenLock, cloud } = globalThis.__cloudStores;\nconst { base64UrlEncode, cloudAccountSession, cloudEnvironmentToken, pendingSsoSignIn, relayTokenCache } = cloud;\nclass ChunkedAssetStore');
  const module = await import(data(compile(source) + '\n//' + Math.random()));
  return {
    store: new module.CloudSessionStore(),
    ssoStore: new module.PendingSsoStore(),
    relayStore: new module.RelayTokenStore(),
    envStore: new module.CloudEnvironmentTokenStore(),
    records,
    setLocked: value => locked = value,
    setFailWrite: value => failWrite = value,
    setFailRead: value => failRead = value
  };
}

const session = token => ({
  version: 2,
  accountId: 'user-a',
  sessionId: 'sess-a',
  clientToken: token,
  email: 'a@example.test',
  displayName: 'User A',
  publishableKey: key,
  relayUrl: 'https://relay.example.test',
  jwtTemplate: 't3-relay',
  redirectUri: 't3code://app/'
});

test('large Clerk sessions commit only after every chunk reads back exactly', async () => {
  const s = await setup();
  const value = session('T'.repeat(2500));
  await s.store.save(value);
  assert.ok(s.records.has('t3-cloud-account-manifest-v1'));
  const manifest = JSON.parse(new TextDecoder().decode(s.records.get('t3-cloud-account-manifest-v1')));
  assert.ok(manifest.chunks >= 3);
  assert.equal((await s.store.load()).clientToken, value.clientToken);
  await s.store.save(session('U'.repeat(900)));
  assert.equal((await s.store.load()).clientToken, 'U'.repeat(900));
  const left = [...s.records.keys()].filter(name => name.startsWith('t3-cloud-account-session-'));
  assert.equal(left.length, 2);
});

test('failed chunk or manifest writes leave the previous account session readable', async () => {
  const s = await setup();
  await s.store.save(session('OLD'));
  s.setFailRead('t3-cloud-account-session-2-0');
  await assert.rejects(s.store.save(session('NEW'.repeat(500))));
  assert.equal((await s.store.load()).clientToken, 'OLD');
  s.setFailRead('');
  s.setFailWrite('t3-cloud-account-manifest-v1');
  await assert.rejects(s.store.save(session('NEW')));
  assert.equal((await s.store.load()).clientToken, 'OLD');
});

test('locked storage rejects read, write and clear without destroying the committed session', async () => {
  const s = await setup();
  await s.store.save(session('SAFE'));
  s.setLocked(true);
  await assert.rejects(s.store.load(), /解锁/);
  await assert.rejects(s.store.save(session('NEW')), /解锁/);
  await assert.rejects(s.store.clear(), /解锁/);
  s.setLocked(false);
  assert.equal((await s.store.load()).clientToken, 'SAFE');
  await s.store.clear();
  assert.equal(await s.store.load(), undefined);
});

test('PendingSsoStore persists large pending SSO records across chunks and expires stale records', async () => {
  const s = await setup();
  const pending = {
    signInId: 'sia_1',
    strategy: 'oauth_github',
    clientToken: 'tok_' + 'A'.repeat(1400),
    publishableKey: key,
    relayUrl: 'https://relay.example.test',
    jwtTemplate: 't3-relay',
    redirectUri: 't3code://app/',
    createdAt: Date.now()
  };
  await s.ssoStore.save(pending);
  const loaded = await s.ssoStore.load();
  assert.equal(loaded.signInId, 'sia_1');
  assert.equal(loaded.clientToken, pending.clientToken);

  await s.ssoStore.save({ ...pending, createdAt: Date.now() - 20 * 60 * 1000 });
  assert.equal(await s.ssoStore.load(), undefined);
});

test('CloudEnvironmentTokenStore persists >1024-byte DPoP environment tokens across Asset chunks and clears cleanly', async () => {
  const s = await setup();
  const token = {
    environmentId: 'c87d033d-3fe9-4b11-85cb-d6e123456789',
    accountId: 'user_31example',
    label: '奋斗的iMac Pro',
    endpoint: {
      httpBaseUrl: 'https://prod-47d891c41242b05d.t3coderelay.com',
      wsBaseUrl: 'wss://prod-47d891c41242b05d.t3coderelay.com/ws',
      providerKind: 'cloudflare_tunnel'
    },
    accessToken: 'eyJ' + 'B'.repeat(1600),
    expiresAt: Date.now() + 300000,
    thumbprint: 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-abcde'
  };
  assert.ok(new TextEncoder().encode(JSON.stringify(token)).length > 1024);
  await s.envStore.save(token);
  const loaded = await s.envStore.load(token.environmentId);
  assert.equal(loaded.accessToken, token.accessToken);
  assert.equal(loaded.endpoint.httpBaseUrl, token.endpoint.httpBaseUrl);

  const rotated = { ...token, accessToken: 'eyJ' + 'C'.repeat(1200) };
  await s.envStore.save(rotated);
  assert.equal((await s.envStore.load(token.environmentId)).accessToken, rotated.accessToken);

  await s.envStore.clear(token.environmentId);
  assert.equal(await s.envStore.load(token.environmentId), undefined);
});

test('RelayTokenStore persists >1024-byte relay DPoP tokens across Asset chunks and clears cleanly', async () => {
  const s = await setup();
  const cache = {
    accountId: 'user_31example',
    clientId: 't3-mobile',
    relayUrl: 'https://relay.t3.codes',
    thumbprint: 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-abcde',
    scopes: [cloud.RELAY_STATUS_SCOPE, cloud.RELAY_CONNECT_SCOPE],
    accessToken: 'eyJ' + 'R'.repeat(1500),
    expiresAtMillis: Date.now() + 600000
  };
  assert.ok(new TextEncoder().encode(JSON.stringify(cache)).length > 1024);
  await s.relayStore.save(cache);
  assert.equal((await s.relayStore.load()).accessToken, cache.accessToken);
  await s.relayStore.clear();
  assert.equal(await s.relayStore.load(), undefined);
});
