import test from 'node:test';
import assert from 'node:assert/strict';
import { coreUrl, projectsUrl, r4Url, threadRepositoriesUrl } from './load-core.mjs';
import { ThreadState } from '../entry/src/main/ets/protocol/Wire.ts';

const P = await import(projectsUrl);
const C = await import(coreUrl);
const R4 = await import(r4Url);
const TR = await import(threadRepositoriesUrl);

test('M1: projectView and cachedShellEntry parse and preserve trackedFolders with forward compatibility', () => {
  const project = P.projectView({
    id: 'proj-multi',
    title: 'Multi Repo',
    workspaceRoot: '/work/hub',
    trackedFolders: [
      { path: '/work/hub/api', name: 'api', discovered: true },
      { path: '/work/extra/web', name: 'web' },
      { path: '/work/extra/web', name: 'duplicate-ignored' },
      { path: '', name: 'invalid' }
    ],
    createdAt: '2026-11-20T00:00:00.000Z',
    updatedAt: '2026-11-20T00:00:00.000Z'
  });
  assert.deepEqual(project.trackedFolders, [
    { path: '/work/hub/api', name: 'api', discovered: true },
    { path: '/work/extra/web', name: 'web' }
  ]);
  const scoped = P.scopedProjectView(project, 'l1', 'env-1', 'Local', false);
  assert.deepEqual(scoped.trackedFolders, project.trackedFolders);

  const single = P.projectView({
    id: 'proj-single',
    title: 'Single',
    workspaceRoot: '/work/single',
    createdAt: '2026-11-20T00:00:00.000Z',
    updatedAt: '2026-11-20T00:00:00.000Z'
  });
  assert.equal(single.trackedFolders, undefined);

  const cached = C.cachedShellEntry({
    environmentId: 'env-1',
    savedAt: Date.now(),
    scratchWorkspaceRoot: '',
    capabilities: {},
    projects: [project],
    threads: []
  });
  assert.deepEqual(cached.projects[0].trackedFolders, project.trackedFolders);
});

test('M1: suggestedTrackedFolders and appendTrackedFolders enforce workspace suggestions and max cap', () => {
  const tracked = [{ path: '/work/hub/api', name: 'api', discovered: true }];
  const scanned = [
    { path: '/work/hub/api', name: 'api', isGitRepository: true, source: 'child' },
    { path: '/work/hub/child-only', name: 'child-only', isGitRepository: true, source: 'child' },
    { path: '/work/outside/web', name: 'web', isGitRepository: true, source: 'code-workspace' },
    { path: '/work/outside/web', name: 'web-dup', isGitRepository: true, source: 'code-workspace' }
  ];
  const suggested = TR.suggestedTrackedFolders(tracked, scanned);
  assert.deepEqual(suggested, [{ path: '/work/outside/web', name: 'web' }]);

  const appended = TR.appendTrackedFolders(tracked, suggested);
  assert.equal(appended.length, 2);
  assert.equal(appended[1].path, '/work/outside/web');

  const full = Array.from({ length: P.PROJECT_TRACKED_FOLDERS_MAX }, (_, idx) => ({
    path: '/work/r' + idx,
    name: 'r' + idx
  }));
  assert.equal(TR.appendTrackedFolders(full, [{ path: '/work/overflow', name: 'overflow' }]), null);
});

