import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { compile } from './load-core.mjs';
import { VoiceFrames, VoiceTranscript } from '../entry/src/main/ets/protocol/Voice.ts';
const source = (await readFile(new URL('../entry/src/main/ets/services/VoiceInput.ets', import.meta.url), 'utf8'))
  .replace(/^import .*;\n/gm, '').replace('export class VoiceInput', 'class VoiceInput');
function setup(create) {
  let listener, read, options, released=0, shutdown=0, writes=[];
  const engine={setListener(v){listener=v},startListening(){},writeAudio(_id,v){writes.push([...v])},finish(){},cancel(){},shutdown(){shutdown++}};
  const capturer={on(k,fn){if(k==='readData')read=fn},off(){},async start(){},async stop(){},async release(){released++}};
  const speechRecognizer={async createEngine(v){options=v;return create?await create(engine):engine}};
  const audio={async createAudioCapturer(){return capturer},AudioSamplingRate:{SAMPLE_RATE_16000:16000},AudioChannel:{CHANNEL_1:1},AudioSampleFormat:{SAMPLE_FORMAT_S16LE:1},AudioEncodingType:{ENCODING_TYPE_RAW:0},SourceType:{SOURCE_TYPE_MIC:0},InterruptType:{INTERRUPT_TYPE_BEGIN:1}};
  const Klass=new Function('speechRecognizer','audio','VoiceFrames','VoiceTranscript',compile(source)+'\nreturn VoiceInput;')(speechRecognizer,audio,VoiceFrames,VoiceTranscript);
  return {voice:new Klass(),get listener(){return listener},get options(){return options},get released(){return released},get shutdown(){return shutdown},writes,read(v){read(v.buffer)}};
}
const settle=()=>new Promise(r=>setImmediate(r));
test('PCM frames preserve arbitrary callback boundaries and pad only final bytes',()=>{
 const frames=new VoiceFrames();const bytes=Uint8Array.from({length:1500},(_,i)=>i%256);
 const a=frames.push(bytes.slice(0,170));assert.equal(a.length,0);
 const b=frames.push(bytes.slice(170));assert.equal(b.length,2);
 const tail=frames.finish();assert.equal(tail.length,640);
 assert.deepEqual([...b[0],...b[1],...tail.slice(0,220)],[...bytes]);
 assert.ok(tail.slice(220).every(n=>n===0));assert.equal(frames.finish(),undefined);
 frames.push(new Uint8Array(5));frames.clear();assert.equal(frames.finish(),undefined);
});
test('partial speech replaces partial sentence without duplicating finalized text',()=>{
 const t=new VoiceTranscript();assert.equal(t.accept('你',false),'你');assert.equal(t.accept('你好',true),'你好');
 assert.equal(t.accept('世',false),'你好世');assert.equal(t.accept('世界',true),'你好世界');
});
test('service forces offline recognition, cancellation discards stale callbacks and releases microphone',async()=>{
 const x=setup();const states=[];await x.voice.start(s=>states.push(s));assert.equal(x.options.online,1);
 const id=x.voice.session;x.listener.onStart(id,'');await settle();
 x.read(new Uint8Array(900));assert.equal(x.writes.length,1);assert.equal(x.writes[0].length,640);
 await x.voice.cancel();const count=states.length;x.listener.onResult(id,{result:'late',isFinal:true,isLast:true});
 await settle();assert.equal(states.length,count);assert.equal(x.released,1);assert.equal(x.shutdown,1);
});
test('cancel during engine initialization cannot acquire microphone or publish later result',async()=>{
 let resolve;const x=setup(engine=>new Promise(r=>{resolve=()=>r(engine)}));const states=[];
 const starting=x.voice.start(s=>states.push(s));await settle();await x.voice.cancel();resolve();await starting;
 assert.equal(x.released,0);assert.equal(x.shutdown,1);assert.equal(states.some(s=>s.phase==='recording'),false);
});
test('completed recognition is editable only after microphone release and duplicated complete is ignored',async()=>{
 const x=setup();const states=[];await x.voice.start(s=>states.push(s));const id=x.voice.session;
 x.listener.onStart(id,'');await settle();x.listener.onResult(id,{result:'草稿',isFinal:true,isLast:true});
 x.listener.onComplete(id,'');await settle();assert.equal(states.filter(s=>s.phase==='ready').length,1);
 assert.equal(states.at(-1).text,'草稿');assert.equal(x.released,1);
});
const panelSource=await readFile(new URL('../entry/src/main/ets/components/VoiceInputPanel.ets',import.meta.url),'utf8');
function panelHarness(permission) {
 const methods=panelSource.slice(panelSource.indexOf('  private foregroundChanged()'),panelSource.indexOf('  build()'));
 const abilityAccessCtrl={GrantStatus:{PERMISSION_GRANTED:0},createAtManager(){return {requestPermissionsFromUser:permission}}};
 const Panel=new Function('abilityAccessCtrl',compile('return class { '+methods+' }'))(abilityAccessCtrl);
 let starts=0,cancels=0;
 const panel=Object.assign(new Panel(),{generation:0,foreground:true,alive:true,phase:'idle',transcript:'',message:'',voice:{async start(){starts++},async cancel(){cancels++}},getUIContext(){return {getHostContext(){return {}}}}});
 return {panel,get starts(){return starts},get cancels(){return cancels}};
}
test('denied microphone permission never starts the recording service',async()=>{
 const h=panelHarness(async()=>({authResults:[-1]}));await h.panel.start();
 assert.equal(h.starts,0);assert.equal(h.panel.phase,'error');assert.match(h.panel.message,/权限/);
});
test('background during pending permission discards the request and cannot auto-resume recording',async()=>{
 let allow;const h=panelHarness(()=>new Promise(r=>{allow=()=>r({authResults:[0]})}));
 const pending=h.panel.start();h.panel.foreground=false;h.panel.foregroundChanged();allow();await pending;
 h.panel.foreground=true;h.panel.foregroundChanged();assert.equal(h.starts,0);assert.equal(h.cancels,1);assert.equal(h.panel.transcript,'');
});
