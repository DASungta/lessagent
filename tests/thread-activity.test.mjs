import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { compile, data } from './load-core.mjs';

const wireUrl = new URL('../entry/src/main/ets/protocol/Wire.ts', import.meta.url).href;
const source = (await readFile(new URL('../entry/src/main/ets/protocol/ThreadItems.ts', import.meta.url), 'utf8'))
  .replace("'./Wire'", JSON.stringify(wireUrl));
const {
  activityLines, activitySummary, isPlainUserText,
  isHiddenWorkItem, isProminentWorkItem, summarizeWork,
  formatWorkDuration, deriveCheckpointBadges, groupWorkByMessage,
  parseDiffPreviewLines, resolveExpandedActivityBody
} = await import(data(compile(source)));

test('command_execution summarizes first command line and exit tone', () => {
  const [ok, fail, running, empty] = activityLines([
    { id: '1', type: 'command_execution', status: 'completed', exitCode: 0, input: 'rg   "复制全部" entry/src', output: 'hit' },
    { id: '2', type: 'command_execution', status: 'failed', exitCode: 2, input: 'npm test', output: 'err' },
    { id: '3', type: 'command_execution', status: 'inProgress', input: 'sleep 1' },
    { id: '4', type: 'command_execution', status: 'completed' },
  ]).map(activitySummary);

  assert.deepEqual(ok, { icon: 'cmd', title: 'rg "复制全部" entry/src', badge: 'exit 0', badgeTone: 'success', additions: '', deletions: '' });
  assert.deepEqual(fail, { icon: 'cmd', title: 'npm test', badge: 'exit 2', badgeTone: 'danger', additions: '', deletions: '' });
  assert.deepEqual(running, { icon: 'cmd', title: 'sleep 1', badge: '运行中', badgeTone: 'neutral', additions: '', deletions: '' });
  assert.deepEqual(empty, { icon: 'cmd', title: '命令', badge: '完成', badgeTone: 'success', additions: '', deletions: '' });
});

test('file_change splits file title and additions/deletions', () => {
  const [changed] = activityLines([
    { id: 'f1', type: 'file_change', fileName: 'TerminalPanel.ets', additions: 18, deletions: 9 }
  ]).map(activitySummary);
  assert.deepEqual(changed, { icon: 'file', title: 'TerminalPanel.ets', badge: '', badgeTone: 'neutral', additions: '+18', deletions: '−9' });
});

test('file_search, reasoning, checkpoint and error summarize cleanly', () => {
  const [search, reasoning, checkpoint, err] = activityLines([
    { id: 's1', type: 'file_search', status: 'completed', pattern: '*.ets', results: [] },
    { id: 'r1', type: 'reasoning', status: 'inProgress', text: 'thinking...' },
    { id: 'c1', type: 'checkpoint', files: [{ path: 'a.ts' }] },
    { id: 'e1', type: 'error', failure: { class: 'network', message: 'timeout' } },
  ]).map(activitySummary);

  assert.deepEqual(search, { icon: 'file', title: '搜索 *.ets', badge: '完成', badgeTone: 'success', additions: '', deletions: '' });
  assert.deepEqual(reasoning, { icon: 'info', title: '思考过程', badge: '思考中', badgeTone: 'neutral', additions: '', deletions: '' });
  assert.deepEqual(checkpoint, { icon: 'info', title: '检查点', badge: '', badgeTone: 'neutral', additions: '', deletions: '' });
  assert.equal(err.badge, '失败');
  assert.equal(err.badgeTone, 'danger');
});

test('isPlainUserText detects plain vs markdown messages', () => {
  assert.equal(isPlainUserText('1'), true);
  assert.equal(isPlainUserText('把终端选字的按钮挪到输出区域下面'), true);
  assert.equal(isPlainUserText('第一行\n第二行'), true);
  assert.equal(isPlainUserText('看看 `Index.ets`'), false);
  assert.equal(isPlainUserText('- item 1'), false);
  assert.equal(isPlainUserText('# Title'), false);
  assert.equal(isPlainUserText('**bold**'), false);
  assert.equal(isPlainUserText('https://example.com'), false);
});

