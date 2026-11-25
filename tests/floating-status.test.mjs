import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { floatingStatusUrl, projectsUrl } from './load-core.mjs';
import { ThreadState } from '../entry/src/main/ets/protocol/Wire.ts';

const F = await import(floatingStatusUrl);
const P = await import(projectsUrl);

const baseThread = (extra = {}) => ({
  id: 't1',
  projectId: 'p1',
  title: 'Thread 1',
  createdAt: '2026-01-01T00:00:00.000Z',
  updatedAt: '2026-01-01T00:00:00.000Z',
  status: 'idle',
  ...extra
});

const baseInput = (overrides = {}) => ({
  draftMode: false,
  ready: true,
  connecting: false,
  environmentLabel: 'DESKTOP',
  connectionError: '',
  unknown: false,
  pendingActionCount: 0,
  canOperateThread: true,
  canForceStop: true,
  forceStopping: false,
  backgroundStopPending: false,
  nowMs: Date.parse('2026-01-01T00:01:00.000Z'),
  threadSynced: true,
  runs: [],
  turnItems: [],
  messages: [],
  subagents: [],
  providerThreads: [],
  nodes: [],
  details: { id: 't1' },
  shellThread: P.threadView(baseThread()),
  allThreads: [],
  selectedLocalId: 'local-1',
  queuedCount: 0,
  hasWorktreeSetupCard: false,
  supportsSnooze: true,
  supportsSettlement: true,
  ...overrides
});

test('ThreadState tracks providerThreads, providerSessions, nodes, subagent body preservation, and lifecycle events', () => {
  const state = new ThreadState('t1');
  state.apply({
    kind: 'snapshot',
    snapshotSequence: 10,
    projection: {
      thread: { id: 't1', projectId: 'p1', title: 'Main', activeProviderThreadId: 'pt-1' },
      runs: [{ id: 'r1', ordinal: 1, status: 'waiting', startedAt: '2026-01-01T00:00:00.000Z' }],
      messages: [],
      subagents: [{ id: 's1', runId: 'r1', prompt: 'Inspect logs', status: 'running', updatedAt: '2026-01-01T00:00:10.000Z' }],
      providerThreads: [{ id: 'pt-1', appThreadId: 't1', status: 'idle', pendingBackgroundTasks: [{ taskId: 'bg-1', kind: 'subagent', description: 'Subagent: v7 夜景光' }] }],
      providerSessions: [{ id: 'ps-1', driver: 'claudeAgent', status: 'idle' }],
      nodes: [{ id: 'n1', kind: 'root_turn', runId: null, status: 'running', startedAt: '2026-01-01T00:00:05.000Z' }],
      turnItems: []
    }
  });
  assert.equal(state.providerThreads.length, 1);
  assert.equal(state.providerSessions.length, 1);
  assert.equal(state.nodes.length, 1);

  // subagent.updated with promptOmitted keeps original prompt body
  state.apply({
    kind: 'event',
    sequence: 11,
    event: {
      threadId: 't1',
      type: 'subagent.updated',
      payload: { id: 's1', runId: 'r1', prompt: '', promptOmitted: true, status: 'completed', result: 'Done', updatedAt: '2026-01-01T00:00:20.000Z' }
    }
  });
  assert.equal(state.subagents[0].prompt, 'Inspect logs');
  assert.equal(state.subagents[0].result, 'Done');

  // provider-thread.updated updates activeProviderThreadId when not a queued placeholder
  state.apply({
    kind: 'event',
    sequence: 12,
    event: {
      threadId: 't1',
      type: 'provider-thread.updated',
      payload: { id: 'pt-queued', appThreadId: 't1', status: 'not_loaded', nativeThreadRef: null, firstRunOrdinal: null }
    }
  });
  assert.equal(state.details.activeProviderThreadId, 'pt-1');
  state.apply({
    kind: 'event',
    sequence: 13,
    event: {
      threadId: 't1',
      type: 'provider-thread.updated',
      payload: { id: 'pt-2', appThreadId: 't1', status: 'active', nativeThreadRef: { id: 'n' }, firstRunOrdinal: 2 }
    }
  });
  assert.equal(state.details.activeProviderThreadId, 'pt-2');

  // provider-session.detached removes session
  state.apply({
    kind: 'event',
    sequence: 14,
    event: { threadId: 't1', type: 'provider-session.detached', payload: { providerSessionId: 'ps-1' } }
  });
  assert.equal(state.providerSessions.length, 0);

  // thread.settled and thread.visit-recorded update details
  state.apply({
    kind: 'event',
    sequence: 15,
    event: { threadId: 't1', type: 'thread.settled', payload: { id: 't1', settledOverride: 'settled' } }
  });
  assert.equal(state.details.settledOverride, 'settled');
  state.apply({
    kind: 'event',
    sequence: 16,
    event: { threadId: 't1', type: 'thread.visit-recorded', payload: { lastVisitedAt: '2026-01-01T00:05:00.000Z' } }
  });
  assert.equal(state.details.lastVisitedAt, '2026-01-01T00:05:00.000Z');
});

