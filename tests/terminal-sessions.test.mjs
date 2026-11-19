import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { compile, data } from './load-core.mjs';
import { TerminalGrid, terminalSnapshot, terminalSessions, newTerminalId, terminalCanvasSize, terminalFitSize,
  DEFAULT_TERMINAL_FONT_SIZE, MIN_TERMINAL_FONT_SIZE, MAX_TERMINAL_FONT_SIZE } from '../entry/src/main/ets/protocol/Terminal.ts';
import { record, text } from '../entry/src/main/ets/protocol/Wire.ts';
const summary=(terminalId, overrides={})=>({threadId:'thread-a',terminalId,cwd:'/fixture',label:terminalId,status:'running',hasRunningSubprocess:false,...overrides});
const empty=()=>({loaded:false,terminals:[]});
const uuid='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

test('terminal metadata snapshot/upsert/remove isolates thread and rejects malformed or duplicate identities',()=>{
 const state=terminalSessions(empty(),{type:'snapshot',terminals:[summary('a'),summary('other',{threadId:'other-thread'})]},'thread-a');
 assert.equal(state.loaded,true); assert.deepEqual(state.terminals.map(s=>s.terminalId),['a']);
 const updated=terminalSessions(state,{type:'upsert',terminal:summary('a',{status:'exited',label:'Finished'})},'thread-a');
 assert.equal(updated.terminals.length,1); assert.equal(updated.terminals[0].status,'exited');
 const pair=terminalSessions(state,{type:'upsert',terminal:summary('b')},'thread-a');
 assert.deepEqual(terminalSessions(pair,{type:'upsert',terminal:summary('a',{label:'New label'})},'thread-a').terminals.map(t=>t.terminalId),['a','b']);
 assert.equal(terminalSessions(updated,{type:'remove',threadId:'other-thread',terminalId:'a'},'thread-a'),updated);
 assert.deepEqual(terminalSessions(updated,{type:'remove',threadId:'thread-a',terminalId:'a'},'thread-a').terminals,[]);
 assert.throws(()=>terminalSessions(empty(),{type:'upsert',terminal:summary('a')},'thread-a'),/快照/);
 assert.throws(()=>terminalSessions(empty(),{type:'snapshot',terminals:[summary('a'),summary('a')]},'thread-a'),/重复/);
 assert.throws(()=>terminalSessions(empty(),{type:'snapshot',terminals:[summary('')]},'thread-a'),/标识/);
 assert.throws(()=>terminalSessions(empty(),{type:'snapshot',terminals:[summary('a',{status:'made-up'})]},'thread-a'),/状态/);
 assert.throws(()=>terminalSessions(empty(),{type:'unknown'},'thread-a'));
});
test('new terminal identity includes collision-resistant suffix and counts selected pending identity',()=>{
 assert.equal(newTerminalId(['term-1','term-2-'+uuid],uuid),'term-3-'+uuid);
 assert.notEqual(newTerminalId([],uuid),newTerminalId([],'bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee'));
 assert.throws(()=>newTerminalId([],'not-a-uuid'));
});

const runtime={TerminalGrid,terminalSnapshot,terminalSessions,newTerminalId,record,text,terminalCanvasSize,terminalFitSize,
 DEFAULT_TERMINAL_FONT_SIZE,MIN_TERMINAL_FONT_SIZE,MAX_TERMINAL_FONT_SIZE,
 workspacePrefs:{terminalFontSize:14},setTerminalFontSize:async size=>{runtime.workspacePrefs.terminalFontSize=size;},
 util:{generateRandomUUID:()=>uuid},CanvasRenderingContext2D:class{},RenderingContextSettings:class{},AlertDialog:{show(){}}};
globalThis.__terminalSessions=runtime;
const panelSource=(await readFile(new URL('../entry/src/main/ets/components/TerminalPanel.ets',import.meta.url),'utf8')).split('  build() {')[0]+'}';
const js=panelSource.replace(/^import[\s\S]*?;\n/gm,'').replace(/@(?:Prop|State)\s+/g,'')
 .replace(/@(?:StorageLink|Watch)\([^)]*\)\s*/g,'').replace('@Component\nexport struct TerminalPanel','export class TerminalPanel');
