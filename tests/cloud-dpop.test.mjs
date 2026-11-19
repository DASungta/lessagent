import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { cloudUrl } from './load-cloud.mjs';
const cloud = await import(cloudUrl);

const { privateKey, publicKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const jwk = publicKey.export({ format: 'jwk' });

test('DPoP proof is ES256, P-256, uppercase method, query/hash-free htu and optional ath', () => {
  const target = 'https://relay.example.test/v1/client/dpop-token?secret=query#fragment';
  const expectedHtu = 'https://relay.example.test/v1/client/dpop-token';
  const ath = 'A'.repeat(43);
  const header = cloud.dpopHeader(jwk);
  const payload = cloud.dpopPayload('post', target, 'synthetic-jti', 1700000000, ath);
  assert.deepEqual(payload, { htm: 'POST', htu: expectedHtu, jti: 'synthetic-jti', iat: 1700000000, ath });
  const input = cloud.dpopSigningInput(header, payload);
  const der = crypto.sign('sha256', Buffer.from(input), privateKey);
  const raw = cloud.rawEccSignature(new Uint8Array(der));
  assert.equal(raw.length, 64);
  const proof = cloud.dpopProof(input, raw);
  const parts = proof.split('.');
  assert.equal(parts.length, 3);
  assert.deepEqual(JSON.parse(Buffer.from(parts[0], 'base64url').toString()), header);
  assert.deepEqual(JSON.parse(Buffer.from(parts[1], 'base64url').toString()), payload);
  assert.equal(Buffer.from(parts[2], 'base64url').length, 64);
  assert.equal(crypto.verify('sha256', Buffer.from(input), publicKey, der), true);

  const noAth = cloud.dpopPayload('GET', 'https://relay.example.test/path', 'jti-2', 1700000001);
  assert.equal(Object.prototype.hasOwnProperty.call(noAth, 'ath'), false);
  assert.throws(() => cloud.dpopPayload('PO ST', target, 'jti', 1), /方法/);
  assert.throws(() => cloud.dpopPayload('GET', 'file:///secret', 'jti', 1), /地址/);
  assert.throws(() => cloud.dpopProof(input, raw.slice(0, 63)), /64/);
});

test('DER ECDSA conversion is fixed-width and tampering is rejected', () => {
  const input = Buffer.from('t3-code-dpop-der-check');
  const der = new Uint8Array(crypto.sign('sha256', input, privateKey));
  const raw = cloud.rawEccSignature(der);
  assert.equal(raw.length, 64);
  assert.equal(crypto.verify('sha256', input, publicKey, der), true);
  const tampered = raw.slice(); tampered[63] ^= 1;
  // Node accepts DER only; build DER from r||s to prove the converted values remain valid.
  const integer = value => {
    let start = 0;
    while (start < value.length - 1 && value[start] === 0) start++;
    const trimmed = value.slice(start);
    return (trimmed[0] & 0x80) !== 0 ? Uint8Array.from([0x02, trimmed.length + 1, 0, ...trimmed]) :
      Uint8Array.from([0x02, trimmed.length, ...trimmed]);
  };
  const r = integer(tampered.slice(0, 32)), s = integer(tampered.slice(32));
  const rebuilt = Buffer.from([0x30, r.length + s.length, ...r, ...s]);
  assert.equal(crypto.verify('sha256', input, publicKey, rebuilt), false);
  assert.throws(() => cloud.rawEccSignature(Uint8Array.from([0x30, 1, 0])), /签名/);
});

test('thumbprint input follows RFC 7638 member order and device approval code is deterministic', () => {
  assert.equal(cloud.dpopThumbprintInput(jwk),
    JSON.stringify({ crv: jwk.crv, kty: jwk.kty, x: jwk.x, y: jwk.y }));
  assert.match(cloud.connectDeviceVerificationCode('ABCDEFGHijklmnop'), /^[A-Z2-9]{4}-[A-Z2-9]{4}$/);
  assert.equal(cloud.connectDeviceVerificationCode('ABCDEFGHijklmnop'),
    cloud.connectDeviceVerificationCode('ABCDEFGHijklmnop'));
  assert.throws(() => cloud.checkedDpopPublicJwk({ kty: 'EC', crv: 'P-256', x: 'AA', y: 'AA' }));
});