test('derivePendingBackgroundWork and presentPendingBackgroundWork handle active runs, waiting subagents, commands, PR watches, and deduplication', () => {
  // Active running run hides pending background tasks
  assert.deepEqual(
    F.derivePendingBackgroundWork(
      [{ id: 'r1', ordinal: 1, status: 'running' }],
      [{ id: 'pt-1', pendingBackgroundTasks: [{ taskId: 'k1', kind: 'subagent', description: 'Worker' }] }],
      [],
      { activeProviderThreadId: 'pt-1' }
    ),
    []
  );

  // Settled/waiting run collects providerThread tasks, turn items (deduped by nativeId), and PR watches
  const tasks = F.derivePendingBackgroundWork(
    [{ id: 'r1', ordinal: 1, status: 'waiting' }],
    [{ id: 'pt-1', pendingBackgroundTasks: [{ taskId: 'native-1', kind: 'subagent', description: 'Subagent: v7 夜景光、壁灯落幕' }] }],
    [
      { id: 'ti-1', runId: 'r1', type: 'subagent', status: 'running', title: 'Duplicate', nativeItemRef: { nativeId: 'native-1' } },
      { id: 'ti-2', runId: 'r1', type: 'command_execution', status: 'running', command: 'npm run dev\nlistening' }
    ],
    {
      activeProviderThreadId: 'pt-1',
      pullRequests: [{ host: 'github.com', repository: 'org/repo', number: 42, source: 'manual', watch: { checksPending: true }, snapshot: { state: 'open' } }]
    }
  );
  assert.equal(tasks.length, 3);
  const singleSubagent = F.presentPendingBackgroundWork([tasks[0]]);
  assert.equal(singleSubagent.waiting, true);
  assert.equal(singleSubagent.title, '等待 · v7 夜景光、壁灯落幕');

  const multi = F.presentPendingBackgroundWork(tasks);
  assert.equal(multi.waiting, true);
  assert.equal(multi.title, '等待 1 个子 Agent、1 个命令、1 个监控');

  const nonWaitingCmd = F.presentPendingBackgroundWork([{ taskId: 'c1', kind: 'command', label: 'npm run dev', childThreadId: '', awaited: false }]);
  assert.equal(nonWaitingCmd.waiting, false);
  assert.equal(nonWaitingCmd.title, '运行中 · npm run dev');
});