const {TerminalPanel}=await import(data(compile('const {TerminalGrid,terminalSnapshot,terminalSessions,newTerminalId,record,text,util,CanvasRenderingContext2D,RenderingContextSettings,AlertDialog,terminalCanvasSize,terminalFitSize,DEFAULT_TERMINAL_FONT_SIZE,MIN_TERMINAL_FONT_SIZE,MAX_TERMINAL_FONT_SIZE,workspacePrefs}=globalThis.__terminalSessions;\nconst setTerminalFontSize=(size)=>globalThis.__terminalSessions.setTerminalFontSize(size);\n'+js)));
const panel=()=>{const p=new TerminalPanel();p.threadId='thread-a';p.canOperate=()=>true;p.draw=()=>{};
 p.alive=true;p.canvasWidth=640;p.canvasHeight=384;return p;};
const loaded=(p, ids=['a','b'])=>{p.sessions=terminalSessions(empty(),{type:'snapshot',terminals:ids.map(id=>summary(id))},'thread-a');};
const snap=(id,history='')=>({type:'snapshot',snapshot:{threadId:'thread-a',terminalId:id,history,status:'running',sequence:0,cols:40,rows:24}});

test('selection cancels viewing and clears input/replies while old events cannot paint new terminal',()=>{
 const p=panel();loaded(p);p.terminalId='a';let stopped=0;let receive;
 p.attach=(id,size,resume,next)=>{assert.equal(id,'a');assert.equal(resume,true);receive=next;return()=>stopped++;};
 p.connect(); receive(snap('a','alpha')); assert.equal(p.active,true);
 p.input='never send';p.replyQueue=['reply'];p.selectSession('b');
 assert.equal(stopped,1);assert.equal(p.terminalId,'b');assert.equal(p.active,false);assert.equal(p.input,'');assert.deepEqual(p.replyQueue,[]);
 receive(snap('a','late'));assert.equal(p.active,false);assert.equal(p.grid.cells[0][0].char,' ');
});
test('unknown or failed metadata cannot create or connect unseen default terminal',()=>{
 const p=panel();let attaches=0;p.attach=()=>{attaches++;return()=>{};};
 p.createSession();p.connect();assert.equal(p.terminalId,'');assert.equal(attaches,0);
 let failed; p.watchTerminals=(receive,onFailure)=>{failed=onFailure;receive({type:'snapshot',terminals:[summary('a')]});return()=>{};};
 p.loadSessions();assert.equal(p.terminalId,'a');assert.equal(p.sessions.loaded,true);
 failed('offline');assert.equal(p.sessions.loaded,false);assert.equal(p.sessions.terminals.length,1);assert.match(p.listError,/未确认/);
 p.createSession();p.connect();assert.equal(attaches,0);assert.equal(p.terminalId,'a');
});
test('new identity is only started on explicit connection and restart is separate from resume',()=>{
 const p=panel();loaded(p,['term-1']);let requests=[];p.attach=(id,size,resume)=>{requests.push({id,resume});return()=>{};};
 p.createSession();assert.equal(p.terminalId,'term-2-'+uuid);assert.deepEqual(requests,[]);
 p.connect();assert.deepEqual(requests,[{id:'term-2-'+uuid,resume:true}]);
 p.connect(false);assert.equal(requests[1].resume,false);
});
test('all writes/replies/resizes target explicit selected identity and stale failures do not alter new session',async()=>{
 const p=panel();loaded(p);p.terminalId='a';p.active=true;let reject;const writes=[];
 p.write=(id,data)=>{writes.push({id,data});return new Promise((resolve,no)=>reject=no);};
 const pending=p.send('once');p.disconnect();p.selectSession('b');p.active=true;reject(new Error('late'));await pending;
 assert.deepEqual(writes,[{id:'a',data:'once'}]);assert.equal(p.active,true);assert.equal(p.error,'');assert.equal(p.busy,false);
 const replies=[];p.reply=async(id,data)=>replies.push({id,data});p.queueQueries(['query']);await new Promise(r=>setImmediate(r));
 assert.deepEqual(replies,[{id:'b',data:'query'}]);
 let target;p.resize=async(id)=>{target=id;};await p.fit();assert.equal(target,'b');
});
test('close confirmation only affects captured terminal and never retargets after selection changes',async()=>{
 const p=panel();loaded(p);p.terminalId='a';p.active=true;let calls=[];let finish;
 p.closeTerminal=id=>{calls.push(id);return new Promise(resolve=>finish=resolve);};
 const oldGeneration=p.generation;const pending=p.stopConfirmed('a',oldGeneration);
 p.disconnect();p.selectSession('b');p.active=true;finish();await pending;
 assert.deepEqual(calls,['a']);assert.equal(p.terminalId,'b');assert.equal(p.active,true);
 await p.stopConfirmed('a',oldGeneration);assert.equal(calls.length,1);
 p.closeTerminal=async id=>calls.push(id);await p.stopConfirmed('b',p.generation);
 assert.deepEqual(calls,['a','b']);assert.equal(p.terminalId,'');assert.deepEqual(p.sessions.terminals.map(s=>s.terminalId),['a']);
});
test('read-only viewing consumes queries without replies and blocks every mutation',async()=>{
 const p=panel();loaded(p);p.terminalId='a';p.canOperate=()=>false;const calls=[];
 p.attach=(id,size,resume,receive)=>{calls.push('observe:'+id);receive(snap(id));return()=>{};};
 p.write=async()=>calls.push('write');p.reply=async()=>calls.push('reply');p.resize=async()=>calls.push('resize');p.closeTerminal=async()=>calls.push('close');
 p.connect();p.receive({type:'output',threadId:'thread-a',terminalId:'a',sequence:1,data:'\x1b[6n'});
 await p.send('danger');await p.fit();await p.stopConfirmed('a',p.generation);p.createSession();p.connect(false);
 assert.deepEqual(calls,['observe:a']);assert.deepEqual(p.replyQueue,[]);assert.equal(p.terminalId,'a');
});
test('background releases metadata and terminal watchers; late callbacks cannot restore state',()=>{
 const p=panel();let receive;let metadataStops=0;let outputStops=0;
 p.watchTerminals=next=>{receive=next;return()=>metadataStops++;};p.loadSessions();receive({type:'snapshot',terminals:[summary('a')]});
 p.cancel=()=>outputStops++;p.active=true;p.foreground=false;p.foregroundChanged();
 assert.equal(metadataStops,1);assert.equal(outputStops,1);assert.equal(p.sessions.loaded,false);assert.equal(p.active,false);
 receive({type:'snapshot',terminals:[summary('b')]});assert.equal(p.terminalId,'a');assert.equal(p.sessions.loaded,false);
});

