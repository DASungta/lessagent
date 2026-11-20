import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { compile, data } from './load-core.mjs';
import { projectsUrl } from './load-projects.mjs';
const P = await import(projectsUrl);

test('clone destination browses its existing base until edited and ignores a stale browse failure', async () => {
  const source = await readFile(new URL('../entry/src/main/ets/components/AddProjectPanel.ets', import.meta.url), 'utf8');
  const code = (source.split('  @Builder')[0] + '}')
    .replace(/^import .*? from '\.\.\/services\/Workspace';\n/m, '')
    .replace(/^import\s+[^\n]*?from\s+['"](?:\.\/ui\/|\.\.\/common\/Theme)[^'"]*['"];\n/gm, '')
    .replace("'../protocol/Projects'", JSON.stringify(projectsUrl))
    .replace(/@(?:Prop|State)\s+|@Watch\([^)]*\)\s*/g, '')
    .replace('@Component\nexport struct', 'export class');
  const { AddProjectPanel } = await import(data(compile(code)));
  const panel = new AddProjectPanel();
  const calls = [];
  let rejectPrevious;
  panel.environments = [{
    environmentId: 'test-environment', ready: true, baseDirectory: '/work', ghqCloneLayout: true,
    client: {
      canReadFiles: () => true,
      async browseFilesystem(path) {
        calls.push(path);
        if (path === '/work/previous') return new Promise((_resolve, reject) => { rejectPrevious = reject; });
        if (path === '/work/') return { entries: [{ name: 'existing', fullPath: '/work/existing' }], parentPath: '/' };
        if (path === '/work/manual') return { entries: [{ name: 'checkout', fullPath: '/work/manual/checkout' }], parentPath: '/work' };
        throw new Error('Destination has not been created');
      },
    },
  }];
  panel.aboutToAppear();
  panel.startSource('url');
  panel.repositoryInput = 'https://github.com/example/repo';
  await panel.continueRepository();
  assert.equal(panel.step, 'destination');
  assert.equal(panel.pathInput, '/work/github.com/example/repo');
  assert.deepEqual(calls, ['/work/']);
  assert.deepEqual(panel.browse.map(entry => entry.fullPath), ['/work/existing']);
  panel.pathInput = '/work/previous';
  const previousBrowse = panel.loadBrowse();
  panel.pathInput = '/work/manual';
  await panel.loadBrowse();
  rejectPrevious(new Error('Previous directory does not exist'));
  await previousBrowse;
  assert.deepEqual(calls, ['/work/', '/work/previous', '/work/manual']);
  assert.deepEqual(panel.browse.map(entry => entry.fullPath), ['/work/manual/checkout']);
  assert.equal(panel.pathInput, '/work/manual');
  assert.equal(panel.browseParent, '/work');
  assert.equal(panel.error, '');
});

const repo = (key, root = '/work/repo', name = 'repo') => ({
  canonicalKey: key, displayName: name, name, rootPath: root,
  locator: { source: 'git-remote', remoteName: 'origin', remoteUrl: 'https://example.test/repo.git' }
});
const project = (id, title, root, extra = {}) => ({
  id, title, workspaceRoot: root, createdAt: '2026-01-01T00:00:00.000Z',
  updatedAt: '2026-01-02T00:00:00.000Z', scripts: [], ...extra
});
const thread = (id, projectId, title, extra = {}) => ({
  id, projectId, title, createdAt: '2026-01-01T00:00:00.000Z',
  updatedAt: '2026-01-02T00:00:00.000Z', latestUserMessageAt: '2026-01-02T00:00:00.000Z',
  status: 'idle', ...extra
});
const scopedProject = (localId, value, environmentLabel = localId) =>
  ({ ...P.projectView(value), localId, environmentId: 'env-' + localId, environmentLabel, isScratch: false });
const scopedThread = (localId, value, projectLabel = 'Repo', environmentLabel = localId) =>
  ({ ...P.threadView(value), localId, environmentId: 'env-' + localId, environmentLabel, projectLabel });
const caps = (extra = {}) => ({
  settlement: true, snooze: true, pinning: true, pinReorder: true,
  activeReorder: true, autoSettleOptOut: true, titleRegeneration: true, ...extra
});

