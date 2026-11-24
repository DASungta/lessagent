import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { cloudUrl } from './load-cloud.mjs';
const cloud = await import(cloudUrl);

const key = 'pk_test_' + Buffer.from('clerk.example.test$').toString('base64');
const config = (overrides = {}) => ({
  clerk: {
    publishableKey: key,
    jwtTemplate: 't3-relay',
    oauthClientId: '',
    redirectUri: 't3code://app/',
    ...(overrides.clerk || {})
  },
  relay: { url: overrides.relayUrl ?? 'https://relay.example.test' }
});

test('bundled rawfile t3-connect.json ships valid official T3 Connect public defaults', async () => {
  const raw = JSON.parse(await readFile(new URL('../entry/src/main/resources/rawfile/t3-connect.json', import.meta.url), 'utf8'));
  const parsed = cloud.cloudConfig(raw);
  assert.equal(cloud.cloudConfigured(parsed), true);
  assert.equal(cloud.cloudSignInReady(parsed), true);
  assert.equal(parsed.relay.url, 'https://relay.t3.codes');
  assert.equal(parsed.clerk.jwtTemplate, 't3-relay');
  assert.equal(parsed.clerk.redirectUri, 't3code://app/');
  assert.equal(cloud.clerkFrontendApi(parsed.clerk.publishableKey), 'https://clerk.t3.codes');
});

