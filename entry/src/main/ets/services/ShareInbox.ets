import { Want } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { previewFrameMatchesViewport, previewSourceOversized } from '../protocol/Preview';
import { R4_MAX_FILE_BYTES, R4_MAX_IMAGE_BYTES, attachmentRecord } from '../protocol/R4';
import {
  IncomingShareQueue, IncomingTextShare, IncomingShareAttachment, SharedTextRecord, ShareAttachmentSource,
  shareAttachmentMatchesType, shareAttachmentSource, sharedParts
} from '../protocol/IncomingShare';

const MAX_SHARE_FILES = 10;
const MAX_BATCH_BYTES = 50 * 1024 * 1024;
const MAX_STAGED_BYTES = 64 * 1024 * 1024;
const THUMBNAIL_EDGE = 320;
const THUMBNAIL_PIXELS = THUMBNAIL_EDGE * THUMBNAIL_EDGE;
interface StagedShareFile { metadata: IncomingShareAttachment; bytes: ArrayBuffer; }

const inbox: IncomingShareQueue = new IncomingShareQueue();
const staged: Map<number, StagedShareFile[]> = new Map();
let stagedBytes = 0;
let nextFileId = 1;
let borrowing = false;
let pendingWants = 0;
let ingesting: Promise<void> = Promise.resolve();

function notify(): void {
  AppStorage.setOrCreate('t3IncomingShareRevision', (AppStorage.get<number>('t3IncomingShareRevision') || 0) + 1);
}
function reportFailure(): void {
  AppStorage.setOrCreate('t3IncomingShareError',
    '无法接收分享。请检查文件读权限及类型：支持系统文件中的 UTF‑8 TXT 或 JPEG、PNG、GIF、WebP 图片，每批最多 10 个附件和 50 MiB。');
}

async function stageFile(source: ShareAttachmentSource, remaining: number): Promise<StagedShareFile> {
  const file = await fileIo.open(source.uri, fileIo.OpenMode.READ_ONLY | fileIo.OpenMode.NOFOLLOW);
  try {
    const stat = await fileIo.stat(file.fd);
    const max = Math.min(remaining, source.type === 'image' ? R4_MAX_IMAGE_BYTES : R4_MAX_FILE_BYTES);
    const size = stat.size;
    if (!stat.isFile() || !Number.isSafeInteger(size) || size < 1 || size > max) throw new Error('附件大小或文件类型无效');
    const bytes = new ArrayBuffer(size);
    const destination = new Uint8Array(bytes);
    const block = new ArrayBuffer(Math.min(65536, size));
    let offset = 0;
    while (offset < size) {
      const length = Math.min(block.byteLength, size - offset);
      const count = await fileIo.read(file.fd, block, { length });
      if (!Number.isSafeInteger(count) || count <= 0 || count > length) throw new Error('附件读取不完整');
      destination.set(new Uint8Array(block, 0, count), offset);
      offset += count;
    }
    if (await fileIo.read(file.fd, block, { length: 1 }) !== 0 || !shareAttachmentMatchesType(bytes, source.mimeType)) {
      throw new Error('附件内容与类型或大小不符');
    }
    const metadata = attachmentRecord({ type: source.type, name: source.name, mimeType: source.mimeType,
      id: 'share-file-' + nextFileId++, sizeBytes: size });
    return { metadata, bytes };
  } finally { await fileIo.close(file); }
}

