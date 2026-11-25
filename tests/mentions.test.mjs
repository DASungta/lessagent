import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { composerUrl, mentionsUrl, r4Url } from './load-core.mjs';

const mentions = await import(mentionsUrl);
const r4 = await import(r4Url);
const composer = await import(composerUrl);

function makeThread(overrides = {}) {
  return {
    localId: 'loc-a',
    environmentId: 'env-a',
    environmentLabel: 'ca02',
    projectLabel: 'Work',
    id: 'th-1',
    label: '修复登录闪退',
    projectId: 'p-1',
    providerInstanceId: 'codex',
    model: 'gpt-5',
    interactionMode: 'default',
    creationSource: 'mobile',
    branch: 'main',
    worktreePath: '',
    status: 'idle',
    activityRunStatus: '',
    activityRunStartedAt: '',
    blockedOnThreadWait: false,
    activeRunId: '',
    latestRunId: '',
    latestRunRequestedAt: '',
    latestRunStartedAt: '',
    latestRunCompletedAt: '',
    lastError: '',
    lastErrorClass: '',
    createdAt: '2026-11-20T10:00:00Z',
    updatedAt: '2026-11-25T10:00:00Z',
    archivedAt: '',
    settledOverride: '',
    settledAt: '',
    unsettledAt: '',
    snoozedUntil: '',
    snoozedAt: '',
    pinnedAt: '',
    pinOrderKey: '',
    activeOrderKey: '',
    autoSettleDisabledAt: '',
    latestUserMessageAt: '2026-11-25T10:00:00Z',
    latestUserAuthoredMessageAt: '2026-11-25T10:00:00Z',
    lastVisitedAt: '',
    pendingKind: '',
    pendingAt: '',
    pendingUserOnly: false,
    pendingGuestMessageCount: 0,
    hasActionableProposedPlan: false,
    titleRegenerationRequestId: '',
    titleRegenerationStartedAt: '',
    lineageRelationship: '',
    lineageParentThreadId: '',
    lineageSideChat: false,
    lineageWorkflowStep: false,
    delegatedFromEnvironmentId: '',
    delegatedFromThreadId: '',
    lastSnoozeWakeAt: '',
    pendingBackgroundTasks: [],
    goal: undefined,
    deletedAt: '',
    ...overrides
  };
}

test('detectInlineMentionTrigger detects @ queries and ignores emails', () => {
  assert.deepEqual(mentions.detectInlineMentionTrigger('@', 1), {
    kind: 'mention', query: '', rangeStart: 0, rangeEnd: 1
  });
  assert.deepEqual(mentions.detectInlineMentionTrigger('参考 @登录', 6), {
    kind: 'mention', query: '登录', rangeStart: 3, rangeEnd: 6
  });
  assert.deepEqual(mentions.detectInlineMentionTrigger('先看 @src/app 后面继续', 11), {
    kind: 'mention', query: 'src/app', rangeStart: 3, rangeEnd: 11
  });
  assert.equal(mentions.detectInlineMentionTrigger('联系 user@example.com 确认', 20), undefined);
  assert.equal(mentions.detectInlineMentionTrigger('没有触发词', 5), undefined);
  assert.deepEqual(mentions.replaceTextRange('参考 @登录 继续', 3, 6, ''), {
    text: '参考  继续', cursor: 3
  });
});

