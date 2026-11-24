import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  compile, data, coreUrl, projectsUrl, composerUrl, r4Url, r5Url,
  threadItemsUrl, filesUrl, floatingStatusUrl, agentFeedbackUrl
} from './load-core.mjs';
import { ThreadState, validateDescriptor } from '../entry/src/main/ets/protocol/Wire.ts';

const wireUrl = new URL('../entry/src/main/ets/protocol/Wire.ts', import.meta.url).href;
async function loadProtocol(filename, replacements = {}) {
  let src = await readFile(new URL(`../entry/src/main/ets/protocol/${filename}`, import.meta.url), 'utf8');
  src = src.replaceAll("'./Wire'", JSON.stringify(wireUrl));
  for (const [from, to] of Object.entries(replacements)) {
    src = src.replaceAll(from, JSON.stringify(to));
  }
  return import(data(compile(src)));
}

const core = await import(coreUrl);
const projects = await import(projectsUrl);
const composer = await import(composerUrl);
const r4 = await import(r4Url);
const r5 = await import(r5Url);
const threadItems = await import(threadItemsUrl);
const files = await import(filesUrl);
const floating = await import(floatingStatusUrl);
const scheduledTasks = await loadProtocol('ScheduledTasks.ts', {
  "'./Composer'": composerUrl,
  "'./R4'": r4Url,
  "'./Projects'": projectsUrl
});
const usage = await loadProtocol('Usage.ts');
const providerSettings = await loadProtocol('ProviderSettings.ts');
const worktreeSettingsUrl = data(compile(
  (await readFile(new URL('../entry/src/main/ets/protocol/WorktreeSettings.ts', import.meta.url), 'utf8'))
    .replaceAll("'./Wire'", JSON.stringify(wireUrl))
));
const worktreeSettings = await import(worktreeSettingsUrl);
const sourceControlSettings = await loadProtocol('SourceControlSettings.ts', { "'./WorktreeSettings'": worktreeSettingsUrl });
const labsSettings = await loadProtocol('LabsSettings.ts', {
  "'./WorktreeSettings'": worktreeSettingsUrl,
  "'./AgentFeedback'": agentFeedbackUrl
});
const projectWorktreeSettings = await loadProtocol('ProjectWorktreeSettings.ts', { "'./WorktreeSettings'": worktreeSettingsUrl });
const worktreeStorage = await loadProtocol('WorktreeStorage.ts', { "'./WorktreeSettings'": worktreeSettingsUrl });
const autoSettle = await loadProtocol('AutoSettle.ts', { "'./WorktreeSettings'": worktreeSettingsUrl });
const threadDefaults = await loadProtocol('ThreadDefaults.ts', { "'./WorktreeSettings'": worktreeSettingsUrl });
const draftDefaults = await loadProtocol('DraftDefaults.ts');
const environment = await loadProtocol('Environment.ts', { "'./Core'": coreUrl });