test('isHiddenWorkItem filters pure noise while keeping failures and prominent items', () => {
  assert.equal(isHiddenWorkItem({ id: 'cp', type: 'checkpoint', files: [] }), true);
  assert.equal(isHiddenWorkItem({ id: 'todo', type: 'todo_list', steps: [] }), true);
  assert.equal(isHiddenWorkItem({ id: 'req', type: 'run_interrupt_request' }), true);
  assert.equal(isHiddenWorkItem({ id: 'prep-ok', type: 'command_execution', status: 'completed', exitCode: 0, input: 'Preparing workspace' }), true);
  assert.equal(isHiddenWorkItem({ id: 'prep-defer', type: 'command_execution', status: 'completed', exitCode: 0, input: 'Preparing workspace', deferredWork: true }), false);
  assert.equal(isHiddenWorkItem({ id: 'prep-fail', type: 'command_execution', status: 'failed', exitCode: 1, input: 'Preparing workspace' }), false);
  assert.equal(isHiddenWorkItem({ id: 'prep-cancel-err', type: 'error', status: 'cancelled', failure: { code: 'workspace_preparation_failed' } }), true);

  assert.equal(isProminentWorkItem({ id: 'e', type: 'error', status: 'failed', failure: { message: 'boom' } }), true);
  assert.equal(isProminentWorkItem({ id: 'int', type: 'run_interrupt_result', message: 'stopped' }), true);
  assert.equal(isProminentWorkItem({ id: 'c', type: 'command_execution', status: 'completed', input: 'ls' }), false);
});

test('summarizeWork and formatWorkDuration format counts, failures, and elapsed time', () => {
  assert.equal(formatWorkDuration(0), '');
  assert.equal(formatWorkDuration(400), '<1 秒');
  assert.equal(formatWorkDuration(23000), '23 秒');
  assert.equal(formatWorkDuration(72000), '1 分 12 秒');
  assert.equal(formatWorkDuration(3720000), '1 小时 2 分');

  const lines = activityLines([
    { id: 'c1', type: 'command_execution', status: 'completed', exitCode: 0, input: 'rg foo' },
    { id: 'f1', type: 'file_change', fileName: 'a.ts', additions: 12, deletions: 3 },
    { id: 'c2', type: 'command_execution', status: 'failed', exitCode: 1, input: 'npm test' },
    { id: 's1', type: 'file_search', status: 'completed', pattern: '*.ts' },
  ]);
  const s = summarizeWork(lines);
  assert.equal(s.totalSteps, 4);
  assert.equal(s.commands, 2);
  assert.equal(s.files, 1);
  assert.equal(s.searches, 1);
  assert.equal(s.failures, 1);
  assert.equal(s.additions, 12);
  assert.equal(s.deletions, 3);
  assert.equal(s.label, '运行 2 条命令，修改 1 个文件，搜索 1 次');
  assert.equal(s.failureLabel, '1 失败');
});

test('deriveCheckpointBadges ignores empty checkpoints and honors filesTotal', () => {
  const messages = [{ id: 'a1', role: 'assistant', text: 'ok', streaming: false, runId: 'r1' }];
  const derived = deriveCheckpointBadges(
    [
      { id: 'cp0', runId: 'r0', status: 'ready', files: [] },
      { id: 'cp-miss', runId: 'r1', status: 'missing', files: [{ path: 'x.ts', additions: 1, deletions: 0 }] },
      {
        id: 'cp1',
        runId: 'r1',
        status: 'ready',
        files: [{ path: 'auth/session.ts', additions: 12, deletions: 3 }],
        filesTotal: { count: 2, additions: 24, deletions: 6 }
      }
    ],
    [{ id: 'cp-item-empty', type: 'checkpoint', runId: 'r0', files: [] }],
    messages
  );
  assert.equal(derived.byRun['r0'], undefined);
  assert.equal(derived.byAssistantMessage['a1']?.fileCount, 2);
  assert.equal(derived.byAssistantMessage['a1']?.diffLabel, '+24 −6');
  assert.equal(derived.byAssistantMessage['a1']?.label, '2 文件');
});

