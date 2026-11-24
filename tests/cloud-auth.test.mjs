import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { cloudUrl } from './load-cloud.mjs';
import { compile, data } from './load-core.mjs';
const cloud = await import(cloudUrl);

const key = 'pk_test_' + Buffer.from('clerk.example.test$').toString('base64');
const config = {
  clerk: {
    publishableKey: key,
    jwtTemplate: 't3-relay',
    oauthClientId: '',
    redirectUri: 't3code://app/'
  },
  relay: { url: 'https://relay.example.test' }
};

function makeJwt(payload) {
  const seg = Buffer.from(JSON.stringify(payload)).toString('base64url');
  return 'eyJhbGciOiJSUzI1NiJ9.' + seg + '.sig';
}

function activeClientEnvelope(sessionId, userId, email, extra = {}) {
  return {
    response: extra.response ?? {
      object: 'client',
      id: 'client_1',
      last_active_session_id: sessionId,
      sessions: [{
        id: sessionId,
        status: 'active',
        user: {
          id: userId,
          primary_email_address_id: 'em_1',
          email_addresses: [{ id: 'em_1', email_address: email }],
          first_name: 'Alice',
          last_name: 'Dev'
        }
      }]
    },
    client: extra.client ?? {
      object: 'client',
      id: 'client_1',
      last_active_session_id: sessionId,
      sessions: [{
        id: sessionId,
        status: 'active',
        user: {
          id: userId,
          primary_email_address_id: 'em_1',
          email_addresses: [{ id: 'em_1', email_address: email }],
          first_name: 'Alice',
          last_name: 'Dev'
        }
      }]
    }
  };
}

async function load(handler, overrides = {}) {
  const store = {
    value: overrides.stored,
    async load() { return this.value; },
    async save(value) { this.value = structuredClone(value); },
    async clear() { this.value = undefined; }
  };
  const ssoStore = {
    value: overrides.pendingSso,
    async load() { return this.value; },
    async save(value) { this.value = structuredClone(value); },
    async clear() { this.value = undefined; }
  };
  const opened = [];
  const calls = [];
  class Failure extends Error {
    constructor(status, value = {}, headers = {}) {
      super('http ' + status);
      this.status = status;
      this.value = value;
      this.headers = headers;
    }
  }
  globalThis.__cloudAuth = {
    common: {},
    http: { RequestMethod: { GET: 'GET', POST: 'POST', DELETE: 'DELETE' } },
    openLink: async url => opened.push(url),
    failure: Failure,
    cloudHttp: async (url, method, headers, body, contentType) => {
      calls.push({ url, method, headers: { ...headers }, body, contentType });
      const res = await handler(url, method, headers, body, calls);
      if (res.error) throw new Failure(res.error.status, res.error.value || {}, res.error.headers || {});
      return { status: res.status || 200, value: res.value, headers: res.headers || {} };
    }
  };
  const source = (await readFile(new URL('../entry/src/main/ets/services/CloudAuth.ets', import.meta.url), 'utf8'))
    .replace("import { common } from '@kit.AbilityKit';", 'const common = globalThis.__cloudAuth.common;')
    .replace("import { http } from '@kit.NetworkKit';", 'const http = globalThis.__cloudAuth.http;')
    .replace("from '../protocol/Wire';", 'from ' + JSON.stringify(new URL('../entry/src/main/ets/protocol/Wire.ts', import.meta.url).href) + ';')
    .replace("from '../protocol/Cloud';", 'from ' + JSON.stringify(cloudUrl) + ';')
    .replace("import { CloudSessionStore, PendingSsoStore } from '../storage/CloudStores';",
      'const CloudSessionStore = Object; const PendingSsoStore = Object;')
    .replace("import { CloudHttpFailure, CloudHttpResult, cloudHttp } from './CloudHttp';",
      'const { CloudHttpFailure, cloudHttp } = { CloudHttpFailure: globalThis.__cloudAuth.failure, cloudHttp: globalThis.__cloudAuth.cloudHttp };');
  const module = await import(data(compile(source) + '\n//' + Math.random()));
  const auth = new module.CloudAuth(config, store, ssoStore);
  const context = { openLink: globalThis.__cloudAuth.openLink };
  return { auth, store, ssoStore, opened, calls, context };
}

