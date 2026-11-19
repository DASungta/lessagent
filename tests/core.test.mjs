import test from 'node:test';
import assert from 'node:assert/strict';
import { coreUrl } from './load-core.mjs';
const { ShellState, models, cards, markdown, respondCommand, secretAnswer, secretReferenceAnswer, stopCommand, answerSelected, inputAnswers } = await import(coreUrl);
import { ThreadState } from '../entry/src/main/ets/protocol/Wire.ts';
test('shell updates deduplicate and remove archived threads and projects', () => {
 const s=new ShellState();
 s.apply({kind:'snapshot',snapshot:{snapshotSequence:4,projects:[{id:'p',title:'P'}],threads:[{id:'t',title:'T',projectId:'p'}]}});
 s.apply({kind:'thread.updated',sequence:5,location:'active',thread:{id:'t',title:'New',projectId:'p'}});
 s.apply({kind:'thread.updated',sequence:5,location:'active',thread:{id:'t',title:'Stale',projectId:'p'}});
 assert.equal(s.threads[0].label,'New');
 s.apply({kind:'thread.updated',sequence:6,location:'archive',thread:{id:'t',title:'New',projectId:'p'}});
 assert.equal(s.threads.length,0);
 s.apply({kind:'project.removed',sequence:7,projectId:'p'});assert.equal(s.projects.length,0);
 assert.throws(()=>s.apply({kind:'project.updated',sequence:8,project:{id:12,title:'bad'}}));
});
test('provider models preserve exact instance and model identifiers',()=>{
 assert.deepEqual(models({providers:[{instanceId:'c',models:[{slug:'m',name:'Model'}]}]}),[{instanceId:'c',model:'m',label:'c / Model'}]);
});
test('snapshot and events expose only pending actionable requests and separate secrets',()=>{
 const state=new ThreadState('t');
 const req={id:'r',status:'pending',responseCapability:{type:'live'}};
 const item={id:'a',type:'approval_request',requestId:'r',requestKind:'command',prompt:'run test'};
 state.apply({kind:'snapshot',snapshotSequence:1,projection:{thread:{id:'t'},messages:[],runtimeRequests:[req],turnItems:[item]}});
 assert.equal(cards(state.requests,state.items)[0].kind,'approval');
 state.apply({kind:'event',sequence:2,event:{threadId:'t',type:'runtime-request.updated',payload:{...req,status:'resolved'}}});
 assert.equal(cards(state.requests,state.items).length,0);
 const secret={id:'s',type:'secret_request',secretStatus:'pending',label:'Password',reason:'Test'};
 assert.equal(cards([], [secret])[0].kind,'secret');
 assert.deepEqual(secretAnswer('t','s','value',false),{threadId:'t',turnItemId:'s',answer:{type:'save',secret:'value'}});
 assert.ok(!JSON.stringify(respondCommand('c','t','r','decline',{})).includes('secret'));
 assert.equal(stopCommand('c','t').type,'thread.stop');
 assert.equal(respondCommand('c','t','r','acceptAlways',{}).decision,'acceptAlways');
 assert.throws(()=>respondCommand('c','t','r','bogus',{}));
});
test('inherited secret requests are read-only and only http pages are exposed',()=>{
 const inherited={id:'s',type:'secret_request',secretStatus:'pending',label:'Password',reason:'Test',
  visibility:'inherited',url:'javascript:alert(1)'};
 const card=cards([],[inherited])[0];
 assert.equal(card.kind,'secret');assert.equal(card.enabled,false);assert.equal(card.secretUrl,'');
 assert.match(card.label,/等待在原会话中回答/);
 const local=cards([],[{...inherited,visibility:'local',url:'https://accounts.example/auth'}])[0];
 assert.equal(local.enabled,true);assert.equal(local.secretUrl,'https://accounts.example/auth');
});
test('message-capability user input can be dismissed even when the request is live',()=>{
 const card=cards([{id:'r',status:'pending',responseCapability:{type:'live'}}],
  [{id:'i',requestId:'r',type:'user_input_request',questions:[],responseMode:'message'}])[0];
 assert.equal(card.canDismiss,true);
 assert.throws(()=>secretReferenceAnswer('t','s','provider','a\nb'),/秘密引用无效/);
});
test('Markdown code blocks preserve literal content including incomplete streaming blocks',()=>{
 assert.deepEqual(markdown('# Title\n```js\nx < y\n```'),[{kind:'heading',text:'Title'},{kind:'code',text:'x < y'}]);
 assert.deepEqual(markdown('```\npartial'),[{kind:'code',text:'partial'}]);
});
test('input cards preserve custom option values, required flags and multiple selections',()=>{
 const q={id:'q',header:'Choose',question:'Which?',options:[{label:'A',value:'a',description:'first'}],multiSelect:true,allowCustomAnswer:false,required:true};
 const result=cards([{id:'r',status:'pending',responseCapability:{type:'not_resumable'}}],[{id:'i',requestId:'r',type:'user_input_request',questions:[q]}]);
 assert.equal(result[0].enabled,false);assert.equal(result[0].questions[0].multi,true);
 assert.deepEqual(result[0].questions[0].values,['a']);assert.equal(result[0].questions[0].custom,false);
});
test('repository identity enrichment snapshots cannot erase project or thread pickers',()=>{
 const s=new ShellState();
 s.apply({kind:'snapshot',snapshot:{snapshotSequence:4,projects:[{id:'p',title:'P'}],threads:[{id:'t',title:'T',projectId:'p'}]}});
 s.apply({kind:'snapshot',resolvedRepositoryIdentityRoots:['/tmp/test'],snapshot:{snapshotSequence:5,projects:[],threads:[],archivedThreads:[]}});
 assert.equal(s.projects.length,1);assert.equal(s.threads[0].id,'t');assert.equal(s.cursor,4);
 s.apply({kind:'thread.removed',sequence:6,location:'archive',threadId:'t'});
 assert.equal(s.threads[0].id,'t');
 s.apply({kind:'thread.removed',sequence:7,location:'active',threadId:'t'});assert.equal(s.threads.length,0);
});

