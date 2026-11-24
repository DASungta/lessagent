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
 assert.equal(result[0].questions[0].optionItems[0].label,'A');
 assert.equal(result[0].questions[0].optionItems[0].description,'first');
});

test('questionDisplays normalizes recommended options, suppresses boilerplate and nests companion Other prompts',async()=>{
 const { questionDisplays } = await import(coreUrl);
 const [card]=cards([{id:'r',status:'pending',responseCapability:{type:'live'}}],[{
  id:'i',requestId:'r',type:'user_input_request',questions:[
   {id:'q1',header:'图库入口你想放在哪里？',question:'The agent has 2 questions.',allowCustomAnswer:false,required:true,
    options:[
     {label:'(Recommended) 输入框栏直接放一个图库图标，点一下直接选照片',description:'(Recommended) 输入框栏直接放一个图库图标，点一下直接选照片'},
     {label:'只放在 + 菜单第一项',description:'保持输入框简洁',value:'plus_menu'}
    ]},
   {id:'q1_other',header:'Other',question:'Optional free-form answer to: 图库入口你想放在哪里？',allowCustomAnswer:true,required:false,options:[]},
   {id:'q2',header:'Layout',question:'How should extra items behave?',allowCustomAnswer:true,required:true,
    options:[{label:'Dynamic',description:'',preview:'preview text'}]}
  ]
 }]);
 assert.equal(card.questions[0].optionItems[0].recommended,true);
 assert.equal(card.questions[0].optionItems[0].label,'输入框栏直接放一个图库图标，点一下直接选照片');
 assert.equal(card.questions[0].optionItems[0].description,'');
 assert.equal(card.questions[0].optionItems[0].value,'(Recommended) 输入框栏直接放一个图库图标，点一下直接选照片');
 assert.equal(card.questions[0].optionItems[1].recommended,false);
 assert.equal(card.questions[0].optionItems[1].description,'保持输入框简洁');
 assert.equal(card.questions[0].optionItems[1].value,'plus_menu');
 assert.equal(card.questions[2].optionItems[0].preview,'preview text');

 const displays=questionDisplays(card.questions);
 assert.equal(displays.length,3);
 assert.equal(displays[0].companion,false);
 assert.equal(displays[0].ordinal,1);
 assert.equal(displays[0].primaryTotal,2);
 assert.equal(displays[0].eyebrow,'');
 assert.equal(displays[0].title,'图库入口你想放在哪里？');
 assert.equal(displays[1].companion,true);
 assert.equal(displays[1].ordinal,0);
 assert.equal(displays[2].companion,false);
 assert.equal(displays[2].ordinal,2);
 assert.equal(displays[2].eyebrow,'Layout');
 assert.equal(displays[2].title,'How should extra items behave?');
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

test('ShellState tracks cached vs live snapshots, preserves rows across reconnect reset, and validates cachedShellEntry',async()=>{
 const { ShellState, cachedShellEntry } = await import(coreUrl);
 const s = new ShellState();
 assert.equal(s.hasSnapshot, false);
 assert.equal(s.liveSynced, false);
 s.apply({ kind: 'snapshot', snapshot: { snapshotSequence: 8, projects: [{ id: 'p', title: 'Proj', workspaceRoot: '/w' }], threads: [{ id: 't', title: 'Task', projectId: 'p' }] } });
 assert.equal(s.hasSnapshot, true);
 assert.equal(s.liveSynced, true);

 // Reconnect reset keeps rows visible while allowing lower snapshot sequence after server restart
 s.resetForReconnect();
 assert.equal(s.hasSnapshot, true);
 assert.equal(s.liveSynced, false);
 assert.equal(s.cursor, -1);
 assert.equal(s.threads.length, 1);
 s.apply({ kind: 'snapshot', snapshot: { snapshotSequence: 1, projects: [{ id: 'p', title: 'Proj2', workspaceRoot: '/w' }], threads: [{ id: 't2', title: 'Fresh', projectId: 'p' }] } });
 assert.equal(s.liveSynced, true);
 assert.equal(s.threads[0].id, 't2');

 // Cache hydration validates fields, drops deleted threads, and never overwrites live state
 const validated = cachedShellEntry({
  environmentId: 'env-1',
  savedAt: Date.now(),
  scratchWorkspaceRoot: '/scratch',
  capabilities: { threadSettlement: true, ignored: 'nope' },
  projects: s.projects,
  threads: [...s.threads, { id: 'del', label: 'Gone', projectId: 'p', deletedAt: '2026-01-01T00:00:00Z' }]
 });
 assert.equal(validated.threads.length, 1);
 assert.deepEqual(validated.capabilities, { threadSettlement: true });
 const fresh = new ShellState();
 fresh.hydrateCache(validated.projects, validated.threads);
 assert.equal(fresh.hasSnapshot, true);
 assert.equal(fresh.liveSynced, false);
 assert.equal(fresh.threads[0].id, 't2');
 s.hydrateCache([], []);
 assert.equal(s.threads[0].id, 't2', 'live state must not be overwritten by cache');
 s.clear();
 assert.equal(s.hasSnapshot, false);
 assert.equal(s.threads.length, 0);
});

test('cachedShellEntry preserves project defaultModelSelection and options', async () => {
  const { cachedShellEntry } = await import(coreUrl);
  const entry = cachedShellEntry({
    environmentId: 'env-1',
    savedAt: Date.now(),
    scratchWorkspaceRoot: '/scratch',
    capabilities: {},
    projects: [{
      id: 'p1', label: 'Proj', workspaceRoot: '/w',
      defaultModelSelection: { instanceId: 'codex', model: 'gpt-5', options: [{ id: 'reasoningEffort', value: 'max' }] }
    }],
    threads: []
  });
  assert.deepEqual(entry.projects[0].defaultModelSelection, {
    instanceId: 'codex', model: 'gpt-5', options: [{ id: 'reasoningEffort', value: 'max' }]
  });
});

test('secret cards parse multi-value fields, drop malformed entries, forbid reference on fields, and format values answers', async () => {
  const { cards, secretAnswer, secretValuesAnswer, secretRequestErrorMessage } = await import(coreUrl);
  const { RpcFailure } = await import('../entry/src/main/ets/protocol/Wire.ts');
  const single = cards([], [{
    id: 's1', type: 'secret_request', secretStatus: 'pending', label: 'API Key', reason: 'Auth', placeholder: 'sk-...'
  }])[0];
  assert.deepEqual(single.secretFields, []);
  assert.equal(single.secretReference, true);
  assert.equal(single.secretPlaceholder, 'sk-...');
  assert.deepEqual(secretAnswer('t', 's1', 'sk-123', false), {
    threadId: 't', turnItemId: 's1', answer: { type: 'save', secret: 'sk-123' }
  });

  const multi = cards([], [{
    id: 's2', type: 'secret_request', secretStatus: 'pending', label: 'Login', reason: 'Sign in', delivery: 'file',
    fields: [
      { name: 'email', label: 'Email', placeholder: 'user@example.com', secret: false },
      { name: 'password', label: 'Password' },
      { name: 'email', label: 'Duplicate' },
      { name: '', label: 'Missing name' },
      { name: 'no_label', label: '   ' },
      { name: 'bad_secret', label: 'Bad Secret', secret: 'no' },
      null,
      'not-an-object'
    ]
  }])[0];
  assert.equal(multi.secretReference, false);
  assert.deepEqual(multi.secretFields, [
    { name: 'email', label: 'Email', placeholder: 'user@example.com', secret: false },
    { name: 'password', label: 'Password', placeholder: '', secret: true }
  ]);

  // Even a single-entry fields array disables reference answers
  const oneField = cards([], [{
    id: 's3', type: 'secret_request', secretStatus: 'pending', label: 'PIN', reason: 'Unlock',
    fields: [{ name: 'pin', label: 'PIN' }]
  }])[0];
  assert.equal(oneField.secretReference, false);
  assert.equal(oneField.secretFields.length, 1);

  assert.deepEqual(secretValuesAnswer('t', 's2', { email: ' a@b.dev ', password: ' pw ' }), {
    threadId: 't', turnItemId: 's2', answer: { type: 'save', values: { email: 'a@b.dev', password: 'pw' } }
  });
  // Prototype-named fields work safely without reading Object.prototype
  const protoAnswer = secretValuesAnswer('t', 's2', { constructor: ' value ' }, [{ name: 'constructor', label: 'Key', placeholder: '', secret: true }]);
  assert.equal(Object.getPrototypeOf(protoAnswer.answer.values), Object.prototype);
  assert.equal(protoAnswer.answer.values.constructor, 'value');
  assert.throws(() => secretValuesAnswer('t', 's2', {}, [{ name: 'constructor', label: 'Key', placeholder: '', secret: true }]));
  assert.throws(() => secretValuesAnswer('t', 's2', { email: 'a@b.dev' }, multi.secretFields));
  assert.throws(() => secretValuesAnswer('t', 's2', { email: '   ', password: 'pw' }, multi.secretFields));
  assert.throws(() => secretValuesAnswer('t', 's2', { email: 'a@b.dev', password: 'pw', extra: 'x' }, multi.secretFields));

  const mismatch = new RpcFailure('服务端拒绝请求或任务失败，请在远端服务端核对详情', true, 'SecretRequestError', 'fields_mismatch');
  assert.equal(secretRequestErrorMessage(mismatch), '此请求需要的字段与当前版本不一致，请更新应用后重试');
});

test('ShellState supports afterSequence incremental resume, ignores unknown stream kinds, and tolerates long/multiline display fields', async () => {
  const { ShellState } = await import(coreUrl);
  const s = new ShellState();
  const longTitle = 'Line 1\nLine 2\t' + 'a'.repeat(300);
  const longPath = '/Users/work/' + 'sub/'.repeat(70) + 'repo';
  s.apply({
    kind: 'snapshot',
    snapshot: {
      snapshotSequence: 12,
      projects: [{ id: 'p1', title: longTitle, workspaceRoot: longPath }],
      threads: [{ id: 't1', title: 'Task\nwith newline', projectId: 'p1', providerInstanceId: null, branch: 'feat/' + 'x'.repeat(280) }]
    }
  });
  assert.equal(s.cursor, 12);
  assert.equal(s.resumeCursor, 12);
  assert.equal(s.liveSynced, true);
  assert.ok(s.projects[0].label.length > 256);
  assert.equal(s.projects[0].label.includes('\n'), false);
  assert.equal(s.threads[0].label, 'Task with newline');

  // Unknown future kind does not throw
  s.apply({ kind: 'snapshot-required' });
  s.apply({ kind: 'future.shell.event', sequence: 13 });
  assert.equal(s.cursor, 12);

  // Reconnect reset keeps resumeCursor, replays missed delta + synchronized marker to restore liveSynced
  s.resetForReconnect();
  assert.equal(s.cursor, -1);
  assert.equal(s.resumeCursor, 12);
  assert.equal(s.liveSynced, false);
  s.apply({ kind: 'thread.updated', sequence: 12, location: 'active', thread: { id: 't1', title: 'Duplicate', projectId: 'p1' } });
  assert.equal(s.threads[0].label, 'Task with newline');
  s.apply({ kind: 'thread.updated', sequence: 13, location: 'active', thread: { id: 't1', title: 'Updated via replay', projectId: 'p1' } });
  s.apply({ kind: 'synchronized' });
  assert.equal(s.liveSynced, true);
  assert.equal(s.cursor, 13);
  assert.equal(s.threads[0].label, 'Updated via replay');
});
