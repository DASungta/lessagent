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

test('settled detection, unseen completion badge, and visited failure clearing match Thread List V2 rules', () => {
  const now = Date.parse('2026-01-05T12:00:00.000Z');
  const fullCaps = caps();
  const noSettleCaps = caps({ settlement: false });

  const settled = scopedThread('a', thread('s1', 'p', 'Settled thread', {
    settledOverride: 'settled',
    latestRunCompletedAt: '2026-01-05T10:00:00.000Z',
    lastVisitedAt: '2026-01-05T09:00:00.000Z'
  }));
  assert.equal(P.threadIsSettled(settled, fullCaps), true);
  assert.equal(P.threadIsSettled(settled, noSettleCaps), false);
  assert.equal(P.threadHasUnseenCompletion(settled), false);

  const unseen = scopedThread('a', thread('u1', 'p', 'Unseen completion', {
    latestRunCompletedAt: '2026-01-05T10:00:00.000Z',
    lastVisitedAt: '2026-01-05T09:00:00.000Z'
  }));
  assert.equal(P.threadHasUnseenCompletion(unseen), true);
  assert.equal(P.threadStatus(unseen, now), '已回复');

  const visited = scopedThread('a', thread('u2', 'p', 'Visited completion', {
    latestRunCompletedAt: '2026-01-05T10:00:00.000Z',
    lastVisitedAt: '2026-01-05T10:05:00.000Z'
  }));
  assert.equal(P.threadHasUnseenCompletion(visited), false);
  assert.equal(P.threadStatus(visited, now), '');

  const neverVisited = scopedThread('a', thread('u3', 'p', 'No lastVisitedAt', {
    latestRunCompletedAt: '2026-01-05T10:00:00.000Z'
  }));
  assert.equal(P.threadHasUnseenCompletion(neverVisited), false);
  assert.equal(P.threadStatus(neverVisited, now), '');

  const interrupted = scopedThread('a', thread('u4', 'p', 'Interrupted', {
    status: 'interrupted',
    latestRunCompletedAt: '2026-01-05T10:00:00.000Z',
    lastVisitedAt: '2026-01-05T09:00:00.000Z'
  }));
  assert.equal(P.threadHasUnseenCompletion(interrupted), false);

  const unseenFailed = scopedThread('a', thread('f1', 'p', 'Failed unseen', {
    status: 'failed',
    latestRunCompletedAt: '2026-01-05T10:00:00.000Z',
    lastVisitedAt: '2026-01-05T09:00:00.000Z'
  }));
  assert.equal(P.threadStatus(unseenFailed, now), '失败');

  const seenFailed = scopedThread('a', thread('f2', 'p', 'Failed seen', {
    status: 'failed',
    latestRunCompletedAt: '2026-01-05T10:00:00.000Z',
    lastVisitedAt: '2026-01-05T10:01:00.000Z'
  }));
  assert.equal(P.threadStatus(seenFailed, now), '');

  const seenLimited = scopedThread('a', thread('f3', 'p', 'Usage limited seen', {
    status: 'failed',
    lastErrorClass: 'usage_limit',
    latestRunCompletedAt: '2026-01-05T10:00:00.000Z',
    lastVisitedAt: '2026-01-05T10:01:00.000Z'
  }));
  assert.equal(P.threadStatus(seenLimited, now), '用量受限');
});

