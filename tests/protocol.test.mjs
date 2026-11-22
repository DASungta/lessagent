import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { bootstrapForm, createThread, RpcClient, sendMessage, serverBase,
  socketUrl, ThreadState, validateDescriptor } from '../entry/src/main/ets/protocol/Wire.ts';

function setup() {
  const sent = [];
  const rpc = new RpcClient({ send: async (frame) => { sent.push(JSON.parse(frame)); } });
  return { rpc, sent };
}

const fixtures = JSON.parse(await readFile(new URL('./fixtures/thread-stream.json', import.meta.url)));

test('HTTP direct URLs validated; credentials encoded as OAuth form data', () => {
  assert.equal(serverBase(' https://test.example:443/ '), 'https://test.example:443');
  assert.equal(serverBase('http://127.0.0.1:8787'), 'http://127.0.0.1:8787');
  for (const base of ['https://test:65536', 'http://test:0', 'https://user:pass@test', 'https://test/ws?token=x', 'wss://test', 'https://test/path']) {
    assert.throws(() => serverBase(base));
  }
  assert.equal(serverBase('http://192.168.1.1:3000'), 'http://192.168.1.1:3000');
  const params = new URLSearchParams(bootstrapForm('test +&中文'));
  assert.equal(params.get('subject_token'), 'test +&中文');
  assert.equal(params.get('grant_type'), 'urn:ietf:params:oauth:grant-type:token-exchange');
  assert.equal(new URL(socketUrl('https://test', 'test+/=')).searchParams.get('wsTicket'), 'test+/=');
  assert.throws(() => bootstrapForm(' '));
});

test('descriptor rejects missing/older/newer protocol before sending a credential', () => {
  const base = { environmentId: 'env-test', label: 'Test', serverVersion: '0.1' };
  assert.equal(validateDescriptor({ ...base, orchestrationProtocolVersion: 2 }).environmentId, 'env-test');
  for (const version of [undefined, 1, 3, '2']) assert.throws(() => validateDescriptor({ ...base, orchestrationProtocolVersion: version }));
});

test('RPC correlates out-of-order replies and sanitizes server failures', async () => {
  const { rpc, sent } = setup();
  const first = rpc.request('one', {});
  const second = rpc.request('two', {});
  assert.deepEqual(sent[0], { _tag: 'Request', id: '1', tag: 'one', payload: {}, headers: [] });
  rpc.receive(JSON.stringify([
    { _tag: 'Exit', requestId: '2', exit: { _tag: 'Success', value: { ok: true } } },
    { _tag: 'Exit', requestId: '1', exit: { _tag: 'Failure', cause: [{ _tag: 'Die', defect: 'SECRET' }] } }
  ]));
  assert.deepEqual(await second, { ok: true });
  await assert.rejects(first, (error) => !error.message.includes('SECRET'));
  rpc.fail('done');
});

test('streams ACK after applying batches; handles frame parts and Chinese', async () => {
  const { rpc, sent } = setup();
  const state = new ThreadState('thread-test');
  const result = rpc.request('orchestration.subscribeThread', { threadId: 'thread-test' }, (item) => state.apply(item));
  const frame = JSON.stringify({ _tag: 'Chunk', requestId: '1', values: fixtures });
  rpc.receive('\u001e' + frame.slice(0, 40));
  assert.equal(sent.length, 1);
  rpc.receive(frame.slice(40));
  assert.equal(state.messages[0].text, '你好 👋');
  assert.equal(state.messages[0].streaming, false);
  assert.deepEqual(sent[1], { _tag: 'Ack', requestId: '1' });
  rpc.receive('{"_tag":"Exit","requestId":"1","exit":{"_tag":"Success"}}');
  assert.equal(await result, undefined);
  rpc.fail('done');
});

test('duplicate/stale events ignored, global sequence gaps permitted, snapshot resets state', () => {
  const state = new ThreadState('thread-test');
  fixtures.forEach((item) => state.apply(item));
  state.apply(fixtures[1]);
  state.apply(fixtures[2]);
  assert.equal(state.cursor, 14);
  assert.equal(state.messages.length, 1);
  assert.equal(state.messages[0].text, '你好 👋');
  state.apply({ kind: 'event', sequence: 99, event: { type: 'future.event', threadId: 'thread-test' } });
  assert.equal(state.cursor, 99);
  state.apply(fixtures[0]);
  assert.equal(state.messages.length, 1);
  assert.equal(state.cursor, 99);
  state.apply({ ...fixtures[0], snapshotSequence: 100 });
  assert.equal(state.messages.length, 0);
  assert.equal(state.cursor, 100);
  assert.throws(() => state.apply({ ...fixtures[1], sequence: 101, event: { ...fixtures[1].event, threadId: 'other' } }));
  assert.throws(() => state.apply({ ...fixtures[1], sequence: -1 }));
});

