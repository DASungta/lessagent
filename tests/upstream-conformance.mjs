// Optional: run against a checkout of the pinned upstream with Effect 4.1.3 installed.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { bootstrapForm, createThread, RpcClient, sendMessage } from '../entry/src/main/ets/protocol/Wire.ts';

import { coreUrl } from './load-core.mjs';
const { respondCommand, stopCommand, secretAnswer, uploadTarget } = await import(coreUrl);

const source = process.env.T3_SOURCE;
assert.ok(source, 'Set T3_SOURCE to the upstream checkout (see docs/phase-one.md)');
assert.equal(execFileSync('git', ['-C', source, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim(),
  'ad1b1365999c92c3fc7a054e7f3af84623f74fee');
const load = (path) => import(pathToFileURL(resolve(source, path)).href);
const [Effect, Schema, Queue, Stream, Rpc, RpcGroup, RpcServer, Serialization, commands, auth] = await Promise.all([
  ...['Effect', 'Schema', 'Queue', 'Stream', 'rpc/Rpc', 'rpc/RpcGroup', 'rpc/RpcServer', 'rpc/RpcSerialization']
    .map((name) => load('node_modules/effect/dist/' + name + '.js')),
  load('packages/contracts/src/orchestrationV2.ts'), load('packages/contracts/src/auth.ts')
]);
const decodeCommand = Schema.decodeUnknownSync(Schema.toCodecJson(commands.OrchestrationV2Command));
const thread = createThread('cmd-test', 'thread-test', 'project-test', 'codex', 'test-model');
const message = sendMessage('cmd-test-2', 'thread-test', 'message-test', 'hello');
decodeCommand(thread);
decodeCommand(message);
const assets = await load('packages/contracts/src/assets.ts');
Schema.decodeUnknownSync(assets.AttachmentCreateUploadUrlInput)({type:'file',name:'test.bin',mimeType:'application/octet-stream',sizeBytes:3});
const target = uploadTarget({relativeUrl:'/api/attachments/upload/signed.token',attachmentId:'pending-test',expiresAt:Date.now()+60000},3,'test.bin');
decodeCommand({...message,attachments:[target.attachment]});
Schema.decodeUnknownSync(commands.OrchestrationV2SubscribeThreadInput)({threadId:'thread-test'});
decodeCommand(stopCommand('stop', 'thread-test'));
decodeCommand(respondCommand('approve', 'thread-test', 'request-test', 'accept', {}));
decodeCommand(respondCommand('answer', 'thread-test', 'request-test', '', { language: 'ArkTS' }));
const secrets = await load('packages/contracts/src/secretRequest.ts');
Schema.decodeUnknownSync(secrets.SecretRequestAnswerInput)(secretAnswer('thread-test', 'item-test', 'synthetic', false));
Schema.decodeUnknownSync(commands.OrchestrationV2SubscribeShellInput)({});
Schema.decodeUnknownSync(Schema.toCodecJson(auth.AuthTokenExchangeRequest))(
  Object.fromEntries(new URLSearchParams(bootstrapForm('synthetic-test-credential'))));
console.log('Pinned upstream command and OAuth schemas: PASS');

// Use the real serialized Effect RPC server, including its flow control, rather than an echo mock.
const group = RpcGroup.make(
  Rpc.make('test.echo', { payload: Schema.Struct({ text: Schema.String }), success: Schema.String }),
  Rpc.make('test.stream', { payload: Schema.Struct({}), success: Schema.String, stream: true }),
  Rpc.make('orchestration.dispatchCommand', {
    payload: commands.OrchestrationV2Command, success: commands.OrchestrationV2DispatchCommandResult
  })
);
const handlers = group.toLayer({
  'test.echo': ({ text }) => Effect.succeed(text),
  'test.stream': () => Stream.fromIterable(['你', '好', '👋']),
  'orchestration.dispatchCommand': () => Effect.succeed({ sequence: 1 })
});
await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
  const incoming = yield* Queue.make();
  const disconnects = yield* Queue.make();
  const parser = Serialization.json.makeUnsafe();
  const sent = [];
  const client = new RpcClient({
    send: async (frame) => {
      sent.push(JSON.parse(frame));
      for (const value of parser.decode(frame)) await Effect.runPromise(Queue.offer(incoming, value));
    }
  });
  const protocol = {
    run: (receive) => Effect.forever(Effect.flatMap(Queue.take(incoming), (frame) => receive(0, frame))),
    disconnects,
    send: (_id, response) => Effect.sync(() => client.receive(parser.encode(response))),
    end: () => Effect.void,
    clientIds: Effect.succeed(new Set([0])),
    initialMessage: Effect.succeedNone,
    supportsAck: true, supportsTransferables: false, supportsSpanPropagation: false, supportsNotifications: false,
    codecFor: Serialization.json.codecFor
  };
  yield* Effect.forkScoped(RpcServer.make(group).pipe(
    Effect.provideService(RpcServer.Protocol, protocol), Effect.provide(handlers)));
  yield* Effect.promise(async () => {
    assert.equal(await client.request('test.echo', { text: 'Harmony 中文' }), 'Harmony 中文');
    const values = [];
    await client.request('test.stream', {}, (value) => values.push(value));
    assert.deepEqual(values, ['你', '好', '👋']);
    assert.ok(sent.some((frame) => frame._tag === 'Ack'));
    assert.deepEqual(await client.request('orchestration.dispatchCommand', thread), { sequence: 1 });
    await assert.rejects(client.request('orchestration.dispatchCommand', { type: 'invalid' }));
    client.fail('test finished');
  });
})).pipe(Effect.timeout('5 seconds')));
console.log('Effect 4.1.3 serialized RPC (request, stream ACK, command, rejection): PASS');
