import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { compile, composerUrl, data, projectsUrl, r4Url } from './load-core.mjs';
const component = await readFile(new URL('../entry/src/main/ets/components/ScheduledTasksPanel.ets', import.meta.url), 'utf8');
const helpers = component.slice(component.indexOf('export function scheduleWeekdaySelection'), component.indexOf('@Component'));
const { scheduleWeekdaySelection } = await import(data(compile(helpers)));
test('weekday chips preserve a day, toggle without duplicates and treat legacy empty as daily', () => {
  assert.equal(scheduleWeekdaySelection('1', 1), '1');
  assert.equal(scheduleWeekdaySelection('1,2', 1), '2');
  assert.equal(scheduleWeekdaySelection('1,3', 2), '1,2,3');
  assert.equal(scheduleWeekdaySelection('', 0), '1,2,3,4,5,6');
  let days = '0,1,2,3,4,5,6';
  for (let day = 0; day < 7; day++) days = scheduleWeekdaySelection(days, day);
  assert.equal(days, '6');
});

async function loadSchedulePanel() {
  const wire = JSON.stringify(new URL('../entry/src/main/ets/protocol/Wire.ts', import.meta.url).href);
  const protocol = await readFile(new URL('../entry/src/main/ets/protocol/ScheduledTasks.ts', import.meta.url), 'utf8');
  const providerSource = await readFile(new URL('../entry/src/main/ets/protocol/ProviderSettings.ts', import.meta.url), 'utf8');
  const providerUrl = data(compile(providerSource.replace("'./Wire'", wire)));
  const protocolUrl = data(compile(protocol.replace("'./Wire'", wire).replace("'./Composer'", JSON.stringify(composerUrl))
    .replace("'./R4'", JSON.stringify(r4Url)).replace("'./Projects'", JSON.stringify(projectsUrl))));
  const code = component.slice(component.indexOf('@Component'), component.indexOf('  build() {')) + '}';
  return (await import(data(compile(`
    import { record } from ${wire};
    import { validateTaskSettings } from ${JSON.stringify(composerUrl)};
    import { isListedThread } from ${JSON.stringify(projectsUrl)};
    import { providerCatalog } from ${JSON.stringify(providerUrl)};
    import { readScheduledTasks, mutateScheduledTask, scheduledTaskInput, scheduledTaskModelReplacementNeedsConfirmation,
      readScheduledWorkspaceOptions } from ${JSON.stringify(protocolUrl)};
    ${code.replace('@Component\nexport struct', 'export class').replace(/@(?:State|Prop)\s+|@Watch\([^)]*\)\s*/g, '')}
  `)))).ScheduledTasksPanel;
}

test('scheduled task UI preserves original model by default and only confirms valid explicit replacements', async () => {
  const ScheduledTasksPanel = await loadSchedulePanel();
  const panel = new ScheduledTasksPanel();
  panel.connection = {
    ready: true, canScope: () => true, supports: () => false, generationValue: () => 1,
    config: { providers: [{ instanceId:'p', installed:true, enabled:true, models:[{ slug:'a' },{ slug:'b' }] }] },
    shell: { threads: [{ id:'thread', providerInstanceId:'p', model:'b' }] },
  };
  panel.needsRefresh = false;
  panel.loadedOwner = panel.connection; panel.loadedGeneration = 1;
  panel.timeZone = 'Asia/Shanghai';
  panel.providers = [{ id:'p', name:'Provider', models:[{ id:'a',name:'Old' }, { id:'b',name:'New' }] }];
  const task = { id:'id', title:'task', prompt:'prompt', projectId:'project', enabled:false, threadId:null,
    workspaceStrategy:{ type:'root' }, runtimeMode:'approval-required', interactionMode:'default',
    schedule:{ type:'fixed_time', timeOfDay:'09:00' }, modelSelection:{ instanceId:'p', model:'a', options:[{ id:'effort', value:'high' }] } };
  panel.edit(task);
  assert.equal(panel.editingModel, false);
  panel.prepareSave();
  assert.deepEqual(panel.pending.modelSelection, task.modelSelection);
  assert.match(panel.modelConfirmation, /保留原模型及专属选项/);
  panel.edit(task);
  panel.editingModel = true;
  panel.model = 'other';
  panel.prepareSave();
  assert.equal(panel.confirmation, '');
  panel.model = 'b';
  panel.prepareSave();
  assert.deepEqual(panel.pending.modelSelection, { instanceId:'p', model:'b' });
  assert.equal(panel.pending.enabled, false);
  assert.match(panel.modelConfirmation, /原模型：Provider \/ Old\n新模型：Provider \/ New\n确认后将清除原模型的专属选项/);
  panel.edit({ ...task, threadId:'thread' });
  panel.editingModel = true; panel.model = 'b';
  panel.prepareSave();
  assert.deepEqual(panel.pending.modelSelection, task.modelSelection);
  assert.match(panel.modelConfirmation, /Provider \/ New\n任务继续使用绑定会话的当前模型/);
});

