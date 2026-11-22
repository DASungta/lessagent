import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { compile, data, composerUrl, r4Url, projectsUrl } from './load-core.mjs';
const source = (await readFile(new URL('../entry/src/main/ets/protocol/ScheduledTasks.ts', import.meta.url),'utf8')).replace("'./Wire'", JSON.stringify(new URL('../entry/src/main/ets/protocol/Wire.ts', import.meta.url).href))
  .replace("'./Composer'", JSON.stringify(composerUrl))
  .replace("'./R4'", JSON.stringify(r4Url)).replace("'./Projects'", JSON.stringify(projectsUrl));
const api = await import(data(compile(source)));
const task={id:'task-1',title:'A',prompt:'B',enabled:false,schedule:{type:'interval',everyMs:60000},projectId:'p',threadId:null,workspaceStrategy:{type:'root'},modelSelection:{instanceId:'codex',model:'m',options:{effort:'high'}},runtimeMode:'approval-required',interactionMode:'default',updatedAt:'2026-11-19T01:00:00Z',nextRunAt:null,lastRunStatus:'never'};
const draft={title:'A',prompt:'B',projectId:'p',instanceId:'codex',model:'m',type:'interval',time:'09:00',weekdays:'1,2,3',minutes:'1'};
function fixture(rows=[task]) {
  let tasks=structuredClone(rows);const calls=[];let stopped=0;
  return {ready:true,generation:1,generationValue(){return this.generation},config:{environment:{environmentId:'e'},
    providers:[{instanceId:'other',installed:true,enabled:true,models:[{slug:'new'}]}]},canScope:()=>true,calls,
    get stopped(){return stopped},replaceTasks(value){tasks=structuredClone(value)},
    watchRpcStream(method,payload,cb){calls.push(method);queueMicrotask(()=>cb({tasks,timeZone:'Asia/Shanghai'}));return cb},stopRpcStream(){stopped++},
    async rpcRequest(method,payload){calls.push(method);if(method==='server.getConfig')return this.config;if(method==='scheduledTasks.delete'){tasks=[];return {id:payload.id}} tasks=[{...task,...payload}];return {task:tasks[0]};}
  };
}
test('schedule contract rejects cron, impossible dates, unknown zone and invalid intervals',()=>{
  assert.deepEqual(api.scheduleFromFields('fixed_time','09:00','1,1,0',''),{type:'fixed_time',timeOfDay:'09:00',weekdays:[0,1]});
  assert.equal(api.scheduleFromFields('fixed_time','9:00','1','').timeOfDay,'09:00');
  for(const args of [['cron','* * * * *','',''],['fixed_time','24:00','1',''],['fixed_time','09:00','',''],['interval','','','0.5'],['once','2027-02-30T09:00:00+08:00','',''],['once','2027-02-28T09:00:00','','']]) assert.throws(()=>api.scheduleFromFields(...args));
  assert.equal(api.scheduleFromFields('once','2027-02-28T09:00:00+08:00','','').runAt,'2027-02-28T01:00:00.000Z');
  assert.throws(()=>api.scheduledTaskInput({...draft,type:'fixed_time'},''));
});
test('create is disabled; edits preserve target, workspace, model options and require existing',()=>{
  const created=api.scheduledTaskInput(draft,'Asia/Shanghai');assert.equal(created.enabled,false);assert.equal(created.runtimeMode,'approval-required');assert.equal(created.threadId,null);
  const original={...task,enabled:true,threadId:'thread',threadMode:'fresh_session',workspaceStrategy:{type:'worktree',baseRef:'main',branch:'task'},runtimeMode:'auto'};
  const edited=api.scheduledTaskInput({...draft,projectId:'evil',model:'evil'},'Asia/Shanghai',original);
  assert.equal(edited.requireExisting,true);assert.equal(edited.threadId,'thread');assert.equal(edited.threadMode,'fresh_session');assert.deepEqual(edited.modelSelection,task.modelSelection);assert.deepEqual(edited.workspaceStrategy,original.workspaceStrategy);assert.equal(edited.enabled,true);
  assert.throws(()=>api.scheduledTaskInput(draft,'Asia/Shanghai',{...task,schedule:{type:'webhook'}}));
});
test('subscribe snapshot is cancelled, mutations read before and after, wrong scope/environment/stale data do not write',async()=>{
  const c=fixture();await api.mutateScheduledTask(c,'e','setEnabled',{id:task.id,enabled:true},task);
  assert.deepEqual(c.calls,['scheduledTasks.subscribe','scheduledTasks.setEnabled','scheduledTasks.subscribe']);assert.equal(c.stopped,2);
  const deletion=fixture();assert.equal((await api.mutateScheduledTask(deletion,'e','delete',{id:task.id},task)).tasks.length,0);
  for(const change of [c=>c.canScope=()=>false,c=>c.config.environment.environmentId='other']){const f=fixture();change(f);await assert.rejects(api.mutateScheduledTask(f,'e','delete',{id:task.id},task));assert.equal(f.calls.length,0)}
  const stale=fixture([{...task,updatedAt:'later'}]);await assert.rejects(api.mutateScheduledTask(stale,'e','delete',{id:task.id},task));assert.deepEqual(stale.calls,['scheduledTasks.subscribe']);
});
test('unknown mutation result is never retried; secret webhook endpoint is absent from views',async()=>{
  const f=fixture();f.rpcRequest=async method=>{f.calls.push(method);throw new Error('timeout')};
  await assert.rejects(api.mutateScheduledTask(f,'e','delete',{id:task.id},task));assert.equal(f.calls.filter(x=>x==='scheduledTasks.delete').length,1);
  const parsed=api.scheduleSnapshot({tasks:[{...task,webhook:{url:'https://example/secret'}}]});assert.ok(!JSON.stringify(parsed).includes('secret'));
});