test('M1: parseWorkspaceFolders, parseWorkspaceScan, and parseTaskFolderResult handle valid and partial data', () => {
  const folders = TR.parseWorkspaceFolders({
    folders: [
      { name: 'api', path: '/work/hub/api', state: 'git', discovered: true },
      { name: 'docs', path: '/work/hub/docs', state: 'plain' },
      { name: 'gone', path: '/work/hub/gone', state: 'missing' },
      { name: 'bad', path: '/work/hub/bad', state: 'future-state' }
    ]
  });
  assert.equal(folders.length, 3);
  assert.equal(TR.folderStateLabel(folders[0].state), 'Git 仓库');
  assert.equal(TR.folderStateLabel(folders[2].state), '目录缺失');

  const scan = TR.parseWorkspaceScan({
    workspaceRoot: '/work/hub',
    isGitRepository: false,
    codeWorkspaceFile: '/work/hub/hub.code-workspace',
    folders: [
      { path: '/work/hub/api', name: 'api', isGitRepository: true, source: 'child' },
      { path: '/work/web', name: 'web', isGitRepository: true, source: 'code-workspace' }
    ]
  });
  assert.equal(scan.isGitRepository, false);
  assert.equal(scan.folders.length, 2);

  assert.equal(TR.parseTaskFolderResult({ taskFolder: null }), undefined);
  const tf = TR.parseTaskFolderResult({
    taskFolder: {
      root: '/tmp/wt/task-1',
      projectId: 'proj-multi',
      projectRoot: '/work/hub',
      anchor: '/work',
      projectPath: '/tmp/wt/task-1/hub',
      projectIsWorktree: false,
      repositories: [
        { repositoryPath: '/work/hub/api', worktreePath: '/tmp/wt/task-1/hub/api', name: 'api' },
        { repositoryPath: '/work/web', worktreePath: '/tmp/wt/task-1/web', name: 'web' }
      ]
    }
  });
  assert.equal(tf.projectIsWorktree, false);
  assert.equal(tf.repositories.length, 2);
});

test('M1: worktreeRepositoryChoices and resolveWorktreeRepositorySelection follow 8-repo threshold', () => {
  const folders = [
    { name: 'api', path: '/work/hub/api', state: 'git', discovered: true },
    { name: 'web', path: '/work/other/web', state: 'git' },
    { name: 'notes', path: '/work/hub/notes', state: 'plain' }
  ];
  const choices = TR.worktreeRepositoryChoices(folders, '/work/hub');
  assert.deepEqual(choices, [
    { repositoryPath: '/work/hub/api', name: 'api', relativePath: 'api' },
    { repositoryPath: '/work/other/web', name: 'web' }
  ]);

  const defaultSel = TR.resolveWorktreeRepositorySelection(choices, undefined);
  assert.deepEqual(defaultSel.selected, ['/work/hub/api', '/work/other/web']);
  assert.equal(defaultSel.needsChoice, false);
  assert.equal(defaultSel.strategyRepositories, undefined);

  const customSel = TR.resolveWorktreeRepositorySelection(choices, ['/work/hub/api']);
  assert.deepEqual(customSel.selected, ['/work/hub/api']);
  assert.deepEqual(customSel.strategyRepositories, [{ path: '/work/hub/api' }]);

  const manyChoices = Array.from({ length: TR.TASK_FOLDER_DEFAULT_REPOSITORIES_MAX + 1 }, (_, i) => ({
    repositoryPath: '/work/hub/repo-' + i,
    name: 'repo-' + i
  }));
  const overThreshold = TR.resolveWorktreeRepositorySelection(manyChoices, undefined);
  assert.deepEqual(overThreshold.selected, []);
  assert.equal(overThreshold.needsChoice, true);
  assert.equal(overThreshold.strategyRepositories, undefined);
});

test('M1: DraftWorkspace and launchWorkspace support multi-repo repositories list and plain root fallback', () => {
  const draft = R4.composerDraft({
    version: 1,
    draftId: 'd-multi',
    localId: 'l1',
    environmentId: 'env-1',
    projectId: 'proj-multi',
    text: 'Check both repos',
    modelSelection: { instanceId: 'codex', model: 'gpt-5' },
    runtimeMode: 'approval-required',
    interactionMode: 'default',
    workspace: {
      mode: 'worktree',
      branch: '',
      worktreePath: '',
      startFromOrigin: true,
      repositories: ['/work/hub/api', '/work/web']
    },
    attachments: [],
    context: [],
    updatedAt: 10
  });
  assert.deepEqual(draft.workspace.repositories, ['/work/hub/api', '/work/web']);
  // Single-repo git root still requires an explicit baseRef
  assert.throws(() => R4.launchWorkspace(draft, true));
  // Plain multi-repo project root falls back to HEAD and sends repositories list
  assert.deepEqual(R4.launchWorkspace(draft, false), {
    type: 'worktree',
    baseRef: 'HEAD',
    startFromOrigin: true,
    repositories: [{ path: '/work/hub/api' }, { path: '/work/web' }]
  });
  // Switching workspace mode preserves chosen repositories
  const switched = R4.switchDraftWorkspaceMode(draft.workspace, 'local', []);
  assert.deepEqual(switched.repositories, ['/work/hub/api', '/work/web']);
});