test('groupWorkByMessage places work chronologically, hides pure Q&A noise, and handles interrupted tail', () => {
  const clean = groupWorkByMessage(
    [
      { id: 'tu1', type: 'user_message', messageId: 'u1', runId: 'r1', text: 'hi' },
      { id: 'tp1', type: 'command_execution', runId: 'r1', status: 'completed', exitCode: 0, input: 'Preparing workspace' },
      { id: 'ta1', type: 'assistant_message', messageId: 'a1', runId: 'r1', text: 'hello' },
      { id: 'tc1', type: 'checkpoint', runId: 'r1', status: 'completed', files: [] }
    ],
    [{ id: 'r1', status: 'completed', startedAt: '2026-11-18T08:55:39Z', completedAt: '2026-11-18T08:55:50Z' }],
    [{ id: 'cp1', runId: 'r1', status: 'ready', files: [] }],
    [
      { id: 'u1', role: 'user', text: 'hi', streaming: false, runId: 'r1' },
      { id: 'a1', role: 'assistant', text: 'hello', streaming: false, runId: 'r1' }
    ]
  );
  assert.equal(clean.hasVisible, false);
  assert.equal(Object.keys(clean.before).length, 0);
  assert.equal(clean.tail, undefined);

  const rich = groupWorkByMessage(
    [
      { id: 'tu1', type: 'user_message', messageId: 'u1', runId: 'r1', text: 'fix' },
      { id: 'tp1', type: 'command_execution', runId: 'r1', status: 'completed', exitCode: 0, input: 'Preparing workspace' },
      { id: 'w1', type: 'file_search', runId: 'r1', status: 'completed', pattern: 'session' },
      { id: 'w2', type: 'command_execution', runId: 'r1', status: 'failed', exitCode: 1, input: 'npm test' },
      { id: 'ta1', type: 'assistant_message', messageId: 'a1', runId: 'r1', text: 'fixed' },
      { id: 'tu2', type: 'user_message', messageId: 'u2', runId: 'r2', text: 'refactor' },
      { id: 'w3', type: 'file_search', runId: 'r2', status: 'completed', pattern: '*.ts' },
      { id: 'e2', type: 'error', runId: 'r2', status: 'failed', failure: { class: 'provider', message: 'stopped' } }
    ],
    [
      { id: 'r1', status: 'completed', startedAt: '2026-11-18T08:00:00Z', completedAt: '2026-11-18T08:01:12Z' },
      { id: 'r2', status: 'interrupted', startedAt: '2026-11-18T08:02:00Z', completedAt: '2026-11-18T08:02:23Z' }
    ],
    [
      { id: 'cp1', runId: 'r1', status: 'ready', files: [{ path: 'auth/session.ts', additions: 12, deletions: 3 }] }
    ],
    [
      { id: 'u1', role: 'user', text: 'fix', streaming: false, runId: 'r1' },
      { id: 'a1', role: 'assistant', text: 'fixed', streaming: false, runId: 'r1' },
      { id: 'u2', role: 'user', text: 'refactor', streaming: false, runId: 'r2' }
    ]
  );
  assert.equal(rich.hasVisible, true);
  assert.equal(rich.before['a1'].items.length, 2);
  assert.equal(rich.before['a1'].runMeta.headerLabel, '已工作 1 分 12 秒 · 2 步');
  assert.equal(rich.before['a1'].checkpoint.diffLabel, '+12 −3');
  assert.equal(rich.before['a1'].defaultExpanded, false);
  assert.equal(rich.tail.runMeta.headerLabel, '你在 23 秒后停止了');
  assert.equal(rich.tail.prominent.length, 1);
  assert.equal(rich.tail.defaultExpanded, true);
});

test('checkpoint turn item emitted after assistant_message does not duplicate into tail', () => {
  const res = groupWorkByMessage(
    [
      { id: 'tu1', type: 'user_message', messageId: 'u1', runId: 'r1', text: 'q1' },
      { id: 'ta1', type: 'assistant_message', messageId: 'a1', runId: 'r1', text: 'ans1' },
      { id: 'tc1', type: 'checkpoint', runId: 'r1', status: 'completed', files: [{ path: 'MATH.md', additions: 3, deletions: 0 }] },
      { id: 'tu2', type: 'user_message', messageId: 'u2', runId: 'r2', text: 'q2' },
      { id: 'ta2', type: 'assistant_message', messageId: 'a2', runId: 'r2', text: 'ans2' },
      { id: 'tc2', type: 'checkpoint', runId: 'r2', status: 'completed', files: [] }
    ],
    [
      { id: 'r1', status: 'completed', startedAt: '2026-11-18T15:25:06Z', completedAt: '2026-11-18T15:25:12Z' },
      { id: 'r2', status: 'completed', startedAt: '2026-11-18T15:29:33Z', completedAt: '2026-11-18T15:29:39Z' }
    ],
    [
      { id: 'cp1', runId: 'r1', status: 'ready', files: [{ path: 'MATH.md', kind: 'modified', additions: 3, deletions: 0 }] },
      { id: 'cp2', runId: 'r2', status: 'ready', files: [] }
    ],
    [
      { id: 'u1', role: 'user', text: 'q1', streaming: false, runId: 'r1' },
      { id: 'a1', role: 'assistant', text: 'ans1', streaming: false, runId: 'r1' },
      { id: 'u2', role: 'user', text: 'q2', streaming: false, runId: 'r2' },
      { id: 'a2', role: 'assistant', text: 'ans2', streaming: false, runId: 'r2' }
    ]
  );
  assert.equal(Object.keys(res.before).length, 1);
  assert.equal(res.before['a1'].checkpoint.diffLabel, '+3');
  assert.equal(res.tail, undefined);
});