test('projects group by repository across environments, keep monorepo paths apart when asked, and archive only when every checkout is archived', () => {
  const projects = [
    scopedProject('a', project('p1', 'Repo', '/work/repo', { repositoryIdentity: repo('github:org/repo') })),
    scopedProject('b', project('p1', 'Repo', '/work/repo', { repositoryIdentity: repo('github:org/repo') })),
    scopedProject('a', project('p2', 'API', '/work/repo/api', { repositoryIdentity: repo('github:org/repo') })),
    scopedProject('a', project('p3', 'Plain', '/work/plain'))
  ];
  const grouped = P.buildProjectGroups(projects, 'repository');
  const repoGroup = grouped.find(group => group.key === 'github:org/repo');
  assert.equal(repoGroup.projects.length, 3);
  assert.deepEqual(repoGroup.projectRefs.map(ref => ref.localId), ['a', 'b', 'a']);
  const byPath = P.buildProjectGroups(projects, 'repository_path');
  assert.equal(byPath.filter(group => group.key.startsWith('github:org/repo')).length, 2);
  const separate = P.buildProjectGroups(projects, 'separate');
  assert.equal(separate.length, 4);
  const halfArchived = P.buildProjectGroups([
    scopedProject('a', project('p1', 'Repo', '/work/repo', { repositoryIdentity: repo('github:org/repo'), archivedAt: '2026-01-03T00:00:00.000Z' })),
    scopedProject('b', project('p1', 'Repo', '/work/repo', { repositoryIdentity: repo('github:org/repo') }))
  ], 'repository')[0];
  assert.equal(halfArchived.archived, false);
  assert.equal(P.pickableProjectGroups([halfArchived]).length, 1);
});

test('scratch projects group as No project and are excluded from the project picker', () => {
  const scratch = { ...scopedProject('a', project('s1', 'No project', '/work/scratch')), isScratch: true };
  const normal = scopedProject('a', project('p1', 'Repo', '/work/repo'));
  const groups = P.buildProjectGroups([scratch, normal], 'repository');
  assert.equal(groups.find(group => group.key === '\u0000no-project').label, 'No project');
  assert.deepEqual(P.pickableProjectGroups(groups).map(group => group.label), ['Repo']);
});

test('active and pinned order keys decide list order; settled and snoozed use their own clocks', () => {
  const threads = [
    scopedThread('a', thread('t1', 'p', 'One', { activeOrderKey: 'f' })),
    scopedThread('a', thread('t2', 'p', 'Two', { activeOrderKey: 'b' })),
    scopedThread('a', thread('t3', 'p', 'Three', { activeOrderKey: 'd' })),
    scopedThread('a', thread('p1', 'p', 'Pinned B', { pinnedAt: '2026-01-01T00:00:00.000Z', pinOrderKey: 'd' })),
    scopedThread('a', thread('p2', 'p', 'Pinned A', { pinnedAt: '2026-01-01T00:00:00.000Z', pinOrderKey: 'b' })),
    scopedThread('a', thread('s1', 'p', 'Settled', { settledOverride: 'settled', settledAt: '2026-01-03T00:00:00.000Z' }))
  ];
  assert.deepEqual(P.sortActive(threads.slice(0, 3)).map(t => t.id), ['t2', 't3', 't1']);
  assert.deepEqual(P.sortPinned(threads.slice(3, 5)).map(t => t.id), ['p2', 'p1']);
  assert.equal(P.sortSettled([threads[5]])[0].id, 's1');
  assert.ok(P.pinOrderKeyBetween('b', 'c') > 'b');
  assert.ok(P.pinOrderKeyBetween('b', 'c') < 'c');
  assert.equal(P.topOfPinnedRun(threads.slice(3, 5)) < 'b', true);
  const payload = P.threadMovePayload([threads[1], threads[2], threads[0]], threads[2], true, 'active');
  assert.ok(payload.orderKey < 'b');
});

