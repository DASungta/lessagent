import { picker, fileIo, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import { boundAttachmentFileName } from '../protocol/R4';
import { client, T3Client } from './T3Client';

interface QueuedAttachment {
  uri: string;
  photo: boolean;
}

const MAX_IMAGE_BYTES = 10 * 1024 * 1024;
const MAX_FILE_BYTES = 50 * 1024 * 1024;

// shortcut: each document is read into memory; use streaming before raising the 50 MiB contract cap.
export class AttachmentPicker {
  private owner: T3Client;
  constructor(owner: T3Client = client) { this.owner = owner; }
  belongsTo(owner: T3Client): boolean { return this.owner === owner; }
  private uris: QueuedAttachment[] = [];
  private scope: string = '';
  private revision: number = 0;
  private currentScope(): string {
    if (this.owner.draftScope) return this.owner.connectedBase + '\n' + this.owner.uploadEnvironmentId + '\n' + this.owner.draftScope;
    const recovery = this.owner.recovery;
    return recovery ? recovery.base + '\n' + recovery.environmentId + '\n' + recovery.threadId : '';
  }
  canRetry(): boolean {
    const scope = this.currentScope();
    return this.uris.length > 0 && !!scope && this.scope === scope;
  }
  async choose(): Promise<boolean> {
    const scope = this.currentScope();
    const revision = ++this.revision;
    // The system picker can pause the connection. Only the upload itself needs a live generation.
    const captured = this.owner.captureAttachmentTarget(false);
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 10;
    const selected = await new picker.DocumentViewPicker().select(options);
    if (!selected.length) return false;
    if (revision !== this.revision || !captured() || scope !== this.currentScope()) throw new Error('附件目标已变化，请重新选择');
    this.uris = selected.map((uri: string): QueuedAttachment => ({ uri, photo: false }));
    this.scope = scope;
    return await this.retry();
  }
  async choosePhotos(): Promise<boolean> {
    const scope = this.currentScope();
    const revision = ++this.revision;
    // The system picker can pause the connection. Only the upload itself needs a live generation.
    const captured = this.owner.captureAttachmentTarget(false);
    const options = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 10;
    const result = await new photoAccessHelper.PhotoViewPicker().select(options);
    const selected = result && Array.isArray(result.photoUris) ? result.photoUris : [];
    if (!selected.length) return false;
    if (revision !== this.revision || !captured() || scope !== this.currentScope()) throw new Error('附件目标已变化，请重新选择');
    this.uris = selected.map((uri: string): QueuedAttachment => ({ uri, photo: true }));
    this.scope = scope;
    return await this.retry();
  }
  clear(): void { this.revision++; this.uris = []; this.scope = ''; }
  cancel(): void { this.clear(); this.owner.cancelUpload(); }
  async retry(): Promise<boolean> {
    if (!this.uris.length || this.scope !== this.currentScope()) throw new Error('请在当前会话重新选择附件');
    const revision = ++this.revision;
    const captured = this.owner.captureAttachmentTarget();
    const current = (): boolean => revision === this.revision && captured() && this.scope === this.currentScope();
    while (this.uris.length) {
      const item = this.uris[0];
      await this.upload(item, current);
      if (!current()) throw new Error('附件目标已变化，请重新选择');
      this.uris.shift();
    }
    return true;
  }
  private fileName(uri: string, fallback: string): string {
    const name = new fileUri.FileUri(uri).name || '';
    return boundAttachmentFileName(name, fallback);
  }
  private jpegName(name: string): string {
    const dot = name.lastIndexOf('.');
    const stem = dot > 0 ? name.slice(0, dot) : name;
    return boundAttachmentFileName((stem || 'photo') + '.jpg', 'photo.jpg');
  }
  private mime(name: string): string {
    const lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.txt') || lower.endsWith('.md')) return 'text/plain';
    return 'application/octet-stream';
  }
  private async transcodeToJpeg(fd: number): Promise<ArrayBuffer> {
    const source = image.createImageSource(fd);
    if (!source) throw new Error('该图片格式暂不支持，请选择 JPEG/PNG/GIF/WebP 图片');
    const packer = image.createImagePacker();
    try {
      const options: image.PackingOption = { format: 'image/jpeg', quality: 90 };
      const bytes = await packer.packToData(source, options);
      if (bytes.byteLength < 1 || bytes.byteLength > MAX_IMAGE_BYTES) throw new Error('请选择 1 字节至 10 MiB 的图片');
      return bytes;
    } catch (error) {
      if (error instanceof Error && error.message.includes('10 MiB')) throw error;
      throw new Error('该图片格式暂不支持，请选择 JPEG/PNG/GIF/WebP 图片');
    } finally {
      await packer.release().catch(() => {});
      await source.release().catch(() => {});
    }
  }
  private async upload(item: QueuedAttachment, current: () => boolean): Promise<void> {
    const rawName = this.fileName(item.uri, item.photo ? 'photo.jpg' : 'attachment');
    const detectedMime = this.mime(rawName);
    const supportedImage = detectedMime.startsWith('image/');
    const needsTranscode = item.photo && !supportedImage;
    const uploadName = needsTranscode ? this.jpegName(rawName) : rawName;
    const mimeType = needsTranscode ? 'image/jpeg' : detectedMime;
    const isImage = supportedImage || needsTranscode;
    const file = await fileIo.open(item.uri, fileIo.OpenMode.READ_ONLY);
    try {
      const size = (await fileIo.stat(file.fd)).size;
      let bytes: ArrayBuffer;
      if (needsTranscode) {
        if (size < 1 || size > MAX_FILE_BYTES) throw new Error('请选择 1 字节至 50 MiB 的图片文件');
        bytes = await this.transcodeToJpeg(file.fd);
      } else {
        const max = isImage ? MAX_IMAGE_BYTES : MAX_FILE_BYTES;
        if (size < 1 || size > max) throw new Error(isImage ? '请选择 1 字节至 10 MiB 的图片' : '请选择 1 字节至 50 MiB 的文件');
        bytes = new ArrayBuffer(size);
        let offset = 0;
        while (offset < size) {
          const chunk = new ArrayBuffer(Math.min(64 * 1024, size - offset));
          const count = await fileIo.read(file.fd, chunk);
          if (count <= 0) throw new Error('文件读取不完整，请重新选择');
          new Uint8Array(bytes).set(new Uint8Array(chunk, 0, count), offset);
          offset += count;
        }
      }
      if (!current()) throw new Error('会话已变更，请重新选择附件');
      await this.owner.upload(uploadName, bytes, mimeType, isImage ? 'image' : 'file', current);
    } finally { await fileIo.close(file); }
  }
}
