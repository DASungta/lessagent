import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { compile, data } from './load-core.mjs';
import { previewViewport, previewPoint, previewControl, previewCanSend, previewJpeg,
  previewKey, previewMouse, previewNavigation, previewTabs, previewHistory, PREVIEW_MAX_FRAME_BYTES,
  PREVIEW_RESIZE_CHOICES, previewResizeInput, verifyPreviewResize, previewFrameMatchesViewport, previewDecodeSize } from '../entry/src/main/ets/protocol/Preview.ts';

test('preview coordinates account for letterboxing and reject outside taps', () => {
 const viewport = previewViewport(800,600);
 assert.deepEqual(previewPoint(200,200,400,400,viewport),{x:400,y:300});
 assert.equal(previewPoint(200,20,400,400,viewport),undefined);
 assert.equal(previewPoint(400,200,400,400,viewport),undefined);
 assert.equal(previewPoint(NaN,0,400,400,viewport),undefined);
 assert.throws(()=>previewViewport(0,600)); assert.throws(()=>previewViewport(3840,3840));
});
test('preview requires explicit server control before input; takeover is separate', () => {
 assert.equal(previewCanSend(undefined,'mouse'),false);
 const control = previewControl({canOperate:true,controller:'agent',generation:4,dialog:null});
 assert.equal(previewCanSend(control,'mouse'),false); assert.equal(previewCanSend(control,'takeControl'),true);
 assert.equal(previewCanSend({...control,controller:'another-viewer'},'takeControl'),false);
 assert.equal(previewCanSend({...control,controller:'you'},'mouse'),true);
 assert.equal(previewCanSend({...control,canOperate:false},'takeControl'),false);
 assert.throws(()=>previewControl({canOperate:true,controller:'bad',generation:4}));
});
test('preview input follows upstream key/mouse and JPEG limits', () => {
 assert.deepEqual(previewMouse({x:10,y:20},true),{type:'mouse',action:'down',x:10,y:20,button:'left',buttons:1,clickCount:1,modifiers:0});
 assert.equal(previewKey('Enter',true).text,'\r'); assert.equal(previewKey('Enter',false).text,undefined);
 assert.throws(()=>previewKey('unknown',true));
 assert.throws(()=>previewNavigation('javascript:alert(1)'));
 assert.equal(previewNavigation('http://localhost:3000').url,'http://localhost:3000');
 previewJpeg(Uint8Array.from([255,216,255,217]).buffer);
 assert.throws(()=>previewJpeg(new ArrayBuffer(PREVIEW_MAX_FRAME_BYTES+1)));
 assert.throws(()=>previewJpeg(Uint8Array.from([255,216,0,0]).buffer));
});

const state = { sockets:[], released:0, sourcesReleased:0, decodeGate:null, imageSize:{width:720,height:1280}, throwSource:false, mimeType:'image/jpeg', outputSize:null, outputGate:null, decodeOptions:[] };
class FakeSocket {
 handlers = {}; sent=[]; closed=false;
 on(type,callback) { this.handlers[type]=callback; }
 async connect() { return true; }
 async send(value) { if (this.closed) throw new Error('closed'); this.sent.push(value); return true; }
 async close() { this.closed=true; }
 emit(type,value) { this.handlers[type]?.(undefined,value); }
}
globalThis.__previewTest = {
 webSocket: { createWebSocket() { const socket = new FakeSocket(); state.sockets.push(socket); return socket; } },
 image: { createImageSource() {
  if(state.throwSource) throw new Error('native decoder failed');
  return { async getImageInfo() { return {size:state.imageSize,mimeType:state.mimeType}; },
    async createPixelMap(options) {
      state.decodeOptions.push(options);
      const outputSize = state.outputSize ?? options.desiredSize;
      const gate=state.decodeGate; if(gate) await gate;
      return { async getImageInfo() {
        if (state.outputGate) await state.outputGate;
        return { size: outputSize };
      }, async release() { state.released++; } };
    },
    async release() { state.sourcesReleased++; } };
 } }
};
const wireUrl = new URL('../entry/src/main/ets/protocol/Wire.ts', import.meta.url).href;
const hostsUrl = new URL('../entry/src/main/ets/protocol/Hosts.ts', import.meta.url).href;
const protocolUrl = new URL('../entry/src/main/ets/protocol/Preview.ts', import.meta.url).href;
const source = (await readFile(new URL('../entry/src/main/ets/services/PreviewStream.ets',import.meta.url),'utf8'))
 .replace("import { webSocket } from '@kit.NetworkKit';",'const webSocket = globalThis.__previewTest.webSocket;')
 .replace("import { image } from '@kit.ImageKit';",'const image = globalThis.__previewTest.image;')
 .replace("'../protocol/Wire'",JSON.stringify(wireUrl))
 .replace("'../protocol/Hosts'",JSON.stringify(hostsUrl))
 .replace("'../protocol/Preview'",JSON.stringify(protocolUrl));
const { PreviewStream } = await import(data(compile(source)));
const tick = () => new Promise(resolve=>setImmediate(resolve));
const jpeg = () => Uint8Array.from([255,216,255,217]).buffer;
const controller = (socket, who='you') => socket.emit('message',JSON.stringify({type:'control',canOperate:true,controller:who,generation:1,dialog:null}));