test('deriveThreadTurnSubagents and resolveSubagentPillSegment produce live 1/3, settled count, and hide older turns', () => {
  const runs = [
    { id: 'r1', ordinal: 1, status: 'completed', startedAt: '2026-01-01T00:00:00.000Z' },
    { id: 'r2', ordinal: 2, status: 'waiting', startedAt: '2026-01-01T00:01:00.000Z' },
    { id: 'r3', ordinal: 3, status: 'rolled_back', startedAt: '2026-01-01T00:02:00.000Z' }
  ];
  const rawSubagents = [
    { id: 'a1', runId: 'r2', title: 'Subagent: Task 1', status: 'running', startedAt: '2026-01-01T00:01:01.000Z', updatedAt: '2026-01-01T00:01:05.000Z' },
    { id: 'a2', runId: 'r2', title: 'Task 2', status: 'completed', startedAt: '2026-01-01T00:01:02.000Z', updatedAt: '2026-01-01T00:01:06.000Z' },
    { id: 'a3', runId: 'r2', title: 'Task 3', status: 'completed', startedAt: '2026-01-01T00:01:03.000Z', updatedAt: '2026-01-01T00:01:07.000Z' },
    { id: 'a-rolled', runId: 'r3', title: 'Rolled back', status: 'running', updatedAt: '2026-01-01T00:02:01.000Z' },
    { id: 'a-old', runId: 'r1', title: 'Old completed', status: 'completed', updatedAt: '2026-01-01T00:00:10.000Z' }
  ];
  const turn = F.deriveThreadTurnSubagents(runs, rawSubagents);
  assert.equal(turn.runId, 'r2');
  assert.equal(turn.subagents.length, 3);
  assert.equal(turn.subagents[0].title, 'Task 1');
  assert.equal(F.resolveSubagentPillSegment(turn).label, '1/3');

  // When all 3 finish in latest turn, pill shows '3 已完成'
  const finishedTurn = F.deriveThreadTurnSubagents(
    [{ id: 'r2', ordinal: 2, status: 'completed', startedAt: '2026-01-01T00:01:00.000Z' }],
    rawSubagents.slice(0, 3).map(s => ({ ...s, status: 'completed' }))
  );
  assert.equal(F.resolveSubagentPillSegment(finishedTurn).label, '3 已完成');

  // When a newer turn starts without agents, completed earlier turn's agents hide
  const laterTurnNoAgents = F.deriveThreadTurnSubagents(
    [
      { id: 'r1', ordinal: 1, status: 'completed', startedAt: '2026-01-01T00:00:00.000Z' },
      { id: 'r2', ordinal: 2, status: 'completed', startedAt: '2026-01-01T00:01:00.000Z' }
    ],
    [{ id: 'a-old', runId: 'r1', title: 'Old', status: 'completed', updatedAt: '2026-01-01T00:00:10.000Z' }]
  );
  assert.equal(F.resolveSubagentPillSegment(laterTurnNoAgents), undefined);
});