test('only an explicit model swap drops confirmed options; normal and same-model edits preserve values', () => {
  const prior = { ...task, modelSelection: { provider: 'legacy', model: 'unknown', options: [{ id: 'opaque', value: 'future' }] },
    threadMode: 'continue', creationSource: 'mobile', runtimeMode: 'auto', interactionMode: 'plan' };
  assert.equal(api.scheduledTaskModelReplacementNeedsConfirmation(prior, 'legacy', 'unknown'), false);
  assert.equal(api.scheduledTaskModelReplacementNeedsConfirmation(prior, 'other', 'new'), true);
  assert.deepEqual(api.scheduledTaskInput({ ...draft, instanceId: 'other', model: 'new' }, 'UTC', prior).modelSelection, prior.modelSelection);
  assert.deepEqual(api.scheduledTaskInput({ ...draft, instanceId: 'legacy', model: 'unknown', modelChanged: true }, 'UTC', prior).modelSelection, prior.modelSelection);
  const replacement = { ...draft, instanceId: 'other', model: 'new', modelChanged: true };
  assert.throws(() => api.scheduledTaskInput(replacement, 'UTC', prior), /清除/);
  assert.throws(() => api.scheduledTaskInput({ ...replacement, confirmModelOptionsReset: true }, 'UTC', { ...prior, threadId: 'bound' }), /绑定/);
  const payload = api.scheduledTaskInput({ ...replacement, confirmModelOptionsReset: true }, 'UTC', prior);
  assert.deepEqual(payload.modelSelection, { instanceId: 'other', model: 'new' });
  assert.equal(payload.threadMode, 'continue');
  assert.equal(payload.runtimeMode, 'auto');
  assert.equal(payload.interactionMode, 'plan');
  assert.equal(payload.creationSource, 'mobile');
});

test('model mutation validates fresh compatible catalog and values before sending and never sends old options', async () => {
  const c = fixture();
  const payload = api.scheduledTaskInput({ ...draft, instanceId: 'other', model: 'new',
    modelChanged: true, confirmModelOptionsReset: true }, 'UTC', task);
  const result = await api.mutateScheduledTask(c, 'e', 'upsert', payload, task);
  assert.deepEqual(c.calls, ['scheduledTasks.subscribe', 'server.getConfig', 'scheduledTasks.subscribe',
    'scheduledTasks.upsert', 'scheduledTasks.subscribe']);
  assert.deepEqual(result.tasks[0].modelSelection, { instanceId: 'other', model: 'new' });
  const incompatible = fixture();
  incompatible.config.settings = { projectSettingsOverrides: { p: { providerInstances: { other: { enabled: false } } } } };
  await assert.rejects(api.mutateScheduledTask(incompatible, 'e', 'upsert', payload, task), /不可用/);
  assert.ok(!incompatible.calls.includes('scheduledTasks.upsert'));
  const forged = fixture();
  await assert.rejects(api.mutateScheduledTask(forged, 'e', 'upsert',
    { ...payload, modelSelection: { ...payload.modelSelection, options: task.modelSelection.options } }, task), /旧模型选项/);
  assert.ok(!forged.calls.includes('scheduledTasks.upsert'));
});