test('native preview adapter decodes continuous JPEGs, acknowledges and refuses revoked control',async()=>{
 let alive=true; const frames=[]; const failures=[];
 const stream = new PreviewStream(()=>alive); stream.onFrame=f=>frames.push(f); stream.onFailure=m=>failures.push(m);
 await stream.start('wss://example.invalid/api/preview-stream/ws?wsTicket=fixture');
 const socket = state.sockets.at(-1);
 await assert.rejects(stream.send({type:'text',text:'test'}),/控制权/);
 controller(socket); await stream.send({type:'text',text:'test'});
 await stream.send(previewHistory(-1)); await stream.send(previewHistory(1));
 assert.deepEqual(socket.sent.map(value=>JSON.parse(value)).filter(value=>value.type==='history').map(value=>value.delta),[-1,1]);
 socket.emit('message',jpeg()); await tick(); socket.emit('message',jpeg()); await tick();
 assert.equal(frames.length,2); assert.equal(socket.sent.filter(s=>s==='{"type":"ack"}').length,2);
 controller(socket,'agent'); await assert.rejects(stream.send({type:'reload'}),/控制权/);
 alive=false; await assert.rejects(stream.send({type:'takeControl'}),/失效/); assert.equal(socket.closed,true);
 assert.equal(failures.length,0); for(const frame of frames) await frame.release(); stream.stop();
});
test('preview keeps only latest pending frame and discards late decoded frames after stop',async()=>{
 let release; state.decodeGate=new Promise(resolve=>{release=resolve;});
 const stream=new PreviewStream(()=>true); let frames=0; stream.onFrame=()=>{frames++;};
 await stream.start('wss://example.invalid/ws'); const socket=state.sockets.at(-1);
 socket.emit('message',jpeg()); await tick();
 socket.emit('message',jpeg()); socket.emit('message',jpeg());
 assert.equal(socket.sent.filter(s=>s==='{"type":"ack"}').length,1);
 const before=state.released; stream.stop(); release(); state.decodeGate=null; await tick();
 assert.equal(frames,0); assert.equal(state.released,before+1);
});
test('preview rejects oversized decoded image and native decoder exceptions without leaking URLs',async()=>{
 const stream=new PreviewStream(()=>true); const failures=[]; stream.onFailure=m=>failures.push(m);
 state.imageSize={width:8000,height:8000};
 await stream.start('wss://example.invalid/ws?wsTicket=do-not-leak');
 for(let index=0;index<3;index++){state.sockets.at(-1).emit('message',jpeg());await tick();}
 assert.match(failures[0],/尺寸连续超限/); assert.equal(failures.join('').includes('do-not-leak'),false);
 state.imageSize={width:720,height:1280}; state.throwSource=true;
 await stream.start('wss://example.invalid/ws'); state.sockets.at(-1).emit('message',jpeg()); await tick();
 assert.equal(failures.length,2); state.throwSource=false; stream.stop();
});
test('reconnecting a preview ignores all old socket messages and does not replay input',async()=>{
 const stream=new PreviewStream(()=>true); const controls=[]; const failures=[];
 stream.onControl=c=>controls.push(c); stream.onFailure=m=>failures.push(m);
 await stream.start('wss://example.invalid/old'); const old=state.sockets.at(-1); controller(old);
 await stream.send({type:'text',text:'once'});
 await stream.start('wss://example.invalid/new'); const current=state.sockets.at(-1);
 controller(old); old.emit('close',{code:4401,reason:'old'}); old.emit('message',jpeg());
 assert.equal(controls.length,1); assert.equal(failures.length,0); assert.equal(current.sent.length,0);
 await assert.rejects(stream.send({type:'text',text:'other'}),/控制权/);
 stream.stop();
});
const panelSource = (await readFile(new URL('../entry/src/main/ets/components/PreviewPanel.ets',import.meta.url),'utf8'))
 .split('  build() {')[0] + '}';
const panelJs = panelSource.replace("import { image } from '@kit.ImageKit';", '')
 .replace(/^import\s+[^\n]*?from\s+['"](?:\.\/ui\/|\.\.\/common\/Theme)[^'"]*['"];\n/gm, '')
 .replace("'../services/PreviewStream'", JSON.stringify(data(compile(source))))
 .replace("'../protocol/Preview'", JSON.stringify(protocolUrl)).replace(/@(?:Prop|State)\s+/g,'').replace(/@(?:StorageLink|Watch)\([^)]*\)\s*/g,'')
 .replace('@Component\nexport struct PreviewPanel','export class PreviewPanel');
const { PreviewPanel } = await import(data(compile(panelJs)));
test('closing remote preview clears the tab only after confirmed success, never retries failures',async()=>{
 const p=new PreviewPanel(); const tabs=[]; let closes=0; let stops=0;
 p.tabId='tab-a'; p.isCurrent=()=>true; p.onTab=id=>tabs.push(id); p.stream={stop(){stops++;}};
 p.closeTab=async id=>{assert.equal(id,'tab-a');closes++;throw new Error('timeout');};
 await p.closeConfirmed('tab-a');
 assert.equal(closes,1); assert.equal(p.tabId,'tab-a'); assert.equal(stops,0); assert.deepEqual(tabs,[]);
 assert.match(p.error,/不会自动重试/); assert.equal(p.busy,false);
 p.closeTab=async()=>{closes++;}; await p.closeConfirmed('tab-a');
 assert.equal(closes,2); assert.equal(p.tabId,''); assert.equal(stops,1); assert.deepEqual(tabs,['']);
 assert.equal(p.status,'远端页面已关闭');
});
test('closing obsolete tab or late close acknowledgement cannot clear a new environment tab',async()=>{
 const p=new PreviewPanel(); p.tabId='tab-a'; p.isCurrent=()=>true;
 let closes=0; let finish; const tabs=[]; p.onTab=id=>tabs.push(id);
 p.closeTab=async()=>{closes++;await new Promise(resolve=>{finish=resolve;});};
 await p.closeConfirmed('other'); assert.equal(closes,0);
 const closing=p.closeConfirmed('tab-a'); p.generation++; p.tabId='tab-b'; finish(); await closing;
 assert.equal(p.tabId,'tab-b'); assert.deepEqual(tabs,[]);
 p.isCurrent=()=>false; await p.closeConfirmed('tab-b'); assert.equal(closes,1);
});