test('Clerk Native FAPI email + OTP + 2FA sign-in completes session and mints short-lived t3-relay JWT', async () => {
  let mintCalls = 0;
  const s = await load(async (url, method, headers, body) => {
    assert.ok(url.includes('_is_native=1'));
    if (url.includes('/v1/client?') && method === 'GET') {
      return { value: { response: { id: 'client_1', sessions: [] }, client: null }, headers: { authorization: 'client_tok_1' } };
    }
    if (url.includes('/v1/client/sign_ins?') && method === 'POST') {
      assert.equal(headers.Authorization, 'client_tok_1');
      assert.match(body, /identifier=alice%40example\.test/);
      return {
        value: {
          response: {
            id: 'sia_1', status: 'needs_first_factor', identifier: 'alice@example.test',
            supported_first_factors: [
              { strategy: 'email_code', email_address_id: 'em_1', safe_identifier: 'alice@example.test' },
              { strategy: 'password' }
            ]
          },
          client: { id: 'client_1', sessions: [] }
        },
        headers: { authorization: 'client_tok_2' }
      };
    }
    if (url.includes('/sia_1/prepare_first_factor')) {
      assert.equal(headers.Authorization, 'client_tok_2');
      assert.match(body, /strategy=email_code/);
      assert.match(body, /email_address_id=em_1/);
      return {
        value: {
          response: {
            id: 'sia_1', status: 'needs_first_factor', identifier: 'alice@example.test',
            supported_first_factors: [{ strategy: 'email_code', email_address_id: 'em_1', safe_identifier: 'alice@example.test' }]
          }
        },
        headers: { authorization: 'client_tok_3' }
      };
    }
    if (url.includes('/sia_1/attempt_first_factor')) {
      assert.equal(headers.Authorization, 'client_tok_3');
      assert.match(body, /code=123456/);
      return {
        value: {
          response: {
            id: 'sia_1', status: 'needs_second_factor', identifier: 'alice@example.test',
            supported_second_factors: [{ strategy: 'totp' }, { strategy: 'backup_code' }]
          }
        },
        headers: { authorization: 'client_tok_4' }
      };
    }
    if (url.includes('/sia_1/attempt_second_factor')) {
      assert.equal(headers.Authorization, 'client_tok_4');
      assert.match(body, /strategy=totp&code=654321/);
      return {
        value: activeClientEnvelope('sess_1', 'user_alice', 'alice@example.test', {
          response: { id: 'sia_1', status: 'complete', created_session_id: 'sess_1' }
        }),
        headers: { authorization: 'client_tok_5' }
      };
    }
    if (url.includes('/v1/client/sessions/sess_1/tokens/t3-relay')) {
      mintCalls++;
      assert.equal(headers.Authorization, mintCalls === 1 ? 'client_tok_5' : 'client_tok_6');
      const exp = Math.floor(Date.now() / 1000) + 60;
      return {
        value: { object: 'token', jwt: makeJwt({ sub: 'user_alice', aud: 't3-code-relay', exp, n: mintCalls }) },
        headers: { authorization: 'client_tok_6' }
      };
    }
    throw new Error('unexpected ' + method + ' ' + url);
  });

  const step1 = await s.auth.startEmailSignIn('alice@example.test');
  assert.equal(step1.kind, 'needs_first_factor');
  await s.auth.sendEmailCode();
  const step2 = await s.auth.verifyEmailCode('123456');
  assert.equal(step2.kind, 'needs_second_factor');
  const step3 = await s.auth.verifySecondFactor('totp', '654321');
  assert.equal(step3.kind, 'complete');
  assert.equal(step3.session.accountId, 'user_alice');
  assert.equal(step3.session.email, 'alice@example.test');
  assert.equal(step3.session.displayName, 'Alice Dev');
  await s.auth.persist(step3.session);

  // Concurrent calls deduplicate and cache within skew; rotating header persists to store.
  const [tokA, tokB] = await Promise.all([s.auth.getRelayToken(), s.auth.getRelayToken()]);
  assert.equal(tokA, tokB);
  assert.equal(mintCalls, 1);
  assert.equal(s.store.value.clientToken, 'client_tok_6');

  // Force refresh mints a fresh template JWT using the rotated client token.
  const tokC = await s.auth.getRelayToken(true);
  assert.notEqual(tokC, tokA);
  assert.equal(mintCalls, 2);
});