test('new scheduled targets are project-scoped, display the bound model and distinguish all modern modes', async () => {
  const ScheduledTasksPanel = await loadSchedulePanel();
  const panel = new ScheduledTasksPanel();
  let modern = true;
  const thread = (id, projectId, extra = {}) => ({ id, projectId, label: id, providerInstanceId: 'p', model: 'b',
    updatedAt: '2026-01-01', ...extra });
  panel.connection = {
    ready: true, canScope: () => true, supports: () => modern, generationValue: () => 1,
    config: { providers: [{ instanceId:'p', installed:true, enabled:true, models:[{ slug:'a' }] }] },
    shell: { threads: [thread('target', 'a'), thread('second', 'a', { updatedAt:'2025-12-01' }),
      thread('archived', 'a', { archivedAt:'old' }),
      thread('side', 'a', { lineageSideChat:true }), thread('other', 'b')] },
  };
  panel.needsRefresh = false; panel.timeZone = 'Asia/Shanghai';
  panel.loadedOwner = panel.connection; panel.loadedGeneration = 1;
  panel.alive = true; panel.activeLocalId = 'local'; panel.environmentId = 'env';
  panel.scopedProjects = [{ id:'a', localId:'local', environmentId:'env' }, { id:'b', localId:'local', environmentId:'env' }];
  panel.providers = [{ id:'p', models:[{ id:'a' }] }];
  panel.edit();
  panel.titleInput = 'new'; panel.prompt = 'task'; panel.instanceId = 'p'; panel.model = 'a';
  panel.selectProject(1);
  assert.deepEqual(panel.threadCandidates.map(row => row.id), ['target', 'second']);
  panel.selectThreadMode(2);
  panel.prepareSave();
  assert.equal(panel.pending.threadId, null);
  assert.equal(panel.pending.threadMode, 'fresh_session');
  assert.equal(panel.pending.enabled, false);
  assert.match(panel.targetConfirmation, /首次运行创建会话.*新上下文\n调度：09:00/);
  panel.connection.shell.threads = panel.connection.shell.threads.map(row =>
    row.id === 'second' ? { ...row, updatedAt:'2026-02-01' } : row);
  assert.equal(panel.threadOptions()[1].value, 'target');
  panel.selectThread(1);
  panel.prepareSave();
  assert.equal(panel.pending.threadId, 'target');
  assert.deepEqual(panel.pending.modelSelection, { instanceId:'p', model:'b' });
  assert.match(panel.targetConfirmation, /target.*新上下文/);
  assert.match(panel.modelConfirmation, /绑定会话的当前模型/);
  panel.confirmation = '';
  panel.connection.shell.threads = panel.connection.shell.threads.filter(row => row.id !== 'target');
  panel.selectThread(1);
  assert.equal(panel.draftThreadId, 'target');
  panel.prepareSave();
  assert.equal(panel.confirmation, '');
  assert.match(panel.error, /所选会话已不可用/);
  panel.selectProject(2);
  assert.equal(panel.draftThreadId, '');
  assert.equal(panel.draftThreadMode, 'new_thread');
  modern = false;
  panel.selectThread(1);
  panel.prepareSave();
  assert.equal(panel.pending.threadId, 'other');
  assert.equal(panel.pending.threadMode, undefined);
  assert.match(panel.targetConfirmation, /other.*继续同一会话/);
});

test('refreshing an editor cannot rebase unsaved values onto a newly read task', async () => {
  const method = component.slice(component.indexOf('  private requestRefresh()'), component.indexOf('  private async refresh()'));
  const { Editor, dialog } = await import(data(compile(`
    export let dialog;
    const AlertDialog = { show(value) { dialog = value; } };
    export class Editor {
      alive = true; editor = true; selected = { id: 'original' }; confirmation = 'upsert';
      busy = false; reads = 0; refresh() { this.reads++; }
      invalidateWorkspaceOptions() {}
      ${method}
    }
  `))).then(mod => ({ Editor: mod.Editor, dialog: () => mod.dialog }));
  const page = new Editor();
  page.requestRefresh();
  dialog().primaryButton.action();
  assert.equal(page.editor, true);
  assert.equal(page.reads, 0);
  page.selected = { id: 'different' };
  dialog().secondaryButton.action();
  assert.equal(page.reads, 0);
  page.requestRefresh();
  dialog().secondaryButton.action();
  assert.equal(page.editor, false);
  assert.equal(page.confirmation, '');
  assert.equal(page.reads, 1);
});