test('preview tab list only admits server tabs belonging to the requested thread', () => {
 const session={threadId:'thread-a',tabId:'tab-a',runtime:'server',navStatus:{url:'http://localhost:3000',title:'Fixture'}};
 assert.deepEqual(previewTabs({sessions:[session,{...session,threadId:'other',tabId:'other'},{...session,runtime:'desktop',tabId:'desktop'}]},'thread-a'),
  [{tabId:'tab-a',url:'http://localhost:3000',title:'Fixture',zoomFactor:1,viewport:{_tag:'fill'}}]);
 assert.throws(()=>previewTabs({sessions:[session,session]},'thread-a'),/重复/);
 assert.throws(()=>previewTabs({sessions:[{...session,tabId:''}]},'thread-a'),/标识/);
 assert.throws(()=>previewTabs({},'thread-a'),/列表/);
 assert.deepEqual(previewHistory(1),{type:'history',delta:1});
 assert.deepEqual(previewHistory(-1),{type:'history',delta:-1});
 assert.throws(()=>previewHistory(0));
});
test('switching tabs stops old stream and input, never closes remote tabs or takes control',()=>{
 const p=new PreviewPanel(); const selected=[]; let stops=0;
 p.isCurrent=()=>true; p.tabId='a'; p.tabs=[{tabId:'a',url:'http://localhost/a',title:'A'},{tabId:'b',url:'http://localhost/b',title:'B'}];
 p.stream={stop(){stops++;}}; p.input='do not replay'; p.controlling=true; p.canOperate=true;
 p.onTab=id=>selected.push(id); p.selectTab('outside'); assert.equal(stops,0);
 p.selectTab('b'); assert.equal(stops,1); assert.equal(p.tabId,'b'); assert.equal(p.address,'http://localhost/b');
 assert.equal(p.input,''); assert.equal(p.controlling,false); assert.equal(p.stream,undefined); assert.deepEqual(selected,['b']);
 p.newTab(); assert.equal(p.tabId,''); assert.equal(p.address,''); assert.equal(p.tabs.length,2);
 p.foreground=false; p.selectTab('a'); assert.equal(p.tabId,'');
});
test('refresh discards late cross-environment lists and preserves selection on failure',async()=>{
 const p=new PreviewPanel(); p.isCurrent=()=>true; p.tabId='a'; p.tabs=[{tabId:'a',title:'A',url:''}];
 let finish; p.listTabs=()=>new Promise(resolve=>{finish=resolve;});
 const pending=p.refreshTabs(); p.disconnect(); p.tabId='b'; finish([{tabId:'late',title:'Late',url:''}]); await pending;
 assert.equal(p.tabId,'b'); assert.equal(p.tabs[0].tabId,'a');
 p.listTabs=async()=>{throw new Error('offline');}; await p.refreshTabs();
 assert.equal(p.tabId,'b'); assert.equal(p.tabs[0].tabId,'a'); assert.match(p.error,/offline/);
 p.listTabs=async()=>[]; await p.refreshTabs(); assert.equal(p.tabId,''); assert.equal(p.busy,false);
});

test('navigation events read current title and address but preserve unfinished address edits',async()=>{
 const p=new PreviewPanel(); p.isCurrent=()=>true; p.tabId='a'; p.address='http://localhost/alpha';
 let changed; let stopped=0; let url='http://localhost/beta';
 p.watchTabs=callback=>{changed=callback;return()=>{stopped++;};};
 p.listTabs=async()=>[{tabId:'a',title:url.endsWith('beta')?'Beta':'Gamma',url}];
 await p.refreshTabs(); assert.equal(p.address,url); assert.equal(p.tabs[0].title,'Beta');
 p.address='http://localhost/unfinished'; p.addressDirty=true; url='http://localhost/gamma';
 changed(); await tick(); assert.equal(p.address,'http://localhost/unfinished'); assert.equal(p.tabs[0].title,'Gamma');
 p.addressDirty=false; p.addressEditing=true; p.syncAddress(); assert.equal(p.address,url);
 p.addressEditing=false; p.syncAddress(); assert.equal(p.address,url);
 p.disconnect(); assert.equal(stopped,1); url='http://localhost/late'; changed(); await tick();
 assert.equal(p.address,'http://localhost/gamma');
});
test('navigation events during a list read coalesce into one fresh read without publishing stale metadata',async()=>{
 const p=new PreviewPanel(); p.isCurrent=()=>true; p.tabId='a'; p.address='http://localhost/initial';
 let changed; let finish; let reads=0;
 p.watchTabs=callback=>{changed=callback;return()=>{};};
 p.listTabs=async()=>{reads++; if(reads===1) return await new Promise(resolve=>{finish=resolve;});
  return [{tabId:'a',title:'Latest',url:'http://localhost/latest'}];};
 const pending=p.refreshTabs(); changed(); changed(); changed();
 finish([{tabId:'a',title:'Stale',url:'http://localhost/stale'}]); await pending; await tick();
 assert.equal(reads,2); assert.equal(p.address,'http://localhost/latest'); assert.equal(p.tabs[0].title,'Latest');
 assert.equal(p.listing,false); assert.equal(p.listAgain,false);
});

test('resize sends exactly an upstream-compatible viewport and verifies scoped snapshot and CSS zoom', () => {
  const [phone, tablet, desktop] = PREVIEW_RESIZE_CHOICES.map(choice => choice.viewport);
  assert.deepEqual(previewResizeInput('thread', 'tab', phone), {
    threadId: 'thread', tabId: 'tab', viewport: { _tag: 'preset', presetId: 'iphone-12-pro', width: 390, height: 844 }
  });
  assert.equal(tablet.presetId, 'ipad-mini');
  assert.equal(desktop._tag, 'freeform');
  for (const invalid of [{ ...phone, height: 740 }, { ...desktop, width: 239 }, { ...desktop, width: 380.5 }]) {
    assert.throws(() => previewResizeInput('thread', 'tab', invalid), /尺寸/);
  }
  const snapshot = { threadId: 'thread', tabId: 'tab', runtime: 'server', viewport: phone, zoomFactor: 1.25 };
  assert.deepEqual(verifyPreviewResize(snapshot, 'thread', 'tab', phone), { width: 312, height: 675 });
  assert.throws(() => verifyPreviewResize(snapshot, 'thread', 'other', phone), /已变化/);
  assert.throws(() => verifyPreviewResize({ ...snapshot, viewport: tablet }, 'thread', 'tab', phone), /尚未确认/);
  assert.equal(previewFrameMatchesViewport({ width: 312, height: 675 }, phone), true);
  assert.equal(previewFrameMatchesViewport({ width: 1280, height: 800 }, phone), false);
});