test('composeMessageWithContexts injects missing t3-context references so server expands all records', () => {
  const threadRec = mentions.deterministicThreadContext('env-a', 'th-42', '修复 [登录]\n闪退');
  assert.equal(threadRec.kind, 'thread');
  assert.equal(threadRec.contextId, 'thread_th-42');
  assert.equal(threadRec.label, '修复 登录 闪退');
  assert.equal(threadRec.payload.threadId, 'th-42');
  assert.equal(threadRec.payload.environmentId, 'env-a');

  const envRec = mentions.deterministicEnvironmentContext('env-b', 'Mac Studio');
  assert.equal(envRec.kind, 'environment');
  assert.equal(envRec.contextId, 'environment_env-b');
  assert.equal(envRec.payload.environmentId, 'env-b');

  const fileRec = mentions.deterministicFileContext('src/app.ts');
  assert.equal(fileRec.kind, 'mention');
  assert.equal(fileRec.payload.path, 'src/app.ts');

  // Appends missing references without disturbing leading slash commands
  const composed = mentions.composeMessageWithContexts('/review 请参考一下', [threadRec, envRec, fileRec]);
  assert.ok(composed.text.startsWith('/review 请参考一下\n\n'));
  assert.ok(composed.text.includes('[修复 登录 闪退](t3-context://v1/thread/thread_th-42)'));
  assert.ok(composed.text.includes('[Mac Studio](t3-context://v1/environment/environment_env-b)'));
  assert.ok(composed.text.includes('[src/app.ts](t3-context://v1/mention/' + fileRec.contextId + ')'));

  // Does not duplicate references already present in prompt text
  const already = mentions.composeMessageWithContexts(
    '结合 [修复 登录 闪退](t3-context://v1/thread/thread_th-42) 继续排查',
    [threadRec, envRec]
  );
  assert.equal(already.text.split('t3-context://v1/thread/thread_th-42').length - 1, 1);
  assert.ok(already.text.includes('t3-context://v1/environment/environment_env-b'));

  // Context-only message still yields valid non-empty wire text and readable provisional title
  const contextOnly = mentions.composeMessageWithContexts('', [threadRec]);
  assert.equal(contextOnly.text, '[修复 登录 闪退](t3-context://v1/thread/thread_th-42)');
  const launch = composer.launchTask(
    'c1', 't-new', 'm1', 'p1', contextOnly.text,
    { modelSelection: { instanceId: 'codex', model: 'gpt-5' }, runtimeMode: 'auto', interactionMode: 'default' },
    [],
    r4.contextPayload(contextOnly.context)
  );
  assert.equal(launch.title, '@修复 登录 闪退');
  assert.equal(launch.initialMessage.context.records[0].kind, 'thread');
});

test('matchMentionThreads enforces Android eligibility, linked environments, side chats, and ranking', () => {
  const threads = [
    makeThread({ id: 'self', label: '当前会话', updatedAt: '2026-11-25T12:00:00Z' }),
    makeThread({ id: 't-local', label: '登录态续期排查', projectLabel: 'LessAgent', updatedAt: '2026-11-25T11:00:00Z' }),
    makeThread({ id: 't-older', label: '旧任务列表优化', updatedAt: '2026-11-24T10:00:00Z' }),
    makeThread({ id: 't-linked', environmentId: 'env-remote', environmentLabel: 'vps-prod', label: '登录网关配置', updatedAt: '2026-11-25T09:00:00Z' }),
    makeThread({ id: 't-unlinked', environmentId: 'env-other', environmentLabel: 'other', label: '登录测试（未关联环境）', updatedAt: '2026-11-25T11:50:00Z' }),
    makeThread({ id: 't-archived', label: '已归档登录会话', archivedAt: '2026-11-25T11:30:00Z' }),
    makeThread({ id: 't-subagent', label: '子智能体登录', lineageRelationship: 'subagent' }),
    makeThread({ id: 't-own-side', label: '当前会话侧聊登录', lineageSideChat: true, lineageParentThreadId: 'self', latestUserMessageAt: '2026-11-25T11:40:00Z' }),
    makeThread({ id: 't-empty-side', label: '空侧聊登录', lineageSideChat: true, lineageParentThreadId: 'self', latestUserMessageAt: '' }),
    makeThread({ id: 't-other-side', label: '别人侧聊登录', lineageSideChat: true, lineageParentThreadId: 't-older', latestUserMessageAt: '2026-11-25T11:45:00Z' })
  ];

  // Empty query returns empty when allowEmptyQuery=false, or recent eligible threads when true
  assert.deepEqual(
    mentions.matchMentionThreads({
      threads, currentEnvironmentId: 'env-a', linkedEnvironmentLabels: { 'env-remote': 'VPS' },
      excludeThreadId: 'self', query: '', allowEmptyQuery: false
    }),
    []
  );

  const recent = mentions.matchMentionThreads({
    threads, currentEnvironmentId: 'env-a', linkedEnvironmentLabels: { 'env-remote': 'VPS' },
    excludeThreadId: 'self', query: '', allowEmptyQuery: true, limit: 10
  });
  assert.deepEqual(recent.map((item) => item.threadId), ['t-own-side', 't-local', 't-linked', 't-older']);
  assert.equal(recent[0].description, '侧聊');
  assert.equal(recent[1].description, '会话 · LessAgent');
  assert.equal(recent[2].description, '会话 · VPS');

  // Query filters and ranks title prefix above substring
  const queried = mentions.matchMentionThreads({
    threads, currentEnvironmentId: 'env-a', linkedEnvironmentLabels: { 'env-remote': 'VPS' },
    excludeThreadId: 'self', query: '登录', allowEmptyQuery: true
  });
  assert.deepEqual(queried.map((item) => item.threadId), ['t-local', 't-linked', 't-own-side']);
});