test('thread shelves isolate environments and project refs, and search hits can surface a non-title match', () => {
  const now = Date.parse('2026-01-05T00:00:00.000Z');
  const a = scopedThread('a', thread('same', 'p', 'A title'));
  const b = scopedThread('b', thread('same', 'p', 'B title'));
  const snoozed = scopedThread('a', thread('sleep', 'p', 'Sleep', { snoozedUntil: '2026-01-06T00:00:00.000Z', snoozedAt: '2026-01-04T00:00:00.000Z' }));
  const settled = scopedThread('a', thread('done', 'p', 'Done', { settledOverride: 'settled', settledAt: '2026-01-03T00:00:00.000Z' }));
  const working = scopedThread('a', thread('run', 'p', 'Run', { status: 'running' }));
  const shelves = P.buildThreadShelves({
    threads: [a, b, snoozed, settled, working], environmentId: 'a', projectRefs: ['a\u0000p'],
    query: '', searchHits: {}, nowMs: now, capabilities: { a: caps(), b: caps() }, sortOrder: 'updated_at', selectedKey: ''
  });
  assert.equal(shelves.active.length, 1);
  assert.equal(shelves.active[0].id, 'same');
  assert.equal(shelves.snoozed[0].id, 'sleep');
  assert.equal(shelves.settled[0].id, 'done');
  assert.equal(shelves.working[0].id, 'run');
  const searched = P.buildThreadShelves({
    threads: [a, b], environmentId: 'b', projectRefs: [], query: 'body text',
    searchHits: { 'b:same': 'body text' }, nowMs: now,
    capabilities: { a: caps(), b: caps() }, sortOrder: 'updated_at', selectedKey: ''
  });
  assert.equal(P.flattenSearchResults(searched, 'body text')[0].localId, 'b');
});

test('search ranking puts title matches before project and content-only matches', () => {
  const now = Date.now();
  const exact = scopedThread('a', thread('exact', 'p', 'Deploy'));
  const projectMatch = scopedThread('a', thread('project', 'p', 'Other', {}), 'Deploy project');
  const content = scopedThread('a', thread('content', 'p', 'Different', {}), 'Other');
  const result = P.buildThreadShelves({
    threads: [content, projectMatch, exact], environmentId: '', projectRefs: [], query: 'deploy',
    searchHits: { 'a:content': 'deploy output' }, nowMs: now,
    capabilities: { a: caps() }, sortOrder: 'updated_at', selectedKey: ''
  });
  assert.deepEqual(result.matches.map(thread => thread.id), ['exact', 'project', 'content']);
});

test('snooze presets are local-time based, deduplicated and reject expired custom times', () => {
  const now = new Date('2026-01-05T09:00:00+08:00');
  const presets = P.resolveSnoozePresets(now, [
    { kind: 'after', minutes: 60, day: '', time: '' },
    { kind: 'after', minutes: 60, day: '', time: '' },
    { kind: 'at', minutes: 0, day: 'today', time: '08:00' },
    { kind: 'at', minutes: 0, day: 'tomorrow', time: '09:00' }
  ]);
  assert.equal(presets.length, 2);
  assert.equal(new Date(presets[0].snoozedUntil).getHours(), 10);
  assert.equal(new Date(presets[1].snoozedUntil).getDate(), 6);
  assert.equal(P.resolveCustomSnooze({ mode: 'duration', date: '', time: '', amount: '2', unit: 'hours' }, now) !== '', true);
  assert.equal(P.resolveCustomSnooze({ mode: 'date', date: '2020-01-01', time: '09:00', amount: '', unit: '' }, now), '');
  assert.equal(P.resolveCustomSnooze({ mode: 'date', date: '2026-02-30', time: '09:00', amount: '', unit: '' }, now), '');
});

test('project, thread and clone commands carry only the original fields', () => {
  assert.deepEqual(P.projectCreateCommand('c', 'p', '/work/Repo'), {
    type: 'project.create', commandId: 'c', projectId: 'p', title: 'Repo', workspaceRoot: '/work/Repo',
    createWorkspaceRootIfMissing: true, defaultModelSelection: null
  });
  assert.deepEqual(P.projectUpdateCommand('c', 'p', { title: 'New' }), { type: 'project.update', commandId: 'c', projectId: 'p', title: 'New' });
  assert.deepEqual(P.projectDeleteCommand('c', 'p'), { type: 'project.delete', commandId: 'c', projectId: 'p', force: true });
  assert.deepEqual(P.threadMetadataCommand('c', 't', 'Name'), { type: 'thread.metadata.update', commandId: 'c', threadId: 't', title: 'Name' });
  assert.deepEqual(P.threadRegenerateCommand('c', 't'), { type: 'thread.metadata.update', commandId: 'c', threadId: 't', regenerateTitle: true });
  assert.equal(P.normalizeCloneUrl('org/repo'), 'https://github.com/org/repo.git');
  assert.equal(P.cloneDirectoryName('https://github.com/org/repo.git'), 'repo');
  assert.equal(P.cloneDirectoryPath('https://github.com/org/repo.git', true), 'github.com/org/repo');
  assert.equal(P.newProjectPathPreview('/work/new/', 'My App'), '/work/new/my-app');
  assert.throws(() => P.resolveProjectPath('../repo', 'darwin'), /完整路径/);
});

