import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {compile,data} from './load-core.mjs';
import {DeviceMjpegParser,deviceScreen,devicePoint,deviceRotation,deviceTouch,deviceButton,deviceKey,deviceNextOrientation,DEVICE_FRAME_MAX,safeDeviceHubBase,deviceChoices} from '../entry/src/main/ets/protocol/DevicePreview.ts';
const jpeg=Buffer.from([255,216,1,2,255,217]);
const part=(length=true)=>Buffer.concat([Buffer.from('--frame\r\nContent-Type: image/jpeg\r\n'+(length?'Content-Length: 6\r\n':'')+'\r\n'),jpeg,Buffer.from('\r\n')]);
const array=buffer=>Uint8Array.from(typeof buffer==='string'?Buffer.from(buffer):buffer).buffer;

test('MJPEG parser handles arbitrary byte splits and multiple frames with or without content length',()=>{
 for(const sized of [true,false]) {
  const parser=new DeviceMjpegParser('multipart/x-mixed-replace; boundary="frame"');
  const stream=Buffer.concat([part(sized),part(sized),Buffer.from('--frame--\r\n')]);
  const frames=[];
  for(const byte of stream)frames.push(...parser.push(array([byte])));
  assert.equal(frames.length,2);for(const frame of frames)assert.deepEqual(Buffer.from(frame),jpeg);
  assert.deepEqual(parser.push(array('ignored')),[]);
 }
});
test('MJPEG parser rejects nonvideo, oversized frames, corrupt JPEG and huge headers',()=>{
 assert.throws(()=>new DeviceMjpegParser('application/json'));
 const p=new DeviceMjpegParser('multipart/x-mixed-replace;boundary=frame');
 assert.throws(()=>p.push(array('--frame\r\nContent-Type: image/jpeg\r\nContent-Length: '+(DEVICE_FRAME_MAX+1)+'\r\n\r\n')));
 const bad=new DeviceMjpegParser('multipart/x-mixed-replace;boundary=frame');
 assert.throws(()=>bad.push(array('--frame\r\nContent-Type: image/jpeg\r\nContent-Length: 4\r\n\r\nABCD')));
 const header=new DeviceMjpegParser('multipart/x-mixed-replace;boundary=frame');
 assert.throws(()=>header.push(array('--frame\r\n'+'X'.repeat(9000))));
});
test('iOS coordinates normalize displayed frame and remap into rotated raw framebuffer',()=>{
 const screen=deviceScreen({width:400,height:800,orientation:'portrait'});
 assert.equal(deviceRotation(screen),0); assert.deepEqual(devicePoint(100,100,200,400,screen),{x:0.5,y:0.25});
 const left={...screen,orientation:'landscape_left'};
 assert.equal(deviceRotation(left),90);assert.deepEqual(devicePoint(100,100,400,200,left),{x:0.5,y:0.75});
 assert.equal(devicePoint(10,0,400,400,left),undefined);
 assert.deepEqual(deviceNextOrientation(screen),{orientation:'landscape_left'});
 assert.throws(()=>deviceTouch('cancel',{x:0,y:0}));assert.throws(()=>deviceTouch('begin',{x:2,y:0}));
 assert.deepEqual(deviceButton('home'),{button:'home'});assert.throws(()=>deviceButton('power'));
 assert.deepEqual(deviceKey(40,true),{type:'down',usage:40});assert.throws(()=>deviceKey(999,true));
});
const mocks={sockets:[],requests:[],framesReleased:0,sourcesReleased:0,rotations:[]};
class Socket{
 handlers={};sent=[];closed=false;
 on(t,f){this.handlers[t]=f;}async connect(){return true;}async send(v){this.sent.push(v);return true;}async close(){this.closed=true;}
 emit(t,v){this.handlers[t]?.(undefined,v);}
}
class Request{
 handlers={};destroyed=false;
 on(t,f){this.handlers[t]=f;}async requestInStream(){return 200;}destroy(){this.destroyed=true;}emit(t,v){this.handlers[t]?.(v);}
}
globalThis.__devicePreviewTest={
 webSocket:{createWebSocket(){const v=new Socket();mocks.sockets.push(v);return v;}},
 http:{RequestMethod:{GET:'GET'},createHttp(){const v=new Request();mocks.requests.push(v);return v;}},
 util:{TextEncoder:class{encodeInto(s){return new TextEncoder().encode(s);}},TextDecoder:class{decodeToString(b){return new TextDecoder().decode(b);}}},
 image:{createImageSource(){return{async getImageInfo(){return{size:{width:400,height:800}};},async createPixelMap(){return{async rotate(a){mocks.rotations.push(a);},async release(){mocks.framesReleased++;}};},async release(){mocks.sourcesReleased++;}};}}
};
const wireUrl=new URL('../entry/src/main/ets/protocol/Wire.ts',import.meta.url).href;
const protocolUrl=new URL('../entry/src/main/ets/protocol/DevicePreview.ts',import.meta.url).href;
const source=(await readFile(new URL('../entry/src/main/ets/services/DevicePreviewStream.ets',import.meta.url),'utf8'))
 .replace("import { http, webSocket } from '@kit.NetworkKit';",'const {http,webSocket}=globalThis.__devicePreviewTest;')
 .replace("import { image } from '@kit.ImageKit';",'const image=globalThis.__devicePreviewTest.image;')
 .replace("import { util } from '@kit.ArkTS';",'const util=globalThis.__devicePreviewTest.util;')
 .replace("'../protocol/Wire'",JSON.stringify(wireUrl)).replace("'../protocol/DevicePreview'",JSON.stringify(protocolUrl));
