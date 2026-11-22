import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {compile, threadItemsUrl, floatingStatusUrl} from './load-core.mjs';
const { emptyWorkMap } = await import(threadItemsUrl);
const { emptyFloatingCapsule } = await import(floatingStatusUrl);
const source=await readFile(new URL('../entry/src/main/ets/pages/Index.ets',import.meta.url),'utf8');
const methods=source.slice(source.indexOf('  private draftKey()'),source.indexOf('  private openTaskSettings()'));
const emptyWorkspace=()=>({mode:'local',branch:'',worktreePath:'',startFromOrigin:true});
const draftSettings=d=>({modelSelection:d.modelSelection,runtimeMode:d.runtimeMode,interactionMode:d.interactionMode});
let counter=0;
const util={generateRandomUUID:()=>`draft-${++counter}`};
const draftStore={async save(){}};
const client={bindDraftAttachments(){}};
const Page=new Function('client','util','emptyWorkspace','draftSettings','draftStore','emptyWorkMap','emptyFloatingCapsule',compile('return class { '+methods+' }'))(client,util,emptyWorkspace,draftSettings,draftStore,emptyWorkMap,emptyFloatingCapsule);
function page(localId='a') {
  return Object.assign(new Page(),{selectedLocalId:localId,threadId:'old',draftMode:false,projectId:'old-project',prompt:'old text',
    remembered:[],rememberProject:function(id){this.remembered.push(id)},activeDraftId:'',draftRecords:[],textDrafts:new Map(),settingsDrafts:new Map(),contextDrafts:new Map(),models:[{instanceId:'codex',model:'m'}],
    source:{update(){}},picker:{clear(){}},panelOpen:true,draftWorkspace:emptyWorkspace(),draftContext:[],attachments:[],
    branches:[],branchesLoading:false,commandPanel:'',sendMode:'auto',messages:[],actions:[],tools:[],linkItems:[],queued:[],
    extraPlans:[],extraSubagents:[],extraGuest:undefined,extraUsage:undefined,draftEnvironment:()=> 'env-a',
    loadBranches:async()=>{}, newDraftDefaults:async()=>({runtimeMode:'approval-required',workspace:emptyWorkspace()}),
    persistDraft:async function(){const r=this.draftRecord();if(r)this.draftRecords=[r,...this.draftRecords.filter(d=>d.draftId!==r.draftId)];},
    taskSettings:{modelSelection:{instanceId:'codex',model:'m'},runtimeMode:'approval-required',interactionMode:'default'}});
}
test('choosing a project opens a local draft without a server create, preserving the previous thread composer',async()=>{
 const p=page();await p.beginDraft('new-project');
 assert.deepEqual(p.remembered,['new-project']);assert.equal(p.page,'chat');assert.equal(p.draftMode,true);assert.equal(p.threadId,'');assert.equal(p.projectId,'new-project');assert.equal(p.prompt,'');
 assert.equal(p.textDrafts.get('a\nT:old'),'old text');assert.equal(p.panelOpen,false);assert.deepEqual(p.messages,[]);assert.deepEqual(p.actions,[]);
 assert.equal(p.draftRecords.length,1);assert.equal(p.draftRecords[0].draftId,p.activeDraftId);assert.equal(p.draftRecords[0].projectId,'new-project');
});
test('draft text, model and workspace survive project changes without colliding across environments',async()=>{
 const p=page();await p.beginDraft('p');const first=p.activeDraftId;p.prompt='draft A';
 p.taskSettings={modelSelection:{instanceId:'codex',model:'m',options:[{id:'effort',value:'high'}]},runtimeMode:'approval-required',interactionMode:'plan'};
 p.draftWorkspace={mode:'worktree',branch:'main',worktreePath:'',startFromOrigin:true};
 await p.beginDraft('q');p.prompt='draft Q';await p.beginDraft('p',first);
 assert.equal(p.prompt,'draft A');assert.equal(p.taskSettings.interactionMode,'plan');assert.equal(p.draftWorkspace.mode,'worktree');
 p.selectedLocalId='b';p.draftMode=false;await p.beginDraft('p');assert.equal(p.prompt,'');assert.equal(p.taskSettings.interactionMode,'default');
 assert.equal(p.draftRecords.find(d=>d.draftId===first).text,'draft A');
});
test('a draft cannot replace another composer while its first send is pending or unresolved',async()=>{
 for(const state of [{busy:true},{unknown:true}]){
  const p=page();Object.assign(p,state);await p.beginDraft('new');assert.equal(p.projectId,'old-project');assert.equal(p.prompt,'old text');assert.equal(p.draftMode,false);
 }
});
const sendMethod=source.slice(source.indexOf('  private async send()'),source.indexOf('  private async stop()'));
test('unknown first submission transfers its draft to the allocated thread without resurrecting it as a new task',async()=>{
 const owner={recovery:{threadId:'allocated',pendingId:'m'},attachments:[],async launch(){throw Error('lost acknowledgement')}};
 const SendPage=new Function('client',compile('return class { '+sendMethod+' }'))(owner);
 const settings={modelSelection:{instanceId:'codex',model:'m'},runtimeMode:'approval-required',interactionMode:'default'};
 const draft={draftId:'d1',localId:'a',projectId:'p',text:'first'};
 const p=Object.assign(new SendPage(),{selectedLocalId:'a',draftMode:true,activeDraftId:'d1',projectId:'p',prompt:'first',taskSettings:settings,
   draftWorkspace:emptyWorkspace(),draftContext:[],draftRecords:[draft],textDrafts:new Map(),drafts:new Map([['a\nD:d1','first']]),settingsDrafts:new Map(),
  contextDrafts:new Map(),
   draftKey:()=> 'a\nD:d1',deleteDraft:async()=>{},incomingPairing(){},persistDraft:async()=>{}});
 await p.send();assert.equal(p.draftMode,false);assert.equal(p.threadId,'allocated');
 assert.equal(p.textDrafts.get('a\nT:allocated'),'first');
});