test('Clerk Native SSO opens external redirect, consumes callback once with rotating_token_nonce, and handles transferable sign-up', async () => {
  let signUpTransferred = false;
  const s = await load(async (url, method, headers, body) => {
    if (url.includes('/v1/client?') && method === 'GET') {
      return { value: { response: { id: 'client_sso', sessions: [] }, client: null }, headers: { authorization: 'sso_tok_1' } };
    }
    if (url.includes('/v1/client/sign_ins?') && method === 'POST') {
      assert.match(body, /strategy=oauth_github/);
      assert.match(body, /redirect_url=t3code%3A%2F%2Fapp%2F/);
      return {
        value: {
          response: {
            id: 'sia_sso', status: 'needs_identifier',
            first_factor_verification: {
              status: 'unverified', strategy: 'oauth_github',
              external_verification_redirect_url: 'https://github.com/login/oauth/authorize?state=xyz'
            }
          }
        },
        headers: { authorization: 'sso_tok_2' }
      };
    }
    if (url.includes('/v1/client/sign_ins/sia_sso') && method === 'GET') {
      assert.ok(url.includes('rotating_token_nonce=nonce_99'));
      assert.equal(headers.Authorization, 'sso_tok_2');
      return {
        value: {
          response: {
            id: 'sia_sso', status: 'needs_identifier',
            first_factor_verification: { status: 'transferable', strategy: 'oauth_github' }
          },
          client: { id: 'client_sso', sessions: [] }
        },
        headers: { authorization: 'sso_tok_3' }
      };
    }
    if (url.includes('/v1/client/sign_ups') && method === 'POST') {
      signUpTransferred = true;
      assert.equal(headers.Authorization, 'sso_tok_3');
      assert.equal(body, 'transfer=true');
      return {
        value: activeClientEnvelope('sess_gh', 'user_gh', 'gh@example.test', {
          response: { id: 'sua_1', status: 'complete', created_session_id: 'sess_gh' }
        }),
        headers: { authorization: 'sso_tok_4' }
      };
    }
    throw new Error('unexpected ' + method + ' ' + url);
  });

  await s.auth.beginSso('oauth_github', s.context);
  assert.equal(s.opened.length, 1);
  assert.equal(s.opened[0], 'https://github.com/login/oauth/authorize?state=xyz');
  assert.equal(s.ssoStore.value.signInId, 'sia_sso');

  const completed = await s.auth.completeSsoCallback('t3code://app/?rotating_token_nonce=nonce_99');
  assert.equal(signUpTransferred, true);
  assert.equal(completed.kind, 'complete');
  assert.equal(completed.session.accountId, 'user_gh');
  assert.equal(s.ssoStore.value, undefined);

  // Replaying the exact same deep link fails closed.
  await assert.rejects(s.auth.completeSsoCallback('t3code://app/?rotating_token_nonce=nonce_99'), /没有等待中/);
});

test('restore validates active Clerk session, tolerates offline start, and rejects config changes or revoked sessions', async () => {
  const stored = {
    version: 2, accountId: 'user_a', sessionId: 'sess_a', clientToken: 'tok_a',
    email: 'a@example.test', displayName: 'User A', publishableKey: key,
    relayUrl: 'https://relay.example.test', jwtTemplate: 't3-relay', redirectUri: 't3code://app/'
  };

  // Online restore refreshes rotated client token
  const online = await load(async () => ({
    value: activeClientEnvelope('sess_a', 'user_a', 'a@example.test'),
    headers: { authorization: 'tok_a_rotated' }
  }), { stored });
  const restored = await online.auth.restore();
  assert.equal(restored.accountId, 'user_a');
  assert.equal(online.store.value.clientToken, 'tok_a_rotated');

  // Offline restore keeps cached session without clearing it
  const offline = await load(async () => { throw new Error('network down'); }, { stored });
  assert.equal((await offline.auth.restore()).accountId, 'user_a');

  // Clerk 401 session revoked clears local session cleanly
  const expired = await load(async () => ({
    error: { status: 401, value: { errors: [{ code: 'session_not_found' }] } }
  }), { stored });
  assert.equal(await expired.auth.restore(), undefined);
  assert.equal(expired.store.value, undefined);

  // Config mismatch fails closed and clears stored session
  const changed = await load(async () => ({ value: {} }), {
    stored: { ...stored, relayUrl: 'https://other.example.test' }
  });
  await assert.rejects(changed.auth.restore(), /配置已变化/);
  assert.equal(changed.store.value, undefined);
});

test('getRelayToken throws CloudSessionExpiredError on Clerk 401 and clear revokes remote session best-effort', async () => {
  const stored = {
    version: 2, accountId: 'user_a', sessionId: 'sess_a', clientToken: 'tok_a',
    email: 'a@example.test', displayName: 'User A', publishableKey: key,
    relayUrl: 'https://relay.example.test', jwtTemplate: 't3-relay', redirectUri: 't3code://app/'
  };
  let removed = false;
  const s = await load(async (url) => {
    if (url.includes('/tokens/t3-relay')) {
      return { error: { status: 401, value: { errors: [{ code: 'session_not_found' }] } } };
    }
    if (url.includes('/sessions/sess_a/remove')) {
      removed = true;
      return { value: { response: { status: 'removed' } } };
    }
    throw new Error('unexpected ' + url);
  }, { stored });
  s.auth.session = stored;
  await assert.rejects(s.auth.getRelayToken(), err => err instanceof cloud.CloudSessionExpiredError);
  await s.auth.clear(true);
  assert.equal(removed, true);
  assert.equal(s.store.value, undefined);
});
