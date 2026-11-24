import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  agentFeedbackUrl,
  compile,
  composerUrl,
  data,
  linkedThreadUrl,
  markdownLinksUrl,
  r4Url,
  serverClockUrl,
  threadItemsUrl
} from './load-core.mjs';

const wireUrl = new URL('../entry/src/main/ets/protocol/Wire.ts', import.meta.url).href;
const Wire = await import(wireUrl);
const ServerClock = await import(serverClockUrl);
const AgentFeedback = await import(agentFeedbackUrl);
const LinkedThread = await import(linkedThreadUrl);
const ThreadItems = await import(threadItemsUrl);
const Composer = await import(composerUrl);
const R4 = await import(r4Url);
const MarkdownLinks = await import(markdownLinksUrl);

const labsSource = (await readFile(new URL('../entry/src/main/ets/protocol/LabsSettings.ts', import.meta.url), 'utf8'))
  .replace("'./Wire'", JSON.stringify(wireUrl))
  .replace("'./AgentFeedback'", JSON.stringify(agentFeedbackUrl))
  .replace("import { WorktreeSettingsConnection } from './WorktreeSettings';", '');
const LabsSettings = await import(data(compile(labsSource)));

test('ServerClock computes midpoint offset and raises stale negative offset after sleep catch-up', () => {
  ServerClock.resetAllServerClocks();
  assert.equal(ServerClock.serverClockOffset('env_1'), 0);

  // Client sent at 1000, received at 1100 (midpoint 1050), server clock was 1050 - 5000 = -3950 -> offset -5000ms.
  const baseClient = Date.parse('2026-06-01T10:00:10.000Z');
  const serverIso = new Date(baseClient - 5000 + 50).toISOString();
  ServerClock.recordServerClock('env_1', serverIso, baseClient, baseClient + 100);
  assert.equal(ServerClock.serverClockOffset('env_1'), -5000);
  assert.equal(ServerClock.serverNowMs('env_1', baseClient + 1000), baseClient - 4000);

  // Older timestamp behind estimated server clock does not lower offset.
  ServerClock.observeServerTime('env_1', baseClient - 9000, baseClient + 1000);
  assert.equal(ServerClock.serverClockOffset('env_1'), -5000);

  // Newer server timestamp ahead of estimated server clock raises the stale negative offset.
  ServerClock.observeServerTime('env_1', baseClient + 800, baseClient + 1000);
  assert.equal(ServerClock.serverClockOffset('env_1'), -200);

  ServerClock.clearServerClock('env_1');
  assert.equal(ServerClock.serverClockOffset('env_1'), 0);
});

test('LinkedThread races candidate probes in priority order and parses unlink results', async () => {
  let slowFinished = false;
  const result = await LinkedThread.prepareLinkedEnvironmentConnection({
    environmentId: 'env-remote',
    label: 'Remote Mac',
    alreadyConnectedLocalId: '',
    requestPairing: async () => ({
      type: 'credential',
      environmentId: 'env-remote',
      label: 'Remote Mac',
      urls: ['https://lan.local:3773', 'https://relay.t3.codes/env-remote'],
      credential: 'ONE_TIME_CODE',
      expiresAt: '2026-06-01T12:00:00Z'
    }),
    reaches: async (url) => {
      if (url === 'https://lan.local:3773') return true;
      // Lower-priority URL hangs — higher-priority probe must resolve immediately!
      await new Promise((resolve) => {
        const t = setTimeout(() => { slowFinished = true; resolve(); }, 3000);
        t.unref?.();
      });
      return true;
    }
  });
  assert.equal(result.type, 'prefill');
  assert.equal(result.prefill.host, 'https://lan.local:3773');
  assert.equal(result.prefill.credential, 'ONE_TIME_CODE');
  assert.equal(slowFinished, false);

  const parsed = LinkedThread.parsePeerLinkRemoveResult({ removed: true, endedThere: false });
  assert.equal(parsed.removed, true);
  assert.equal(parsed.endedThere, false);
  assert.ok(LinkedThread.peerLinkRemoveMessage('Mac Studio', parsed).includes('已解除本地与「Mac Studio」的互链'));
  assert.ok(LinkedThread.peerLinkRemoveMessage('Mac Studio', { removed: true, endedThere: true }).includes('已结束对端会话'));
});