test('new drafts consume resolved defaults while restored drafts keep their saved choices',async()=>{
 const p=page();let reads=0;
 p.newDraftDefaults=async()=>{reads++;return {runtimeMode:'auto-accept-edits',workspace:{mode:'worktree',branch:'',worktreePath:'',startFromOrigin:false}}};
 await p.beginDraft('p');const id=p.activeDraftId;
 assert.equal(p.taskSettings.runtimeMode,'auto-accept-edits');assert.equal(p.draftWorkspace.mode,'worktree');assert.equal(p.draftWorkspace.startFromOrigin,false);
 p.newDraftDefaults=async()=>{throw Error('must not read for existing draft')};
 await p.beginDraft('p',id);assert.equal(reads,1);assert.equal(p.taskSettings.runtimeMode,'auto-accept-edits');
});
test('defaults failure leaves the old composer intact and concurrent new draft cannot overtake its read',async()=>{
 const p=page();let reject;let reads=0;
 p.newDraftDefaults=async()=>{reads++;return await new Promise((_,r)=>{reject=r})};
 const pending=p.beginDraft('p');assert.equal(p.busy,true);
 await p.beginDraft('q');assert.equal(reads,1);
 reject(Error('environment changed'));await pending;
 assert.equal(p.busy,false);assert.equal(p.draftMode,false);assert.equal(p.projectId,'old-project');assert.equal(p.prompt,'old text');assert.equal(p.draftRecords.length,0);
});

