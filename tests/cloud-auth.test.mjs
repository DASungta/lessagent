import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { cloudUrl } from './load-cloud.mjs';
import { compile, data } from './load-core.mjs';
const cloud = await import(cloudUrl);

const config = { clerk: { publishableKey: 'pk_test_' + Buffer.from('clerk.example.test').toString('base64'),
  jwtTemplate: 't3-mobile', oauthClientId: 't3-harmony', redirectUri: 't3code://auth/callback' },
  relay: { url: 'https://relay.example.test' } };

async function load(overrides = {}) {
  let random = 0;
  const store = { value: overrides.stored, async load() { return this.value; },
    async save(value) { this.value = structuredClone(value); }, async clear() { this.value = undefined; } };
  const opened = [];
  const calls = [];
  class Failure extends Error { constructor(status) { super('http ' + status); this.status = status; } }
  globalThis.__cloudAuth = {
    common: {}, util: { TextDecoder, TextEncoder },
    crypto: { createRandom: () => ({ generateRandomSync: length => ({
      data: Uint8Array.from(Array.from({ length }, (_, index) => (random + index + 1) % 251)) }) }) },
    openLink: async url => opened.push(url),
    failure: Failure,
    cloudHttp: async (url, method, headers, body) => {
      calls.push({ url, method, headers, body });
      if (overrides.tokenError) throw new Failure(401);
      const sub = Buffer.from(JSON.stringify({ sub: 'user-a' })).toString('base64url');
      return { status: 200, value: { access_token: 'header.' + sub + '.signature',
        token_type: 'Bearer', expires_in: overrides.expiresIn || 3600 } };
    }
  };
  const source = (await readFile(new URL('../entry/src/main/ets/services/CloudAuth.ets', import.meta.url), 'utf8'))
    .replace("import { common } from '@kit.AbilityKit';", 'const common = globalThis.__cloudAuth.common;')
    .replace("import { cryptoFramework } from '@kit.CryptoArchitectureKit';", 'const cryptoFramework = globalThis.__cloudAuth.crypto;')
    .replace("import { util } from '@kit.ArkTS';", 'const { util } = globalThis.__cloudAuth;')
    .replace("import { http } from '@kit.NetworkKit';", 'const http = { RequestMethod: { POST: "POST" } };')
    .replace("from '../protocol/Wire';", 'from ' + JSON.stringify(new URL('../entry/src/main/ets/protocol/Wire.ts', import.meta.url).href) + ';')
    .replace("from '../protocol/Cloud';", 'from ' + JSON.stringify(cloudUrl) + ';')
    .replace("import { CloudSessionStore } from '../storage/CloudStores';", 'const CloudSessionStore = Object;')
    .replace("import { CloudHttpFailure, CloudHttpResult, cloudHttp } from './CloudHttp';",
      'const { CloudHttpFailure, cloudHttp } = { CloudHttpFailure: globalThis.__cloudAuth.failure, cloudHttp: globalThis.__cloudAuth.cloudHttp };')
    .replace("import { DpopSigner } from './Dpop';", 'const DpopSigner = Object;');
  const module = await import(data(compile(source) + '\n//' + Math.random()));
  const signer = { async sha256Base64Url() { return 'C'.repeat(43); } };
  const auth = new module.CloudAuth(config, signer, store);
  const context = { openLink: globalThis.__cloudAuth.openLink };
  return { auth, store, opened, calls, context };
}

test('Clerk login uses system browser, state+PKCE and one-shot callback consumption', async () => {
  const s = await load();
  await s.auth.begin(s.context);
  assert.equal(s.opened.length, 1);
  const authorize = new URL(s.opened[0]);
  assert.equal(authorize.origin, 'https://clerk.example.test');
  assert.equal(authorize.searchParams.get('client_id'), 't3-harmony');
  assert.equal(authorize.searchParams.get('code_challenge'), 'C'.repeat(43));
  const state = authorize.searchParams.get('state');
  const callback = 't3code://auth/callback?code=code-1&state=' + encodeURIComponent(state);
  const session = await s.auth.complete(callback);
  assert.equal(session.accountId, 'user-a');
  assert.equal(session.relayUrl, 'https://relay.example.test');
  assert.equal(s.calls.length, 1);
  assert.match(s.calls[0].body, /code=code-1/);
  await assert.rejects(s.auth.complete(callback), /没有等待中/);
  await s.auth.persist(session);
  assert.equal(s.store.value.accountId, 'user-a');
});

test('restore is account-scoped, expires closed, and config changes require re-login', async () => {
  const stored = { accountId: 'user-a', accessToken: 'header.eyJzdWIiOiJ1c2VyLWEifQ.signature',
    expiresAt: Date.now() + 60000, relayUrl: 'https://relay.example.test',
    clientId: 't3-harmony', redirectUri: 't3code://auth/callback', jwtTemplate: 't3-mobile' };
  const a = await load({ stored });
  assert.equal((await a.auth.restore()).accountId, 'user-a');
  const expired = await load({ stored: { ...stored, expiresAt: 1 } });
  assert.equal(await expired.auth.restore(), undefined);
  assert.equal(expired.store.value, undefined);
  const changed = await load({ stored: { ...stored, relayUrl: 'https://other.example.test' } });
  await assert.rejects(changed.auth.restore(), /配置已变化/);
  assert.equal(changed.store.value, undefined);
});

test('failed token exchange leaves no session and does not expose the authorization code', async () => {
  const s = await load({ tokenError: true });
  await s.auth.begin(s.context);
  const state = new URL(s.opened[0]).searchParams.get('state');
  await assert.rejects(s.auth.complete('t3code://auth/callback?code=secret-code&state=' +
    encodeURIComponent(state)), /Clerk 登录失败/);
  try { await s.auth.complete('t3code://auth/callback?code=secret-code&state=' +
    encodeURIComponent(state)); } catch (error) {
    assert.ok(!error.message.includes('secret-code'));
  }
});
