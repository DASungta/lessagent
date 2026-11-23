import test from 'node:test';
import assert from 'node:assert/strict';
import { linkBatchUrl } from './load-core.mjs';
import { RpcFailure } from '../entry/src/main/ets/protocol/Wire.ts';

const {
  LINK_BATCH_CONCURRENCY,
  linkBatchCandidates,
  linkBatchBlockLabel,
  peerLinkFailureKind,
  linkBatchFailureLabel,
  linkBatchFailureFromError,
  runLinkBatch,
  linkBatchSummary
} = await import(linkBatchUrl);

test('L4: linkBatchCandidates blocks machines when links unknown, already linked, disconnected, read-only, or without address', () => {
  const machines = [
    { localId: 'l1', environmentId: 'e1', label: 'M1', urls: ['http://10.0.0.1:3773'], connected: true, linked: false },
    { localId: 'l2', environmentId: 'e2', label: 'M2', urls: ['http://10.0.0.2:3773'], connected: true, linked: true },
    { localId: 'l3', environmentId: 'e3', label: 'M3', urls: ['http://10.0.0.3:3773'], connected: false, linked: false },
    { localId: 'l4', environmentId: 'e4', label: 'M4', urls: ['http://10.0.0.4:3773'], connected: true, linked: false },
    { localId: 'l5', environmentId: 'e5', label: 'M5', urls: [], connected: true, linked: false }
  ];
  const writable = new Set(['e1', 'e2', 'e3', 'e5']);

  const loading = linkBatchCandidates(machines, writable, 'loading');
  assert.ok(loading.every((c) => c.blocked === 'links_unknown'));

  const loaded = linkBatchCandidates(machines, writable, 'loaded');
  assert.deepEqual(loaded.map((c) => c.blocked), [null, 'linked', 'not_connected', 'no_access', 'no_address']);
  assert.match(linkBatchBlockLabel('no_access'), /配对码/);
});

test('L4: peerLinkFailureKind and linkBatchFailureFromError map structured PeerLinkError and hide non-PeerLink errors', () => {
  const wrong = new RpcFailure('denied', true, 'PeerLinkError', 'unreachable', 'answered as X', '', 'OtherMachine');
  assert.equal(peerLinkFailureKind(wrong), 'wrong_environment');
  assert.deepEqual(linkBatchFailureFromError(wrong), {
    kind: 'failed',
    failure: 'wrong_environment',
    detail: 'answered as X'
  });

  const refused = new RpcFailure('denied', true, 'PeerLinkError', 'pairing_rejected', 'expired');
  assert.equal(peerLinkFailureKind(refused), 'code_refused');
  assert.equal(linkBatchFailureLabel('code_refused'), '配对码被拒绝');

  const unreach = new RpcFailure('denied', true, 'PeerLinkError', 'not_a_t3_environment', 'bad host');
  assert.equal(peerLinkFailureKind(unreach), 'unreachable');

  const leakRisk = new Error('request failed with pairingCode=TOP-SECRET');
  const sanitized = linkBatchFailureFromError(leakRisk);
  assert.deepEqual(sanitized, { kind: 'failed', failure: 'other', detail: '' });
});

test('L4: runLinkBatch runs with bounded concurrency, isolates per-machine failures, and refreshes links once', async () => {
  assert.equal(LINK_BATCH_CONCURRENCY, 4);
  const machines = [
    { localId: 'l1', environmentId: 'e1', label: 'B1', urls: ['http://10.0.0.1:14882', 'http://10.0.0.1:14892'], connected: true, linked: false },
    { localId: 'l2', environmentId: 'e2', label: 'B2', urls: ['http://10.0.0.2:14882'], connected: true, linked: false },
    { localId: 'l3', environmentId: 'e3', label: 'B3', urls: ['http://10.0.0.3:14882'], connected: true, linked: false }
  ];
  const sentPayloads = [];
  let refreshes = 0;
  const outcomes = await runLinkBatch({
    machines,
    access: 'full-access',
    mint: async (m) => {
      if (m.environmentId === 'e2') throw new Error('mint denied');
      return 'CODE-' + m.environmentId;
    },
    link: async (payload) => {
      sentPayloads.push(payload);
      if (payload.expectedEnvironmentId === 'e3') {
        throw new RpcFailure('fail', true, 'PeerLinkError', 'unreachable', 'dial timeout');
      }
    },
    refreshLinks: () => { refreshes += 1; }
  });

  assert.equal(refreshes, 1);
  assert.equal(outcomes.get('e1').kind, 'linked');
  assert.equal(outcomes.get('e2').kind, 'failed');
  assert.equal(outcomes.get('e2').failure, 'no_code');
  assert.equal(outcomes.get('e3').kind, 'failed');
  assert.equal(outcomes.get('e3').failure, 'unreachable');
  assert.equal(outcomes.get('e3').detail, 'dial timeout');

  const b1Req = sentPayloads.find((p) => p.expectedEnvironmentId === 'e1');
  assert.equal(b1Req.url, 'http://10.0.0.1:14882');
  assert.deepEqual(b1Req.alternateUrls, ['http://10.0.0.1:14892']);
  assert.equal(b1Req.pairingCode, 'CODE-e1');
  assert.equal(b1Req.access, 'full-access');

  assert.deepEqual(linkBatchSummary(outcomes), { linked: 1, failed: ['e2', 'e3'] });
});
