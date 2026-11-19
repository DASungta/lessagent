import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { compile, data, r4Url } from './load-core.mjs';
const source = (await readFile(new URL('../entry/src/main/ets/protocol/IncomingShare.ts', import.meta.url), 'utf8'))
  .replace("'./R4'", JSON.stringify(r4Url));
const shareUrl = data(compile(source));
const api = await import(shareUrl);
let serviceNumber = 0;
async function loadService() {
  const serviceSource = (await readFile(new URL('../entry/src/main/ets/services/ShareInbox.ets', import.meta.url), 'utf8'))
    .replace("import { Want } from '@kit.AbilityKit';", '')
    .replace("import { systemShare } from '@kit.ShareKit';", 'const systemShare = globalThis.__r7share;')
    .replace("import { fileIo } from '@kit.CoreFileKit';", 'const fileIo = globalThis.__r7shareFiles;')
    .replace("import { image } from '@kit.ImageKit';", 'const image = globalThis.__r7shareImage;')
    .replace("'../protocol/Preview'", JSON.stringify(new URL('../entry/src/main/ets/protocol/Preview.ts', import.meta.url).href))
    .replace("'../protocol/R4'", JSON.stringify(r4Url))
    .replace("'../protocol/IncomingShare'", JSON.stringify(shareUrl));
  return import(data(compile(serviceSource + '\n// fixture ' + ++serviceNumber)));
}
const plain = content => ({utd:'general.plain-text', content});
test('incoming text preserves order, type, paragraphs and repeated records as inert text', () => {
  const parts = api.sharedParts([plain(' hi\nthere '), {utd:'general.hyperlink',content:'https://example.org/a'},
    plain(' hi\nthere ')]);
  assert.deepEqual(parts.map(({ id, kind })=>[id,kind]), [[1,'text'], [2,'link'], [3,'text']]);
  assert.equal(api.shareDraftText(parts), ' hi\nthere \n\nhttps://example.org/a\n\n hi\nthere ');
  assert.equal(api.shareDraftText(api.sharedParts([plain('<script>alert(1)</script>')])), '<script>alert(1)</script>');
  assert.throws(() => api.sharedParts([{utd:'general.hyperlink',content:'javascript:alert(1)'}]));
});
test('incoming share rejects malformed, mixed media and oversized payloads without truncation', () => {
  for(const records of [[], [plain(' ')], [plain('a\0b')], [plain(2)], [{utd:'general.image',uri:'file:///private/x'}], Array.from({length:33},()=>plain('a')), [plain('a'.repeat(api.MAX_SHARED_TEXT_CHARS)),plain('b')]]) {
    assert.throws(() => api.sharedParts(records));
  }
  assert.equal(api.shareDraftText(api.sharedParts([plain('a'.repeat(api.MAX_SHARED_TEXT_CHARS))])).length, api.MAX_SHARED_TEXT_CHARS);
});
test('share queue keeps existing drafts, dedupes pending deliveries, and removes only confirmed id', () => {
  const queue = new api.IncomingShareQueue();
  const add = value => queue.add(api.sharedParts([plain(value)]));
  add('one'); add('one'); add('two');
  const first = queue.peek(); first.parts[0].text = 'tamper';
  assert.equal(queue.peek().parts[0].text, 'one');
  queue.remove(999); assert.equal(queue.peek().id, first.id);
  queue.remove(first.id); assert.equal(queue.peek().parts[0].text,'two');
  for(let i=0;i<7;i++) add('pending'+i);
  assert.throws(()=>add('overflow'));
  assert.equal(queue.peek().parts[0].text,'two');
});
test('ShareKit intake serializes cold/warm Wants and unrelated actions cannot ingest', async () => {
  const storage = new Map();
  globalThis.AppStorage = {get:k=>storage.get(k), setOrCreate:(k,v)=>storage.set(k,v)};
  let finishFirst;
  let calls=0;
  globalThis.__r7share = { getSharedData: async want => {
    calls++;
    if(want.seq===1) await new Promise(resolve=>finishFirst=resolve);
    if(want.seq===3) throw Error('private URI secret');
    return {getRecords:()=>[plain('text'+want.seq)]};
  }};
  const service = await loadService();
  await service.acceptIncomingShare({action:'ohos.want.action.viewData',seq:1}); assert.equal(calls,0);
  const first = service.acceptIncomingShare({action:'ohos.want.action.sendData',seq:1});
  const second = service.acceptIncomingShare({action:'ohos.want.action.sendData',seq:2});
  await Promise.resolve(); assert.equal(calls,1); finishFirst(); await first; await second;
  assert.equal(service.peekIncomingShare().parts[0].text,'text1');
  service.removeIncomingShare(service.peekIncomingShare().id);
  assert.equal(service.peekIncomingShare().parts[0].text,'text2');
  await service.acceptIncomingShare({action:'ohos.want.action.sendData',seq:3});
  assert.equal(service.peekIncomingShare().parts[0].text,'text2');
  assert.ok(!storage.get('t3IncomingShareError').includes('secret'));
  delete globalThis.__r7share; delete globalThis.AppStorage;
});

