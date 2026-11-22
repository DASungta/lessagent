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

const modelCatalogConfig = (extraSettings = {}, extraRoot = {}) => ({
  environment: { environmentId: 'e' },
  providers: [
    {
      instanceId: 'codex', driver: 'codex', enabled: true, installed: true, auth: { status: 'authenticated' },
      supportedRuntimeModes: ['approval-required', 'auto-accept-edits', 'full-access'],
      models: [
        { slug: 'legacy-gpt', name: 'Legacy GPT', isLegacy: true },
        { slug: 'gpt-5', name: 'GPT 5', capabilities: { optionDescriptors: [{ id: 'reasoningEffort', type: 'select', options: [{ id: 'high' }, { id: 'max' }] }, { id: 'fast', type: 'boolean' }] } },
        { slug: 'gpt-default', name: 'GPT Default', isDefault: true }
      ]
    },
    {
      instanceId: 'antigravity', driver: 'antigravity', enabled: true, installed: true, auth: { status: 'authenticated' },
      models: [
        { slug: 'gemini-4-neon', name: 'Gemini 4 Neon', capabilities: { optionDescriptors: [{ id: 'thought_level', type: 'select', options: [{ id: 'high' }, { id: 'xhigh' }] }] } },
        { slug: 'gemini-custom', name: 'Custom', isCustom: true }
      ]
    }
  ],
  settings: extraSettings,
  ...extraRoot
});

test('model defaults resolve project override > unfolded legacy > environment default > catalog default and normalize options', () => {
  const proj = { ...project, defaultModelSelection: { instanceId: 'codex', model: 'gpt-5', options: [{ id: 'reasoningEffort', value: 'high' }] } };
  const overrideCfg = modelCatalogConfig({
    defaultModelSelection: { instanceId: 'codex', model: 'gpt-default' },
    projectSettingsOverrides: {
      p: { defaultModelSelection: { instanceId: 'antigravity', model: 'gemini-4-neon', options: [{ id: 'thought_level', value: 'xhigh' }, { id: 'stale', value: 'x' }] } }
    }
  });
  assert.deepEqual(resolve(overrideCfg, 'e', proj).modelSelection, {
    instanceId: 'antigravity', model: 'gemini-4-neon', options: [{ id: 'thought_level', value: 'xhigh' }]
  });

  // Unfolded legacy applies when override is absent, including legacy object options; folded ignores legacy.
  const legacyCfg = modelCatalogConfig({ defaultModelSelection: { instanceId: 'codex', model: 'gpt-default' } });
  const legacyProj = { ...project, defaultModelSelection: { provider: 'codex', model: 'gpt-5', options: { reasoningEffort: 'max', fast: true, invalid: 'bad' } } };
  assert.deepEqual(resolve(legacyCfg, 'e', legacyProj).modelSelection, {
    instanceId: 'codex', model: 'gpt-5', options: [{ id: 'reasoningEffort', value: 'max' }, { id: 'fast', value: true }]
  });
  legacyCfg.settings.projectSettingsFolded = true;
  assert.deepEqual(resolve(legacyCfg, 'e', legacyProj).modelSelection, { instanceId: 'codex', model: 'gpt-default' });

  // Explicit null override suppresses environment default and falls back to catalog default.
  const nullOverrideCfg = modelCatalogConfig({
    defaultModelSelection: { instanceId: 'codex', model: 'gpt-5' },
    projectSettingsOverrides: { p: { defaultModelSelection: null } }
  });
  assert.deepEqual(resolve(nullOverrideCfg, 'e', proj).modelSelection, { instanceId: 'codex', model: 'gpt-default' });
});

test('model defaults skip disabled, disallowed, hidden, legacy, and unauthenticated selections and narrow runtimeMode', () => {
  const disabledCfg = modelCatalogConfig({
    defaultModelSelection: { instanceId: 'antigravity', model: 'gemini-4-neon' },
    providerModelPreferences: { codex: { hiddenModels: ['gpt-default'], modelOrder: ['gpt-5'] } },
    projectSettingsOverrides: {
      p: {
        providerInstances: { antigravity: { enabled: false } },
        defaultModelSelection: { instanceId: 'antigravity', model: 'gemini-4-neon' }
      }
    }
  });
  // antigravity disabled for project p -> env default also antigravity -> catalog skips antigravity and hidden gpt-default -> gpt-5
  assert.deepEqual(resolve(disabledCfg, 'e', project).modelSelection, { instanceId: 'codex', model: 'gpt-5' });

  // Custom model stays selectable even if listed in hiddenModels
  const customHiddenCfg = modelCatalogConfig({
    providerModelPreferences: { antigravity: { hiddenModels: ['gemini-custom'] } },
    projectSettingsOverrides: { p: { defaultModelSelection: { instanceId: 'antigravity', model: 'gemini-custom' } } }
  });
  assert.deepEqual(resolve(customHiddenCfg, 'e', project).modelSelection, { instanceId: 'antigravity', model: 'gemini-custom' });

  // Legacy non-antigravity default is rejected; disallowed driver is skipped; provider supportedRuntimeModes narrows runtimeMode
  const policyCfg = modelCatalogConfig({
    defaultRuntimeMode: 'auto',
    projectSettingsOverrides: { p: { defaultModelSelection: { instanceId: 'codex', model: 'legacy-gpt' } } },
    defaultModelSelection: { instanceId: 'antigravity', model: 'gemini-4-neon' }
  }, {
    managedPolicy: { limits: { providers: { allowedDrivers: ['codex'] } } }
  });
  const resolvedPolicy = resolve(policyCfg, 'e', project);
  assert.deepEqual(resolvedPolicy.modelSelection, { instanceId: 'codex', model: 'gpt-default' });
  assert.equal(resolvedPolicy.runtimeMode, 'approval-required');

  // Exhausted usage window falls back to fallbackModelSelection
  const futureReset = new Date(Date.now() + 600000).toISOString();
  const exhaustedCfg = modelCatalogConfig({
    defaultModelSelection: { instanceId: 'antigravity', model: 'gemini-4-neon' },
    fallbackModelSelection: { instanceId: 'codex', model: 'gpt-5' }
  });
  exhaustedCfg.providers[1].usageLimits = { windows: [{ id: 'gemini-pro', usedPercent: 100, resetsAt: futureReset }] };
  assert.deepEqual(resolve(exhaustedCfg, 'e', project).modelSelection, { instanceId: 'codex', model: 'gpt-5' });
});