test('replacement aborts when task binding, generation or context changes while resolving the model', async () => {
  const replacement = api.scheduledTaskInput({ ...draft, instanceId: 'other', model: 'new',
    modelChanged: true, confirmModelOptionsReset: true }, 'UTC', task);
  for (const change of [
    c => c.replaceTasks([{ ...task, threadId: 'bound' }]),
    c => { c.generation++; }
  ]) {
    const c = fixture();
    const rpc = c.rpcRequest.bind(c);
    c.rpcRequest = async (method, payload) => {
      const result = await rpc(method, payload);
      if (method === 'server.getConfig') change(c);
      return result;
    };
    await assert.rejects(api.mutateScheduledTask(c, 'e', 'upsert', replacement, task), /已变化/);
    assert.ok(!c.calls.includes('scheduledTasks.upsert'));
  }
  const switched = fixture();
  await assert.rejects(api.mutateScheduledTask(switched, 'e', 'upsert', replacement, task, () => false), /已变化/);
  assert.equal(switched.calls.length, 0);
});

const shellThread = { id: 'bound', projectId: 'p', archivedAt: null, deletedAt: null,
  modelSelection: { instanceId: 'codex', model: 'm', options: [{ id: 'opaque', value: 'v' }] },
  runtimeMode: 'auto', interactionMode: 'plan', worktreePath: '/worktrees/current', branch: 'branch' };
function creationFixture(thread = shellThread, project = { id: 'p' }, modern = true) {
  const c = fixture([]);
  const watch = c.watchRpcStream.bind(c);
  c.config.environment.capabilities = modern ? { scheduledTaskThreadModes: true } : {};
  c.watchRpcStream = (method, payload, listener) => {
    if (method !== 'orchestration.subscribeShell') return watch(method, payload, listener);
    c.calls.push(method);
    queueMicrotask(() => listener({ kind: 'snapshot', snapshot: { projects: project ? [project] : [], threads: thread ? [thread] : [] } }));
    return listener;
  };
  return c;
}

test('first binding stays off and stores safe launch defaults separately from the target thread', async () => {
  const c = creationFixture();
  const payload = api.scheduledTaskInput({ ...draft, threadId: 'bound', threadMode: 'fresh_session', supportsThreadModes: true }, 'UTC');
  assert.equal(payload.enabled, false);
  assert.equal(payload.threadId, 'bound');
  assert.equal(payload.threadMode, 'fresh_session');
  const result = await api.mutateScheduledTask(c, 'e', 'upsert', payload);
  const saved = result.tasks[0];
  assert.deepEqual(c.calls, ['scheduledTasks.subscribe', 'orchestration.subscribeShell', 'scheduledTasks.upsert', 'scheduledTasks.subscribe']);
  assert.equal(saved.threadId, 'bound');
  assert.equal(saved.enabled, false);
  assert.equal(saved.runtimeMode, 'approval-required');
  assert.equal(saved.interactionMode, 'default');
  assert.deepEqual(saved.workspaceStrategy, { type: 'root' });
  assert.deepEqual(saved.modelSelection, { instanceId: 'codex', model: 'm' });
  assert.equal(saved.creationSource, 'mobile');
});

