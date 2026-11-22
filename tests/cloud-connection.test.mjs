import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { cloudUrl } from './load-cloud.mjs';
import { compile, data } from './load-core.mjs';

const endpoint = { httpBaseUrl: 'https://env.example.test', wsBaseUrl: 'wss://env.example.test/',
  providerKind: 'cloudflare_tunnel' };

async function load(handler) {
  const calls = [];
  class Failure extends Error {
    constructor(status, value) { super('http ' + status); this.status = status; this.value = value; }
  }
  globalThis.__cloudConnection = {
    http: { RequestMethod: { GET: 'GET', POST: 'POST' } },
    url: { URL },
    cloudHttpFailure: Failure,
    cloudHttp: async (url, method, headers, body, contentType) => {
      calls.push({ url, method, headers: { ...headers }, body, contentType });
      const response = await handler(url, method, headers, body, calls);
      if (response.error) throw new Failure(response.error.status, response.error.value);
      return { status: response.status || 200, value: response.value };
    }
  };
  const source = (await readFile(new URL('../entry/src/main/ets/services/CloudConnection.ets', import.meta.url), 'utf8'))
    .replace("import { http } from '@kit.NetworkKit';", 'const { http } = globalThis.__cloudConnection;')
    .replace("import { url } from '@kit.ArkTS';", 'const { url } = globalThis.__cloudConnection;')
    .replace("from '../protocol/Wire';", 'from ' + JSON.stringify(new URL('../entry/src/main/ets/protocol/Wire.ts', import.meta.url).href) + ';')
    .replace("from '../protocol/Cloud';", 'from ' + JSON.stringify(cloudUrl) + ';')
    .replace("import { CloudHttpFailure, CloudHttpResult, cloudHttp } from './CloudHttp';",
      'const { CloudHttpFailure, cloudHttp } = { CloudHttpFailure: globalThis.__cloudConnection.cloudHttpFailure, cloudHttp: globalThis.__cloudConnection.cloudHttp };')
    .replace("import { CloudRelay } from './CloudRelay';", 'const CloudRelay = Object;')
    .replace("import { CloudEnvironmentTokenStore } from '../storage/CloudStores';", 'const CloudEnvironmentTokenStore = Object;')
    .replace("import { DpopSigner } from './Dpop';", 'const DpopSigner = Object;');
  const module = await import(data(compile(source) + '\n//' + Math.random()));
  const proofs = [];
  const signer = { thumbprint: async () => 'thumb-a', prove: async (method, url, token) => {
    proofs.push({ method, url, token: token || '' });
    return `proof:${method}:${url}:${token || ''}`;
  } };
  let bootstrapCount = 0;
  const relay = { connect: async () => {
    bootstrapCount++;
    return { environmentId: 'env-1', endpoint, credential: 'BOOTSTRAP_' + bootstrapCount,
      expiresAt: Date.now() + 600000 };
  } };
  let stored;
  const store = { async load() { return stored; }, async save(value) { stored = structuredClone(value); },
    async clear() { stored = undefined; } };
  const transport = new module.CloudEnvironmentTransport('env-1', 'Studio', 'user-a', 'device-1',
    relay, signer, store, () => true);
  return { transport, calls, proofs, store: () => stored, bootstrap: () => bootstrapCount };
}

test('cloud transport exchanges the relay credential, caches the environment DPoP token and reuses it', async () => {
  let exchanges = 0;
  const ctx = await load(async (url, method, headers) => {
    if (url.endsWith('/oauth/token')) {
      exchanges++;
      assert.match(headers.dpop, /^proof:POST:https:\/\/env\.example\.test\/oauth\/token:/);
      return { value: { access_token: 'ENV_DPOP', token_type: 'DPoP', expires_in: 300 } };
    }
    assert.equal(headers.Authorization, 'DPoP ENV_DPOP');
    assert.match(headers.dpop, /:ENV_DPOP$/);
    return { value: { authenticated: true, permissions: ['access:read'] } };
  });
  assert.equal((await ctx.transport.endpoint()).httpBaseUrl, 'https://env.example.test');
  assert.deepEqual(await ctx.transport.requestJson('/api/auth/session', 'GET'), {
    authenticated: true, permissions: ['access:read'] });
  assert.deepEqual(await ctx.transport.requestJson('/api/auth/session', 'GET'), {
    authenticated: true, permissions: ['access:read'] });
  assert.equal(exchanges, 1);
  assert.equal(ctx.store().accessToken, 'ENV_DPOP');
  assert.equal(ctx.store().accountId, 'user-a');
});