test('M1: threadChangedRepositories, threadGitRepositories, threadRepositorySections, and ThreadState checkpointScopes', () => {
  const state = new ThreadState('t-multi');
  state.apply({
    kind: 'snapshot',
    snapshotSequence: 5,
    projection: {
      thread: { id: 't-multi', projectId: 'proj-multi' },
      messages: [],
      runs: [],
      turnItems: [],
      checkpoints: [
        { id: 'cp1', scopeId: 's-api', runId: 'r1', ordinalWithinScope: 1, status: 'ready', files: [] },
        { id: 'cp2', scopeId: 's-web', runId: 'r2', ordinalWithinScope: 2, status: 'ready', files: [] }
      ],
      checkpointScopes: [
        { id: 's-root', kind: 'root', parentScopeId: null, cwd: '/work/hub' },
        { id: 's-api', kind: 'manual', parentScopeId: 's-root', cwd: '/work/hub/api', label: 'api', repositoryPath: '/work/hub/api' },
        { id: 's-web', kind: 'manual', parentScopeId: 's-root', cwd: '/work/web', label: 'web', repositoryPath: '/work/web' }
      ]
    }
  });
  assert.equal(state.checkpointScopes.length, 3);
  state.apply({
    kind: 'event',
    sequence: 6,
    event: {
      threadId: 't-multi',
      type: 'checkpoint-scope.created',
      payload: { id: 's-cli', kind: 'manual', parentScopeId: 's-root', cwd: '/work/hub/cli', label: 'cli', repositoryPath: '/work/hub/cli' }
    }
  });
  assert.equal(state.checkpointScopes.length, 4);

  const changed = TR.threadChangedRepositories(state.checkpoints, state.checkpointScopes);
  // Most recently changed (web ordinal 2) comes first, then api (ordinal 1), then cli (no run)
  assert.deepEqual(changed.map((item) => item.name), ['web', 'api', 'cli']);

  const taskFolder = {
    root: '/tmp/wt/t1',
    projectId: 'proj-multi',
    projectRoot: '/work/hub',
    anchor: '/work',
    projectPath: '/tmp/wt/t1/hub',
    projectIsWorktree: false,
    repositories: [
      { repositoryPath: '/work/hub/api', worktreePath: '/tmp/wt/t1/hub/api', name: 'api' },
      { repositoryPath: '/work/web', worktreePath: '/tmp/wt/t1/web', name: 'web' }
    ]
  };
  const sections = TR.threadRepositorySections(changed, [], '/tmp/wt/t1/hub', true, taskFolder, true);
  assert.deepEqual(sections.visible.map((s) => ({ name: s.name, cwd: s.cwd, origin: s.origin })), [
    { name: 'web', cwd: '/tmp/wt/t1/web', origin: 'worktree' },
    { name: 'api', cwd: '/tmp/wt/t1/hub/api', origin: 'worktree' }
  ]);

  const gitRepos = TR.threadGitRepositories(changed, undefined, [
    { name: 'api', path: '/work/hub/api', state: 'git', discovered: true },
    { name: 'extra', path: '/work/extra', state: 'git' }
  ], '/work/hub');
  assert.equal(gitRepos.some((r) => r.name === 'extra'), true);
  assert.equal(TR.repositoryFilePath('api', 'src/index.ts'), 'api/src/index.ts');
  assert.equal(TR.repositoryFilePath('', 'README.md'), 'README.md');
});
