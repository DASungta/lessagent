import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {compile,data} from './load-core.mjs';
import {androidVideoPacket,androidSpsSize,androidKeyframe,ANDROID_VIDEO_MAX_PACKET,androidControlPoint,androidTouch,androidButton,androidKey,androidTextInputs,androidControlJson} from '../entry/src/main/ets/protocol/AndroidVideo.ts';
const baseline=await readFile(new URL('./fixtures/android-video/baseline-320x240.h264',import.meta.url));
const high=await readFile(new URL('./fixtures/android-video/high-640x360.h264',import.meta.url));
const raw=b=>Uint8Array.from(b).buffer;

test('real x264 baseline/high Annex-B fixtures expose SPS/PPS/IDR and cropped dimensions',()=>{
 for(const [bytes,expected] of [[baseline,{width:320,height:240}],[high,{width:640,height:360}]]) {
  const packet=androidVideoPacket(raw(bytes),1000);
  assert.equal(packet.key,true);assert.ok(packet.sps);assert.ok(packet.pps);
  assert.deepEqual(androidSpsSize(packet.sps),expected);
  const key=androidVideoPacket(androidKeyframe(packet.data,packet.sps,packet.pps),1000);
  assert.equal(key.key,true);assert.deepEqual(androidSpsSize(key.sps),expected);
 }
});
test('SEMU header preserves safe timestamp and rejects malformed framing/version/limits',()=>{
 const bytes=new Uint8Array(baseline.length+16);const view=new DataView(bytes.buffer);
 view.setUint32(0,0x53454d55);view.setUint8(4,1);view.setUint8(5,1);view.setUint32(8,1);view.setUint32(12,123);
 bytes.set(baseline,16);
 assert.equal(androidVideoPacket(bytes.buffer,0).timestamp,4294967419);
 view.setUint8(4,2);assert.throws(()=>androidVideoPacket(bytes.buffer,0),/版本/);
 view.setUint8(4,1);view.setUint32(8,0xffffffff);assert.throws(()=>androidVideoPacket(bytes.buffer,0),/时间戳/);
 assert.throws(()=>androidVideoPacket(new ArrayBuffer(ANDROID_VIDEO_MAX_PACKET+1),0));
 assert.throws(()=>androidVideoPacket(raw([1,2,3,4,5]),0),/Annex-B/);
 assert.throws(()=>androidSpsSize(new Uint8Array([0x67,0,0,0])));
});
const mock={sockets:[],epoch:0,starts:[],pushes:[],stops:[],nextPush:0,error:''};
class Socket { handlers={};sent=[];closed=false;on(t,f){this.handlers[t]=f;}async connect(){return true;}
 async send(v){this.sent.push(v);return true;}async close(){this.closed=true;}emit(t,v){this.handlers[t]?.(undefined,v);} }
globalThis.__androidVideoTest={
 webSocket:{createWebSocket(){const s=new Socket();mock.sockets.push(s);return s;}},
 nativeVideo:{start(surface,width,height){mock.starts.push({surface,width,height});return ++mock.epoch;},
  push(epoch,bytes,pts,key){mock.pushes.push({epoch,bytes,pts,key});const result=mock.nextPush;mock.nextPush=0;return result;},
  stop(epoch){mock.stops.push(epoch);},stats(){return{epoch:mock.epoch,ready:true,rendered:1,dropped:0,width:320,height:240,error:mock.error};}}
};
const wireUrl=new URL('../entry/src/main/ets/protocol/Wire.ts',import.meta.url).href;
const protocolUrl=new URL('../entry/src/main/ets/protocol/AndroidVideo.ts',import.meta.url).href;
const source=(await readFile(new URL('../entry/src/main/ets/services/AndroidDeviceStream.ets',import.meta.url),'utf8'))
 .replace("import { webSocket } from '@kit.NetworkKit';",'const webSocket=globalThis.__androidVideoTest.webSocket;')
 .replace("import nativeVideo, { DecoderStats } from 'libt3device.so';",'const nativeVideo=globalThis.__androidVideoTest.nativeVideo;')
 .replace("'../protocol/Wire'",JSON.stringify(wireUrl)).replace("'../protocol/AndroidVideo'",JSON.stringify(protocolUrl));