test('malformed frames fail closed, without acknowledging rejected chunks', async () => {
  for (const frame of ['not json', 'null', '{"_tag":"Unexpected"}', '{"_tag":"Chunk","requestId":"1","values":{}}']) {
    const { rpc, sent } = setup();
    const result = rpc.request('stream', {}, () => {});
    rpc.receive(frame);
    await assert.rejects(result, /协议/);
    assert.equal(sent.length, 1);
  }
});

test('timeout interrupts and closes; mutation is never retried', async () => {
  const { rpc, sent } = setup();
  await assert.rejects(rpc.request('orchestration.dispatchCommand', { commandId: 'cmd-test' }, undefined, 10), /结果未知/);
  assert.equal(sent.filter((item) => item._tag === 'Request').length, 1);
  assert.deepEqual(sent[1], { _tag: 'Interrupt', requestId: '1' });
  await assert.rejects(rpc.request('again', {}), /断开/);
});

test('disconnect rejects all pending work; heartbeats follow Effect RPC envelopes', async () => {
  const { rpc, sent } = setup();
  rpc.ping();
  rpc.receive('{"_tag":"Ping"}');
  assert.deepEqual(sent, [{ _tag: 'Ping' }, { _tag: 'Pong' }]);
  const result = rpc.request('stream', {}, () => {});
  rpc.fail('连接断开，结果未知');
  await assert.rejects(result, /结果未知/);
  const count = sent.length;
  rpc.ping();
  assert.equal(sent.length, count);
});

test('command subset preserves IDs and uses approval-required mode', () => {
  const command = createThread('cmd', 'thread', 'project', 'provider', 'model');
  assert.equal(command.runtimeMode, 'approval-required');
  assert.equal(command.creationSource, 'mobile');
  assert.equal(command.commandId, 'cmd');
  const message = sendMessage('cmd2', 'thread', 'message', 'hello');
  assert.equal(message.type, 'message.dispatch');
  assert.deepEqual(message.dispatchMode, { type: 'start_immediately' });
  assert.throws(() => sendMessage('cmd', 'thread', 'message', ' '));
  assert.throws(() => createThread('cmd', 'thread', '', 'provider', 'model'));
});

test('assistant turn items render live text and merge with the final conversation message', () => {
  const state = new ThreadState('thread-test');
  state.apply(fixtures[0]);
  state.apply({ kind: 'event', sequence: 11, event: {
    type: 'turn-item.updated', threadId: 'thread-test', payload: {
      type: 'assistant_message', id: 'item-live', messageId: 'message-test', threadId: 'thread-test', text: '你', streaming: true
    }
  } });
  assert.equal(state.messages[0].text, '你');
  assert.equal(state.messages[0].streaming, true);
  state.apply(fixtures[2]);
  assert.equal(state.messages.length, 1);
  assert.equal(state.messages[0].text, '你好 👋');
  assert.equal(state.messages[0].streaming, false);
});

test('history keeps attachment names without retaining local paths or signed URLs',()=>{
 const state=new ThreadState('thread-test');
 state.apply({kind:'snapshot',snapshotSequence:1,projection:{thread:{id:'thread-test'},messages:[{id:'m',threadId:'thread-test',role:'user',text:'inspect',streaming:false,attachments:[{type:'file',id:'pending-test',name:'safe.txt',mimeType:'text/plain',sizeBytes:3,relativeUrl:'SECRET_URL',path:'PRIVATE_PATH'}]}]}});
 assert.deepEqual(state.messages[0].attachmentNames,['safe.txt']);
 assert.ok(!JSON.stringify(state.messages).includes('SECRET_URL'));assert.ok(!JSON.stringify(state.messages).includes('PRIVATE_PATH'));
});

test('a non-fatal read timeout rejects only that request and keeps the connection usable', async () => {
  const sent=[];
  const rpc=new RpcClient({send:async frame=>{sent.push(JSON.parse(frame));}});
  const slow=rpc.request('slowRead',{},undefined,20,false);
  await assert.rejects(slow,/请求超时/);
  assert.ok(!sent.some(frame=>frame._tag==='Interrupt'));
  const next=rpc.request('nextRead',{});
  rpc.receive(JSON.stringify({_tag:'Exit',requestId:'2',exit:{_tag:'Success',value:{ok:true}}}));
  assert.deepEqual(await next,{ok:true});
  rpc.fail('done');
});

