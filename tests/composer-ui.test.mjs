import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {compile, threadItemsUrl} from './load-core.mjs';
const { emptyWorkMap } = await import(threadItemsUrl);
const source=await readFile(new URL('../entry/src/main/ets/pages/Index.ets',import.meta.url),'utf8');
const methods=source.slice(source.indexOf('  private draftKey()'),source.indexOf('  private openTaskSettings()'));
const emptyWorkspace=()=>({mode:'local',branch:'',worktreePath:'',startFromOrigin:true});
const draftSettings=d=>({modelSelection:d.modelSelection,runtimeMode:d.runtimeMode,interactionMode:d.interactionMode});
let counter=0;
const util={generateRandomUUID:()=>`draft-${++counter}`};
const draftStore={async save(){}};
const client={bindDraftAttachments(){}};
const Page=new Function('client','util','emptyWorkspace','draftSettings','draftStore','emptyWorkMap',compile('return class { '+methods+' }'))(client,util,emptyWorkspace,draftSettings,draftStore,emptyWorkMap);
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