const {AndroidDeviceStream}=await import(data(compile(source)));
const delta=raw([0,0,0,1,0x41,0xaa]);
test('stream starts native decoder only after parameters and IDR, rebuilds on video-session',async()=>{
 const stream=new AndroidDeviceStream(()=>true);await stream.start('wss://example.invalid/device','123');
 const socket=mock.sockets.at(-1);const before=mock.starts.length;
 socket.emit('message',delta);assert.equal(mock.starts.length,before);
 socket.emit('message',raw(baseline));assert.equal(mock.starts.length,before+1);
 assert.deepEqual(mock.starts.at(-1),{surface:'123',width:320,height:240});assert.equal(mock.pushes.at(-1).key,true);
 socket.emit('message',JSON.stringify({type:'video-session'}));socket.emit('message',delta);
 assert.equal(mock.starts.length,before+1);
 socket.emit('message',raw(high));assert.equal(mock.starts.length,before+2);assert.equal(mock.starts.at(-1).height,360);
 stream.stop();
});
test('backpressure waits for keyframe and stale/changed environment sockets never feed native',async()=>{
 let alive=true;const stream=new AndroidDeviceStream(()=>alive);const errors=[];stream.onFailure=m=>errors.push(m);
 await stream.start('wss://example.invalid/device','123');const first=mock.sockets.at(-1);
 mock.nextPush=1;first.emit('message',raw(baseline));const sent=mock.pushes.length;
 first.emit('message',delta);assert.equal(mock.pushes.length,sent);
 first.emit('message',raw(baseline));assert.equal(mock.pushes.length,sent+1);
 await stream.start('wss://example.invalid/device2','456');const current=mock.sockets.at(-1);
 const starts=mock.starts.length;first.emit('message',raw(baseline));first.emit('close');assert.equal(mock.starts.length,starts);assert.equal(errors.length,0);
 alive=false;current.emit('message',raw(baseline));assert.equal(mock.starts.length,starts);assert.match(errors[0],/改变/);
 stream.stop();
});

test('native rejection preserves the original decoder stage error instead of generic expiry',async()=>{
 const stream=new AndroidDeviceStream(()=>true);const errors=[];stream.onFailure=m=>errors.push(m);
 await stream.start('wss://example.invalid/device','123');
 mock.error='H.264 SetSurface failed 8';mock.nextPush=2;
 mock.sockets.at(-1).emit('message',raw(baseline));
 assert.equal(errors[0],'H.264 SetSurface failed 8');
 mock.error='';stream.stop();
});
test('owner invalidation without new frames is detected by watchdog and releases socket/native/timer',async()=>{
 let alive=true;const stream=new AndroidDeviceStream(()=>alive);const failures=[];stream.onFailure=m=>failures.push(m);
 await stream.start('wss://example.invalid/device','123');const socket=mock.sockets.at(-1);
 socket.emit('message',raw(baseline));const epoch=mock.epoch;const stopped=mock.stops.length;
 alive=false;
 await new Promise(resolve=>setTimeout(resolve,320));
 assert.equal(socket.closed,true);assert.equal(stream.timer,-1);assert.equal(stream.socket,undefined);
 assert.equal(mock.stops.length,stopped+1);assert.equal(mock.stops.at(-1),epoch);
 assert.equal(failures.length,1);assert.match(failures[0],/改变/);
 stream.stop();
});

test('all media panels immediately release resources in background and never auto reconnect',async()=>{
 for(const name of ['AndroidDevicePanel','PreviewPanel','DevicePreviewPanel']) {
  const body=(await readFile(new URL('../entry/src/main/ets/components/'+name+'.ets',import.meta.url),'utf8')).split('  build() {')[0]+'}';
  const clean=body.replace(/^import[\s\S]*?;\n/gm,'').replace(/@(?:Prop|State)\s+/g,'')
   .replace(/@(?:StorageLink|Watch)\([^)]*\)\s*/g,'').replace('@Component\nexport struct '+name,'export class '+name);
  const module=await import(data(compile('const XComponentController=class {};\n'+clean)));
  const panel=new module[name]();let stops=0;let released=0;
  panel.stream={stop(){stops++;}};panel.busy=true;
  if(name!=='AndroidDevicePanel') panel.frame={async release(){released++;}};
  panel.foreground=false;panel.foregroundChanged();
  assert.equal(stops,1,name);assert.equal(panel.stream,undefined,name);assert.equal(panel.busy,false,name);
  if(name!=='AndroidDevicePanel')assert.equal(released,1,name);
  assert.match(panel.status,/手动连接/);
  panel.foreground=true;panel.foregroundChanged();assert.equal(stops,1,name);assert.equal(panel.stream,undefined,name);
 }
});