test('a viewport event drops an old async decoded frame but still acknowledges it', async () => {
  const stream = new PreviewStream(() => true);
  let release;
  state.decodeGate = new Promise(resolve => { release = resolve; });
  const frames = [];
  stream.onFrame = frame => frames.push(frame);
  await stream.start('wss://example.invalid/ws');
  const socket = state.sockets.at(-1);
  socket.emit('message', jpeg());
  await tick();
  socket.emit('message', JSON.stringify({ type: 'viewport', width: 390, height: 844 }));
  const before = state.released;
  release();
  state.decodeGate = null;
  await tick();
  assert.equal(frames.length, 0);
  assert.equal(state.released, before + 1);
  assert.deepEqual(socket.sent, ['{"type":"ack"}']);
  socket.emit('message', jpeg());
  await tick();
  assert.equal(frames.length, 1);
  for (const frame of frames) await frame.release();
  stream.stop();
});

test('resize freezes touch and reconnects media, waiting for both new viewport and matching JPEG', async () => {
  const panel = new PreviewPanel();
  panel.tabId = 'tab';
  panel.isCurrent = () => true;
  panel.listTabs = async () => [{ tabId: 'tab', url: '', title: 'Fixture' }];
  panel.streamUrl = async () => 'wss://example.invalid/ws';
  await panel.connect();
  const oldSocket = state.sockets.at(-1);
  controller(oldSocket);
  panel.hasTouch = true;
  let finish;
  panel.resizeTab = async (tabId, viewport) => {
    assert.equal(tabId, 'tab');
    assert.equal(viewport.width, 390);
    return await new Promise(resolve => { finish = resolve; });
  };
  const switching = panel.applyResize();
  assert.equal(panel.hasTouch, false);
  assert.equal(panel.busy, true);
  assert.equal(oldSocket.closed, false);
  finish({ width: 390, height: 844 });
  await switching;
  assert.equal(oldSocket.closed, true);
  const socket = state.sockets.at(-1);
  assert.notEqual(socket, oldSocket);
  controller(socket);
  socket.emit('message', JSON.stringify({ type: 'viewport', width: 1280, height: 800 }));
  socket.emit('message', jpeg());
  await tick();
  assert.equal(panel.viewportPending, true);
  socket.emit('message', JSON.stringify({ type: 'viewport', width: 390, height: 844 }));
  assert.equal(panel.viewportPending, true);
  socket.emit('message', jpeg());
  await tick();
  assert.equal(panel.viewportPending, true);
  const originalSize = state.imageSize;
  state.imageSize = { width: 390, height: 844 };
  socket.emit('message', jpeg());
  await tick();
  state.imageSize = originalSize;
  assert.equal(panel.viewportPending, false);
  assert.equal(panel.frameCount, 1);
  assert.equal(panel.viewportLabel, '390 × 844');
  panel.disconnect();
});

test('first-frame timeout offers manual recovery without creating another media connection', async (t) => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const panel = new PreviewPanel();
  panel.tabId = 'tab';
  panel.isCurrent = () => true;
  panel.streamUrl = async () => 'wss://example.invalid/ws';
  panel.listTabs = async () => [{ tabId: 'tab', title: 'Fixture', url: '' }];
  await panel.connect();
  const socket = state.sockets.at(-1);
  const socketCount = state.sockets.length;
  assert.equal(panel.waitingForFrame, true);
  controller(socket);
  t.mock.timers.tick(12000);
  assert.equal(panel.firstFrameTimedOut, true);
  assert.equal(state.sockets.length, socketCount);
  socket.emit('message', jpeg());
  await tick();
  assert.equal(panel.waitingForFrame, false);
  assert.equal(panel.firstFrameTimedOut, false);
  assert.equal(panel.frameCount, 1);
  panel.disconnect();
});

function newPreviewAttempt() {
  const panel = new PreviewPanel();
  const calls = { tabs: 0, media: 0, prepare: 0 };
  panel.isCurrent = () => true;
  panel.prepareConnection = () => { calls.prepare++; };
  panel.address = 'http://localhost:3000';
  panel.createTab = async () => { calls.tabs++; return 'new'; };
  panel.streamUrl = async id => {
    assert.equal(id, 'new');
    calls.media++;
    return 'wss://example.invalid/ws';
  };
  panel.listTabs = async () => [{ tabId: 'new', title: 'New', url: panel.address }];
  panel.navigate();
  return { panel, calls };
}

test('a newly created tab automatically reattaches its media once without replaying commands', async (t) => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const { panel, calls } = newPreviewAttempt();
  await tick();
  const initialSocket = state.sockets.at(-1);
  controller(initialSocket);
  const preparations = calls.prepare;
  t.mock.timers.tick(3499);
  assert.equal(calls.media, 1);
  t.mock.timers.tick(1);
  await tick();
  const retrySocket = state.sockets.at(-1);
  assert.equal(initialSocket.closed, true);
  assert.notEqual(retrySocket, initialSocket);
  assert.deepEqual({ tabs: calls.tabs, media: calls.media }, { tabs: 1, media: 2 });
  // The only extra prepare is the ordinary metadata refresh after a socket attaches.
  assert.equal(calls.prepare, preparations + 1);
  assert.deepEqual(initialSocket.sent, []);
  assert.deepEqual(retrySocket.sent, []);
  assert.equal(panel.firstFrameRetryTimer, 0);
  t.mock.timers.tick(12000);
  assert.equal(panel.firstFrameTimedOut, true);
  assert.equal(calls.media, 2);
  panel.disconnect();
  assert.equal(panel.firstFrameTimer, 0);
});

