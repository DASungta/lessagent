#!/usr/bin/env node
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const archive = resolve(root, 'docs/baselines/t3code-ad1b136.tar.gz');
const baseline = JSON.parse(readFileSync(resolve(root, 'docs/evidence/r0/baseline.json'), 'utf8'));
const archiveSha = createHash('sha256').update(readFileSync(archive)).digest('hex');
if (baseline.commit !== 'ad1b1365999c92c3fc7a054e7f3af84623f74fee') throw new Error('unexpected baseline commit');
if (baseline.archive_sha256 !== archiveSha) throw new Error('baseline archive hash mismatch');
const output = process.argv[2] || resolve(root, 'docs/evidence/r2/upstream-contract.json');
const prefix = `t3code-ad1b136/`;
const cache = new Map();
const source = path => {
  if (!cache.has(path)) cache.set(path, execFileSync('tar', ['-xOzf', archive, prefix + path], {
    encoding: 'utf8', maxBuffer: 16 * 1024 * 1024
  }));
  return cache.get(path);
};
const checks = [
  ['public-config-gating', 'apps/mobile/src/features/cloud/publicConfig.ts',
    ['publishableKey', 'jwtTemplate', 'normalizeSecureRelayUrl', 'hasCloudPublicConfig']],
  ['secure-relay-origin', 'packages/shared/src/relayUrl.ts',
    [`url.protocol !== "https:"`, 'url.username.length', 'url.pathname', 'return url.origin']],
  ['dpop-jws', 'packages/client-runtime/src/relay/dpopProof.ts',
    ['typ: "dpop+jwt"', 'alg: "ES256"', 'htm:', 'htu,', 'jti:', 'iat:', 'ath:', 'raw `r‖s`']],
  ['dpop-thumbprint-order', 'packages/client-runtime/src/relay/dpopProof.ts',
    ['{ crv: jwk.crv, kty: jwk.kty, x: jwk.x, y: jwk.y }']],
  ['dpop-htu-normalization', 'packages/shared/src/dpopCommon.ts',
    ['parsed.hash = "";', 'parsed.search = "";']],
  ['relay-token-cache-binding', 'packages/client-runtime/src/relay/managedRelay.ts',
    ['token.accountId === input.accountId', 'token.clientId === input.clientId',
      'token.relayUrl === input.relayUrl', 'token.thumbprint === input.thumbprint',
      'input.scopes.every', 'expiresAtMillis > input.nowMillis + 5_000']],
  ['relay-invalid-bearer-retry', 'packages/client-runtime/src/relay/managedRelay.ts',
    ['reason === "invalid_bearer"', 'refreshRejectedToken ? attempt(false)']],
  ['relay-client-endpoints', 'packages/contracts/src/relay.ts',
    ['"/v1/client/dpop-token"', '"/v1/environments"', '"/v1/environments/:environmentId/status"',
      '"/v1/environments/:environmentId/connect"', '"/v1/client/environment-link-challenges"',
      '"/v1/client/environment-links"', 'authorization: TrimmedNonEmptyString',
      'dpop: TrimmedNonEmptyString', 'clientKeyThumbprint']],
  ['relay-connect-credential', 'packages/contracts/src/relay.ts',
    ['credential: TrimmedNonEmptyString', 'expiresAt: TrimmedNonEmptyString',
      'clientProofKeyThumbprint', 'providerKind']],
  ['environment-dpop-exchange', 'packages/client-runtime/src/authorization/service.ts',
    ['environmentEndpointUrl(bootstrap.endpoint.httpBaseUrl, "/oauth/token")',
      'expiresAtEpochMs', 'dpopThumbprint']],
  ['environment-link-http', 'packages/contracts/src/environmentHttp.ts',
    ['"/api/connect/link-proof"', '"/api/connect/relay-config"', 'RelayLinkProofRequest',
      'RelayEnvironmentConfigRequest']],
  ['device-approval-http', 'packages/contracts/src/environmentHttp.ts',
    ['"/api/auth/connect-devices/approve"', '"/api/auth/connect-devices/revoke"',
      '"/api/auth/pairing-links/revoke"']],
  ['device-approval-stream', 'packages/contracts/src/auth.ts',
    ['AuthConnectDeviceRequest', 'connectDeviceRequest', 'AuthAccessStreamEvent',
      'pairingLinkUpserted', 'pairingLinkRemoved']],
  ['account-cleanup-order', 'packages/client-runtime/src/relay/cloudAccountService.ts',
    ['handlers.deactivate();', 'await handlers.cleanUp', 'state = { _tag: "Active"']]
];
const result = checks.map(([id, path, markers]) => {
  const content = source(path);
  const missing = markers.filter(marker => !content.includes(marker));
  if (missing.length) throw new Error(`${id}: missing ${missing.join(', ')}`);
  return { id, path, markers, pass: true };
});
const report = {
  upstream: baseline.commit,
  archive: baseline.archive,
  archiveSha256: archiveSha,
  result: 'pass',
  checks: result,
  generatedAt: new Date().toISOString()
};
writeFileSync(output, JSON.stringify(report, null, 2) + '\n');
console.log(`R2 upstream contract audit: ${result.length}/${result.length} passed`);