test('public config stays hidden until all three upstream fields exist and relay is a secure origin', () => {
  const empty = cloud.cloudConfig({ clerk: {}, relay: {} });
  assert.equal(cloud.cloudConfigured(empty), false);
  assert.equal(cloud.cloudSignInReady(empty), false);
  const checked = cloud.cloudConfig(config());
  assert.equal(cloud.cloudConfigured(checked), true);
  assert.equal(cloud.cloudSignInReady(checked), true);
  // Redirect defaults to t3code://app/ when omitted, and normalizes t3code://app -> t3code://app/
  assert.equal(cloud.cloudConfig(config({ clerk: { redirectUri: '' } })).clerk.redirectUri, 't3code://app/');
  assert.equal(cloud.cloudConfig(config({ clerk: { redirectUri: 't3code://app' } })).clerk.redirectUri, 't3code://app/');
  assert.equal(cloud.cloudConfig(config({ clerk: { redirectUri: 't3code://auth/callback' } })).clerk.redirectUri, 't3code://auth/callback');
  assert.equal(cloud.cloudConfig(config({ clerk: { redirectUri: 'lessagent://app' } })).clerk.redirectUri, 'lessagent://app/');
  assert.equal(cloud.cloudConfig(config({ clerk: { redirectUri: 'lessagent://auth/callback' } })).clerk.redirectUri, 'lessagent://auth/callback');
  assert.throws(() => cloud.cloudConfig(config({ clerk: { redirectUri: 'https://evil.test/cb' } })), /回调/);
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

test('custom deployment override validates strictly and toggles against official defaults', () => {
  const base = cloud.cloudConfig(cloud.OFFICIAL_CLOUD_CONFIG);
  assert.equal(cloud.isCustomCloudConfig(base, cloud.resolveEffectiveCloudConfig(base, undefined)), false);
  const override = cloud.parseCloudConfigOverride({
    enabled: true,
    publishableKey: key,
    jwtTemplate: 'custom-relay',
    relayUrl: 'https://custom-relay.example.test/'
  });
  const effective = cloud.resolveEffectiveCloudConfig(base, override);
  assert.equal(effective.relay.url, 'https://custom-relay.example.test');
  assert.equal(effective.clerk.jwtTemplate, 'custom-relay');
  assert.equal(cloud.isCustomCloudConfig(base, effective), true);
  assert.throws(() => cloud.parseCloudConfigOverride({
    enabled: true, publishableKey: key, jwtTemplate: '', relayUrl: 'https://custom.example.test'
  }), /同时提供/);
  assert.throws(() => cloud.parseCloudConfigOverride({
    enabled: true, publishableKey: key, jwtTemplate: 'tpl', relayUrl: 'http://insecure.test'
  }), /HTTPS/);
});

test('Clerk publishable key decodes only to an HTTPS frontend API host', () => {
  assert.equal(cloud.clerkFrontendApi(key), 'https://clerk.example.test');
  assert.throws(() => cloud.clerkFrontendApi('pk_test_not-base64!'), /Clerk/);
  assert.throws(() => cloud.clerkFrontendApi('pk_test_' + Buffer.from('clerk.test/path').toString('base64')), /Clerk/);
  assert.throws(() => cloud.clerkFrontendApi('sk_test_' + Buffer.from('clerk.test').toString('base64')), /Clerk/);
});

test('SSO callback URI matching and validation reject foreign schemes, hosts, paths, and errors', () => {
  assert.equal(cloud.isCloudCallbackUri('t3code://app/?rotating_token_nonce=abc'), true);
  assert.equal(cloud.isCloudCallbackUri('t3code://app?rotating_token_nonce=abc'), true);
  assert.equal(cloud.isCloudCallbackUri('t3code://auth/callback?code=1'), true);
  assert.equal(cloud.isCloudCallbackUri('lessagent://app/?rotating_token_nonce=abc'), true);
  assert.equal(cloud.isCloudCallbackUri('lessagent://app?rotating_token_nonce=abc'), true);
  assert.equal(cloud.isCloudCallbackUri('lessagent://auth/callback?code=1'), true);
  assert.equal(cloud.isCloudCallbackUri('lessagent://pair?code=1'), false);
  assert.equal(cloud.isCloudCallbackUri('t3code://pair?code=1'), false);
  assert.equal(cloud.isCloudCallbackUri('https://app.t3.codes/'), false);

  const ok = cloud.clerkSsoCallback('t3code://app/?rotating_token_nonce=nonce-123&created_session_id=sess_1', 't3code://app/');
  assert.equal(ok.rotatingTokenNonce, 'nonce-123');
  assert.equal(ok.createdSessionId, 'sess_1');
  assert.throws(() => cloud.clerkSsoCallback('t3code://pair/?rotating_token_nonce=abc', 't3code://app/'), /不匹配/);
  assert.throws(() => cloud.clerkSsoCallback('t3code://app/evil?rotating_token_nonce=abc', 't3code://app/'), /不匹配/);
  assert.throws(() => cloud.clerkSsoCallback('t3code://app/?error=access_denied', 't3code://app/'), /取消|失败/);
});

test('Clerk Native FAPI environment and error parsers stay strict and localized', () => {
  const env = cloud.parseClerkEnvironment({
    auth_config: {
      first_factors: ['email_code', 'password', 'oauth_github'],
      second_factors: ['totp', 'backup_code'],
      native_settings: { api_enabled: true }
    },
    display_config: { application_name: 'T3 Code' },
    user_settings: {
      social: {
        oauth_github: { enabled: true, authenticatable: true, name: 'GitHub' },
        oauth_google: { enabled: true, authenticatable: true, name: 'Google' },
        oauth_apple: { enabled: false, authenticatable: true, name: 'Apple' }
      }
    }
  });
  assert.equal(env.nativeApiEnabled, true);
  assert.equal(env.emailCodeEnabled, true);
  assert.equal(env.passwordEnabled, true);
  assert.deepEqual(env.socialProviders.map(p => p.strategy), ['oauth_github', 'oauth_google']);
  assert.deepEqual(env.secondFactorStrategies, ['totp', 'backup_code']);
  assert.match(cloud.clerkErrorMessage(422, { errors: [{ code: 'form_password_incorrect' }] }), /密码错误/);
  assert.match(cloud.clerkErrorMessage(422, { errors: [{ code: 'form_code_incorrect' }] }), /验证码不正确/);
});

test('base64url is canonical and JWT subject/template validators reject mismatched subjects', () => {
  const bytes = Uint8Array.from([0, 1, 2, 250, 251, 252, 253, 254, 255]);
  assert.deepEqual([...cloud.base64UrlDecode(cloud.base64UrlEncode(bytes))], [...bytes]);
  assert.throws(() => cloud.base64UrlDecode('A'), /base64url/);
  const token = (payload) => 'x.' + cloud.base64UrlEncode(new TextEncoder().encode(JSON.stringify(payload))) + '.y';
  assert.equal(cloud.clerkTokenSubject(token({ sub: 'user_123' })), 'user_123');
  assert.throws(() => cloud.clerkTokenSubject(token({ sub: '' })), /身份/);
  assert.throws(() => cloud.clerkTokenSubject('not-a-jwt'), /格式/);
  const exp = Math.floor(Date.now() / 1000) + 60;
  const minted = cloud.parseClerkTemplateToken({ jwt: token({ sub: 'user_123', aud: 't3-code-relay', exp }) }, 'user_123');
  assert.equal(minted.expiresAtMillis, exp * 1000);
  assert.throws(() => cloud.parseClerkTemplateToken({ jwt: token({ sub: 'user_other', exp }) }, 'user_123'), /不匹配/);
});

test('v2 account session rejects legacy v1, cross-relay/config records and unsafe callbacks', () => {
  const value = {
    version: 2,
    accountId: 'user_123',
    sessionId: 'sess_123',
    clientToken: 'header.payload.sig',
    email: 'dev@example.test',
    displayName: 'Dev User',
    publishableKey: key,
    relayUrl: 'https://relay.example.test',
    jwtTemplate: 't3-relay',
    redirectUri: 't3code://app/'
  };
  assert.equal(cloud.cloudAccountSession(value).accountId, 'user_123');
  for (const bad of [
    { ...value, version: 1 },
    { ...value, relayUrl: 'http://relay.example.test' },
    { ...value, redirectUri: 't3code://evil/callback' },
    { ...value, clientToken: '' },
    { ...value, sessionId: '' },
    { ...value, publishableKey: 'sk_live_bad' }
  ]) assert.throws(() => cloud.cloudAccountSession(bad));
});