test('defaults read is bound to selected environment and project until it returns',async()=>{
 const helper=source.slice(source.indexOf('  private async newDraftDefaults('),source.indexOf('  private async beginDraft('));
 for(const mutate of [p=>p.selectedLocalId='other',p=>p.page='home',p=>p.scopedProjects[0].workspaceRoot='/changed']) {
  let finish;
  const owner={ready:true,generationValue:()=>3};
  const ReadPage=new Function('client','readDraftDefaults',compile('return class { '+helper+' }'))(owner,async()=>await new Promise(r=>finish=r));
  const p=Object.assign(new ReadPage(),{selectedLocalId:'e',page:'choose-project',scopedProjects:[{id:'p',localId:'e',environmentId:'env',workspaceRoot:'/repo',archivedAt:''}],scopedThreads:[]});
  const pending=p.newDraftDefaults('p');mutate(p);finish({runtimeMode:'auto',workspace:emptyWorkspace()});
  await assert.rejects(pending,/变化/);
 }
});

test('draft mode exposes project switching and retargets active drafts across projects and environments',async()=>{
 assert.match(source,/accessibilityDescription\('切换项目'\)\.onClick\(\(\) => this\.openProjectPicker\(false, true\)\)/);
 assert.match(source,/label:\s*'切换项目'[\s\S]*?onTap:\s*\(\) => this\.openProjectPicker\(false, true\)/);
 assert.match(source,/if \(this\.draftMode\) this\.openProjectPicker\(false, true\);/);

 const pickerMethods = source.slice(source.indexOf('  private openProjectPicker('), source.indexOf('  private pickerGroups(')) +
   '\n' + source.slice(source.indexOf('  private closeProjectPicker('), source.indexOf('  private async chooseProject('));
 const PickerPage = new Function(compile('return class { ' + pickerMethods + ' }'))();
 const picker = Object.assign(new PickerPage(), {
   keyboard: { reset() {} }, ready: true, environmentEntries: [], draftMode: true, activeDraftId: 'd-active',
   draftSaveTimer: 0, draftRecords: [{ draftId: 'd-active', text: 'stale' }],
   draftRecord: () => ({ draftId: 'd-active', text: 'fresh typed text' }),
   persistDraft: async () => {}, page: 'chat', panelOpen: true, choosingShare: false, pendingDraftId: '', projectPickerReturn: 'sessions'
 });
 picker.openProjectPicker(false, true);
 assert.equal(picker.page, 'choose-project');
 assert.equal(picker.pendingDraftId, 'd-active');
 assert.equal(picker.projectPickerReturn, 'chat');
 assert.equal(picker.panelOpen, false);
 assert.equal(picker.draftRecords[0].text, 'fresh typed text');
 picker.closeProjectPicker();
 assert.equal(picker.page, 'chat');
 assert.equal(picker.pendingDraftId, '');
 assert.equal(picker.projectPickerReturn, 'sessions');

 const p = page('env-a');
 await p.beginDraft('proj-a');
 const activeId = p.activeDraftId;
 p.prompt = 'keep this prompt';
 p.draftWorkspace = { mode: 'worktree', branch: 'feat-old', worktreePath: '/old/wt', startFromOrigin: false };
 p.draftContext = [
   { version: 1, kind: 'mention', contextId: 'm1', label: 'old.ts', payload: { path: 'old.ts' } },
   { version: 1, kind: 'skill', contextId: 's1', label: 'skill:test', payload: { name: 'test' } }
 ];
 client.attachments = [{ type: 'image', id: 'att-1', name: 'a.png', mimeType: 'image/png', sizeBytes: 123 }];
 p.attachments = client.attachments.slice();
 await p.persistDraft();

 p.newDraftDefaults = async (projectId) => ({
   runtimeMode: projectId === 'proj-b' ? 'auto-accept-edits' : 'full-access',
   workspace: { mode: 'local', branch: 'main', worktreePath: '', startFromOrigin: true }
 });
 const sameEnvProject = { id: 'proj-b', label: 'Project B', localId: 'env-a', environmentId: 'env-a' };
 const retargetedSame = await p.retargetDraft(sameEnvProject, activeId);
 assert.equal(retargetedSame, true);
 assert.equal(p.projectId, 'proj-b');
 assert.equal(p.activeDraftId, activeId);
 assert.equal(p.draftRecords.length, 1);
 assert.equal(p.prompt, 'keep this prompt');
 assert.deepEqual(p.draftWorkspace, { mode: 'local', branch: 'main', worktreePath: '', startFromOrigin: true });
 assert.deepEqual(p.draftContext.map(item => item.kind), ['skill']);
 assert.equal(p.attachments.length, 1);
 assert.equal(p.remembered[p.remembered.length - 1], 'proj-b');

 p.selectedLocalId = 'env-b';
 p.draftEnvironment = () => 'eid-b';
 p.models = [{ instanceId: 'claude', model: 'sonnet' }];
 const otherEnvProject = { id: 'proj-c', label: 'Project C', localId: 'env-b', environmentId: 'eid-b' };
 const retargetedOther = await p.retargetDraft(otherEnvProject, activeId);
 assert.equal(retargetedOther, true);
 assert.equal(p.projectId, 'proj-c');
 assert.equal(p.prompt, 'keep this prompt');
 assert.equal(p.attachments.length, 0);
 assert.deepEqual(p.taskSettings.modelSelection, { instanceId: 'claude', model: 'sonnet' });
 assert.equal(p.taskSettings.runtimeMode, 'full-access');
 assert.match(p.status, /附件未带入/);
});