test('parseDiffPreviewLines classifies add, del, hunk and file headers', () => {
  assert.deepEqual(
    parseDiffPreviewLines('--- a.ts\n+++ a.ts\n@@ -1,2 +1,2 @@\n-old\n+new\n ctx'),
    [
      { text: '--- a.ts', tone: 'plain' },
      { text: '+++ a.ts', tone: 'plain' },
      { text: '@@ -1,2 +1,2 @@', tone: 'hunk' },
      { text: '-old', tone: 'del' },
      { text: '+new', tone: 'add' },
      { text: ' ctx', tone: 'plain' }
    ]
  );
});

test('groupWorkByMessage places post-assistant failure into afterAssistant and gives unique groupIds per message', async () => {
  const { threadItemsUrl } = await import('./load-core.mjs');
  const { activityLines, activitySummary } = await import(threadItemsUrl);

  const res = groupWorkByMessage(
    [
      { id: 'u1', type: 'user_message', role: 'user', text: 'go', runId: 'r1' },
      { id: 't1', type: 'tool_call', title: 'Read foo.ts', status: 'completed', runId: 'r1' },
      { id: 'a1a', type: 'assistant_message', role: 'assistant', text: 'part 1', runId: 'r1' },
      { id: 't2', type: 'tool_call', title: 'Read bar.ts', status: 'completed', runId: 'r1' },
      { id: 'a1b', type: 'assistant_message', role: 'assistant', text: 'part 2', runId: 'r1' },
      { id: 'err-r1', type: 'error', status: 'failed', failure: { message: 'provider_error 4m36s timeout' }, runId: 'r1' },
      { id: 'u2', type: 'user_message', role: 'user', text: 'next', runId: 'r2' },
      { id: 'a2', type: 'assistant_message', role: 'assistant', text: 'done', runId: 'r2' }
    ],
    [],
    [],
    [
      { id: 'u1', role: 'user', text: 'go', streaming: false, runId: 'r1' },
      { id: 'a1a', role: 'assistant', text: 'part 1', streaming: false, runId: 'r1' },
      { id: 'a1b', role: 'assistant', text: 'part 2', streaming: false, runId: 'r1' },
      { id: 'u2', role: 'user', text: 'next', streaming: false, runId: 'r2' },
      { id: 'a2', role: 'assistant', text: 'done', streaming: false, runId: 'r2' }
    ]
  );

  assert.equal(res.tail, undefined);
  assert.ok(res.before['a1a']);
  assert.ok(res.before['a1b']);
  assert.notEqual(res.before['a1a'].groupId, res.before['a1b'].groupId);
  assert.ok(res.afterAssistant?.['a1b']);
  assert.equal(res.afterAssistant['a1b'].prominent.some((a) => a.id === 'err-r1'), true);
  assert.equal(res.before['a2'], undefined);

  const [summary] = activityLines([
    {
      id: 'dt1',
      type: 'dynamic_tool',
      toolName: 'Read',
      title: 'Read src/App.ets',
      status: 'completed',
      runId: 'r1'
    }
  ]).map(activitySummary);
  assert.equal(summary.title.includes('dynamic_tool'), false);
  assert.equal(summary.title.includes('completed'), false);
});

test('resolveExpandedActivityBody tracks live reasoning deltas and fetched historical snapshots', () => {
  assert.equal(
    resolveExpandedActivityBody(
      { itemId: 'r1', kind: 'reasoning', label: '思考过程 · inProgress', text: 'The new user request indicates a desire for logos and better wrapping.' },
      'The new user request indicates a desire for'
    ),
    'The new user request indicates a desire for logos and better wrapping.'
  );
  assert.equal(
    resolveExpandedActivityBody(
      { itemId: 'r2', kind: 'reasoning', label: '思考过程 · completed', text: '' },
      'Loaded full reasoning text from turnItem RPC.'
    ),
    'Loaded full reasoning text from turnItem RPC.'
  );
  assert.equal(
    resolveExpandedActivityBody(
      { itemId: 'c1', kind: 'command_execution', label: '命令 · completed · exit 0', text: 'ls\npartial' },
      'ls\nfull output'
    ),
    'ls\nfull output'
  );
});