test('share receive registration validates against the installed API24 URI schema', async () => {
  const { createRequire } = await import('node:module');
  const sdk = (process.env.DEVECO_HOME || '/Applications/DevEco-Studio.app/Contents') + '/sdk/default/openharmony';
  const Ajv = createRequire(import.meta.url)(sdk + '/ets/build-tools/ets-loader/node_modules/ajv/dist/ajv.js');
  const schema = JSON.parse(await readFile(sdk + '/toolchains/modulecheck/module.json', 'utf8'));
  const module = JSON.parse(await readFile(new URL('../entry/src/main/module.json5', import.meta.url), 'utf8'));
  const uris = module.module.abilities[0].skills.find(item => item.actions.includes('ohos.want.action.sendData')).uris;
  const validate = new Ajv({strict:false}).compile(schema.properties.module.properties.abilities.items.properties.skills.items.properties.uris.items);
  assert.equal(validate({utd:'general.plain-text'}), false);
  assert.deepEqual(uris.map(uri => uri.utd), ['general.plain-text', 'general.hyperlink', 'general.image']);
  for (const uri of uris) {
    assert.equal(validate(uri), true, JSON.stringify(validate.errors));
    assert.equal(uri.scheme, 'file');
    assert.equal(uri.maxFileSupported, uri.utd === 'general.image' ? 10 : 32);
  }
});

const docs = 'file://docs/storage/Users/currentUser/Download/';
const media = 'file://media/Photo/42/IMG_0042/fixture.png';
const fileRecord = (uri, utd = 'general.file') => ({ uri, utd });
const share = records => ({ action: 'ohos.want.action.sendData', records });
const textBytes = Buffer.from('原文件\r\n保持字节');
const pngBytes = Buffer.from([137,80,78,71,13,10,26,10,0]);
async function attachmentService(files) {
  const storage = new Map();
  const opened = [];
  const closed = [];
  const reads = [];
  const handles = new Map();
  let next = 0;
  globalThis.AppStorage = { get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value) };
  globalThis.__r7share = { getSharedData: async want => ({ getRecords: () => want.records }) };
  globalThis.__r7shareFiles = {
    OpenMode: { READ_ONLY: 1, NOFOLLOW: 2 },
    async open(uri, mode) {
      opened.push(uri);
      assert.equal(mode, 3);
      const file = files.get(uri);
      if (!file) throw Error('permission denied for private URI');
      const fd = ++next;
      handles.set(fd, { file, offset: 0, uri });
      return { fd };
    },
    async stat(fd) {
      const { file } = handles.get(fd);
      return { isFile: () => !file.directory, size: file.size ?? file.bytes.length };
    },
    async read(fd, block, options) {
      const handle = handles.get(fd);
      const { file, offset } = handle;
      reads.push(fd);
      const remaining = (file.realSize ?? file.bytes?.length ?? file.size) - offset;
      const count = Math.max(0, Math.min(remaining, options.length, file.shortReads ? 2 : Infinity));
      const output = new Uint8Array(block, 0, count);
      if (file.bytes) output.set(file.bytes.subarray(offset, offset + count));
      else output.fill(97);
      handle.offset += count;
      return count;
    },
    async close({fd}) { closed.push(handles.get(fd).uri); handles.delete(fd); }
  };
  return { service: await loadService(), storage, opened, closed, reads };
}