test('composer exposes direct gallery button and dynamically adjusts attachment menu items by state', () => {
 assert.match(source, /Image\(\$r\('app\.media\.ui_image'\)\)[\s\S]*?accessibilityText\('从图库选择图片'\)[\s\S]*?this\.attach\('photo'\)/);
 assert.match(source, /\.bindMenu\(this\.composerAttachmentMenu\(this\.uploadingAttachment, this\.canRetryAttachment, this\.attachments\.length > 0\)\)/);

 const menuMethod = source.slice(
  source.indexOf('  private composerAttachmentMenu('),
  source.indexOf('  private async acknowledge()')
 );
 const MenuPage = new Function(compile('return class { ' + menuMethod + ' }'))();
 const page = new MenuPage();

 assert.deepEqual(
  page.composerAttachmentMenu(false, false, false).map((item) => item.value),
  ['从图库选择', '选择文件', '粘贴结构化上下文']
 );
 assert.deepEqual(
  page.composerAttachmentMenu(true, false, false).map((item) => item.value),
  ['取消上传', '粘贴结构化上下文']
 );
 assert.deepEqual(
  page.composerAttachmentMenu(false, true, false).map((item) => item.value),
  ['从图库选择', '选择文件', '重试上传', '粘贴结构化上下文']
 );
 assert.deepEqual(
  page.composerAttachmentMenu(false, false, true).map((item) => item.value),
  ['从图库选择', '选择文件', '粘贴结构化上下文', '清空附件']
 );
 assert.deepEqual(
  page.composerAttachmentMenu(false, true, true).map((item) => item.value),
  ['从图库选择', '选择文件', '重试上传', '粘贴结构化上下文', '清空附件']
 );
});