test('connection changes refresh the list but preserve editing and quarantine stale reads and writes', async () => {
  const ScheduledTasksPanel = await loadSchedulePanel();
  const panel = new ScheduledTasksPanel();
  const subscriptions = [];
  let rejectWrite;
  let allowed = true;
  const task = { id:'id', title:'task', prompt:'prompt', projectId:'p', enabled:false, threadId:null,
    workspaceStrategy:{ type:'root' }, runtimeMode:'approval-required', interactionMode:'default',
    schedule:{ type:'fixed_time', timeOfDay:'09:00' }, modelSelection:{ instanceId:'p', model:'m' },
    updatedAt:'2026-11-19T01:00:00Z', lastRunStatus:'never' };
  const connection = {
    ready: true, generation: 1, generationValue() { return this.generation; }, canScope: () => allowed,
    config: { environment:{ environmentId:'env' }, providers:[] }, shell: { projects:[] },
    watchRpcStream(_method, _payload, callback) { subscriptions.push(callback); return callback; }, stopRpcStream() {},
    async rpcRequest() { return new Promise((_resolve, reject) => { rejectWrite = reject; }); },
  };
  panel.connection = connection;
  const tick = () => new Promise(resolve => setImmediate(resolve));
  const snapshot = { tasks:[task], timeZone:'Asia/Shanghai' };
  panel.aboutToAppear();
  connection.ready = false; connection.generation++; panel.connectionChanged();
  assert.equal(panel.writable(), false);
  connection.ready = true; panel.connectionChanged();
  assert.equal(subscriptions.length, 2);
  subscriptions[0]({ tasks:[], timeZone:'UTC' });
  await tick();
  assert.equal(panel.busy, true);
  subscriptions[1](snapshot);
  await tick();
  assert.equal(panel.writable(), true);
  assert.equal(panel.tasks[0].id, task.id);
  allowed = false; panel.connectionChanged();
  subscriptions[2](snapshot); await tick();
  assert.equal(panel.writable(), false);
  allowed = true; panel.connectionChanged();
  subscriptions[3](snapshot); await tick();
  assert.equal(panel.writable(), true);
  panel.selected = panel.tasks[0];
  panel.prepareAction('delete');
  const write = panel.commit();
  subscriptions[4](snapshot); await tick();
  assert.equal(typeof rejectWrite, 'function');
  connection.generation++; panel.connectionChanged();
  rejectWrite(new Error('late write')); await write;
  assert.equal(panel.busy, true);
  assert.equal(panel.selected.id, task.id);
  subscriptions[5](snapshot); await tick();
  panel.edit(panel.tasks[0]); panel.titleInput = 'unsaved';
  panel.confirmation = 'upsert';
  connection.generation++; panel.connectionChanged();
  assert.equal(subscriptions.length, 6);
  assert.equal(panel.titleInput, 'unsaved');
  assert.equal(panel.confirmation, 'upsert');
  assert.match(panel.error, /表单已保留/);
  assert.equal(panel.writable(), false);
  panel.aboutToDisappear();
});