test('ShellState and Projects drop malformed array items and tolerate repositories, unknown defaultThreadEnvMode, and snooze kinds', () => {
  const shell = new core.ShellState();
  shell.apply({
    kind: 'snapshot',
    snapshot: {
      snapshotSequence: 20,
      projects: [
        {
          id: 'p1',
          title: 'Multi-Repo Workspace',
          workspaceRoot: '/work/mono',
          defaultThreadEnvMode: 'future_sandbox_mode',
          repositories: [{ path: '/work/mono/sub-a', canonicalKey: 'gh:org/sub-a' }],
          trackedFolders: [{ name: 'sub-a', path: '/work/mono/sub-a' }]
        },
        null,
        { id: 123, title: 'bad project' }
      ],
      threads: [
        {
          id: 't1',
          title: 'Main Task',
          projectId: 'p1',
          pendingBackgroundTasks: [{ taskId: 'bg1', kind: 'command' }, null, 'bad']
        },
        { id: '', title: 'empty id', projectId: 'p1' }
      ],
      archivedThreads: [
        { id: 't2', title: 'Archived', projectId: 'p1', archivedAt: '2026-11-20T00:00:00Z' },
        { id: 99 }
      ]
    }
  });
  assert.equal(shell.projects.length, 1);
  assert.equal(shell.projects[0].id, 'p1');
  assert.equal(shell.projects[0].defaultThreadEnvMode, undefined);
  assert.equal(shell.threads.length, 1);
  assert.equal(shell.threads[0].pendingBackgroundTasks.length, 1);
  assert.equal(shell.archived.length, 1);

  const presets = projects.snoozeSettingsFrom([
    { kind: 'after', minutes: 30 },
    { kind: 'future_trigger', rule: 'when-idle' },
    null,
    { kind: 'at', day: 'tomorrow', time: '09:30' }
  ]);
  assert.equal(presets.length, 2);
  assert.equal(presets[0].kind, 'after');
  assert.equal(presets[1].kind, 'at');

  const archivedGroups = projects.buildArchiveGroups({
    snapshots: {
      loc1: {
        projects: [{ id: 'p1', title: 'P1', workspaceRoot: '/w' }, { bad: true }],
        threads: [{ id: 't2', title: 'Old', projectId: 'p1', archivedAt: '2026-11-20T00:00:00Z' }, null]
      }
    },
    entries: [{ localId: 'loc1', environmentId: 'env1', label: 'Mac' }],
    environmentId: '',
    query: '',
    sortOrder: 'newest',
    scratchRoots: {}
  });
  assert.equal(archivedGroups.length, 1);
  assert.equal(archivedGroups[0].threads.length, 1);
});

test('ThreadState, ThreadItems, Core.cards, and FloatingStatus tolerate unknown turn items, manual checkpoint scopes with repositoryPath, and secret fields', () => {
  const state = new ThreadState('t1');
  state.apply({
    kind: 'snapshot',
    snapshotSequence: 5,
    projection: {
      thread: {
        id: 't1',
        pullRequests: [{ host: 'github.com', repository: 'org/repo', number: 1, url: 'https://github.com/org/repo/pull/1', source: 'manual', watch: { checksPending: true } }, 'bad-pr'],
        pendingBackgroundTasks: [{ taskId: 'bg-1', kind: 'command', description: 'build' }, null]
      },
      messages: [{ id: 'm1', threadId: 't1', role: 'user', text: 'hi', streaming: false }, null],
      runs: [{ id: 'r1', status: 'completed', ordinal: 1 }, 'bad-run'],
      checkpoints: [
        {
          id: 'cp1',
          runId: 'r1',
          status: 'ready',
          scope: { kind: 'manual', repositoryPath: '/work/mono/sub-a' },
          repositoryPath: '/work/mono/sub-a',
          files: [{ path: 'src/a.ts', additions: 3, deletions: 1 }, null, 'bad']
        },
        null
      ],
      visibleTurnItems: [
        {
          visibility: 'local',
          item: { id: 'u1', type: 'user_message', messageId: 'm1', runId: 'r1', text: 'hi', ordinal: 1 }
        },
        {
          visibility: 'local',
          item: { id: 'fut1', type: 'future_widget_card', runId: 'r1', title: 'Preview', status: 'completed', ordinal: 2 }
        },
        {
          visibility: 'local',
          item: {
            id: 'sec1', type: 'secret_request', secretStatus: 'pending', label: 'Credentials', reason: 'Sign in',
            delivery: 'file', ordinal: 3,
            fields: [{ name: 'email', label: 'Email', secret: false }, { name: '', label: 'DropMe' }, { name: 'password', label: 'Password' }]
          }
        },
        {
          visibility: 'local',
          item: { id: 'err1', type: 'error', runId: 'r1', status: 'failed', failure: null, ordinal: 4 }
        },
        null,
        { visibility: 'local', item: 'not-an-object' }
      ],
      runtimeRequests: [{ id: 'req1', status: 'pending', responseCapability: { type: 'live' } }, null]
    }
  });
  assert.equal(state.messages.length, 1);
  assert.equal(state.runs.length, 1);
  assert.equal(state.checkpoints.length, 1);
  assert.equal(state.items.length, 4);

  // Unknown future turn item renders via generic fallback without throwing
  const lines = threadItems.activityLines([
    ...state.items,
    { id: 'bad-no-type' },
    { id: 'fs1', type: 'file_search', pattern: '*.ts', results: [{ fileName: 'a.ts' }, null, { noFileName: 1 }] }
  ]);
  assert.ok(lines.some((line) => line.kind === 'future_widget_card'));
  assert.ok(lines.some((line) => line.kind === 'error'));
  assert.ok(lines.some((line) => line.kind === 'file_search' && line.text.includes('a.ts')));

  const grouped = threadItems.groupWorkByMessage(state.items, state.runs, state.checkpoints, state.messages);
  assert.equal(grouped.hasVisible, true);

  const actionCards = core.cards(state.requests, [
    ...state.items,
    { type: 'secret_request', secretStatus: 'pending', id: 123 }, // malformed card dropped
    { id: 'ui1', requestId: 'req1', type: 'user_input_request', questions: [{ id: 'q1', header: 'H', question: 'Q', options: [{ label: 'A' }, null] }, null] }
  ]);
  assert.equal(actionCards.length, 2);
  assert.equal(actionCards[0].kind, 'secret');
  assert.equal(actionCards[0].secretFields.length, 2);
  assert.equal(actionCards[1].kind, 'input');
  assert.equal(actionCards[1].questions[0].optionItems.length, 1);

  const bg = floating.derivePendingBackgroundWork(state.runs, [], state.items, state.details);
  assert.equal(bg.length, 2);
});