test('deriveFloatingCapsuleModel matches screenshot Waiting · <title> | Stop | 1/3 and respects priority order', () => {
  const waitingBg = F.deriveFloatingCapsuleModel(baseInput({
    runs: [{ id: 'r1', ordinal: 1, status: 'waiting', startedAt: '2026-01-01T00:00:30.000Z' }],
    providerThreads: [{ id: 'pt-1', pendingBackgroundTasks: [{ taskId: 'bg-1', kind: 'subagent', description: 'Subagent: v7 夜景光、壁灯落...', childThreadId: 'c1' }] }],
    details: { id: 't1', activeProviderThreadId: 'pt-1' },
    subagents: [
      { id: 's1', runId: 'r1', title: 'v7 夜景光', status: 'running', updatedAt: '2026-01-01T00:00:40.000Z' },
      { id: 's2', runId: 'r1', title: '壁灯落', status: 'completed', updatedAt: '2026-01-01T00:00:35.000Z' },
      { id: 's3', runId: 'r1', title: '门窗', status: 'completed', updatedAt: '2026-01-01T00:00:36.000Z' }
    ]
  }));
  assert.equal(waitingBg.visible, true);
  assert.equal(waitingBg.status.kind, 'background');
  assert.equal(waitingBg.status.label, '等待 · v7 夜景光、壁灯落...');
  assert.equal(waitingBg.status.actionLabel, '停止');
  assert.equal(waitingBg.status.actionKind, 'stop-background');
  assert.equal(waitingBg.agents.label, '1/3');

  // Disconnected overrides everything
  const disconnected = F.deriveFloatingCapsuleModel(baseInput({ ready: false, connecting: true }));
  assert.equal(disconnected.status.kind, 'connection');
  assert.equal(disconnected.status.icon, 'spinner');

  // Run stop unresponsive offers Force stop
  const stopUnresponsive = F.deriveFloatingCapsuleModel(baseInput({
    runs: [{ id: 'r1', ordinal: 1, status: 'running' }],
    turnItems: [{ id: 'i1', runId: 'r1', type: 'run_interrupt_request', startedAt: '2026-01-01T00:00:50.000Z', unresponsiveAt: '2026-01-01T00:00:58.000Z' }]
  }));
  assert.equal(stopUnresponsive.status.kind, 'stop');
  assert.equal(stopUnresponsive.status.actionKind, 'force-stop');

  // Pending action overrides child-input & working
  const actionNeeded = F.deriveFloatingCapsuleModel(baseInput({ pendingActionCount: 2, queuedCount: 3 }));
  assert.equal(actionNeeded.status.kind, 'action-needed');
  assert.equal(actionNeeded.status.label, '2 个请求待处理');
  assert.equal(actionNeeded.queuedCount, 3);

  // Child input overrides working
  const childInput = F.deriveFloatingCapsuleModel(baseInput({
    allThreads: [
      P.threadView(baseThread({
        id: 'child-1',
        title: 'Inspect Worker',
        status: 'waiting',
        activityRunStatus: 'waiting',
        lineage: { relationshipToParent: 'subagent', parentThreadId: 't1' },
        pendingRuntimeRequest: { id: 'req-1', kind: 'approval', createdAt: '2026-01-01T00:00:40.000Z' }
      }))
    ],
    runs: [{ id: 'r1', ordinal: 1, status: 'running', startedAt: '2026-01-01T00:00:20.000Z' }]
  }));
  assert.equal(childInput.status.kind, 'child-input');
  assert.equal(childInput.status.targetThreadId, 'child-1');

  // Compacting overrides working
  const compacting = F.deriveFloatingCapsuleModel(baseInput({
    runs: [{ id: 'r1', ordinal: 1, status: 'running', startedAt: '2026-01-01T00:00:20.000Z' }],
    turnItems: [{ id: 'c1', runId: 'r1', type: 'compaction', status: 'running' }]
  }));
  assert.equal(compacting.status.kind, 'compacting');

  // Running displays working timer
  const working = F.deriveFloatingCapsuleModel(baseInput({
    runs: [{ id: 'r1', ordinal: 1, status: 'running', startedAt: '2026-01-01T00:00:18.000Z' }]
  }));
  assert.equal(working.status.kind, 'working');
  assert.equal(working.status.label, '运行中 42s');
  assert.equal(F.formatWorkingDuration('2026-01-01T00:00:00.000Z', Date.parse('2026-01-01T00:01:05.000Z')), '1m 05s');
  assert.equal(F.formatWorkingDuration('2026-01-01T00:00:00.000Z', Date.parse('2026-01-01T01:02:05.000Z')), '1h 02m');
});