test('matchMentionEnvironments and matchMentionModels align with upstream rules', () => {
  const envsOff = mentions.matchMentionEnvironments({
    environments: [{ environmentId: 'env-a', label: 'ca02' }, { environmentId: 'env-b', label: 'Mac Mini' }],
    linkedEnvironmentLabels: { 'env-c': 'Linux VPS' },
    currentEnvironmentId: 'env-a',
    offersLinkedEnvironments: false,
    query: 'mac'
  });
  assert.deepEqual(envsOff, []);

  const envsOn = mentions.matchMentionEnvironments({
    environments: [{ environmentId: 'env-a', label: 'ca02' }, { environmentId: 'env-b', label: 'Mac Mini' }],
    linkedEnvironmentLabels: { 'env-b': 'Mac Mini', 'env-c': 'Linux VPS' },
    currentEnvironmentId: 'env-a',
    offersLinkedEnvironments: true,
    query: '',
    allowEmptyQuery: true
  });
  assert.deepEqual(envsOn.map((item) => item.environmentId), ['env-b', 'env-c']);

  const config = {
    providers: [
      {
        instanceId: 'codex', driver: 'codex', displayName: 'Codex', installed: true, enabled: true, status: 'ready',
        auth: { status: 'authenticated' },
        models: [
          { slug: 'gpt-5.4', name: 'GPT-5.4' },
          { slug: 'gpt-legacy', name: 'GPT Legacy', legacy: true },
          { slug: 'gpt-hidden', name: 'GPT Hidden', hidden: true }
        ]
      },
      {
        instanceId: 'signed-out', driver: 'claudeAgent', installed: true, enabled: true, status: 'ready',
        auth: { status: 'unauthenticated' },
        models: [{ slug: 'claude-4', name: 'Claude 4' }]
      }
    ]
  };
  const candidates = mentions.extractMentionModelCandidates(config, []);
  assert.equal(candidates.length, 1);
  assert.deepEqual(mentions.matchMentionModels(candidates, 'g'), []);
  const matched = mentions.matchMentionModels(candidates, 'gpt');
  assert.equal(matched.length, 1);
  assert.equal(mentions.formatComposerModelMention(matched[0].instanceId, matched[0].model), 'model:codex/gpt-5.4');
});

test('mentionFileItems preserves server fuzzy entries and splits basename/dir cleanly', () => {
  const items = mentions.mentionFileItems([
    { path: 'entry/src/main/ets/components/ComposerCommandPanel.ets', kind: 'file' },
    { path: 'entry/src/main/ets/protocol', kind: 'directory' }
  ]);
  assert.equal(items[0].label, 'ComposerCommandPanel.ets');
  assert.equal(items[0].description, 'entry/src/main/ets/components');
  assert.equal(items[0].fileKind, 'file');
  assert.equal(items[1].label, 'protocol');
  assert.equal(items[1].fileKind, 'directory');
});

test('UI wiring includes threads/environments/models/files in both mentions sheet and inline @ popover', async () => {
  const indexSource = await readFile(new URL('../entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
  const panelSource = await readFile(new URL('../entry/src/main/ets/components/ComposerCommandPanel.ets', import.meta.url), 'utf8');
  const clientSource = await readFile(new URL('../entry/src/main/ets/services/T3Client.ets', import.meta.url), 'utf8');
  const mdSource = await readFile(new URL('../entry/src/main/ets/components/MarkdownView.ets', import.meta.url), 'utf8');

  assert.match(panelSource, /搜索会话、环境、模型或文件/);
  assert.match(panelSource, /mentionThreads/);
  assert.match(panelSource, /mentionEnvironments/);
  assert.match(panelSource, /mentionModels/);
  assert.match(indexSource, /ComposerMentionPopover\(\{/);
  assert.match(indexSource, /onTextSelectionChange/);
  assert.match(indexSource, /parseComposerContextHref/);
  assert.match(clientSource, /composeMessageWithContexts/);
  assert.match(mdSource, /span\.href\.startsWith\('t3-context:\/\/'\)[\s\S]*?onOpenLink/);
});
