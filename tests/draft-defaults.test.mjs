import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { compile, data } from './load-core.mjs';
const source=(await readFile(new URL('../entry/src/main/ets/protocol/DraftDefaults.ts',import.meta.url),'utf8'))
 .replace("'./Wire'",JSON.stringify(new URL('../entry/src/main/ets/protocol/Wire.ts',import.meta.url).href));
const {resolveDraftDefaults:resolve,readDraftDefaults:read}=await import(data(compile(source)));
const project={id:'p',workspaceRoot:'/repo',hasThreads:true};
const config=(settings={})=>({environment:{environmentId:'e'},settings});
const file=(contents)=>({relativePath:'t3.json',contents,truncated:false});
test('draft defaults preserve explicit global values and reject identity and unknown values',()=>{
 assert.deepEqual(resolve(config(),'e',project),{runtimeMode:'approval-required',workspace:{mode:'local',branch:'',worktreePath:'',startFromOrigin:true}});
 const c=config({defaultRuntimeMode:'auto',defaultThreadEnvMode:'worktree',newWorktreesStartFromOrigin:false});
 assert.equal(resolve(c,'e',project).runtimeMode,'auto'); assert.equal(resolve(c,'e',project).workspace.mode,'worktree');
 assert.equal(resolve(c,'e',project).workspace.startFromOrigin,false);
 assert.throws(()=>resolve(c,'other',project),/身份/);
 for(const settings of [{defaultRuntimeMode:'future'},{defaultThreadEnvMode:'future'},{newWorktreesStartFromOrigin:'yes'}]) assert.throws(()=>resolve(config(settings),'e',project));
});
test('project overrides beat unfolded legacy and environment, folded legacy never revives',()=>{
 const p={...project,defaultThreadEnvMode:'worktree'};
 const c=config({defaultThreadEnvMode:'local',defaultRuntimeMode:'auto',projectSettingsOverrides:{p:{defaultThreadEnvMode:'local',defaultRuntimeMode:'approval-required',newWorktreesStartFromOrigin:false}}});
 assert.equal(resolve(c,'e',p).workspace.mode,'local'); assert.equal(resolve(c,'e',p).runtimeMode,'approval-required');
 c.settings.projectSettingsOverrides={}; assert.equal(resolve(c,'e',p).workspace.mode,'worktree');
 c.settings.projectSettingsFolded=true; assert.equal(resolve(c,'e',p).workspace.mode,'local');
});
test('null inherits checked in JSONC only, absent file falls back, invalid or truncated never silently chooses local',()=>{
 const c=config({defaultThreadEnvMode:null});
 assert.equal(resolve(c,'e',project,file('{/*comment*/ "defaultThreadEnvMode":"worktree", "url":"http://a",}')).workspace.mode,'worktree');
 assert.equal(resolve(c,'e',project,{exists:false}).workspace.mode,'local');
 assert.equal(resolve(c,'e',project,file('{}')).workspace.mode,'local');
 assert.throws(()=>resolve(c,'e',project),/尚未/);
 assert.throws(()=>resolve(c,'e',project,file('{bad')),/格式/);
 assert.throws(()=>resolve(c,'e',project,{...file('{}'),truncated:true}),/完整/);
 assert.throws(()=>resolve(c,'e',project,file('{"defaultThreadEnvMode":"future"}')),/不受支持/);
});
test('organization permission ceiling clamps global and project defaults without widening access',()=>{
 const c={...config({defaultRuntimeMode:'full-access',projectSettingsOverrides:{p:{defaultRuntimeMode:'auto'}}}),managedPolicy:{limits:{maxRuntimeMode:'auto-accept-edits'}}};
 assert.equal(resolve(c,'e',project).runtimeMode,'auto-accept-edits');
 c.settings.projectSettingsOverrides.p.defaultRuntimeMode='approval-required';
 assert.equal(resolve(c,'e',project).runtimeMode,'approval-required');
 c.managedPolicy.limits.maxRuntimeMode='future'; assert.throws(()=>resolve(c,'e',project),/上限/);
});
test('scratch and first name-only project stay local, explicit project or file choices remain honored',()=>{
 const c={...config({defaultThreadEnvMode:'worktree'}),newProjectsRoot:'/projects'};
 const p={...project,workspaceRoot:'/projects/new',hasThreads:false};
 assert.equal(resolve(c,'e',p).workspace.mode,'local');
 assert.equal(resolve(c,'e',{...p,hasThreads:true}).workspace.mode,'worktree');
 assert.equal(resolve({...c,newProjectsRoot:'C:\\Projects'},'e',{...p,workspaceRoot:'c:/projects/New'}).workspace.mode,'local');
 assert.equal(resolve(c,'e',{...p,workspaceRoot:'/projects/new/deep'}).workspace.mode,'worktree');
 assert.equal(resolve(c,'e',{...p,defaultThreadEnvMode:'worktree'}).workspace.mode,'worktree');
 c.settings.defaultThreadEnvMode=null;
 assert.equal(resolve(c,'e',p,file('{"defaultThreadEnvMode":"worktree"}')).workspace.mode,'worktree');
 assert.equal(resolve(c,'e',{...p,isScratch:true}).workspace.mode,'local');
});
test('reader uses actual optional file RPC only for inherited mode, refuses unauthorized reads and propagates failures',async()=>{
 let current=config({defaultThreadEnvMode:null}); const calls=[];
 const conn={ready:true,canScope:()=>true,rpcRequest:async(method,payload)=>{calls.push([method,payload]);return method==='server.getConfig'?current:file('{"defaultThreadEnvMode":"worktree"}');}};
 assert.equal((await read(conn,'e',project)).workspace.mode,'worktree');
 assert.deepEqual(calls[1],['projects.readFile',{cwd:'/repo',relativePath:'t3.json',allowMissing:true}]);
 calls.length=0; current=config({defaultThreadEnvMode:'local'}); await read(conn,'e',project); assert.equal(calls.length,1);
 current=config({defaultThreadEnvMode:null}); conn.canScope=scope=>scope!=='filesystem:read'; await assert.rejects(read(conn,'e',project),/文件读取权限/);
 conn.canScope=()=>true; conn.rpcRequest=async()=>{throw Error('offline');}; await assert.rejects(read(conn,'e',project),/offline/);
});