test('new unbound tasks can continue or use a fresh session after their first run on modern servers', async () => {
  for (const mode of ['new_thread', 'continue', 'fresh_session']) {
    const c = creationFixture();
    const payload = api.scheduledTaskInput({ ...draft, threadId: null, threadMode: mode, supportsThreadModes: true }, 'UTC');
    assert.equal(payload.threadMode, mode);
    assert.equal((await api.mutateScheduledTask(c, 'e', 'upsert', payload)).tasks[0].threadMode, mode);
  }
  const old = creationFixture(shellThread, { id: 'p' }, false);
  const legacy = api.scheduledTaskInput({ ...draft, threadId: 'bound', threadMode: 'continue' }, 'UTC');
  assert.equal('threadMode' in legacy, false);
  assert.equal((await api.mutateScheduledTask(old, 'e', 'upsert', legacy)).tasks[0].threadId, 'bound');
  assert.throws(() => api.scheduledTaskInput({ ...draft, threadId: 'bound', threadMode: 'new_thread', supportsThreadModes: true }, 'UTC'), /不匹配/);
  assert.throws(() => api.scheduledTaskInput({ ...draft, threadMode: 'fresh_session' }, 'UTC'), /不支持/);
});

test('binding rejects missing, archived, cross-project and changed target models before submission', async () => {
  const payload = api.scheduledTaskInput({ ...draft, threadId: 'bound', supportsThreadModes: true }, 'UTC');
  for (const [thread, project, error] of [
    [undefined, { id: 'p', archivedAt: 'earlier' }, /项目/],
    [null, { id: 'p' }, /会话/],
    [{ ...shellThread, projectId: 'other' }, { id: 'p' }, /会话/],
    [{ ...shellThread, archivedAt: 'earlier' }, { id: 'p' }, /会话/],
    [{ ...shellThread, deletedAt: 'earlier' }, { id: 'p' }, /会话/],
    [{ ...shellThread, modelSelection: { instanceId: 'changed', model: 'm' } }, { id: 'p' }, /模型已变化/]
  ]) {
    const c = creationFixture(thread, project);
    await assert.rejects(api.mutateScheduledTask(c, 'e', 'upsert', payload), error);
    assert.ok(!c.calls.includes('scheduledTasks.upsert'));
  }
  const c = creationFixture();
  const watch = c.watchRpcStream.bind(c);
  c.watchRpcStream = (method, request, callback) => watch(method, request, value => {
    if (method === 'orchestration.subscribeShell') c.generation++;
    callback(value);
  });
  await assert.rejects(api.mutateScheduledTask(c, 'e', 'upsert', payload), /环境已变化/);
  assert.ok(!c.calls.includes('scheduledTasks.upsert'));
});

test('ordinary edits do not rebind existing targets even when draft data names another session or mode', () => {
  const existing = { ...task, threadId: 'original', threadMode: 'continue' };
  const payload = api.scheduledTaskInput({ ...draft, threadId: 'other', threadMode: 'fresh_session', supportsThreadModes: true }, 'UTC', existing);
  assert.equal(payload.threadId, 'original');
  assert.equal(payload.threadMode, 'continue');
  assert.equal(payload.requireExisting, true);
});

test('new bound payload cannot silently carry the thread full-access mode or a different workspace', async () => {
  const payload = api.scheduledTaskInput({ ...draft, threadId: 'bound', supportsThreadModes: true }, 'UTC');
  for (const altered of [
    { ...payload, runtimeMode: 'full-access' },
    { ...payload, workspaceStrategy: { type: 'existing_worktree', worktreePath: '/target' } }
  ]) {
    const c = creationFixture();
    await assert.rejects(api.mutateScheduledTask(c, 'e', 'upsert', altered), /默认运行元数据/);
    assert.ok(!c.calls.includes('scheduledTasks.upsert'));
  }
});

const ref = (name, worktreePath = null, extras = {}) => ({ name, worktreePath, current: false, isDefault: false, ...extras });
function workspaceFixture(existing, pages = [
  { isRepo: true, refs: [ref('main', '/work/project', { current: true }), ref('feature', '/work/checkout')], nextCursor: null }
]) {
  const c = creationFixture(shellThread, { id: 'p', workspaceRoot: '/work/project' });
  if (existing) c.replaceTasks([existing]);
  const rpc = c.rpcRequest.bind(c);
  c.refRequests = [];
  c.rpcRequest = async (method, payload) => {
    if (method !== 'vcs.listRefs') return rpc(method, payload);
    c.calls.push(method);
    c.refRequests.push(payload);
    return pages[c.refRequests.length - 1];
  };
  return c;
}

