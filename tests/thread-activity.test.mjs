import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { compile, data } from './load-core.mjs';

const wireUrl = new URL('../entry/src/main/ets/protocol/Wire.ts', import.meta.url).href;
const source = (await readFile(new URL('../entry/src/main/ets/protocol/ThreadItems.ts', import.meta.url), 'utf8'))
  .replace("'./Wire'", JSON.stringify(wireUrl));
const { activityLines, activitySummary, isPlainUserText } = await import(data(compile(source)));

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
