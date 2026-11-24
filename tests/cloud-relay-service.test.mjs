import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { cloudUrl } from './load-cloud.mjs';
import { compile, data } from './load-core.mjs';

const endpoint = { httpBaseUrl: 'https://env.example.test', wsBaseUrl: 'wss://env.example.test/',
  providerKind: 'cloudflare_tunnel' };
const environment = { environmentId: 'env-1', label: 'Studio', endpoint,
  linkedAt: '2026-01-01T00:00:00.000Z' };
const config = { clerk: { publishableKey: '', jwtTemplate: 't3-relay', oauthClientId: '', redirectUri: 't3code://app/' },
  relay: { url: 'https://relay.example.test' } };

async function load(handler, tokenReader) {
  const calls = [];
  const tokenCalls = [];
  class Failure extends Error {
    constructor(status, value) { super('http ' + status); this.status = status; this.value = value; }
  }
  globalThis.__relayService = {
    http: { RequestMethod: { GET: 'GET', POST: 'POST', DELETE: 'DELETE' } },
    cloudHttpFailure: Failure,
    cloudHttp: async (url, method, headers, body, contentType) => {
      calls.push({ url, method, headers: { ...headers }, body, contentType });
      const response = await handler(url, method, headers, body, calls);
      if (response.error) throw new Failure(response.error.status, response.error.value);
      return { status: 200, value: response.value, headers: {} };
    }
  };
  const source = (await readFile(new URL('../entry/src/main/ets/services/CloudRelay.ets', import.meta.url), 'utf8'))
    .replace("import { http } from '@kit.NetworkKit';", 'const { http } = globalThis.__relayService;')
    .replace("from '../protocol/Wire';", 'from ' + JSON.stringify(new URL('../entry/src/main/ets/protocol/Wire.ts', import.meta.url).href) + ';')
    .replace("from '../protocol/Cloud';", 'from ' + JSON.stringify(cloudUrl) + ';')
    .replace("import { CloudHttpFailure, CloudHttpResult, cloudHttp } from './CloudHttp';",
      'const { CloudHttpFailure, cloudHttp } = { CloudHttpFailure: globalThis.__relayService.cloudHttpFailure, cloudHttp: globalThis.__relayService.cloudHttp };')
    .replace("import { DpopSigner } from './Dpop';", 'const DpopSigner = Object;')
    .replace("import { RelayTokenStore } from '../storage/CloudStores';", 'const RelayTokenStore = Object;');
  const module = await import(data(compile(source) + '\n//' + Math.random()));
  const signer = { thumbprint: async () => 'thumb-a',
    prove: async (method, url, token) => `proof:${method}:${url}:${token || ''}` };
  const store = { value: undefined, async load() { return this.value; },
    async save(value) { this.value = structuredClone(value); }, async clear() { this.value = undefined; } };
  const readClerkToken = async (force) => {
    tokenCalls.push(Boolean(force));
    return tokenReader ? tokenReader(Boolean(force)) : 'SYNTHETIC_CLERK';
  };
  return {
    relay: new module.CloudRelay(config, 'user-a', readClerkToken, () => true, signer, store),
    calls, tokenCalls, store
  };
}

test('relay exchanges a DPoP token using dynamic Clerk JWT, reuses scoped cache, lists, reads status and connects', async () => {
  let exchanges = 0;
  const { relay, store } = await load(async (url, method, headers, body) => {
    if (url.endsWith('/v1/client/dpop-token')) {
      exchanges++;
      assert.equal(headers.dpop, 'proof:POST:https://relay.example.test/v1/client/dpop-token:');
      assert.match(body, /subject_token=SYNTHETIC_CLERK/);
      assert.match(body, /scope=environment%3Astatus%20environment%3Aconnect/);
      return { value: { access_token: 'DPOP_ACCESS', token_type: 'DPoP',
        issued_token_type: 'urn:ietf:params:oauth:token-type:access_token', expires_in: 300,
        scope: 'environment:status environment:connect' } };
    }
    if (url.endsWith('/v1/environments')) {
      assert.equal(headers.Authorization, 'Bearer SYNTHETIC_CLERK');
      return { value: { environments: [environment] } };
    }
    if (url.endsWith('/status')) {
      assert.equal(headers.Authorization, 'DPoP DPOP_ACCESS');
      assert.match(headers.dpop, /:DPOP_ACCESS$/);
      return { value: { ...environment, status: 'online', checkedAt: '2026-01-01T00:00:01.000Z' } };
    }
    if (url.endsWith('/connect')) {
      assert.equal(body, JSON.stringify({ deviceId: 'device-1', clientKeyThumbprint: 'thumb-a' }));
      return { value: { environmentId: 'env-1', endpoint, credential: 'SYNTHETIC_CREDENTIAL',
        expiresAt: '2030-01-01T00:00:00.000Z' } };
    }
    throw Error('unexpected ' + url);
  });
  assert.equal((await relay.listEnvironments())[0].environmentId, 'env-1');
  assert.equal((await relay.status(environment)).status, 'online');
  assert.equal((await relay.status(environment)).status, 'online');
  assert.equal((await relay.connect('env-1', 'device-1')).credential, 'SYNTHETIC_CREDENTIAL');
  assert.equal(exchanges, 1);
  assert.equal(store.value.accountId, 'user-a');
});

