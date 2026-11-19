import test from 'node:test';
import assert from 'node:assert/strict';
import { cloudUrl } from './load-cloud.mjs';
const cloud = await import(cloudUrl);

const endpoint = { httpBaseUrl: 'https://env.example.test', wsBaseUrl: 'wss://env.example.test/',
  providerKind: 'cloudflare_tunnel' };
const record = { environmentId: 'env-1', label: 'Studio Mac', endpoint, linkedAt: '2026-01-01T00:00:00.000Z' };

test('relay environment, status and connect records reject identity or endpoint substitution', () => {
  const [parsed] = cloud.relayEnvironments({ environments: [record] });
  assert.equal(parsed.environmentId, 'env-1');
  assert.equal(parsed.endpoint.httpBaseUrl, 'https://env.example.test');
  assert.deepEqual(cloud.relayEnvironments({ environments: [record] }), [parsed]);
  const status = cloud.relayStatus({
    environmentId: 'env-1', endpoint, status: 'online', checkedAt: '2026-01-01T00:00:01.000Z',
    traceId: 'trace-1', descriptor: { environmentId: 'env-1' }
  }, parsed);
  assert.equal(status.status, 'online');
  assert.equal(cloud.relayConnect({ environmentId: 'env-1', endpoint,
    credential: 'SYNTHETIC_BOOTSTRAP', expiresAt: '2030-01-01T00:00:00.000Z' }, 'env-1').credential,
  'SYNTHETIC_BOOTSTRAP');
  assert.throws(() => cloud.relayStatus({ environmentId: 'other', endpoint, status: 'online',
    checkedAt: '2026-01-01T00:00:01.000Z' }, parsed), /不一致/);
  assert.throws(() => cloud.relayStatus({ environmentId: 'env-1',
    endpoint: { ...endpoint, httpBaseUrl: 'https://evil.example.test' }, status: 'online',
    checkedAt: '2026-01-01T00:00:01.000Z' }, parsed), /不一致/);
  assert.throws(() => cloud.relayConnect({ environmentId: 'other', endpoint,
    credential: 'x', expiresAt: '2030-01-01T00:00:00.000Z' }, 'env-1'), /无效/);
  assert.throws(() => cloud.relayEnvironments({ environments: [record, record] }), /重复/);
  for (const bad of ['http://env.example.test', 'ws://env.example.test']) {
    assert.throws(() => cloud.relayEnvironments({ environments: [{ ...record,
      endpoint: { ...endpoint, httpBaseUrl: bad } }] }));
  }
});

test('DPoP relay token must be DPoP and grant exactly the requested scopes', () => {
  const token = { access_token: 'SYNTHETIC_ACCESS', token_type: 'DPoP',
    issued_token_type: 'urn:ietf:params:oauth:token-type:access_token', expires_in: 300,
    scope: 'environment:status environment:connect' };
  assert.deepEqual(cloud.relayToken(token, ['environment:status', 'environment:connect']).scopes,
    ['environment:status', 'environment:connect']);
  assert.throws(() => cloud.relayToken(token, ['environment:status']), /范围/);
  assert.throws(() => cloud.relayToken({ ...token, scope: 'environment:status environment:connect mobile:registration' },
    ['environment:status', 'environment:connect']), /范围/);
  assert.throws(() => cloud.relayToken({ ...token, token_type: 'Bearer' },
    ['environment:status', 'environment:connect']), /令牌/);
  assert.throws(() => cloud.relayToken({ ...token, expires_in: 0 },
    ['environment:status', 'environment:connect']), /令牌/);
});