test('cloud socket URL uses DPoP RPC ticket, upgrade proof and relay connection method', async () => {
  const ctx = await load(async (url, method, headers) => {
    if (url.endsWith('/oauth/token')) return { value: { access_token: 'ENV_DPOP', token_type: 'DPoP', expires_in: 300 } };
    if (url.endsWith('/api/auth/websocket-ticket/rpc')) {
      assert.equal(headers.Authorization, 'DPoP ENV_DPOP');
      return { value: { ticket: 'WS_TICKET' } };
    }
    throw Error('unexpected ' + url);
  });
  const url = new URL(await ctx.transport.socketUrl());
  assert.equal(url.protocol, 'wss:');
  assert.equal(url.pathname, '/ws');
  assert.equal(url.searchParams.get('wsTicket'), 'WS_TICKET');
  assert.equal(url.searchParams.get('connectionMethod'), 'relay');
  assert.equal(url.searchParams.get('orchestrationProtocol'), '2');
  assert.equal(url.searchParams.get('frameParts'), '1');
  assert.match(url.searchParams.get('dpop'), /^proof:GET:https:\/\/env\.example\.test\/ws:WS_TICKET$/);
  assert.ok(ctx.proofs.some(proof => proof.url.endsWith('/api/auth/websocket-ticket/rpc') &&
    proof.token === 'ENV_DPOP'));
});

test('ticket 404 falls back to the bare endpoint with a fresh proof for that path', async () => {
  const ctx = await load(async (url) => {
    if (url.endsWith('/oauth/token')) return { value: { access_token: 'ENV_DPOP', token_type: 'DPoP', expires_in: 300 } };
    if (url.endsWith('/api/auth/websocket-ticket/rpc')) {
      return { error: { status: 404, value: {} } };
    }
    if (url.endsWith('/api/auth/websocket-ticket')) return { value: { ticket: 'FALLBACK_TICKET' } };
    throw Error('unexpected ' + url);
  });
  const socket = new URL(await ctx.transport.socketUrl());
  assert.equal(socket.searchParams.get('wsTicket'), 'FALLBACK_TICKET');
  assert.ok(ctx.proofs.some(proof => proof.url.endsWith('/api/auth/websocket-ticket') &&
    proof.method === 'POST'));
});

test('environment 401 invalidates the cached token and obtains a new relay bootstrap', async () => {
  let exchanges = 0, attempts = 0, bootstraps = 0;
  const ctx = await load(async (url, method, headers) => {
    if (url.endsWith('/oauth/token')) {
      exchanges++;
      return { value: { access_token: 'ENV_' + exchanges, token_type: 'DPoP', expires_in: 300 } };
    }
    attempts++;
    if (attempts === 1) return { error: { status: 401, value: { code: 'auth_invalid' } } };
    assert.equal(headers.Authorization, 'DPoP ENV_2');
    return { value: { ok: true } };
  });
  // endpoint() uses one bootstrap; the forced refresh must replace it rather than reusing the one-use credential.
  await ctx.transport.endpoint();
  assert.deepEqual(await ctx.transport.requestJson('/api/auth/session', 'GET'), { ok: true });
  assert.equal(exchanges, 2);
  assert.equal(attempts, 2);
  assert.equal(ctx.bootstrap(), 2);
});

test('cachedEndpoint and tokenExpiresAt reuse valid cached token across reconnects and fall back on ticket failure', async () => {
  let ticketCalls = 0;
  const ctx = await load(async (url) => {
    if (url.endsWith('/oauth/token')) return { value: { access_token: 'ENV_CACHED', token_type: 'DPoP', expires_in: 600 } };
    if (url.endsWith('/api/auth/websocket-ticket/rpc')) {
      ticketCalls++;
      if (ticketCalls === 2) return { error: { status: 401, value: {} } };
      return { value: { ticket: 'TICKET_' + ticketCalls } };
    }
    throw Error('unexpected ' + url);
  });
  // First socketUrl performs bootstrap + token exchange
  await ctx.transport.socketUrl();
  assert.equal(ctx.bootstrap(), 1);
  assert.ok(ctx.transport.tokenExpiresAt() > Date.now() + 500000);
  const cachedEp = await ctx.transport.cachedEndpoint();
  assert.equal(cachedEp?.httpBaseUrl, 'https://env.example.test');

  // Clear in-memory bootstrap to simulate reconnect after expiry while DPoP token is still cached;
  // ticket failure (401) transparently falls back to a fresh relay bootstrap + token exchange.
  ctx.transport.bootstrap = undefined;
  const recoveredUrl = new URL(await ctx.transport.socketUrl());
  assert.equal(recoveredUrl.searchParams.get('wsTicket'), 'TICKET_3');
  assert.equal(recoveredUrl.searchParams.get('frameParts'), '1');
  assert.equal(ctx.bootstrap(), 2);
});
