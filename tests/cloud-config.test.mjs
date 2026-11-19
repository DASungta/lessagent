import test from 'node:test';
import assert from 'node:assert/strict';
import { cloudUrl } from './load-cloud.mjs';
const cloud = await import(cloudUrl);

const key = 'pk_test_' + Buffer.from('clerk.example.test$').toString('base64');
const config = (overrides = {}) => ({
  clerk: {
    publishableKey: key,
    jwtTemplate: 't3-mobile',
    oauthClientId: 't3-harmony',
    redirectUri: 't3code://auth/callback',
    ...(overrides.clerk || {})
  },
  relay: { url: overrides.relayUrl ?? 'https://relay.example.test' }
});

test('public config stays hidden until all three upstream fields exist and relay is a secure origin', () => {
  const empty = cloud.cloudConfig({ clerk: {}, relay: {} });
  assert.equal(cloud.cloudConfigured(empty), false);
  assert.equal(cloud.cloudSignInReady(empty), false);
  const checked = cloud.cloudConfig(config());
  assert.equal(cloud.cloudConfigured(checked), true);
  assert.equal(cloud.cloudSignInReady(checked), true);
  assert.equal(cloud.cloudSignInReady(cloud.cloudConfig(config({ clerk: { oauthClientId: '' } }))), false);
  for (const relayUrl of ['http://relay.example.test', 'https://user:secret@relay.example.test',
    'https://relay.example.test/path', 'https://relay.example.test?token=secret',
    'https://relay.example.test/#secret']) {
    assert.throws(() => cloud.cloudConfig(config({ relayUrl })), /HTTPS|中继/);
  }
  assert.equal(cloud.cloudConfig(config({ relayUrl: 'https://relay.example.test/' })).relay.url,
    'https://relay.example.test');
  assert.equal(cloud.cloudConfig(config({ relayUrl: 'https://relay.example.test:443' })).relay.url,
    'https://relay.example.test');
});

test('Clerk publishable key decodes only to an HTTPS frontend API host', () => {
  assert.equal(cloud.clerkFrontendApi(key), 'https://clerk.example.test');
  assert.throws(() => cloud.clerkFrontendApi('pk_test_not-base64!'), /Clerk/);
  assert.throws(() => cloud.clerkFrontendApi('pk_test_' + Buffer.from('clerk.test/path').toString('base64')), /Clerk/);
  assert.throws(() => cloud.clerkFrontendApi('sk_test_' + Buffer.from('clerk.test').toString('base64')), /Clerk/);
});

test('OAuth URL and callback bind exact redirect, state and PKCE without exposing the verifier', () => {
  const checked = cloud.cloudConfig(config());
  const verifier = 'A'.repeat(64);
  const challenge = 'B'.repeat(43);
  const url = new URL(cloud.oauthAuthorizeUrl(checked, 'state-1234567890', challenge));
  assert.equal(url.origin, 'https://clerk.example.test');
  assert.equal(url.pathname, '/oauth/authorize');
  assert.equal(url.searchParams.get('client_id'), 't3-harmony');
  assert.equal(url.searchParams.get('redirect_uri'), 't3code://auth/callback');
  assert.equal(url.searchParams.get('code_challenge_method'), 'S256');
  assert.equal(url.searchParams.get('code_challenge'), challenge);
  assert.ok(!url.toString().includes(verifier));
  assert.equal(cloud.oauthCallback('t3code://auth/callback?code=one&state=state-1234567890',
    'state-1234567890', 't3code://auth/callback').code, 'one');
  assert.throws(() => cloud.oauthCallback('t3code://auth/callback?code=one&state=wrong',
    'state-1234567890', 't3code://auth/callback'), /状态/);
  assert.throws(() => cloud.oauthCallback('t3code://other/callback?code=one&state=state-1234567890',
    'state-1234567890', 't3code://auth/callback'), /回调/);
  assert.throws(() => cloud.oauthCallback('t3code://auth/callback?error=denied&state=state-1234567890',
    'state-1234567890', 't3code://auth/callback'), /回调/);
  assert.throws(() => cloud.oauthTokenForm('code', 'short', checked), /PKCE/);
});

test('base64url is canonical and JWT subject is used only for local account isolation', () => {
  const bytes = Uint8Array.from([0, 1, 2, 250, 251, 252, 253, 254, 255]);
  assert.deepEqual([...cloud.base64UrlDecode(cloud.base64UrlEncode(bytes))], [...bytes]);
  assert.throws(() => cloud.base64UrlDecode('A'), /base64url/);
  const token = (payload) => 'x.' + cloud.base64UrlEncode(new TextEncoder().encode(JSON.stringify(payload))) + '.y';
  assert.equal(cloud.clerkTokenSubject(token({ sub: 'user_123' })), 'user_123');
  assert.throws(() => cloud.clerkTokenSubject(token({ sub: '' })), /身份/);
  assert.throws(() => cloud.clerkTokenSubject('not-a-jwt'), /格式/);
});

test('account session rejects cross-relay/config records and unsafe callbacks', () => {
  const value = { accountId: 'user_123', accessToken: 'SYNTHETIC', expiresAt: Date.now() + 60000,
    relayUrl: 'https://relay.example.test', clientId: 't3-harmony',
    redirectUri: 't3code://auth/callback', jwtTemplate: 't3-mobile' };
  assert.equal(cloud.cloudAccountSession(value).accountId, 'user_123');
  for (const bad of [{ ...value, relayUrl: 'http://relay.example.test' },
    { ...value, redirectUri: 't3code://evil/callback' }, { ...value, accessToken: '' },
    { ...value, expiresAt: 0 }]) assert.throws(() => cloud.cloudAccountSession(bad));
});
