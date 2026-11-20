import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { compile, data, r4Url } from './load-core.mjs';

const source = await readFile(new URL('../entry/src/main/ets/components/ShareImportPanel.ets', import.meta.url), 'utf8');
const protocol = await readFile(new URL('../entry/src/main/ets/protocol/IncomingShare.ts', import.meta.url), 'utf8');
const shareUrl = data(compile(protocol.replace("'./R4'", JSON.stringify(r4Url))));
const code = source.split('  build() {')[0] + '}';
const { ShareImportPanel } = await import(data(compile(code
  .replace("'../protocol/IncomingShare'", JSON.stringify(shareUrl))
  .replace("import { image } from '@kit.ImageKit';", '')
  .replace(/^import\s+[^\n]*?from\s+['"](?:\.\/ui\/|\.\.\/common\/Theme)[^'"]*['"];\n/gm, '')
  .replace('@Component\nexport struct', 'export class')
  .replace(/@(?:Prop|State)\s+|@(?:Watch|StorageLink)\([^)]*\)\s*/g, ''))));

test('share image previews load only on request and release late, removed and closed images', async () => {
  const panel = new ShareImportPanel();
  panel.shareId = 1;
  panel.attachments = [{ id:'first',type:'image' }, { id:'second',type:'image' }, { id:'text',type:'file' }];
  panel.destination = 'Environment / Project';
  const read = [];
  const released = [];
  const map = id => ({ id, async release(){ released.push(id); } });
  panel.loadThumbnail = (shareId, id, current) => new Promise(resolve => read.push({ shareId, id, current, resolve }));
  panel.aboutToAppear();
  await panel.showPreview('text');
  assert.deepEqual(read, []);
  assert.equal(panel.canSave(), true);
  const first = panel.showPreview('first');
  assert.equal(panel.canSave(), false);
  const second = panel.showPreview('second');
  assert.equal(panel.previewId, 'second');
  assert.deepEqual(read.map(item => item.id), ['first']);
  assert.equal(read[0].current(), false);
  read[0].resolve(map('first'));
  await first;
  await Promise.resolve();
  assert.deepEqual(read.map(item => [item.shareId, item.id]), [[1,'first'],[1,'second']]);
  read[1].resolve(map('second'));
  await second;
  assert.equal(panel.thumbnail.id, 'second');
  assert.equal(panel.canSave(), true);
  assert.deepEqual(released, ['first']);
  panel.attachments = panel.attachments.filter(item => item.id !== 'second');
  panel.attachmentsChanged();
  assert.equal(panel.thumbnail, undefined);
  assert.deepEqual(released, ['first','second']);
  const closing = panel.showPreview('first');
  panel.aboutToDisappear();
  read[2].resolve(map('after-close'));
  await closing;
  assert.equal(panel.thumbnail, undefined);
  assert.deepEqual(released, ['first','second','after-close']);
});
