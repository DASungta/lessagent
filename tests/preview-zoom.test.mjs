import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { compile, data } from './load-core.mjs';
import { PREVIEW_ZOOM_LEVELS, previewTabs, previewResizeInput, previewZoomInput, previewZoomTarget,
  verifyPreviewZoom, previewStreamViewport, previewDecodeSize, previewNeedsZoomRepair, repairPreviewZoom100 } from '../entry/src/main/ets/protocol/Preview.ts';

const desktop = { _tag: 'freeform', width: 1280, height: 800 };
const session = { threadId: 'thread', tabId: 'tab', runtime: 'server', zoomFactor: 1, viewport: desktop };

test('preview zoom uses exact upstream levels, tab-only payload and separate CSS and allocation limits', () => {
  assert.deepEqual(PREVIEW_ZOOM_LEVELS, [0.25, 0.33, 0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4, 5]);
  assert.deepEqual(previewZoomInput('thread', 'tab', 0.25), { threadId: 'thread', tabId: 'tab', zoomFactor: 0.25 });
  assert.throws(() => previewZoomInput('thread', 'tab', 0.26), /无效/);
  const zoom = previewZoomTarget(previewTabs({ sessions: [session] }, 'thread')[0], 0.25);
  assert.deepEqual(zoom, { zoomFactor: 0.25, viewport: { width: 5120, height: 3200 } });
  assert.deepEqual(previewStreamViewport(5120, 3200), zoom.viewport);
  assert.throws(() => previewResizeInput('thread', 'tab', { _tag: 'freeform', width: 5120, height: 3200 }), /无效/);
  assert.throws(() => previewDecodeSize(zoom.viewport), /超限/);
  assert.throws(() => previewStreamViewport(15361, 800), /无效/);
});

test('preview zoom fixes metadata to the same tab, runtime and layout; fill needs a measured viewport', () => {
  const [tab] = previewTabs({ sessions: [session] }, 'thread');
  const expected = previewZoomTarget(tab, 1.25);
  assert.deepEqual(verifyPreviewZoom({ ...session, zoomFactor: 1.25 }, 'thread', tab, expected), expected);
  assert.throws(() => verifyPreviewZoom({ ...session, zoomFactor: 1.25, tabId: 'another' }, 'thread', tab, expected), /已变化/);
  assert.throws(() => verifyPreviewZoom({ ...session, zoomFactor: 1.25, runtime: 'desktop' }, 'thread', tab, expected), /已变化/);
  assert.throws(() => verifyPreviewZoom({ ...session, zoomFactor: 1.25, viewport: { ...desktop, width: 1200 } }, 'thread', tab, expected), /尺寸已变化/);
  assert.throws(() => verifyPreviewZoom(session, 'thread', tab, expected), /尚未确认/);
  const [fill, future] = previewTabs({ sessions: [{ ...session, viewport: undefined, zoomFactor: undefined },
    { ...session, tabId: 'future', zoomFactor: 7 }] }, 'thread');
  assert.equal(fill.zoomFactor, 1);
  assert.throws(() => previewZoomTarget(fill, 0.25), /等待/);
  assert.deepEqual(previewZoomTarget(fill, 0.25, desktop), {
    zoomFactor: 0.25, viewport: { width: 5120, height: 3200 }, viewportTolerance: 3
  });
  assert.equal(future.zoomFactor, undefined);
  assert.throws(() => previewZoomTarget(future, 1), /不可用/);
});