const{DevicePreviewStream}=await import(data(compile(source)));
const tick=()=>new Promise(resolve=>setImmediate(resolve));
const access={mjpegUrl:'https://example.invalid/stream.mjpeg',inputUrl:'wss://example.invalid/input'};
const screenMessage=orientation=>array(Buffer.concat([Buffer.from([0x82]),Buffer.from(JSON.stringify({width:400,height:800,orientation}))]));
test('actual device adapter streams multiple HTTP JPEG frames and admits binary HID only after both signals',async()=>{
 let alive=true;const stream=new DevicePreviewStream(()=>alive);const frames=[];const ready=[];
 stream.onFrame=f=>frames.push(f);stream.onInput=v=>ready.push(v);
 await stream.start(access);const request=mocks.requests.at(-1);const socket=mocks.sockets.at(-1);
 await assert.rejects(stream.send(4,deviceButton('home')),/准入/);
 socket.emit('message',array([0x83]));await assert.rejects(stream.send(4,deviceButton('home')),/准入/);
 socket.emit('message',screenMessage('landscape_left'));assert.equal(ready.at(-1),true);
 await stream.send(4,deviceButton('home'));const packet=new Uint8Array(socket.sent[0]);assert.equal(packet[0],4);
 assert.deepEqual(JSON.parse(new TextDecoder().decode(packet.slice(1))),{button:'home'});
 request.emit('headersReceive',{'content-type':'multipart/x-mixed-replace;boundary=frame'});
 request.emit('dataReceive',array(part()));await tick();request.emit('dataReceive',array(part()));await tick();
 assert.equal(frames.length,2);assert.deepEqual(mocks.rotations.slice(-2),[90,90]);
 alive=false;await assert.rejects(stream.send(4,deviceButton('home')),/准入/);assert.equal(socket.closed,true);assert.equal(request.destroyed,true);
 for(const f of frames)await f.release();stream.stop();
});
test('reconnect ignores old HTTP/socket events and rejects non MJPEG hosts without leaking credentials',async()=>{
 const stream=new DevicePreviewStream(()=>true);const failures=[];stream.onFailure=m=>failures.push(m);
 await stream.start(access);const old=mocks.requests.at(-1);const socket=mocks.sockets.at(-1);
 await stream.start(access);old.emit('dataEnd');socket.emit('close');assert.equal(failures.length,0);
 mocks.requests.at(-1).emit('headersReceive',{'Content-Type':'application/json'});
 assert.equal(failures.length,1);assert.match(failures[0],/H.264\/WebRTC/);stream.stop();
});

test('device hub path is same-origin API path and rejects ticket exfiltration or normalization tricks',()=>{
 assert.equal(safeDeviceHubBase('/api/device-hub'),'/api/device-hub');
 assert.equal(safeDeviceHubBase('/api/device-hub/'),'/api/device-hub');
 for(const path of ['https://evil.test/hub','//evil.test/hub','/api//evil','/api/../evil','/api/%2e%2e/evil',
   '/api/device-hub?redirect=https://evil.test','/api/device-hub#x','/api/device-hub\\evil','/api/device-hub\n']) {
  assert.throws(()=>safeDeviceHubBase(path),path);
 }
});
test('device picker only opens ordinary iOS/Android simulators and isolates same IDs by host',()=>{
 const hosts=[{id:'local',label:'This Mac',kind:'local'},{id:'ssh',label:'Remote Mac',kind:'ssh'},
  {id:'cloud',label:'Cloud',kind:'eas'}];
 const base={id:'same',name:'iPhone',platform:'ios',physical:false,booted:true,version:'18'};
 const choices=deviceChoices([{...base,hostId:'local'},{...base,hostId:'ssh'},
  {...base,id:'android',hostId:'local',platform:'android'},
  {...base,id:'physical',hostId:'local',physical:true},
  {...base,hostId:'cloud'},{...base,hostId:'unknown'}],hosts);
 assert.deepEqual(choices.map(c=>c.supported),[true,true,true,false,false,false]);
 assert.match(choices[2].reason,/H.264/); assert.equal(choices[1].hostLabel,'Remote Mac');
 assert.throws(()=>deviceChoices([{...base,hostId:'local'},{...base,hostId:'local'}],hosts));
 assert.equal(deviceChoices([{...base,hostId:'local',physical:undefined}],hosts)[0].supported,false);
});
