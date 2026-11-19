import test from 'node:test';
import assert from 'node:assert/strict';
import {r4Url,threadItemsUrl} from './load-core.mjs';
const r4=await import(r4Url);
const threadItems=await import(threadItemsUrl);

test('drafts reload only with their environment and project scope',()=>{
 const draft=r4.composerDraft({version:1,draftId:'d1',localId:'a',environmentId:'env-a',projectId:'p1',text:'hello',
  modelSelection:{instanceId:'grok',model:'grok-4.7'},runtimeMode:'approval-required',interactionMode:'default',
  workspace:{mode:'worktree',branch:'main',worktreePath:'',startFromOrigin:true},
  attachments:[{type:'image',id:'img_1',name:'a.png',mimeType:'image/png',sizeBytes:12}],
  context:[{version:1,kind:'mention',contextId:'m1',label:'src/a.ts',path:'src/a.ts'}],updatedAt:1});
 assert.equal(draft.localId,'a');assert.equal(draft.workspace.mode,'worktree');assert.equal(draft.attachments[0].type,'image');
 assert.equal(draft.context[0].payload.path,'src/a.ts');
 assert.throws(()=>r4.composerDraft({...draft,workspace:{...draft.workspace,mode:'remote'}}));
});

test('launch workspace preserves root, existing worktree and new worktree semantics',()=>{
 const base={version:1,draftId:'d',localId:'a',environmentId:'e',projectId:'p',text:'',modelSelection:{instanceId:'x',model:'m'},
  runtimeMode:'approval-required',interactionMode:'default',attachments:[],context:[],updatedAt:1};
 assert.deepEqual(r4.launchWorkspace({...base,workspace:{mode:'local',branch:'dev',worktreePath:'',startFromOrigin:false}}),
  {type:'root',branch:'dev'});
 assert.deepEqual(r4.launchWorkspace({...base,workspace:{mode:'local',branch:'dev',worktreePath:'/tmp/wt',startFromOrigin:false}}),
  {type:'existing_worktree',worktreePath:'/tmp/wt',branch:'dev'});
 assert.deepEqual(r4.launchWorkspace({...base,workspace:{mode:'worktree',branch:'main',worktreePath:'',startFromOrigin:true}}),
  {type:'worktree',baseRef:'main',startFromOrigin:true});
 assert.throws(()=>r4.launchWorkspace({...base,workspace:{mode:'worktree',branch:'',worktreePath:'',startFromOrigin:true}}));
});

test('attachments enforce file, image and aggregate limits while preserving exact bytes',()=>{
 const image={type:'image',id:'i1',name:'photo.png',mimeType:'image/png',sizeBytes:10};
 assert.deepEqual(r4.attachmentRecord(image),image);
 assert.throws(()=>r4.attachmentRecord({...image,mimeType:'image/bmp'}));
 assert.throws(()=>r4.attachmentRecord({...image,sizeBytes:10*1024*1024+1}));
 assert.equal(r4.attachmentLimitError([]),'');
 const many=Array.from({length:101},(_,i)=>({type:'file',id:`f${i}`,name:'a.txt',mimeType:'text/plain',sizeBytes:1}));
 assert.match(r4.attachmentLimitError(many),/100/);
});

test('composer context rejects duplicate ids, invalid paths and oversized labels',()=>{
 const mention=r4.mentionContext('src/a.ts','m1');
 assert.equal(r4.contextPayload([mention]).records[0].path,'src/a.ts');
 assert.throws(()=>r4.mentionContext('/etc/passwd','m1'));
 assert.throws(()=>r4.contextPayload([mention,mention]));
 const skill=r4.skillContext('review','s1');
 assert.equal(skill.kind,'skill');
 const terminal=r4.terminalContext('id','命令输出',0,1,'line one\nline two','t1');
 assert.equal(terminal.kind,'terminal');assert.equal(terminal.payload.lineEnd,1);
 assert.throws(()=>r4.terminalContext('id','x',2,1,'','t2'));
});

test('branch, plan, subagent and guest parsing keeps typed identities',()=>{
 assert.deepEqual(r4.branches({refs:[{name:'main',current:true,isDefault:true,worktreePath:null}]}),
  [{name:'main',isRemote:false,remoteName:'',current:true,isDefault:true,worktreePath:''}]);
 assert.equal(r4.proposedPlans([{id:'p1',type:'proposed_plan',markdown:'# Plan',streaming:false,status:'completed'}])[0].markdown,'# Plan');
 const agent=r4.subagents([{id:'a1',prompt:'Do work',status:'running',childThreadId:'t2',remoteChild:{environmentId:'e2',threadId:'t3'}}])[0];
 assert.equal(agent.childThreadId,'t2');assert.equal(agent.remoteEnvironmentId,'e2');assert.equal(agent.canStop,true);
 const share=r4.guestShare({id:'g',host:'h',createdAt:'2026-01-01T00:00:00Z',expiresAt:'2026-01-02T00:00:00Z',
  guestName:null,messages:[{id:'m',text:'hi',status:'pending',attachments:[]}]});
 assert.equal(share.guestName,'');assert.equal(share.messages[0].status,'pending');
});

test('fork and queue commands use the server execution ids',()=>{
 assert.deepEqual(r4.forkThreadCommand('c','source','target','run','Side',true),{type:'thread.fork',commandId:'c',
  createdBy:'user',creationSource:'mobile',sourceThreadId:'source',targetThreadId:'target',
  sourcePoint:{type:'run',runId:'run'},title:'Side',sideChat:true});
 assert.equal(r4.forkThreadCommand('c','s','t','','',false).sourcePoint.type,'latest_stable');
 assert.equal(r4.promoteCommand('c','t','queued','active').type,'queued-message.promote-to-steer');
 assert.throws(()=>r4.promoteCommand('c','t','','active'));
});

test('activity rows expose reasoning and command output identity',()=>{
 const lines=threadItems.activityLines([{id:'r',type:'reasoning',status:'completed',text:'checking files'},
  {id:'c',type:'command_execution',status:'completed',exitCode:0,input:'ls',output:'a.txt'}]);
 assert.equal(lines[0].label,'思考过程 · completed');assert.equal(lines[0].text,'checking files');
 assert.match(lines[1].label,/exit 0/);
});

test('resume chooses the latest executed run rather than array order',()=>{
 const runs=[
  {id:'a',status:'interrupted',ordinal:2,completedAt:'2026-01-01T00:00:02Z',startedAt:'2026-01-01T00:00:00Z'},
  {id:'b',status:'starting',ordinal:3,completedAt:null,startedAt:'2026-01-01T00:00:03Z'},
  {id:'c',status:'interrupted',ordinal:5,completedAt:'2026-01-01T00:00:05Z',startedAt:'2026-01-01T00:00:04Z'},
  {id:'d',status:'queued',ordinal:9,completedAt:null,startedAt:null}
 ];
 assert.equal(r4.latestExecutedRun(runs).id,'b');
 assert.equal(r4.latestExecutedRun(runs.filter(run=>run.id!=='b')).id,'c');
 assert.equal(r4.latestExecutedRun([{id:'x',status:'cancelled',ordinal:1,completedAt:'2026-01-01T00:00:00Z',startedAt:null}]),undefined);
});
