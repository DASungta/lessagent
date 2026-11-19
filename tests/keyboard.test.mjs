import test from 'node:test';
import assert from 'node:assert/strict';
import { KeyboardCommands, KEY_F, KEY_N, KEY_ENTER, KEY_ESCAPE, KEY_META_LEFT, KEY_META_RIGHT } from '../entry/src/main/ets/protocol/Keyboard.ts';
const context = (extra={}) => ({foreground:true,composing:false,textFocused:false,composerFocused:false,blocked:false,busy:false,unknownSubmission:false,canSend:true,canSearch:true,canNewTask:true,canBack:true,...extra});
const event = (keyCode,extra={}) => ({keyCode,down:true,keyboard:true,deviceId:1,ctrl:false,alt:false,shift:false,...extra});
const handle=(key,mods={},ctx={})=>new KeyboardCommands().handle(event(key,mods),context(ctx));
test('Ctrl search/new task and unmodified Escape only dispatch permitted navigation',()=>{
 assert.equal(handle(KEY_F,{ctrl:true}),'search');assert.equal(handle(KEY_N,{ctrl:true}),'new-task');assert.equal(handle(KEY_ESCAPE),'back');
 for(const key of [KEY_F,KEY_N])assert.equal(handle(key),'');
 assert.equal(handle(KEY_F,{ctrl:true},{canSearch:false}),'');assert.equal(handle(KEY_N,{ctrl:true},{canNewTask:false}),'');assert.equal(handle(KEY_ESCAPE,{}, {canBack:false}),'');
});
test('send requires composer focus, explicit modifier and readiness; ordinary Enter never sends',()=>{
 for(const extra of [{},{shift:true},{alt:true},{ctrl:true,shift:true}])assert.equal(handle(KEY_ENTER,extra,{composerFocused:true,textFocused:true}),'');
 assert.equal(handle(KEY_ENTER,{ctrl:true}),'');assert.equal(handle(KEY_ENTER,{ctrl:true},{composerFocused:true,textFocused:true}),'send');
 assert.equal(handle(KEY_ENTER,{ctrl:true},{composerFocused:true,canSend:false}),'');
});
test('composition, background, blocked surfaces, busy and unknown submission reject every command',()=>{
 for(const guard of [{composing:true},{foreground:false},{blocked:true},{busy:true},{unknownSubmission:true}])
  for(const key of [KEY_F,KEY_N,KEY_ENTER,KEY_ESCAPE])assert.equal(handle(key,{ctrl:key!==KEY_ESCAPE},{composerFocused:true,...guard}),'');
 for(const key of [KEY_F,KEY_N,KEY_ESCAPE])assert.equal(handle(key,{ctrl:key!==KEY_ESCAPE},{textFocused:true}),'');
});
test('extra modifiers and non-keyboard sources never dispatch',()=>{
 for(const key of [KEY_F,KEY_N,KEY_ENTER]){
  assert.equal(handle(key,{ctrl:true,alt:true},{composerFocused:true}),'');
  assert.equal(handle(key,{ctrl:true,shift:true},{composerFocused:true}),'');
  assert.equal(handle(key,{ctrl:true,keyboard:false},{composerFocused:true}),'');
 }
});
test('held keys do not repeat commands until released',()=>{
 const k=new KeyboardCommands();const e=event(KEY_N,{ctrl:true});assert.equal(k.handle(e,context()),'new-task');
 assert.equal(k.handle(e,context()),'');assert.equal(k.handle({...e,down:false},context()),'');assert.equal(k.handle(e,context()),'new-task');
});
test('left/right Cmd tracked from SDK Meta key events, cleared on release/reset/device change',()=>{
 for(const meta of [KEY_META_LEFT,KEY_META_RIGHT]){
  const k=new KeyboardCommands();assert.equal(k.handle(event(meta),context()),'');
  assert.equal(k.handle(event(KEY_F),context()),'search');k.handle(event(KEY_F,{down:false}),context());
  assert.equal(k.handle(event(KEY_N,{ctrl:true}),context()),'');k.handle(event(KEY_N,{down:false}),context());
  k.handle(event(meta,{down:false}),context());assert.equal(k.handle(event(KEY_N),context()),'');
  k.reset();k.handle(event(meta),context());assert.equal(k.handle(event(KEY_F,{deviceId:2}),context()),'');
  k.reset();assert.equal(k.handle(event(KEY_ENTER),context({composerFocused:true})),'');
 }
});