test('session scope fallback and capability gating do not treat unknown as denied', () => {
  assert.equal(P.sessionAllows(undefined, 'orchestration:operate'), undefined);
  assert.equal(P.sessionAllows({ authenticated: true, scopes: ['orchestration:operate'] }, 'source-control:write'), true);
  assert.equal(P.sessionAllows({ authenticated: true, permissions: [] }, 'orchestration:operate'), false);
  assert.equal(P.sessionAllows({ authenticated: true, permissions: ['filesystem:read'] }, 'filesystem:read'), true);
  assert.equal(P.capability({ capabilities: { threadSnooze: true } }, 'threadSnooze'), true);
  assert.equal(P.capability({ capabilities: {} }, 'threadSnooze'), false);
});

test('shell parser keeps archived rows separate and ignores stale snapshots', async () => {
  const { coreUrl } = await import('./load-core.mjs');
  const { ShellState } = await import(coreUrl);
  const state = new ShellState();
  state.apply({
    kind: 'snapshot', snapshot: {
      snapshotSequence: 4,
      projects: [project('p', 'Repo', '/work/repo', { repositoryIdentity: repo('github:org/repo') })],
      threads: [thread('t', 'p', 'Active')],
      archivedThreads: [thread('a', 'p', 'Archived', { archivedAt: '2026-01-03T00:00:00.000Z' })]
    }
  });
  assert.equal(state.threads[0].label, 'Active');
  assert.equal(state.archived[0].label, 'Archived');
  state.apply({ kind: 'snapshot', snapshot: { snapshotSequence: 3, projects: [], threads: [], archivedThreads: [] } });
  assert.equal(state.threads.length, 1);
  state.apply({ kind: 'thread.updated', sequence: 5, location: 'archive', thread: thread('t', 'p', 'Archived now', { archivedAt: '2026-01-04T00:00:00.000Z' }) });
  assert.equal(state.threads.length, 0);
  assert.equal(state.archived.find(row => row.id === 't').label, 'Archived now');
});

test('archived threads group per project, filter by environment, search project or title, and sort by archive date', () => {
  const snapshot = (threads, projects) => ({ projects, threads });
  const snapshots = {
    a: snapshot([
      { id: 'same', projectId: 'p', title: 'Alpha', archivedAt: '2026-01-02T00:00:00.000Z',
        createdAt: '2026-01-01T00:00:00.000Z', updatedAt: '2026-01-02T00:00:00.000Z' },
      { id: 'older', projectId: 'p', title: 'Old', archivedAt: '2026-01-01T00:00:00.000Z',
        createdAt: '2026-01-01T00:00:00.000Z', updatedAt: '2026-01-01T00:00:00.000Z' }
    ], [project('p', 'Repo', '/work/repo', { repositoryIdentity: repo('github:org/repo') })]),
    b: snapshot([
      { id: 'same', projectId: 'p', title: 'Beta', archivedAt: '2026-01-03T00:00:00.000Z',
        createdAt: '2026-01-01T00:00:00.000Z', updatedAt: '2026-01-03T00:00:00.000Z' }
    ], [project('p', 'Repo', '/work/repo-b', { repositoryIdentity: repo('github:org/repo') })])
  };
  const groups = P.buildArchiveGroups({
    snapshots, entries: [
      { localId: 'a', environmentId: 'env-a', label: 'A' },
      { localId: 'b', environmentId: 'env-b', label: 'B' }
    ], environmentId: 'env-b', query: '', sortOrder: 'newest', scratchRoots: {}
  });
  assert.equal(groups.length, 1);assert.equal(groups[0].threads[0].environmentLabel, 'B');
  const searched = P.buildArchiveGroups({
    snapshots, entries: [
      { localId: 'a', environmentId: 'env-a', label: 'A' },
      { localId: 'b', environmentId: 'env-b', label: 'B' }
    ], environmentId: '', query: 'alpha', sortOrder: 'oldest', scratchRoots: {}
  });
  assert.equal(searched.length, 1);assert.equal(searched[0].threads.length, 1);
  assert.equal(searched[0].threads[0].label, 'Alpha');
});

