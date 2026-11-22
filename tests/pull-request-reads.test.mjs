import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { compile, data, r5Url } from './load-core.mjs';

const source = await readFile(new URL('../entry/src/main/ets/components/PullRequestsPanel.ets', import.meta.url), 'utf8');
const reads = source.slice(source.indexOf('  private alive:'), source.indexOf('  private async generateGuide()'));
const { PanelHarness } = await import(data(compile(`
  import { firstPullRequestCursor, hasPullRequestCursors, mergePullRequestRows, normalizePullRequestCursors,
    orderParsedDiffFilesForReview, parseDiff, pullRequestPatch, pullRequestProjectChoices, pullRequestRef,
    tagPullRequestRows } from ${JSON.stringify(r5Url)};
  export class PanelHarness {
    projectId = 'project';
    activeLocalId = '';
    environments = [];
    projects = [];
    connectionFor = () => undefined;
    selectedEnvLocalId = '';
    selectedProjectKey = '';
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

test('home pull requests aggregate environments, filter by projectId, forward full cursor maps, and route detail to row client', async () => {
  const panel = new PanelHarness();
  panel.alive = true;
  panel.projectId = '';
  panel.activeLocalId = 'mac';
  const macCalls = [];
  const ca02Calls = [];
  const detailClients = [];
  const makeClient = (name, calls, pages) => ({
    ready: true,
    generationValue: () => 1,
    listPullRequests: async (filter, query, cursor, projectId, cursors) => {
      calls.push({ filter, query, cursor, projectId, cursors });
      return pages.shift() || { rows: [], errors: [], nextCursor: '', nextCursors: {} };
    },
    pullRequestDetail: async ref => {
      detailClients.push([name, ref.projectId, ref.number]);
      return { projectId: ref.projectId, repository: ref.repository, number: ref.number, title: 'T', body: '', activity: {} };
    },
    pullRequestActivity: async () => ({ comments: [], threads: [], commits: [] }),
    pullRequestDiff: async () => diff('a.ts'),
    pullRequestChecks: async () => undefined,
    pullRequestReviewGuide: async () => undefined
  });
  const prRow = (projectId, repository, number, updatedAt) => ({
    provider: 'gitlab', host: 'gitlab.example', projectId, projectTitle: 'yxbuddy',
    repository, number, title: 'PR #' + number, url: 'u', author: 'dev', headBranch: 'h', baseBranch: 'main',
    state: 'open', draft: false, additions: 1, deletions: 0, updatedAt, reviewDecision: '', checksState: '',
    labels: [], stackPosition: 0, stackSize: 0
  });
  const macClient = makeClient('mac', macCalls, [
    { rows: [prRow('p-yx-mac', 'base/yxbuddy', 39, '2026-11-22T02:00:00Z')], errors: [], nextCursor: 'cur-mac-1',
      nextCursors: { 'gitlab.example:base/yxbuddy': 'cur-mac-1' } },
    { rows: [prRow('p-yx-mac', 'base/yxbuddy', 38, '2026-11-21T02:00:00Z')], errors: [], nextCursor: '', nextCursors: {} },
    { rows: [], errors: [], nextCursor: '', nextCursors: {} }
  ]);
  const ca02Client = makeClient('ca02', ca02Calls, [
    { rows: [prRow('p-yx-ca02', 'base/yxbuddy', 39, '2026-11-22T02:00:00Z'), prRow('p-only-ca02', 'team/other', 7, '2026-11-22T04:00:00Z')],
      errors: [], nextCursor: '', nextCursors: {} }
  ]);
  panel.connection = macClient;
  panel.connectionFor = id => (id === 'mac' ? macClient : id === 'ca02' ? ca02Client : undefined);
  panel.environments = [
    { localId: 'mac', environmentId: 'env-mac', label: 'iMac', enabled: true },
    { localId: 'ca02', environmentId: 'env-ca02', label: 'ca02', enabled: true }
  ];
  panel.projects = [
    { localId: 'mac', environmentId: 'env-mac', environmentLabel: 'iMac', id: 'p-harm', label: 't3code-harmony',
      workspaceRoot: '/harm', archivedAt: '', pinnedAt: '', isScratch: false,
      repository: { canonicalKey: 'github.com/dasungta/t3code-harmony', displayName: 'DASungta/t3code-harmony' } },
    { localId: 'ca02', environmentId: 'env-ca02', environmentLabel: 'ca02', id: 'p-only-ca02', label: 'other',
      workspaceRoot: '/other', archivedAt: '', pinnedAt: '', isScratch: false,
      repository: { canonicalKey: 'gitlab.example/team/other', displayName: 'team/other' } }
  ];

  await panel.loadList();
  assert.deepEqual(panel.rows.map(r => [r.number, r.localId]), [[7, 'ca02'], [39, 'mac']]);
  assert.equal(panel.nextCursor, 'cur-mac-1');

  await panel.loadMore();
  assert.deepEqual(macCalls[1].cursors, { 'gitlab.example:base/yxbuddy': 'cur-mac-1' });
  assert.equal(ca02Calls.length, 1);
  assert.deepEqual(panel.rows.map(r => r.number), [7, 39, 38]);

  await panel.open(panel.rows[0]);
  assert.deepEqual(detailClients, [['ca02', 'p-only-ca02', 7]]);
  panel.selected = undefined;
  panel.detailConnection = undefined;

  panel.selectedProjectKey = 'mac:p-harm';
  await panel.loadList();
  assert.equal(macCalls[2].projectId, 'p-harm');
  assert.equal(ca02Calls.length, 1);
  assert.deepEqual(panel.rows, []);
});
