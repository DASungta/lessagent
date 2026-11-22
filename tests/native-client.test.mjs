// Execute the actual NetworkKit adapter with a small fake kit; HAP build checks the SDK types.
import { coreUrl, projectsUrl, composerUrl, r4Url, filesUrl, r5Url, floatingStatusUrl, markdownUrl, threadRepositoriesUrl, linkedThreadUrl } from './load-core.mjs';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import test from 'node:test';
const require = createRequire(import.meta.url);
const deveco = process.env.DEVECO_HOME || '/Applications/DevEco-Studio.app/Contents';
const ts = require(deveco + '/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const original = await readFile(new URL('../entry/src/main/ets/services/T3Client.ets', import.meta.url), 'utf8');
const wire = new URL('../entry/src/main/ets/protocol/Wire.ts', import.meta.url).href;
const hosts = new URL('../entry/src/main/ets/protocol/Hosts.ts', import.meta.url).href;
const cloud = 'data:text/javascript;base64,' + Buffer.from(ts.transpileModule(
  (await readFile(new URL('../entry/src/main/ets/protocol/Cloud.ts', import.meta.url), 'utf8'))
    .replace("import { url } from '@kit.ArkTS';",
      'const url = { URL: class extends URL { get params() { return this.searchParams; } }, URLParams: URLSearchParams };')
    .replace("'./Wire'", JSON.stringify(wire)),
  { compilerOptions: { module: ts.ModuleKind.ES2022, target: ts.ScriptTarget.ES2022 } }
).outputText).toString('base64');
const devicePreviewUrl = 'data:text/javascript;base64,' + Buffer.from(ts.transpileModule(await readFile(new URL('../entry/src/main/ets/protocol/DevicePreview.ts', import.meta.url),'utf8'), {compilerOptions:{module:ts.ModuleKind.ES2022,target:ts.ScriptTarget.ES2022}}).outputText).toString('base64');
const markdownMediaCacheUrl = 'data:text/javascript;base64,' + Buffer.from(ts.transpileModule(
  (await readFile(new URL('../entry/src/main/ets/services/MarkdownMediaCache.ets', import.meta.url), 'utf8'))
    .replace("'../protocol/Markdown'", JSON.stringify(markdownUrl)),
  { compilerOptions: { module: ts.ModuleKind.ES2022, target: ts.ScriptTarget.ES2022 } }
).outputText).toString('base64');
let moduleId = 0;
async function setup(options = {}) {
  const requests = [];
  const socketConnects = [];
  const frames = [];
  let destroyed = 0;
  let socket;
  const kit = {
    util: { generateRandomUUID: () => 'test-' + Math.random().toString(36).slice(2) },
    http: {
      RequestMethod: { GET: 'GET', POST: 'POST' }, HttpDataType: { STRING: 'string' },
      createHttp: () => ({
        request: async (url, args) => {
          requests.push({ url, args });
          if (options.httpError && (!options.httpErrorPath || url.includes(options.httpErrorPath))) {
            throw Object.assign(new Error('network error'), options.httpError);
          }
          if (args.method === 'POST' && args.extraData === '') {
            throw Object.assign(new Error('Invalid extraData'), { code: 401 });
          }
          let value;
          let status = 200;
          if (url.includes('/api/attachments/upload/')) { if (options.waitUpload) await options.waitUpload(); return {responseCode:options.uploadStatus ?? 204,result:''}; }
          if (url.endsWith('/.well-known/t3/environment')) {
            if (options.waitMetadata) await options.waitMetadata;
            value = {
              environmentId: options.environmentId ?? 'env',
              label: 'Test',
              serverVersion: 'test',
              orchestrationProtocolVersion: options.protocol ?? 2,
              ...(options.descriptorCapabilities ? { capabilities: options.descriptorCapabilities } : {})
            };
          } else if (url.endsWith('/api/auth/session')) {
            if (options.onSessionRequest) {
              const custom = await options.onSessionRequest(url, args);
              if (custom) return { responseCode: custom.status ?? 200, result: JSON.stringify(custom.value ?? {}) };
            }
            const state = options.sessionState ?? {authenticated:true,permissions:['access:read']};
            if (options.waitAccess) await (typeof options.waitAccess === 'function' ? options.waitAccess() : options.waitAccess);
            value = state;
          } else if (url.endsWith('/api/auth/pairing-token')) {
            value = {credential:'SYNTHETIC_PEER_CODE'};
          } else if (url.endsWith('/api/auth/connect-devices/approve')) {
            value = { approved: true };
          } else if (url.endsWith('/api/auth/pairing-links/revoke') ||
            url.endsWith('/api/auth/connect-devices/revoke')) {
            value = { revoked: true };
          } else if (url.endsWith('/oauth/token')) {
            if (options.onTokenRequest) {
              const custom = await options.onTokenRequest(url, args);
              if (custom) return { responseCode: custom.status ?? 200, result: JSON.stringify(custom.value ?? {}) };
            }
            if (options.authError) status = 401;
            value = { access_token: 'SYNTHETIC_TOKEN', token_type: 'Bearer', expires_in: 3600 };
          } else if (url.includes('/api/orchestration/threads/') && url.includes('/history')) {
            value = options.historyResponse ?? { items: [], messages: [], hasMore: false, oldestCursor: null };
          } else if (url.endsWith('/api/pull-requests/diff')) {
            if (options.onDiffRequest) {
              const custom = await options.onDiffRequest(url, args);
              if (custom) return { responseCode: custom.status ?? 200, result: JSON.stringify(custom.value ?? {}) };
            }
            value = { diff: '' };
          } else {
            if (options.onTicketRequest) {
              const custom = await options.onTicketRequest(url, args);
              if (custom) return { responseCode: custom.status ?? 200, result: JSON.stringify(custom.value ?? {}) };
            }
            if (options.ticket404 && url.endsWith('/rpc')) status = 404;
            if (options.transientRpcStatus && url.endsWith('/rpc')) status = options.transientRpcStatus;
            value = { ticket: 'SYNTHETIC_TICKET' };
          }
          return { responseCode: status, result: JSON.stringify(value) };
        },
        destroy: () => destroyed++
      })
    },
    webSocket: {
      createWebSocket: () => {
        const listeners = {};
        const currentSocket = {
          on: (type, callback) => listeners[type] = callback,
          close: async () => true,
          connect: async (url, connectOptions) => {
            socketConnects.push({ url, connectOptions });
            if (options.socketError) throw new Error('transport echoed ' + url);
            if (!options.neverOpen) {
              if (options.openDelayMs) setTimeout(() => listeners.open?.({ code: 0 }, {}), options.openDelayMs);
              else queueMicrotask(() => listeners.open?.({ code: 0 }, {}));
            }
            return true;
          },
          emitOpen: (err = { code: 0 }) => listeners.open?.(err, {}),
          emitError: (err = { code: 2300056 }) => listeners.error?.(err),
          emitClose: (value = { code: 1006, reason: 'abnormal' }) => listeners.close?.({ code: 0 }, value),
          emit: (value) => listeners.message({ code: 0 }, JSON.stringify(value)),
          send: async (frame) => {
            const value = JSON.parse(frame);
            frames.push(value);
            options.onFrame?.(value);
            if (value._tag === 'Request') queueMicrotask(() => {
              const configPayload = {
                environment: { environmentId: options.mismatch ? 'other' : (options.environmentId ?? 'env'),
                  capabilities: options.capabilities ?? {peerLinks:options.peerLinks===true},
                  ...(options.platform ? {platform: options.platform} : {}) },
                providers: options.providers ?? [],
                ...(options.secretRequestReferences ? {secretRequestReferences:true} : {}),
                settings: options.settings ?? {linkedEnvironmentsEnabled:options.peerLinks===true},
                ...(options.newProjectsRoot ? {newProjectsRoot: options.newProjectsRoot} : {}),
                ...(options.scratchWorkspaceRoot ? {scratchWorkspaceRoot: options.scratchWorkspaceRoot} : {})
              };
              if (options.onRequest) {
                const custom = options.onRequest(value, currentSocket);
                if (custom === 'handled') return;
              }
              if (value.tag === 'subscribeServerConfig') {
                if (options.rejectSubscribeConfig) {
                  currentSocket.emit({ _tag: 'Exit', requestId: value.id, exit: { _tag: 'Failure', cause: { _tag: 'Fail', error: { message: 'unknown method' } } } });
                } else {
                  currentSocket.emit({ _tag: 'Chunk', requestId: value.id, values: [{ version: 1, type: 'snapshot', config: configPayload }] });
                }
              } else if (value.tag === 'server.probe') {
                if (options.dropProbe) return;
                if (options.rejectProbeKnown) {
                  currentSocket.emit({ _tag: 'Exit', requestId: value.id, exit: { _tag: 'Failure', cause: { _tag: 'Fail', error: { message: 'unknown method' } } } });
                } else {
                  currentSocket.emit({ _tag: 'Exit', requestId: value.id, exit: { _tag: 'Success', value: {} } });
                }
              } else if (value.tag === 'orchestration.subscribeShell') {
                if (!options.delayShellSnapshot) {
                  currentSocket.emit({ _tag: 'Chunk', requestId: value.id, values: [{ kind: 'snapshot', snapshot: {
                    snapshotSequence: 9,
                    projects: options.shellProjects ?? [],
                    threads: options.shellThreads ?? []
                  } }] });
                }
              } else if (value.tag === 'orchestration.subscribeThread') {
                if (typeof options.onSubscribeThread === 'function') {
                  options.onSubscribeThread(value, currentSocket);
                } else if (options.rejectThread) {
                  currentSocket.emit({ _tag: 'Exit', requestId: value.id, exit: { _tag: 'Failure', cause: { _tag: 'Fail', error: { message: 'not found' } } } });
                } else {
                  currentSocket.emit({ _tag: 'Chunk', requestId: value.id, values: [{ kind: 'snapshot', snapshotSequence: 10,
                    projection: { thread: { id: value.payload.threadId }, messages: options.messages ?? [] } }] });
                }
              } else if (value.tag === 'git.runStackedAction') {
                currentSocket.emit({ _tag: 'Chunk', requestId: value.id, values: [
                  { kind: 'phase_started', phase: 'commit', label: 'Committing...' },
                  { kind: 'action_finished', result: { action: 'commit',
                    branch: { status: 'skipped_not_requested' },
                    commit: { status: 'created', commitSha: 'abc1234' },
                    push: { status: 'skipped_not_requested' },
                    pr: { status: 'skipped_not_requested' }, toast: { title: 'Committed' } } }
                ] });
                currentSocket.emit({ _tag: 'Exit', requestId: value.id, exit: { _tag: 'Success', value: null } });
              } else {
                if (options.dropMutation && value.tag !== 'server.getConfig') return;
                if (options.secretFailureReason && value.tag === 'secrets.answerRequest') {
                  currentSocket.emit({ _tag: 'Exit', requestId: value.id, exit: { _tag: 'Failure', cause: { _id: 'Cause', reasons: [{ _tag: 'Fail', error: { _tag: 'SecretRequestError', reason: options.secretFailureReason } }] } } });
                  return;
                }
                const result = value.tag === 'assets.createUrl' ? {relativeUrl:'/api/assets/synthetic',expiresAt:Date.now()+120000,imageDimensions:{width:1260,height:2720}} : value.tag === 'orchestration.launchThread' ? {threadId: options.launchIdentity ?? value.payload.threadId, projection:{},resumed:false} : value.tag === 'attachments.createUploadUrl' ? {attachmentId:'pending-test',relativeUrl:options.uploadPath ?? '/api/attachments/upload/signed.token',expiresAt:Date.now()+60000} : value.tag === 'server.getConfig' ? configPayload : value.tag === 'peerLinks.list' ? {links:[{environmentId:'peer',label:'Synthetic peer',status:'reachable',expiresAt:new Date(Date.now()+86400000).toISOString(),lastError:null}]} : { sequence: 11 };
                currentSocket.emit({ _tag: 'Exit', requestId: value.id, exit: { _tag: 'Success', value: result } });
              }
            });
            return true;
          }
        };
        socket = currentSocket;
        return currentSocket;
      }
    },
    dpopSigner: options.dpopSigner
  };
  globalThis.__nativeKit = kit;
  const source = original
    .replace("import { http, webSocket } from '@kit.NetworkKit';", 'const { http, webSocket } = globalThis.__nativeKit;')
    .replace("import { util } from '@kit.ArkTS';", 'const { util } = globalThis.__nativeKit;')
    .replace("import { BusinessError } from '@kit.BasicServicesKit';", '')
    .replace("import { dpopSigner } from './Dpop';", 'const { dpopSigner } = globalThis.__nativeKit;')
    .replace("'../protocol/DevicePreview'", JSON.stringify(devicePreviewUrl))
    .replace("'../protocol/Wire'", JSON.stringify(wire))
    .replace("'../protocol/Hosts'", JSON.stringify(hosts))
    .replace("'../protocol/Core'", JSON.stringify(coreUrl))
    .replace("'../protocol/Cloud'", JSON.stringify(cloud))
    .replace("'../protocol/Projects'", JSON.stringify(projectsUrl))
    .replace("'../protocol/ThreadRepositories'", JSON.stringify(threadRepositoriesUrl))
    .replace("'../protocol/LinkedThread'", JSON.stringify(linkedThreadUrl))
    .replace("'../protocol/Composer'", JSON.stringify(composerUrl))
    .replace("'../protocol/FloatingStatus'", JSON.stringify(floatingStatusUrl))
    .replace("'../protocol/Files'", JSON.stringify(filesUrl))
    .replace("'../protocol/Markdown'", JSON.stringify(markdownUrl))
    .replace("'./MarkdownMediaCache'", JSON.stringify(markdownMediaCacheUrl))
    .replace("'../protocol/R5'", JSON.stringify(r5Url));
  const sourceWithR4 = source.replace("'../protocol/R4'", JSON.stringify(r4Url));
  const compiled = ts.transpileModule(sourceWithR4, { compilerOptions: { module: ts.ModuleKind.ES2022, target: ts.ScriptTarget.ES2022 } }).outputText;
  const { T3Client } = await import('data:text/javascript;base64,' + Buffer.from(compiled + '\n// instance ' + ++moduleId).toString('base64'));
  const client = new T3Client();
  client.recoveryStore = options.recoveryStore;
  return { client, requests, socketConnects, frames, destroyed: () => destroyed, socket: () => socket };
}

test('re-pair replaces expired credentials only on success and never replays an unknown message',async()=>{
 const previous={base:'https://test',environmentId:'env',token:'EXPIRED_SYNTHETIC',expiresAt:1};
 const recovery={base:previous.base,environmentId:'env',threadId:'t',pendingId:'unconfirmed',pendingKind:'message'};
 for(const authError of [true,false]){
  let stored=structuredClone(previous),writes=0;
  const {client,frames}=await setup({authError,recoveryStore:{async load(){return structuredClone(recovery)},async save(){throw Error('unknown recovery must not be rewritten')}}});
  client.expectedEnvironmentId='env';client.store={async load(){return structuredClone(stored)},async save(value){stored=structuredClone(value);writes++}};
  try{
   await client.connect(previous.base,'replacement-test-code');await new Promise(setImmediate);
   assert.equal(client.ready,!authError);assert.equal(writes,authError?0:1);
   if(authError)assert.deepEqual(stored,previous);
   else {assert.equal(stored.token,'SYNTHETIC_TOKEN');assert.deepEqual(client.recovery,recovery)}
   assert.equal(frames.some(frame=>frame.tag==='orchestration.dispatchCommand'),false);
  }finally{client.disconnect()}
 }
});

test('native adapter runs auth, ticket, identity check, create, subscribe, send and reconnect', async () => {
  const { client, requests, frames, destroyed } = await setup();
  try {
    await client.connect('https://test', 'synthetic credential');
    assert.equal(client.ready, true);
    await new Promise(setImmediate);
    assert.equal(requests.length, 4);
    assert.equal(destroyed(), 4);
    assert.equal(new URL(requests[3].url).pathname, '/api/auth/session');
    assert.equal(requests[3].args.method, 'GET');
    assert.equal(new URLSearchParams(requests[1].args.extraData).get('subject_token'), 'synthetic credential');
    assert.equal(requests[2].args.header.Authorization, 'Bearer SYNTHETIC_TOKEN');
    assert.equal(requests[1].args.maxRedirects, 0);
    const threadId = await client.newThread('project', 'codex', 'model');
    await client.watch(threadId);
    await new Promise(setImmediate);
    assert.equal(client.thread.cursor, 10);
    assert.ok(frames.some((frame) => frame._tag === 'Ack'));
    await client.send('hello');
    assert.ok(frames.some((frame) => frame.payload?.type === 'message.dispatch'));
    await client.watch('another-thread');
    await new Promise(setImmediate);
    assert.equal(client.thread.threadId, 'another-thread');
    assert.ok(frames.some(frame => frame._tag === 'Interrupt'));
    client.disconnect();
    await client.connect('https://test', 'new synthetic credential');
    await client.watch(threadId);
    await new Promise(setImmediate);
    assert.equal(client.thread.threadId, threadId);
    assert.equal(client.thread.cursor, 10);
  } finally { client.disconnect(); }
});

test('native config exposes R3 capabilities, paths, platform, snooze presets and source-control offers only when advertised', async () => {
  const { client } = await setup({
    capabilities: { threadSettlement: true, threadSnooze: true, threadPinning: true,
      threadPinReorder: true, threadActiveReorder: true, projectOrganization: true,
      threadTitleRegeneration: true, threadProjectFromScratch: true },
    settings: { addProjectBaseDirectory: '/work', ghqCloneLayout: true,
      offeredSourceControlProviders: { github: true, gitlab: false },
      snoozePresets: [{ kind: 'after', minutes: 45 }] },
    platform: { os: 'darwin' },
    newProjectsRoot: '/work/new', scratchWorkspaceRoot: '/work/scratch'
  });
  try {
    await client.connect('https://test', 'synthetic');
    assert.equal(client.supports('threadSnooze'), true);
    assert.equal(client.supports('threadForceStop'), false);
    assert.equal(client.addProjectBaseDirectory, '/work');
    assert.equal(client.ghqCloneLayout, true);
    assert.equal(client.newProjectsRoot, '/work/new');
    assert.equal(client.scratchWorkspaceRoot, '/work/scratch');
    assert.equal(client.platform, 'darwin');
    assert.equal(client.offeredSourceControlProviders.github, true);
    assert.equal(client.offeredSourceControlProviders.gitlab, false);
    assert.equal(client.snoozePresets.length, 1);
    assert.equal(client.snoozePresets[0].minutes, 45);
  } finally { client.disconnect(); }
});

test('cloud transport bypasses bearer exchange and keeps HTTP/RPC authorization in the relay adapter', async () => {
  const { client, requests, frames } = await setup();
  const cloudRequests = [];
  const transport = {
    environmentId: 'env', label: 'Cloud',
    async endpoint() {
      return { httpBaseUrl: 'https://managed.example.test', wsBaseUrl: 'wss://managed.example.test/',
        providerKind: 'cloudflare_tunnel' };
    },
    async socketUrl() { return 'wss://managed.example.test/ws?wsTicket=SYNTHETIC&dpop=SYNTHETIC'; },
    async requestJson(path, method, body) {
      cloudRequests.push({ path, method, body });
      if (path === '/api/auth/session') return { authenticated: true, permissions: ['access:read'] };
      throw Error('unexpected cloud path ' + path);
    },
    async renew() { return Date.now() + 600000; },
    async reset() {}
  };
  client.expectedEnvironmentId = 'env';
  client.cloud = transport;
  try {
    await client.connect('https://ignored.example.test');
    assert.equal(client.ready, true);
    assert.equal(requests.length, 1);
    assert.ok(requests[0].url.endsWith('/.well-known/t3/environment'));
    await client.refreshPeerAccess();
    assert.deepEqual(cloudRequests, [
      { path: '/api/auth/session', method: 'GET', body: '' },
      { path: '/api/auth/session', method: 'GET', body: '' }
    ]);
    assert.equal(client.canManagePeerAccess(), false);
    const threadId = await client.newThread('project', 'codex', 'model');
    await client.watch(threadId);
    await new Promise(setImmediate);
    assert.ok(frames.some(frame => frame.payload?.type === 'thread.create'));
  } finally { client.disconnect(); }
});

test('device approval, denial and trusted-key revocation use their exact HTTP contracts', async () => {
  const { client, requests } = await setup();
  try {
    await client.connect('https://test', 'synthetic');
    client.authAccess = { pairingLinks: [{ id: 'link-1', createdAt: Date.now(),
      expiresAt: Date.now() + 60000, verificationCode: 'K7QM-2XFD',
      clientLabel: 'Pixel', clientOs: 'Android', clientBrowser: '' },
      { id: 'link-2', createdAt: Date.now(), expiresAt: Date.now() + 60000,
        verificationCode: 'ZZZZ-ZZZZ', clientLabel: 'Tablet', clientOs: 'Android', clientBrowser: '' }],
    devices: [] };
    await client.approveDevice('link-1');
    await client.denyDevice('link-2');
    await client.revokeDevice('thumb-a');
    const paths = requests.map(request => new URL(request.url).pathname);
    assert.ok(paths.includes('/api/auth/connect-devices/approve'));
    assert.ok(paths.includes('/api/auth/pairing-links/revoke'));
    assert.ok(paths.includes('/api/auth/connect-devices/revoke'));
    assert.equal(requests.find(request => request.url.endsWith('/approve')).args.extraData,
      JSON.stringify({ pairingLinkId: 'link-1' }));
    assert.equal(requests.find(request => request.url.endsWith('/connect-devices/revoke')).args.extraData,
      JSON.stringify({ proofKeyThumbprint: 'thumb-a' }));
  } finally { client.disconnect(); }
});

test('only a ticket 404 falls back to the bare endpoint', async () => {
  const { client, requests } = await setup({ ticket404: true });
  try {
    await client.connect('https://test', 'synthetic');
    assert.equal(client.ready, true);
    assert.ok(requests[3].url.endsWith('/api/auth/websocket-ticket'));
  } finally { client.disconnect(); }
});

test('bad credentials and incompatible versions stop before opening a socket', async () => {
  for (const options of [{ authError: true }, { protocol: 3 }]) {
    const { client, requests, socket } = await setup(options);
    await client.connect('https://test', 'synthetic');
    assert.equal(client.ready, false);
    assert.equal(socket(), undefined);
    assert.match(client.status, options.authError ? /鉴权失败/ : /不兼容/);
    assert.equal(requests.length, options.authError ? 2 : 1);
  }
});

test('socket failures cannot echo tickets into UI diagnostics', async () => {
  const { client } = await setup({ socketError: true });
  await client.connect('https://test', 'synthetic');
  assert.equal(client.ready, false);
  assert.match(client.status, /WebSocket/);
  assert.ok(!client.status.includes('SYNTHETIC_TICKET'));
});

test('identity mismatch blocks a connection', async () => {
  const { client } = await setup({ mismatch: true });
  await client.connect('https://test', 'synthetic');
  assert.equal(client.ready, false);
  assert.match(client.status, /身份不一致/);
});

test('background/disconnect during metadata lookup prevents a stale credential exchange', async () => {
  let release;
  const gate = new Promise((resolve) => { release = resolve; });
  const { client, requests, socket } = await setup({ waitMetadata: gate });
  const connecting = client.connect('https://test', 'synthetic');
  assert.equal(client.connectionPending,true);
  client.disconnect('entered background');
  release();
  await connecting;
  assert.equal(client.connectionPending,false);
  assert.equal(requests.length, 1);
  assert.equal(client.ready, false);
  assert.equal(socket(), undefined);
});

test('secure session reuse does not exchange one-time pairing again; expiry and server mismatch fail closed', async () => {
 const {client,requests}=await setup();
 let saved;
 client.store={load:async()=>saved,save:async v=>{saved=v},clear:async()=>{saved=undefined}};
 try {
  await client.connect('https://test','synthetic');assert.equal(client.ready,true);
  client.disconnect();await client.connect('https://test');assert.equal(client.ready,true);
  assert.equal(requests.filter(r=>r.url.endsWith('/oauth/token')).length,1);
  client.disconnect();await client.connect('https://other');assert.equal(client.ready,false);
  assert.match(client.status,/有效会话/);
  saved.expiresAt=0;await client.connect('https://test');assert.equal(client.ready,false);
  await client.forget();assert.equal(saved,undefined);
 }finally{client.disconnect();}
});

test('responses, secrets and stop use distinct contracts and reject stale requests', async()=>{
 const {client,frames}=await setup();
 try {
  await client.connect('https://test','synthetic');await client.watch('t');await new Promise(setImmediate);
  client.thread.requests=[{id:'r',status:'pending',responseCapability:{type:'live'}}];
  await client.respond('r','accept',{});
  client.thread.requests[0].status='resolved';await assert.rejects(client.respond('r','accept',{}),/失效/);
  client.thread.items=[{id:'s',type:'secret_request',secretStatus:'pending'}];
  await client.secret('s','SYNTHETIC_SECRET',false);await client.stop();
  const secret=frames.find(f=>f.tag==='secrets.answerRequest');
  assert.equal(secret.payload.answer.secret,'SYNTHETIC_SECRET');
  assert.ok(!frames.some(f=>f.payload?.type==='message.dispatch'));
  assert.ok(frames.some(f=>f.payload?.type==='thread.stop'));
 }finally{client.disconnect();}
});

test('unknown message submission requires a fresh snapshot before manual retry',async()=>{
 const {client}=await setup();
 try {
  await client.connect('https://test','synthetic');await client.watch('t');await new Promise(setImmediate);
  client.recovery.pendingId='lost-ack-message';client.recovery.pendingKind='message';
  await assert.rejects(client.send('retry'),/结果未知/);
  await client.watch('t');await new Promise(r=>setTimeout(r,60));
  assert.match(client.status,/结果未知/);
  await assert.rejects(client.send('retry'),/结果未知/);
  await client.acknowledgeUnknown();
  await client.send('manually checked retry');
 }finally{client.disconnect();}
});

test('snapshot confirms a lost acknowledgement by message id without resending',async()=>{
 const {client,frames}=await setup({messages:[{id:'lost-ack',threadId:'t',role:'user',text:'already accepted',streaming:false}]});
 try{
  await client.connect('https://test','synthetic');await client.watch('t');
  client.recovery.pendingId='lost-ack';client.recovery.pendingKind='message';
  await client.watch('t');await new Promise(setImmediate);
  assert.equal(client.recoveredMessageId,'lost-ack');assert.match(client.status,/已接收/);
  assert.equal(frames.filter(f=>f.payload?.type==='message.dispatch').length,0);
 }finally{client.disconnect();}
});

function memoryRecovery(initial) {
 let value=initial;
 return {load:async()=>structuredClone(value),save:async v=>{value=structuredClone(v)},clear:async()=>{value=undefined}};
}
test('process exit restores selected thread and unknown message without replay or persisted body', async()=>{
 const store=memoryRecovery();
 const first=await setup({dropMutation:true,recoveryStore:store});
 await first.client.connect('https://test','synthetic');await first.client.watch('t');await new Promise(setImmediate);
 const sending=first.client.send('PRIVATE PROMPT').catch(()=>{});
 await new Promise(setImmediate);
 const persisted=await store.load();assert.equal(persisted.pendingKind,'message');
 assert.ok(!JSON.stringify(persisted).includes('PRIVATE PROMPT'));
 first.client.disconnect();await sending;
 const next=await setup({recoveryStore:store,messages:[{id:persisted.pendingId,threadId:'t',role:'user',text:'PRIVATE PROMPT',streaming:false}]});
 try {
  await next.client.connect('https://test','synthetic');await new Promise(r=>setTimeout(r,70));
  assert.equal(next.client.thread.threadId,'t');assert.equal(next.client.recoveredMessageId,persisted.pendingId);
  assert.equal(next.frames.filter(f=>f.payload?.type==='message.dispatch').length,0);
  await assert.rejects(next.client.send('again'),/结果未知/);
  await next.client.acknowledgeUnknown();assert.equal((await store.load()).pendingId,'');
 } finally {next.client.disconnect();}
});
test('journal failure and duplicate clicks cannot send modifying frames', async()=>{
 const store=memoryRecovery();const {client,frames}=await setup({recoveryStore:store,dropMutation:true});
 try {
  await client.connect('https://test','synthetic');await client.watch('t');await new Promise(setImmediate);
  store.save=async()=>{throw Error('storage unavailable')};
  await assert.rejects(client.send('blocked'),/storage unavailable/);
  assert.equal(frames.filter(f=>f.payload?.type==='message.dispatch').length,0);
 } finally {client.disconnect();}
});
test('background returns to the same thread using reads only; explicit disconnect stays disconnected',async()=>{
 const {client,frames}=await setup({recoveryStore:memoryRecovery()});
 try {
  await client.connect('https://test','synthetic');await client.watch('t');await new Promise(setImmediate);
  client.suspend();assert.equal(client.ready,false);await client.resume();await new Promise(setImmediate);
  assert.equal(client.thread.threadId,'t');assert.equal(frames.filter(f=>f.tag==='orchestration.dispatchCommand').length,0);
  client.disconnect();await client.resume();assert.equal(client.ready,false);
 }finally{client.disconnect();}
});
test('recovery record cannot cross server identities',async()=>{
 const store=memoryRecovery({base:'https://other',environmentId:'other',threadId:'private',pendingId:'',pendingKind:''});
 const {client,frames}=await setup({recoveryStore:store});
 try {await client.connect('https://test','synthetic');assert.equal(client.ready,false);
 assert.equal(frames.filter(f=>f.tag==='orchestration.subscribeThread').length,0);
 assert.match(client.status,/身份不一致/);}finally{client.disconnect();}
});

test('double click while journal write waits sends only one command',async()=>{
 let release;const gate=new Promise(r=>release=r);const store=memoryRecovery();
 const {client,frames}=await setup({recoveryStore:store});
 try{
  await client.connect('https://test','synthetic');await client.watch('t');await new Promise(setImmediate);
  const save=store.save;store.save=async v=>{await gate;await save(v)};
  const first=client.send('one');await assert.rejects(client.send('two'),/结果未知/);
  await assert.rejects(client.connect('https://other','must-not-exchange'),/正在提交/);
  assert.equal(client.ready,true);
  release();await first;assert.equal(frames.filter(f=>f.payload?.type==='message.dispatch').length,1);
 }finally{release();client.disconnect();}
});

test('attachment sends exact bytes without bearer forwarding or redirects, and dispatches only on user send',async()=>{
 const {client,frames,requests}=await setup();
 try{
  await client.connect('https://test','synthetic');await client.watch('t');await new Promise(setImmediate);
  const bytes=new Uint8Array([1,2,3]).buffer;await client.upload('test.bin',bytes);
  const upload=requests.find(r=>r.url.includes('/api/attachments/upload/'));
  assert.equal(upload.args.extraData,bytes);assert.equal(upload.args.header.Authorization,undefined);
  assert.equal(upload.args.maxRedirects,0);assert.equal(frames.filter(f=>f.payload?.type==='message.dispatch').length,0);
  await client.send('inspect');assert.equal(frames.find(f=>f.payload?.type==='message.dispatch').payload.attachments[0].id,'pending-test');
  assert.equal(client.attachment,undefined);
 }finally{client.disconnect();}
});
test('invalid signed targets and failed uploads cannot attach or dispatch',async()=>{
 for(const options of [{uploadPath:'https://evil/path'},{uploadStatus:500}]){
  const {client,frames,requests}=await setup(options);
  try{
   await client.connect('https://test','synthetic');await client.watch('t');await new Promise(setImmediate);
   await assert.rejects(client.upload('test.bin',new Uint8Array([1]).buffer));
   assert.equal(client.attachment,undefined);assert.equal(frames.filter(f=>f.payload?.type==='message.dispatch').length,0);
   assert.ok(requests.every(r=>!r.url.includes('evil')));
  }finally{client.disconnect();}
 }
});

test('two native client instances with colliding thread IDs keep streams and reconnect independent',async()=>{
 const a=await setup({environmentId:'env-a',messages:[{id:'same-message',threadId:'same-thread',role:'assistant',text:'A',streaming:false}]}),
       b=await setup({environmentId:'env-b',messages:[{id:'same-message',threadId:'same-thread',role:'assistant',text:'B',streaming:false}]});
 try {
  await Promise.all([a.client.connect('https://a','synthetic-a'),b.client.connect('https://b','synthetic-b')]);
  await Promise.all([a.client.watch('same-thread'),b.client.watch('same-thread')]);
  await new Promise(setImmediate);
  assert.equal(a.client.thread.messages[0].text,'A');assert.equal(b.client.thread.messages[0].text,'B');
  assert.equal(a.client.recovery.environmentId,'env-a');assert.equal(b.client.recovery.environmentId,'env-b');
  const oldSocket=a.socket();a.client.suspend();assert.equal(b.client.ready,true);
  oldSocket.emit({_tag:'Chunk',requestId:'0',values:[{kind:'snapshot',snapshotSequence:99,projection:{thread:{id:'same-thread'},messages:[]}}]});
  assert.equal(b.client.thread.messages[0].text,'B');
  await a.client.resume();assert.equal(a.client.ready,true);assert.equal(b.client.ready,true);
 } finally {a.client.disconnect();b.client.disconnect()}
});
test('catalog identity checks run before any credential exchange',async()=>{
 for(const mode of ['changed','duplicate']) {
  const {client,requests}=await setup();
  if(mode==='changed')client.expectedEnvironmentId='expected-other';
  else client.validateIdentity=()=>{throw Error('duplicate environment')};
  try {
   await client.connect('https://test','synthetic');assert.equal(client.ready,false);
   assert.equal(requests.filter(x=>x.url.endsWith('/oauth/token')).length,0);
  }finally{client.disconnect()}
 }
});
test('peer listing requires the beta capability and authoritative access permission for its own connection',async()=>{
 for(const options of [{peerLinks:false},{peerLinks:true,sessionState:{authenticated:true,scopes:['access:read'],permissions:[]}}, {peerLinks:true}]){
  const s=await setup(options);try{
   await s.client.connect('https://test','synthetic');await s.client.refreshPeerAccess();
   if(!options.peerLinks||options.sessionState){assert.equal(s.client.canListPeerLinks(),false);await assert.rejects(s.client.linkedEnvironments(),/无权/);assert.equal(s.frames.filter(f=>f.tag==='peerLinks.list').length,0)}
   else {const links=await s.client.linkedEnvironments();assert.equal(links[0].label,'Synthetic peer');assert.equal(s.requests.filter(r=>r.url.endsWith('/api/auth/session')).length,2)}
  }finally{s.client.disconnect()}
 }
});
test('late session permission response cannot authorize a disconnected peer client',async()=>{
 let release;const gate=new Promise(resolve=>release=resolve);const s=await setup({peerLinks:true,waitAccess:gate});
 try{
  await s.client.connect('https://test','synthetic');const pending=s.client.refreshPeerAccess();
  await new Promise(setImmediate);s.client.disconnect();release();await assert.rejects(pending,/连接已变更/);assert.equal(s.client.canListPeerLinks(),false);
 }finally{s.client.disconnect()}
});
test('peer answer writes metadata before RPC and never persists the one-use code',async()=>{
 let reached;const sent=new Promise(resolve=>reached=resolve);
 const s=await setup({peerLinks:true,sessionState:{authenticated:true,permissions:['access:write']},dropMutation:true,onFrame:frame=>{if(frame.tag==='peerLinks.answerRequest')reached()}});
 const store=memoryRecovery();s.client.recoveryStore=store;
 try {
  await s.client.connect('https://test','synthetic');await s.client.watch('t');await new Promise(setImmediate);
  s.client.thread.items=[{id:'link',threadId:'t',type:'link_request',linkStatus:'pending'}];
  const pending=s.client.answerLinkRequest('link',{type:'link',urls:['https://peer'],access:'read-only',pairingCode:'SYNTHETIC_LINK_CODE'});const failure=assert.rejects(pending);
  await sent;const saved=await store.load();assert.match(saved.pendingId,/^test-/);assert.equal(saved.pendingKind,'response');assert.ok(!JSON.stringify(saved).includes('SYNTHETIC_LINK_CODE'));
  assert.equal(s.frames.filter(f=>f.tag==='peerLinks.answerRequest').length,1);s.client.disconnect('offline');await failure;
 }finally{s.client.disconnect()}
});
test('pairing mint uses JSON at the chosen access and permission refresh cannot go backwards',async()=>{
 const options={peerLinks:true,sessionState:{authenticated:true,permissions:['access:write']}};const s=await setup(options);
 try {
  await s.client.connect('https://test','synthetic');assert.equal(await s.client.mintPeerPairingCode('read-only'),'SYNTHETIC_PEER_CODE');
  const request=s.requests.find(r=>r.url.endsWith('/api/auth/pairing-token'));assert.equal(request.args.header['Content-Type'],'application/json');assert.equal(request.args.maxRedirects,0);assert.deepEqual(JSON.parse(request.args.extraData).scopes,['orchestration:read']);
  let release,calls=0;const gate=new Promise(resolve=>release=resolve);options.waitAccess=()=>++calls===1?gate:undefined;
  const old=s.client.refreshPeerAccess();await new Promise(setImmediate);options.sessionState={authenticated:true,permissions:['access:read']};await s.client.refreshPeerAccess();release();await assert.rejects(old,/权限查询已更新/);
  assert.equal(s.client.canManagePeerAccess(),false);assert.equal(s.client.canListPeerLinks(),true);
 }finally{s.client.disconnect()}
});
test('older permission lookups cannot restore revoked access after a newer response',async()=>{
 let release,entered;const slow=new Promise(resolve=>release=resolve),waiting=new Promise(resolve=>entered=resolve);let queries=0;
 const options={peerLinks:true,sessionState:{authenticated:true,permissions:['access:write']},waitAccess:undefined};
 const s=await setup(options);try{
  await s.client.connect('https://test','synthetic');
  options.waitAccess=()=>{if(++queries===1){entered();return slow}};
  const old=s.client.refreshPeerAccess();const rejected=assert.rejects(old,/权限查询已更新/);await waiting;
  options.sessionState={authenticated:true,permissions:['access:read']};await s.client.refreshPeerAccess();assert.equal(s.client.canManagePeerAccess(),false);assert.equal(s.client.canListPeerLinks(),true);
  release();await rejected;assert.equal(s.client.canManagePeerAccess(),false);
 }finally{s.client.disconnect()}
});
test('automatic peer code creation sends only the selected access scopes as JSON and does not save its secret',async()=>{
 const s=await setup({peerLinks:true,sessionState:{authenticated:true,permissions:['access:write']}});try{
  await s.client.connect('https://test','synthetic');assert.equal(await s.client.mintPeerPairingCode('read-only'),'SYNTHETIC_PEER_CODE');
  const request=s.requests.find(r=>r.url.endsWith('/api/auth/pairing-token'));assert.equal(request.args.header['Content-Type'],'application/json');assert.equal(request.args.maxRedirects,0);
  assert.deepEqual(JSON.parse(request.args.extraData),{label:'T3 Code link',scopes:['orchestration:read']});assert.equal(s.client.recovery,undefined);
 }finally{s.client.disconnect()}
});

const taskProviders = [{instanceId:'codex',driver:'codex',installed:true,enabled:true,models:[{slug:'m',name:'Model',capabilities:null}],supportedRuntimeModes:['approval-required']}];
const taskSettings = {modelSelection:{instanceId:'codex',model:'m'},runtimeMode:'approval-required',interactionMode:'default'};
test('draft first send emits only launchThread and persists its message identity before the request',async()=>{
 let saved, sawMarker=false;
 const {client,frames}=await setup({providers:taskProviders,recoveryStore:{async load(){},async save(value){saved=structuredClone(value)}},onFrame(frame){if(frame.tag==='orchestration.launchThread')sawMarker=saved?.pendingId===frame.payload.initialMessage.messageId}});
 try{
  await client.connect('https://test','synthetic');
  const id=await client.launch('project','first message',taskSettings);
  assert(sawMarker);assert.equal(saved.threadId,id);assert.equal(saved.pendingId,'');
  const launches=frames.filter(f=>f.tag==='orchestration.launchThread');assert.equal(launches.length,1);
  assert.equal(frames.filter(f=>f.payload?.type==='thread.create'||f.payload?.type==='message.dispatch').length,0);
  await client.watch(id);await new Promise(setImmediate);assert.equal(client.thread.threadId,id);
 }finally{client.disconnect()}
});
test('launch storage failure and a mismatched launch identity cannot clear unknown-submission protection',async()=>{
 for(const wrongIdentity of [false,true]){
  let saved;
  const {client,frames}=await setup({providers:taskProviders,...(wrongIdentity?{launchIdentity:'other-thread'}:{}),recoveryStore:{async load(){},async save(value){if(!wrongIdentity && value.pendingId)throw Error('store failed');saved=structuredClone(value)}}});
  try{
   await client.connect('https://test','synthetic');
   await assert.rejects(()=>client.launch('project','first message',taskSettings));
   if(wrongIdentity){assert(client.recovery.pendingId);assert.equal(client.mutationPending,true)}
   else {assert.equal(client.recovery,undefined);assert.equal(client.mutationPending,false)}
   assert.equal(frames.filter(f=>f.tag==='orchestration.launchThread').length,wrongIdentity?1:0);
   await assert.rejects(()=>client.launch('project','do not resend',taskSettings));
   assert.equal(frames.filter(f=>f.tag==='orchestration.launchThread').length,wrongIdentity?1:0);
  }finally{client.disconnect()}
 }
});
test('a launch in progress blocks another launch, model changes and reconnect before any duplicate command',async()=>{
 let release;
 const block=new Promise(resolve=>release=resolve);
 const {client,frames}=await setup({providers:taskProviders,recoveryStore:{async load(){},async save(value){if(value.pendingId)await block}}});
 try{
  await client.connect('https://test','synthetic');
  const pending=client.launch('project','one',taskSettings);
  await new Promise(setImmediate);
  await assert.rejects(()=>client.launch('project','two',taskSettings));
  await assert.rejects(()=>client.connect('https://test'));
  release();await pending;
  assert.equal(frames.filter(f=>f.tag==='orchestration.launchThread').length,1);
 }finally{release();client.disconnect()}
});

test('usage-limit recovery uses the projected run and reset time',async()=>{
 const {client,frames}=await setup({providers:[]});
 try{
  await client.connect('https://test','synthetic');
  await client.watch('thread-limit');await new Promise(setImmediate);
  client.thread.details={latestRunId:'run-limit',usageLimitResetAt:'2026-11-18T00:00:00.000Z'};
  await client.setLimitRecovery(true,undefined);
  const command=frames.find(frame=>frame.payload?.type==='thread.metadata.update');
  assert.deepEqual(command.payload.limitRecovery,{runId:'run-limit',resetAt:'2026-11-18T00:00:00.000Z',autoResume:true});
 }finally{client.disconnect()}
});

test('secret references use the configured provider and never send a typed value',async()=>{
 const {client,frames}=await setup({providers:[],secretRequestReferences:true,
  settings:{secretProviders:{vault:{kind:'vault',label:'Vault'}}}});
 try{
  await client.connect('https://test','synthetic');
  await client.watch('thread-secret');await new Promise(setImmediate);
  client.thread.items=[{id:'secret-item',type:'secret_request',secretStatus:'pending',label:'Key',reason:'Need',visibility:'local'}];
  await client.secretReference('secret-item','vault','apps/example');
  const frame=frames.find(value=>value.tag==='secrets.answerRequest');
  assert.deepEqual(frame.payload,{threadId:'thread-secret',turnItemId:'secret-item',
    answer:{type:'reference',reference:{provider:'vault',reference:'apps/example'}}});
  assert.ok(!JSON.stringify(frame.payload).includes('secretValue'));
 }finally{client.disconnect()}
});
test('multi-field secret requests submit trimmed values, reject references, and map fields_mismatch errors',async()=>{
 const {client,frames}=await setup({providers:[],secretRequestReferences:true,
  settings:{secretProviders:{vault:{kind:'vault',label:'Vault'}}}});
 try{
  await client.connect('https://test','synthetic');
  await client.watch('thread-multi-secret');await new Promise(setImmediate);
  client.thread.items=[{
   id:'multi-item',type:'secret_request',secretStatus:'pending',label:'Login',reason:'Auth',visibility:'local',delivery:'file',
   fields:[{name:'email',label:'Email',secret:false},{name:'password',label:'Password'}]
  }];
  await assert.rejects(()=>client.secretReference('multi-item','vault','apps/example'),/不支持秘密引用/);
  await assert.rejects(()=>client.secret('multi-item','single-value',false),/按字段提交/);
  await assert.rejects(()=>client.secretValues('multi-item',{email:'user@example.com',password:'   '}),/请填写所有敏感字段/);
  await client.secretValues('multi-item',{email:' user@example.com ',password:' p@ss '});
  const frame=frames.find(value=>value.tag==='secrets.answerRequest');
  assert.deepEqual(frame.payload,{threadId:'thread-multi-secret',turnItemId:'multi-item',
   answer:{type:'save',values:{email:'user@example.com',password:'p@ss'}}});
  // Decline remains supported on multi-field requests
  await client.secret('multi-item','',true);
  const declineFrame=frames.filter(value=>value.tag==='secrets.answerRequest').at(-1);
  assert.deepEqual(declineFrame.payload,{threadId:'thread-multi-secret',turnItemId:'multi-item',answer:{type:'decline'}});
 }finally{client.disconnect()}

 const mismatch=await setup({secretFailureReason:'fields_mismatch'});
 try{
  await mismatch.client.connect('https://test','synthetic');
  await mismatch.client.watch('thread-mismatch');await new Promise(setImmediate);
  mismatch.client.thread.items=[{
   id:'multi-mismatch',type:'secret_request',secretStatus:'pending',label:'Login',reason:'Auth',visibility:'local',
   fields:[{name:'email',label:'Email',secret:false}]
  }];
  await assert.rejects(
   ()=>mismatch.client.secretValues('multi-mismatch',{email:'a@b.dev'}),
   /此请求需要的字段与当前版本不一致，请更新应用后重试/
  );
 }finally{mismatch.client.disconnect()}
});
test('queue operations recheck live run state and never send a stale queued edit',async()=>{
 const {client,frames}=await setup();
 try{
  await client.connect('https://test','synthetic');await client.watch('thread');await new Promise(setImmediate);
  client.thread.runs=[{id:'run',status:'queued'}];
  await client.queue('edit','run',null,'updated');
  const command=frames.find(f=>f.payload?.type==='queued-run.edit').payload;
  assert.equal(command.text,'updated');assert.equal(command.attachments,undefined);
  client.thread.runs=[{id:'run',status:'running'}];
  await assert.rejects(()=>client.queue('cancel','run'));
  assert.equal(frames.filter(f=>f.payload?.type==='queued-run.cancel').length,0);
 }finally{client.disconnect()}
});
test('a file uploaded in a local draft goes into the first launch without creating an empty thread',async()=>{
 const {client,frames}=await setup({providers:taskProviders});
 try{
  await client.connect('https://test','synthetic');client.draftScope='draft:project';
  await client.upload('first.txt',new Uint8Array([1,2,3]).buffer);
  assert.equal(frames.filter(f=>f.tag==='orchestration.launchThread'||f.payload?.type==='thread.create').length,0);
  await client.launch('project','read attachment',taskSettings);
  const launch=frames.find(f=>f.tag==='orchestration.launchThread').payload;
  assert.equal(launch.initialMessage.attachments.length,1);assert.equal(launch.initialMessage.attachments[0].name,'first.txt');assert.equal(client.attachment,undefined);assert.equal(client.draftScope,'');
 }finally{client.disconnect()}
});
test('confirmed thread model and modes update their own projection; disabled modes cannot be submitted',async()=>{
 const {client,frames}=await setup({providers:taskProviders});
 try{
  await client.connect('https://test','synthetic');await client.watch('t');await new Promise(setImmediate);
  client.thread.details={id:'t',projectId:'project',modelSelection:{instanceId:'codex',model:'m'},runtimeMode:'approval-required',interactionMode:'default'};
  await client.configureThread(taskSettings);await client.changeThreadMode('plan',true);
  assert.equal(client.thread.details.interactionMode,'plan');
  await assert.rejects(()=>client.changeThreadMode('full-access',false));
  assert.equal(frames.filter(f=>f.payload?.type==='thread.runtime-mode.set').length,0);
 }finally{client.disconnect()}
});

test('git stacked action reads the finished result from its progress stream',async()=>{
 const s=await setup({sessionState:{authenticated:true,permissions:['access:read','source-control:write']}});
 try {
  await s.client.connect('https://test','synthetic');
  const progress=[];
  const result=await s.client.gitAction('/repo','commit','message',false,[],label=>progress.push(label));
  assert.equal(result.commit.status,'created');
  assert.equal(result.commit.commitSha,'abc1234');
  assert.ok(progress.includes('Committing...'));
  assert.equal(s.frames.filter(f=>f.tag==='git.runStackedAction').length,1);
 } finally { s.client.disconnect(); }
});
test('preview uses a fresh media ticket and rejects a late ticket from an old connection',async()=>{
 const s=await setup();
 try {
  await s.client.connect('https://test','synthetic');
  const target=await s.client.previewStreamUrl('thread / one','tab&two');
  assert.ok(s.requests.some(r=>r.url==='https://test/api/auth/websocket-ticket/media'));
  assert.equal(new URL(target).searchParams.get('threadId'),'thread / one');
  assert.equal(new URL(target).searchParams.get('tabId'),'tab&two');
  let finish;s.client.httpJson=()=>new Promise(resolve=>finish=resolve);
  const late=s.client.previewStreamUrl('thread','tab');s.client.disconnect();finish({ticket:'late'});
  await assert.rejects(late,/已变化/);
 } finally {s.client.disconnect()}
});

test('device media keeps both tickets on the current hub origin and rejects injected paths',async()=>{
 const s=await setup();try{
  await s.client.connect('https://test','synthetic');
  const before=s.requests.length;const access=await s.client.deviceStreamAccess('/api/device-hub','host one','device/two');
  assert.equal(new URL(access.mjpegUrl).origin,'https://test');assert.equal(new URL(access.inputUrl).origin,'wss://test');
  assert.equal(new URL(access.inputUrl).searchParams.get('device'),'device/two');
  assert.equal(s.requests.slice(before).filter(r=>r.url.endsWith('/media')).length,2);
  const count=s.requests.length;await assert.rejects(s.client.deviceStreamAccess('https://other.test/api/device-hub','h','d'));
  assert.equal(s.requests.length,count);
 }finally{s.client.disconnect()}
});

test('file download requests attachment media while preview and draft keep their own contracts',async()=>{
 const s=await setup();try{
  await s.client.connect('https://test','synthetic');await s.client.watch('t');
  await s.client.workspaceFileUrl('/repo','README.md',false);
  let resource=s.frames.filter(f=>f.tag==='assets.createUrl').at(-1).payload.resource;
  assert.deepEqual(resource,{_tag:'media-file',threadId:'t',path:'/repo/README.md',disposition:'attachment',hostOnly:true});
  await s.client.workspaceFileUrl('/repo','image.png',true);resource=s.frames.filter(f=>f.tag==='assets.createUrl').at(-1).payload.resource;assert.equal(resource._tag,'workspace-file');
  s.client.draftScope='draft:new';await s.client.workspaceFileUrl('/new','image.png',true);resource=s.frames.filter(f=>f.tag==='assets.createUrl').at(-1).payload.resource;assert.deepEqual(resource,{_tag:'draft-workspace-file',cwd:'/new',path:'image.png'});
  for(const path of ['../secret','/etc/passwd','C:\\secret','a/./b'])await assert.rejects(s.client.workspaceFileUrl('/repo',path,false));
 }finally{s.client.disconnect()}
});

test('markdownMediaUrl resolves host absolute paths, relative paths and caches signed URLs per generation',async()=>{
 const s=await setup();try{
  await s.client.connect('https://test','synthetic');await s.client.watch('t');
  const direct=await s.client.markdownMediaUrl('https://cdn.example/a.png','/repo');
  assert.equal(direct.url,'https://cdn.example/a.png');
  assert.equal(s.frames.filter(f=>f.tag==='assets.createUrl').length,0);

  const abs=await s.client.markdownMediaUrl('/Users/zhangyc/.local/share/shot.jpeg','/repo');
  assert.equal(abs.url,'https://test/api/assets/synthetic');
  assert.equal(abs.width,1260);
  assert.equal(abs.height,2720);
  assert.deepEqual(s.frames.filter(f=>f.tag==='assets.createUrl').at(-1).payload.resource,{
    _tag:'media-file',threadId:'t',path:'/Users/zhangyc/.local/share/shot.jpeg'
  });

  // Cached hit avoids duplicate RPC
  const cached=await s.client.markdownMediaUrl('/Users/zhangyc/.local/share/shot.jpeg','/repo');
  assert.equal(cached.url,abs.url);
  assert.equal(s.frames.filter(f=>f.tag==='assets.createUrl').length,1);

  // Explicit refresh re-mints URL
  await s.client.markdownMediaUrl('/Users/zhangyc/.local/share/shot.jpeg','/repo',true);
  assert.equal(s.frames.filter(f=>f.tag==='assets.createUrl').length,2);

  // Relative workspace image uses hostOnly: true
  await s.client.markdownMediaUrl('docs/assets/logo.png','/repo');
  assert.deepEqual(s.frames.filter(f=>f.tag==='assets.createUrl').at(-1).payload.resource,{
    _tag:'media-file',threadId:'t',path:'/repo/docs/assets/logo.png',hostOnly:true
  });

  // Draft scope falls back to draft-workspace-file
  s.client.draftScope='draft:1';
  await s.client.markdownMediaUrl('/Users/zhangyc/draft.png','/new');
  assert.deepEqual(s.frames.filter(f=>f.tag==='assets.createUrl').at(-1).payload.resource,{
    _tag:'draft-workspace-file',cwd:'/new',path:'/Users/zhangyc/draft.png'
  });

  for(const bad of ['javascript:alert(1)','../secret.png','~/a.png','file://other-host/share/a.png']){
    await assert.rejects(s.client.markdownMediaUrl(bad,'/repo'));
  }
 }finally{s.client.disconnect()}
});

test('terminal metadata and read-only observe surface failures and cancel the originating connection',async()=>{
 const {client}=await setup();client.ready=true;client.canScope=s=>s==='terminal:operate'?false:true;
 const calls=[];const cancelled=[];let reject;let receive;
 const rpc={request(method,payload,onItem){calls.push({method,payload});receive=onItem;return new Promise((_,r)=>reject=r)},cancelStream(fn){cancelled.push(fn)}};
 client.rpc=rpc;const failures=[];const values=[];
 const stop=client.watchTerminals(v=>values.push(v),m=>failures.push(m));
 assert.equal(calls[0].method,'subscribeTerminalMetadata');receive({type:'snapshot',terminals:[]});assert.equal(values.length,1);
 reject(Error('denied'));await new Promise(setImmediate);assert.equal(failures.length,1);
 const cancelObserve=client.attachTerminal({threadId:'t',terminalId:'a'},()=>{},()=>{},true);
 assert.equal(calls[1].method,'terminal.observe');assert.deepEqual(calls[1].payload,{threadId:'t',terminalId:'a'});
 assert.throws(()=>client.attachTerminal({threadId:'t',terminalId:'a'},()=>{},()=>{}),/无权/);
 client.rpc={cancelStream(){throw Error('must cancel original socket')}};
 stop();cancelObserve();assert.equal(cancelled.length,2);
});
test('old terminal connection cannot publish frames or failures after environment changes',async()=>{
 const {client}=await setup();client.ready=true;client.canScope=()=>true;
 let receive,reject;const failures=[],values=[];
 client.rpc={request(method,payload,fn){receive=fn;return new Promise((_,r)=>reject=r)},cancelStream(){}};
 const stop=client.watchTerminals(v=>values.push(v),m=>failures.push(m));
 client.generation++;receive({type:'snapshot',terminals:[]});reject(Error('old'));await new Promise(setImmediate);
 assert.deepEqual(values,[]);assert.deepEqual(failures,[]);stop();
});

test('resume refreshes settings permissions automatically and ignores the previous connection response', async () => {
  let finish;
  const oldResponse = new Promise(resolve => { finish = resolve; });
  const options = { sessionState: { authenticated: true, permissions: ['settings:write'] }, waitAccess: oldResponse };
  const { client, requests } = await setup(options);
  try {
    await client.connect('https://test', 'synthetic');
    assert.equal(client.canScope('settings:write'), undefined);
    options.sessionState = { authenticated: true, permissions: ['orchestration:read'] };
    options.waitAccess = undefined;
    client.suspend();
    await client.resume();
    await new Promise(setImmediate);
    assert.equal(client.ready, true);
    assert.equal(client.canScope('settings:write'), false);
    assert.equal(client.canScope('orchestration:read'), true);
    let staleUpdates = 0;
    client.onUpdate = () => { staleUpdates++; };
    finish();
    await new Promise(setImmediate);
    assert.equal(client.canScope('settings:write'), false);
    assert.equal(staleUpdates, 0);
    assert.equal(requests.filter(request => new URL(request.url).pathname === '/api/auth/session').length, 2);
  } finally {
    finish();
    client.disconnect();
  }
});

test('a newer explicit scope refresh wins over an automatic refresh on the same transport', async () => {
  let finish;
  const stale = new Promise(resolve => { finish = resolve; });
  const options = { sessionState: { authenticated: true, permissions: ['settings:write'] }, waitAccess: stale };
  const { client } = await setup(options);
  try {
    await client.connect('https://test', 'synthetic');
    options.sessionState = { authenticated: true, permissions: [] };
    options.waitAccess = undefined;
    await client.refreshSessionAccess();
    assert.equal(client.canScope('settings:write'), false);
    finish();
    await new Promise(setImmediate);
    assert.equal(client.canScope('settings:write'), false);
  } finally {
    finish();
    client.disconnect();
  }
});

test('verified settings readback updates connected Add Project consumers without another request', async () => {
 const { client, requests, frames } = await setup({
  settings: { addProjectBaseDirectory: '~/first', ghqCloneLayout: false }
 });
 try {
  await client.connect('https://test', 'synthetic');
  await new Promise(setImmediate);
  const generation = client.generationValue();
  const observed = client.config;
  const updated = { ...observed, settings: { ...observed.settings, addProjectBaseDirectory: '~/next', ghqCloneLayout: true } };
  assert.throws(() => client.applyVerifiedSettingsConfig(updated, 'env', generation - 1), /环境已变化/);
  assert.throws(() => client.applyVerifiedSettingsConfig(updated, 'other', generation), /环境已变化/);
  const httpBefore = requests.length;
  const rpcBefore = frames.length;
  client.applyVerifiedSettingsConfig(updated, 'env', generation);
  assert.equal(client.addProjectBaseDirectory, '~/next');
  assert.equal(client.ghqCloneLayout, true);
  assert.equal(requests.length, httpBefore);
  assert.equal(frames.length, rpcBefore);
 } finally { client.disconnect(); }
});

test('late upload cannot clear or append to a different draft on the same native connection', async () => {
 let finish, started;
 let calls=0;
 const gate=new Promise(resolve=>finish=resolve);
 const entered=new Promise(resolve=>started=resolve);
 const {client}=await setup({waitUpload:()=>{if (++calls===1){started();return gate;}}});
 const bytes=new Uint8Array([1]).buffer;
 try {
  await client.connect('https://test','synthetic');client.draftScope='draft:a';
  const failed=assert.rejects(client.upload('old-a.txt',bytes),/上传未确认|目标已变化/);
  await entered;
  client.draftScope='draft:b';
  await client.upload('new-b.txt',bytes);
  finish();await failed;
  assert.deepEqual(client.attachments.map(item=>item.name),['new-b.txt']);
  assert.equal(client.attachment.name,'new-b.txt');
  assert.equal(client.attachmentThread,'draft:b');
 } finally {finish();client.disconnect();}
});

test('A→B→A invalidates old upload while a retry in the current draft succeeds', async () => {
 let finish, started;
 let calls=0;
 const gate=new Promise(resolve=>finish=resolve);
 const entered=new Promise(resolve=>started=resolve);
 const {client}=await setup({waitUpload:()=>{if (++calls===1){started();return gate;}}});
 const bytes=new Uint8Array([1]).buffer;
 try {
  await client.connect('https://test','synthetic');client.draftScope='draft:a';
  const failed=assert.rejects(client.upload('late-a.txt',bytes),/上传未确认|目标已变化/);
  await entered;client.draftScope='draft:b';client.draftScope='draft:a';
  finish();await failed;
  assert.deepEqual(client.attachments,[]);
  await client.upload('retry-a.txt',bytes);
  assert.deepEqual(client.attachments.map(item=>item.name),['retry-a.txt']);
 } finally {finish();client.disconnect();}
});

test('upload from an obsolete generation cannot replace a reconnected draft attachment', async () => {
 let finish, started;
 let calls=0;
 const gate=new Promise(resolve=>finish=resolve);
 const entered=new Promise(resolve=>started=resolve);
 const {client}=await setup({waitUpload:()=>{if (++calls===1){started();return gate;}}});
 const bytes=new Uint8Array([1]).buffer;
 try {
  await client.connect('https://test','synthetic');client.draftScope='draft:a';
  const failed=assert.rejects(client.upload('old-connection.txt',bytes),/上传未确认|目标已变化/);
  await entered;
  client.disconnect();
  await client.connect('https://test','synthetic');client.draftScope='draft:a';
  await client.upload('new-connection.txt',bytes);
  finish();await failed;
  assert.deepEqual(client.attachments.map(item=>item.name),['new-connection.txt']);
  assert.equal(client.attachmentThread,'draft:a');
 } finally {finish();client.disconnect();}
});

test('late upload to a thread cannot replace the next thread attachment', async () => {
 let finish, entered;
 let count=0;
 const gate=new Promise(resolve=>finish=resolve);
 const started=new Promise(resolve=>entered=resolve);
 const {client}=await setup({waitUpload:()=>{if(++count===1){entered();return gate;}}});
 const bytes=new Uint8Array([1]).buffer;
 try {
  await client.connect('https://test','synthetic');await client.watch('a');
  const stale=assert.rejects(client.upload('old-thread.txt',bytes),/上传未确认|目标已变化/);
  await started;await client.watch('b');await client.upload('current-thread.txt',bytes);
  finish();await stale;
  assert.deepEqual(client.attachments.map(item=>item.name),['current-thread.txt']);
  assert.equal(client.attachmentThread,'b');
 } finally {finish();client.disconnect();}
});

test('stale non-pending recovery is cleared on known subscribe rejection while pending recovery stays protected', async () => {
 const nonPendingStore=memoryRecovery({base:'https://test',environmentId:'env',threadId:'stale-thread',pendingId:'',pendingKind:''});
 const first=await setup({recoveryStore:nonPendingStore,rejectThread:true});
 try {
  await first.client.connect('https://test','synthetic');
  await new Promise(setImmediate);
  assert.equal(first.client.ready,true);
  assert.equal(first.client.status,'已连接');
  assert.equal(first.client.thread,undefined);
  assert.equal(await nonPendingStore.load(),undefined);
 } finally {first.client.disconnect();}

 const pendingRecord={base:'https://test',environmentId:'env',threadId:'pending-thread',pendingId:'msg-1',pendingKind:'message'};
 const pendingStore=memoryRecovery(pendingRecord);
 const second=await setup({recoveryStore:pendingStore,rejectThread:true});
 try {
  await second.client.connect('https://test','synthetic');
  await new Promise(setImmediate);
  assert.equal(second.client.ready,false);
  assert.deepEqual(await pendingStore.load(),pendingRecord);
 } finally {second.client.disconnect();}
});

test('bounded subscribeThread payload, disconnect-reconnect re-watch, transient retry recovery, and loadOlderHistory', async () => {
 const { client, frames, requests } = await setup({
  historyResponse: {
   items: [{ item: { id: 'item-u0', type: 'user_message', messageId: 'u0', text: 'older q', createdAt: '2026-01-01T00:00:00.000Z', runId: 'r0' }, visibility: 'visible' }],
   nextCursor: '20',
   hasMoreHistory: false
  }
 });
 client.store = { async load() { return undefined; }, async save() {}, async clear() {} };
 try {
  await client.connect('https://test', 'synthetic');
  await new Promise(setImmediate);
  await client.watch('thread-bound');
  await new Promise(setImmediate);

  const subFrame = frames.find((f) => f.tag === 'orchestration.subscribeThread');
  assert.deepEqual(subFrame.payload, {
   threadId: 'thread-bound',
   acceptBoundedSnapshot: true,
   requestCompletionMarker: true,
   acceptDedupedBodies: true
  });

  // Apply bounded snapshot history metadata and load older history without compactIds=1
  client.thread.apply({
   kind: 'snapshot',
   snapshotSequence: 11,
   historyCursor: '40',
   hasMoreHistory: true,
   projection: {
    thread: { id: 'thread-bound', title: 'Bounded', modelSelection: { provider: 'codex', model: 'm' } },
    messages: [{ id: 'u1', role: 'user', text: 'latest q', createdAt: '2026-01-01T00:01:00.000Z', runId: 'r1' }],
    visibleTurnItems: [{ item: { id: 'item-u1', type: 'user_message', messageId: 'u1', text: 'latest q', runId: 'r1' }, visibility: 'visible' }]
   }
  });
  await client.loadOlderHistory();
  const histReq = requests.find((r) => r.url.includes('/history'));
  assert.ok(histReq);
  assert.equal(histReq.url.includes('compactIds'), false);
  assert.equal(histReq.url.includes('cursor=40'), true);
  assert.equal(histReq.args.header['x-t3-orchestration-protocol'], '2');
  assert.deepEqual(client.thread.messages.map((m) => m.id), ['u0', 'u1']);

  // Background disconnect -> reconnect without pending recovery still re-watches lastWatchedThreadId
  const beforeCount = frames.filter((f) => f.tag === 'orchestration.subscribeThread').length;
  client.disconnect();
  await client.connect('https://test', 'synthetic');
  await new Promise(setImmediate);
  const afterCount = frames.filter((f) => f.tag === 'orchestration.subscribeThread').length;
  assert.equal(afterCount, beforeCount + 1);
  assert.equal(frames.filter((f) => f.tag === 'orchestration.subscribeThread').at(-1).payload.threadId, 'thread-bound');

  // Forget clears remembered route/watched thread
  await client.forget();
  assert.equal(client.lastWatchedThreadId, '');
 } finally {
  client.disconnect();
 }

 // Transient 502 on saved connect schedules recovery instead of dying silently
 const transient = await setup({ transientRpcStatus: 502 });
 transient.client.store = {
  async load() { return { base: 'https://test', environmentId: 'env', token: 'SYNTHETIC_TOKEN', expiresAt: Date.now() + 60000 }; },
  async save() {},
  async clear() {}
 };
 try {
  await transient.client.connect('https://test', 'synthetic');
  assert.equal(transient.client.ready, false);
  assert.ok(transient.client.retryTimer !== undefined || transient.client.status.includes('重连'));
 } finally {
  transient.client.disconnect();
 }
});

test('direct private and tailnet hosts bypass system proxy on HTTP and WebSocket while public hosts keep default proxy', async () => {
 for (const [base, expectBypass] of [
  ['http://192.168.2.97:3773', true],
  ['https://box.ts.net', true],
  ['https://example.com', false],
 ]) {
  const { client, requests, socketConnects } = await setup();
  try {
   await client.connect(base, 'synthetic');
   assert.equal(client.ready, true);
   assert.ok(requests.length >= 3);
   for (const req of requests) {
    assert.equal(req.args.usingProxy, expectBypass ? false : undefined, base + ' ' + req.url);
   }
   assert.equal(socketConnects.length, 1);
   assert.deepEqual(socketConnects[0].connectOptions, expectBypass ? { proxy: 'no-proxy' } : undefined, base);
  } finally {
   client.disconnect();
  }
 }
});

test('HTTP network errors produce clear Chinese diagnostics, hide credentials, and remain recoverable', async () => {
 const timeout = await setup({ httpError: { code: 2300028 } });
 timeout.client.store = {
  async load() { return { base: 'http://192.168.2.97:3773', environmentId: 'env', token: 'SYNTHETIC_TOKEN', expiresAt: Date.now() + 60000 }; },
  async save() {},
  async clear() {}
 };
 try {
  await timeout.client.connect('http://192.168.2.97:3773', 'SECRET_PAIRING_CODE');
  assert.equal(timeout.client.ready, false);
  assert.match(timeout.client.status, /连接超时.*系统错误码 2300028/);
  assert.equal(timeout.client.status.includes('SECRET_PAIRING_CODE'), false);
  assert.ok(timeout.client.retryTimer !== undefined);
 } finally {
  timeout.client.disconnect();
 }

 const refused = await setup({ httpError: { code: 2300007 } });
 try {
  await refused.client.connect('http://192.168.2.97:3773', 'synthetic');
  assert.match(refused.client.status, /无法连接服务器.*系统错误码 2300007/);
 } finally {
  refused.client.disconnect();
 }

 const tls = await setup({ httpError: { code: 2300060 } });
 try {
  await tls.client.connect('https://example.com', 'synthetic');
  assert.match(tls.client.status, /TLS 证书校验失败.*系统错误码 2300060/);
 } finally {
  tls.client.disconnect();
 }
});

test('connect uses subscribeServerConfig with workspaceSnapshotsOnDemand, applies live updates, and falls back to server.getConfig on legacy hosts', async () => {
 const fast = await setup({ capabilities: { threadSettlement: true } });
 try {
  await fast.client.connect('https://test', 'synthetic');
  const subFrame = fast.frames.find((f) => f.tag === 'subscribeServerConfig');
  assert.ok(subFrame, 'must send subscribeServerConfig');
  assert.deepEqual(subFrame.payload, { workspaceSnapshotsOnDemand: true, providerStatusDeltas: true });
  assert.equal(fast.frames.some((f) => f.tag === 'server.getConfig'), false);
  // Late settingsUpdated, providerStatusDeltas & snapshot updates apply live without reconnecting
  fast.socket().emit({ _tag: 'Chunk', requestId: subFrame.id, values: [
    { version: 1, type: 'settingsUpdated', payload: { settings: { addProjectBaseDirectory: '/late-dir', ghqCloneLayout: true } } }
  ] });
  assert.equal(fast.client.addProjectBaseDirectory, '/late-dir');
  assert.equal(fast.client.ghqCloneLayout, true);
 } finally {
  fast.client.disconnect();
 }

 const deltaHost = await setup({
  providers: [{
   instanceId: 'codex',
   enabled: true,
   installed: true,
   status: 'ready',
   models: [{ slug: 'gpt-5', name: 'GPT-5' }],
   slashCommands: [{ name: 'review' }],
   skills: [{ name: 'refactor', enabled: true }]
  }]
 });
 try {
  await deltaHost.client.connect('https://test', 'synthetic');
  const subFrame = deltaHost.frames.find((f) => f.tag === 'subscribeServerConfig');
  deltaHost.socket().emit({ _tag: 'Chunk', requestId: subFrame.id, values: [
   { version: 1, type: 'providerStatusDeltas', payload: { providers: [{ instanceId: 'codex', enabled: true, installed: true, status: 'busy' }] } }
  ] });
  assert.equal(deltaHost.client.models.length, 1);
  assert.equal(deltaHost.client.models[0].model, 'gpt-5');
  assert.deepEqual(deltaHost.client.providerCommands(), ['review']);
  assert.deepEqual(deltaHost.client.providerSkills(), ['refactor']);
 } finally {
  deltaHost.client.disconnect();
 }

 const legacy = await setup({ rejectSubscribeConfig: true, capabilities: { threadSnooze: true } });
 try {
  await legacy.client.connect('https://test', 'synthetic');
  assert.equal(legacy.client.ready, true);
  assert.equal(legacy.frames.some((f) => f.tag === 'subscribeServerConfig'), true);
  assert.equal(legacy.frames.some((f) => f.tag === 'server.getConfig'), true);
  assert.equal(legacy.client.supports('threadSnooze'), true);
 } finally {
  legacy.client.disconnect();
 }
});

test('reconnect skips redundant credential save, reuses prechecked descriptor, and preserves cached shell until forget', async () => {
 let saveCalls = 0;
 let stored;
 const { client, requests } = await setup({
  shellProjects: [{ id: 'p1', title: 'Alpha', workspaceRoot: '/alpha' }],
  shellThreads: [{ id: 't1', title: 'First task', projectId: 'p1' }],
  capabilities: { threadSettlement: true }
 });
 client.store = {
  async load() { return stored ? structuredClone(stored) : undefined; },
  async save(v) { saveCalls++; stored = structuredClone(v); },
  async clear() { stored = undefined; }
 };
 try {
  await client.connect('https://test', 'synthetic');
  await new Promise(setImmediate);
  assert.equal(saveCalls, 1);
  assert.equal(client.shellSynced, true);
  assert.equal(client.shell.threads.length, 1);
  const exported = client.exportShellCache();
  assert.ok(exported);
  assert.equal(exported.threads[0].id, 't1');
  assert.equal(exported.capabilities.threadSettlement, true);

  // Transient disconnect preserves cached shell for UI while marking liveSynced false
  client.disconnect('offline', false);
  assert.equal(client.ready, false);
  assert.equal(client.shellSynced, false);
  assert.equal(client.hasShellData, true);
  assert.equal(client.shell.threads.length, 1);

  // Probe route + reuse prechecked descriptor skips duplicate /.well-known/t3/environment and skips redundant store.save
  const probe = await client.probeRoute('https://test', 'env', 2500);
  assert.equal(probe.ok, true);
  const reqBefore = requests.length;
  await client.connect('https://test', '', probe);
  await new Promise(setImmediate);
  assert.equal(client.ready, true);
  assert.equal(saveCalls, 1, 'reconnect without new credential must not rewrite AssetStore');
  const reconnectPaths = requests.slice(reqBefore).map((r) => new URL(r.url).pathname);
  assert.equal(reconnectPaths.includes('/.well-known/t3/environment'), false, 'must reuse freshly probed descriptor');
  assert.equal(reconnectPaths.includes('/api/auth/websocket-ticket/rpc'), true);

  // Explicit forget clears shell cache in memory
  await client.forget();
  assert.equal(client.hasShellData, false);
  assert.equal(client.shell.threads.length, 0);
 } finally {
  client.disconnect();
 }
});

test('enterBackground keeps socket alive and foreground resume probes via server.probe before reconnecting', async () => {
 // Case 1: Live socket answers server.probe -> zero reconnect!
 const live = await setup();
 try {
  await live.client.connect('https://test', 'synthetic');
  await new Promise(setImmediate);
  const socketsBefore = live.socketConnects.length;
  live.client.enterBackground();
  assert.equal(live.client.ready, true, 'enterBackground must keep socket alive');
  await live.client.resume(2000);
  assert.equal(live.client.ready, true);
  assert.equal(live.socketConnects.length, socketsBefore, 'healthy socket must not reconnect on foreground');
  assert.equal(live.frames.some((f) => f.tag === 'server.probe'), true);
 } finally {
  live.client.disconnect();
 }

 // Case 2: Older host rejects server.probe with known RPC exit -> still proves socket is alive!
 const knownReject = await setup({ rejectProbeKnown: true });
 try {
  await knownReject.client.connect('https://test', 'synthetic');
  await new Promise(setImmediate);
  const socketsBefore = knownReject.socketConnects.length;
  knownReject.client.enterBackground();
  await knownReject.client.resume(2000);
  assert.equal(knownReject.client.ready, true);
  assert.equal(knownReject.socketConnects.length, socketsBefore);
 } finally {
  knownReject.client.disconnect();
 }

 // Case 3: Silent dead socket fails probe -> transparently reconnects!
 const dead = await setup({ dropProbe: true });
 let savedToken = { base: 'https://test', environmentId: 'env', token: 'SYNTHETIC_TOKEN', expiresAt: Date.now() + 60000 };
 dead.client.store = { async load() { return savedToken; }, async save(v) { savedToken = v; }, async clear() {} };
 try {
  await dead.client.connect('https://test', 'synthetic');
  await new Promise(setImmediate);
  const socketsBefore = dead.socketConnects.length;
  dead.client.enterBackground();
  await dead.client.resume(12000);
  assert.equal(dead.client.ready, true);
  assert.equal(dead.socketConnects.length, socketsBefore + 1, 'silent socket must reconnect after probe timeout');
 } finally {
  dead.client.disconnect();
 }
});

test('connect waits for WebSocket open handshake, enables frameParts=1, and isolates stream failures without killing the socket', async () => {
 // 1. Gated on socket open event
 const gated = await setup({ neverOpen: true });
 try {
  const connecting = gated.client.connect('https://test', 'synthetic');
  await new Promise((resolve) => setTimeout(resolve, 25));
  assert.equal(gated.socketConnects.length, 1);
  assert.equal(new URL(gated.socketConnects[0].url).searchParams.get('frameParts'), '1');
  assert.equal(gated.frames.length, 0, 'must not send RPC frames before socket open fires');
  gated.socket().emitOpen({ code: 0 });
  await connecting;
  assert.equal(gated.client.ready, true);
  assert.ok(gated.frames.some((f) => f.tag === 'subscribeServerConfig'));
 } finally {
  gated.client.disconnect();
 }

 // 2. Reconnect sends afterSequence for both shell and thread, and stream exits resubscribe locally without killing WS
 const isolated = await setup({
  shellProjects: [{ id: 'p1', title: 'Alpha', workspaceRoot: '/alpha' }],
  shellThreads: [{ id: 't1', title: 'Task 1', projectId: 'p1' }]
 });
 let storedToken = { base: 'https://test', environmentId: 'env', token: 'SYNTHETIC_TOKEN', expiresAt: Date.now() + 60000 };
 isolated.client.store = { async load() { return storedToken; }, async save(v) { storedToken = v; }, async clear() {} };
 try {
  await isolated.client.connect('https://test', 'synthetic');
  await new Promise(setImmediate);
  await isolated.client.watch('t1');
  await new Promise(setImmediate);
  assert.equal(isolated.client.shell.cursor, 9);
  assert.equal(isolated.client.thread.cursor, 10);

  // Transient disconnect -> reconnect sends afterSequence for shell (9) and thread (10)
  isolated.client.disconnect('网络抖动', false, false);
  await isolated.client.connect('https://test', '');
  await new Promise(setImmediate);
  const lastShellSub = isolated.frames.filter((f) => f.tag === 'orchestration.subscribeShell').at(-1);
  assert.equal(lastShellSub.payload.requestCompletionMarker, true);
  assert.equal(lastShellSub.payload.omitIdleSubagents, true);
  assert.equal(lastShellSub.payload.afterSequence, 9);
  const lastThreadSub = isolated.frames.filter((f) => f.tag === 'orchestration.subscribeThread').at(-1);
  assert.equal(lastThreadSub.payload.afterSequence, 10);
  assert.equal(lastThreadSub.payload.acceptDedupedBodies, true);

  // Closing the shell stream or thread stream keeps the WebSocket alive and retries locally
  const socketsBefore = isolated.socketConnects.length;
  const shellSubCountBefore = isolated.frames.filter((f) => f.tag === 'orchestration.subscribeShell').length;
  const threadSubCountBefore = isolated.frames.filter((f) => f.tag === 'orchestration.subscribeThread').length;
  isolated.socket().emit({ _tag: 'Exit', requestId: lastShellSub.id, exit: { _tag: 'Success', value: null } });
  isolated.socket().emit({ _tag: 'Exit', requestId: lastThreadSub.id, exit: { _tag: 'Success', value: null } });
  assert.equal(isolated.client.ready, true, 'stream exit must not disconnect healthy WebSocket');
  await new Promise((resolve) => setTimeout(resolve, 350));
  assert.equal(isolated.socketConnects.length, socketsBefore, 'local stream resubscribe must reuse existing socket');
  assert.ok(isolated.frames.filter((f) => f.tag === 'orchestration.subscribeShell').length > shellSubCountBefore);
  assert.ok(isolated.frames.filter((f) => f.tag === 'orchestration.subscribeThread').length > threadSubCountBefore);
 } finally {
  isolated.client.disconnect();
 }
});

test('inbound traffic proves socket alive during resume probe, offline pauses retries, and backoff escalates on rapid flap', async () => {
 // 1. Live inbound frame during dropped server.probe resolves probe alive without reconnecting
 const traffic = await setup({ dropProbe: true });
 try {
  await traffic.client.connect('https://test', 'synthetic');
  await new Promise(setImmediate);
  const socketsBefore = traffic.socketConnects.length;
  traffic.client.enterBackground();
  const resuming = traffic.client.resume(2000);
  setTimeout(() => { traffic.socket().emit({ _tag: 'Pong' }); }, 30);
  await resuming;
  assert.equal(traffic.client.ready, true);
  assert.equal(traffic.socketConnects.length, socketsBefore, 'incoming frame proves socket alive without reconnect');
 } finally {
  traffic.client.disconnect();
 }

 // 2. Offline pauses automatic retry and coming back online reconnects immediately
 const net = await setup();
 let saved = { base: 'https://test', environmentId: 'env', token: 'SYNTHETIC_TOKEN', expiresAt: Date.now() + 60000 };
 net.client.store = { async load() { return saved; }, async save(v) { saved = v; }, async clear() {} };
 try {
  await net.client.connect('https://test', 'synthetic');
  await new Promise(setImmediate);
  net.client.handleNetworkStatus(true);
  net.socket().emitClose({ code: 1006, reason: 'network down' });
  assert.equal(net.client.ready, false);
  assert.equal(net.client.networkOffline, true);
  assert.equal(net.client.reconnectPending, false, 'offline client must pause retry loop');

  net.client.handleNetworkStatus(false);
  await new Promise((resolve) => setTimeout(resolve, 50));
  assert.equal(net.client.ready, true, 'coming back online must immediately reconnect');
  assert.equal(net.client.networkOffline, false);
 } finally {
  net.client.disconnect();
 }

 // 3. Rapid flap (< 30s uptime) escalates retryDelay instead of resetting to 250ms forever
 const flap = await setup();
 flap.client.store = { async load() { return saved; }, async save(v) { saved = v; }, async clear() {} };
 try {
  await flap.client.connect('https://test', 'synthetic');
  await new Promise(setImmediate);
  // First drop from live session uses fast 250ms retry (jittered 125..250)
  flap.client.disconnect('drop 1', true, false);
  const firstDelay = flap.client.retryDelay;
  assert.ok(firstDelay >= 100 && firstDelay <= 250, 'first live drop should use fast retry, got ' + firstDelay);
  clearTimeout(flap.client.retryTimer); flap.client.retryTimer = 0;

  // Immediate reconnect + drop within < 30s must escalate backoff rather than resetting
  await flap.client.connect('https://test', '');
  flap.client.disconnect('drop 2', true, false);
  const secondDelay = flap.client.retryDelay;
  assert.ok(secondDelay >= 500, 'rapid flap must escalate exponential backoff, got ' + secondDelay);
 } finally {
  flap.client.disconnect();
 }
});

test('direct DPoP pairing uses device key when accessTokenRenewal is advertised and sends DPoP on HTTP and WS', async () => {
  const proofCalls = [];
  let stored;
  const { client, requests, socketConnects } = await setup({
    descriptorCapabilities: { accessTokenRenewal: true },
    dpopSigner: {
      async prove(method, target, accessToken) {
        proofCalls.push({ method, target, accessToken });
        return `proof:${method}:${target}:${accessToken ?? ''}`;
      }
    },
    onTokenRequest: (_url, args) => {
      assert.equal(args.header.DPoP, 'proof:POST:https://test/oauth/token:');
      const params = new URLSearchParams(args.extraData);
      assert.equal(params.get('subject_token'), 'one-time-code');
      assert.equal(params.get('subject_token_type'), 'urn:t3:params:oauth:token-type:environment-bootstrap');
      return { status: 200, value: { access_token: 'DPOP_TOK_1', token_type: 'DPoP', expires_in: 900 } };
    },
    onTicketRequest: (_url, args) => {
      assert.equal(args.header.Authorization, 'DPoP DPOP_TOK_1');
      assert.equal(args.header.DPoP, 'proof:POST:https://test/api/auth/websocket-ticket/rpc:DPOP_TOK_1');
      return { status: 200, value: { ticket: 'DPOP_TICKET_1' } };
    }
  });
  client.store = {
    async load() { return stored ? structuredClone(stored) : undefined; },
    async save(v) { stored = structuredClone(v); },
    async clear() { stored = undefined; }
  };
  try {
    await client.connect('https://test', 'one-time-code');
    await new Promise(setImmediate);
    assert.equal(client.ready, true);
    assert.equal(stored.kind, 'dpop');
    assert.equal(stored.token, 'DPOP_TOK_1');
    const wsUrl = new URL(socketConnects[0].url);
    assert.equal(wsUrl.searchParams.get('wsTicket'), 'DPOP_TICKET_1');
    assert.equal(wsUrl.searchParams.get('dpop'), 'proof:GET:https://test/ws:DPOP_TICKET_1');
    assert.equal(wsUrl.searchParams.get('connectionMethod'), 'direct');
    const sessionReq = requests.find((r) => r.url.endsWith('/api/auth/session'));
    assert.ok(sessionReq);
    assert.equal(sessionReq.args.header.Authorization, 'DPoP DPOP_TOK_1');
    assert.equal(sessionReq.args.header.DPoP, 'proof:GET:https://test/api/auth/session:DPOP_TOK_1');
    await client.pullRequestDiff({ number: 1 });
    const diffReq = requests.find((r) => r.url.endsWith('/api/pull-requests/diff'));
    assert.equal(diffReq.args.header.Authorization, 'DPoP DPOP_TOK_1');
    assert.equal(diffReq.args.header.DPoP, 'proof:POST:https://test/api/pull-requests/diff:DPOP_TOK_1');
    assert.equal(proofCalls[0].target, 'https://test/oauth/token');
    assert.equal(proofCalls[0].accessToken, undefined);
  } finally {
    client.disconnect();
  }
});

test('direct pairing falls back to Bearer without wasting one-time code when capability absent or proof signing fails', async () => {
  // 1. Server without accessTokenRenewal does not invoke signer
  let signerCalls = 0;
  const noCap = await setup({
    descriptorCapabilities: {},
    dpopSigner: {
      async prove() { signerCalls++; return 'unused'; }
    }
  });
  try {
    await noCap.client.connect('https://test', 'code-no-cap');
    assert.equal(noCap.client.ready, true);
    assert.equal(signerCalls, 0);
    const tokenReqs = noCap.requests.filter((r) => r.url.endsWith('/oauth/token'));
    assert.equal(tokenReqs.length, 1);
    assert.equal(tokenReqs[0].args.header.DPoP, undefined);
  } finally {
    noCap.client.disconnect();
  }

  // 2. Signer throws BEFORE /oauth/token -> falls back to Bearer and posts the one-time code only once
  let stored;
  const brokenSigner = await setup({
    descriptorCapabilities: { accessTokenRenewal: true },
    dpopSigner: {
      async prove() { throw new Error('device key locked'); }
    }
  });
  brokenSigner.client.store = {
    async load() { return stored ? structuredClone(stored) : undefined; },
    async save(v) { stored = structuredClone(v); },
    async clear() { stored = undefined; }
  };
  try {
    await brokenSigner.client.connect('https://test', 'single-use-code');
    assert.equal(brokenSigner.client.ready, true);
    const tokenReqs = brokenSigner.requests.filter((r) => r.url.endsWith('/oauth/token'));
    assert.equal(tokenReqs.length, 1);
    assert.equal(tokenReqs[0].args.header.DPoP, undefined);
    assert.equal(new URLSearchParams(tokenReqs[0].args.extraData).get('subject_token'), 'single-use-code');
    assert.equal(stored.kind, undefined);
    assert.equal(new URL(brokenSigner.socketConnects[0].url).searchParams.get('dpop'), null);
  } finally {
    brokenSigner.client.disconnect();
  }
});

test('direct DPoP renews expired or expiring tokens with per-connection lock deduplication', async () => {
  let tokenCounter = 0;
  let stored = {
    base: 'https://test',
    environmentId: 'env',
    token: 'DPOP_EXPIRED_0',
    expiresAt: Date.now() - 5000,
    kind: 'dpop'
  };
  const { client, requests } = await setup({
    descriptorCapabilities: { accessTokenRenewal: true },
    dpopSigner: {
      async prove(method, target, accessToken) {
        return `proof:${method}:${target}:${accessToken ?? ''}`;
      }
    },
    onTokenRequest: async (_url, args) => {
      tokenCounter++;
      const params = new URLSearchParams(args.extraData);
      assert.equal(params.get('grant_type'), 'urn:ietf:params:oauth:grant-type:token-exchange');
      assert.equal(params.get('subject_token_type'), 'urn:ietf:params:oauth:token-type:access_token');
      assert.equal(params.get('requested_token_type'), 'urn:ietf:params:oauth:token-type:access_token');
      assert.equal(params.get('scope'), null);
      assert.equal(args.header.DPoP, 'proof:POST:https://test/oauth/token:');
      if (tokenCounter === 1) {
        assert.equal(params.get('subject_token'), 'DPOP_EXPIRED_0');
        // Return a token already inside the 60s refresh skew (30s) so concurrent HTTP requests renew it once.
        return { status: 200, value: { access_token: 'DPOP_SHORT_1', token_type: 'DPoP', expires_in: 30 } };
      }
      assert.equal(params.get('subject_token'), 'DPOP_SHORT_1');
      await new Promise((resolve) => setTimeout(resolve, 25));
      return { status: 200, value: { access_token: 'DPOP_FRESH_2', token_type: 'DPoP', expires_in: 900 } };
    }
  });
  client.store = {
    async load() { return structuredClone(stored); },
    async save(v) { stored = structuredClone(v); },
    async clear() { stored = undefined; }
  };
  try {
    // Reconnect with expired DPoP session succeeds via renewal without pairing code
    await client.connect('https://test');
    assert.equal(client.ready, true);
    assert.equal(tokenCounter, 1);
    assert.equal(stored.token, 'DPOP_SHORT_1');
    assert.equal(stored.kind, 'dpop');

    // Concurrent authenticated HTTP calls within 60s skew share ONE renewal lock
    await Promise.all([
      client.pullRequestDiff({ number: 1 }),
      client.pullRequestDiff({ number: 2 })
    ]);
    assert.equal(tokenCounter, 2, 'concurrent renewals must deduplicate under per-connection lock');
    assert.equal(stored.token, 'DPOP_FRESH_2');
    const diffReqs = requests.filter((r) => r.url.endsWith('/api/pull-requests/diff'));
    assert.equal(diffReqs.length, 2);
    for (const req of diffReqs) {
      assert.equal(req.args.header.Authorization, 'DPoP DPOP_FRESH_2');
      assert.equal(req.args.header.DPoP, 'proof:POST:https://test/api/pull-requests/diff:DPOP_FRESH_2');
    }
  } finally {
    client.disconnect();
  }
});

test('direct DPoP retries once on 401 for websocket-ticket and HTTP requests, handles 404 ticket fallback, and avoids loops', async () => {
  let tokenCounter = 0;
  let ticketAttempts = 0;
  let diffAttempts = 0;
  let stored = {
    base: 'https://test',
    environmentId: 'env',
    token: 'DPOP_STALE_CLOCK',
    expiresAt: Date.now() + 3600000,
    kind: 'dpop'
  };
  const { client, socketConnects } = await setup({
    descriptorCapabilities: { accessTokenRenewal: true },
    dpopSigner: {
      async prove(method, target, accessToken) {
        return `proof:${method}:${target}:${accessToken ?? ''}`;
      }
    },
    onTokenRequest: (_url, args) => {
      tokenCounter++;
      const subject = new URLSearchParams(args.extraData).get('subject_token');
      if (tokenCounter === 1) {
        assert.equal(subject, 'DPOP_STALE_CLOCK');
        return { status: 200, value: { access_token: 'DPOP_AFTER_WS_401', token_type: 'DPoP', expires_in: 3600 } };
      }
      if (tokenCounter === 2) {
        assert.equal(subject, 'DPOP_AFTER_WS_401');
        return { status: 200, value: { access_token: 'DPOP_AFTER_HTTP_401', token_type: 'DPoP', expires_in: 3600 } };
      }
      assert.equal(subject, 'DPOP_AFTER_HTTP_401');
      return { status: 200, value: { access_token: 'DPOP_STILL_REJECTED', token_type: 'DPoP', expires_in: 3600 } };
    },
    onTicketRequest: (url, args) => {
      ticketAttempts++;
      if (ticketAttempts === 1) {
        assert.equal(args.header.Authorization, 'DPoP DPOP_STALE_CLOCK');
        return { status: 401, value: { error: 'invalid_credential' } };
      }
      if (ticketAttempts === 2) {
        assert.equal(url, 'https://test/api/auth/websocket-ticket/rpc');
        assert.equal(args.header.Authorization, 'DPoP DPOP_AFTER_WS_401');
        return { status: 404, value: { error: 'not_found' } };
      }
      assert.equal(url, 'https://test/api/auth/websocket-ticket');
      assert.equal(args.header.Authorization, 'DPoP DPOP_AFTER_WS_401');
      assert.equal(args.header.DPoP, 'proof:POST:https://test/api/auth/websocket-ticket:DPOP_AFTER_WS_401');
      return { status: 200, value: { ticket: 'FALLBACK_TICKET' } };
    },
    onDiffRequest: (_url, args) => {
      diffAttempts++;
      if (diffAttempts === 1) {
        assert.equal(args.header.Authorization, 'DPoP DPOP_AFTER_WS_401');
        return { status: 401, value: { error: 'invalid_credential' } };
      }
      if (diffAttempts === 2) {
        assert.equal(args.header.Authorization, 'DPoP DPOP_AFTER_HTTP_401');
        assert.equal(args.header.DPoP, 'proof:POST:https://test/api/pull-requests/diff:DPOP_AFTER_HTTP_401');
        return { status: 200, value: { diff: 'ok-after-retry' } };
      }
      // Persistent 401 on subsequent call must fail after exactly one renewal + one retry
      return { status: 401, value: { error: 'revoked' } };
    }
  });
  client.store = {
    async load() { return structuredClone(stored); },
    async save(v) { stored = structuredClone(v); },
    async clear() { stored = undefined; }
  };
  try {
    await client.connect('https://test');
    assert.equal(client.ready, true);
    assert.equal(tokenCounter, 1);
    assert.equal(ticketAttempts, 3);
    assert.equal(stored.token, 'DPOP_AFTER_WS_401');
    assert.equal(new URL(socketConnects[0].url).searchParams.get('dpop'), 'proof:GET:https://test/ws:FALLBACK_TICKET');

    const res = await client.pullRequestDiff({ number: 7 });
    assert.deepEqual(res, { diff: 'ok-after-retry' });
    assert.equal(tokenCounter, 2);
    assert.equal(stored.token, 'DPOP_AFTER_HTTP_401');

    // Persistent 401: renews once (tokenCounter 2 -> 3), retries once (diffAttempts 2 -> 4), then throws
    await assert.rejects(() => client.pullRequestDiff({ number: 8 }), /鉴权失败/);
    assert.equal(tokenCounter, 3);
    assert.equal(diffAttempts, 4);
  } finally {
    client.disconnect();
  }
});

test('legacy Bearer saved sessions keep working without DPoP and reject expiry as before', async () => {
  let signerUsed = 0;
  let stored = {
    base: 'https://test',
    environmentId: 'env',
    token: 'LEGACY_BEARER_TOK',
    expiresAt: Date.now() + 3600000
  };
  const { client, requests, socketConnects } = await setup({
    descriptorCapabilities: { accessTokenRenewal: true },
    dpopSigner: {
      async prove() { signerUsed++; return 'unused'; }
    }
  });
  client.store = {
    async load() { return structuredClone(stored); },
    async save(v) { stored = structuredClone(v); },
    async clear() { stored = undefined; }
  };
  try {
    await client.connect('https://test');
    assert.equal(client.ready, true);
    assert.equal(signerUsed, 0);
    const ticketReq = requests.find((r) => r.url.includes('/api/auth/websocket-ticket'));
    assert.equal(ticketReq.args.header.Authorization, 'Bearer LEGACY_BEARER_TOK');
    assert.equal(ticketReq.args.header.DPoP, undefined);
    assert.equal(new URL(socketConnects[0].url).searchParams.get('dpop'), null);

    client.disconnect();
    stored.expiresAt = Date.now() - 1000;
    await client.connect('https://test');
    assert.equal(client.ready, false);
    assert.match(client.status, /没有此服务器的有效会话/);
  } finally {
    client.disconnect();
  }
});

test('C1: launch, send, queued send-now/resume and steer replay with the same commandId after socket drop', async () => {
  const cases = [
    {
      name: 'new thread first message (launchThread)',
      matchTag: 'orchestration.launchThread',
      run: (client) => client.launch('project', 'first message', taskSettings)
    },
    {
      name: 'follow-up message (message.dispatch)',
      matchTag: 'orchestration.dispatchCommand',
      matchType: 'message.dispatch',
      prepare: async (client) => { await client.watch('t-c1'); await new Promise(setImmediate); },
      run: (client) => client.send('follow-up')
    },
    {
      name: 'queued send-now (queued-run.start)',
      matchTag: 'orchestration.dispatchCommand',
      matchType: 'queued-run.start',
      prepare: async (client) => {
        await client.watch('t-c1'); await new Promise(setImmediate);
        client.thread.runs = [{ id: 'run-q1', status: 'queued', queuePosition: 0 }];
      },
      run: (client) => client.queue('start', 'run-q1')
    },
    {
      name: 'queued resume (queue.resume)',
      matchTag: 'orchestration.dispatchCommand',
      matchType: 'queue.resume',
      prepare: async (client) => {
        await client.watch('t-c1'); await new Promise(setImmediate);
        client.thread.runs = [{ id: 'run-q1', status: 'queued', queueHeld: true }];
      },
      run: (client) => client.queue('resume')
    },
    {
      name: 'queued steer (queued-message.promote-to-steer)',
      matchTag: 'orchestration.dispatchCommand',
      matchType: 'queued-message.promote-to-steer',
      prepare: async (client) => {
        await client.watch('t-c1'); await new Promise(setImmediate);
        client.thread.runs = [
          { id: 'run-active', status: 'running' },
          { id: 'run-q1', status: 'queued' }
        ];
      },
      run: (client) => client.promoteQueued('run-q1')
    }
  ];

  // Test both server-never-received and server-already-processed (idempotent receipt replay)
  for (const serverProcessedFirst of [false, true]) {
    for (const tc of cases) {
      const seenCommandIds = [];
      const appliedReceipts = new Map();
      let stored = { base: 'https://test', environmentId: 'env', token: 'SYNTHETIC_TOKEN', expiresAt: Date.now() + 60000 };
      const { client, socketConnects } = await setup({
        providers: taskProviders,
        recoveryStore: memoryRecovery(),
        onRequest(frame, sock) {
          if (frame.tag !== tc.matchTag) return;
          if (tc.matchType && frame.payload?.type !== tc.matchType) return;
          const cmdId = frame.payload.commandId;
          seenCommandIds.push(cmdId);
          if (seenCommandIds.length === 1) {
            if (serverProcessedFirst) {
              const receipt = tc.matchTag === 'orchestration.launchThread'
                ? { threadId: frame.payload.threadId, projection: {}, resumed: false }
                : { sequence: 42 };
              appliedReceipts.set(cmdId, receipt);
            }
            // Socket drops before Exit reaches client; auto-reconnect should replay with same commandId
            sock.emitClose({ code: 1006, reason: 'network drop' });
            return 'handled';
          }
          // Second attempt after reconnect
          if (appliedReceipts.has(cmdId)) {
            sock.emit({ _tag: 'Exit', requestId: frame.id, exit: { _tag: 'Success', value: appliedReceipts.get(cmdId) } });
            return 'handled';
          }
          const result = tc.matchTag === 'orchestration.launchThread'
            ? { threadId: frame.payload.threadId, projection: {}, resumed: false }
            : { sequence: 43 };
          appliedReceipts.set(cmdId, result);
          sock.emit({ _tag: 'Exit', requestId: frame.id, exit: { _tag: 'Success', value: result } });
          return 'handled';
        }
      });
      client.store = {
        async load() { return structuredClone(stored); },
        async save(v) { stored = structuredClone(v); },
        async clear() { stored = undefined; }
      };
      try {
        await client.connect('https://test', 'synthetic');
        await new Promise(setImmediate);
        if (tc.prepare) await tc.prepare(client);
        const socketsBefore = socketConnects.length;
        await tc.run(client);
        assert.equal(seenCommandIds.length, 2, `${tc.name} (processedFirst=${serverProcessedFirst}): must replay once`);
        assert.equal(seenCommandIds[0], seenCommandIds[1], `${tc.name}: commandId must stay identical across replay`);
        assert.equal(appliedReceipts.size, 1, `${tc.name}: server must apply command exactly once`);
        assert.ok(socketConnects.length > socketsBefore, `${tc.name}: must have reconnected`);
        assert.equal(client.recovery.pendingId, '', `${tc.name}: pending recovery cleared after confirmation`);
      } finally {
        client.disconnect();
      }
    }
  }
});

test('C1: known server refusal does not resend and resend cap stops after 2 socket-loss retries', async () => {
  // 1. Known server refusal on launchThread must NOT resend
  let launchAttempts = 0;
  const refused = await setup({
    providers: taskProviders,
    recoveryStore: memoryRecovery(),
    onRequest(frame, sock) {
      if (frame.tag !== 'orchestration.launchThread') return;
      launchAttempts++;
      sock.emit({
        _tag: 'Exit',
        requestId: frame.id,
        exit: { _tag: 'Failure', cause: { reasons: [{ _tag: 'Fail', error: { _tag: 'Refused' } }] } }
      });
      return 'handled';
    }
  });
  try {
    await refused.client.connect('https://test', 'synthetic');
    await assert.rejects(() => refused.client.launch('project', 'bad', taskSettings));
    assert.equal(launchAttempts, 1, 'known refusal must not resend');
    assert.equal(refused.client.recovery, undefined, 'known launch refusal clears provisional recovery');
  } finally {
    refused.client.disconnect();
  }

  // 2. Poison-pill cap: drops on all 3 attempts (initial + 2 resends) then fails and preserves unknown recovery
  const capCommandIds = [];
  let stored = { base: 'https://test', environmentId: 'env', token: 'SYNTHETIC_TOKEN', expiresAt: Date.now() + 60000 };
  const capped = await setup({
    providers: taskProviders,
    recoveryStore: memoryRecovery(),
    onRequest(frame, sock) {
      if (frame.tag !== 'orchestration.dispatchCommand' || frame.payload?.type !== 'message.dispatch') return;
      capCommandIds.push(frame.payload.commandId);
      sock.emitClose({ code: 1006, reason: 'poison drop' });
      return 'handled';
    }
  });
  capped.client.store = {
    async load() { return structuredClone(stored); },
    async save(v) { stored = structuredClone(v); },
    async clear() { stored = undefined; }
  };
  try {
    await capped.client.connect('https://test', 'synthetic');
    await capped.client.watch('t-cap');
    await new Promise(setImmediate);
    // Speed up reconnect retries for test by calling connect when retry schedules
    const origRetry = capped.client.retry.bind(capped.client);
    capped.client.retry = () => {
      origRetry(10);
    };
    await assert.rejects(() => capped.client.send('poison'));
    assert.equal(capCommandIds.length, 3, 'must try initial + 2 resends then stop');
    assert.equal(new Set(capCommandIds).size, 1, 'all 3 attempts share one commandId');
    assert.ok(capped.client.recovery.pendingId, 'unconfirmed command keeps recovery protection');
  } finally {
    capped.client.disconnect();
  }
});

test('C2: incompatible initial server config stops session without auto-reconnect and allows manual retry', async () => {
  let badConfig = true;
  let stored = { base: 'https://test', environmentId: 'env', token: 'SYNTHETIC_TOKEN', expiresAt: Date.now() + 60000 };
  const { client, frames } = await setup({
    onRequest(frame, sock) {
      if (frame.tag !== 'subscribeServerConfig') return;
      if (badConfig) {
        sock.emit({
          _tag: 'Chunk',
          requestId: frame.id,
          values: [{ version: 1, type: 'snapshot', config: { environment: { environmentId: 'env' }, cwd: 42 } }]
        });
        return 'handled';
      }
      // Minimal config missing optional fields (cwd, settings, capabilities, providers) must succeed (P0-2)
      sock.emit({
        _tag: 'Chunk',
        requestId: frame.id,
        values: [{ version: 1, type: 'snapshot', config: { environment: { environmentId: 'env' }, unknownFutureField: { x: 1 } } }]
      });
      return 'handled';
    }
  });
  client.store = {
    async load() { return structuredClone(stored); },
    async save(v) { stored = structuredClone(v); },
    async clear() { stored = undefined; }
  };
  try {
    await client.connect('https://test', 'synthetic');
    assert.equal(client.ready, false);
    assert.equal(client.reconnectPending, false, 'incompatible config must stop auto-reconnect');
    assert.match(client.status, /不兼容/);
    assert.equal(frames.some((f) => f.tag === 'server.getConfig'), false, 'must not fall back to server.getConfig on decode error');

    // Manual retry succeeds once server config is compatible (even with optional fields absent)
    badConfig = false;
    await client.connect('https://test', 'synthetic');
    assert.equal(client.ready, true);
  } finally {
    client.disconnect();
  }

  // Legacy server.getConfig fallback with unreadable critical config also blocks without reconnect storm
  const legacyBad = await setup({
    rejectSubscribeConfig: true,
    onRequest(frame, sock) {
      if (frame.tag !== 'server.getConfig') return;
      sock.emit({ _tag: 'Exit', requestId: frame.id, exit: { _tag: 'Success', value: { environment: { environmentId: 'env' }, settings: 'invalid-string' } } });
      return 'handled';
    }
  });
  legacyBad.client.store = {
    async load() { return structuredClone(stored); },
    async save(v) { stored = structuredClone(v); },
    async clear() { stored = undefined; }
  };
  try {
    await legacyBad.client.connect('https://test', 'synthetic');
    assert.equal(legacyBad.client.ready, false);
    assert.equal(legacyBad.client.reconnectPending, false);
    assert.match(legacyBad.client.status, /不兼容/);
  } finally {
    legacyBad.client.disconnect();
  }
});

test('C2: unreadable later config update or server-ended config stream terminates session for reconnect', async () => {
  // 1. Unreadable later update ends established session with transient reconnect
  let stored = { base: 'https://test', environmentId: 'env', token: 'SYNTHETIC_TOKEN', expiresAt: Date.now() + 60000 };
  const s1 = await setup();
  s1.client.store = {
    async load() { return structuredClone(stored); },
    async save(v) { stored = structuredClone(v); },
    async clear() { stored = undefined; }
  };
  try {
    await s1.client.connect('https://test', 'synthetic');
    assert.equal(s1.client.ready, true);
    const sub = s1.frames.find((f) => f.tag === 'subscribeServerConfig');
    s1.socket().emit({
      _tag: 'Chunk',
      requestId: sub.id,
      values: [{ version: 1, type: 'snapshot', config: { environment: { environmentId: 'env' }, cwd: 42 } }]
    });
    assert.equal(s1.client.ready, false, 'later unreadable config update must end session');
    assert.equal(s1.client.reconnectPending, true, 'later unreadable update triggers transient reconnect');
    assert.match(s1.client.status, /无法读取的服务器配置更新/);
  } finally {
    s1.client.disconnect();
  }

  // 2. Server interrupts/closes config stream after readiness -> ends session for reconnect
  const s2 = await setup();
  s2.client.store = {
    async load() { return structuredClone(stored); },
    async save(v) { stored = structuredClone(v); },
    async clear() { stored = undefined; }
  };
  try {
    await s2.client.connect('https://test', 'synthetic');
    assert.equal(s2.client.ready, true);
    const sub = s2.frames.find((f) => f.tag === 'subscribeServerConfig');
    s2.socket().emit({ _tag: 'Exit', requestId: sub.id, exit: { _tag: 'Success', value: null } });
    await new Promise(setImmediate);
    assert.equal(s2.client.ready, false, 'server-ended config stream must end session');
    assert.equal(s2.client.reconnectPending, true, 'server-ended config stream triggers reconnect');
  } finally {
    s2.client.disconnect();
  }
});

test('C3: reconnect loop survives unexpected exceptions in store, reconnectSavedRoutes, onUpdate, resume, and stops on non-recoverable auth/identity errors', async () => {
  // 1. Unexpected store.load() throw and onUpdate() throw must not kill the retry loop
  let loadCount = 0;
  let stored = { base: 'https://test', environmentId: 'env', token: 'SYNTHETIC_TOKEN', expiresAt: Date.now() + 60000 };
  const s1 = await setup();
  s1.client.store = {
    async load() {
      loadCount++;
      if (loadCount === 2) throw new Error('unexpected keystore glitch');
      return structuredClone(stored);
    },
    async save(v) { stored = structuredClone(v); },
    async clear() { stored = undefined; }
  };
  try {
    await s1.client.connect('https://test', 'synthetic');
    assert.equal(s1.client.ready, true);
    const origRetry = s1.client.retry.bind(s1.client);
    s1.client.retry = () => origRetry(15);

    // Inject defect in onUpdate during disconnect
    let threwUpdate = false;
    s1.client.onUpdate = () => {
      if (!threwUpdate) { threwUpdate = true; throw new Error('UI callback exploded'); }
    };
    s1.socket().emitClose({ code: 1006, reason: 'drop' });
    assert.equal(s1.client.ready, false);
    assert.equal(s1.client.reconnectPending, true, 'onUpdate defect must not prevent scheduling retry');

    // Retry 1 hits unexpected store.load() throw -> loop reschedules -> Retry 2 succeeds!
    await new Promise((r) => setTimeout(r, 120));
    assert.ok(loadCount >= 3, 'loop must retry past unexpected store error, loadCount=' + loadCount);
    assert.equal(s1.client.ready, true, 'client must recover automatically after unexpected defect');
  } finally {
    s1.client.disconnect();
  }

  // 2. reconnectSavedRoutes unexpected error keeps retrying; non-recoverable identity/auth error stops loop
  const s2 = await setup();
  let routeCalls = 0;
  try {
    await s2.client.connect('https://test', 'synthetic');
    const origRetry = s2.client.retry.bind(s2.client);
    s2.client.retry = () => origRetry(15);
    s2.client.reconnectSavedRoutes = async () => {
      routeCalls++;
      if (routeCalls === 1) throw new TypeError('unexpected route defect');
      if (routeCalls === 2) throw new Error('服务器身份已变化，未发送配对凭据');
    };
    s2.client.disconnect('网络波动', true, false);
    await new Promise((r) => setTimeout(r, 100));
    assert.equal(routeCalls, 2, 'must retry after unexpected defect and stop after non-recoverable identity error');
    assert.equal(s2.client.reconnectPending, false, 'non-recoverable error must stop retry loop');
    assert.match(s2.client.status, /服务器身份/);
  } finally {
    s2.client.disconnect();
  }

  // 3. resume() unexpected failure still schedules retry instead of dying
  const s3 = await setup();
  let resumeLoads = 0;
  s3.client.store = {
    async load() {
      resumeLoads++;
      if (resumeLoads === 2) throw new Error('unexpected resume failure');
      return structuredClone(stored);
    },
    async save(v) { stored = structuredClone(v); },
    async clear() { stored = undefined; }
  };
  try {
    await s3.client.connect('https://test', 'synthetic');
    const origRetry = s3.client.retry.bind(s3.client);
    s3.client.retry = () => origRetry(15);
    s3.client.suspend();
    await s3.client.resume(0);
    assert.equal(s3.client.reconnectPending, true, 'resume unexpected failure must schedule backoff retry');
    await new Promise((r) => setTimeout(r, 80));
    assert.equal(s3.client.ready, true, 'subsequent retry after resume defect must succeed');
  } finally {
    s3.client.disconnect();
  }

  // 4. Heartbeat timer survives an unexpected sync throw from rpc.ping()
  const s4 = await setup();
  const realSetInterval = globalThis.setInterval;
  const realClearInterval = globalThis.clearInterval;
  let capturedTick = null;
  let cleared = false;
  globalThis.setInterval = (fn) => { capturedTick = fn; return 99999; };
  globalThis.clearInterval = (id) => { if (id === 99999) cleared = true; else realClearInterval(id); };
  try {
    await s4.client.connect('https://test', 'synthetic');
    assert.equal(typeof capturedTick, 'function');
    let pings = 0;
    s4.client.rpc.ping = () => {
      pings++;
      if (pings === 1) throw new Error('unexpected ping defect');
    };
    capturedTick();
    capturedTick();
    assert.equal(pings, 2, 'heartbeat must keep ticking after an unexpected exception');
    assert.equal(cleared, false, 'heartbeat timer must not be cleared on defect');
  } finally {
    globalThis.setInterval = realSetInterval;
    globalThis.clearInterval = realClearInterval;
    s4.client.disconnect();
  }
});

test('C4: failed resumed subscribeThread reloads full snapshot without blanking cached messages', async () => {
  let subAttempt = 0;
  const seenAfterSequences = [];
  const cachedMsg = { id: 'm1', threadId: 't-c4', role: 'user', text: 'cached hello', streaming: false };
  const reloadedMsg = { id: 'm2', threadId: 't-c4', role: 'assistant', text: 'reloaded reply', streaming: false };
  const s = await setup({
    onSubscribeThread: (frame, sock) => {
      subAttempt++;
      seenAfterSequences.push(frame.payload.afterSequence);
      if (subAttempt === 1) {
        sock.emit({
          _tag: 'Chunk',
          requestId: frame.id,
          values: [
            { kind: 'snapshot', snapshotSequence: 10, projection: { thread: { id: 't-c4', title: 'Initial' }, messages: [cachedMsg] } },
            { kind: 'synchronized' }
          ]
        });
      } else if (subAttempt === 2) {
        // Resumed replay hits a decode defect (wrong threadId event).
        sock.emit({
          _tag: 'Chunk',
          requestId: frame.id,
          values: [{ kind: 'event', sequence: 11, event: { threadId: 'wrong-thread', type: 'message.updated', payload: {} } }]
        });
      } else if (subAttempt === 3) {
        // First full snapshot reload also hits a decode defect -> should back off and show sync error while keeping cache.
        sock.emit({
          _tag: 'Chunk',
          requestId: frame.id,
          values: [{ kind: 'snapshot', snapshotSequence: -1, projection: {} }]
        });
      } else if (subAttempt === 4) {
        // Backed-off retry delivers valid full snapshot at sequence 15.
        sock.emit({
          _tag: 'Chunk',
          requestId: frame.id,
          values: [
            { kind: 'snapshot', snapshotSequence: 15, projection: { thread: { id: 't-c4', title: 'Reloaded' }, messages: [cachedMsg, reloadedMsg] } },
            { kind: 'synchronized' }
          ]
        });
      } else if (subAttempt === 5) {
        // Subsequent resumed replay after recovery gets a known server rejection -> falls back immediately without afterSequence.
        sock.emit({ _tag: 'Exit', requestId: frame.id, exit: { _tag: 'Failure', cause: { _tag: 'Fail', error: { message: 'cursor expired' } } } });
      } else {
        sock.emit({
          _tag: 'Chunk',
          requestId: frame.id,
          values: [
            { kind: 'snapshot', snapshotSequence: 18, projection: { thread: { id: 't-c4', title: 'RecoveredAgain' }, messages: [cachedMsg, reloadedMsg] } },
            { kind: 'synchronized' }
          ]
        });
      }
    }
  });
  let stored = { base: 'https://test', environmentId: 'env', token: 'SYNTHETIC_TOKEN', expiresAt: Date.now() + 60000 };
  s.client.store = { async load() { return structuredClone(stored); }, async save(v) { stored = structuredClone(v); }, async clear() {} };
  try {
    await s.client.connect('https://test', 'synthetic');
    await new Promise(setImmediate);
    await s.client.watch('t-c4');
    await new Promise(setImmediate);
    assert.equal(subAttempt, 1);
    assert.equal(seenAfterSequences[0], undefined);
    assert.deepEqual(s.client.thread.messages.map((m) => m.id), ['m1']);

    // Speed up backoff so attempt 4 runs promptly while still distinguishing immediate attempt 3 vs backed-off attempt 4.
    const origSchedule = s.client.scheduleThreadResubscribe.bind(s.client);
    let backoffCount = 0;
    s.client.scheduleThreadResubscribe = (threadId, generation) => {
      backoffCount++;
      s.client.threadRetryDelay = 40;
      origSchedule(threadId, generation);
    };

    // Disconnect and reconnect -> attempt 2 sends afterSequence: 10, fails decode -> attempt 3 fires immediately without afterSequence
    // -> attempt 3 fails decode -> keeps cached message, sets threadSyncError, schedules backoff attempt 4 without afterSequence.
    s.client.disconnect('网络抖动', false, false);
    await s.client.connect('https://test', '');
    await new Promise((r) => setTimeout(r, 15));

    assert.equal(seenAfterSequences[1], 10, 'resumed subscribe must send cached afterSequence');
    assert.equal(seenAfterSequences[2], undefined, 'failed resumed replay must fall back immediately without afterSequence');
    assert.equal(backoffCount, 1, 'only failed full-snapshot reload should back off');
    assert.equal(s.client.threadSyncError, '无法同步消息', 'failed full reload must expose sync error');
    assert.deepEqual(s.client.thread.messages.map((m) => m.id), ['m1'], 'cached messages must remain visible during failed reload');

    // Wait for backed-off attempt 4 -> full snapshot without afterSequence succeeds and clears error
    await new Promise((r) => setTimeout(r, 90));
    assert.equal(subAttempt, 4);
    assert.equal(seenAfterSequences[3], undefined, 'backed-off retry must still request full snapshot');
    assert.equal(s.client.threadSyncError, '', 'successful snapshot must clear sync error');
    assert.equal(s.client.thread.cursor, 15);
    assert.deepEqual(s.client.thread.messages.map((m) => m.id), ['m1', 'm2']);

    // Next reconnect resumes from new sequence 15 -> attempt 5 gets known RPC failure -> falls back immediately to attempt 6 without afterSequence
    s.client.disconnect('再次抖动', false, false);
    await s.client.connect('https://test', '');
    await new Promise((r) => setTimeout(r, 30));
    assert.equal(seenAfterSequences[4], 15, 'after recovery, next reconnect must resume from updated sequence');
    assert.equal(seenAfterSequences[5], undefined, 'rejected resumed subscribe must immediately fall back to full snapshot');
    assert.equal(s.client.thread.cursor, 18);
    assert.deepEqual(s.client.thread.messages.map((m) => m.id), ['m1', 'm2']);
  } finally {
    s.client.disconnect();
  }
});

test('C5: resumeLatestRun dispatches fallback continuation text for compatibility with older servers', async () => {
  const s = await setup();
  try {
    await s.client.connect('https://test', 'synthetic');
    await new Promise(setImmediate);
    await s.client.watch('t-c5');
    await new Promise(setImmediate);
    s.client.thread.runs = [{ id: 'run-interrupted', status: 'interrupted', ordinal: 1, startedAt: '2026-01-01T00:00:00Z', completedAt: '2026-01-01T00:01:00Z' }];
    await s.client.resumeLatestRun();
    const dispatch = s.frames.filter((f) => f.tag === 'orchestration.dispatchCommand').at(-1);
    assert.ok(dispatch);
    assert.equal(dispatch.payload.type, 'message.dispatch');
    assert.equal(dispatch.payload.manualContinuationOfRunId, 'run-interrupted');
    assert.equal(dispatch.payload.text, 'Continue where you left off.');
    assert.deepEqual(dispatch.payload.dispatchMode, { type: 'start_immediately' });
  } finally {
    s.client.disconnect();
  }
});

test('U1: T3Client tracks attempts and blocks resumeLatestRun when provider lacks native resume on delivered turn', async () => {
  const s = await setup({
    onSubscribeThread: (frame, sock) => {
      sock.emit({
        _tag: 'Chunk',
        requestId: frame.id,
        values: [{
          kind: 'snapshot',
          snapshotSequence: 10,
          projection: {
            thread: { id: frame.payload.threadId },
            messages: [],
            runs: [{ id: 'run-stop', status: 'interrupted', ordinal: 1, startedAt: '2026-01-01T00:00:00Z', completedAt: '2026-01-01T00:01:00Z', providerThreadId: 'pt-1', providerInstanceId: 'pi-1' }],
            attempts: [{ id: 'att-1', runId: 'run-stop', attemptOrdinal: 1, reason: 'initial' }],
            providerTurns: [{ id: 'turn-1', runAttemptId: 'att-1' }],
            providerThreads: [{ id: 'pt-1', providerSessionId: 'ps-1' }],
            providerSessions: [{ id: 'ps-1', providerInstanceId: 'pi-1', capabilities: { turns: { supportsNativeResume: false } } }]
          }
        }]
      });
    }
  });
  try {
    await s.client.connect('https://test', 'synthetic');
    await new Promise(setImmediate);
    await s.client.watch('t-u1');
    await new Promise(setImmediate);
    assert.equal(s.client.thread.attempts.length, 1);
    assert.equal(s.client.resumableRunId(), '');
    await assert.rejects(() => s.client.resumeLatestRun(), /不支持恢复/);

    // Receiving a run-attempt.created event for a later steering_restart makes it resumable again.
    s.client.thread.apply({
      kind: 'event',
      sequence: 11,
      event: {
        threadId: 't-u1',
        type: 'run-attempt.created',
        payload: { id: 'att-2', runId: 'run-stop', attemptOrdinal: 2, reason: 'steering_restart' }
      }
    });
    assert.equal(s.client.resumableRunId(), 'run-stop');
    await s.client.resumeLatestRun();
    const dispatch = s.frames.filter((f) => f.tag === 'orchestration.dispatchCommand').at(-1);
    assert.equal(dispatch.payload.manualContinuationOfRunId, 'run-stop');
  } finally {
    s.client.disconnect();
  }
});

test('M1: T3Client calls workspace.listFolders, workspace.scanFolders, workspace.taskFolder, workspace.addTaskFolderRepository and forwards launch repositories', async () => {
  const s = await setup({
    onRequest: (frame, sock) => {
      if (frame.tag === 'workspace.listFolders') {
        sock.emit({ _tag: 'Exit', requestId: frame.id, exit: { _tag: 'Success', value: { folders: [
          { name: 'api', path: '/work/hub/api', state: 'git', discovered: true },
          { name: 'web', path: '/work/web', state: 'git' }
        ] } } });
        return 'handled';
      }
      if (frame.tag === 'workspace.scanFolders') {
        sock.emit({ _tag: 'Exit', requestId: frame.id, exit: { _tag: 'Success', value: {
          workspaceRoot: '/work/hub', isGitRepository: false, codeWorkspaceFile: null,
          folders: [{ path: '/work/hub/api', name: 'api', isGitRepository: true, source: 'child' }]
        } } });
        return 'handled';
      }
      if (frame.tag === 'workspace.taskFolder') {
        sock.emit({ _tag: 'Exit', requestId: frame.id, exit: { _tag: 'Success', value: {
          taskFolder: {
            root: '/tmp/wt/t1', projectId: 'proj-multi', projectRoot: '/work/hub', anchor: '/work',
            projectPath: '/tmp/wt/t1/hub', projectIsWorktree: false,
            repositories: [{ repositoryPath: '/work/hub/api', worktreePath: '/tmp/wt/t1/hub/api', name: 'api' }]
          }
        } } });
        return 'handled';
      }
      if (frame.tag === 'workspace.addTaskFolderRepository') {
        sock.emit({ _tag: 'Exit', requestId: frame.id, exit: { _tag: 'Success', value: {
          root: '/tmp/wt/t1', projectId: 'proj-multi', projectRoot: '/work/hub', anchor: '/work',
          projectPath: '/tmp/wt/t1/hub', projectIsWorktree: false,
          repositories: [
            { repositoryPath: '/work/hub/api', worktreePath: '/tmp/wt/t1/hub/api', name: 'api' },
            { repositoryPath: '/work/web', worktreePath: '/tmp/wt/t1/web', name: 'web' }
          ]
        } } });
        return 'handled';
      }
      return undefined;
    },
    providers: [{ instanceId: 'codex', driver: 'codex', enabled: true, installed: true, models: [{ slug: 'gpt-5', name: 'GPT-5' }] }]
  });
  try {
    await s.client.connect('https://test', 'synthetic');
    await new Promise(setImmediate);
    const folders = await s.client.listWorkspaceFolders('proj-multi');
    assert.equal(folders.length, 2);
    const scan = await s.client.scanWorkspaceFolders('/work/hub');
    assert.equal(scan.isGitRepository, false);
    const tf = await s.client.getTaskFolder('/tmp/wt/t1/hub');
    assert.equal(tf.repositories.length, 1);
    const updated = await s.client.addTaskFolderRepository('t-1', '/work/web');
    assert.equal(updated.repositories.length, 2);

    await s.client.launch(
      'proj-multi',
      'Inspect repos',
      { modelSelection: { instanceId: 'codex', model: 'gpt-5' }, runtimeMode: 'approval-required', interactionMode: 'default' },
      { mode: 'worktree', branch: '', worktreePath: '', startFromOrigin: true, repositories: ['/work/hub/api'] },
      [],
      false
    );
    const launchFrame = s.frames.find((f) => f.tag === 'orchestration.launchThread');
    assert.deepEqual(launchFrame.payload.workspaceStrategy, {
      type: 'worktree',
      baseRef: 'HEAD',
      startFromOrigin: true,
      repositories: [{ path: '/work/hub/api' }]
    });
  } finally {
    s.client.disconnect();
  }
});

test('L1: T3Client reads peerLinks.names, subscribes linked thread stream, paginates history/items, and surfaces PeerLinkThreadReadError', async () => {
  const { linkedThreadFailure } = await import(linkedThreadUrl);
  const s = await setup({
    onRequest: (value, sock) => {
      if (value.tag === 'subscribeServerConfig') {
        sock.emit({
          _tag: 'Chunk',
          requestId: value.id,
          values: [{
            version: 1,
            type: 'snapshot',
            config: {
              environment: { environmentId: 'env', capabilities: { peerLinks: true } },
              settings: { linkedEnvironmentsEnabled: true },
              providers: []
            }
          }]
        });
        return 'handled';
      }
      if (value.tag === 'peerLinks.names') {
        sock.emit({ _tag: 'Exit', requestId: value.id, exit: { _tag: 'Success', value: { links: [{ environmentId: 'env-b', label: 'Machine B' }] } } });
        return 'handled';
      }
      if (value.tag === 'peerLinks.subscribeThread') {
        if (value.payload.threadId === 'forbidden-thread') {
          sock.emit({
            _tag: 'Exit',
            requestId: value.id,
            exit: {
              _tag: 'Failure',
              cause: {
                _id: 'Cause',
                reasons: [{ _tag: 'Fail', error: { _tag: 'PeerLinkThreadReadError', reason: 'rejected', label: 'Machine B', message: 'read refused' } }]
              }
            }
          });
          return 'handled';
        }
        sock.emit({
          _tag: 'Chunk',
          requestId: value.id,
          values: [{
            kind: 'snapshot',
            snapshotSequence: 5,
            hasMoreHistory: true,
            historyCursor: 'cur-1',
            projection: {
              thread: { id: value.payload.threadId, title: 'Remote Task' },
              messages: [{ id: 'm1', threadId: value.payload.threadId, role: 'assistant', text: 'Hello from B', streaming: false }]
            }
          }]
        });
        return 'handled';
      }
      if (value.tag === 'peerLinks.threadHistoryPage') {
        sock.emit({
          _tag: 'Exit',
          requestId: value.id,
          exit: {
            _tag: 'Success',
            value: {
              items: [{ item: { id: 'it-0', type: 'user_message', messageId: 'm0', text: 'Earlier prompt' }, visibility: 'visible' }],
              nextCursor: null,
              hasMoreHistory: false
            }
          }
        });
        return 'handled';
      }
      if (value.tag === 'peerLinks.threadItem') {
        sock.emit({
          _tag: 'Exit',
          requestId: value.id,
          exit: { _tag: 'Success', value: { item: { id: value.payload.itemId, type: 'command_execution', output: 'full output' } } }
        });
        return 'handled';
      }
      return undefined;
    }
  });
  try {
    await s.client.connect('https://test', 'CODE');
    assert.equal(s.client.linkedEnvironmentsEnabled(), true);
    const names = await s.client.peerLinkNames();
    assert.deepEqual(names, [{ environmentId: 'env-b', label: 'Machine B' }]);
    assert.equal(s.client.peerLinkLabel('env-b'), 'Machine B');

    const received = [];
    const cancel = s.client.subscribeLinkedThread('env-b', 'thr-b', (frame) => received.push(frame), () => {}, () => {});
    await new Promise((r) => setTimeout(r, 30));
    assert.equal(received.length, 1);
    assert.equal(received[0].kind, 'snapshot');
    cancel();
    assert.ok(s.frames.some((f) => f._tag === 'Interrupt'));

    const page = await s.client.linkedThreadHistoryPage('env-b', 'thr-b', 'cur-1');
    assert.equal(page.hasMoreHistory, false);
    assert.equal(page.items[0].messageId, 'm0');

    const detail = await s.client.linkedThreadItem('env-b', 'thr-b', 'item-9');
    assert.equal(detail.output, 'full output');

    let readErr;
    s.client.subscribeLinkedThread('env-b', 'forbidden-thread', () => {}, () => {}, (err) => { readErr = err; });
    await new Promise((r) => setTimeout(r, 30));
    const failure = linkedThreadFailure(readErr, 'Fallback');
    assert.equal(failure.reason, 'rejected');
    assert.equal(failure.retryable, false);
    assert.equal(failure.label, 'Machine B');
  } finally {
    s.client.disconnect();
  }
});

test('L2: T3Client.requestPeerClientPairing parses credential, unsupported, and falls back to undefined on refusal', async () => {
  let mode = 'credential';
  const s = await setup({
    onRequest: (value, sock) => {
      if (value.tag === 'subscribeServerConfig') {
        sock.emit({
          _tag: 'Chunk',
          requestId: value.id,
          values: [{
            version: 1,
            type: 'snapshot',
            config: {
              environment: { environmentId: 'env', capabilities: { peerLinks: true } },
              settings: { linkedEnvironmentsEnabled: true },
              providers: []
            }
          }]
        });
        return 'handled';
      }
      if (value.tag === 'peerLinks.pairClient') {
        if (mode === 'credential') {
          sock.emit({
            _tag: 'Exit',
            requestId: value.id,
            exit: {
              _tag: 'Success',
              value: {
                type: 'credential',
                environmentId: 'env-b',
                label: 'Machine B',
                urls: ['http://192.168.10.75:14882'],
                credential: 'PAIR-B-123',
                expiresAt: '2026-11-23T12:00:00Z'
              }
            }
          });
        } else if (mode === 'unsupported') {
          sock.emit({
            _tag: 'Exit',
            requestId: value.id,
            exit: {
              _tag: 'Success',
              value: {
                type: 'unsupported',
                environmentId: 'env-b',
                label: 'Machine B',
                urls: ['http://192.168.10.75:14882'],
                reason: 'link_access'
              }
            }
          });
        } else {
          sock.emit({
            _tag: 'Exit',
            requestId: value.id,
            exit: {
              _tag: 'Failure',
              cause: { _id: 'Cause', reasons: [{ _tag: 'Fail', error: { _tag: 'EnvironmentAuthorizationError', message: 'denied' } }] }
            }
          });
        }
        return 'handled';
      }
      return undefined;
    }
  });
  try {
    await s.client.connect('https://test', 'CODE');
    const cred = await s.client.requestPeerClientPairing('env-b');
    assert.equal(cred.type, 'credential');
    assert.equal(cred.credential, 'PAIR-B-123');
    mode = 'unsupported';
    const unsup = await s.client.requestPeerClientPairing('env-b');
    assert.equal(unsup.type, 'unsupported');
    assert.equal(unsup.reason, 'link_access');
    mode = 'refused';
    assert.equal(await s.client.requestPeerClientPairing('env-b'), undefined);
  } finally {
    s.client.disconnect();
  }
});

test('L3: T3Client.subscribeSideThread, sideThreadItem, and sendToSideThread operate independently of main thread', async () => {
  const dispatched = [];
  const s = await setup({
    onRequest: (value, sock) => {
      if (value.tag === 'orchestration.getTurnItem') {
        sock.emit({
          _tag: 'Exit',
          requestId: value.id,
          exit: { _tag: 'Success', value: { item: { id: value.payload.itemId, output: 'side detail' } } }
        });
        return 'handled';
      }
      if (value.tag === 'orchestration.dispatchCommand') {
        dispatched.push(value.payload);
        sock.emit({ _tag: 'Exit', requestId: value.id, exit: { _tag: 'Success', value: { sequence: 20 } } });
        return 'handled';
      }
      return undefined;
    }
  });
  try {
    await s.client.connect('https://test', 'CODE');
    await s.client.watch('parent-thread');
    const sideFrames = [];
    const cancel = s.client.subscribeSideThread('child-side', (frame) => sideFrames.push(frame), () => {}, () => {});
    await new Promise((r) => setTimeout(r, 30));
    assert.equal(s.client.thread.threadId, 'parent-thread');
    assert.equal(sideFrames.length, 1);
    assert.equal(sideFrames[0].projection.thread.id, 'child-side');

    const item = await s.client.sideThreadItem('child-side', 'it-1');
    assert.equal(item.output, 'side detail');

    await s.client.sendToSideThread('child-side', 'follow up in side panel');
    assert.equal(dispatched.length, 1);
    assert.equal(dispatched[0].threadId, 'child-side');
    assert.equal(dispatched[0].text, 'follow up in side panel');
    cancel();
    assert.equal(s.client.thread.threadId, 'parent-thread');
  } finally {
    s.client.disconnect();
  }
});