test('first frame, failed media, background, changed context and released controls prevent automatic reattach', async (t) => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const cancel = [
    (_panel, socket) => { socket.emit('message', jpeg()); },
    (_panel, socket) => { socket.emit('error'); },
    panel => { panel.foreground = false; panel.foregroundChanged(); },
    panel => { panel.isCurrent = () => false; },
    panel => { panel.aboutToDisappear(); },
    (_panel, socket) => { controller(socket, 'another-viewer'); },
    (panel, socket) => { controller(socket); return panel.send({ type: 'releaseControl' }); },
  ];
  for (const stop of cancel) {
    const { panel, calls } = newPreviewAttempt();
    await tick();
    assert.ok(panel.firstFrameRetryTimer);
    await stop(panel, state.sockets.at(-1));
    await tick();
    t.mock.timers.tick(3500);
    await tick();
    assert.equal(calls.media, 1);
    assert.equal(panel.firstFrameRetryTimer, 0);
    panel.disconnect();
    assert.equal(panel.firstFrameTimer, 0);
  }
});

test('live frames preserve control labels and stale taps never cross viewer leases', async () => {
  const panel = new PreviewPanel();
  panel.tabId = 'tab'; panel.isCurrent = () => true;
  panel.streamUrl = async () => 'wss://example.invalid/ws';
  panel.listTabs = async () => [{ tabId: 'tab', title: 'Fixture', url: '' }];
  const originalSize = state.imageSize;
  const originalTouchType = globalThis.TouchType;
  globalThis.TouchType = { Down: 0, Up: 1, Cancel: 2 };
  const point = { x: 100, y: 100 };
  const touch = type => ({ type, touches: [point], changedTouches: [point] });
  const transfer = (socket, who, generation, canOperate = true) => socket.emit('message',
    JSON.stringify({ type:'control', canOperate, controller:who, generation, dialog:null }));
  try {
    await panel.connect();
    const socket = state.sockets.at(-1);
    panel.displayWidth = 390; panel.displayHeight = 740;
    socket.emit('message', JSON.stringify({ type: 'viewport', width: 390, height: 740 }));
    state.imageSize = { width: 390, height: 740 };
    transfer(socket, 'another-viewer', 2);
    socket.emit('message', jpeg());
    await tick();
    assert.equal(panel.status, '实时画面');
    assert.equal(panel.controlStatus(), '另一查看器正在控制');
    transfer(socket, 'unclaimed', 3, false);
    socket.emit('message', jpeg());
    await tick();
    assert.equal(panel.controlStatus(), '只读观看');
    transfer(socket, 'you', 4);
    await panel.touch(touch(TouchType.Down));
    transfer(socket, 'another-viewer', 5);
    transfer(socket, 'you', 6);
    await panel.touch(touch(TouchType.Up));
    assert.deepEqual(socket.sent.map(JSON.parse).filter(event => event.type === 'mouse'), []);
    let resolveDown;
    const send = socket.send.bind(socket);
    socket.send = async value => {
      const result = await send(value);
      if (JSON.parse(value).action === 'down') await new Promise(resolve => { resolveDown = resolve; });
      return result;
    };
    await panel.touch(touch(TouchType.Down));
    const pending = panel.touch(touch(TouchType.Up));
    await tick();
    transfer(socket, 'another-viewer', 7);
    transfer(socket, 'you', 8);
    resolveDown();
    await pending;
    assert.deepEqual(socket.sent.map(JSON.parse).filter(event => event.type === 'mouse').map(event => event.action), ['down']);
    socket.send = send;
    await panel.touch(touch(TouchType.Down));
    await panel.touch(touch(TouchType.Up));
    assert.deepEqual(socket.sent.map(JSON.parse).filter(event => event.type === 'mouse').map(event => event.action), ['down', 'down', 'up']);
  } finally {
    panel.disconnect();
    state.imageSize = originalSize;
    globalThis.TouchType = originalTouchType;
  }
});

test('ordinary attach displays a valid frame while mismatched CSS geometry keeps touch and zoom blocked', async () => {
  const panel = new PreviewPanel();
  panel.tabId = 'tab';
  panel.isCurrent = () => true;
  panel.streamUrl = async () => 'wss://example.invalid/ws';
  panel.listTabs = async () => [{ tabId: 'tab', title: 'Fixture', url: '', zoomFactor: 1, viewport: { _tag: 'fill' } }];
  const oldSize = state.imageSize;
  try {
    await panel.connect();
    const socket = state.sockets.at(-1);
    controller(socket);
    socket.emit('message', JSON.stringify({ type: 'viewport', width: 390, height: 740 }));
    state.imageSize = { width: 390, height: 700 };
    socket.emit('message', jpeg());
    await tick();
    assert.ok(panel.frame);
    assert.equal(panel.frameCount, 1);
    assert.equal(panel.viewportPending, true);
    assert.equal(panel.canZoom(), false);
    assert.equal(panel.viewportLabel, '触控坐标待同步');
  } finally {
    panel.disconnect();
    state.imageSize = oldSize;
  }
});

