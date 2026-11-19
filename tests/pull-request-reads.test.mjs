import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { compile, data, r5Url } from './load-core.mjs';

const source = await readFile(new URL('../entry/src/main/ets/components/PullRequestsPanel.ets', import.meta.url), 'utf8');
const reads = source.slice(source.indexOf('  private alive:'), source.indexOf('  private async generateGuide()'));
const { PanelHarness } = await import(data(compile(`
  import { parseDiff, pullRequestPatch, pullRequestRef } from ${JSON.stringify(r5Url)};
  export class PanelHarness {
    projectId = 'project';
    busy = false; loading = false; rows = []; errors = [];
    filter = 'open'; query = ''; nextCursor = '';
    ${reads}
  }
`)));

const row = number => ({ projectId: 'project', repository: 'org/repo', number });
const diff = path => ({
  patch: 'diff --git a/' + path + ' b/' + path + '\n--- a/' + path + '\n+++ b/' + path + '\n@@ -1 +1 @@\n-old\n+new',
  truncated: false, nextCursor: null
});
const wait = () => new Promise(setImmediate);
function harness() {
  const panel = new PanelHarness();
  panel.alive = true;
  let generation = 1;
  const calls = [];
  const deferred = [];
  const connection = {
    generationValue: () => generation,
    listPullRequests: async () => ({ rows: [], errors: [], nextCursor: '' }),
    pullRequestDetail: async ref => ({ ...row(ref.number), title: 'PR ' + ref.number, body: '', activity: {} }),
    pullRequestActivity: async () => ({}),
    pullRequestDiff: ref => {
      calls.push(ref.number);
      return new Promise(resolve => deferred.push(resolve));
    },
    pullRequestChecks: async () => undefined,
    pullRequestReviewGuide: async () => undefined
  };
  panel.connection = connection;
  return { panel, connection, calls, deferred, swapGeneration: () => { generation++; } };
}

test('A→B→A ignores the first A diff and its completion while the newest A still loads', async () => {
  const { panel, calls, deferred } = harness();
  const firstA = panel.open(row(1)); await wait();
  panel.closeDetail();
  const b = panel.open(row(2)); await wait();
  panel.closeDetail();
  const lastA = panel.open(row(1)); await wait();
  assert.deepEqual(calls, [1, 2, 1]);
  deferred[0](diff('stale-a')); await firstA;
  deferred[1](diff('stale-b')); await b;
  assert.equal(panel.loading, true);
  assert.equal(panel.busy, true);
  assert.deepEqual(panel.patchFiles, []);
  deferred[2](diff('current-a')); await lastA;
  assert.deepEqual(panel.patchFiles.map(file => file.path), ['current-a']);
  assert.equal(panel.loading, false);
});

test('leaving and replacing the connection generation ignore late diffs', async () => {
  const { panel, connection, deferred, swapGeneration } = harness();
  let checks = 0;
  connection.pullRequestChecks = async () => { checks++; };
  const closing = panel.open(row(1)); await wait();
  panel.aboutToDisappear();
  deferred[0](diff('left')); await closing;
  assert.deepEqual(panel.patchFiles, []);
  assert.equal(checks, 0);

  panel.alive = true;
  const old = panel.open(row(2)); await wait();
  swapGeneration();
  deferred[1](diff('old-connection')); await old;
  assert.deepEqual(panel.patchFiles, []);
  assert.equal(checks, 0);
  assert.equal(panel.busy, false);
});

test('a late or mismatched detail never starts a diff for another PR', async () => {
  const { panel, connection, calls } = harness();
  let finish;
  connection.pullRequestDetail = () => new Promise(resolve => { finish = resolve; });
  const stale = panel.open(row(1)); await wait();
  panel.closeDetail();
  finish({ ...row(1), activity: {} }); await stale;
  assert.equal(panel.detail, undefined);
  connection.pullRequestDetail = async () => ({ ...row(3), activity: {} });
  await panel.open(row(2));
  assert.match(panel.error, /不匹配/);
  assert.deepEqual(calls, []);
});

test('a failed diff is distinguishable from an empty patch and clears on a successful read', async () => {
  const { panel, connection } = harness();
  connection.pullRequestDiff = async () => { throw Error('provider error'); };
  await panel.open(row(1));
  assert.equal(panel.selected.number, 1);
  assert.match(panel.diffError, /读取失败/);
  connection.pullRequestDiff = async () => diff('file.txt');
  await panel.open(row(1));
  assert.equal(panel.diffError, '');
  assert.deepEqual(panel.patchFiles.map(file => file.path), ['file.txt']);
});

test('pagination never pairs an old cursor with newly typed PR search text', async () => {
  const { panel, connection } = harness();
  const calls = [];
  connection.listPullRequests = async (filter, query, cursor) => {
    calls.push([query, cursor]);
    return { rows: [], errors: [], nextCursor: 'page-for-' + query };
  };
  panel.query = 'first';
  await panel.loadList();
  panel.query = 'second';
  await panel.loadMore();
  assert.deepEqual(calls, [['first', '']]);
  await panel.loadList();
  await panel.loadMore();
  assert.deepEqual(calls.slice(1), [['second', ''], ['second', 'page-for-second']]);
});