test('AgentFeedback parses items, formats display/payload, and integrates with LabsSettings', async () => {
  const items = [
    {
      id: 'fb_1',
      type: 'feedback_request',
      threadId: 'thr_1',
      feedbackStatus: 'pending',
      visibility: 'local',
      preview: {
        kind: 'bug',
        subject: 'MCP bridge timeout',
        expected: 'Fast response',
        actual: 'Tool call stalled after 30s',
        workaround: 'Restart session'
      }
    },
    {
      id: 'fb_2',
      type: 'feedback_request',
      threadId: 'thr_parent',
      feedbackStatus: 'pending',
      visibility: 'inherited',
      preview: {
        kind: 'confusing',
        subject: 'Inherited notice',
        expected: 'Clear label',
        actual: 'Ambiguous wording',
        workaround: ''
      }
    }
  ];
  const parsed = AgentFeedback.parseAgentFeedbackRequests(items, 'thr_1');
  assert.equal(parsed.length, 2);
  assert.equal(AgentFeedback.feedbackRequestDisplay(parsed[0]).kind, 'pending');
  assert.equal(AgentFeedback.feedbackRequestDisplay(parsed[1]).kind, 'pending-elsewhere');
  assert.equal(ThreadItems.visibleWorkItems(items).length, 0);

  const payload = AgentFeedback.agentFeedbackAnswerPayload('thr_1', 'fb_1', 'send', true);
  assert.deepEqual(payload, {
    threadId: 'thr_1',
    turnItemId: 'fb_1',
    answer: 'send',
    includeConversation: true
  });

  // Labs settings read & write agentFeedback mode.
  let storedMode = 'on-request';
  const conn = {
    ready: true,
    canScope: () => true,
    rpcRequest: async (method, params) => {
      if (method === 'server.updateSettings') {
        storedMode = params.patch.agentFeedback.mode;
        return {};
      }
      return {
        environment: { environmentId: 'env_1', capabilities: { agentFeedback: true, peerLinks: true } },
        settings: { linkedEnvironmentsEnabled: true, agentFeedback: { mode: storedMode } }
      };
    }
  };
  const initial = await LabsSettings.readLabsSettings(conn, 'env_1');
  assert.equal(initial.agentFeedback.value, 'on-request');
  const updated = await LabsSettings.writeAgentFeedbackMode(conn, 'env_1', 'auto');
  assert.equal(updated.agentFeedback.value, 'auto');
});

test('Wire keeps queued user message visible when cancelled after starting', () => {
  assert.equal(Wire.isHeldRun({ id: 'r1', status: 'queued' }), true);
  assert.equal(Wire.isHeldRun({ id: 'r2', status: 'cancelled' }), true);
  assert.equal(Wire.isHeldRun({ id: 'r3', status: 'cancelled', startedAt: '2026-01-01T00:00:00Z' }), false);

  const state = new Wire.ThreadState('thr_1');
  state.apply({
    kind: 'snapshot',
    snapshotSequence: 1,
    projection: {
      thread: { id: 'thr_1', title: 'T' },
      runs: [
        { id: 'r_q', status: 'queued', triggerMessageId: 'm_q' },
        { id: 'r_c', status: 'cancelled', triggerMessageId: 'm_c', startedAt: '2026-01-01T00:00:01Z' }
      ],
      messages: [
        { id: 'm_q', threadId: 'thr_1', runId: 'r_q', role: 'user', text: 'still queued', streaming: false, createdAt: '2026-01-01T00:00:00Z' },
        { id: 'm_c', threadId: 'thr_1', runId: 'r_c', role: 'user', text: 'started then cancelled', streaming: false, createdAt: '2026-01-01T00:00:01Z' }
      ],
      items: []
    }
  });
  const ids = state.messages.map(m => m.id);
  assert.equal(ids.includes('m_q'), false);
  assert.equal(ids.includes('m_c'), true);
});