test('relay token cache isolates account, client, relay, key, scopes and expiry skew', () => {
  const cached = { accountId: 'user-a', clientId: 't3-mobile', relayUrl: 'https://relay.example.test',
    thumbprint: 'thumb-a', scopes: ['environment:status', 'environment:connect'],
    accessToken: 'SYNTHETIC', expiresAtMillis: 10000 };
  assert.equal(cloud.relayTokenMatches(cached, 'user-a', 't3-mobile', 'https://relay.example.test',
    'thumb-a', ['environment:connect'], 4000), true);
  assert.equal(cloud.relayTokenMatches(cached, 'user-b', 't3-mobile', 'https://relay.example.test',
    'thumb-a', ['environment:connect'], 4000), false);
  assert.equal(cloud.relayTokenMatches(cached, 'user-a', 't3-web', 'https://relay.example.test',
    'thumb-a', ['environment:connect'], 4000), false);
  assert.equal(cloud.relayTokenMatches(cached, 'user-a', 't3-mobile', 'https://other.example.test',
    'thumb-a', ['environment:connect'], 4000), false);
  assert.equal(cloud.relayTokenMatches(cached, 'user-a', 't3-mobile', 'https://relay.example.test',
    'thumb-b', ['environment:connect'], 4000), false);
  assert.equal(cloud.relayTokenMatches(cached, 'user-a', 't3-mobile', 'https://relay.example.test',
    'thumb-a', ['environment:status', 'environment:connect'], 5000), false);
  assert.equal(cloud.relayTokenMatches(cached, 'user-a', 't3-mobile', 'https://relay.example.test',
    'thumb-a', ['environment:connect'], 5000), false);
});

test('device access stream projects pending/trusted devices and prompts only fresh matches', () => {
  const snapshot = cloud.authAccess({ pairingLinks: [{
    id: 'link-1', createdAt: '2026-01-01T00:00:00.000Z', expiresAt: '2026-01-01T00:10:00.000Z',
    connectDeviceRequest: { verificationCode: 'K7QM-2XFD',
      client: { label: 'Pixel', deviceType: 'mobile', os: 'Android' } }
  }], clientSessions: [], connectDevices: [{
    proofKeyThumbprint: 'thumb-a', verificationCode: 'AAAA-AAAA',
    client: { label: 'Laptop', deviceType: 'desktop', os: 'Linux' },
    approvedAt: '2026-01-01T00:00:00.000Z'
  }] });
  assert.equal(snapshot.pairingLinks[0].clientLabel, 'Pixel');
  assert.equal(snapshot.devices[0].label, 'Laptop');
  const newer = cloud.applyAuthAccessEvent(snapshot, { type: 'pairingLinkUpserted', revision: 2,
    payload: { ...snapshot.pairingLinks[0], id: 'link-2', createdAt: '2026-01-01T00:01:00.000Z',
      expiresAt: '2026-01-01T00:10:00.000Z',
      connectDeviceRequest: { verificationCode: 'ZZZZ-ZZZZ', client: { label: 'Phone', deviceType: 'mobile' } } } });
  assert.deepEqual(newer.pairingLinks.map(row => row.id), ['link-2', 'link-1']);
  assert.equal(cloud.applyAuthAccessEvent(newer, { type: 'pairingLinkRemoved', revision: 3,
    payload: { id: 'link-1' } }).pairingLinks.length, 1);
  const prompts = cloud.deviceApprovalPrompts('Mac', snapshot.pairingLinks, [], Date.parse('2026-01-01T00:05:00Z'));
  assert.equal(prompts.length, 1);
  assert.match(prompts[0].message, /K7QM-2XFD/);
  assert.equal(cloud.deviceApprovalPrompts('Mac', snapshot.pairingLinks, [], Date.parse('2026-01-01T00:11:00Z')).length, 0);
  assert.equal(cloud.deviceApprovalPrompts('Mac', snapshot.pairingLinks, ['link-1'],
    Date.parse('2026-01-01T00:05:00Z')).length, 0);
});

test('relay errors and account transitions do not leak credentials', () => {
  const token = 'SYNTHETIC_ACCESS_TOKEN';
  const message = cloud.relayErrorMessage(401, { code: 'auth_invalid', reason: 'invalid_bearer',
    traceId: 'trace-1', access_token: token });
  assert.match(message, /登录已过期/);
  assert.match(message, /trace-1/);
  assert.ok(!message.includes(token));
  assert.match(cloud.relayErrorMessage(403, { code: 'environment_connect_not_authorized',
    reason: 'environment_link_not_found', traceId: 't' }), /未链接/);
  assert.equal(cloud.planCloudAccountStep(undefined, 'user-a').kind, 'signin');
  assert.equal(cloud.planCloudAccountStep(undefined, 'user-a').transition, false);
  const switchStep = cloud.planCloudAccountStep('user-a', 'user-b');
  assert.equal(switchStep.kind, 'signin');
  assert.equal(switchStep.previousAccountId, 'user-a');
  assert.equal(cloud.planCloudAccountStep('user-a', '').kind, 'signout');
  assert.equal(cloud.planCloudAccountStep('user-a', 'user-a').kind, 'none');
});