test('visible fork items keep inherited visibility across later item events',()=>{
 const state=new ThreadState('child');
 state.apply({kind:'snapshot',snapshotSequence:1,projection:{thread:{id:'child'},messages:[],
  visibleTurnItems:[{position:0,visibility:'inherited',sourceThreadId:'parent',
   item:{id:'secret',type:'secret_request',secretStatus:'pending',label:'Key',reason:'Need it'}}],turnItems:[]}});
 assert.equal(state.items[0].visibility,'inherited');assert.equal(state.items[0].sourceThreadId,'parent');
 state.apply({kind:'event',sequence:2,event:{threadId:'child',type:'turn-item.updated',
  payload:{id:'secret',type:'secret_request',secretStatus:'saved',label:'Key',reason:'Need it'}}});
 assert.equal(state.items[0].visibility,'inherited');assert.equal(state.items[0].sourceThreadId,'parent');
});

test('a cancelled queued run does not overwrite the active run status notice',()=>{
 const state=new ThreadState('t');
 state.apply({kind:'snapshot',snapshotSequence:1,projection:{thread:{id:'t'},messages:[],runs:[
  {id:'active',status:'running'},{id:'queued',status:'queued',queuePosition:1}]}});
 state.apply({kind:'event',sequence:2,event:{threadId:'t',type:'run.updated',
  payload:{id:'queued',status:'cancelled'}}});
 assert.equal(state.notices,'任务状态：running');
});

test('empty continuation messages are hidden but attachment-only messages remain',()=>{
 const state=new ThreadState('t');
 state.apply({kind:'snapshot',snapshotSequence:1,projection:{thread:{id:'t'},messages:[
  {id:'empty',threadId:'t',role:'user',text:'',streaming:false},
  {id:'files',threadId:'t',role:'user',text:'',streaming:false,
   attachments:[{type:'file',id:'f',name:'a.txt',mimeType:'text/plain',sizeBytes:1}]}]}});
 assert.deepEqual(state.messages.map(message=>message.id),['files']);
});

test('user message attachment names survive the turn-item projection update',()=>{
 const state=new ThreadState('t');
 state.apply({kind:'snapshot',snapshotSequence:1,projection:{thread:{id:'t'},messages:[
  {id:'u',threadId:'t',role:'user',text:'attached',streaming:false,
   attachments:[{type:'image',id:'i',name:'pixel.png',mimeType:'image/png',sizeBytes:1}]}],
  turnItems:[{id:'tu',type:'user_message',messageId:'u',text:'attached',status:'completed',
   attachments:[{type:'image',id:'i',name:'pixel.png',mimeType:'image/png',sizeBytes:1}]}]}});
 assert.deepEqual(state.messages[0].attachmentNames,['pixel.png']);
});

test('nonfatal stream first-frame timeout interrupts only its subscription and keeps other RPCs alive',async()=>{
 const {rpc,sent}=setup();const received=[];
 const pending=rpc.request('subscribeTerminalMetadata',{},v=>received.push(v),1,false);
 await assert.rejects(pending,/超时/);
 const id=sent[0].id;
 assert.deepEqual(sent[1],{_tag:'Interrupt',requestId:id});
 rpc.receive(JSON.stringify({_tag:'Chunk',requestId:id,values:[{type:'snapshot',terminals:[]}]}));
 assert.equal(received.length,0);
 const next=rpc.request('server.getConfig',{});const request=sent.at(-1);
 rpc.receive(JSON.stringify({_tag:'Exit',requestId:request.id,exit:{_tag:'Success',value:{ok:true}}}));
 assert.deepEqual(await next,{ok:true});
 assert.equal(sent.some(x=>x.tag==='terminal.close'),false);
});

