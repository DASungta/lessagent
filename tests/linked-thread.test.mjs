import test from 'node:test';
import assert from 'node:assert/strict';
import { linkedThreadUrl } from './load-core.mjs';
import { RpcFailure } from '../entry/src/main/ets/protocol/Wire.ts';

const {
  LINKED_THREAD_RETRY_MS,
  parsePeerLinkNames,
  parseThreadLinkHref,
  threadLinkCandidates,
  resolveLinkedThreadOpen,
  isLinkedThreadUnreachable,
  linkedThreadFailure,
  isLinkedThreadWorking,
  parseLinkedThreadHistoryPage,
  parsePeerLinkClientPairingResult,
  prepareLinkedEnvironmentConnection,
  linkedManualReasonMessage
} = await import(linkedThreadUrl);

test('parseThreadLinkHref handles v1, v2, app.t3.codes links and rejects invalid targets', () => {
  assert.deepEqual(parseThreadLinkHref('t3-thread://v1/thread-123'), {
    environmentId: '',
    threadId: 'thread-123',
    decodedThreadId: 'thread-123'
  });
  assert.deepEqual(parseThreadLinkHref('t3-thread://v2/env-b/thread%2042'), {
    environmentId: 'env-b',
    threadId: 'thread%2042',
    decodedThreadId: 'thread 42'
  });
  assert.deepEqual(parseThreadLinkHref('https://app.t3.codes/threads/env%2Db/thr%2D99?foo=bar'), {
    environmentId: 'env-b',
    threadId: 'thr-99',
    decodedThreadId: 'thr-99'
  });
  assert.equal(parseThreadLinkHref('https://example.com/threads/env-b/thr-99'), undefined);
  assert.equal(parseThreadLinkHref('t3-thread://v2/env-b/thr/extra'), undefined);
  assert.equal(parseThreadLinkHref('t3-thread://v1/'), undefined);
  assert.deepEqual(threadLinkCandidates('thread:delegated-task:mcp%3A1', 'thread:delegated-task:mcp:1'), [
    'thread:delegated-task:mcp%3A1',
    'thread:delegated-task:mcp:1'
  ]);
  assert.deepEqual(threadLinkCandidates('thr-1', 'thr-1'), ['thr-1']);
});

test('parsePeerLinkNames parses unexpired link names and defaults missing label to environmentId', () => {
  assert.deepEqual(
    parsePeerLinkNames({
      links: [
        { environmentId: 'env-b', label: 'Build Server' },
        { environmentId: 'env-c', label: '' },
        { environmentId: '', label: 'Bad' }
      ]
    }),
    [
      { environmentId: 'env-b', label: 'Build Server' },
      { environmentId: 'env-c', label: 'env-c' }
    ]
  );
});

test('resolveLinkedThreadOpen picks direct when connected, linked via peer, else unavailable', () => {
  assert.equal(resolveLinkedThreadOpen({
    ownConnected: true,
    targetEnvironmentId: 'env-b',
    viaEnvironmentId: 'env-a',
    linkedEnvironmentsEnabled: false
  }), 'direct');
  assert.equal(resolveLinkedThreadOpen({
    ownConnected: false,
    targetEnvironmentId: 'env-b',
    viaEnvironmentId: 'env-a',
    linkedEnvironmentsEnabled: true
  }), 'linked');
  assert.equal(resolveLinkedThreadOpen({
    ownConnected: false,
    targetEnvironmentId: 'env-a',
    viaEnvironmentId: 'env-a',
    linkedEnvironmentsEnabled: true
  }), 'unavailable');
  assert.equal(resolveLinkedThreadOpen({
    ownConnected: false,
    targetEnvironmentId: 'env-b',
    viaEnvironmentId: 'env-a',
    linkedEnvironmentsEnabled: false
  }), 'unavailable');
});

test('linkedThreadFailure classifies authorization and PeerLinkThreadReadError without retrying permanent errors', () => {
  assert.equal(LINKED_THREAD_RETRY_MS, 15000);

  const authErr = new RpcFailure('denied', true, 'EnvironmentAuthorizationError', '', 'missing scope');
  const auth = linkedThreadFailure(authErr, 'Server B');
  assert.equal(auth.reason, 'unauthorized');
  assert.equal(auth.retryable, false);
  assert.equal(isLinkedThreadUnreachable(authErr), false);

  const nonRetryableReasons = ['disabled', 'unknown_link', 'expired', 'rejected', 'thread_not_found', 'incompatible'];
  for (const reason of nonRetryableReasons) {
    const err = new RpcFailure('failed', true, 'PeerLinkThreadReadError', reason, 'msg', 'Remote B');
    const mapped = linkedThreadFailure(err, 'Fallback');
    assert.equal(mapped.reason, reason);
    assert.equal(mapped.retryable, false, `${reason} must not retry`);
    assert.equal(mapped.label, 'Remote B');
    assert.equal(isLinkedThreadUnreachable(err), false);
  }

  const unreachable = new RpcFailure('failed', true, 'PeerLinkThreadReadError', 'unreachable', 'offline', 'Remote B');
  const mappedUnreachable = linkedThreadFailure(unreachable, 'Fallback');
  assert.equal(mappedUnreachable.reason, 'unreachable');
  assert.equal(mappedUnreachable.retryable, true);
  assert.equal(isLinkedThreadUnreachable(unreachable), true);

  const networkDrop = new RpcFailure('socket closed', false);
  assert.equal(linkedThreadFailure(networkDrop, 'Fallback').retryable, true);
  assert.equal(isLinkedThreadUnreachable(networkDrop), true);

  const unknownRefusal = new RpcFailure('bad request', true, 'SomeError', 'bad', 'server detail');
  const mappedUnknown = linkedThreadFailure(unknownRefusal, 'Fallback');
  assert.equal(mappedUnknown.retryable, false);
  assert.equal(mappedUnknown.detail, 'server detail');
});