test('input option selection reflects single and multiple answers',()=>{
 assert.equal(answerSelected('a','a'),true);assert.equal(answerSelected(['a','b'],'b'),true);
 assert.equal(answerSelected(undefined,'a'),false);assert.equal(answerSelected(['a'],'b'),false);
});

test('input question identifiers cannot mutate answer prototypes',()=>{
 const result=inputAnswers(new Map([['__proto__',['Blue']],['constructor','Green']]));
 assert.equal(Object.getPrototypeOf(result),Object.prototype);
 assert.deepEqual(result['__proto__'],['Blue']);assert.equal(JSON.parse(JSON.stringify(result)).constructor,'Green');
});

test('an empty user input request remains an input card instead of an approval',()=>{
 assert.equal(cards([{id:'r',status:'pending',responseCapability:{type:'live'}}],
  [{id:'i',requestId:'r',type:'user_input_request',questions:[]}])[0].kind,'input');
});

test('upload target rejects external, expired, traversal and oversized capabilities', async()=>{
 const {uploadTarget}=await import('./load-core.mjs').then(m=>import(m.coreUrl));
 const valid={relativeUrl:'/api/attachments/upload/signed.token',attachmentId:'pending-id',expiresAt:Date.now()+60000};
 assert.equal(uploadTarget(valid,10,'a.txt').attachment.type,'file');
 for(const relativeUrl of ['https://evil/api/attachments/upload/x','//evil/x','/api/attachments/upload/../x','/api/attachments/upload/..','/api/attachments/upload/x?token=secret']){
  assert.throws(()=>uploadTarget({...valid,relativeUrl},10,'a.txt'));
 }
 assert.throws(()=>uploadTarget({...valid,expiresAt:0},10,'a.txt'));
 assert.throws(()=>uploadTarget(valid,10*1024*1024+1,'a.txt'));
});
test('peer access respects explicit grants and status preserves expiry/unreachable failures',async()=>{
 const {peerAccessGranted,peerLinkViews,peerLinkStatus}=await import(coreUrl);
 assert.equal(peerAccessGranted({authenticated:true,scopes:['access:read'],permissions:[]},false),false);
 assert.equal(peerAccessGranted({authenticated:true,scopes:['access:read']},false),true);
 assert.equal(peerAccessGranted({authenticated:false,permissions:['access:write']},true),false);
 assert.equal(peerAccessGranted(undefined,true),false);
 assert.equal(peerAccessGranted({authenticated:true,permissions:['access:read',{}]},false),false);
 const now=Date.now();const row={environmentId:'peer',label:'Peer',status:'reachable',expiresAt:new Date(now+86400000).toISOString(),lastError:null};
 const [link]=peerLinkViews({links:[row]});assert.equal(peerLinkStatus(link,now),'1 天后过期');
 assert.match(peerLinkStatus({...link,expiresAt:now},now),/已过期/);assert.equal(peerLinkStatus({...link,status:'unreachable',lastError:'offline'},now),'offline');
 assert.throws(()=>peerLinkViews({links:[{...row,status:'unknown'}]}));
});
test('link requests retain thread provenance and answer payloads contain only intended fields',async()=>{
 const {linkRequests,linkAnswerPayload,peerPairingScopes}=await import(coreUrl);
 const item={id:'link',threadId:'t',type:'link_request',reason:'test',linkStatus:'pending'};
 assert.equal(linkRequests([item],'t')[0].visibility,'local');assert.equal(linkRequests([{...item,threadId:'other',visibility:'local'}],'t')[0].visibility,'inherited');
 assert.throws(()=>linkRequests([{...item,linkStatus:'unknown'}],'t'));
 assert.deepEqual(linkAnswerPayload('t','link',{type:'decline',pairingCode:'MUST_NOT_PASS'}),{threadId:'t',turnItemId:'link',answer:{type:'decline'}});
 assert.deepEqual(linkAnswerPayload('t','link',{type:'use-existing',environmentId:'peer',pairingCode:'MUST_NOT_PASS'}).answer,{type:'use-existing',environmentId:'peer'});
 assert.deepEqual(linkAnswerPayload('t','link',{type:'link',urls:['https://peer'],access:'read-only',pairingCode:' code '}).answer,{type:'link',urls:['https://peer'],access:'read-only',pairingCode:'code'});
 assert.throws(()=>linkAnswerPayload('t','link',{type:'link',urls:['https://user:pass@peer'],access:'read-only',pairingCode:'code'}));
 assert.throws(()=>linkAnswerPayload('t','link',{type:'link',urls:['https://peer'],access:'unknown',pairingCode:'code'}));
 assert.deepEqual(peerPairingScopes('read-only'),['orchestration:read']);assert.deepEqual(peerPairingScopes('full-access'),['orchestration:read','orchestration:operate','settings:write','source-control:write']);
});

test('the captured real Replay link card is actionable only in its own thread',async()=>{
 const {readFile}=await import('node:fs/promises');
 const fixture=JSON.parse(await readFile(new URL('../docs/evidence/r1/replay-link-request.json',import.meta.url),'utf8'));
 const {linkRequests}=await import(coreUrl);
 const [card]=linkRequests([fixture.card],fixture.threadId);
 assert.equal(card.status,'pending');assert.equal(card.visibility,'local');assert.equal(card.access,'read-only');
 assert.equal(linkRequests([fixture.card],'another-thread')[0].visibility,'inherited');
});
