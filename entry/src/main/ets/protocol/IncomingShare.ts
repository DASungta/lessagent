import { DraftAttachment, R4_MAX_INPUT_CHARS } from './R4';

export const MAX_SHARED_TEXT_CHARS = R4_MAX_INPUT_CHARS;
export interface SharedTextRecord { utd: string; content?: string; uri?: string; }
export type IncomingShareAttachment = DraftAttachment;
export interface ShareAttachmentSource { uri: string; type: string; name: string; mimeType: string; }
export interface SharePart { id: number; kind: string; text: string; }
export interface IncomingTextShare { id: number; parts: SharePart[]; attachments?: IncomingShareAttachment[]; }

export function shareDraftText(parts: SharePart[]): string {
  return parts.filter((part: SharePart) => !!part.text.trim()).map((part: SharePart) => part.text).join('\n\n');
}

export function sharedParts(records: SharedTextRecord[], allowEmpty: boolean = false): SharePart[] {
  if ((!allowEmpty && records.length === 0) || records.length > 32) throw new Error('分享内容为空或条目过多');
  const parts: SharePart[] = [];
  let length = 0;
  for (let index = 0; index < records.length; index++) {
    const record = records[index];
    if (record.utd !== 'general.plain-text' && record.utd !== 'general.hyperlink') {
      throw new Error('目前仅支持分享纯文字或网页链接，请移除其他附件');
    }
    if (typeof record.content !== 'string' || record.content.includes('\u0000')) throw new Error('分享文字无效');
    const link = record.utd === 'general.hyperlink';
    const value = link ? record.content.trim() : record.content;
    if (!value.trim()) continue;
    if (link && !/^https?:\/\/[^\s]+$/i.test(value)) throw new Error('分享链接必须是 HTTP 或 HTTPS 地址');
    length += value.length + (parts.length > 0 ? 2 : 0);
    if (length > MAX_SHARED_TEXT_CHARS) throw new Error('分享文字过长，请缩短后重新分享');
    parts.push({ id: index + 1, kind: link ? 'link' : 'text', text: value });
  }
  if (!allowEmpty && parts.length === 0) throw new Error('分享文字为空');
  return parts;
}

export function shareAttachmentSource(record: SharedTextRecord): ShareAttachmentSource {
  const uri = record.uri;
  if (typeof uri !== 'string' || uri.length > 4096 || /[?#\\\x00-\x20\x7f]/.test(uri)) throw new Error('附件 URI 无效');
  const docs = 'file://docs/storage/Users/currentUser/';
  const media = 'file://media/Photo/';
  const isMedia = uri.startsWith(media);
  if (!uri.startsWith(docs) && !isMedia) throw new Error('只接受系统文件或相册共享的文件');
  const segments = uri.slice(isMedia ? media.length : docs.length).split('/').map(part => decodeURIComponent(part));
  if (segments.some(part => !part || part === '.' || part === '..' || /[/%?#\\\x00-\x1f\x7f]/.test(part))) {
    throw new Error('附件路径无效');
  }
  if (isMedia && (segments.length !== 3 || !/^\d+$/.test(segments[0]))) throw new Error('相册附件 URI 无效');
  const name = segments[segments.length - 1];
  if (name.length > 255 || !name.trim()) throw new Error('附件名称无效');
  const dot = name.lastIndexOf('.');
  const ext = dot > 0 ? name.slice(dot + 1).toLowerCase() : '';
  const mimeType = ext === 'txt' ? 'text/plain' : ext === 'jpg' || ext === 'jpeg' ? 'image/jpeg' :
    ext === 'png' ? 'image/png' : ext === 'gif' ? 'image/gif' : ext === 'webp' ? 'image/webp' : '';
  const type = mimeType.startsWith('image/') ? 'image' : 'file';
  const utd = record.utd;
  if (!mimeType || (isMedia && type !== 'image') ||
    (utd !== 'general.file' && !(type === 'file' ? utd === 'general.plain-text' :
      utd === 'general.image' || utd === 'general.' + mimeType.slice('image/'.length)))) {
    throw new Error('仅支持 TXT、JPEG、PNG、GIF 或 WebP 分享附件');
  }
  return { uri, type, name, mimeType };
}

export function shareAttachmentMatchesType(buffer: ArrayBuffer, mimeType: string): boolean {
  const bytes = new Uint8Array(buffer);
  const signature = (expected: number[], start: number = 0): boolean =>
    expected.every((value: number, offset: number): boolean => bytes[start + offset] === value);
  if (mimeType === 'image/jpeg') return signature([255, 216, 255]) && signature([255, 217], bytes.length - 2);
  if (mimeType === 'image/png') return signature([137, 80, 78, 71, 13, 10, 26, 10]);
  if (mimeType === 'image/gif') return signature([71, 73, 70, 56]) && (bytes[4] === 55 || bytes[4] === 57) && bytes[5] === 97;
  if (mimeType === 'image/webp') return signature([82, 73, 70, 70]) && signature([87, 69, 66, 80], 8);
  if (mimeType !== 'text/plain') return false;
  for (let index = 0; index < bytes.length; index++) {
    const lead = bytes[index];
    if (lead === 0) return false;
    if (lead < 128) continue;
    const extra = lead >= 194 && lead <= 223 ? 1 : lead >= 224 && lead <= 239 ? 2 : lead >= 240 && lead <= 244 ? 3 : 0;
    if (!extra || index + extra >= bytes.length) return false;
    const first = bytes[index + 1];
    if ((lead === 224 && first < 160) || (lead === 237 && first > 159) ||
      (lead === 240 && first < 144) || (lead === 244 && first > 143)) return false;
    for (let n = 0; n < extra; n++) {
      const byte = bytes[++index];
      if (byte < 128 || byte > 191) return false;
    }
  }
  return true;
}

function copyParts(parts: SharePart[]): SharePart[] {
  return parts.map((part: SharePart): SharePart => ({ id: part.id, kind: part.kind, text: part.text }));
}
export class IncomingShareQueue {
  private items: IncomingTextShare[] = [];
  private nextId: number = 1;
  get full(): boolean { return this.items.length >= 8; }
  add(parts: SharePart[], attachments: IncomingShareAttachment[] = []): number | undefined {
    const text = shareDraftText(parts);
    if ((!text.trim() && !attachments.length) || text.length > MAX_SHARED_TEXT_CHARS || text.includes('\u0000')) throw new Error('分享内容无效');
    if (!attachments.length && this.items.some((item: IncomingTextShare) => !item.attachments?.length && item.parts.length === parts.length &&
      item.parts.every((part: SharePart, index: number) => part.kind === parts[index].kind && part.text === parts[index].text))) return undefined;
    if (this.full) throw new Error('待处理分享已满，请先处理已有内容');
    const id = this.nextId++;
    this.items.push({ id, parts: copyParts(parts), attachments: attachments.length ? attachments.map(item => ({ ...item })) : undefined });
    return id;
  }
  peek(): IncomingTextShare | undefined {
    const item = this.items[0];
    return item ? { id: item.id, parts: copyParts(item.parts),
      attachments: item.attachments?.map(attachment => ({ ...attachment })) } : undefined;
  }
  removeAttachment(id: number, attachmentId: string): boolean {
    const item = this.items.find(entry => entry.id === id);
    const attachments = item?.attachments;
    if (!item || !attachments?.some(attachment => attachment.id === attachmentId)) return false;
    const remaining = attachments.filter(attachment => attachment.id !== attachmentId);
    item.attachments = remaining.length ? remaining : undefined;
    return true;
  }
  remove(id: number): void { this.items = this.items.filter(item => item.id !== id); }
}