test('Working preference switches between the inbox clock and manual active ordering without dropping search matches', () => {
  const at = day => '2026-01-' + String(day).padStart(2, '0') + 'T00:00:00.000Z';
  const row = (id, extra) => scopedThread('a', thread(id, 'p', id, extra));
  const threads = [
    row('running', { status: 'running', createdAt: at(4), latestRunRequestedAt: at(8) }),
    row('new', { createdAt: at(5), latestUserMessageAt: at(9) }),
    row('returned', { createdAt: at(2), unsettledAt: at(6), latestRunCompletedAt: at(7) }),
    row('manual-later', { activeOrderKey: 'c', createdAt: at(3) }),
    row('manual-first', { activeOrderKey: 'b', createdAt: at(2) }),
    row('approval', { status: 'running', pendingRuntimeRequest: { kind: 'approval', createdAt: at(9) } }),
    row('answer', { status: 'waiting', pendingRuntimeRequest: { kind: 'user_input', createdAt: at(8) } }),
    row('pinned', { status: 'running', pinnedAt: at(3), pinOrderKey: 'b' }),
    row('snoozed', { status: 'running', snoozedAt: at(8), snoozedUntil: at(12), settledOverride: 'settled', pinnedAt: at(4) }),
    row('settled', { status: 'running', settledOverride: 'settled', pinnedAt: at(4) })
  ];
  const input = { threads, environmentId: '', projectRefs: [], query: '', searchHits: {},
    nowMs: Date.parse(at(10)), capabilities: { a: caps() }, sortOrder: 'updated_at', selectedKey: '' };
  const enabled = P.buildThreadShelves({ ...input, workingShelfEnabled: true });
  const disabled = P.buildThreadShelves({ ...input, workingShelfEnabled: false });
  const ids = rows => rows.map(item => item.id);
  assert.equal(enabled.workingShelfEnabled, true);
  assert.deepEqual(ids(enabled.active), ['approval', 'answer', 'returned', 'new', 'manual-later', 'manual-first']);
  assert.deepEqual(ids(enabled.working), ['running']);
  assert.equal(disabled.workingCount, 0);
  assert.deepEqual(ids(disabled.active), ['returned', 'new', 'running', 'answer', 'approval', 'manual-first', 'manual-later']);
  assert.equal(P.canMoveBeforeActiveNeighbor(disabled.active, 0), false);
  assert.equal(P.canMoveBeforeActiveNeighbor(disabled.active, 5), true);
  for (const shelves of [enabled, disabled]) {
    assert.deepEqual(ids(shelves.pinned), ['pinned']);
    assert.deepEqual(ids(shelves.snoozed), ['snoozed']);
    assert.deepEqual(ids(shelves.settled), ['settled']);
    const results = P.buildThreadShelves({ ...input, workingShelfEnabled: shelves.workingShelfEnabled,
      query: 'matching body', searchHits: { 'a:running': 'matching body' } });
    assert.deepEqual(ids(results.matches), ['running']);
  }
});

test('new-task destination selects the current, filtered or remembered checkout by environment and falls back safely', () => {
  const copy = (env, id, extra = {}) => scopedProject(env, project(id, id, '/work/repo',
    { repositoryIdentity: repo('github:org/repo'), ...extra }));
  const a = copy('a', 'same');
  const b = copy('b', 'same');
  const current = copy('a', 'current', { repositoryIdentity: repo('github:org/current', '/work/current') });
  const archived = copy('b', 'archived', { archivedAt: '2026-01-05T00:00:00.000Z' });
  const scratch = { ...copy('b', 'scratch'), isScratch: true };
  const group = P.buildProjectGroups([a, b], 'repository')[0];
  const all = [a, b, current, archived, scratch];
  const ref = item => ({ environmentId: item.environmentId, projectId: item.id });
  const pick = ({ ready = ['a', 'b'], enabled = true, focused, filtered, prefer = 'a', last } = {}) =>
    P.newTaskDestination(all, ready, enabled, focused, filtered, prefer, last);
  assert.equal(pick({ enabled: false, focused: ref(current), filtered: group, last: ref(b) }), undefined);
  assert.equal(pick({ focused: ref(current), filtered: group, last: ref(b) }), current);
  assert.equal(pick({ focused: ref(archived), filtered: group, last: ref(b) }), b);
  assert.equal(pick({ filtered: group, last: ref(b), ready: ['a'] }), a);
  assert.equal(pick({ filtered: group, last: ref(current), prefer: 'b' }), b);
  assert.equal(pick({ last: ref(b) }), b);
  assert.equal(pick({ last: ref(b), ready: ['a'] }), undefined);
  assert.equal(pick({ last: ref(archived) }), undefined);
  assert.equal(pick({ last: ref(scratch) }), undefined);
  assert.equal(pick({ focused: ref(scratch) }), scratch);
  assert.equal(pick({ last: { environmentId: 'gone', projectId: 'same' } }), undefined);
});