test('rejects app sandbox authorities, paths with traversal or escaped separators, and remote URLs before open', async () => {
  const forbidden = [
    'file://com.dasungta.t3code.harmony/data/storage/el2/base/haps/entry/files/private.txt',
    'file:///data/storage/el2/base/haps/entry/files/private.txt',
    'file://another.app/data/storage/el2/base/private.txt',
    'https://example.test/share.txt',
    docs + '../private.txt', docs + '%2e%2e/private.txt', docs + '%252e%252e/private.txt',
    docs + 'folder%2fprivate.txt', docs + 'folder%5cprivate.txt', docs + 'name.txt?secret',
    docs + 'file%3F.txt', 'file://docs@evil/storage/Users/currentUser/Download/file.txt',
    'file://media/Photo/1/%2e%2e/photo.png'
  ];
  const { service, opened, storage } = await attachmentService(new Map());
  for (const uri of forbidden) await service.acceptIncomingShare(share([fileRecord(uri)]));
  assert.deepEqual(opened, []);
  assert.equal(service.peekIncomingShare(), undefined);
  assert.ok(!storage.get('t3IncomingShareError').includes('secret'));
});

test('batch share keeps exact TXT bytes, metadata only, and removal releases the staged attachment', async () => {
  const firstUri = docs + 'note%20one.txt';
  const { service, opened, closed } = await attachmentService(new Map([
    [firstUri, {bytes: textBytes, shortReads: true}], [media, {bytes: pngBytes}]
  ]));
  await service.acceptIncomingShare(share([fileRecord(firstUri), plain('Caption'), fileRecord(media, 'general.image')]));
  const entry = service.peekIncomingShare();
  assert.deepEqual(opened, [firstUri, media]);
  assert.deepEqual(closed, opened);
  assert.equal(entry.parts[0].text, 'Caption');
  assert.deepEqual(entry.attachments.map(file => [file.type,file.name,file.mimeType,file.sizeBytes]), [
    ['file','note one.txt','text/plain',textBytes.length], ['image','fixture.png','image/png',pngBytes.length]
  ]);
  assert.ok(!JSON.stringify(entry).includes('file://'));
  entry.attachments[0].name = 'mutated';
  assert.equal(service.peekIncomingShare().attachments[0].name, 'note one.txt');
  const id = entry.attachments[0].id;
  await service.withStagedShareAttachment(entry.id, id, async bytes => {
    assert.deepEqual(Buffer.from(bytes), textBytes);
    new Uint8Array(bytes).fill(0);
    await assert.rejects(service.withStagedShareAttachment(entry.id, id, async () => {}), /正在读取/);
  });
  await service.withStagedShareAttachment(entry.id, id, async bytes => assert.deepEqual(Buffer.from(bytes), textBytes));
  service.removeIncomingShare(entry.id);
  await assert.rejects(service.withStagedShareAttachment(entry.id, id, async () => {}), /失效/);
  assert.equal(service.peekIncomingShare(), undefined);
});

test('batch rolls back when a later entry is denied, not a regular file, invalid UTF-8 or larger than stat', async () => {
  const good = docs + 'good.txt';
  const blocked = docs + 'blocked.txt';
  const directory = docs + 'directory.txt';
  const binary = docs + 'binary.txt';
  const growing = docs + 'growing.txt';
  const { service, closed } = await attachmentService(new Map([
    [good,{bytes:textBytes}], [directory,{bytes:textBytes,directory:true}],
    [binary,{bytes:Buffer.from([0xf4,0x90,0x80,0x80])}],
    [growing,{bytes:textBytes,size:2}]
  ]));
  for (const bad of [blocked, directory, binary, growing]) {
    await service.acceptIncomingShare(share([fileRecord(good), fileRecord(bad)]));
    assert.equal(service.peekIncomingShare(), undefined);
  }
  assert.equal(closed.filter(uri=>uri===good).length,4);
  assert.equal(closed.includes(directory),true);
  await service.acceptIncomingShare(share([fileRecord(good)]));
  assert.equal(service.peekIncomingShare().parts.length,0);
  assert.equal(service.peekIncomingShare().attachments.length,1);
});