test('exited terminal can be closed without a live attachment',async()=>{
 const p=panel();p.sessions=terminalSessions(empty(),{type:'snapshot',terminals:[summary('a',{status:'exited'})]},'thread-a');
 p.terminalId='a';p.active=false;const closed=[];p.closeTerminal=async id=>closed.push(id);
 await p.stopConfirmed('a',p.generation);assert.deepEqual(closed,['a']);assert.equal(p.sessions.terminals.length,0);
});

test('reading stays anchored as output grows and latest resumes following',()=>{
 const p=panel();loaded(p);p.terminalId='a';p.canvasHeight=60;
 p.grid=new TerminalGrid(20,4);p.active=true;p.sequence=0;
 p.grid.feed('one\r\ntwo\r\nthree\r\nfour\r\nfive\r\nsix');
 p.readPage(1);assert.ok(p.readingOffset>0);
 const before=p.grid.viewText(p.readingOffset,p.visibleRows());
 p.receive({type:'output',threadId:'thread-a',terminalId:'a',sequence:1,data:'\r\nseven\r\neight'});
 assert.equal(p.grid.viewText(p.readingOffset,p.visibleRows()),before);
 p.readLatest();assert.equal(p.readingOffset,0);
 assert.match(p.grid.viewText(0,p.visibleRows()),/eight/);
});
test('switch and reconnect clear reading offset, alternate-screen transitions do not expose old history',()=>{
 const p=panel();loaded(p);p.terminalId='a';p.readingOffset=3;p.copyNotice='old';p.selectSession('b');
 assert.equal(p.readingOffset,0);assert.equal(p.copyNotice,'');
 p.readingOffset=3;p.attach=()=>()=>{};p.connect();assert.equal(p.readingOffset,0);
 p.grid=new TerminalGrid(20,3);p.grid.feed('a\r\nb\r\nc\r\nd');p.readingOffset=1;p.sequence=0;
 p.receive({type:'output',threadId:'thread-a',terminalId:'b',sequence:1,data:'\x1b[?1049hALT'});
 assert.equal(p.readingOffset,0);assert.match(p.grid.viewText(0,3),/ALT/);
});
test('explicit visible-page copy works while read-only and reports failure without any terminal writes',async()=>{
 const p=panel();loaded(p);p.terminalId='a';p.canOperate=()=>false;p.canvasHeight=40;
 p.grid=new TerminalGrid(5,2);p.grid.feed('abcdef');
 const copied=[];p.onCopy=async value=>copied.push(value);
 assert.deepEqual(copied,[]);await p.copyVisible();
 assert.deepEqual(copied,[p.grid.viewText(0,2)]);assert.match(copied[0],/abcdef/);
 assert.equal(p.copyNotice,'当前页已复制');
 p.onCopy=async()=>{throw Error('private system details');};await p.copyVisible();
 assert.equal(p.copyNotice,'复制失败，请重试');assert.equal(p.copying,false);
 p.foreground=false;await p.copyVisible();assert.equal(copied.length,1);
});
test('copy late completion cannot update a different terminal or background panel',async()=>{
 const p=panel();loaded(p);p.terminalId='a';p.grid.feed('alpha');let finish;
 p.onCopy=()=>new Promise(resolve=>finish=resolve);
 const pending=p.copyVisible();assert.equal(p.copying,true);p.selectSession('b');finish();await pending;
 assert.equal(p.copyNotice,'');assert.equal(p.copying,false);
 p.grid.feed('beta');const next=p.copyVisible();p.foreground=false;p.foregroundChanged();finish();await next;
 assert.equal(p.copyNotice,'');assert.equal(p.copying,false);
});