test('new drafts adopt resolved defaultModelSelection with options and retarget uncustomized drafts across projects', async () => {
  const clientWithConfig = {
    bindDraftAttachments() {},
    config: {
      providers: [
        { instanceId: 'codex', driver: 'codex' },
        { instanceId: 'antigravity', driver: 'antigravity' }
      ],
      settings: {
        projectSettingsOverrides: {
          'proj-disabled': { providerInstances: { antigravity: { enabled: false } } }
        }
      }
    }
  };
  const ConfiguredPage = new Function('client', 'util', 'emptyWorkspace', 'draftSettings', 'draftStore', 'emptyWorkMap', 'emptyFloatingCapsule',
    compile('return class { ' + methods + ' }'))(clientWithConfig, util, emptyWorkspace, draftSettings, draftStore, emptyWorkMap, emptyFloatingCapsule);
  const p = Object.assign(new ConfiguredPage(), {
    selectedLocalId: 'env-a', threadId: '', draftMode: false, projectId: '', prompt: '',
    remembered: [], rememberProject() {}, activeDraftId: '', draftRecords: [],
    textDrafts: new Map(), settingsDrafts: new Map(), contextDrafts: new Map(),
    models: [{ instanceId: 'codex', model: 'grok' }, { instanceId: 'antigravity', model: 'gemini-4-neon' }, { instanceId: 'codex', model: 'deepseek' }],
    source: { update() {} }, picker: { clear() {} }, panelOpen: false, draftWorkspace: emptyWorkspace(),
    draftContext: [], attachments: [], branches: [], branchesLoading: false, commandPanel: '', sendMode: 'auto',
    messages: [], actions: [], tools: [], linkItems: [], queued: [], extraPlans: [], extraSubagents: [],
    extraGuest: undefined, extraUsage: undefined, draftEnvironment: () => 'env-a', loadBranches: async () => {},
    persistDraft: async function() { const r = this.draftRecord(); if (r) this.draftRecords = [r, ...this.draftRecords.filter(d => d.draftId !== r.draftId)]; },
    taskSettings: { modelSelection: { instanceId: '', model: '' }, runtimeMode: 'approval-required', interactionMode: 'default' },
    newDraftDefaults: async (projectId) => ({
      runtimeMode: 'full-access',
      workspace: emptyWorkspace(),
      modelSelection: projectId === 'proj-a'
        ? { instanceId: 'antigravity', model: 'gemini-4-neon', options: [{ id: 'thought_level', value: 'xhigh' }] }
        : { instanceId: 'codex', model: 'deepseek', options: [{ id: 'reasoningEffort', value: 'max' }] }
    })
  });

  await p.beginDraft('proj-a');
  assert.deepEqual(p.taskSettings.modelSelection, { instanceId: 'antigravity', model: 'gemini-4-neon', options: [{ id: 'thought_level', value: 'xhigh' }] });
  assert.equal(p.draftModelCustomized, false);

  // Uncustomized draft switches to new project's default model when retargeted
  const draftId = p.activeDraftId;
  await p.retargetDraft({ id: 'proj-b', label: 'B', localId: 'env-a', environmentId: 'env-a' }, draftId);
  assert.deepEqual(p.taskSettings.modelSelection, { instanceId: 'codex', model: 'deepseek', options: [{ id: 'reasoningEffort', value: 'max' }] });

  // Customized draft keeps explicit model if selectable in target project, else resets to target project's default
  p.taskSettings = { ...p.taskSettings, modelSelection: { instanceId: 'antigravity', model: 'gemini-4-neon', options: [{ id: 'thought_level', value: 'high' }] } };
  p.draftModelCustomized = true;
  await p.persistDraft();
  await p.retargetDraft({ id: 'proj-a', label: 'A', localId: 'env-a', environmentId: 'env-a' }, draftId);
  assert.deepEqual(p.taskSettings.modelSelection, { instanceId: 'antigravity', model: 'gemini-4-neon', options: [{ id: 'thought_level', value: 'high' }] });
  assert.equal(p.draftModelCustomized, true);

  await p.retargetDraft({ id: 'proj-disabled', label: 'Disabled', localId: 'env-a', environmentId: 'env-a' }, draftId);
  assert.deepEqual(p.taskSettings.modelSelection, { instanceId: 'codex', model: 'deepseek', options: [{ id: 'reasoningEffort', value: 'max' }] });
  assert.equal(p.draftModelCustomized, false);
});

test('TaskSettingsPanel watches settings prop and mounts only while panelOpen is true', async () => {
  const panelSource = await readFile(new URL('../entry/src/main/ets/components/TaskSettingsPanel.ets', import.meta.url), 'utf8');
  assert.match(panelSource, /@Prop\s+@Watch\('syncSettings'\)\s+settings:\s*TaskSettings\b/);
  assert.match(source, /this\.panelOpen\s*&&\s*this\.panel\s*===\s*'task-settings'/);
});