test('staged queue total is applied before reading, and cancel restores the capacity', async () => {
  const first = docs + 'first.txt';
  const second = docs + 'second.txt';
  const { service, reads } = await attachmentService(new Map([
    [first,{size:35*1024*1024}], [second,{size:30*1024*1024}]
  ]));
  await service.acceptIncomingShare(share([fileRecord(first)]));
  const accepted = service.peekIncomingShare();
  const priorReads = reads.length;
  await service.acceptIncomingShare(share([fileRecord(second)]));
  assert.equal(reads.length, priorReads);
  assert.equal(service.peekIncomingShare().id, accepted.id);
  service.removeIncomingShare(accepted.id);
  await service.acceptIncomingShare(share([fileRecord(second)]));
  assert.equal(service.peekIncomingShare().attachments[0].name,'second.txt');
  service.removeIncomingShare(service.peekIncomingShare().id);
});

test('empty plain-text URI stays inline; a nonempty URI must pass the file route and permissions', async () => {
  const allowed = docs + 'granted.txt';
  const privateUri = 'file://com.dasungta.t3code.harmony/data/storage/el2/base/private.txt';
  const { service, opened } = await attachmentService(new Map([[allowed, { bytes: textBytes }]]));
  await service.acceptIncomingShare(share([{ ...plain('inline'), uri: '' }, fileRecord(allowed, 'general.plain-text')]));
  const entry = service.peekIncomingShare();
  assert.equal(entry.parts[0].text, 'inline');
  assert.equal(entry.attachments[0].name, 'granted.txt');
  assert.deepEqual(opened, [allowed]);
  service.removeIncomingShare(entry.id);
  await service.acceptIncomingShare(share([{ ...plain('fake inline'), uri: privateUri }]));
  await service.acceptIncomingShare(share([fileRecord('')]));
  assert.deepEqual(opened, [allowed]);
  assert.equal(service.peekIncomingShare(), undefined);
});

test('single attachment removal is exact and cannot revive an already borrowed file', async () => {
  const first = docs + 'first.txt';
  const second = docs + 'second.txt';
  const { service, storage } = await attachmentService(new Map([
    [first, { bytes: textBytes }], [second, { bytes: Buffer.from('second') }]
  ]));
  await service.acceptIncomingShare(share([plain('caption'), fileRecord(first), fileRecord(second)]));
  const entry = service.peekIncomingShare();
  const [a, b] = entry.attachments;
  let finish;
  const gate = new Promise(resolve => { finish = resolve; });
  const use = service.withStagedShareAttachment(entry.id, a.id, async bytes => {
    assert.deepEqual(Buffer.from(bytes), textBytes);
    await gate;
    assert.deepEqual(Buffer.from(bytes), textBytes);
  });
  const before = storage.get('t3IncomingShareRevision');
  assert.equal(service.removeIncomingShareAttachment(999, a.id), false);
  assert.equal(service.removeIncomingShareAttachment(entry.id, a.id), true);
  assert.equal(service.removeIncomingShareAttachment(entry.id, a.id), false);
  assert.equal(storage.get('t3IncomingShareRevision'), before + 1);
  assert.equal(service.peekIncomingShare().id, entry.id);
  assert.deepEqual(service.peekIncomingShare().parts, entry.parts);
  assert.deepEqual(service.peekIncomingShare().attachments, [b]);
  finish(); await use;
  await assert.rejects(service.withStagedShareAttachment(entry.id, a.id, async () => {}), /失效/);
  await service.withStagedShareAttachment(entry.id, b.id, async bytes => assert.equal(Buffer.from(bytes).toString(), 'second'));
  assert.equal(service.removeIncomingShareAttachment(entry.id, b.id), true);
  assert.equal(service.peekIncomingShare().attachments, undefined);
  assert.deepEqual(service.peekIncomingShare().parts, entry.parts);
});

