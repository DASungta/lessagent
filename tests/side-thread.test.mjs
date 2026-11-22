import test from 'node:test';
import assert from 'node:assert/strict';
import { sideThreadUrl } from './load-core.mjs';

const {
  DEFAULT_SIDE_THREAD_OPEN_TARGET,
  parseSideThreadOpenTarget,
  validSideThreadOpenTarget,
  sideThreadKindOf,
  sideThreadComposer,
  resolveSideThreadOpenTarget,
  pushSideThreadReturn,
  popSideThreadReturn,
  sideChatsForThread,
  sideThreadKindLabel
} = await import(sideThreadUrl);

test('L3: sideThreadOpenTarget parsing and unified target resolution across panel and main', () => {
  assert.equal(DEFAULT_SIDE_THREAD_OPEN_TARGET, 'panel');
  assert.equal(parseSideThreadOpenTarget(undefined), 'panel');
  assert.equal(parseSideThreadOpenTarget('main'), 'main');
  assert.equal(parseSideThreadOpenTarget('bogus'), 'panel');
  assert.equal(validSideThreadOpenTarget('panel'), true);
  assert.equal(validSideThreadOpenTarget('main'), true);
  assert.equal(validSideThreadOpenTarget('popup'), false);

  assert.equal(resolveSideThreadOpenTarget('panel', 'primary', true), 'panel');
  assert.equal(resolveSideThreadOpenTarget('panel', 'alternate', true), 'main');
  assert.equal(resolveSideThreadOpenTarget('main', 'primary', true), 'main');
  assert.equal(resolveSideThreadOpenTarget('main', 'alternate', true), 'panel');
  assert.equal(resolveSideThreadOpenTarget('panel', 'main', true), 'main');
  assert.equal(resolveSideThreadOpenTarget('panel', 'primary', false), 'main');
});

test('L3: sideThreadKindOf and sideThreadComposer classify side chats, subagents, provider subagents, and linked threads', () => {
  assert.equal(sideThreadKindOf({ lineageSideChat: true, lineageParentThreadId: 'p1', lineageRelationship: 'fork' }), 'side-chat');
  assert.equal(sideThreadKindOf({ lineageSideChat: false, lineageParentThreadId: 'p1', lineageRelationship: 'subagent', creationSource: 'agent' }), 'subagent');
  assert.equal(sideThreadKindOf({ lineageSideChat: false, lineageParentThreadId: 'p1', lineageRelationship: 'subagent', creationSource: 'provider' }), 'provider-subagent');
  assert.equal(sideThreadKindOf({ lineageSideChat: false, lineageParentThreadId: '', lineageRelationship: 'fork' }), undefined);

  assert.equal(sideThreadComposer('side-chat'), 'composer');
  assert.equal(sideThreadComposer('subagent'), 'composer');
  assert.equal(sideThreadComposer('provider-subagent'), 'read-only');
  assert.equal(sideThreadComposer('linked'), 'read-only-connect');
  assert.equal(sideThreadKindLabel('side-chat'), '侧聊');
  assert.equal(sideThreadKindLabel('linked'), '链接环境会话');
});

test('L3: return stack preserves parent scroll position, deduplicates consecutive top, and restores on pop', () => {
  let stack = [];
  stack = pushSideThreadReturn(stack, { localId: 'e1', threadId: 't1', scrollY: 420, scrollIndex: 3 });
  stack = pushSideThreadReturn(stack, { localId: 'e1', threadId: 't1', scrollY: 510, scrollIndex: 4 });
  assert.equal(stack.length, 1);
  assert.equal(stack[0].scrollY, 510);

  stack = pushSideThreadReturn(stack, { localId: 'e1', threadId: 't2', scrollY: 120, scrollIndex: 1 });
  assert.equal(stack.length, 2);

  const firstPop = popSideThreadReturn(stack);
  assert.deepEqual(firstPop.point, { localId: 'e1', threadId: 't2', scrollY: 120, scrollIndex: 1 });
  assert.equal(firstPop.rest.length, 1);

  const secondPop = popSideThreadReturn(firstPop.rest);
  assert.deepEqual(secondPop.point, { localId: 'e1', threadId: 't1', scrollY: 510, scrollIndex: 4 });
  assert.equal(secondPop.rest.length, 0);
});

test('L3: sideChatsForThread filters active side chats of parent thread newest first', () => {
  const chats = sideChatsForThread([
    { id: 'sc-old', lineageSideChat: true, lineageParentThreadId: 'parent', updatedAt: '2026-11-20T10:00:00Z', archivedAt: '', deletedAt: '' },
    { id: 'sc-new', lineageSideChat: true, lineageParentThreadId: 'parent', updatedAt: '2026-11-20T12:00:00Z', archivedAt: '', deletedAt: '' },
    { id: 'sc-arch', lineageSideChat: true, lineageParentThreadId: 'parent', updatedAt: '2026-11-20T13:00:00Z', archivedAt: '2026-11-20T13:01:00Z', deletedAt: '' },
    { id: 'other', lineageSideChat: true, lineageParentThreadId: 'other-parent', updatedAt: '2026-11-20T14:00:00Z', archivedAt: '', deletedAt: '' },
    { id: 'normal-fork', lineageSideChat: false, lineageParentThreadId: 'parent', updatedAt: '2026-11-20T14:00:00Z', archivedAt: '', deletedAt: '' }
  ], 'parent');
  assert.deepEqual(chats.map((c) => c.id), ['sc-new', 'sc-old']);
});