test('projectView parses server projectIcon variants safely and propagates them to groups and threads', () => {
  const globe = P.projectView(project('p1', 'NetworkOps', '/work/ops', {
    projectIcon: { kind: 'lucide', name: 'globe-2', color: 'indigo' }
  }));
  assert.deepEqual(globe.projectIcon, { kind: 'lucide', name: 'globe-2', color: 'indigo', emoji: '', text: '' });

  const emoji = P.projectView(project('p2', 'Tools', '/work/tools', {
    projectIcon: { kind: 'emoji', emoji: '🚀' }
  }));
  assert.deepEqual(emoji.projectIcon, { kind: 'emoji', name: '', color: '', emoji: '🚀', text: '' });

  const mono = P.projectView(project('p3', 'Core', '/work/core', {
    projectIcon: { kind: 'monogram', text: 'CR', color: 'emerald' }
  }));
  assert.deepEqual(mono.projectIcon, { kind: 'monogram', name: '', color: 'emerald', emoji: '', text: 'CR' });

  const legacy = P.projectView(project('p4', 'Legacy', '/work/legacy', {
    projectIcon: { kind: 'lucide', name: 'folder-code', color: 'rose', monogramText: 'LG' }
  }));
  assert.deepEqual(legacy.projectIcon, { kind: 'monogram', name: '', color: 'rose', emoji: '', text: 'LG' });

  const invalid = P.projectView(project('p5', 'Plain', '/work/plain', {
    projectIcon: { kind: 'lucide', name: 'bad icon!!', color: 'nope' }
  }));
  assert.equal(invalid.projectIcon, undefined);

  const scopedA = P.scopedProjectView(
    P.projectView(project('p6', 'Shared', '/work/shared', { repositoryIdentity: repo('github:org/shared') })),
    'a', 'env-a', 'Mac A', false
  );
  const scopedB = P.scopedProjectView(
    P.projectView(project('p6b', 'Shared', '/work/shared', {
      repositoryIdentity: repo('github:org/shared'),
      projectIcon: { kind: 'lucide', name: 'wrench', color: 'fuchsia' }
    })),
    'b', 'env-b', 'Mac B', false
  );
  const group = P.buildProjectGroups([scopedA, scopedB], 'repository')[0];
  assert.deepEqual(P.groupProjectIcon(group), { kind: 'lucide', name: 'wrench', color: 'fuchsia', emoji: '', text: '' });

  const st = P.scopedThreadView(P.threadView(thread('t1', 'p1', 'Hello')), 'a', 'env-a', 'Mac A', 'NetworkOps', globe.projectIcon);
  assert.deepEqual(st.projectIcon, globe.projectIcon);
});

test('ProjectPicker uses pin icon instead of text badge and clean multi-environment filter chips', async () => {
  const pickerSource = await readFile(new URL('../entry/src/main/ets/components/ProjectPicker.ets', import.meta.url), 'utf8');
  assert.equal(pickerSource.includes("StatusBadge({ text: '固定'"), false);
  assert.equal(pickerSource.includes("app.media.ui_pin"), true);
  assert.equal(pickerSource.includes("this.environments.length > 1"), true);
  assert.equal(pickerSource.includes("this.envChip('所有环境', !this.environmentId, () => this.onEnvironment(''))"), true);
  assert.equal(pickerSource.includes("icon: this.groupIcon(group)"), true);
});

test('projectView and scopedProjectView preserve defaultModelSelection and options', () => {
  const configured = P.projectView(project('p-def', 'Configured', '/work/cfg', {
    defaultModelSelection: { instanceId: 'antigravity', model: 'gemini-4-neon', options: [{ id: 'thought_level', value: 'xhigh' }] }
  }));
  assert.deepEqual(configured.defaultModelSelection, {
    instanceId: 'antigravity', model: 'gemini-4-neon', options: [{ id: 'thought_level', value: 'xhigh' }]
  });
  const scoped = P.scopedProjectView(configured, 'a', 'env-a', 'Mac', false);
  assert.deepEqual(scoped.defaultModelSelection, configured.defaultModelSelection);
  assert.equal(P.projectView(project('p-null', 'Null', '/work/null', { defaultModelSelection: null })).defaultModelSelection, null);
});