test('worktree option reads are fresh, local, paginated and tied to the selected project root', async () => {
  const c = workspaceFixture(undefined, [
    { isRepo: true, refs: [ref('main', '/work/project', { current: true })], nextCursor: 200 },
    { isRepo: true, refs: [ref('feature', '/work/checkout'), ref('remote', null, { isRemote: true })], nextCursor: null }
  ]);
  const options = await api.readScheduledWorkspaceOptions(c, 'e', 'p');
  assert.deepEqual(options.refs.map(row => row.name), ['main', 'feature']);
  assert.deepEqual(options.checkoutPaths, ['/work/checkout']);
  assert.deepEqual(c.calls, ['orchestration.subscribeShell', 'vcs.listRefs', 'vcs.listRefs']);
  assert.deepEqual(c.refRequests, [
    { cwd: '/work/project', limit: 200, refKind: 'local', refresh: true },
    { cwd: '/work/project', limit: 200, refKind: 'local', cursor: 200 }
  ]);
});

test('unbound tasks can save a confirmed new or existing checkout; ordinary edits preserve advanced workspace', async () => {
  const worktree = { type: 'worktree', baseRef: 'feature', startFromOrigin: false };
  const created = api.scheduledTaskInput({ ...draft, workspaceStrategy: worktree }, 'UTC');
  const c = workspaceFixture();
  assert.deepEqual((await api.mutateScheduledTask(c, 'e', 'upsert', created)).tasks[0].workspaceStrategy, worktree);
  assert.equal(created.enabled, false);
  const original = { ...task, workspaceStrategy: { type: 'worktree', baseRef: 'main', branch: 'have-explicit-branch', startFromOrigin: true } };
  const ordinary = api.scheduledTaskInput(draft, 'UTC', original);
  assert.deepEqual(ordinary.workspaceStrategy, original.workspaceStrategy);
  const checkout = { type: 'existing_worktree', worktreePath: '/work/checkout' };
  const moved = api.scheduledTaskInput({ ...draft, workspaceStrategy: checkout }, 'UTC', original);
  const editing = workspaceFixture(original);
  assert.deepEqual((await api.mutateScheduledTask(editing, 'e', 'upsert', moved, original)).tasks[0].workspaceStrategy, checkout);
  assert.ok(editing.calls.includes('vcs.listRefs'));
  assert.equal(editing.calls.filter(method => method === 'scheduledTasks.upsert').length, 1);
});

test('unsafe, detached, missing or cross-project checkout inputs never reach upsert', async () => {
  const choose = workspaceStrategy => api.scheduledTaskInput({ ...draft, workspaceStrategy }, 'UTC');
  assert.throws(() => choose({ type: 'worktree', baseRef: '--option', startFromOrigin: true }), /无效/);
  assert.throws(() => choose({ type: 'worktree', baseRef: 'main', startFromOrigin: 'true' }), /无效/);
  assert.throws(() => choose({ type: 'existing_worktree', worktreePath: '../other' }), /无效/);
  assert.throws(() => api.scheduledTaskInput({ ...draft, threadId: 'bound', workspaceStrategy: { type: 'root' } }, 'UTC'), /绑定/);
  for (const strategy of [
    { type: 'worktree', baseRef: 'missing', startFromOrigin: true },
    { type: 'existing_worktree', worktreePath: '/other/project' },
    { type: 'existing_worktree', worktreePath: '/work/project' }
  ]) {
    const c = workspaceFixture();
    await assert.rejects(api.mutateScheduledTask(c, 'e', 'upsert', choose(strategy)), /变化|当前项目/);
    assert.ok(!c.calls.includes('scheduledTasks.upsert'));
  }
  const c = workspaceFixture();
  const watch = c.watchRpcStream.bind(c);
  let shellReads = 0;
  c.watchRpcStream = (method, input, listener) => watch(method, input, value => {
    if (method === 'orchestration.subscribeShell' && ++shellReads === 2) value.snapshot.projects[0].workspaceRoot = '/new';
    listener(value);
  });
  await assert.rejects(api.mutateScheduledTask(c, 'e', 'upsert', choose({ type: 'worktree', baseRef: 'main', startFromOrigin: true })), /工作目录已变化/);
  assert.ok(!c.calls.includes('scheduledTasks.upsert'));
});

