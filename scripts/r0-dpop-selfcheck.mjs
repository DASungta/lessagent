// R0 host-only representation check; this does not validate HarmonyOS crypto or relay login.
import assert from 'node:assert/strict';
import { createHash, generateKeyPairSync, sign, verify } from 'node:crypto';
const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const { kty, crv, x, y } = publicKey.export({ format: 'jwk' });
const jwk = { kty, crv, x, y };
const digest = value => createHash('sha256').update(value).digest('base64url');
const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
// Same inputs and timestamp as upstream dpopProof.test.ts, using host crypto instead of Effect.
const url = new URL('https://relay.example.test/v1/environments/env-1/connect?debug=1#ignored');
url.search = ''; url.hash = '';
const payload = { htm: 'POST', htu: url.toString(), jti: '00000000-0000-4000-8000-000000000001', iat: 1700000000, ath: digest('relay-access-token') };
assert.equal(payload.htu, 'https://relay.example.test/v1/environments/env-1/connect');
assert.equal(Buffer.from(x, 'base64url').length, 32);
assert.equal(Buffer.from(y, 'base64url').length, 32);
const input = Buffer.from(`${encode({ typ: 'dpop+jwt', alg: 'ES256', jwk })}.${encode(payload)}`);
const signature = sign('sha256', input, { key: privateKey, dsaEncoding: 'ieee-p1363' });
assert.equal(signature.length, 64);
assert(verify('sha256', input, { key: publicKey, dsaEncoding: 'ieee-p1363' }, signature));
assert(!verify('sha256', Buffer.concat([input, Buffer.from('tampered')]), { key: publicKey, dsaEncoding: 'ieee-p1363' }, signature));
assert.notEqual(payload.ath, digest('other-token'));
const thumbprint = digest(JSON.stringify({ crv, kty, x, y }));
assert.equal(Buffer.from(thumbprint, 'base64url').length, 32);
// DER is not a JWS signature: platform bridge must explicitly return r||s.
const der = sign('sha256', input, privateKey);
assert(verify('sha256', input, publicKey, der));
assert(!verify('sha256', input, { key: publicKey, dsaEncoding: 'ieee-p1363' }, der));
console.log(JSON.stringify({ kind: 'O-host-only', checks: ['P-256 coordinates', 'htu removes query/hash', 'ath binds token', 'thumbprint member order', 'ES256 raw signature length', 'valid signature', 'tamper rejection', 'DER is not raw'], passed: true, harmonyDeviceCryptoValidated: false, upstreamEffectTestsExecuted: false, relayValidated: false }, null, 2));