test('threads waiting on holding background work (subagents, background tasks, awaited commands/monitors) stay in Working as 等待', () => {
  const now = Date.parse('2026-11-23T00:57:00.000Z');
  const completedAt = '2026-11-23T00:40:37.320Z';
  const visitedBefore = '2026-11-23T00:30:00.000Z';
  const row = (id, extra) => scopedThread('a', thread(id, 'p', id, extra));

  // Real-world case: main turn completed while a delegated subagent is still running
  const subagentRunning = row('subagent-bg', {
    status: 'completed',
    latestRunId: 'run-7',
    latestRunCompletedAt: completedAt,
    lastVisitedAt: visitedBefore,
    pendingBackgroundTasks: [{
      taskId: 'turn-item:delegated-task:1',
      kind: 'subagent',
      description: 'Neon 执行第1+2批',
      childThreadId: 'child-1'
    }]
  });
  const bgTaskRunning = row('bg-task', {
    status: 'completed',
    latestRunId: 'run-2',
    latestRunCompletedAt: completedAt,
    pendingBackgroundTasks: [{ taskId: 'bg-1', kind: 'background_task' }]
  });
  // PR watch holds completion even on a thread that never ran
  const prWatchNeverRan = row('pr-watch', {
    status: 'idle',
    latestRunId: null,
    pendingBackgroundTasks: [{ taskId: 'pull-request-watch:github.com/org/repo#1', kind: 'monitor', awaited: true }]
  });
  // Unmarked command / monitor (e.g. dev server / watchdog) does NOT hold completion
  const devServer = row('dev-server', {
    status: 'completed',
    latestRunId: 'run-3',
    latestRunCompletedAt: completedAt,
    lastVisitedAt: visitedBefore,
    pendingBackgroundTasks: [{ taskId: 'cmd-1', kind: 'command' }]
  });
  const unawaitedMonitor = row('unawaited-monitor', {
    status: 'completed',
    latestRunId: 'run-4',
    latestRunCompletedAt: completedAt,
    lastVisitedAt: '2026-11-23T00:45:00.000Z',
    pendingBackgroundTasks: [{ taskId: 'mon-1', kind: 'monitor' }]
  });
  // Failed run stays out of Working even with pending background tasks
  const failedWithBg = row('failed-bg', {
    status: 'failed',
    latestRunId: 'run-5',
    latestRunCompletedAt: completedAt,
    lastVisitedAt: visitedBefore,
    lastError: 'Provider failed',
    pendingBackgroundTasks: [{ taskId: 'sub-2', kind: 'subagent' }]
  });
  // Running turn blocked on thread wait stays in Working and displays 等待
  const blockedWait = row('blocked-wait', {
    status: 'running',
    activeRunId: 'run-6',
    latestRunId: 'run-6',
    blockedOnThreadWait: true
  });
  // Plan mode with actionable proposed plan surfaces in Active once run settles
  const proposedPlan = row('proposed-plan', {
    status: 'completed',
    latestRunId: 'run-8',
    interactionMode: 'plan',
    hasActionableProposedPlan: true,
    pendingBackgroundTasks: [{ taskId: 'sub-plan', kind: 'subagent' }]
  });

  assert.equal(P.threadIsWorking(subagentRunning), true);
  assert.equal(P.threadStatus(subagentRunning, now), '等待');
  assert.equal(P.threadCanArchive(subagentRunning), true);
  assert.equal(P.threadCanSnooze(subagentRunning, now), true);

  assert.equal(P.threadIsWorking(bgTaskRunning), true);
  assert.equal(P.threadStatus(bgTaskRunning, now), '等待');

  assert.equal(P.threadIsWorking(prWatchNeverRan), true);
  assert.equal(P.threadStatus(prWatchNeverRan, now), '等待');

  assert.equal(P.threadIsWorking(devServer), false);
  assert.equal(P.threadStatus(devServer, now), '已回复');

  assert.equal(P.threadIsWorking(unawaitedMonitor), false);
  assert.equal(P.threadStatus(unawaitedMonitor, now), '');

  assert.equal(P.threadIsWorking(failedWithBg), false);
  assert.equal(P.threadStatus(failedWithBg, now), '失败');

  assert.equal(P.threadIsWorking(blockedWait), true);
  assert.equal(P.threadStatus(blockedWait, now), '等待');

  assert.equal(P.threadIsWorking(proposedPlan), false);

  const shelves = P.buildThreadShelves({
    threads: [subagentRunning, bgTaskRunning, prWatchNeverRan, devServer, unawaitedMonitor, failedWithBg, blockedWait, proposedPlan],
    environmentId: '',
    projectRefs: [],
    query: '',
    searchHits: {},
    nowMs: now,
    capabilities: { a: caps() },
    sortOrder: 'updated_at',
    selectedKey: '',
    workingShelfEnabled: true
  });
  const ids = rows => rows.map(item => item.id).sort();
  assert.deepEqual(ids(shelves.working), ['bg-task', 'blocked-wait', 'pr-watch', 'subagent-bg']);
  assert.deepEqual(ids(shelves.active), ['dev-server', 'failed-bg', 'proposed-plan', 'unawaited-monitor']);
  assert.equal(shelves.workingCount, 4);
});