test('ThreadState parses projection.checkpoints, updates on checkpoint.captured, and preserves message runId', () => {
  const state = new ThreadState('thread-cp');
  state.apply({
    kind: 'snapshot',
    snapshotSequence: 1,
    projection: {
      thread: { id: 'thread-cp' },
      messages: [
        { id: 'u1', threadId: 'thread-cp', role: 'user', text: 'fix', streaming: false, runId: 'run-1' },
        { id: 'a1', threadId: 'thread-cp', role: 'assistant', text: 'done', streaming: false, runId: 'run-1' }
      ],
      checkpoints: [
        { id: 'cp-1', runId: 'run-1', status: 'ready', files: [{ path: 'a.ts', kind: 'modified', additions: 5, deletions: 2 }] }
      ]
    }
  });
  assert.equal(state.messages[0].runId, 'run-1');
  assert.equal(state.messages[1].runId, 'run-1');
  assert.equal(state.checkpoints.length, 1);
  assert.equal(state.checkpoints[0].id, 'cp-1');

  state.apply({
    kind: 'event',
    sequence: 2,
    event: {
      threadId: 'thread-cp',
      type: 'checkpoint.captured',
      payload: { id: 'cp-2', runId: 'run-2', status: 'ready', files: [] }
    }
  });
  assert.equal(state.checkpoints.length, 2);
  assert.equal(state.checkpoints[1].id, 'cp-2');
});

test('ThreadState derives ordered visible messages, filters hidden wakes, and prepends older history', async () => {
  const state = new ThreadState('t-ord');
  state.apply({
    kind: 'snapshot',
    snapshotSequence: 10,
    historyCursor: '40',
    hasMoreHistory: true,
    projection: {
      thread: { id: 't-ord', title: 'Order Test', modelSelection: { provider: 'codex', model: 'm' } },
      messages: [
        { id: 'u1', role: 'user', text: 'turn 1', createdAt: '2026-01-01T00:01:00.000Z', runId: 'r1' },
        { id: 'a1', role: 'assistant', text: 'ans 1', createdAt: '2026-01-01T00:01:05.000Z', runId: 'r1' },
        { id: 'u2', role: 'user', text: 'turn 2', createdAt: '2026-01-01T00:02:00.000Z', runId: 'r2' },
        { id: 'a2', role: 'assistant', text: 'ans 2', createdAt: '2026-01-01T00:02:05.000Z', runId: 'r2' },
        { id: 'wake-1', role: 'user', createdBy: 'agent', creationSource: 'provider', notification: { kind: 'background_task' }, text: 'Background task completed.\nTask ID: bg-1', createdAt: '2026-01-01T00:00:30.000Z', runId: 'r0' }
      ],
      visibleTurnItems: [
        { id: 'item-u1', type: 'user_message', messageId: 'u1', role: 'user', text: 'turn 1', runId: 'r1' },
        { id: 'tool-1', type: 'tool_call', title: 'Read', status: 'completed', runId: 'r1' },
        { id: 'item-a1', type: 'assistant_message', messageId: 'a1', role: 'assistant', text: 'ans 1', runId: 'r1' },
        { id: 'item-u2', type: 'user_message', messageId: 'u2', role: 'user', text: 'turn 2', runId: 'r2' },
        { id: 'item-a2', type: 'assistant_message', messageId: 'a2', role: 'assistant', text: 'ans 2', runId: 'r2' }
      ]
    }
  });

  assert.equal(state.historyCursor, '40');
  assert.equal(state.hasMoreHistory, true);
  assert.deepEqual(state.messages.map((m) => m.id), ['u1', 'a1', 'u2', 'a2']);
  assert.equal(state.messages[0].timestamp, '2026-01-01T00:01:00.000Z');

  // Hidden wake arriving as live message.updated or turn-item.updated event is excluded
  state.apply({
    kind: 'event',
    sequence: 11,
    event: {
      threadId: 't-ord',
      type: 'message.updated',
      payload: {
        id: 'wake-live',
        threadId: 't-ord',
        role: 'user',
        streaming: false,
        createdBy: 'agent',
        creationSource: 'provider',
        notification: { kind: 'background_task' },
        text: 'Background task completed.\nLive wake',
        runId: 'r2'
      }
    }
  });
  state.apply({
    kind: 'event',
    sequence: 12,
    event: {
      threadId: 't-ord',
      type: 'turn-item.updated',
      payload: {
        id: 'item-wake-live',
        type: 'user_message',
        messageId: 'wake-item-live',
        createdBy: 'agent',
        creationSource: 'provider',
        notification: { kind: 'background_task' },
        text: 'Background task completed.',
        runId: 'r2'
      }
    }
  });
  assert.equal(state.messages.some((m) => m.id === 'wake-live' || m.id === 'wake-item-live'), false);

  // Older history prepends before existing items/messages rather than appending
  state.prependHistory([
    { id: 'item-u0', type: 'user_message', messageId: 'u0', text: 'turn 0', createdAt: '2026-01-01T00:00:00.000Z', runId: 'r0' },
    { id: 'item-a0', type: 'assistant_message', messageId: 'a0', text: 'ans 0', createdAt: '2026-01-01T00:00:05.000Z', runId: 'r0' }
  ]);
  assert.deepEqual(state.items.map((item) => item.id), ['item-u0', 'item-a0', 'item-u1', 'tool-1', 'item-a1', 'item-u2', 'item-a2', 'item-wake-live']);
  assert.deepEqual(state.messages.map((m) => m.id), ['u0', 'a0', 'u1', 'a1', 'u2', 'a2']);
});