test('oversized frames retain the last valid picture and allow changing zoom before a fresh matching frame', async () => {
  const panel = new PreviewPanel();
  panel.tabId = 'tab'; panel.isCurrent = () => true;
  let zoomFactor = 0.25;
  panel.streamUrl = async () => 'wss://example.invalid/ws';
  panel.listTabs = async () => [{ tabId: 'tab', title: 'Fixture', url: '', zoomFactor,
    viewport: { _tag: 'freeform', width: 390, height: 740 } }];
  const previousSize = state.imageSize;
  try {
    await panel.connect();
    const initial = state.sockets.at(-1);
    controller(initial);
    initial.emit('message', JSON.stringify({ type: 'viewport', width: 1560, height: 2960 }));
    state.imageSize = { width: 675, height: 1280 };
    initial.emit('message', jpeg());
    await tick();
    const lastGood = panel.frame;
    assert.ok(lastGood);
    const releases = state.released;
    state.imageSize = { width: 3120, height: 5920 };
    initial.emit('message', jpeg());
    await tick();
    assert.equal(panel.frame, lastGood);
    assert.equal(state.released, releases);
    assert.equal(panel.frameCount, 1);
    assert.equal(panel.frameSkipped, true);
    assert.equal(panel.inputSuspended(), true);
    assert.equal(panel.canZoom(), true);
    panel.zoomTab = async (_id, requested, css) => {
      assert.deepEqual(css, { width: 1560, height: 2960 });
      zoomFactor = requested;
      return { zoomFactor, viewport: { width: 780, height: 1480 } };
    };
    await panel.applyZoom(0.5);
    assert.equal(panel.frame, lastGood);
    assert.equal(panel.frameCount, 0);
    const changed = state.sockets.at(-1);
    controller(changed);
    changed.emit('message', JSON.stringify({ type: 'viewport', width: 1560, height: 2960 }));
    state.imageSize = { width: 675, height: 1280 };
    changed.emit('message', jpeg());
    await tick();
    assert.equal(panel.frame, lastGood);
    assert.equal(panel.frameSkipped, true);
    changed.emit('message', JSON.stringify({ type: 'viewport', width: 780, height: 1480 }));
    changed.emit('message', jpeg());
    await tick();
    assert.notEqual(panel.frame, lastGood);
    assert.equal(panel.frameSkipped, false);
    assert.equal(panel.inputSuspended(), false);
    assert.equal(panel.viewportPending, false);
  } finally {
    panel.disconnect();
    state.imageSize = previousSize;
  }
});

test('tab zoom uses the confirmed CSS viewport and freezes input until a fresh matching stream frame', async () => {
  const panel = new PreviewPanel();
  const tab = { tabId: 'tab', title: 'Zoom', url: 'http://localhost:3000', viewport: { _tag: 'fill' }, zoomFactor: 1 };
  panel.tabId = tab.tabId;
  panel.isCurrent = () => true;
  panel.streamUrl = async () => 'wss://example.invalid/ws';
  let confirmed = 1;
  panel.listTabs = async () => [{ ...tab, zoomFactor: confirmed }];
  const previousSize = state.imageSize;
  const previousTouchType = globalThis.TouchType;
  globalThis.TouchType = { Down: 0, Up: 1, Cancel: 2 };
  const touch = (type, x, y) => ({ type, touches: [{ x, y }], changedTouches: [{ x, y }] });
  try {
    await panel.connect();
    const previous = state.sockets.at(-1);
    controller(previous, 'unclaimed');
    previous.emit('message', JSON.stringify({ type: 'viewport', width: 800, height: 600 }));
    state.imageSize = { width: 400, height: 300 };
    previous.emit('message', jpeg());
    await tick();
    assert.equal(panel.canZoom(), true);
    assert.equal(panel.canResize(), false);
    panel.zoomTab = async (id, zoom, measured) => {
      assert.equal(id, 'tab');
      assert.equal(zoom, 1.25);
      assert.deepEqual(measured, { width: 800, height: 600 });
      confirmed = zoom;
      return { zoomFactor: zoom, viewport: { width: 640, height: 480 }, viewportTolerance: 1 };
    };
    await panel.applyZoom(1.25);
    assert.equal(previous.closed, true);
    assert.equal(panel.zoomLabel(), '缩放 125%');
    const current = state.sockets.at(-1);
    controller(current);
    current.emit('message', JSON.stringify({ type: 'viewport', width: 800, height: 600 }));
    current.emit('message', jpeg());
    await tick();
    assert.equal(panel.frameCount, 0);
    assert.equal(panel.pendingAdjustment, '缩放');
    await panel.touch(touch(TouchType.Down, 160, 120));
    await panel.touch(touch(TouchType.Up, 160, 120));
    assert.deepEqual(current.sent.map(JSON.parse).filter(event => event.type === 'mouse'), []);
    current.emit('message', JSON.stringify({ type: 'viewport', width: 640, height: 480 }));
    state.imageSize = { width: 400, height: 240 };
    current.emit('message', jpeg());
    await tick();
    assert.equal(panel.frameCount, 0);
    state.imageSize = { width: 400, height: 300 };
    current.emit('message', jpeg());
    await tick();
    assert.equal(panel.pendingAdjustment, '');
    assert.equal(panel.viewportLabel, '640 × 480');
    panel.displayWidth = 320;
    panel.displayHeight = 240;
    await panel.touch(touch(TouchType.Down, 160, 120));
    await panel.touch(touch(TouchType.Up, 160, 120));
    assert.deepEqual(current.sent.map(JSON.parse).filter(event => event.type === 'mouse').map(({ x, y }) => [x,y]),
      [[320,240],[320,240]]);
  } finally {
    panel.disconnect();
    state.imageSize = previousSize;
    globalThis.TouchType = previousTouchType;
  }
});

test('go from a new-tab address starts one creation and existing-tab navigation still needs control', async () => {
  const panel = new PreviewPanel();
  panel.isCurrent = () => true;
  panel.newTab();
  assert.equal(panel.canNavigate(), false);
  panel.address = 'http://localhost:3000';
  assert.equal(panel.canNavigate(), true);
  let creates = 0;
  let finish;
  panel.createTab = () => { creates++; return new Promise(resolve => { finish = resolve; }); };
  panel.streamUrl = async () => 'wss://example.invalid/ws';
  panel.listTabs = async () => [{ tabId: 'new', title: 'New', url: panel.address }];
  panel.navigate();
  panel.navigate();
  assert.equal(creates, 1);
  finish('new');
  await tick();
  assert.equal(panel.tabId, 'new');
  assert.equal(panel.canNavigate(), false);
  controller(state.sockets.at(-1));
  assert.equal(panel.canNavigate(), true);
  panel.disconnect();
});