test('Android controls use normalized letterbox coordinates without double rotation',()=>{
 const portrait={width:1080,height:2400};
 assert.deepEqual(androidControlPoint(150,300,300,600,portrait),{x:0.5,y:0.5});
 assert.equal(androidControlPoint(0,300,300,600,portrait),undefined);
 assert.deepEqual(androidControlPoint(0,300,300,600,portrait,true),{x:0,y:0.5});
 assert.deepEqual(androidControlPoint(100,50,400,200,{width:2400,height:1080}),{x:0.25,y:2/9});
 assert.deepEqual(androidTouch('up',{x:0.5,y:0.5}),{type:'touch',action:'up',x:0.5,y:0.5});
 assert.deepEqual(androidButton('recents'),{type:'recents'});assert.deepEqual(androidKey(66),{type:'key',keycode:66});
 assert.throws(()=>androidControlJson({type:'rotate'}));assert.throws(()=>androidControlJson({type:'touch',action:'down',x:2,y:0}));
});
test('Android Unicode input chunks are bounded in UTF8 bytes and never silently truncate',()=>{
 const text='汉😀a'.repeat(300);const chunks=androidTextInputs(text);
 assert.equal(chunks.map(c=>c.text).join(''),text);
 assert.ok(chunks.every(c=>Buffer.byteLength(c.text,'utf8')<=300));
 assert.equal(androidTextInputs('a'.repeat(19200)).length,64);
 assert.throws(()=>androidTextInputs('a'.repeat(19201)));
 assert.throws(()=>androidTextInputs('bad\ud800'));
 assert.throws(()=>androidControlJson({type:'text',text:'a'.repeat(301)}));
});
const pause=()=>new Promise(resolve=>setTimeout(resolve,280));
const controls=socket=>socket.sent.filter(v=>JSON.parse(v).type!=='reset-video').map(v=>JSON.parse(v));
test('actual Android adapter gates control, serializes exact wire packets and releases touch on stop',async()=>{
 let operate=true;const stream=new AndroidDeviceStream(()=>true,()=>operate);const ready=[];stream.onInputReady=v=>ready.push(v);
 await stream.start('wss://example.invalid/control','123');const socket=mock.sockets.at(-1);
 await assert.rejects(stream.sendInput(androidButton('home')),/准入/);
 socket.emit('message',raw(baseline));await pause();assert.equal(ready.at(-1),true);
 await stream.sendInput(androidTouch('down',{x:0.2,y:0.3}));
 await stream.sendInput(androidTouch('move',{x:0.4,y:0.5}));
 stream.stop();await new Promise(resolve=>setImmediate(resolve));
 assert.deepEqual(controls(socket),[{type:'touch',action:'down',x:0.2,y:0.3},
  {type:'touch',action:'move',x:0.4,y:0.5},{type:'touch',action:'up',x:0.4,y:0.5}]);
 assert.equal(socket.closed,true);
 await stream.start('wss://example.invalid/reopen','123');const next=mock.sockets.at(-1);assert.deepEqual(controls(next),[]);
 next.emit('message',raw(baseline));await pause();operate=false;
 await assert.rejects(stream.sendInput(androidButton('home')),/权限/);assert.deepEqual(controls(next),[]);stream.stop();
});
test('queued old-epoch moves are cancelled and only a cleanup up stays on the original socket',async()=>{
 const stream=new AndroidDeviceStream(()=>true,()=>true);await stream.start('wss://example.invalid/control','123');
 const socket=mock.sockets.at(-1);socket.emit('message',raw(baseline));await pause();
 let release;const original=socket.send.bind(socket);
 socket.send=async value=>{await original(value);if(JSON.parse(value).action==='down')await new Promise(resolve=>{release=resolve;});return true;};
 const promises=[stream.sendInput(androidTouch('down',{x:0.1,y:0.1}))];
 const settled=Promise.allSettled(promises);
 await new Promise(resolve=>setImmediate(resolve));
 const moves=[stream.sendInput(androidTouch('move',{x:0.2,y:0.2})),stream.sendInput(androidTouch('move',{x:0.8,y:0.8}))];
 const moved=Promise.allSettled(moves);
 socket.emit('message',JSON.stringify({type:'video-session'}));release();await settled;await moved;
 assert.deepEqual(controls(socket),[{type:'touch',action:'down',x:0.1,y:0.1},{type:'touch',action:'up',x:0.1,y:0.1}]);
 socket.emit('message',raw(high));await pause();await stream.sendInput(androidButton('back'));
 assert.deepEqual(controls(socket).at(-1),{type:'back'});stream.stop();
});
test('Android panel maps overlay-local Down/Up against overlay area and ignores letterbox taps',async()=>{
 const body=(await readFile(new URL('../entry/src/main/ets/components/AndroidDevicePanel.ets',import.meta.url),'utf8')).split('  build() {')[0]+'}';
 const clean=body.replace(/^import[\s\S]*?;\n/gm,'').replace(/@(?:Prop|State)\s+/g,'')
  .replace(/@(?:StorageLink|Watch)\([^)]*\)\s*/g,'').replace('@Component\nexport struct AndroidDevicePanel','export class AndroidDevicePanel');
 globalThis.__androidTouchHelpers={androidControlPoint,androidTouch};
 const module=await import(data(compile('const XComponentController=class {}; const TouchType={Down:0,Up:1,Move:2,Cancel:3}; const {androidControlPoint,androidTouch}=globalThis.__androidTouchHelpers;\n'+clean)));
 const panel=new module.AndroidDevicePanel();const sent=[];
 panel.controlling=true;panel.inputReady=true;panel.foreground=true;panel.stream={async sendInput(v){sent.push(v);}};
 panel.touchWidth=400;panel.touchHeight=600;panel.availableWidth=10;panel.availableHeight=10;
 panel.videoWidth=1080;panel.videoHeight=2400;
 panel.touch({type:0,touches:[{x:200,y:60}],changedTouches:[{x:200,y:60}]});
 panel.touch({type:1,touches:[],changedTouches:[{x:200,y:60}]});
 assert.deepEqual(sent,[{type:'touch',action:'down',x:0.5,y:0.1},{type:'touch',action:'up',x:0.5,y:0.1}]);
 panel.touch({type:0,touches:[{x:10,y:60}],changedTouches:[{x:10,y:60}]});
 assert.equal(sent.length,2);assert.equal(panel.touching,false);
});