test('inlineSpans strips backticks for code nested inside bold and keeps bold styling', async () => {
  const { markdownUrl } = await import('./load-core.mjs');
  const { inlineSpans } = await import(markdownUrl);
  const spans = inlineSpans('**`ca02`** and **T3 `v0.1.1`** and [`/Users/a`](file:///Users/a)');
  const codeSpans = spans.filter((span) => span.kind === 'code');
  assert.deepEqual(codeSpans.map((span) => span.text), ['ca02', 'v0.1.1']);
  assert.equal(codeSpans.every((span) => span.bold === true), true);
  const linkSpan = spans.find((span) => span.kind === 'link');
  assert.equal(linkSpan?.text, '/Users/a');
  assert.equal(spans.some((span) => span.text.includes('`')), false);
});

test('socketUrl enables frameParts=1 and ThreadState restores deduped bodies, tolerates unknown kinds, and supports incremental resume', () => {
  const wsUrl = new URL(socketUrl('https://test', 'tok'));
  assert.equal(wsUrl.searchParams.get('frameParts'), '1');

  const state = new ThreadState('t-dedup');
  state.apply({
    kind: 'snapshot',
    snapshotSequence: 20,
    projection: {
      thread: { id: 't-dedup' },
      messages: [
        { id: 'u1', role: 'user', text: 'Full user prompt', streaming: false, runId: 'r1' },
        { id: 'a1', role: 'assistant', text: 'Full assistant answer', streaming: false, runId: 'r1' }
      ],
      checkpoints: [
        { id: 'cp-1', runId: 'r1', files: [{ path: 'a.ts', kind: 'modified' }] }
      ],
      subagents: [
        { id: 'sub-1', runId: 'r1', prompt: 'Sub prompt', result: 'Sub result', status: 'completed' }
      ],
      visibleTurnItems: [
        { id: 'i-u1', type: 'user_message', messageId: 'u1', text: '', textOmitted: true, runId: 'r1' },
        { id: 'i-a1', type: 'assistant_message', messageId: 'a1', text: '', bodyDeduped: true, runId: 'r1' },
        { id: 'i-cp', type: 'checkpoint', checkpointId: 'cp-1', files: [], filesOmitted: true, runId: 'r1' },
        { id: 'i-sub', type: 'subagent', subagentId: 'sub-1', prompt: '', promptOmitted: true, result: '', resultOmitted: true, runId: 'r1' }
      ]
    }
  });
  assert.equal(state.messages.find((m) => m.id === 'u1')?.text, 'Full user prompt');
  assert.equal(state.messages.find((m) => m.id === 'a1')?.text, 'Full assistant answer');
  assert.equal(state.items.find((i) => i.id === 'i-cp')?.files.length, 1);
  assert.equal(state.items.find((i) => i.id === 'i-sub')?.prompt, 'Sub prompt');
  assert.equal(state.items.find((i) => i.id === 'i-sub')?.result, 'Sub result');

  // Unknown future stream envelope kind is ignored without throwing
  state.apply({ kind: 'heartbeat_hint', snapshotSequence: 21 });
  assert.equal(state.cursor, 20);

  // Reconnect reset keeps resumeCursor while allowing incremental synchronized or lower-sequence fallback snapshot
  state.resetForReconnect();
  assert.equal(state.cursor, -1);
  assert.equal(state.resumeCursor, 20);
  state.apply({ kind: 'synchronized' });
  assert.equal(state.cursor, 20);

  // Lower-sequence fallback snapshot after server restart is accepted after resetForReconnect
  state.resetForReconnect();
  state.apply({
    kind: 'snapshot',
    snapshotSequence: 3,
    projection: { thread: { id: 't-dedup' }, messages: [{ id: 'u2', threadId: 't-dedup', role: 'user', text: 'restarted', streaming: false }] }
  });
  assert.equal(state.cursor, 3);
  assert.equal(state.resumeCursor, 3);
  assert.deepEqual(state.messages.map((m) => m.id), ['u2']);
});