test('ThreadItems maps Cursor granular startupPhase labels in live thinking row', () => {
  const row = ThreadItems.deriveLiveThinkingRow({
    draftMode: false,
    threadSynced: true,
    isStopping: false,
    isCompacting: false,
    pendingActionCount: 0,
    messages: [],
    tailGroup: undefined,
    runs: [{ id: 'run_1', ordinal: 1, status: 'starting', providerInstanceId: 'inst_cursor' }],
    details: {},
    nodes: [],
    items: [],
    providerTurns: [],
    providerSessions: [{ providerInstanceId: 'inst_cursor', startupPhase: 'plugins' }],
    configProviders: [{ id: 'inst_cursor', driver: 'cursor', label: 'Cursor' }],
    fallbackProviderDriver: 'cursor',
    hasPendingBackgroundWork: false,
    hasWorktreeSetupCard: false
  });
  assert.equal(row.visible, true);
  assert.equal(row.label, '正在加载 Cursor 插件…');
  assert.equal(ThreadItems.providerStartingPhaseLabel('mcp', 'Cursor'), '正在启动 Cursor MCP 服务…');
  assert.equal(ThreadItems.providerStartingPhaseLabel('connecting', 'Cursor'), '正在连接 Cursor…');
});

test('Composer formats @-file mentions cleanly and manages model favorites', () => {
  assert.equal(
    Composer.formatMentionPreviewText('Fix [index.ts](src/index.ts) and [Docs](https://example.com)'),
    'Fix @index.ts and [Docs](https://example.com)'
  );
  assert.equal(
    Composer.formatMentionPreviewText('Check [@README.md](README.md)'),
    'Check @README.md'
  );

  const favs = Composer.parseModelFavorites({
    settings: { favorites: [{ provider: 'claude', model: 'sonnet' }, { provider: 'claude', model: 'sonnet' }] }
  });
  assert.equal(favs.length, 1);
  assert.equal(Composer.serverHasModelFavorites({ settings: { favorites: null } }), false);
  assert.equal(Composer.serverHasModelFavorites({ settings: { favorites: [] } }), true);

  const patch = Composer.modelFavoriteUpdatePatch(
    'claude',
    'sonnet',
    true,
    [{ provider: 'codex', model: 'gpt-5' }],
    { settings: { favorites: null } }
  );
  assert.deepEqual(patch.setModelFavorites, [{ provider: 'claude', model: 'sonnet', favorite: true }]);
  assert.equal(patch.migrateModelPreferences.favorites.length, 1);
});

test('R4 bounds overly long attachment filenames while keeping extension', () => {
  const longName = 'a'.repeat(300) + '.png';
  const bounded = R4.boundAttachmentFileName(longName);
  assert.ok(bounded.length <= R4.BOUNDED_ATTACHMENT_FILENAME_MAX);
  assert.ok(bounded.endsWith('.png'));
});

test('MarkdownLinks detects ambiguous cross-project basename matches and preserves special-char paths', () => {
  const unique = MarkdownLinks.pickProjectLinkMatch('Button.ets', [
    { root: '/repo', entries: [{ path: 'src/Button.ets', kind: 'file' }] }
  ]);
  assert.equal(unique, '/repo/src/Button.ets');

  const ambiguous = MarkdownLinks.pickProjectLinkMatch('index.ts', [
    { root: '/repo', entries: [{ path: 'a/index.ts', kind: 'file' }, { path: 'b/index.ts', kind: 'file' }] }
  ]);
  assert.equal(ambiguous, undefined);

  const exact = MarkdownLinks.pickProjectLinkMatch('b/index.ts', [
    { root: '/repo', entries: [{ path: 'a/index.ts', kind: 'file' }, { path: 'b/index.ts', kind: 'file' }] }
  ]);
  assert.equal(exact, '/repo/b/index.ts');

  // Special chars like # ? & ' , % ! ~ inside workspace file links
  const parsed = MarkdownLinks.parseMarkdownFileLink('/repo/docs/guide%20%231%3Fv=2!~a\'b,c.md');
  assert.ok(parsed !== undefined);
  const resolved = MarkdownLinks.resolveFileLinkForWorkspace('/repo', parsed);
  assert.ok(resolved !== undefined);
});