test('workspace writeback must match exactly, without automatic replay', async () => {
  const c = workspaceFixture();
  const rpc = c.rpcRequest.bind(c);
  c.rpcRequest = async (method, payload) => rpc(method, method === 'scheduledTasks.upsert'
    ? { ...payload, workspaceStrategy: { type: 'root' } } : payload);
  const payload = api.scheduledTaskInput({ ...draft,
    workspaceStrategy: { type: 'worktree', baseRef: 'main', startFromOrigin: true } }, 'UTC');
  await assert.rejects(api.mutateScheduledTask(c, 'e', 'upsert', payload), /保存尚未确认/);
  assert.equal(c.calls.filter(method => method === 'scheduledTasks.upsert').length, 1);
});

test('branch discovery marks truncated pages and supports a bounded server-side name query', async () => {
  const pages = Array.from({ length: 5 }, (_, index) => ({
    isRepo: true, refs: [ref('feature-' + index)], nextCursor: (index + 1) * 200
  }));
  const limited = workspaceFixture(undefined, pages);
  const unfiltered = await api.readScheduledWorkspaceOptions(limited, 'e', 'p');
  assert.equal(unfiltered.truncated, true);
  assert.equal(limited.refRequests.length, 5);
  const target = workspaceFixture(undefined, [{ isRepo: true, refs: [ref('feature-after-limit')], nextCursor: null }]);
  assert.equal((await api.readScheduledWorkspaceOptions(target, 'e', 'p', ' feature-after-limit ')).truncated, false);
  assert.equal(target.refRequests[0].query, 'feature-after-limit');
  await assert.rejects(api.readScheduledWorkspaceOptions(workspaceFixture(), 'e', 'p', 'a'.repeat(257)), /搜索内容无效/);
});

test('new worktree save queries the exact base and stops once listed; complete and truncated misses differ', async () => {
  const payload = api.scheduledTaskInput({ ...draft,
    workspaceStrategy: { type: 'worktree', baseRef: 'feature-after-limit', startFromOrigin: true } }, 'UTC');
  const c = workspaceFixture(undefined, [
    { isRepo: true, refs: [ref('feature-after-limit')], nextCursor: 200 }
  ]);
  await api.mutateScheduledTask(c, 'e', 'upsert', payload);
  assert.equal(c.refRequests[0].query, 'feature-after-limit');
  assert.equal(c.refRequests.length, 1);
  const absent = workspaceFixture(undefined, [{ isRepo: true, refs: [], nextCursor: null }]);
  await assert.rejects(api.mutateScheduledTask(absent, 'e', 'upsert', payload), /基础分支已变化/);
  const limited = workspaceFixture(undefined, Array.from({ length: 5 }, (_, index) => ({
    isRepo: true, refs: [ref('feature-after-limit-' + index)], nextCursor: (index + 1) * 200
  })));
  await assert.rejects(api.mutateScheduledTask(limited, 'e', 'upsert', payload), /尚未覆盖/);
  assert.equal(limited.refRequests.length, 5);
  assert.ok(!limited.calls.includes('scheduledTasks.upsert'));
});

test('saved checkout hint only narrows read scope and must return the exact selected checkout', async () => {
  const payload = api.scheduledTaskInput({ ...draft,
    workspaceStrategy: { type: 'existing_worktree', worktreePath: '/work/checkout-late' } }, 'UTC');
  const c = workspaceFixture(undefined, [
    { isRepo: true, refs: [ref('late-branch', '/work/checkout-late')], nextCursor: null }
  ]);
  let saved;
  const rpc = c.rpcRequest;
  c.rpcRequest = async (method, input) => { if (method === 'scheduledTasks.upsert') saved = input; return rpc(method, input); };
  await api.mutateScheduledTask(c, 'e', 'upsert', payload, undefined, () => true, 'late-branch');
  assert.equal(c.refRequests[0].query, 'late-branch');
  assert.deepEqual(saved, payload);
  const wrong = workspaceFixture(undefined, [
    { isRepo: true, refs: [ref('late-branch', '/work/other')], nextCursor: null }
  ]);
  await assert.rejects(api.mutateScheduledTask(wrong, 'e', 'upsert', payload, undefined, () => true, 'late-branch'), /未找到/);
  assert.ok(!wrong.calls.includes('scheduledTasks.upsert'));
});