test('live subagent approvals, user-only inputs, and side-chat requests roll up to parent and pull it out of Working', () => {
  const now = Date.parse('2026-11-23T01:00:00.000Z');
  const row = (env, id, extra) => scopedThread(env, thread(id, 'p', id, extra));

  const parentApproval = row('a', 'parent-approval', {
    status: 'completed',
    latestRunId: 'run-1',
    pendingBackgroundTasks: [{ taskId: 'sub-1', kind: 'subagent', childThreadId: 'child-approval' }]
  });
  const childApproval = row('a', 'child-approval', {
    status: 'waiting',
    lineage: { parentThreadId: 'parent-approval', relationshipToParent: 'subagent' },
    pendingRuntimeRequest: { kind: 'approval', createdAt: '2026-11-23T00:55:00.000Z' }
  });

  // Coordinator-answered subagent question (userOnly !== true) stays in Working
  const parentCoordQ = row('a', 'parent-coord-q', {
    status: 'completed',
    latestRunId: 'run-2',
    pendingBackgroundTasks: [{ taskId: 'sub-2', kind: 'subagent', childThreadId: 'child-coord-q' }]
  });
  const childCoordQ = row('a', 'child-coord-q', {
    status: 'waiting',
    lineage: { parentThreadId: 'parent-coord-q', relationshipToParent: 'subagent' },
    pendingRuntimeRequest: { kind: 'user_input', createdAt: '2026-11-23T00:55:00.000Z' }
  });

  // User-only subagent card rolls up as input and leaves Working
  const parentUserOnly = row('a', 'parent-user-only', {
    status: 'completed',
    latestRunId: 'run-3',
    pendingBackgroundTasks: [{ taskId: 'sub-3', kind: 'subagent', childThreadId: 'child-user-only' }]
  });
  const childUserOnly = row('a', 'child-user-only', {
    status: 'waiting',
    lineage: { parentThreadId: 'parent-user-only', relationshipToParent: 'subagent' },
    pendingRuntimeRequest: { kind: 'user_input', userOnly: true, createdAt: '2026-11-23T00:55:00.000Z' }
  });

  // Provider-native subagent is skipped from roll-up
  const parentNative = row('a', 'parent-native', {
    status: 'completed',
    latestRunId: 'run-4',
    pendingBackgroundTasks: [{ taskId: 'sub-4', kind: 'subagent', childThreadId: 'child-native' }]
  });
  const childNative = row('a', 'child-native', {
    status: 'waiting',
    creationSource: 'provider',
    lineage: { parentThreadId: 'parent-native', relationshipToParent: 'subagent' },
    pendingRuntimeRequest: { kind: 'approval', createdAt: '2026-11-23T00:55:00.000Z' }
  });

  // Cross-environment delegated task approval wakes parent on env-a
  const parentDelegated = row('a', 'parent-delegated', {
    status: 'completed',
    latestRunId: 'run-5',
    snoozedAt: '2026-11-23T00:50:00.000Z',
    snoozedUntil: '2026-11-23T02:00:00.000Z',
    pendingBackgroundTasks: [{ taskId: 'sub-5', kind: 'subagent' }]
  });
  const remoteChild = row('b', 'remote-child', {
    status: 'running',
    delegatedFrom: { environmentId: 'env-a', threadId: 'parent-delegated' },
    pendingRuntimeRequest: { kind: 'permission', createdAt: '2026-11-23T00:55:00.000Z' }
  });

  const shelves = P.buildThreadShelves({
    threads: [
      parentApproval, childApproval,
      parentCoordQ, childCoordQ,
      parentUserOnly, childUserOnly,
      parentNative, childNative,
      parentDelegated, remoteChild
    ],
    environmentId: '',
    projectRefs: [],
    query: '',
    searchHits: {},
    nowMs: now,
    capabilities: { a: caps(), b: caps() },
    sortOrder: 'updated_at',
    selectedKey: '',
    workingShelfEnabled: true
  });
  const byId = Object.fromEntries(shelves.active.concat(shelves.working).map(t => [t.id, t]));
  assert.deepEqual(shelves.working.map(t => t.id).sort(), ['parent-coord-q', 'parent-native']);
  assert.equal(P.threadStatus(byId['parent-approval'], now), '等待批准');
  assert.equal(P.threadCanSnooze(byId['parent-approval'], now), false);
  assert.equal(P.threadStatus(byId['parent-user-only'], now), '等待回答');
  assert.equal(P.threadStatus(byId['parent-coord-q'], now), '等待');
  assert.equal(P.threadStatus(byId['parent-native'], now), '等待');
  assert.equal(P.threadStatus(byId['parent-delegated'], now), '等待批准');
  assert.equal(shelves.snoozedCount, 0);
});