export function acceptIncomingShare(want: Want): Promise<void> {
  if (want.action !== 'ohos.want.action.sendData') return Promise.resolve();
  if (pendingWants >= 8) { reportFailure(); notify(); return Promise.resolve(); }
  pendingWants++;
  ingesting = ingesting.then(async (): Promise<void> => {
    try {
      const data = await systemShare.getSharedData(want);
      const records: SharedTextRecord[] = data.getRecords();
      if (records.length === 0 || records.length > 32) throw new Error('分享条目数量无效');
      const text: SharedTextRecord[] = [];
      const sources: ShareAttachmentSource[] = [];
      for (const item of records) {
        if (item.utd === 'general.hyperlink' || (item.utd === 'general.plain-text' && (item.uri === undefined || item.uri === ''))) {
          text.push(item);
        } else {
          sources.push(shareAttachmentSource(item));
        }
      }
      const parts = sharedParts(text, sources.length > 0);
      if (sources.length > MAX_SHARE_FILES || (sources.length && inbox.full)) throw new Error('待处理分享已满');
      const files: StagedShareFile[] = [];
      let size = 0;
      for (const source of sources) {
        const remaining = Math.min(MAX_BATCH_BYTES - size, MAX_STAGED_BYTES - stagedBytes - size);
        if (remaining <= 0) throw new Error('暂存空间不足');
        const file = await stageFile(source, remaining);
        size += file.metadata.sizeBytes;
        files.push(file);
      }
      const id = inbox.add(parts, files.map(file => file.metadata));
      if (id !== undefined && files.length) { staged.set(id, files); stagedBytes += size; }
      AppStorage.setOrCreate('t3IncomingShareError', '');
    } catch (_) {
      reportFailure();
    } finally {
      pendingWants--;
      notify();
    }
  });
  return ingesting;
}
export function peekIncomingShare(): IncomingTextShare | undefined { return inbox.peek(); }
export function removeIncomingShare(id: number): void {
  const files = staged.get(id);
  if (files) {
    staged.delete(id);
    for (const file of files) stagedBytes -= file.metadata.sizeBytes;
  }
  inbox.remove(id);
  notify();
}

export function removeIncomingShareAttachment(id: number, attachmentId: string): boolean {
  const files = staged.get(id);
  if (!files) return false;
  const index = files.findIndex(item => item.metadata.id === attachmentId);
  if (index < 0 || !inbox.removeAttachment(id, attachmentId)) return false;
  stagedBytes -= files[index].metadata.sizeBytes;
  files.splice(index, 1);
  if (!files.length) staged.delete(id);
  notify();
  return true;
}

export async function withStagedShareAttachment(id: number, attachmentId: string,
  consume: (bytes: ArrayBuffer) => Promise<void>): Promise<void> {
  if (borrowing) throw new Error('正在读取另一个分享附件');
  const copy = staged.get(id)?.find(item => item.metadata.id === attachmentId)?.bytes.slice(0);
  if (!copy) throw new Error('分享附件已失效');
  borrowing = true;
  try { await consume(copy); }
  finally { borrowing = false; }
}

interface ThumbnailResult { frame?: image.PixelMap; }

export async function loadStagedShareThumbnail(id: number, attachmentId: string,
  stillSelected: () => boolean = () => true): Promise<image.PixelMap> {
  const find = (): IncomingShareAttachment | undefined =>
    staged.get(id)?.find(item => item.metadata.id === attachmentId)?.metadata;
  const current = (): boolean => stillSelected() && find()?.type === 'image';
  if (!current()) throw new Error('分享图片已失效');
  if (borrowing) throw new Error('正在读取另一附件，仍可上传原附件');
  const result: ThumbnailResult = {};
  let failure = '无法预览此图片，仍可上传原附件';
  try {
    await withStagedShareAttachment(id, attachmentId, async (bytes: ArrayBuffer): Promise<void> => {
      if (!current()) throw new Error('obsolete');
      const source = image.createImageSource(bytes);
      try {
        const info = await source.getImageInfo(0);
        if (!current()) throw new Error('obsolete');
        if (previewSourceOversized(info.size)) {
          failure = '图片尺寸过大，无法预览，仍可上传原附件';
          throw new Error('oversized');
        }
        const scale = Math.min(1, THUMBNAIL_EDGE / info.size.width, THUMBNAIL_EDGE / info.size.height);
        const desiredSize: image.Size = { width: Math.max(1, Math.floor(info.size.width * scale)),
          height: Math.max(1, Math.floor(info.size.height * scale)) };
        const frame = await source.createPixelMap({ index: 0, editable: false, desiredSize });
        result.frame = frame;
        if (!current()) throw new Error('obsolete');
        const output = (await frame.getImageInfo()).size;
        if (!Number.isSafeInteger(output.width) || !Number.isSafeInteger(output.height) ||
          output.width < 1 || output.height < 1 || output.width > THUMBNAIL_EDGE || output.height > THUMBNAIL_EDGE ||
          output.width * output.height > THUMBNAIL_PIXELS || !previewFrameMatchesViewport(output, info.size)) {
          throw new Error('invalid thumbnail');
        }
      } finally { await source.release().catch(() => {}); }
    });
    const frame = result.frame;
    if (!current() || !frame) throw new Error('obsolete');
    return frame;
  } catch (_) {
    if (result.frame) await result.frame.release().catch(() => {});
    throw new Error(current() ? failure : '分享图片已失效');
  }
}
