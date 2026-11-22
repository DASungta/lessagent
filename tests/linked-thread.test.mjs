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
  parseLinkedThreadHistoryPage
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
    threadId: 'thr%2D99',
    decodedThreadId: 'thr-99'
  });
  assert.equal(parseThreadLinkHref('https://example.com/threads/env-b/thr-99'), undefined);
  assert.equal(parseThreadLinkHref('t3-thread://v2/env-b/thr/extra'), undefined);
  assert.equal(parseThreadLinkHref('t3-thread://v1/'), undefined);
  assert.deepEqual(threadLinkCandidates('thr%201', 'thr 1'), ['thr 1', 'thr%201']);
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