test('deriveFloatingCapsuleModel handles lifecycle snoozed/settled/woke and goals', () => {
  const snoozed = F.deriveFloatingCapsuleModel(baseInput({
    shellThread: P.threadView(baseThread({
      snoozedUntil: '2026-01-01T00:31:00.000Z',
      snoozedAt: '2026-01-01T00:00:00.000Z'
    }))
  }));
  assert.equal(snoozed.status.kind, 'lifecycle');
  assert.equal(snoozed.status.actionKind, 'wake');

  const settled = F.deriveFloatingCapsuleModel(baseInput({
    shellThread: P.threadView(baseThread({ settledOverride: 'settled' }))
  }));
  assert.equal(settled.status.kind, 'lifecycle');
  assert.equal(settled.status.actionKind, 'unsettle');

  const woke = F.deriveFloatingCapsuleModel(baseInput({
    shellThread: P.threadView(baseThread({
      lastSnoozeWakeAt: '2026-01-01T00:00:50.000Z',
      lastVisitedAt: '2026-01-01T00:00:10.000Z'
    }))
  }));
  assert.equal(woke.status.kind, 'lifecycle');
  assert.equal(woke.status.actionKind, 'dismiss-woke');

  const goal = F.deriveFloatingCapsuleModel(baseInput({
    providerThreads: [{ id: 'pt-1', goal: { objective: 'Keep tests green', status: 'paused' } }],
    details: { id: 't1', activeProviderThreadId: 'pt-1' }
  }));
  assert.equal(goal.status.kind, 'goal');
  assert.equal(goal.status.label, '目标已暂停');
});