const index = await readFile(new URL('../entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
const methods = index.slice(index.indexOf('  private previewZoomRepairRequired'), index.indexOf('  private terminalOwner'));
const protocol = new URL('../entry/src/main/ets/protocol/Preview.ts', import.meta.url).href;
const { IndexHarness } = await import(data(compile(`
  import { previewTabs, previewZoomInput, previewZoomTarget, verifyPreviewZoom, previewNeedsZoomRepair, repairPreviewZoom100 } from ${JSON.stringify(protocol)};
  import { record } from ${JSON.stringify(new URL('../entry/src/main/ets/protocol/Wire.ts', import.meta.url).href)};
  export class IndexHarness {
    page = 'preview';
    appForeground = true;
    previewThreadId = 'thread';
    previewGeneration = 1;
    previewKey = 'key';
    previewTabs = new Map([['key', 'tab']]);
    previewCurrent() { return true; }
    ${methods}
  }
`)));

test('native zoom verifies fresh ownership and pauses on late acknowledgements without replay', async () => {
  const panel = new IndexHarness();
  let finish;
  let authorized = true;
  let supported = true;
  let generation = 1;
  const calls = [];
  panel.previewConnection = {
    ready: true, generationValue: () => generation, supports: key => key === 'serverBrowser' && supported,
    canScope: key => key === 'preview:operate' && authorized,
    rpcRequest: async (method, payload) => {
      calls.push([method, payload]);
      if (method === 'preview.list') return { sessions: [session] };
      return await new Promise(resolve => { finish = resolve; });
    }
  };
  authorized = false;
  await assert.rejects(panel.adjustPreviewZoom('tab', 1.25), /权限/);
  authorized = true; supported = false;
  await assert.rejects(panel.adjustPreviewZoom('tab', 1.25), /权限/);
  supported = true;
  assert.equal(calls.length, 0);
  const pending = panel.adjustPreviewZoom('tab', 1.25);
  await new Promise(setImmediate);
  assert.deepEqual(calls, [['preview.list', { threadId: 'thread' }],
    ['preview.adjust', { threadId: 'thread', tabId: 'tab', zoomFactor: 1.25 }]]);
  generation++;
  finish({ ...session, zoomFactor: 1.25 });
  await assert.rejects(pending, /已变化/);
  assert.equal(calls.length, 2);
});

const at = step => new Date(1000 * step).toISOString();
const originalPreset = { _tag: 'preset', presetId: 'ipad-pro-11', width: 768, height: 1024 };
function repairFixture(viewport = originalPreset) {
  let state = { ...session, zoomFactor: 0.5, viewport, updatedAt: at(1) };
  let sequence = 1;
  const calls = [];
  const rpc = async (method, payload) => {
    calls.push([method, payload]);
    if (method === 'preview.list') return { sessions: [state] };
    state = {
      ...state, ...('viewport' in payload ? { viewport: payload.viewport } : { zoomFactor: payload.zoomFactor }),
      updatedAt: at(++sequence)
    };
    return state;
  };
  return { rpc, calls, before: previewTabs({ sessions: [state] }, 'thread')[0] };
}

test('confirmed 100% repair moves one pixel and restores the exact preset through verified reads', async () => {
  assert.equal(previewNeedsZoomRepair('0.1.10'), true);
  assert.equal(previewNeedsZoomRepair('0.1.11'), false);
  assert.equal(previewNeedsZoomRepair(undefined), false);
  const { rpc, calls, before } = repairFixture();
  assert.deepEqual(await repairPreviewZoom100('thread', before, rpc, () => true),
    { zoomFactor: 1, viewport: { width: 768, height: 1024 } });
  assert.deepEqual(calls, [
    ['preview.adjust', { threadId: 'thread', tabId: 'tab', zoomFactor: 1 }],
    ['preview.list', { threadId: 'thread' }],
    ['preview.resize', { threadId: 'thread', tabId: 'tab', viewport: { _tag: 'freeform', width: 769, height: 1024 } }],
    ['preview.list', { threadId: 'thread' }],
    ['preview.resize', { threadId: 'thread', tabId: 'tab', viewport: originalPreset }],
    ['preview.list', { threadId: 'thread' }]
  ]);
});

test('repair refuses fill and lost control before mutation, then stops on conflict or failed stage', async () => {
  const fill = repairFixture({ _tag: 'fill' });
  await assert.rejects(repairPreviewZoom100('thread', fill.before, fill.rpc, () => true), /固定尺寸/);
  assert.equal(fill.calls.length, 0);
  const denied = repairFixture();
  await assert.rejects(repairPreviewZoom100('thread', denied.before, denied.rpc, () => false), /控制权/);
  assert.equal(denied.calls.length, 0);
  const stale = repairFixture();
  await assert.rejects(repairPreviewZoom100('thread', stale.before, async (method, input) => {
    const result = await stale.rpc(method, input);
    if (method === 'preview.list') result.sessions = result.sessions.map(item => ({ ...item, updatedAt: at(50) }));
    return result;
  }, () => true), /已变化/);
  assert.equal(stale.calls.length, 2);
  const timeout = repairFixture({ _tag: 'freeform', width: 3840, height: 2160 });
  await assert.rejects(repairPreviewZoom100('thread', timeout.before, async (method, input) => {
    const result = await timeout.rpc(method, input);
    if (method === 'preview.resize') throw Error('timeout');
    return result;
  }, () => true), /timeout/);
  assert.deepEqual(timeout.calls.map(call => call[0]), ['preview.adjust', 'preview.list', 'preview.resize']);
  assert.equal(timeout.calls[2][1].viewport.width, 3839);
});

test('v0.1.10 Index requires explicit confirmation even for a tab reported at 100%', async () => {
  const panel = new IndexHarness();
  const called = [];
  panel.previewConnection = { ready: true, config: { environment: { serverVersion: '0.1.10' } },
    generationValue: () => 1, supports: () => true, canScope: () => true,
    rpcRequest: async method => {
      called.push(method);
      return { sessions: [{ ...session, viewport: { _tag: 'fill' }, updatedAt: at(1) }] };
    }
  };
  await assert.rejects(panel.adjustPreviewZoom('tab', 1), /显式确认/);
  await assert.rejects(panel.adjustPreviewZoom('tab', 1, undefined, () => true), /固定尺寸/);
  assert.deepEqual(called, ['preview.list', 'preview.list']);
});

test('control lost after the temporary resize is not compensated by an automatic second resize', async () => {
  const fixture = repairFixture();
  let controlling = true;
  await assert.rejects(repairPreviewZoom100('thread', fixture.before, async (method, input) => {
    const result = await fixture.rpc(method, input);
    if (method === 'preview.resize') controlling = false;
    return result;
  }, () => controlling), /控制权已变化/);
  assert.deepEqual(fixture.calls.map(call => call[0]), ['preview.adjust', 'preview.list', 'preview.resize']);
});
