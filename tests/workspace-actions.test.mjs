import test from 'node:test';
import assert from 'node:assert/strict';
import { workspaceUrl } from './load-workspace.mjs';
import { projectsUrl } from './load-projects.mjs';

let serial = 0;
globalThis.__workspaceKit = { util: { generateRandomUUID: () => 'id-' + (++serial) } };
const { WorkspaceActions } = await import(workspaceUrl);
const P = await import(projectsUrl);

const thread = (extra = {}) => ({
  ...P.threadView({ id: 't', projectId: 'p', title: 'Thread', createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-02T00:00:00.000Z', latestUserMessageAt: '2026-01-02T00:00:00.000Z', status: 'idle', ...extra }),
  localId: 'a', environmentId: 'env-a', environmentLabel: 'A', projectLabel: 'Repo'
});
const project = (extra = {}) => ({
  ...P.projectView({ id: 'p', title: 'Repo', workspaceRoot: '/work/repo', createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-02T00:00:00.000Z', ...extra }),
  localId: 'a', environmentId: 'env-a', environmentLabel: 'A', isScratch: false
});

function setup(options = {}) {
  const calls = [];
  const client = {
    ready: true, supports: () => options.supported !== false, scratchWorkspaceRoot: '',
    async dispatchCommand(command) {
      calls.push(command);
      if (options.failDispatch) throw new Error(options.failDispatch);
      if (options.waitDispatch) await options.waitDispatch;
      return { sequence: 1 };
    },
    async projectMutate(command) { calls.push(command); return {}; },
    async startProjectClone(payload) { calls.push({ tag: 'clone', ...payload }); return {}; },
    async publishRepository(payload) { calls.push({ tag: 'publish', ...payload }); return {}; },
    async createProjectFromThread(threadId) { calls.push({ tag: 'into-project', threadId }); return { projectId: 'p' }; },
    async createNewProject(name) { calls.push({ tag: 'new-project', name }); return { projectId: 'created', workspaceRoot: '/work/new/' + name }; },
    async ensureScratch() { calls.push({ tag: 'scratch' }); return { projectId: 'scratch' }; },
    shell: { projects: [], threads: [] }
  };
  const registry = { directory: { entries: [{ localId: 'a', environmentId: 'env-a', label: 'A', deleting: false, pendingBase: '' }] },
    clients: new Map([['a', client]]), entryVisible: () => true };
  return { actions: new WorkspaceActions(registry), calls, client };
}

test('thread actions dispatch the original command names and undo plans restore settle/pin/snooze state', async () => {
  const { actions, calls } = setup();
  const pinned = thread({ pinnedAt: '2026-01-03T00:00:00.000Z', pinOrderKey: 'd',
    snoozedUntil: new Date(Date.now() + 3600000).toISOString(), snoozedAt: '2026-01-02T00:00:00.000Z' });
  const undo = await actions.settle(pinned);
  assert.equal(calls[0].type, 'thread.settle');
  assert.equal(calls[0].threadId, 't');
  assert.deepEqual(undo.steps.map(step => step.action), ['unsettle', 'pin', 'snooze']);
  assert.equal(undo.steps[1].orderKey, 'd');
  await actions.pin(pinned, 'b');
  assert.equal(calls[1].type, 'thread.pin');assert.equal(calls[1].orderKey, 'b');
  await actions.unpin(pinned);assert.equal(calls[2].type, 'thread.unpin');
  await actions.archive(pinned);assert.equal(calls[3].type, 'thread.archive');
  await actions.snooze(pinned, new Date(Date.now() + 60000).toISOString());assert.equal(calls[4].type, 'thread.snooze');
  await actions.rename(pinned, 'New name');assert.equal(calls[5].type, 'thread.metadata.update');assert.equal(calls[5].title, 'New name');
  await actions.regenerateTitle(pinned);assert.equal(calls[6].regenerateTitle, true);
  await actions.setAutoSettle(pinned, false);assert.equal(calls[7].type, 'thread.auto-settle.set');assert.equal(calls[7].enabled, false);
});

test('project updates, deletion and thread-to-project use the R3 command contracts', async () => {
  const { actions, calls } = setup();
  const p = project();
  await actions.updateProjects([p], { pinned: true });
  assert.equal(calls[0].type, 'project.update');assert.equal(calls[0].projectId, 'p');assert.equal(calls[0].pinned, true);
  await actions.deleteProject(p);
  assert.equal(calls[1].type, 'project.delete');assert.equal(calls[1].force, true);
  await actions.turnIntoProject(thread());
  assert.equal(calls[2].tag, 'into-project');
});

test('failed modifying requests are not retried and report the unknown outcome', async () => {
  const { actions, calls } = setup({ failDispatch: '服务端拒绝请求或任务失败，请在现有 T3 客户端核对详情' });
  await assert.rejects(actions.archive(thread()), /结果未确认.*不会自动重试/);
  assert.equal(calls.length, 1);
  await new Promise(resolve => setTimeout(resolve, 30));
  assert.equal(calls.length, 1);
});

test('a pending action rejects a second press before sending another command', async () => {
  let release;
  const wait = new Promise(resolve => { release = resolve; });
  const { actions, calls } = setup({ waitDispatch: wait });
  const first = actions.archive(thread());
  await assert.rejects(actions.archive(thread()), /正在进行/);
  release();
  await first;
  assert.equal(calls.length, 1);
});

test('clone and publish payloads carry exact validated fields', async () => {
  const { actions, calls, client } = setup();
  const environment = { localId: 'a', environmentId: 'env-a', label: 'A', platform: 'darwin', baseDirectory: '/work',
    newProjectsRoot: '/work/new', scratchWorkspaceRoot: '/work/scratch', ghqCloneLayout: true, ready: true, client };
  const id = await actions.startClone(environment, 'https://github.com/org/repo.git', '/work/repo', 'Repo', 'project-1');
  assert.equal(id, 'project-1');
  assert.equal(calls[0].tag, 'clone');assert.equal(calls[0].remoteUrl, 'https://github.com/org/repo.git');
  assert.equal(calls[0].destinationPath, '/work/repo');
  await actions.publish(environment, '/work/repo', 'github', 'org/repo');
  assert.equal(calls[1].visibility, 'private');
  assert.equal(actions.newProjectPreview(environment, ''), '/work/new/project');
  assert.equal(actions.newProjectPreview(environment, 'My App'), '/work/new/my-app');
});

test('project writes use the currently registered client, not a stale panel client', async () => {
  const { actions, calls } = setup();
  const stale = {
    ready: true,
    async createNewProject() { throw new Error('stale client used'); },
    async projectMutate() { throw new Error('stale client used'); },
    async startProjectClone() { throw new Error('stale client used'); },
    async publishRepository() { throw new Error('stale client used'); }
  };
  const environment = { localId: 'a', environmentId: 'env-a', label: 'A', platform: 'darwin', baseDirectory: '/work',
    newProjectsRoot: '/work/new', scratchWorkspaceRoot: '', ghqCloneLayout: false, ready: true, client: stale };
  assert.equal((await actions.createNewProject(environment, 'Fresh')).projectId, 'created');
  await actions.createProject(environment, '/work/repo');
  await actions.startClone(environment, 'https://example.com/org/repo.git', '/work/repo', 'Repo');
  await actions.publish(environment, '/work/repo', 'github', 'org/repo');
  assert.deepEqual(calls.map(call => call.tag || call.type), ['new-project', 'project.create', 'clone', 'publish']);
});

test('auto-settle updates the visible thread immediately after the server accepts it', async () => {
  const { actions, client } = setup();
  const current = thread();
  const shellRow = { ...current };
  client.shell.threads = [shellRow];
  await actions.setAutoSettle(current, false);
  assert.match(current.autoSettleDisabledAt, /^\d{4}-\d{2}-\d{2}T/);
  assert.equal(shellRow.autoSettleDisabledAt, current.autoSettleDisabledAt);
  await actions.setAutoSettle(current, true);
  assert.equal(current.autoSettleDisabledAt, '');
  assert.equal(shellRow.autoSettleDisabledAt, '');
});