const { r4Url } = await import('./load-core.mjs');
const { switchDraftWorkspaceMode, draftWorkspaceForBranch } = await import(r4Url);
const branchRef = (name, flags = {}) => ({ name, isRemote: false, remoteName: '', current: false, isDefault: false, worktreePath: '', ...flags });

test('worktree mode preserves resolved and saved origin choices; picking a remote branch is explicit', () => {
  const selected = [branchRef('main', { current: true, isDefault: true })];
  const initial = resolve(config({ newWorktreesStartFromOrigin: true,
    projectSettingsOverrides: { p: { newWorktreesStartFromOrigin: false } } }), 'e', project).workspace;
  const worktree = switchDraftWorkspaceMode(initial, 'worktree', selected);
  assert.deepEqual(worktree, { mode: 'worktree', branch: 'main', worktreePath: '', startFromOrigin: false });
  const local = switchDraftWorkspaceMode(worktree, 'local', selected);
  assert.equal(draftWorkspaceForBranch(local, branchRef('dev')).startFromOrigin, false);
  assert.equal(switchDraftWorkspaceMode(local, 'worktree', selected).startFromOrigin, false);
  assert.equal(draftWorkspaceForBranch(worktree, branchRef('origin/main', { isRemote: true })).startFromOrigin, true);
  const chosen = { ...worktree, startFromOrigin: true };
  assert.equal(draftWorkspaceForBranch(chosen, branchRef('dev')).startFromOrigin, true);
  assert.equal(switchDraftWorkspaceMode(chosen, 'local', selected).startFromOrigin, true);
});

const index = await readFile(new URL('../entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
const branchMethods = index.slice(index.indexOf('  private branchRequest:'), index.indexOf('  private async applyCurrentCheckoutBranch()'));
globalThis.__draftBranchHelpers = { switchDraftWorkspaceMode, draftWorkspaceForBranch };
const { DraftBranchHarness, setClient } = await import(data(compile(`
  const { switchDraftWorkspaceMode, draftWorkspaceForBranch } = globalThis.__draftBranchHelpers;
  let client;
  export function setClient(owner) { client = owner; }
  export class DraftBranchHarness {
    alive = true; appForeground = true; draftMode = true; page = 'chat'; projectId = 'project';
    busy = false; unknown = false; key = 'environment/draft'; cwd = '/repo'; saved = 0;
    draftWorkspace = { mode: 'local', branch: '', worktreePath: '', startFromOrigin: false };
    branches = [];
    draftKey() { return this.key; }
    draftCwd() { return this.cwd; }
    scheduleDraftSave() { this.saved++; }
    ${branchMethods}
  }
`)));

test('newer refs and changes in draft or connection discard late branch results', async () => {
  const panel = new DraftBranchHarness();
  let finish;
  let generation = 1;
  const owner = { ready: true, generationValue: () => generation, listBranches: () => new Promise(resolve => { finish = resolve; }) };
  setClient(owner);
  const stale = panel.loadBranches();
  const finishStale = finish;
  const fresh = panel.loadBranches();
  finish([branchRef('current', { current: true })]);
  await fresh;
  finishStale([branchRef('stale', { current: true })]);
  await stale;
  assert.equal(panel.draftWorkspace.branch, 'current');
  assert.equal(panel.branches[0].name, 'current');
  const another = panel.loadBranches();
  panel.key = 'environment/new-draft';
  generation++;
  panel.draftWorkspace = { mode: 'local', branch: '', worktreePath: '', startFromOrigin: true };
  finish([branchRef('wrong', { current: true })]);
  await another;
  assert.equal(panel.draftWorkspace.branch, '');
  assert.equal(panel.draftWorkspace.startFromOrigin, true);
});

test('late checkout response cannot save a branch or origin into a different draft', async () => {
  const panel = new DraftBranchHarness();
  let finish;
  let switches = 0;
  let generation = 1;
  const owner = { ready: true, generationValue: () => generation, canWriteSourceControl: () => true,
    switchBranch: () => { switches++; return new Promise(resolve => { finish = resolve; }); },
    listBranches: async () => [] };
  setClient(owner);
  const pending = panel.selectBranch(branchRef('other'));
  assert.equal(switches, 1);
  panel.key = 'environment/new-draft';
  generation++;
  panel.draftWorkspace = { mode: 'local', branch: 'mine', worktreePath: '', startFromOrigin: true };
  finish();
  await pending;
  assert.deepEqual(panel.draftWorkspace, { mode: 'local', branch: 'mine', worktreePath: '', startFromOrigin: true });
  assert.equal(panel.saved, 0);
  assert.equal(panel.busy, false);
  panel.appForeground = false;
  await panel.selectBranch(branchRef('ignored'));
  assert.equal(switches, 1);
});