test('removing one staged file restores its bytes to capacity without removing the share', async () => {
  const large = docs + 'large.txt';
  const sibling = docs + 'keep.txt';
  const next = docs + 'next.txt';
  const {service, reads} = await attachmentService(new Map([
    [large,{size:35*1024*1024}], [sibling,{bytes:textBytes}], [next,{size:30*1024*1024}]
  ]));
  await service.acceptIncomingShare(share([fileRecord(large), fileRecord(sibling)]));
  const entry = service.peekIncomingShare();
  const before = reads.length;
  await service.acceptIncomingShare(share([fileRecord(next)]));
  assert.equal(reads.length, before);
  assert.equal(service.removeIncomingShareAttachment(entry.id, entry.attachments[0].id), true);
  await service.acceptIncomingShare(share([fileRecord(next)]));
  assert.equal(service.peekIncomingShare().id, entry.id);
  assert.equal(service.peekIncomingShare().attachments[0].name, 'keep.txt');
  service.removeIncomingShare(entry.id);
  assert.equal(service.peekIncomingShare().attachments[0].name,'next.txt');
  service.removeIncomingShare(service.peekIncomingShare().id);
});

async function stagedThumbnail(width, height, output, gate, started) {
  const calls = [];
  const frame = {
    getImageInfo: async () => ({ size: output }),
    release: async () => { calls.push('frame released'); },
  };
  globalThis.__r7shareImage = {
    createImageSource(bytes) {
      assert.deepEqual(Buffer.from(bytes), pngBytes);
      return {
        async getImageInfo(index) {
          calls.push(index);
          return { size: { width, height } };
        },
        async createPixelMap(options) {
          calls.push(options);
          started?.();
          await gate;
          return frame;
        },
        async release() { calls.push('source released'); },
      };
    },
  };
  const { service } = await attachmentService(new Map([[media, {bytes: pngBytes}]]));
  await service.acceptIncomingShare(share([fileRecord(media, 'general.image')]));
  const entry = service.peekIncomingShare();
  const attachmentId = entry.attachments[0].id;
  return { service, id: entry.id, attachmentId, frame, calls };
}

test('local image thumbnail requests a proportional bounded first frame', async () => {
  const {service, id, attachmentId, frame, calls} =
    await stagedThumbnail(1200, 1600, { width: 240, height: 320 });
  assert.equal(await service.loadStagedShareThumbnail(id, attachmentId), frame);
  assert.deepEqual(calls, [0, { index: 0, editable: false, desiredSize: {width: 240, height: 320} },
    'source released']);
});

test('thumbnail rejects oversized or invalid dimensions and preserves original staged bytes', async () => {
  for (const [width, height, output, expected] of [
    [4097, 600, undefined, /尺寸过大/],
    [3000, 3000, undefined, /尺寸过大/],
    [1200.5, 1600, undefined, /无法预览/],
    [1200, 1600, {width: 1200, height: 1600}, /无法预览/],
  ]) {
    const { service, id, attachmentId, calls } = await stagedThumbnail(width, height, output);
    await assert.rejects(service.loadStagedShareThumbnail(id, attachmentId), expected);
    if (output) assert.deepEqual(calls.slice(-2), ['source released', 'frame released']);
    else assert.deepEqual(calls, [0, 'source released']);
    await service.withStagedShareAttachment(id, attachmentId, async bytes =>
      assert.deepEqual(Buffer.from(bytes), pngBytes));
  }
});

test('removing an attachment discards and releases the native thumbnail still decoding', async () => {
  let finish;
  let signalStarted;
  const gate = new Promise(resolve => { finish = resolve; });
  const started = new Promise(resolve => { signalStarted = resolve; });
  const { service, id, attachmentId, calls } =
    await stagedThumbnail(1200, 1600, { width: 240, height: 320 }, gate, signalStarted);
  const result = service.loadStagedShareThumbnail(id, attachmentId);
  await started;
  service.removeIncomingShareAttachment(id, attachmentId);
  await assert.rejects(service.loadStagedShareThumbnail(id, attachmentId), /已失效/);
  finish();
  await assert.rejects(result, /已失效/);
  assert.deepEqual(calls.slice(-2), ['source released', 'frame released']);
});