test('isLinkedThreadWorking and parseLinkedThreadHistoryPage handle run status and projected items', () => {
  assert.equal(isLinkedThreadWorking([{ status: 'completed' }, { status: 'failed' }]), false);
  assert.equal(isLinkedThreadWorking([{ status: 'completed' }, { status: 'running' }]), true);
  assert.equal(isLinkedThreadWorking([{ status: 'waiting' }]), true);

  const page = parseLinkedThreadHistoryPage({
    items: [
      { item: { id: 'i1', type: 'user_message', messageId: 'm1', text: 'hi' }, visibility: 'visible', sourceThreadId: 't1' }
    ],
    nextCursor: 'cur-2',
    hasMoreHistory: true
  });
  assert.equal(page.nextCursor, 'cur-2');
  assert.equal(page.hasMoreHistory, true);
  assert.equal(page.items.length, 1);
  assert.equal(page.items[0].id, 'i1');
  assert.equal(page.items[0].visibility, 'visible');
  assert.equal(page.items[0].sourceThreadId, 't1');
});

test('L2: parsePeerLinkClientPairingResult parses credential and unsupported payloads', () => {
  const cred = parsePeerLinkClientPairingResult({
    type: 'credential',
    environmentId: 'env-b',
    label: 'Server B',
    urls: ['http://192.168.1.5:14882', 'ftp://ignored', 'https://b.tail.ts.net'],
    credential: 'ONE-TIME-CODE',
    expiresAt: '2026-11-23T12:00:00Z'
  });
  assert.equal(cred.type, 'credential');
  assert.equal(cred.credential, 'ONE-TIME-CODE');
  assert.deepEqual(cred.urls, ['http://192.168.1.5:14882', 'https://b.tail.ts.net']);

  const unsupported = parsePeerLinkClientPairingResult({
    type: 'unsupported',
    environmentId: 'env-b',
    label: 'Server B',
    urls: ['http://192.168.1.5:14882'],
    reason: 'link_access'
  });
  assert.equal(unsupported.type, 'unsupported');
  assert.equal(unsupported.reason, 'link_access');
  assert.match(linkedManualReasonMessage('Server B', 'link_access'), /完全访问权限/);
});

test('L2: prepareLinkedEnvironmentConnection switches directly if already connected, prefers first reachable URL, and handles unreachable/manual fallback', async () => {
  let asked = 0;
  const already = await prepareLinkedEnvironmentConnection({
    environmentId: 'env-b',
    label: 'Server B',
    alreadyConnectedLocalId: 'local-b',
    requestPairing: async () => { asked++; return undefined; },
    reaches: async () => true
  });
  assert.equal(already.type, 'already_connected');
  assert.equal(already.localId, 'local-b');
  assert.equal(asked, 0);

  const prefilled = await prepareLinkedEnvironmentConnection({
    environmentId: 'env-b',
    label: 'Server B',
    alreadyConnectedLocalId: '',
    requestPairing: async () => ({
      type: 'credential',
      environmentId: 'env-b',
      label: 'Server B',
      urls: ['http://dead.local:14882', 'http://192.168.1.5:14882', 'https://b.ts.net'],
      credential: 'SECRET-CODE',
      expiresAt: '2026-11-23T12:00:00Z'
    }),
    reaches: async (url) => url !== 'http://dead.local:14882'
  });
  assert.equal(prefilled.type, 'prefill');
  assert.equal(prefilled.prefill.host, 'http://192.168.1.5:14882');
  assert.equal(prefilled.prefill.credential, 'SECRET-CODE');
  assert.equal(prefilled.prefill.manualReason, '');

  const unreachable = await prepareLinkedEnvironmentConnection({
    environmentId: 'env-b',
    label: 'Server B',
    alreadyConnectedLocalId: '',
    requestPairing: async () => ({
      type: 'credential',
      environmentId: 'env-b',
      label: 'Server B',
      urls: ['http://dead.local:14882'],
      credential: 'SECRET-CODE',
      expiresAt: '2026-11-23T12:00:00Z'
    }),
    reaches: async () => false
  });
  assert.equal(unreachable.type, 'unreachable');
  assert.equal(unreachable.label, 'Server B');

  const manual = await prepareLinkedEnvironmentConnection({
    environmentId: 'env-b',
    label: 'Server B',
    alreadyConnectedLocalId: '',
    requestPairing: async () => ({
      type: 'unsupported',
      environmentId: 'env-b',
      label: 'Server B',
      urls: ['http://192.168.1.5:14882'],
      reason: 'version'
    }),
    reaches: async () => false
  });
  assert.equal(manual.type, 'prefill');
  assert.equal(manual.prefill.host, 'http://192.168.1.5:14882');
  assert.equal(manual.prefill.credential, '');
  assert.equal(manual.prefill.manualReason, 'version');

  const noPermission = await prepareLinkedEnvironmentConnection({
    environmentId: 'env-b',
    label: 'Server B',
    alreadyConnectedLocalId: '',
    requestPairing: async () => undefined,
    reaches: async () => false
  });
  assert.equal(noPermission.type, 'prefill');
  assert.equal(noPermission.prefill.host, '');
  assert.equal(noPermission.prefill.credential, '');
});