test('chat message List overlays FloatingStatusCapsule via content offsets instead of clipping padding', async () => {
  const indexSource = await readFile(new URL('../entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
  const capsuleSource = await readFile(new URL('../entry/src/main/ets/components/FloatingStatusCapsule.ets', import.meta.url), 'utf8');

  const stackStart = indexSource.indexOf('Stack({ alignContent: Alignment.Bottom }) {\n      List({ space: 14, scroller: this.scroller })');
  assert.ok(stackStart > 0, 'chat List Stack should exist in Index.ets');
  const stackEnd = indexSource.indexOf('}.width(\'100%\').layoutWeight(1)', stackStart);
  assert.ok(stackEnd > stackStart);
  const chatListBlock = indexSource.slice(stackStart, stackEnd);

  assert.match(chatListBlock, /\.padding\(\{\s*left:\s*Space\.md,\s*right:\s*Space\.md\s*\}\)/);
  assert.match(chatListBlock, /\.contentStartOffset\(Space\.xs\)/);
  assert.match(chatListBlock, /\.contentEndOffset\(this\.floatingCapsule\.visible \? 56 : Space\.sm\)/);
  assert.doesNotMatch(chatListBlock, /bottom:\s*this\.floatingCapsule\.visible/);
  assert.match(chatListBlock, /FloatingStatusCapsule\(\{[\s\S]*?\}\)\s*\.hitTestBehavior\(HitTestMode\.Transparent\)/);

  assert.match(capsuleSource, /Blank\(\)\s*\.hitTestBehavior\(HitTestMode\.None\)/);
  assert.match(capsuleSource, /\.hitTestBehavior\(HitTestMode\.Transparent\)/);
});

test('FloatingStatusCapsule supports offline status and stepDelayedConnectionUi prevents transient reconnect flicker', () => {
  const offline = F.deriveFloatingCapsuleModel(baseInput({ ready: false, connecting: false, offline: true }));
  assert.equal(offline.status.kind, 'connection');
  assert.equal(offline.status.icon, 'offline');
  assert.equal(offline.status.label, '当前离线');

  let state = F.initialDelayedConnectionUiState();
  // First connect becomes ready
  let step = F.stepDelayedConnectionUi(state, { ready: true, connecting: false, offline: false, error: '', nowMs: 1000 });
  state = step.state;
  assert.equal(step.suppressConnecting, false);
  assert.equal(step.showError, false);

  // Brief live drop (< 400ms) suppresses reconnecting UI and delays error display
  step = F.stepDelayedConnectionUi(state, { ready: false, connecting: true, offline: false, error: '连接已断开', nowMs: 2000 });
  state = step.state;
  assert.equal(step.suppressConnecting, true);
  assert.equal(step.showError, false);
  assert.equal(step.nextTickMs, 400);

  // After 450ms, connecting pill appears calmly without error yet
  step = F.stepDelayedConnectionUi(state, { ready: false, connecting: true, offline: false, error: '连接已断开', nowMs: 2450 });
  state = step.state;
  assert.equal(step.suppressConnecting, false);
  assert.equal(step.showError, false);
  assert.equal(step.nextTickMs, 4550);

  // After 5s, error escalates
  step = F.stepDelayedConnectionUi(state, { ready: false, connecting: true, offline: false, error: '连接已断开', nowMs: 7100 });
  state = step.state;
  assert.equal(step.suppressConnecting, false);
  assert.equal(step.showError, true);
  assert.equal(step.nextTickMs, 0);

  // Offline shows immediately without suppression
  step = F.stepDelayedConnectionUi(state, { ready: false, connecting: false, offline: true, error: '', nowMs: 7200 });
  assert.equal(step.suppressConnecting, false);
});

test('resolveSubagentPillSegment hides idle-only completed turns and never shows 0 已完成', () => {
  // Completed turn with only idle subagents (e.g. Antigravity subagentsIdleOnTurnCompletion) hides the pill
  const completedAllIdle = F.deriveThreadTurnSubagents(
    [{ id: 'r1', ordinal: 1, status: 'completed', startedAt: '2026-01-01T00:00:00.000Z' }],
    [
      { id: 's1', runId: 'r1', origin: 'provider_native', driver: 'antigravity', title: 'Backend Protocol & Fence Engineer', status: 'idle', updatedAt: '2026-01-01T00:01:00.000Z' },
      { id: 's2', runId: 'r1', origin: 'provider_native', driver: 'antigravity', title: 'Frontend Online Check-In Engineer', status: 'idle', updatedAt: '2026-01-01T00:01:01.000Z' },
      { id: 's3', runId: 'r1', origin: 'provider_native', driver: 'antigravity', title: 'Backend VisitGuide Orchestration Engineer', status: 'idle', updatedAt: '2026-01-01T00:01:02.000Z' }
    ]
  );
  assert.equal(completedAllIdle.liveCount, 0);
  assert.equal(completedAllIdle.settledCount, 0);
  assert.equal(completedAllIdle.idleCount, 3);
  assert.equal(completedAllIdle.subagents.every(s => s.canStop === false), true);
  assert.equal(F.resolveSubagentPillSegment(completedAllIdle), undefined);

  // Active turn with only idle subagents reports '2 空闲' instead of '0 已完成'
  const activeAllIdle = F.deriveThreadTurnSubagents(
    [{ id: 'r1', ordinal: 1, status: 'running', startedAt: '2026-01-01T00:00:00.000Z' }],
    [
      { id: 's1', runId: 'r1', title: 'Worker 1', status: 'idle', updatedAt: '2026-01-01T00:01:00.000Z' },
      { id: 's2', runId: 'r1', title: 'Worker 2', status: 'idle', updatedAt: '2026-01-01T00:01:01.000Z' }
    ]
  );
  assert.equal(F.resolveSubagentPillSegment(activeAllIdle).label, '2 空闲');

  // Completed turn with mixed completed + idle counts only completed
  const mixedDoneAndIdle = F.deriveThreadTurnSubagents(
    [{ id: 'r1', ordinal: 1, status: 'completed', startedAt: '2026-01-01T00:00:00.000Z' }],
    [
      { id: 's1', runId: 'r1', title: 'Done Worker', status: 'completed', updatedAt: '2026-01-01T00:01:00.000Z' },
      { id: 's2', runId: 'r1', title: 'Idle Worker', status: 'idle', updatedAt: '2026-01-01T00:01:01.000Z' }
    ]
  );
  assert.equal(F.resolveSubagentPillSegment(mixedDoneAndIdle).label, '1 已完成');
});