test('workspace editor uses scoped server candidates, drops stale project reads, and preserves untouched strategies', async () => {
  const ScheduledTasksPanel = await loadSchedulePanel();
  const panel = new ScheduledTasksPanel();
  const projects = [{ id:'a', workspaceRoot:'/repo-a' }, { id:'b', workspaceRoot:'/repo-b' }];
  const pending = new Map();
  const connection = {
    ready:true, generationValue:() => 1, canScope:() => true, supports:() => true,
    config: { environment:{ environmentId:'env' }, providers:[] }, shell: { threads:[], projects },
    watchRpcStream(_method, _payload, callback) {
      queueMicrotask(() => callback({ kind:'snapshot', snapshot:{ projects, threads:[] } }));
      return callback;
    },
    stopRpcStream() {},
    async rpcRequest(method, { cwd, query }) {
      assert.equal(method, 'vcs.listRefs');
      return new Promise(resolve => pending.set(query ? cwd + ':' + query : cwd, resolve));
    },
  };
  Object.assign(panel, { connection, environmentId:'env', activeLocalId:'local', alive:true, loadedOwner:connection, loadedGeneration:1,
    needsRefresh:false, scopedProjects: projects.map(project => ({ ...project, localId:'local', environmentId:'env' })) });
  const tick = () => new Promise(resolve => setImmediate(resolve));
  const options = (name, path) => ({ isRepo:true, nextCursor:null, refs:[{ name, isDefault:true, worktreePath:path }] });
  panel.edit();
  panel.selectProject(1); panel.selectWorkspace(1);
  await tick();
  panel.selectProject(2); panel.selectWorkspace(1);
  await tick();
  pending.get('/repo-a')(options('old', '/tmp/old'));
  await tick();
  assert.equal(panel.workspaceLoading, true);
  assert.equal(panel.workspaceOptions, undefined);
  pending.get('/repo-b')(options('main', '/tmp/current'));
  await tick();
  assert.deepEqual(panel.draftWorkspace(), { type:'worktree', baseRef:'main', startFromOrigin:true });
  panel.workspaceOrigin = false;
  assert.match(panel.workspaceSummary(panel.draftWorkspace()), /main.*本地分支/);
  panel.selectWorkspace(2);
  await tick();
  pending.get('/repo-b')(options('main', '/tmp/current'));
  await tick();
  panel.workspacePath = '/tmp/missing';
  assert.throws(() => panel.draftWorkspace(), /可用的工作树/);
  panel.selectWorkspacePath(1);
  assert.deepEqual(panel.draftWorkspace(), { type:'existing_worktree', worktreePath:'/tmp/current' });
  assert.match(panel.workspaceSummary(panel.draftWorkspace()), /\/tmp\/current/);
  panel.workspaceQuery = ' first ';
  const firstFilter = panel.loadWorkspaceOptions();
  await tick();
  panel.workspaceQuery = 'next';
  const nextFilter = panel.loadWorkspaceOptions();
  await tick();
  pending.get('/repo-b:first')(options('first', '/tmp/first'));
  await firstFilter;
  assert.equal(panel.workspaceLoading, true);
  assert.equal(panel.workspaceOptions, undefined);
  pending.get('/repo-b:next')(options('next', '/tmp/next'));
  await nextFilter;
  assert.equal(panel.workspaceAppliedQuery, 'next');
  assert.deepEqual(panel.workspaceOptions.checkoutPaths, ['/tmp/next']);
  assert.deepEqual(panel.draftWorkspace(), { type:'existing_worktree', worktreePath:'/tmp/current' });
  assert.equal(panel.workspaceRefHint, 'main');
  panel.draftThreadId = 'thread';
  assert.equal(panel.draftWorkspace(), undefined);
  panel.edit({ projectId:'b', threadId:'thread', modelSelection:{}, schedule:{},
    workspaceStrategy:{ type:'worktree', baseRef:'legacy', startFromOrigin:false } });
  assert.equal(panel.draftWorkspace(), undefined);
  assert.equal(panel.workspaceLabel(panel.selected), '绑定会话的工作区');
  panel.edit({ ...panel.selected, threadId:null });
  assert.equal(panel.draftWorkspace(), undefined);
  assert.equal(panel.workspaceLoading, true);
  await tick();
  panel.aboutToDisappear();
  pending.get('/repo-b')(options('main', '/tmp/current'));
  await tick();
  assert.equal(panel.workspaceLoading, false);
  assert.equal(panel.workspaceOptions, undefined);
});

test('late project snapshots unlock an open editor without rebasing the draft or Select identities', async () => {
  const ScheduledTasksPanel = await loadSchedulePanel();
  const panel = new ScheduledTasksPanel();
  const connection = { ready:true, generationValue:() => 1, canScope:() => true, shell:{ threads:[] } };
  Object.assign(panel, { connection, environmentId:'env', activeLocalId:'local', alive:true, loadedOwner:connection,
    loadedGeneration:1, needsRefresh:false });
  panel.edit();
  panel.titleInput = 'unsaved title'; panel.prompt = 'unsaved prompt';
  assert.deepEqual(panel.projectOptions().map(option => option.value), ['请选择项目']);
  const first = { localId:'local', environmentId:'env', id:'first', label:'First' };
  const second = { localId:'local', environmentId:'env', id:'second', label:'Second' };
  panel.scopedProjects = [{ ...first, localId:'different', label:'Other env' },
    { ...first, environmentId:'wrong', label:'Wrong identity' }, first, second];
  panel.projectsChanged();
  assert.deepEqual(panel.projectOptions().map(option => option.value), ['请选择项目', 'First', 'Second']);
  panel.scopedProjects = [second, first];
  panel.projectsChanged();
  panel.selectProject(1);
  assert.equal(panel.projectId, first.id);
  panel.scopedProjects = [second];
  panel.projectsChanged();
  assert.deepEqual(panel.projectOptions().map(option => option.value), ['请选择项目', 'First（不可用）', 'Second']);
  panel.selectProject(1);
  assert.equal(panel.projectId, first.id);
  assert.match(panel.error, /不可用/);
  assert.equal(panel.titleInput, 'unsaved title');
  assert.equal(panel.prompt, 'unsaved prompt');
  assert.equal(panel.editor, true);
});