test('legacy 100% recovery is explicitly confirmed for the selected controlled tab, and failures freeze input until resize', async () => {
  const panel = new PreviewPanel();
  panel.tabId = 'tab';
  panel.isCurrent = () => true;
  panel.requiresZoomRepair = () => true;
  panel.streamUrl = async () => 'wss://example.invalid/ws';
  panel.listTabs = async () => [{ tabId: 'tab', title: 'Legacy', url: '', zoomFactor: 1,
    viewport: { _tag: 'freeform', width: 390, height: 740 } }];
  const originalAlert = globalThis.AlertDialog;
  const originalSize = state.imageSize;
  let dialog;
  globalThis.AlertDialog = { show(value) { dialog = value; } };
  let repairs = 0;
  panel.zoomTab = async (_id, _zoom, _viewport, stillControlled) => {
    assert.equal(stillControlled(), true);
    repairs++;
    throw new Error('unconfirmed');
  };
  try {
    await panel.connect();
    const socket = state.sockets.at(-1);
    socket.emit('message', JSON.stringify({ type: 'viewport', width: 390, height: 740 }));
    state.imageSize = { width: 390, height: 740 };
    socket.emit('message', jpeg());
    await tick();
    controller(socket, 'unclaimed');
    panel.confirmZoomRepair();
    assert.equal(dialog, undefined);
    controller(socket);
    const oldMenu = panel.zoomMenu(panel.tabId, panel.generation, panel.controlRevision);
    controller(socket, 'unclaimed');
    controller(socket);
    oldMenu.find(item => item.value === '100%（恢复）').action();
    assert.equal(dialog, undefined);
    panel.confirmZoomRepair();
    assert.match(dialog.message, /一像素.*网址不会刷新/);
    controller(socket, 'unclaimed');
    controller(socket);
    dialog.secondaryButton.action();
    await tick();
    assert.equal(repairs, 0);
    panel.confirmZoomRepair();
    dialog.secondaryButton.action();
    await tick();
    assert.equal(repairs, 1);
    assert.equal(panel.repairBlocked(), true);
    assert.match(panel.error, /请选择不同的固定尺寸/);
    assert.equal(panel.canResize(), true);
    const sentBefore = socket.sent.length;
    panel.input = 'draft';
    await panel.typeText();
    await panel.sendKey('Enter');
    await panel.send({ type: 'reload' });
    assert.equal(panel.input, 'draft');
    assert.equal(socket.sent.length, sentBefore);
    panel.resizeTab = async () => ({ width: 390, height: 844 });
    await panel.applyResize();
    assert.equal(panel.repairBlocked(), true);
    const recovered = state.sockets.at(-1);
    recovered.emit('message', JSON.stringify({ type: 'viewport', width: 390, height: 844 }));
    state.imageSize = { width: 390, height: 844 };
    recovered.emit('message', jpeg());
    await tick();
    assert.equal(panel.repairBlocked(), false);
  } finally {
    panel.disconnect();
    globalThis.AlertDialog = originalAlert;
    state.imageSize = originalSize;
  }
});

test('resize rejects missing control and an unknown result stops media without a second RPC', async () => {
  const panel = new PreviewPanel();
  panel.isCurrent = () => true;
  panel.tabId = 'current';
  let stopped = 0;
  let attempts = 0;
  panel.stream = { stop() { stopped++; } };
  panel.resizeTab = async () => { attempts++; throw new Error('timeout'); };
  await panel.applyResize();
  assert.equal(attempts, 0);
  panel.canOperate = true;
  panel.controlling = true;
  await panel.applyResize();
  await panel.applyResize();
  assert.equal(attempts, 1);
  assert.equal(stopped, 1);
  assert.equal(panel.viewportPending, true);
  assert.match(panel.error, /未确认/);
  assert.equal(panel.tabId, 'current');
});

test('DPR 2 fallback screenshots decode to bounded proportional PixelMaps', async () => {
  const stream = new PreviewStream(() => true);
  const frames = [];
  let failures = 0;
  stream.onFrame = (frame, size) => frames.push({ frame, size });
  stream.onFailure = () => { failures++; };
  const originalSize = state.imageSize;
  const sources = [{ width: 1536, height: 2048 }, { width: 2560, height: 1600 }];
  try {
    await stream.start('wss://example.invalid/ws');
    const socket = state.sockets.at(-1);
    for (const size of sources) {
      state.imageSize = size;
      socket.emit('message', jpeg());
      await tick();
      const output = frames.at(-1).size;
      const desiredSize = previewDecodeSize(size);
      assert.deepEqual(state.decodeOptions.at(-1), { editable: false, desiredSize });
      assert.deepEqual(output, desiredSize);
      assert.ok(output.width <= 1920 && output.height <= 1920);
      assert.ok(output.width * output.height <= 2073600);
      assert.ok(output.width < size.width && output.height < size.height);
      assert.ok(previewFrameMatchesViewport(output, size));
    }
    assert.equal(failures, 0);
    assert.equal(frames.length, 2);
    assert.deepEqual(socket.sent, ['{"type":"ack"}', '{"type":"ack"}']);
  } finally {
    state.imageSize = originalSize;
    stream.stop();
    for (const { frame } of frames) await frame.release();
  }
});