test('selection freezes the visible page and copies that snapshot while output continues', async () => {
 const p=panel();loaded(p);p.terminalId='a';p.canOperate=()=>false;p.canvasHeight=60;
 p.grid=new TerminalGrid(20,4);p.grid.feed('one\r\ntwo\r\nthree\r\nfour\r\nfive\r\nsix');
 p.readPage(1);
 const page=p.grid.viewText(p.readingOffset,p.visibleRows());
 const copied=[];p.onCopy=async value=>copied.push(value);
 p.selectVisibleText();
 assert.equal(p.selectionText,page);assert.deepEqual(copied,[]);
 assert.equal(p.readingNotice(),'当前页快照 · 长按文字选择');
 p.receive({type:'output',threadId:'thread-a',terminalId:'a',sequence:1,data:'\r\nseven\r\neight'});
 assert.equal(p.selectionText,page);
 await p.copyVisible(true);
 assert.deepEqual(copied,[page]);assert.equal(p.readingNotice(),'当前页快照 · 长按文字选择 · 当前页已复制');
 p.readLatest();
 assert.equal(p.selectionText,'');assert.match(p.grid.viewText(0,3),/eight/);
 assert.equal(p.readingNotice(),'跟随最新输出');
 await p.copyVisible(true);assert.deepEqual(copied,[page]);
});

test('selection clears on close, terminal change, reconnect, and background and ignores late copy completion', async () => {
 const p=panel();loaded(p);p.terminalId='a';p.attach=()=>()=>{};p.canvasHeight=20;
 let finish;p.onCopy=()=>new Promise(resolve=>finish=resolve);
 p.selectVisibleText();assert.equal(p.selectionText,'');assert.match(p.copyNotice,/没有可选择/);
 p.grid.feed('alpha');p.selectVisibleText();const pending=p.copyVisible(true);const finishFirst=finish;
 p.closeTextSelection();p.grid.feed(' beta');p.selectVisibleText();
 const next=p.copyVisible(true);const finishNext=finish;
 finishFirst();await pending;
 assert.equal(p.selectionText,'alpha beta');assert.equal(p.copyNotice,'');assert.equal(p.copying,true);
 p.selectSession('b');finishNext();await next;
 assert.equal(p.selectionText,'');assert.equal(p.copyNotice,'');assert.equal(p.copying,false);
 p.grid.feed('beta');p.selectVisibleText();p.canvasHeight=100;p.connect();assert.equal(p.selectionText,'');
 p.selectVisibleText();assert.equal(p.selectionText,'beta\n\n\n\n');
 p.foreground=false;p.foregroundChanged();assert.equal(p.selectionText,'');assert.equal(p.copyNotice,'');
});

