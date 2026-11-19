import { picker, fileIo, fileUri } from '@kit.CoreFileKit';
import { client, T3Client } from './T3Client';

// shortcut: each document is read into memory; use streaming before raising the 50 MiB contract cap.
export class AttachmentPicker {
  private owner: T3Client;
  constructor(owner: T3Client = client) { this.owner = owner; }
  belongsTo(owner: T3Client): boolean { return this.owner === owner; }
  private uris: string[] = [];
  private scope: string = '';
  private revision: number = 0;
  private currentScope(): string {
    if (this.owner.draftScope) return this.owner.connectedBase + '\n' + this.owner.uploadEnvironmentId + '\n' + this.owner.draftScope;
    const recovery = this.owner.recovery;
    return recovery ? recovery.base + '\n' + recovery.environmentId + '\n' + recovery.threadId : '';
  }
  async choose(): Promise<void> {
    const scope = this.currentScope();
    const revision = ++this.revision;
    // The system picker can pause the connection. Only the upload itself needs a live generation.
    const captured = this.owner.captureAttachmentTarget(false);
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 10;
    const selected = await new picker.DocumentViewPicker().select(options);
    if (!selected.length) return;
    if (revision !== this.revision || !captured() || scope !== this.currentScope()) throw new Error('附件目标已变化，请重新选择');
    this.uris = selected;
    this.scope = scope;
    await this.retry();
  }
  clear(): void { this.revision++; this.uris = []; this.scope = ''; }
  cancel(): void { this.clear(); this.owner.cancelUpload(); }
  async retry(): Promise<void> {
    if (!this.uris.length || this.scope !== this.currentScope()) throw new Error('请在当前会话重新选择附件');
    const revision = ++this.revision;
    const captured = this.owner.captureAttachmentTarget();
    const current = (): boolean => revision === this.revision && captured() && this.scope === this.currentScope();
    while (this.uris.length) {
      const uri = this.uris[0];
      await this.upload(uri, current);
      if (!current()) throw new Error('附件目标已变化，请重新选择');
      this.uris.shift();
    }
  }
  private mime(uri: string): string {
    const name = new fileUri.FileUri(uri).name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
    if (name.endsWith('.gif')) return 'image/gif';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.pdf')) return 'application/pdf';
    if (name.endsWith('.json')) return 'application/json';
    if (name.endsWith('.txt') || name.endsWith('.md')) return 'text/plain';
    return 'application/octet-stream';
  }
  private async upload(uri: string, current: () => boolean): Promise<void> {
    const mimeType = this.mime(uri);
    const image = mimeType.startsWith('image/');
    const max = image ? 10 * 1024 * 1024 : 50 * 1024 * 1024;
    const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const size = (await fileIo.stat(file.fd)).size;
      if (size < 1 || size > max) throw new Error(image ? '请选择 1 字节至 10 MiB 的图片' : '请选择 1 字节至 50 MiB 的文件');
      const bytes = new ArrayBuffer(size);
      let offset = 0;
      while (offset < size) {
        const chunk = new ArrayBuffer(Math.min(64 * 1024, size - offset));
        const count = await fileIo.read(file.fd, chunk);
        if (count <= 0) throw new Error('文件读取不完整，请重新选择');
        new Uint8Array(bytes).set(new Uint8Array(chunk, 0, count), offset);
        offset += count;
      }
      if (!current()) throw new Error('会话已变更，请重新选择附件');
      await this.owner.upload(new fileUri.FileUri(uri).name, bytes, mimeType, image ? 'image' : 'file', current);
    } finally { await fileIo.close(file); }
  }
}
