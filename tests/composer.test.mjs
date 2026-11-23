import test from 'node:test';
import assert from 'node:assert/strict';
import {composerUrl} from './load-core.mjs';
import {ThreadState} from '../entry/src/main/ets/protocol/Wire.ts';
const {
  launchTask, validateTaskSettings, optionControls, supportedModes, queuedRuns, queueCommand, modelOptionsSummary,
  shouldExpandComposer, resolveCompactEditorGeometry, layoutExpandedModelControl
}=await import(composerUrl);
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

test('shouldExpandComposer stays single-line until newline, wrap, or overflow and prevents oscillation',()=>{
 assert.equal(shouldExpandComposer({text:'',previewText:'',compactTextWidthVp:180,singleLineTextWidthVp:0,measuredLineCount:2,currentlyExpanded:true}),false);
 assert.equal(shouldExpandComposer({text:'hello',previewText:'',compactTextWidthVp:180,singleLineTextWidthVp:42,measuredLineCount:1,currentlyExpanded:false}),false);
 assert.equal(shouldExpandComposer({text:'\n',previewText:'',compactTextWidthVp:180,singleLineTextWidthVp:0,measuredLineCount:1,currentlyExpanded:false}),true);
 assert.equal(shouldExpandComposer({text:'line 1\nline 2',previewText:'',compactTextWidthVp:180,singleLineTextWidthVp:60,measuredLineCount:1,currentlyExpanded:false}),true);
 assert.equal(shouldExpandComposer({text:'wrapped',previewText:'',compactTextWidthVp:180,singleLineTextWidthVp:140,measuredLineCount:2,currentlyExpanded:false}),true);
 // Single line wider than compact slot expands immediately, and stays expanded even when widened layout reports 1 line
 assert.equal(shouldExpandComposer({text:'long single line text',previewText:'',compactTextWidthVp:180,singleLineTextWidthVp:188,measuredLineCount:1,currentlyExpanded:false}),true);
 assert.equal(shouldExpandComposer({text:'long single line text',previewText:'',compactTextWidthVp:180,singleLineTextWidthVp:188,measuredLineCount:1,currentlyExpanded:true}),true);
 // Hysteresis band keeps it stable at compactWidth - 3, then collapses once comfortably shorter
 assert.equal(shouldExpandComposer({text:'boundary',previewText:'',compactTextWidthVp:180,singleLineTextWidthVp:177,measuredLineCount:1,currentlyExpanded:true}),true);
 assert.equal(shouldExpandComposer({text:'shorter',previewText:'',compactTextWidthVp:180,singleLineTextWidthVp:170,measuredLineCount:1,currentlyExpanded:true}),false);
 // Active IME preview text crossing compact width expands smoothly
 assert.equal(shouldExpandComposer({text:'测试',previewText:'一长段拼音预览',compactTextWidthVp:120,singleLineTextWidthVp:135,measuredLineCount:1,currentlyExpanded:false}),true);
});

test('resolveCompactEditorGeometry prefers measured slot and handles badge and zero-width fallbacks',()=>{
 assert.deepEqual(
  resolveCompactEditorGeometry({rowWidthVp:360,measuredSlotLeftVp:48,measuredSlotWidthVp:216,hasSendModeBadge:false}),
  {leftVp:48,widthVp:216,textWidthVp:200}
 );
 const fallbackPlain=resolveCompactEditorGeometry({rowWidthVp:360,measuredSlotLeftVp:0,measuredSlotWidthVp:0,hasSendModeBadge:false});
 const fallbackBadge=resolveCompactEditorGeometry({rowWidthVp:360,measuredSlotLeftVp:0,measuredSlotWidthVp:0,hasSendModeBadge:true});
 assert.equal(fallbackPlain.leftVp,48);
 assert.ok(fallbackBadge.leftVp>fallbackPlain.leftVp);
 assert.ok(fallbackBadge.widthVp<fallbackPlain.widthVp);
 assert.equal(resolveCompactEditorGeometry({rowWidthVp:0,measuredSlotLeftVp:0,measuredSlotWidthVp:0,hasSendModeBadge:false}).widthVp,140);
});

test('layoutExpandedModelControl never overflows slot for long model names, long summaries, or narrow widths',()=>{
 // Short model + short summary both fit with no truncation
 const shortFit=layoutExpandedModelControl(240,52,34,true);
 assert.equal(shortFit.iconOnly,false);
 assert.equal(shortFit.showSummary,true);
 assert.ok(shortFit.maxLabelWidthVp>=54);
 assert.ok(shortFit.maxSummaryWidthVp>=36);
 assert.ok(shortFit.maxLabelWidthVp+shortFit.maxSummaryWidthVp+60<=240);

 // Very long model name (e.g. DeepSeek V4.1 Flash 1017 Preview) + short summary (High): summary preserved, label truncated inside slot
 const longModel=layoutExpandedModelControl(220,260,32,true);
 assert.equal(longModel.iconOnly,false);
 assert.equal(longModel.showSummary,true);
 assert.equal(longModel.maxSummaryWidthVp,34);
 assert.equal(longModel.maxLabelWidthVp,220-60-34);
 assert.ok(longModel.maxLabelWidthVp+longModel.maxSummaryWidthVp+60<=220);

 // Long model + long summary: both bounded cleanly
 const bothLong=layoutExpandedModelControl(220,260,150,true);
 assert.equal(bothLong.showSummary,true);
 assert.ok(bothLong.maxLabelWidthVp>=24 && bothLong.maxSummaryWidthVp>=24);
 assert.ok(bothLong.maxLabelWidthVp+bothLong.maxSummaryWidthVp+60<=220);

 // Short model + long summary: summary gets remaining width
 const shortModelLongSummary=layoutExpandedModelControl(220,48,140,true);
 assert.equal(shortModelLongSummary.maxLabelWidthVp,50);
 assert.equal(shortModelLongSummary.maxSummaryWidthVp,220-60-50);

 // Narrow slot drops summary before clipping model name; ultra-narrow drops to icon-only
 const narrow=layoutExpandedModelControl(110,160,32,true);
 assert.equal(narrow.iconOnly,false);
 assert.equal(narrow.showSummary,false);
 assert.equal(narrow.maxLabelWidthVp,110-55);
 assert.equal(layoutExpandedModelControl(48,160,32,true).iconOnly,true);

 // Exhaustive sweep invariant: never exceeds slot budget
 for(const slot of [40,56,90,132,180,220,300,420]){
  for(const lw of [0,30,90,260]){
   for(const sw of [0,25,80,180]){
    for(const hasSum of [false,true]){
     const out=layoutExpandedModelControl(slot,lw,sw,hasSum);
     assert.ok(out.maxButtonWidthVp<=slot,`slot=${slot} maxButtonWidthVp=${out.maxButtonWidthVp}`);
     if(!out.iconOnly){
      const chrome=out.showSummary?60:55;
      assert.ok(out.maxLabelWidthVp+out.maxSummaryWidthVp+chrome<=slot,
       `overflow slot=${slot} lw=${lw} sw=${sw} hasSum=${hasSum}: ${JSON.stringify(out)}`);
     }
    }
   }
  }
 }
});