test('history reading anchors before the PTY screen itself starts scrolling',()=>{
 const p=panel();loaded(p);p.terminalId='a';p.canvasHeight=60;p.grid=new TerminalGrid(20,8);p.sequence=0;
 p.grid.feed('one\r\ntwo\r\nthree\r\nfour\r\nfive');p.readPage(1);
 const before=p.grid.viewText(p.readingOffset,3);assert.equal(p.grid.scrollCount,0);
 p.receive({type:'output',threadId:'thread-a',terminalId:'a',sequence:1,data:'\r\nsix\r\nseven'});
 assert.equal(p.grid.scrollCount,0);assert.equal(p.grid.viewText(p.readingOffset,3),before);
});

test('font changes share measured cell geometry across attachment, resize and scrollback copy', async () => {
 const p=panel(); loaded(p); p.terminalId='a'; p.active=true;
 p.canvasReady=true; p.canvasWidth=300; p.canvasHeight=200;
 const measured=[];
 p.context={measureText(value) {
   measured.push({font:this.font,value});
   return {width:Number.parseInt(this.font,10)*6};
 }};
 const sizes=[];
 p.resize=async(id,size)=>sizes.push({id,size});
 await p.changeFontSize(1);
 assert.equal(p.fontSize,15);
 assert.equal(runtime.workspacePrefs.terminalFontSize,15);
 assert.deepEqual(measured,[{font:'15vp monospace',value:'MMMMMMMMMM'}]);
 assert.deepEqual(sizes,[{id:'a',size:{cols:33,rows:9}}]);
 assert.equal(p.visibleRows(),9);
 const attachments=[];
 p.attach=(id,size)=>{attachments.push({id,size});return()=>{};};
 p.connect();
 assert.deepEqual(attachments,sizes);
 p.grid=new TerminalGrid(40,5);
 p.grid.feed('x'.repeat(40)+'\r\ntail');
 assert.equal(p.pageText(),'x'.repeat(33)+'\ntail\n\n\n');
});

test('font adjustment stays local while read-only, disconnected, or too small for a safe resize', async () => {
 const p=panel(); loaded(p); p.terminalId='a'; p.active=true;
 let resizes=0; let attaches=0;
 p.resize=async()=>{resizes++;};p.attach=()=>{attaches++;return()=>{};};
 p.canOperate=()=>false;
 await p.changeFontSize(1);
 assert.equal(p.fontSize,15);
 p.canOperate=()=>true;
 p.active=false;
 await p.changeFontSize(1);
 assert.equal(p.fontSize,16);
 p.canvasHeight=0;
 p.connect();
 assert.equal(attaches,0);
 assert.match(p.error,/空间不足/);
 p.active=true;
 await p.changeFontSize(1);
 assert.equal(p.fontSize,17);
 assert.equal(resizes,0);
 assert.equal(p.pageText(),'');
 const save=runtime.setTerminalFontSize;
 runtime.setTerminalFontSize=async()=>{throw Error('disk');};
 try {
   await p.changeFontSize(1);
   assert.equal(p.fontSize,17);
   assert.match(p.error,/保存失败/);
 } finally { runtime.setTerminalFontSize=save; }
});

test('canvas placement uses measured cells and drawing old narrow rows after a wider resize is safe', () => {
 const p=panel();
 p.canvasWidth=100;p.canvasHeight=60;p.cellWidth=10;p.cellHeight=20;
 p.grid=new TerminalGrid(2,2);
 p.grid.feed('ab\r\ncd\r\nef');
 p.grid.resize(4,2);
 p.readingOffset=1;
 const drawn=[];
 p.context={fillRect(){},fillText(value,x,y){if(value.trim())drawn.push([value,x,y]);}};
 TerminalPanel.prototype.draw.call(p);
 assert.deepEqual(drawn,[['a',0,0],['b',10,0],['c',0,20],['d',10,20]]);
});
