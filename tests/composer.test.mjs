import test from 'node:test';
import assert from 'node:assert/strict';
import {composerUrl} from './load-core.mjs';
import {ThreadState} from '../entry/src/main/ets/protocol/Wire.ts';
const {launchTask,validateTaskSettings,optionControls,supportedModes,queuedRuns,queueCommand,modelOptionsSummary}=await import(composerUrl);
const config={providers:[{instanceId:'codex',driver:'codex',installed:true,enabled:true,models:[{slug:'m',capabilities:{optionDescriptors:[{id:'reasoningEffort',label:'Reasoning',type:'select',options:[{id:'high',label:'High'}]},{id:'fast',label:'Fast',type:'boolean'}]}}],supportedRuntimeModes:['approval-required','full-access']}],settings:{}};
const settings={modelSelection:{instanceId:'codex',model:'m',options:[{id:'reasoningEffort',value:'high'},{id:'fast',value:false}]},runtimeMode:'approval-required',interactionMode:'default'};
test('first send builds one launch with initial message and no client thread.create',()=>{
 const input=launchTask('c','t','m','project','first task',validateTaskSettings(config,'project',settings));
 assert.equal(input.threadId,'t');assert.equal(input.initialMessage.messageId,'m');assert.equal(input.initialMessage.text,'first task');assert.equal(input.workspaceStrategy.type,'root');assert.deepEqual(input.modelSelection,settings.modelSelection);assert.equal(input.creationSource,'mobile');assert.equal(input.bootstrap,undefined);
 assert.throws(()=>launchTask('c','t','m','p',' ',settings));
});
test('model controls, options and organization/project restrictions are validated before sending',()=>{
 assert.equal(optionControls(config,settings.modelSelection).length,2);
 assert.deepEqual(supportedModes(config,settings.modelSelection),['approval-required','full-access']);
 for(const options of [[{id:'reasoningEffort',value:'invalid'}],[{id:'fast',value:'false'}],[{id:'fast',value:true},{id:'fast',value:false}],[{id:'unknown',value:true}]])assert.throws(()=>validateTaskSettings(config,'p',{...settings,modelSelection:{...settings.modelSelection,options}}));
 for(const c of [
 {...config,managedPolicy:{limits:{providers:{allowedDrivers:['other']}}}},
 {...config,settings:{projectSettingsOverrides:{p:{providerInstances:{codex:{enabled:false}}}}}},
 {...config,providers:[{...config.providers[0],installed:false}]},
 ])assert.throws(()=>validateTaskSettings(c,'p',settings));
 const managed={...config,managedPolicy:{limits:{maxRuntimeMode:'approval-required'}}};
 assert.deepEqual(supportedModes(managed,settings.modelSelection),['approval-required']);
 assert.throws(()=>validateTaskSettings(managed,'p',{...settings,runtimeMode:'full-access'}));
});
test('queue state is reconstructed from snapshots and run events without replaying sends',()=>{
 const state=new ThreadState('t');
 state.apply({kind:'snapshot',snapshotSequence:2,projection:{thread:{id:'t'},messages:[{id:'m',threadId:'t',role:'user',text:'queued',streaming:false}],runs:[{id:'run',status:'queued',userMessageId:'m',queuePosition:1,queueHeld:true}]}});
 assert.deepEqual(queuedRuns(state.runs,state.messageRecords),[{id:'run',messageId:'m',text:'queued',position:1,held:true,attachmentNames:[]}]);
 state.apply({kind:'event',sequence:3,event:{threadId:'t',type:'run.updated',payload:{id:'run',status:'running',userMessageId:'m'}}});
 assert.equal(queuedRuns(state.runs,state.messageRecords).length,0);
 state.apply({kind:'event',sequence:2,event:{threadId:'t',type:'run.updated',payload:{id:'run',status:'queued',userMessageId:'m'}}});
 assert.equal(queuedRuns(state.runs,state.messageRecords).length,0);
});
test('a newly created queued run appears before its first status update',()=>{
 const state=new ThreadState('t');
 state.apply({kind:'snapshot',snapshotSequence:1,projection:{thread:{id:'t'},messages:[{id:'m',threadId:'t',role:'user',text:'queued',streaming:false}],runs:[],turnItems:[]}});
 state.apply({kind:'event',sequence:2,event:{threadId:'t',type:'run.created',payload:{id:'run2',status:'queued',userMessageId:'m',queuePosition:0}}});
 assert.equal(queuedRuns(state.runs,state.messageRecords).length,1);
 assert.equal(queuedRuns(state.runs,state.messageRecords)[0].id,'run2');
});
test('queued edits preserve existing attachments and precise order/resume semantics',()=>{
 assert.deepEqual(queueCommand('c','t','edit','r',null,'updated'),{type:'queued-run.edit',commandId:'c',threadId:'t',runId:'r',text:'updated'});
 assert.equal(queueCommand('c','t','reorder','r',null).beforeRunId,null);
 assert.equal(queueCommand('c','t','resume','').type,'queue.resume');
 assert.throws(()=>queueCommand('c','t','reorder','r','r'));
 assert.throws(()=>queueCommand('c','t','edit','r',null,' '));
});

test('modelOptionsSummary formats reasoning effort, defaults, speed traits, and fallbacks cleanly',()=>{
 const cfg={providers:[
  {instanceId:'antigravity',driver:'antigravity',models:[
   {slug:'gemini-4-neon',capabilities:{optionDescriptors:[
    {id:'thought_level',label:'Reasoning',type:'select',role:'reasoning',options:[
     {id:'high',label:'High',isDefault:true},{id:'xhigh',label:'Extra'}
    ]}
   ]}}
  ]},
  {instanceId:'codex',driver:'codex',models:[
   {slug:'gpt-6',capabilities:{optionDescriptors:[
    {id:'reasoningEffort',label:'Reasoning',type:'select',role:'reasoning',options:[
     {id:'medium',label:'Medium',isDefault:true},{id:'high',label:'High'}
    ]},
    {id:'fastMode',label:'Fast',type:'boolean'}
   ]}}
  ]}
 ]};
 assert.equal(modelOptionsSummary(cfg,{instanceId:'antigravity',model:'gemini-4-neon',options:[{id:'thought_level',value:'xhigh'}]}),'Extra');
 assert.equal(modelOptionsSummary(cfg,{instanceId:'antigravity',model:'gemini-4-neon'}),'High');
 assert.equal(modelOptionsSummary(cfg,{instanceId:'antigravity',model:'gemini-4-neon'},{instanceId:'antigravity',model:'gemini-4-neon',options:[{id:'thought_level',value:'xhigh'}]}),'Extra');
 assert.equal(modelOptionsSummary(cfg,{instanceId:'codex',model:'gpt-6',options:[{id:'reasoningEffort',value:'high'},{id:'fastMode',value:true}]}),'High Fast');
 assert.equal(modelOptionsSummary({},{instanceId:'antigravity',model:'gemini-4-neon',options:[{id:'thought_level',value:'xhigh'}]}),'Extra');
 assert.equal(modelOptionsSummary(cfg,{instanceId:'',model:''}),'');
});