test('source limits are independent and actual decode output is validated before frame delivery', async () => {
  assert.throws(() => previewDecodeSize({ width: 4097, height: 1 }), /原图尺寸超限/);
  assert.throws(() => previewDecodeSize({ width: 3000, height: 3000 }), /原图尺寸超限/);
  assert.deepEqual(previewDecodeSize({ width: 1, height: 4096 }), { width: 1, height: 1920 });
  const stream = new PreviewStream(() => true);
  let frames = 0;
  const failures = [];
  stream.onFrame = () => { frames++; };
  stream.onFailure = reason => failures.push(reason);
  const originalSize = state.imageSize;
  state.imageSize = { width: 1536, height: 2048 };
  try {
    for (const output of [state.imageSize, { width: 1300, height: 1600 }, { width: 1247, height: 1000 }]) {
      state.outputSize = output;
      const released = state.released;
      const sourcesReleased = state.sourcesReleased;
      await stream.start('wss://example.invalid/ws');
      const socket = state.sockets.at(-1);
      socket.emit('message', jpeg());
      await tick();
      assert.equal(socket.closed, true);
      assert.equal(frames, 0);
      assert.match(failures.at(-1), /输出尺寸超限或比例无效/);
      assert.equal(state.released, released + 1);
      assert.equal(state.sourcesReleased, sourcesReleased + 1);
    }
  } finally {
    state.outputSize = null;
    state.imageSize = originalSize;
    stream.stop();
  }
});

test('a viewport revision that changes during PixelMap validation still discards and acknowledges the old frame', async () => {
  const stream = new PreviewStream(() => true);
  const failures = [];
  let frames = 0;
  let release;
  state.outputGate = new Promise(resolve => { release = resolve; });
  stream.onFrame = () => { frames++; };
  stream.onFailure = reason => failures.push(reason);
  try {
    await stream.start('wss://example.invalid/ws');
    const socket = state.sockets.at(-1);
    socket.emit('message', jpeg());
    await tick();
    socket.emit('message', JSON.stringify({ type: 'viewport', width: 768, height: 1024 }));
    const released = state.released;
    release();
    await tick();
    assert.equal(frames, 0);
    assert.deepEqual(failures, []);
    assert.equal(state.released, released + 1);
    assert.deepEqual(socket.sent, ['{"type":"ack"}']);
  } finally {
    state.outputGate = null;
    stream.stop();
  }
});

test('oversized stills interleaved with 25% live frames are released and acknowledged without decoding', async () => {
  const stream = new PreviewStream(() => true);
  const frames = [];
  let skipped = 0;
  const failures = [];
  stream.onFrame = (frame, size) => frames.push({ frame, size });
  stream.onFrameSkipped = () => { skipped++; };
  stream.onFailure = reason => failures.push(reason);
  const originalSize = state.imageSize;
  try {
    await stream.start('wss://example.invalid/ws');
    const socket = state.sockets.at(-1);
    socket.emit('message', JSON.stringify({ type: 'viewport', width: 1560, height: 2960 }));
    const before = state.decodeOptions.length;
    const releases = state.sourcesReleased;
    const send = socket.send;
    socket.send = async value => {
      if (skipped && frames.length === 0) assert.equal(state.sourcesReleased, releases + skipped);
      return send.call(socket, value);
    };
    state.imageSize = { width: 3120, height: 5920 };
    socket.emit('message', jpeg()); await tick();
    assert.equal(state.decodeOptions.length, before);
    assert.equal(skipped, 1);
    assert.equal(frames.length, 0);
    assert.equal(state.sourcesReleased, releases + 1);
    state.imageSize = { width: 675, height: 1280 };
    socket.emit('message', jpeg()); await tick();
    assert.equal(frames.length, 1);
    assert.deepEqual(frames[0].size, state.imageSize);
    state.imageSize = { width: 3120, height: 5920 };
    socket.emit('message', jpeg()); await tick();
    socket.emit('message', jpeg()); await tick();
    assert.equal(skipped, 2);
    assert.equal(state.decodeOptions.length, before + 1);
    assert.equal(socket.closed, false);
    assert.equal(socket.sent.length, 4);
    assert.deepEqual(failures, []);
  } finally {
    state.imageSize = originalSize;
    stream.stop();
    for (const { frame } of frames) await frame.release();
  }
});

test('three consecutive oversized frames are acknowledged then stop; invalid JPEG or dimensions still fail immediately', async () => {
  const stream = new PreviewStream(() => true);
  let skipped = 0;
  let frames = 0;
  const failures = [];
  stream.onFrameSkipped = () => { skipped++; };
  stream.onFrame = () => { frames++; };
  stream.onFailure = reason => failures.push(reason);
  const originalSize = state.imageSize;
  try {
    await stream.start('wss://example.invalid/ws');
    const socket = state.sockets.at(-1);
    state.imageSize = { width: 3120, height: 5920 };
    const before = state.decodeOptions.length;
    for (let index = 0; index < 3; index++) {
      socket.emit('message', jpeg());
      await tick();
    }
    assert.equal(skipped, 1);
    assert.equal(frames, 0);
    assert.equal(state.decodeOptions.length, before);
    assert.deepEqual(socket.sent, ['{"type":"ack"}', '{"type":"ack"}', '{"type":"ack"}']);
    assert.equal(socket.closed, true);
    assert.match(failures.at(-1), /连续超限/);
    await stream.start('wss://example.invalid/ws');
    state.imageSize = { width: 0, height: 5920 };
    state.sockets.at(-1).emit('message', jpeg()); await tick();
    assert.match(failures.at(-1), /尺寸信息无效/);
    await stream.start('wss://example.invalid/ws');
    state.imageSize = { width: 3120, height: 5920 };
    state.mimeType = 'image/png';
    state.sockets.at(-1).emit('message', jpeg()); await tick();
    assert.match(failures.at(-1), /格式无效/);
    await stream.start('wss://example.invalid/ws');
    state.sockets.at(-1).emit('message', new ArrayBuffer(PREVIEW_MAX_FRAME_BYTES + 1)); await tick();
    assert.match(failures.at(-1), /帧无效或超过/);
    await stream.start('wss://example.invalid/ws');
    state.sockets.at(-1).emit('message', Uint8Array.from([1, 2, 3, 4]).buffer); await tick();
    assert.match(failures.at(-1), /帧无效或超过/);
    assert.equal(skipped, 1);
    assert.equal(failures.length, 5);
  } finally {
    state.mimeType = 'image/jpeg';
    state.imageSize = originalSize;
    stream.stop();
  }
});
