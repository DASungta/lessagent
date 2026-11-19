// The isolated handoff fixture is the only page this temporary viewer can operate.
import { spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { readFile, realpath } from 'node:fs/promises';
import { createInterface } from 'node:readline';
import { RpcClient, bootstrapForm, socketUrl } from '../../../../entry/src/main/ets/protocol/Wire.ts';
import { previewControl, previewFrameMatchesViewport, previewJpeg, previewMouse,
  previewStreamViewport } from '../../../../entry/src/main/ets/protocol/Preview.ts';

const baseDir = '/tmp/t3-r5-accept-00fcea';
const base = 'http://127.0.0.1:47895';
const fixture = 'http://127.0.0.1:47897/handoff.html';
const scopes = ['orchestration:read', 'preview:operate'];
const label = 'harmony-handoff-viewer-' + randomUUID();
const lifetime = new AbortController();
let socket, media, rpc, input, grantId, authAttempted = false;
let control, viewport, frameMatches = false;
let failure = false;
let phase = 'bind';
let controlChanged = () => {};

function output(event, details = {}) { console.log(JSON.stringify({ event, ...details })); }
function requireState(condition) { if (!condition) throw Error('isolated viewer state invalid'); }
function cli(args) {
  const result = spawnSync('t3', ['auth', ...args, '--base-dir', baseDir], {
    encoding: 'utf8', timeout: 5000, env: { ...process.env, T3CODE_HOME: baseDir }, stdio: ['ignore', 'pipe', 'pipe']
  });
  requireState(result.status === 0);
  return result.stdout;
}
function stop() {
  if (lifetime.signal.aborted) return;
  lifetime.abort();
  input?.close();
  rpc?.fail('verification finished');
}
const interrupt = () => { output('interrupt'); stop(); };
const timeout = setTimeout(() => { failure = true; output('timeout'); stop(); }, 120000);
process.on('SIGINT', interrupt);
process.on('SIGTERM', interrupt);

async function request(path, options = {}) {
  const response = await fetch(base + path, { ...options, redirect: 'error',
    signal: AbortSignal.any([lifetime.signal, AbortSignal.timeout(5000)]) });
  requireState(response.ok);
  return response.json();
}

async function open(websocket) {
  const signal = AbortSignal.any([lifetime.signal, AbortSignal.timeout(5000)]);
  if (signal.aborted) throw Error('socket stopped');
  await new Promise((resolve, reject) => {
    const closed = () => { cleanup(); reject(Error('socket failed')); };
    const ready = () => { cleanup(); resolve(); };
    const cleanup = () => {
      websocket.removeEventListener('open', ready);
      websocket.removeEventListener('close', closed);
      websocket.removeEventListener('error', closed);
      signal.removeEventListener('abort', closed);
    };
    websocket.addEventListener('open', ready);
    websocket.addEventListener('close', closed);
    websocket.addEventListener('error', closed);
    signal.addEventListener('abort', closed);
  });
}

function jpegGeometry(bytes) {
  previewJpeg(bytes);
  const image = Buffer.from(bytes);
  let offset = 2;
  while (offset + 8 < image.length) {
    requireState(image[offset++] === 0xff);
    while (image[offset] === 0xff) offset++;
    const marker = image[offset++];
    if (marker === 0xda || marker === 0xd9) break;
    requireState(offset + 2 <= image.length);
    const length = image.readUInt16BE(offset);
    requireState(length >= 2 && offset + length <= image.length);
    if ([0xc0, 0xc1, 0xc2].includes(marker)) {
      requireState(length >= 8);
      return previewStreamViewport(image.readUInt16BE(offset + 5), image.readUInt16BE(offset + 3));
    }
    offset += length;
  }
  throw Error('frame dimensions missing');
}

try {
  const state = JSON.parse(await readFile(new URL('../../r5/service-round2.json', import.meta.url), 'utf8'));
  requireState(state.server.baseDir === baseDir && state.server.listen === '127.0.0.1:47895');
  requireState((await realpath(baseDir)) === '/private' + baseDir);
  const descriptor = await request('/.well-known/t3/environment');
  requireState(descriptor.environmentId === (await readFile(baseDir + '/userdata/environment-id', 'utf8')).trim() &&
    descriptor.serverVersion === state.server.version);
  requireState(/^[0-9a-f-]{36}$/.test(state.project.id));
  const sql = "SELECT thread_id FROM orchestration_v2_projection_threads WHERE deleted_at IS NULL AND project_id='" +
    state.project.id + "' LIMIT 65;";
  const query = spawnSync('sqlite3', ['-readonly', baseDir + '/userdata/statev2.sqlite', sql], {
    encoding: 'utf8', timeout: 5000, stdio: ['ignore', 'pipe', 'pipe']
  });
  requireState(query.status === 0);
  const threadIds = query.stdout.trim().split('\n').filter(Boolean);
  requireState(threadIds.length > 0 && threadIds.length <= 64 && threadIds.every(id => /^[a-zA-Z0-9_.:-]{1,128}$/.test(id)));

  phase = 'auth';
  const grant = JSON.parse(cli(['pairing', 'create', ...scopes.flatMap(scope => ['--scope', scope]), '--ttl', '5m', '--label', label, '--json']));
  grantId = grant.id;
  requireState(typeof grantId === 'string' && grant.scopes?.length === scopes.length && scopes.every(scope => grant.scopes.includes(scope)));
  const body = bootstrapForm(grant.credential).replace('&client_label=T3%20Harmony', '&client_label=' + encodeURIComponent(label));
  authAttempted = true;
  const auth = await request('/oauth/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body });
  requireState(auth.token_type === 'Bearer' && typeof auth.access_token === 'string');
  const headers = { Authorization: 'Bearer ' + auth.access_token };
  const access = await request('/api/auth/session', { headers });
  const granted = access.permissions ?? access.scopes;
  requireState(access.authenticated === true && Array.isArray(granted) && scopes.every(scope => granted.includes(scope)));

  phase = 'list';
  const ticket = await request('/api/auth/websocket-ticket/rpc', { method: 'POST', headers });
  socket = new WebSocket(socketUrl(base, ticket.ticket));
  rpc = new RpcClient({ async send(frame) { socket.send(frame); } });
  socket.addEventListener('message', event => rpc.receive(event.data));
  await open(socket);
  const findFixture = async () => {
    const found = [];
    for (const threadId of threadIds) {
      requireState(!lifetime.signal.aborted);
      const list = await rpc.request('preview.list', { threadId }, undefined, 4000, false);
      requireState(Array.isArray(list.sessions));
      found.push(...list.sessions.filter(tab => tab.runtime === 'server' && tab.threadId === threadId &&
        tab.navStatus?.url === fixture).map(tab => ({ threadId, tabId: tab.tabId, serverEpoch: list.serverEpoch })));
    }
    requireState(found.length === 1 && typeof found[0].tabId === 'string' && typeof found[0].serverEpoch === 'string');
    return found[0];
  };
  const selected = await findFixture();
  const sameFixture = async () => {
    const current = await findFixture();
    requireState(current.threadId === selected.threadId && current.tabId === selected.tabId && current.serverEpoch === selected.serverEpoch);
  };

  phase = 'media';
  const mediaTicket = await request('/api/auth/websocket-ticket/media', { method: 'POST', headers });
  const parameters = new URLSearchParams({ threadId: selected.threadId, tabId: selected.tabId,
    maxWidth: '720', maxHeight: '1280', wsTicket: mediaTicket.ticket });
  media = new WebSocket(base.replace(/^http/, 'ws') + '/api/preview-stream/ws?' + parameters);
  media.binaryType = 'arraybuffer';
  media.addEventListener('message', event => {
    if (lifetime.signal.aborted) return;
    try {
      if (typeof event.data === 'string') {
        requireState(event.data.length <= 65536);
        const value = JSON.parse(event.data);
        if (value.type === 'viewport') {
          const next = previewStreamViewport(value.width, value.height);
          if (!viewport || next.width !== viewport.width || next.height !== viewport.height) {
            viewport = next; frameMatches = false;
            output('viewport', { width: viewport.width, height: viewport.height });
          }
        } else if (value.type === 'control') {
          const next = previewControl(value);
          if (control && next.generation < control.generation) return;
          control = next;
          output('control', { controller: next.controller, generation: next.generation, canOperate: next.canOperate });
          controlChanged();
        }
      } else {
        const frame = jpegGeometry(event.data);
        media.send('{"type":"ack"}');
        if (viewport && previewFrameMatchesViewport(frame, viewport) && !frameMatches) {
          frameMatches = true;
          output('frame', { width: frame.width, height: frame.height });
        }
      }
    } catch (_) { failure = true; output('media-failed'); stop(); }
  });
  await open(media);
  media.addEventListener('close', () => {
    if (!lifetime.signal.aborted) { failure = true; output('media-closed'); stop(); }
  });

  phase = 'input';
  input = createInterface({ input: process.stdin, crlfDelay: Infinity, terminal: false });
  output('ready');
  const canSend = () => !lifetime.signal.aborted && media.readyState === WebSocket.OPEN && control?.canOperate && !control.dialog;
  for await (const command of input) {
    if (command === 'quit' || lifetime.signal.aborted) break;
    if (command !== 'take' && command !== 'release' && command !== 'click') { output('rejected'); continue; }
    const initial = control;
    if (!canSend() || !initial || (command !== 'take' && initial.controller !== 'you') ||
      (command === 'click' && (!frameMatches || !viewport))) { output('blocked', { action: command }); continue; }
    if (command === 'take' && initial.controller === 'you') { output('confirmed', { action: command }); continue; }
    await sameFixture();
    if (!canSend() || initial.generation !== control.generation || initial.controller !== control.controller ||
      (command === 'click' && (!frameMatches || !viewport))) { output('blocked', { action: command }); continue; }
    if (command === 'click') {
      const point = { x: viewport.width / 2, y: viewport.height / 2 };
      media.send(JSON.stringify(previewMouse(point, true)));
      media.send(JSON.stringify(previewMouse(point, false)));
      output('sent', { action: command, x: point.x, y: point.y, generation: initial.generation });
      continue;
    }
    const confirmed = await new Promise(resolve => {
      const timer = setTimeout(() => done(false), 4000);
      const done = value => {
        clearTimeout(timer);
        lifetime.signal.removeEventListener('abort', aborted);
        controlChanged = () => {};
        resolve(value);
      };
      const aborted = () => done(false);
      lifetime.signal.addEventListener('abort', aborted, { once: true });
      controlChanged = () => {
        if (control.generation > initial.generation &&
          (command === 'take' ? control.controller === 'you' : control.controller !== 'you')) done(true);
      };
      try { media.send(JSON.stringify({ type: command === 'take' ? 'takeControl' : 'releaseControl' })); }
      catch (_) { done(false); }
    });
    output(confirmed ? 'confirmed' : 'unconfirmed', { action: command });
    if (!confirmed) { failure = true; break; }
  }
} catch (_) {
  if (!lifetime.signal.aborted) { failure = true; output('failed', { phase }); }
} finally {
  stop();
  clearTimeout(timeout);
  media?.close();
  socket?.close();
  let revoked = !authAttempted;
  let pairingRevoked = !grantId;
  try {
    if (grantId) { cli(['pairing', 'revoke', grantId]); pairingRevoked = true; }
  } catch (_) {}
  try {
    if (authAttempted) {
      const ownSessions = () => JSON.parse(cli(['session', 'list', '--json'])).filter(session => session.client?.label === label);
      const sessions = ownSessions();
      requireState(sessions.length <= 1);
      if (sessions.length === 1) cli(['session', 'revoke', sessions[0].sessionId]);
      revoked = ownSessions().length === 0;
    }
  } catch (_) {}
  process.off('SIGINT', interrupt);
  process.off('SIGTERM', interrupt);
  output('cleanup', { sessionRevoked: revoked, pairingRevoked });
  if (failure || !revoked || !pairingRevoked) process.exitCode = 1;
}
