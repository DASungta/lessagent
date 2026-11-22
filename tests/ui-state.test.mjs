import { projectsUrl } from './load-projects.mjs';
const { attachPendingSubagentRequests, projectGroupRefs } = await import(projectsUrl);
import { previewTabs } from '../entry/src/main/ets/protocol/Preview.ts';
import { followUpDelivery } from '../entry/src/main/ets/protocol/Settings.ts';
globalThis.__uiFollowUpDelivery = followUpDelivery;
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import { compile, data, r4Url, threadItemsUrl } from './load-core.mjs';
const { emptyWorkMap } = await import(threadItemsUrl);
const ts=createRequire(import.meta.url)((process.env.DEVECO_HOME || '/Applications/DevEco-Studio.app/Contents')+'/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source=await readFile(new URL('../entry/src/main/ets/pages/Index.ets',import.meta.url),'utf8');
const method=source.slice(source.indexOf('  private async send()'),source.indexOf('  private async stop()'));
const code=ts.transpileModule("const followUpDelivery=globalThis.__uiFollowUpDelivery; const workspacePrefs={followUpBehavior:'steer'}; return class { "+method+' }',{compilerOptions:{target:ts.ScriptTarget.ES2022}}).outputText;
test('send acknowledgement clears only the submitted draft, preserving text typed while waiting',async()=>{
 for(const newer of ['', 'next task']) {
  let resolve;
  const client={attachments:[],send:()=>new Promise(r=>resolve=r)};
  const Page=new Function('client',code)(client);
  const page=new Page();Object.assign(page,{incomingPairing:()=>{},prompt:'original',draftMode:false,activeDraftId:'',threadId:'thread',draftContext:[],sendMode:'auto',textDrafts:new Map([['a\nT:thread','original']]),contextDrafts:new Map(),selectedLocalId:'a',draftKey:()=> 'a\nT:thread'});
  const pending=page.send();
  if(newer) { page.prompt=newer; page.textDrafts.set('a\nT:thread',newer); }
  resolve();await pending;
  assert.equal(page.prompt,newer);assert.equal(page.busy,false);
  if(!newer) assert.equal(page.textDrafts.has('a\nT:thread'),false);
 }
});
test('failed send retains the draft and exposes the error',async()=>{
 const Page=new Function('client',code)({attachments:[],send:async()=>{throw Error('offline');}});
 const page=new Page();Object.assign(page,{incomingPairing:()=>{},prompt:'original',draftKey:()=> 'thread',drafts:new Map()});
 await page.send();assert.equal(page.prompt,'original');assert.equal(page.status,'offline');assert.equal(page.busy,false);
});
test('a created thread is not resubmitted when local draft cleanup fails',async()=>{
 let launched=0,watched='';
 const client={attachments:[],launch:async()=>{launched++;return 'thread-new';},watch:async id=>{watched=id;}};
 const Page=new Function('client',code)(client);
 const page=new Page();Object.assign(page,{incomingPairing:()=>{},prompt:'task',draftMode:true,activeDraftId:'d1',
  threadId:'',projectId:'p',selectedLocalId:'a',taskSettings:{},draftWorkspace:{},draftContext:[],
  attachments:[],draftKey:()=> 'a\nD:d1',textDrafts:new Map(),persistDraft:async()=>{},
  contextDrafts:new Map(),
  deleteDraft:async()=>{throw Error('disk full');}});
 await page.send();
 assert.equal(launched,1);assert.equal(watched,'thread-new');assert.equal(page.draftMode,false);
 assert.equal(page.threadId,'thread-new');assert.equal(page.prompt,'');assert.match(page.status,/会话已创建/);
});
test('thread settings keep the changes that succeeded before a later step fails',async()=>{
 const method=source.slice(source.indexOf('  private async saveTaskSettings('),source.indexOf('  private async installProvider('));
 const compiled=ts.transpileModule('return class { '+method+' }',{compilerOptions:{target:ts.ScriptTarget.ES2022}}).outputText;
 const before={modelSelection:{instanceId:'a',model:'one'},runtimeMode:'approval-required',interactionMode:'default'};
 const wanted={modelSelection:{instanceId:'a',model:'two'},runtimeMode:'auto',interactionMode:'plan'};
 const client={configureThread:async()=>{},changeThreadMode:async(mode,interaction)=>{
  if(interaction) throw Error('mode rejected');
 }};
 const Page=new Function('client','validateTaskSettings',compiled)(client,()=>{});
 const page=new Page();Object.assign(page,{busy:false,unknown:false,projectId:'p',draftMode:false,taskSettings:before,
  status:'',panelOpen:true});
 await page.saveTaskSettings(wanted);
 assert.equal(page.taskSettings.modelSelection.model,'two');assert.equal(page.taskSettings.runtimeMode,'auto');
 assert.equal(page.taskSettings.interactionMode,'default');assert.match(page.status,/部分设置已生效/);
 assert.equal(page.panelOpen,true);assert.equal(page.busy,false);
});
test('light and dark text pairs meet normal text contrast',async()=>{
 const luminance=hex=>{const rgb=hex.slice(1).match(/../g).map(x=>parseInt(x,16)/255).map(x=>x<=.04045?x/12.92:((x+.055)/1.055)**2.4);return rgb[0]*.2126+rgb[1]*.7152+rgb[2]*.0722;};
 for(const theme of ['base','dark']) {
  const {color}=JSON.parse(await readFile(new URL(`../entry/src/main/resources/${theme}/element/color.json`,import.meta.url),'utf8'));
  const colors=Object.fromEntries(color.map(x=>[x.name,x.value]));
  for(const [fg,bg] of [['ink','screen'],['muted','screen'],['ink','card'],['muted','card'],['ink','group'],['muted','group'],['on_primary_fill','primary']]) {
   const a=luminance(colors[fg]),b=luminance(colors[bg]);assert.ok((Math.max(a,b)+.05)/(Math.min(a,b)+.05)>=4.5,`${theme} ${fg}/${bg}`);
  }
 }
});
test('native back dismisses the sheet first, then returns to the list',()=>{
 const method=source.slice(source.indexOf('  onBackPress()'),source.indexOf('  private projectOptions()'));
 const compiled=ts.transpileModule('return class { '+method+' }',{compilerOptions:{target:ts.ScriptTarget.ES2022}}).outputText;
 const Page=new Function(compiled)();const page=new Page();
 Object.assign(page,{panelOpen:true,page:'chat',keyboard:{reset(){}}});
 assert.equal(page.onBackPress(),true);assert.equal(page.panelOpen,false);assert.equal(page.page,'chat');
 assert.equal(page.onBackPress(),true);assert.equal(page.page,'sessions');assert.equal(page.onBackPress(),false);
 Object.assign(page,{page:'settings',settingsSection:'about'});
 assert.equal(page.onBackPress(),true);assert.equal(page.settingsSection,'');assert.equal(page.page,'settings');
 assert.equal(page.onBackPress(),true);assert.equal(page.page,'sessions');
});
test('environment binding scopes colliding thread drafts and clears displayed data before rebinding',()=>{
 const method=source.slice(source.indexOf('  private bindEnvironment()'),source.indexOf('  private async restoreAddress()'));
 const key=source.slice(source.indexOf('  private draftKey()'),source.indexOf('  private async watch('));
 const compiled=ts.transpileModule('return class { '+method+key+' }',{compilerOptions:{target:ts.ScriptTarget.ES2022}}).outputText;
 const entries=[{localId:'a',label:'A',base:'https://a'},{localId:'b',label:'B',base:'https://b'}];
 const a={status:'A',thread:{threadId:'same'},shell:{projects:[],threads:[],archived:[]},supports:()=>false,scratchWorkspaceRoot:''},b={status:'B',thread:{threadId:'same'},shell:{projects:[],threads:[],archived:[]},supports:()=>false,scratchWorkspaceRoot:''};
 const registry={directory:{entries,selectedLocalId:'b'},clients:new Map([['a',a],['b',b]]),entryVisible:()=>true};
 let bound;
 class Picker {constructor(owner){this.owner=owner}belongsTo(owner){return this.owner===owner}canRetry(){return false}}
 const Page=new Function('bindClient','AttachmentPicker','client','attachPendingSubagentRequests','buildProjectGroups','workspacePrefs','projectGroupRefs','emptyWorkMap',compiled)(v=>bound=v,Picker,b,attachPendingSubagentRequests,()=>[],{projectGroupingMode:'repository'},projectGroupRefs,emptyWorkMap);
 const page=new Page();Object.assign(page,{registry:()=>registry,selectedLocalId:'a',prompt:'draft A',threadId:'same',draftMode:false,activeDraftId:'',
   textDrafts:new Map(),settingsDrafts:new Map(),contextDrafts:new Map(),draftRecords:[],draftContext:[{contextId:'ctx-a'}],attachments:[],drafts:new Map(),pickers:new Map(),messages:['private A'],source:{update:()=>{}},panel:'server'});
 page.bindEnvironment();assert.equal(bound,b);assert.equal(page.prompt,'');assert.deepEqual(page.messages,[]);
 assert.deepEqual(page.draftContext,[]);
 page.prompt='draft B';registry.directory.selectedLocalId='a';page.bindEnvironment();assert.equal(page.prompt,'draft A');assert.equal(bound,a);
 assert.deepEqual(page.draftContext.map(item=>item.contextId),['ctx-a']);
 assert.equal(page.textDrafts.get('b\nT:same'),'draft B');
});
test('home project filters use scoped identity without inheriting the active chat project',()=>{
 const methods=source.slice(source.indexOf('  private visibleThreads()'),source.indexOf('  private openPanel('));
 const compiled=ts.transpileModule('return class { '+methods+' }',{compilerOptions:{target:ts.ScriptTarget.ES2022}}).outputText;
 const Page=new Function(compiled)();const page=new Page();
 Object.assign(page,{environmentFilter:'',projectFilterId:'',projectFilterLocalId:'',projectId:'same-project',selectedLocalId:'a',scopedProjects:[{localId:'a',id:'same-project',label:'A'},{localId:'b',id:'same-project',label:'B'}],scopedThreads:[{localId:'a',id:'same-thread',projectId:'same-project'},{localId:'b',id:'same-thread',projectId:'same-project'}]});
 assert.deepEqual(page.visibleThreads().map(t=>t.localId),['a','b']);
 page.filterProject(2);assert.deepEqual(page.visibleThreads().map(t=>t.localId),['b']);
 page.environmentFilter='a';page.filterProject(1);assert.deepEqual(page.visibleThreads().map(t=>t.localId),['a']);
 page.filterProject(0);page.environmentFilter='';assert.equal(page.visibleThreads().length,2);
});
test('late callbacks from a destroyed page cannot consume a pending pairing link',()=>{
 const method=source.slice(source.indexOf('  private incomingPairing()'),source.indexOf('  private registry()'));
 const code=ts.transpileModule("const followUpDelivery=globalThis.__uiFollowUpDelivery; const workspacePrefs={followUpBehavior:'steer'}; return class { "+method+' }',{compilerOptions:{target:ts.ScriptTarget.ES2022}}).outputText;
 let consumed=0;const Page=new Function('takePairingLink','AppStorage',code)(()=>{consumed++;return {base:'https://synthetic.invalid',code:'SYNTHETIC'}},{get:()=>''});
 const page=new Page();Object.assign(page,{alive:false,busy:false,openPanel:name=>page.panel=name});page.incomingPairing();assert.equal(consumed,0);
 page.alive=true;page.busy=true;page.incomingPairing();assert.equal(consumed,0);
 page.busy=false;page.incomingPairing();assert.equal(consumed,1);assert.equal(page.panel,'connection-new');assert.equal(page.address,'https://synthetic.invalid');
});
test('pairing confirmation survives connection status updates and a rejected link clears the staged secret',()=>{
 const method=source.slice(source.indexOf('  private incomingPairing()'),source.indexOf('  private registry()'));
 const code=ts.transpileModule("const followUpDelivery=globalThis.__uiFollowUpDelivery; const workspacePrefs={followUpBehavior:'steer'}; return class { "+method+' }',{compilerOptions:{target:ts.ScriptTarget.ES2022}}).outputText;
 let next={base:'https://synthetic.invalid',code:'SYNTHETIC'},error='';
 const Page=new Function('takePairingLink','AppStorage',code)(()=>{const result=next;next=undefined;return result},{get:()=>error,setOrCreate:(key,value)=>{error=value}});
 const page=new Page();Object.assign(page,{alive:true,busy:false,status:'已连接',openPanel:name=>page.panel=name});
 page.incomingPairing();assert.equal(page.status,'已连接');assert.match(page.pairingStatus,/请确认目标/);
 page.status='会话已同步';assert.match(page.pairingStatus,/请确认目标/);
 error='配对链接无效';page.incomingPairing();assert.equal(page.credential,'');assert.equal(page.pairingStatus,'配对链接无效');assert.equal(error,'');
});

test('the add-environment form dispatches explicitly to either a new environment or a saved alternate route',async()=>{
 const method=source.slice(source.indexOf('  private async connect()'),source.indexOf('  private draftKey()'));
 const compiled=ts.transpileModule('return class { '+method+' }',{compilerOptions:{target:ts.ScriptTarget.ES2022}}).outputText;
 const calls=[];
 const registry={async add(base,code){calls.push(['add',base,code]);},async addRoute(id,base,code){calls.push(['route',id,base,code]);}};
 const PairingTarget={pairingTarget:(base,code)=>({base,code})};
 const Page=new Function('pairingTarget','PairingTarget',compiled)(PairingTarget.pairingTarget,PairingTarget);
 for(const [routeFor,address] of [['', 'https://new'],['saved','https://alt']]) {
  const page=new Page();Object.assign(page,{loaded:true,busy:false,credential:'SYNTHETIC_CODE',address,routeFor,
   registry:()=>registry,incomingPairing:()=>{},loadLinkedEnvironments:()=>{},openPanel:panel=>page.panel=panel});
  await page.connect();assert.equal(page.credential,'');assert.equal(page.panel,'server');
 }
 assert.deepEqual(calls,[['add','https://new','SYNTHETIC_CODE'],['route','saved','https://alt','SYNTHETIC_CODE']]);
});

test('connect preserves pairing credential on network timeout and clears it on identity mismatch or success',async()=>{
 const method=source.slice(source.indexOf('  private async connect()'),source.indexOf('  private draftKey()'));
 const compiled=ts.transpileModule('return class { '+method+' }',{compilerOptions:{target:ts.ScriptTarget.ES2022}}).outputText;
 let mode='timeout';
 const registry={async add(){
  if(mode==='timeout')throw Error('HTTP /.well-known/t3/environment 连接超时（系统错误码 2300028）：请确认手机与电脑在同一局域网或 VPN/Tailnet 路由可达，并检查防火墙与端口');
  if(mode==='mismatch')throw Error('服务器身份已变化，未发送配对凭据');
 },async addRoute(){}};
 const Page=new Function('pairingTarget','PairingTarget',compiled)((base,code)=>({base,code}),{});
 const page=new Page();
 Object.assign(page,{loaded:true,busy:false,credential:'SYNTHETIC_CODE',address:'http://192.168.2.97:3773',routeFor:'',pairingError:false,
  registry:()=>registry,incomingPairing:()=>{},loadLinkedEnvironments:()=>{},openPanel:panel=>page.panel=panel});
 await page.connect();
 assert.equal(page.credential,'SYNTHETIC_CODE');
 assert.equal(page.pairingError,true);
 assert.match(page.pairingStatus,/2300028/);
 mode='mismatch';
 await page.connect();
 assert.equal(page.credential,'');
 assert.equal(page.pairingError,true);
 assert.match(page.pairingStatus,/服务器身份/);
 mode='ok';page.credential='SYNTHETIC_CODE';
 await page.connect();
 assert.equal(page.credential,'');
 assert.equal(page.pairingError,false);
 assert.equal(page.panel,'server');
});

test('terminal cannot write after environment or thread changes',()=>{
 const method=source.slice(source.indexOf('  private terminalOwner()'),source.indexOf('  private openFiles()'));
 const compiled=ts.transpileModule('return class { '+method+' }',{compilerOptions:{target:ts.ScriptTarget.ES2022}}).outputText;
 const owner={}; const Page=new Function('client',compiled)(owner); const page=new Page();
 Object.assign(page,{terminalConnection:owner,terminalThreadId:'one',threadId:'one'});
 assert.equal(page.terminalOwner(),owner);
 page.threadId='two';assert.throws(()=>page.terminalOwner(),/已变化/);
 page.threadId='one';page.terminalConnection={};assert.throws(()=>page.terminalOwner(),/已变化/);
});

test('locked startup retries on foreground without concurrent reconnect or lost state',async()=>{
 const restore=source.slice(source.indexOf('  private async restoreAddress()'),source.indexOf('  aboutToDisappear()'));
 const foreground=source.slice(source.indexOf('  private refreshLinkedOnForeground()'),source.indexOf('  private refreshLinkedWhenChanged()'));
 const compiled=ts.transpileModule('return class { '+restore+foreground+' }',{compilerOptions:{target:ts.ScriptTarget.ES2022}}).outputText;
 const Page=new Function(compiled)();const page=new Page();let attempts=0,reconnects=0,release;
 const registry={initialized:false,directory:{entries:[{localId:'saved',enabled:true}]},entryVisible:()=>true,onUpdate(){},
  async initialize(){if(++attempts===1)throw Error('locked');await new Promise(r=>release=r);this.initialized=true},async reconnect(){reconnects++}};
 Object.assign(page,{alive:true,loaded:false,restoringEnvironments:false,appForeground:true,registry:()=>registry,openShortcut:async()=>{},refreshLinkedWhenChanged(){}});
 await page.restoreAddress();assert.equal(page.loaded,false);assert.equal(page.status,'locked');assert.equal(reconnects,0);
 page.refreshLinkedOnForeground();page.refreshLinkedOnForeground();assert.equal(attempts,2);release();await new Promise(setImmediate);
 assert.equal(page.loaded,true);assert.equal(reconnects,1);assert.equal(registry.directory.entries[0].localId,'saved');
 page.refreshLinkedOnForeground();assert.equal(attempts,2);
});

test('share saves a distinct durable draft before removing inbox and never sends',async()=>{
 const method=source.slice(source.indexOf('  private shareChanged('),source.indexOf('  private openProjectPicker('));
 const compiled=ts.transpileModule('return class { '+method+' }',{compilerOptions:{target:ts.ScriptTarget.ES2022}}).outputText;
 const shareProtocol = (await readFile(new URL('../entry/src/main/ets/protocol/IncomingShare.ts', import.meta.url), 'utf8'))
   .replace("'./R4'", JSON.stringify(r4Url));
 const { shareDraftText } = await import(data(compile(shareProtocol)));
 for(const failure of [false,true]){
  let removed=false,opened=false,saved;const prior={draftId:'old',text:'keep'};
  const store={async save(rows){if(failure)throw Error('disk');saved=rows}};
  const original = [{id:1, kind:'text', text:'external'}, {id:2, kind:'text', text:'remove'},
    {id:3, kind:'link', text:'https://example.org'}];
  const Page=new Function('peekIncomingShare','MAX_SHARED_TEXT_CHARS','shareDraftText','draftStore','client','util',
    'AppStorage','removeIncomingShare','attachmentLimitError',compiled)(()=>({id:1,parts:original}),120000,shareDraftText,store,
      {models:[],ready:true,generationValue:()=>1},{generateRandomUUID:()=> 'new'},{get:()=>''},()=>{assert.ok(saved);removed=true},()=>'');
  const page=new Page();Object.assign(page,{appForeground:true,page:'share',shareId:0,selectedLocalId:'first',draftRecords:[prior],
    scopedProjects:[{localId:'e',id:'p',environmentId:'env'}],persistDraft:async()=>{},
    newDraftDefaults:async()=>({runtimeMode:'auto',workspace:{mode:'worktree',startFromOrigin:false}}),
    registry:()=>({select:async localId=>{page.selectedLocalId=localId}}),beginDraft:(p,id)=>{assert.equal(id,'new');opened=true}});
  page.shareChanged();
  page.editSharePart(1, 'edited external'); page.removeSharePart(2); page.shareChanged();
  await page.confirmShare();assert.equal(saved,undefined);
  Object.assign(page,{shareLocalId:'e',shareProjectId:'p',shareDestination:'chosen project'});
  await page.confirmShare();assert.equal(removed,!failure);assert.equal(opened,!failure);assert.equal(prior.text,'keep');
  if(!failure){assert.equal(saved[0].text,'edited external\n\nhttps://example.org');assert.equal(saved[0].runtimeMode,'auto');assert.equal(saved[0].workspace.mode,'worktree');assert.equal(saved[1],prior)}else assert.equal(page.shareError,'disk');
 }
});

test('file shares upload only after confirmation, retry acknowledged files once, and restore an attachment-only draft', async () => {
 const methods = source.slice(source.indexOf('  private shareChanged('), source.indexOf('  private openProjectPicker('));
 const code = compile('return class { ' + methods + ' }');
 const { attachmentLimitError, composerDraft } = await import(r4Url);
 const files = [{id:'stage-a',type:'file', name:'one.txt',mimeType:'text/plain',sizeBytes:3},
   {id:'stage-b',type:'file',name:'two.txt',mimeType:'text/plain',sizeBytes:3}];
 let acknowledged = 0, finish, saved, removed = false, opened = false;
 const uploads = [];
 const owner = { models:[],ready:true,generationValue:()=>1,attachments:[{id:'old'}],
   async uploadOne(name, bytes, mimeType, type, current) {
     assert.equal(current(),true); assert.equal(bytes.byteLength,3);
     uploads.push(name);
     if (name === 'two.txt' && acknowledged === 1) {
       return new Promise((_resolve,reject)=>{ finish=()=>reject(new Error('upload interrupted')); });
     }
     acknowledged++;
     return { id:'remote-' + name.replace('.txt',''),type,name,mimeType,sizeBytes:bytes.byteLength };
   },
   cancelUpload(){ finish?.(); },
 };
 const Page = new Function('peekIncomingShare','MAX_SHARED_TEXT_CHARS','shareDraftText','draftStore','client','util',
   'AppStorage','removeIncomingShare','attachmentLimitError','withStagedShareAttachment',code)(
   ()=>({id:1,parts:[],attachments:files}),120000,()=>'',
   {async save(rows){saved=rows}},owner,{generateRandomUUID:()=> 'new'},{get:()=>''},()=>{removed=true},attachmentLimitError,
   async(id,fileId,consume)=>{assert.equal(id,1);assert.ok(files.some(item=>item.id===fileId));await consume(new ArrayBuffer(3));});
 const previous = {draftId:'previous',attachments:[{id:'old'}]};
 const page = new Page();
 Object.assign(page,{page:'share',appForeground:true,shareId:0,selectedLocalId:'a',draftRecords:[previous],
   scopedProjects:[{localId:'a',id:'project',environmentId:'env'}],persistDraft:async()=>{},registry:()=>({select:async()=>{}}),
   newDraftDefaults:async()=>({runtimeMode:'approval-required',workspace:{mode:'local',branch:'',worktreePath:''}}),
   beginDraft:(_project,draftId)=>{assert.equal(draftId,'new');opened=true}});
 page.shareChanged();
 await page.confirmShare();
 assert.deepEqual(uploads,[]);
 Object.assign(page,{shareDestination:'env · project',shareLocalId:'a',shareProjectId:'project'});
 const pending = page.confirmShare();
 await new Promise(resolve=>setImmediate(resolve));
 page.cancelShareUpload();
 await pending;
 assert.equal(saved,undefined); assert.equal(removed,false); assert.equal(opened,false);
 assert.equal(page.shareUploadedCount,1);
 assert.match(page.shareError,/已取消上传/);
 acknowledged++;
 await page.confirmShare();
 assert.deepEqual(uploads,['one.txt','two.txt','two.txt']);
 const recovered = composerDraft(JSON.parse(JSON.stringify(saved[0])));
 assert.equal(recovered.text,'');
 assert.deepEqual(recovered.attachments.map(item=>item.id),['remote-one','remote-two']);
 assert.equal(saved[1],previous);
 assert.deepEqual(owner.attachments,[{id:'old'}]);
 assert.equal(removed,true); assert.equal(opened,true);
});

test('preview reopens only a server tab belonging to the current thread',async()=>{
 const method=source.slice(source.indexOf('  private async openPreview()'),source.indexOf('  private async createPreviewTab('));
 const compiled=ts.transpileModule('return class { '+method+' }',{compilerOptions:{target:ts.ScriptTarget.ES2022}}).outputText;
 const owner={generationValue:()=>7,async rpcRequest(){return {sessions:[{threadId:'other',runtime:'server',tabId:'bad',navStatus:{}},{threadId:'t',runtime:'desktop',tabId:'desktop',navStatus:{}},{threadId:'t',runtime:'server',tabId:'good',navStatus:{url:'http://localhost:1234'}}]}}};
 const Page=new Function('client','record','text','previewTabs',compiled)(owner,x=>x,x=>x,previewTabs);const page=new Page();
 Object.assign(page,{ready:true,threadId:'t',selectedLocalId:'env',previewTabs:new Map(),panelOpen:true});
 await page.openPreview();assert.equal(page.page,'preview');assert.equal(page.previewTabs.get('env:t'),'good');assert.equal(page.previewAddress,'http://localhost:1234');
});
test('voice only appends to the still-bound draft and never sends',()=>{
 const method=source.slice(source.indexOf('  private insertVoice('),source.indexOf('  private shareChanged('));
 const compiled=ts.transpileModule('return class { '+method+' }',{compilerOptions:{target:ts.ScriptTarget.ES2022}}).outputText;
 const Page=new Function('MAX_SHARED_TEXT_CHARS',compiled)(20);const page=new Page();let saves=0;
 Object.assign(page,{voiceTarget:'e:d',draftKey:()=> 'e:d',prompt:'old',page:'voice',scheduleDraftSave:()=>saves++,send(){throw Error('must not send')}});
 page.insertVoice('new');assert.equal(page.prompt,'old\nnew');assert.equal(saves,1);assert.equal(page.page,'chat');
 page.voiceTarget='other';page.insertVoice('bad');assert.equal(page.prompt,'old\nnew');assert.equal(saves,1);
 page.voiceTarget='e:d';page.insertVoice('x'.repeat(30));assert.equal(page.prompt,'old\nnew');assert.equal(saves,1);
});
test('notification click waits for initialization and rejects an old environment identity',async()=>{
 const method=source.slice(source.indexOf('  private async openNotificationTarget('),source.indexOf('  private insertVoice('));
 const compiled=ts.transpileModule('return class { '+method+' }',{compilerOptions:{target:ts.ScriptTarget.ES2022}}).outputText;
 const target={localId:'e',environmentId:'env',threadId:'t'};let clears=0,opened=0;
 const Page=new Function('peekNotificationTarget','clearNotificationTarget',compiled)(()=>target,()=>clears++);
 const page=new Page();const entry={localId:'e',environmentId:'env'};const thread={localId:'e',id:'t'};
 Object.assign(page,{alive:true,loaded:false,scopedThreads:[thread],registry:()=>({directory:{entries:[entry]},entryVisible:()=>true,clients:new Map([['e',{ready:true}]])}),openScopedThread:async value=>{assert.equal(value,thread);opened++}});
 await page.openNotificationTarget();assert.equal(clears,0);
 page.loaded=true;entry.environmentId='changed';await page.openNotificationTarget();assert.equal(clears,1);assert.equal(opened,0);
 entry.environmentId='env';await page.openNotificationTarget();assert.equal(clears,2);assert.equal(opened,1);
});

test('device open uses the returned booted identity and rejects another host',async()=>{
 const method=source.slice(source.indexOf('  private async openDevice('),source.indexOf('  private previewCurrent()'));
 const compiled=ts.transpileModule('return class { '+method+' }',{compilerOptions:{target:ts.ScriptTarget.ES2022}}).outputText;
 for(const hostId of ['local','other']){
  const owner={async rpcRequest(){return {threadId:'t',hostId,deviceId:'emulator-5554',platform:'android'}}};
  const Page=new Function('client','safeDeviceHubBase','record','text',compiled)(owner,x=>x,x=>x,x=>x);const page=new Page();
  Object.assign(page,{previewThreadId:'t',previewCurrent:()=>true,page:'device-picker'});
  const device={platform:'android',physical:false,hostId:'local',id:'Pixel'};
  if(hostId==='other'){await assert.rejects(page.openDevice(device,'/api/device-hub','local'),/身份/);assert.equal(page.page,'device-picker')}
  else{await page.openDevice(device,'/api/device-hub','local');assert.equal(page.deviceChoice.id,'emulator-5554');assert.equal(page.page,'android-device')}
 }
});

test('explicit media reconnect refreshes generation only for the original ready owner and thread',()=>{
 const method=source.slice(source.indexOf('  private rebindPreviewConnection()'),source.indexOf('  private previewCurrent()'));
 const compiled=ts.transpileModule('return class { '+method+' }',{compilerOptions:{target:ts.ScriptTarget.ES2022}}).outputText;
 const owner={ready:true,generationValue:()=>9};const Page=new Function('client',compiled)(owner);const page=new Page();
 Object.assign(page,{previewConnection:owner,previewThreadId:'t',threadId:'t',previewGeneration:1});
 page.rebindPreviewConnection();assert.equal(page.previewGeneration,9);
 page.threadId='other';assert.throws(()=>page.rebindPreviewConnection());page.threadId='t';owner.ready=false;assert.throws(()=>page.rebindPreviewConnection());
});

test('launcher shortcuts wait for initialization and preserve drafts before one navigation',async()=>{
 const method=source.slice(source.indexOf('  private async openShortcut('),source.indexOf('  private async openNotificationTarget('));
 const compiled=ts.transpileModule('return class { '+method+' }',{compilerOptions:{target:ts.ScriptTarget.ES2022}}).outputText;
 let pending={id:1,action:'new-task'};const events=[];
 const Page=new Function('peekShortcut','consumeShortcut','peekNotificationTarget',compiled)(()=>pending,id=>{if(pending?.id!==id)return false;pending=undefined;events.push('consume');return true},()=>undefined);
 const p=Object.assign(new Page(),{alive:true,ready:true,environmentEntries:[{enabled:true}],loaded:false,appForeground:true,shortcutDraftsLoaded:true,page:'chat',selectedLocalId:'e',draftMode:true,
  persistDraft:async()=>events.push('save'),startNewTask:async()=>events.push('new')});
 await p.openShortcut();assert.deepEqual(events,[]);
 p.loaded=true;p.ready=false;await p.openShortcut();assert.deepEqual(events,[]);p.ready=true;p.busy=true;await p.openShortcut();assert.deepEqual(events,[]);
 p.busy=false;await p.openShortcut();assert.deepEqual(events,['save','consume','new']);
 await p.openShortcut();assert.equal(events.length,3);
 pending={id:2,action:'sessions'};p.page='files';await p.openShortcut();assert.equal(p.page,'files');assert.match(p.status,/返回会话/);
 pending={id:3,action:'sessions'};p.page='chat';await p.openShortcut();assert.equal(p.page,'sessions');
});

test('home connection states prevent empty-thread flash before first shell snapshot and show non-blocking reconnect header with cached threads',()=>{
 const helpers = source.slice(source.indexOf('  private hasEnabledEnvironment()'), source.indexOf('  @Builder\n  iconButton('));
 const compiled = ts.transpileModule('return class { ' + helpers + ' }', { compilerOptions: { target: ts.ScriptTarget.ES2022 } }).outputText;
 const Page = new Function(compiled)();
 const page = Object.assign(new Page(), {
  loaded: true, restoringEnvironments: false, anyEnvironmentReady: true, anyEnvironmentHasShell: false,
  anyEnvironmentLiveSynced: false, reconnectingCount: 1, offlineCount: 0, status: '正在同步会话',
  environmentEntries: [{ localId: 'a', enabled: true, deleting: false }], scopedThreads: []
 });
 // Connection is ready but subscribeShell snapshot has not arrived yet: must stay in loading state, never flash empty thread list!
 assert.equal(page.homeWaitingForFirstSnapshot(), true);
 assert.equal(page.homeAllOfflineWithoutCache(), false);
 assert.equal(page.showHomeStatusBanner(), false);

 // Cached threads present while reconnecting: show non-blocking top-left reconnect indicator and suppress raw status strip
 page.scopedThreads = [{ id: 't1' }];
 page.anyEnvironmentHasShell = true;
 page.anyEnvironmentReady = false;
 page.reconnectingCount = 2;
 assert.equal(page.homeWaitingForFirstSnapshot(), false);
 assert.equal(page.homeShowReconnectingHeader(), true);
 assert.equal(page.homeConnectionLabel(), '正在重连 2 个环境');
 assert.equal(page.showHomeStatusBanner(), false);

 // Live sync completes with 0 threads: no longer waiting, safe to render empty ThreadList
 page.scopedThreads = [];
 page.anyEnvironmentReady = true;
 page.anyEnvironmentHasShell = true;
 page.anyEnvironmentLiveSynced = true;
 page.reconnectingCount = 0;
 assert.equal(page.homeWaitingForFirstSnapshot(), false);
 assert.equal(page.homeAllOfflineWithoutCache(), false);
 assert.equal(page.homeThreadListLoading(), false);
});

test('forkFromMessage forwards sourceThreadId and title, prevents duplicate forks, and ignores stale navigation', async () => {
 const methods = source.slice(source.indexOf('  private currentChatTitle()'), source.indexOf('  private refreshExtras()'));
 const compiled = ts.transpileModule('return class { ' + methods + ' }', { compilerOptions: { target: ts.ScriptTarget.ES2022 } }).outputText;
 const calls = [];
 const watched = [];
 let resolveFork;
 const mockClient = {
  thread: { threadId: 'child-t', details: { title: 'Fallback Title' } },
  canScope: () => true,
  forkThread: (runId, sideChat, sourceThreadId, title) => {
   calls.push({ runId, sideChat, sourceThreadId, title });
   return new Promise((r) => { resolveFork = r; });
  }
 };
 const Page = new Function('client', compiled)(mockClient);
 const page = Object.assign(new Page(), {
  alive: true, ready: true, busy: false, unknown: false, forkingMessageId: '',
  selectedLocalId: 'env-1', threadId: 'child-t', cachedChatTitle: 'Session Title',
  threads: [{ id: 'child-t', label: 'Session Title' }], panelOpen: true, status: '',
  async watch(id) { watched.push(id); }
 });

 const pending = page.forkFromMessage('msg-1', 'run-9', 'parent-t');
 assert.equal(page.busy, true);
 assert.equal(page.forkingMessageId, 'msg-1');
 // Concurrent second fork click while first is in-flight is ignored
 await page.forkFromMessage('msg-2', 'run-10', 'child-t');
 assert.equal(calls.length, 1);
 assert.deepEqual(calls[0], { runId: 'run-9', sideChat: false, sourceThreadId: 'parent-t', title: 'Session Title fork' });
 resolveFork('forked-thread-id');
 await pending;
 assert.deepEqual(watched, ['forked-thread-id']);
 assert.equal(page.busy, false);
 assert.equal(page.forkingMessageId, '');
 assert.equal(page.panelOpen, false);

 // If thread changed while fork was in-flight, do not hijack navigation
 const pendingStale = page.forkFromMessage('msg-3', 'run-11', 'child-t');
 page.threadId = 'other-thread';
 resolveFork('forked-stale-id');
 await pendingStale;
 assert.deepEqual(watched, ['forked-thread-id']);
 assert.equal(page.forkingMessageId, '');

 // Offline or missing scope blocks fork
 page.threadId = 'child-t';
 page.ready = false;
 await page.forkFromMessage('msg-4', 'run-12', 'child-t');
 assert.equal(calls.length, 2);

 // Light & dark SVG icons for copy/check/fork exist
 for (const theme of ['base', 'dark']) {
  for (const name of ['ui_copy.svg', 'ui_check.svg', 'ui_fork.svg']) {
   const svg = await readFile(new URL(`../entry/src/main/resources/${theme}/media/${name}`, import.meta.url), 'utf8');
   assert.ok(svg.includes('<svg') && svg.includes('viewBox="0 0 24 24"'), `${theme}/${name}`);
  }
 }
});