test('Config and settings parsers tolerate sideThreadOpenTarget, featureFlags, unknown model option types, and unknown provider/usage enums', () => {
  const config = {
    environment: {
      environmentId: 'env-1',
      serverVersion: '0.2.0',
      platform: { os: 'darwin' },
      capabilities: {
        peerLinks: true,
        projectSettingsOverrides: true,
        storageCleanup: true,
        threadAutoSettlement: true,
        futureCapability: { nested: true }
      }
    },
    featureFlags: {
      newSideThreadDrawer: true,
      experimentalMultiRepo: 'canary'
    },
    settings: {
      defaultRuntimeMode: 'approval-required',
      defaultThreadEnvMode: 'local',
      responseStreamingMode: 'paragraph',
      enableAgentBrowserAccess: false,
      newWorktreesStartFromOrigin: true,
      worktreeSubmodules: null,
      branchNamingMode: 'future_mode',
      sideThreadOpenTarget: 'split-pane',
      defaultAutoPull: true,
      ghqCloneLayout: false,
      addProjectBaseDirectory: '/work',
      removeAgentCreditsOnMerge: false,
      linkedEnvironmentsEnabled: true,
      fastWorktreeCheckout: false,
      sidebarAutoSettleOnMerge: true,
      sidebarAutoSettleAfterDays: 7,
      sidebarAutoSettleKeepPullRequests: true,
      projectSettingsOverrides: { p1: { unknownOverride: 1 } },
      storageCleanup: { worktreeAfterDays: 14, worktreeOnMerge: true }
    },
    providers: [
      {
        instanceId: 'future-ai',
        driver: 'future_provider_enum',
        displayName: 'Future AI',
        status: 'degraded_beta',
        enabled: true,
        installed: true,
        auth: { status: 'authenticated' },
        supportedRuntimeModes: ['approval-required', 'future-mode'],
        models: [
          {
            slug: 'future-1',
            name: 'Future 1',
            capabilities: {
              optionDescriptors: [
                { id: 'reasoningEffort', label: 'Reasoning', type: 'select', options: [{ id: 'high', label: 'High' }, null] },
                { id: 'temperature', label: 'Temp', type: 'number', min: 0, max: 2 },
                null
              ]
            }
          },
          null,
          { name: 'missing-slug' }
        ],
        usageLimits: {
          checkedAt: '2026-11-22T00:00:00Z',
          windows: [
            { id: 'w1', kind: 'future_window_kind', label: 'Weekly', usedPercent: 25 },
            { id: 'bad-window', label: 'Broken', usedPercent: 'nan' },
            null
          ],
          resetCredits: {
            availableCount: 1,
            options: [
              { creditId: 'c1', label: 'Boost', description: 'Reset' },
              { creditId: 123 }
            ]
          }
        }
      }
    ],
    usageLimitSources: [
      {
        id: 'hub1',
        label: 'Hub',
        accounts: [
          {
            id: 'acct1',
            driver: 'future_provider_enum',
            usageLimits: {
              checkedAt: '2026-11-22T00:00:00Z',
              windows: [{ id: 'w2', kind: 'session', label: 'Session', usedPercent: 40 }, null]
            }
          },
          null,
          { id: 'broken-acct', driver: 'codex', usageLimits: null }
        ]
      },
      null
    ]
  };

  assert.equal(core.models(config).length, 1);
  const controls = composer.optionControls(config, { instanceId: 'future-ai', model: 'future-1' });
  assert.equal(controls.length, 1);
  assert.equal(controls[0].id, 'reasoningEffort');
  assert.equal(controls[0].choices.length, 1);
  assert.deepEqual(composer.supportedModes(config, { instanceId: 'future-ai', model: 'future-1' }), ['approval-required']);

  const catalog = providerSettings.providerCatalog(config, 'env-1');
  assert.equal(catalog.length, 1);
  assert.equal(catalog[0].driver, 'future_provider_enum');
  assert.equal(catalog[0].models.length, 1);

  assert.equal(sourceControlSettings.sourceControlSettings(config, 'env-1').environmentId, 'env-1');
  assert.equal(labsSettings.labsSettings(config, 'env-1').linkedEnvironmentsEnabled.value, true);
  assert.equal(worktreeSettings.worktreeDefaults(config, 'env-1').branchNamingMode, undefined);
  assert.equal(projectWorktreeSettings.projectWorktreeSettings(config, 'env-1', 'p1').supported, true);
  assert.equal(worktreeStorage.worktreeStorage(config, 'env-1').environmentId, 'env-1');
  assert.equal(autoSettle.autoSettleSettings(config, 'env-1').fields.length, 3);
  assert.equal(threadDefaults.threadDefaults(config, 'env-1').fields.length, 4);
  assert.equal(draftDefaults.resolveDraftDefaults(config, 'env-1', { id: 'p1', workspaceRoot: '/w' }).workspace.mode, 'local');

  const accounts = usage.usageAccounts(config);
  assert.equal(accounts.length, 2);
  assert.equal(accounts[0].windows.length, 1);
  const pooled = usage.collectPooledLimitAccounts([{ environmentId: 'env-1', label: 'Mac', config }]);
  assert.equal(pooled.length, 2);
  assert.equal(pooled[0].resetCredits.options.length, 1);

  const summary = usage.parseUsageSummary({
    contractVersion: 6,
    readAt: '2026-11-22T00:00:00Z',
    pricing: { status: 'future_pricing_enum' },
    sources: [{ status: 'future_source_enum' }, null, { noStatus: true }],
    buckets: [{
      day: '2026-11-22',
      provider: 'future_provider_enum',
      model: 'future-1',
      totals: { uncachedInputTokens: 10, cachedInputTokens: 0, cacheCreationTokens: 0, outputTokens: 5, reasoningTokens: 0 },
      costUsd: 0.01,
      unpricedRecords: 0
    }]
  });
  assert.equal(summary.sources.length, 1);
  assert.equal(summary.buckets[0].provider, 'future_provider_enum');
});