test('current checkout stays a valid base ref but cannot masquerade as a linked checkout via its canonical path', async () => {
  const canonical = '/private/work/project';
  const pages = [{ isRepo: true, refs: [ref('main', canonical, { current: true }), ref('other', '/work/other')], nextCursor: null }];
  const choices = await api.readScheduledWorkspaceOptions(workspaceFixture(undefined, pages), 'e', 'p');
  assert.deepEqual(choices.refs.map(r => r.name), ['main', 'other']);
  assert.deepEqual(choices.checkoutPaths, ['/work/other']);
  const payload = api.scheduledTaskInput({ ...draft, workspaceStrategy: { type: 'existing_worktree', worktreePath: canonical } }, 'UTC');
  const c = workspaceFixture(undefined, pages);
  await assert.rejects(api.mutateScheduledTask(c, 'e', 'upsert', payload), api.ScheduledWorkspaceSelectionError);
  assert.ok(!c.calls.includes('scheduledTasks.upsert'));
});

test('U4: scheduledTaskWorktreeBaseRef resolves explicit base, project default branch, main/master fallback', () => {
  const mk = (name, isDefault = false) => ({ name, isDefault });
  assert.equal(api.scheduledTaskWorktreeBaseRef(' release ', [mk('master', true)]), 'release');
  assert.equal(api.scheduledTaskWorktreeBaseRef('', [mk('feature'), mk('master', true)]), 'master');
  assert.equal(api.scheduledTaskWorktreeBaseRef(' ', [mk('origin/develop', true)]), 'origin/develop');
  assert.equal(api.scheduledTaskWorktreeBaseRef('', [mk('feature'), mk('master')]), 'master');
  assert.equal(api.scheduledTaskWorktreeBaseRef('', [mk('origin/master')]), 'origin/master');
  assert.equal(api.scheduledTaskWorktreeBaseRef('', [mk('master'), mk('main')]), 'main');
  assert.equal(api.scheduledTaskWorktreeBaseRef('', []), 'main');
});

test('U4: explicitly clearing a bound task thread sends threadId null with unbindThread true and verifies readback', async () => {
  const bound = { ...task, threadId: 'bound-thread', threadMode: 'continue', creationSource: 'mobile' };
  const cleared = api.scheduledTaskInput({ ...draft, threadId: null, unbindThread: true }, 'UTC', bound);
  assert.equal(cleared.threadId, null);
  assert.equal(cleared.unbindThread, true);
  assert.equal(cleared.threadMode, 'continue');
  assert.equal(cleared.requireExisting, true);

  const c = fixture([bound]);
  let sent;
  const rpc = c.rpcRequest.bind(c);
  c.rpcRequest = async (method, payload) => {
    if (method === 'scheduledTasks.upsert') sent = payload;
    return rpc(method, payload);
  };
  const after = await api.mutateScheduledTask(c, 'e', 'upsert', cleared, bound);
  assert.equal(sent.threadId, null);
  assert.equal(sent.unbindThread, true);
  assert.equal(after.tasks[0].threadId, null);
  assert.equal(after.tasks[0].threadMode, 'continue');

  // If a legacy server ignores unbindThread and keeps the old threadId, readback catches it.
  const staleServer = fixture([bound]);
  const staleRpc = staleServer.rpcRequest.bind(staleServer);
  staleServer.rpcRequest = async (method, payload) => staleRpc(
    method,
    method === 'scheduledTasks.upsert' ? { ...payload, threadId: 'bound-thread' } : payload
  );
  await assert.rejects(api.mutateScheduledTask(staleServer, 'e', 'upsert', cleared, bound), /保存尚未确认/);

  // Forged unbindThread without threadId=null or on an already unbound task is rejected before RPC.
  const forged = fixture([bound]);
  await assert.rejects(api.mutateScheduledTask(forged, 'e', 'upsert', { ...cleared, threadId: 'bound-thread' }, bound), /不能更改/);
  assert.ok(!forged.calls.includes('scheduledTasks.upsert'));
  const alreadyUnbound = fixture([task]);
  await assert.rejects(api.mutateScheduledTask(alreadyUnbound, 'e', 'upsert',
    { ...api.scheduledTaskInput(draft, 'UTC', task), unbindThread: true }, task), /不能更改/);
  assert.ok(!alreadyUnbound.calls.includes('scheduledTasks.upsert'));
});