test('relay refreshes short-lived Clerk template JWT once on 401 invalid_bearer for bearer and token-exchange calls', async () => {
  let listAttempts = 0;
  let exchangeAttempts = 0;
  const { relay, tokenCalls } = await load(async (url, method, headers, body) => {
    if (url.endsWith('/v1/environments')) {
      listAttempts++;
      if (listAttempts === 1) {
        assert.equal(headers.Authorization, 'Bearer STALE_JWT');
        return { error: { status: 401, value: { code: 'auth_invalid', reason: 'invalid_bearer' } } };
      }
      assert.equal(headers.Authorization, 'Bearer FRESH_JWT');
      return { value: { environments: [environment] } };
    }
    if (url.endsWith('/v1/client/dpop-token')) {
      exchangeAttempts++;
      if (exchangeAttempts === 1) {
        assert.match(body, /subject_token=STALE_JWT/);
        return { error: { status: 401, value: { code: 'auth_invalid', reason: 'invalid_bearer' } } };
      }
      assert.match(body, /subject_token=FRESH_JWT/);
      return { value: { access_token: 'DPOP_FRESH', token_type: 'DPoP',
        issued_token_type: 'urn:ietf:params:oauth:token-type:access_token', expires_in: 300,
        scope: 'environment:status environment:connect' } };
    }
    if (url.endsWith('/status')) {
      return { value: { ...environment, status: 'online', checkedAt: '2026-01-01T00:00:01.000Z' } };
    }
    throw Error('unexpected ' + url);
  }, (force) => force ? 'FRESH_JWT' : 'STALE_JWT');

  assert.equal((await relay.listEnvironments()).length, 1);
  assert.equal((await relay.status(environment)).status, 'online');
  assert.equal(listAttempts, 2);
  assert.equal(exchangeAttempts, 2);
  assert.deepEqual(tokenCalls, [false, true, false, true]);
});

test('relay link challenge/link/unlink use bearer endpoints and preserve the exact proof', async () => {
  const { relay, calls } = await load(async (url, method, headers, body) => {
    assert.equal(headers.Authorization, 'Bearer SYNTHETIC_CLERK');
    if (url.endsWith('/environment-link-challenges')) {
      return { value: { challenge: 'CHALLENGE', expiresAt: '2030-01-01T00:00:00.000Z' } };
    }
    if (url.endsWith('/environment-links') && method === 'POST') {
      assert.match(body, /"proof":"SIGNED_PROOF"/);
      return { value: { ok: true, cloudUserId: 'user-a', environmentId: 'env-1', endpoint,
        endpointRuntime: null, relayIssuer: 'https://relay.example.test',
        environmentCredential: 'ENV_CREDENTIAL', cloudMintPublicKey: 'MINT_KEY' } };
    }
    if (url.endsWith('/environment-links/env-1') && method === 'DELETE') return { value: { ok: true } };
    throw Error('unexpected ' + url);
  });
  assert.equal((await relay.createLinkChallenge()).challenge, 'CHALLENGE');
  assert.equal((await relay.linkEnvironment('env-1', 'SIGNED_PROOF', 'device-1')).environmentCredential,
    'ENV_CREDENTIAL');
  await relay.unlinkEnvironment('env-1');
  assert.equal(calls.length, 3);
});

test('relay invalid_bearer on DPoP request invalidates old token and retries once without a second loop', async () => {
  let exchanges = 0, statusCalls = 0;
  const { relay } = await load(async (url, method, headers) => {
    if (url.endsWith('/v1/client/dpop-token')) {
      exchanges++;
      return { value: { access_token: 'TOKEN_' + exchanges, token_type: 'DPoP',
        issued_token_type: 'urn:ietf:params:oauth:token-type:access_token', expires_in: 300,
        scope: 'environment:status environment:connect' } };
    }
    statusCalls++;
    if (statusCalls === 1) return { error: { status: 401, value: { code: 'auth_invalid',
      reason: 'invalid_bearer', traceId: 'trace-1' } } };
    assert.equal(headers.Authorization, 'DPoP TOKEN_2');
    return { value: { ...environment, status: 'online', checkedAt: '2026-01-01T00:00:01.000Z' } };
  });
  assert.equal((await relay.status(environment)).status, 'online');
  assert.equal(exchanges, 2);
  assert.equal(statusCalls, 2);
});