test('ScheduledTasks, R4, R5, and Files drop invalid/unknown array elements without failing the whole response', () => {
  const validTask = {
    id: 'task-1', title: 'Daily', prompt: 'Check status', enabled: true,
    schedule: { type: 'interval', everyMs: 60000 }, projectId: 'p1', threadId: null,
    workspaceStrategy: { type: 'root' }, modelSelection: { instanceId: 'codex', model: 'gpt-6' },
    runtimeMode: 'approval-required', interactionMode: 'default',
    updatedAt: '2026-11-22T00:00:00Z', lastRunStatus: 'idle'
  };
  const snap = scheduledTasks.scheduleSnapshot({
    timeZone: 'Asia/Shanghai',
    tasks: [validTask, null, { id: 'future-task', enabled: 'yes' }, validTask]
  });
  assert.equal(snap.tasks.length, 1);
  assert.equal(snap.tasks[0].id, 'task-1');

  assert.equal(r4.branches({ refs: [{ name: 'main', current: true }, null, { bad: 1 }] }).length, 1);
  assert.equal(r4.subagents([{ id: 's1', status: 'running' }, { id: 'bad' }]).length, 1);
  assert.equal(r4.proposedPlans([{ type: 'proposed_plan', id: 'pl1', markdown: '# Hi', status: 'ready' }, { type: 'proposed_plan', id: 'bad' }]).length, 1);
  assert.equal(r4.backgroundTasks({ pendingBackgroundTasks: [{ taskId: 'bg1', kind: 'command' }, null] }).length, 1);

  const prRows = r5.pullRequestRows({
    entries: [
      {
        provider: 'github', host: 'github.com', projectId: 'p1', projectTitle: 'P1', repository: 'org/repo',
        number: 42, title: 'Fix', url: 'https://github.com/org/repo/pull/42',
        headBranch: 'fix', baseBranch: 'main', state: 'open',
        labels: [{ name: 'bug' }, null, { noName: true }]
      },
      null,
      { number: 99 }
    ],
    errors: [{ message: 'rate limited' }, null],
    providers: [{ kind: 'github', host: 'github.com', configured: true, detail: null }, { bad: true }]
  });
  assert.equal(prRows.rows.length, 1);
  assert.deepEqual(prRows.rows[0].labels, ['bug']);
  assert.equal(prRows.errors.length, 1);
  assert.equal(prRows.providers.length, 1);

  const detail = r5.pullRequestDetail({
    number: 42, title: 'Fix', url: 'https://github.com/org/repo/pull/42', state: 'open',
    repository: 'org/repo', projectId: 'p1', headBranch: 'fix', baseBranch: 'main',
    additions: 1, deletions: 0, changedFiles: 1,
    capabilities: { mergeMethods: ['squash', 123], review: { verdicts: ['approve', null], inlineComment: true } },
    viewerPermissions: { actions: ['merge', false], comment: true },
    checks: [{ name: 'CI', status: 'pass' }, null],
    reviewers: [{ login: 'alice' }, null],
    labels: [{ name: 'p0' }, null],
    comments: [{ id: 'c1', author: { login: 'bob' }, body: 'ok' }, null],
    reviewThreads: [{ id: 'rt1', path: 'a.ts', resolved: false, comments: [{ id: 'rc1', body: 'nit' }, null] }, null],
    commits: [{ sha: 'abc', subject: 'init' }, null]
  });
  assert.deepEqual(detail.mergeMethods, ['squash']);
  assert.deepEqual(detail.actions, ['merge']);
  assert.deepEqual(detail.reviewVerdicts, ['approve']);
  assert.equal(detail.checks.length, 1);
  assert.equal(detail.activity.comments.length, 1);
  assert.equal(detail.activity.threads[0].comments.length, 1);

  const entries = files.workspaceEntries({
    entries: [
      { path: 'src/index.ts', kind: 'file' },
      { path: 'vendor/sub', kind: 'submodule' },
      { path: '../escape.txt', kind: 'file' },
      null
    ]
  });
  assert.equal(entries.length, 1);
  assert.equal(entries[0].path, 'src/index.ts');
});

test('Security boundaries stay strictly fail-closed on invalid pairing, descriptor, environment directory, and peer links', () => {
  assert.throws(() => validateDescriptor({ environmentId: 'e', label: 'L', serverVersion: '1', orchestrationProtocolVersion: 3 }));
  assert.throws(() => environment.environmentDirectory({
    schemaVersion: 2, generation: 1, selectedLocalId: '',
    entries: [{ localId: 'a', environmentId: 'e', base: 'https://a', label: 'A', enabled: true, kind: 'unknown', credentialRef: 't3-v2-a-session', recovery: [] }]
  }));
  assert.throws(() => environment.savedSession({ base: 'https://a', environmentId: 'e', token: 't', expiresAt: 1, extra: 'bad' }));
  assert.throws(() => core.peerLinkViews({ links: [{ environmentId: 'p', label: 'P', status: 'future', expiresAt: new Date().toISOString(), lastError: null }] }));
});