test('saved filters stay scoped before snapshots, through reconnect and regrouping, and until explicitly cleared', async () => {
  const index = await readFile(new URL('../entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
  const methodRange = (start, end) => index.slice(index.indexOf(start), index.indexOf(end, index.indexOf(start)));
  const bind = methodRange('  private bindEnvironment()', '  private workspace()');
  assert.match(bind, /this\.syncProjectFilter\(\)/);
  assert.doesNotMatch(bind, /this\.(?:environmentFilter|projectFilterKey)\s*=\s*''/);
  const shelves = methodRange('  private rebuildWorkspace()', '    if (this.snoozeTimer)');
  const { FilterPage, workspacePrefs } = await import(data(compile(`
    import { buildProjectGroups, projectGroupRefs, buildThreadShelves, newTaskDestination } from ${JSON.stringify(projectsUrl)};
    export const workspacePrefs = { projectGroupingMode: 'repository', projectFilterGroupingMode: 'repository',
      projectFilterKey: 'github:org/repo', environmentFilter: 'a', useLastProjectForNewThreads: true,
      lastThreadProject: { environmentId: 'env-b', projectId: 'other' } };
    const saveWorkspacePreferences = () => {};
    export class FilterPage {
      ${methodRange('  private chooseGrouping(', '  private setThreadQuery(')}
      ${methodRange('  private filterProjectKey(', '  private async restoreAddress(')}
      ${methodRange('  private async filterEnvironment(', '  private async openScopedThread(')}
      ${methodRange('  private async startNewTask(', '  private rememberProject(')}
      ${shelves} }
    }
  `)));
  const a = scopedProject('a', project('target', 'Repo', '/work/repo', { repositoryIdentity: repo('github:org/repo') }));
  const path = scopedProject('a', project('nested', 'Nested', '/work/repo/packages/ui',
    { repositoryIdentity: repo('github:org/repo') }));
  const b = scopedProject('b', project('other', 'Other', '/work/other'));
  const elsewhere = scopedThread('b', thread('other-thread', b.id, 'Other'));
  const target = scopedThread('a', thread('target-thread', a.id, 'Target'));
  const clients = new Map([['b', { ready: true }]]);
  let pickers = 0;
  const page = Object.assign(new FilterPage(), {
    page: 'sessions', selectedLocalId: 'b', threadId: '', threadQuery: '', searchHits: {}, threadSearchHits: {},
    projectFilterKey: workspacePrefs.projectFilterKey, environmentFilter: workspacePrefs.environmentFilter,
    projectGroups: [], scopedProjects: [], scopedThreads: [], environmentEntries: [],
    threadCapabilities: {}, registry: () => ({ clients }), openProjectPicker: () => { pickers++; },
  });
  page.syncProjectFilter(); page.rebuildWorkspace();
  assert.deepEqual(page.shelves.active, []);
  assert.equal(page.projectFilterLabel, '已选项目暂不可用');
  page.environmentEntries = [{ localId: 'b', enabled: true }];
  page.scopedProjects = [b]; page.scopedThreads = [elsewhere];
  page.chooseGrouping('repository_path');
  assert.deepEqual(page.shelves.active, []);
  page.environmentFilter = '';
  page.rebuildWorkspace();
  assert.deepEqual(page.shelves.active, []);
  await page.startNewTask();
  assert.equal(pickers, 1);
  assert.equal(page.projectFilterKey, 'github:org/repo');
  assert.equal(workspacePrefs.environmentFilter, 'a');
  page.environmentFilter = workspacePrefs.environmentFilter;
  page.scopedProjects = [a, path, b]; page.scopedThreads = [target, elsewhere];
  page.chooseGrouping('repository_path');
  assert.equal(page.projectFilterRefs.length, 2);
  assert.deepEqual(page.shelves.active.map(row => row.id), ['target-thread']);
  await page.startNewTask();
  assert.equal(pickers, 2);
  page.filterProjectKey('');
  assert.equal(workspacePrefs.projectFilterKey, '');
  assert.equal(workspacePrefs.environmentFilter, 'a');
  assert.deepEqual(page.shelves.active.map(row => row.id), ['target-thread']);
  await page.filterEnvironment(0);
  assert.equal(workspacePrefs.projectFilterKey, '');
  assert.equal(workspacePrefs.environmentFilter, '');
  assert.equal(workspacePrefs.projectFilterGroupingMode, undefined);
  assert.equal(page.shelves.active.length, 2);
});
