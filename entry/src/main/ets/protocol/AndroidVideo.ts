export interface AndroidVideoSize { width: number; height: number; }
export interface AndroidVideoPacket { data: Uint8Array; key: boolean; timestamp: number; sps: Uint8Array | undefined; pps: Uint8Array | undefined; }
export const ANDROID_VIDEO_MAX_PACKET = 4 * 1024 * 1024;

export function androidVideoPacket(raw: ArrayBuffer, fallbackTimestamp: number): AndroidVideoPacket {
  if (raw.byteLength < 4 || raw.byteLength > ANDROID_VIDEO_MAX_PACKET) throw new Error('Android 视频包大小无效');
  let bytes = new Uint8Array(raw); let key = false; let timestamp = fallbackTimestamp;
  const header = new DataView(raw);
  if (raw.byteLength >= 16 && header.getUint32(0, false) === 0x53454d55) {
    if (header.getUint8(4) !== 1) throw new Error('未知 SEMU 视频版本');
    key = (header.getUint8(5) & 1) !== 0;
    timestamp = header.getUint32(8, false) * 4294967296 + header.getUint32(12, false);
    if (!Number.isSafeInteger(timestamp)) throw new Error('视频时间戳超限');
    bytes = bytes.slice(16);
  }
  let sps: Uint8Array | undefined = undefined; let pps: Uint8Array | undefined = undefined;
  const starts: number[] = []; const offsets: number[] = [];
  for (let i = 0; i + 3 < bytes.length; i++) {
    if (bytes[i] !== 0 || bytes[i + 1] !== 0) continue;
    const length = bytes[i + 2] === 1 ? 3 : bytes[i + 2] === 0 && bytes[i + 3] === 1 ? 4 : 0;
    if (length) { starts.push(i); offsets.push(i + length); i += length - 1; }
    if (starts.length > 256) throw new Error('视频 NAL 数量超限');
  }
  if (!starts.length) throw new Error('视频包不是 Annex-B');
  for (let i = 0; i < starts.length; i++) {
    const start = offsets[i]; const end = i + 1 < starts.length ? starts[i + 1] : bytes.length;
    if (start >= end) continue;
    const type = bytes[start] & 31;
    if (type === 5) key = true;
    if (type === 7 || type === 8) {
      if (end - start > 65536) throw new Error('视频参数集超限');
      if (type === 7) sps = bytes.slice(start, end); else pps = bytes.slice(start, end);
    }
  }
  return { data: bytes, key, timestamp, sps, pps };
}

class SpsBits {
  private bytes: Uint8Array;
  private position: number = 0;
  constructor(bytes: Uint8Array) { this.bytes = bytes; }
  read(count: number): number {
    if (count < 0 || count > 32 || this.position + count > this.bytes.length * 8) throw new Error('SPS 数据不足');
    let value = 0;
    for (let i = 0; i < count; i++) { const offset = this.position++; value = value * 2 + ((this.bytes[Math.floor(offset / 8)] >> (7 - offset % 8)) & 1); }
    return value;
  }
  ue(): number {
    let zeros = 0;
    while (this.read(1) === 0) if (++zeros > 24) throw new Error('SPS Exp-Golomb 超限');
    return Math.pow(2, zeros) - 1 + this.read(zeros);
  }
  se(): number { const value = this.ue(); return value % 2 ? (value + 1) / 2 : -value / 2; }
}
export function androidSpsSize(sps: Uint8Array): AndroidVideoSize {
  if (sps.length < 4 || sps.length > 65536 || (sps[0] & 31) !== 7) throw new Error('无效 H.264 SPS');
  const unpacked: number[] = [];
  for (let i = 1; i < sps.length; i++) {
    if (i >= 3 && sps[i] === 3 && sps[i - 1] === 0 && sps[i - 2] === 0) continue;
    unpacked.push(sps[i]);
  }
  const bits = new SpsBits(new Uint8Array(unpacked));
  const profile = bits.read(8); bits.read(8); bits.read(8); bits.ue();
  let chroma = 1; let separate = 0;
  if ([100, 110, 122, 244, 44, 83, 86, 118, 128, 138, 139, 134, 135].includes(profile)) {
    chroma = bits.ue(); if (chroma > 3) throw new Error('SPS 色度无效');
    if (chroma === 3) separate = bits.read(1);
    if (bits.ue() > 6 || bits.ue() > 6) throw new Error('SPS 位深超限');
    bits.read(1);
    if (bits.read(1)) for (let i = 0; i < (chroma === 3 ? 12 : 8); i++) {
      if (!bits.read(1)) continue;
      let last = 8; let next = 8;
      for (let j = 0; j < (i < 6 ? 16 : 64); j++) {
        if (next !== 0) next = ((last + bits.se()) % 256 + 256) % 256;
        last = next === 0 ? last : next;
      }
    }
  }
  if (bits.ue() > 12) throw new Error('SPS 帧号范围无效');
  const order = bits.ue();
  if (order === 0) { if (bits.ue() > 12) throw new Error('SPS 顺序范围无效'); }
  else if (order === 1) {
    bits.read(1); bits.se(); bits.se(); const count = bits.ue();
    if (count > 256) throw new Error('SPS 顺序周期超限');
    for (let i = 0; i < count; i++) bits.se();
  } else if (order !== 2) throw new Error('SPS 顺序类型无效');
  if (bits.ue() > 32) throw new Error('SPS 参考帧超限');
  bits.read(1); const columns = bits.ue() + 1; const rows = bits.ue() + 1;
  const frameOnly = bits.read(1); if (!frameOnly) bits.read(1); bits.read(1);
  let left = 0, right = 0, top = 0, bottom = 0;
  if (bits.read(1)) { left = bits.ue(); right = bits.ue(); top = bits.ue(); bottom = bits.ue(); }
  const chromaArray = separate ? 0 : chroma;
  const cropX = chromaArray === 1 || chromaArray === 2 ? 2 : 1;
  const cropY = (chromaArray === 1 ? 2 : 1) * (2 - frameOnly);
  const width = columns * 16 - (left + right) * cropX;
  const height = rows * 16 * (2 - frameOnly) - (top + bottom) * cropY;
  if (width < 1 || height < 1 || width > 4096 || height > 4096 || width * height > 10000000) throw new Error('H.264 分辨率超限');
  return { width, height };
}
export function androidKeyframe(data: Uint8Array, sps: Uint8Array, pps: Uint8Array): ArrayBuffer {
  const size = data.length + sps.length + pps.length + 8;
  if (size > ANDROID_VIDEO_MAX_PACKET) throw new Error('关键帧超过解码限额');
  const bytes = new Uint8Array(size); bytes.set([0, 0, 0, 1]); bytes.set(sps, 4);
  bytes.set([0, 0, 0, 1], 4 + sps.length); bytes.set(pps, 8 + sps.length); bytes.set(data, 8 + sps.length + pps.length);
  return bytes.buffer;
}

export interface AndroidControlInput { type: string; action?: string; x?: number; y?: number; text?: string; keycode?: number; }
export interface AndroidControlPoint { x: number; y: number; }
export function androidControlPoint(x: number, y: number, width: number, height: number,
  video: AndroidVideoSize, clamp: boolean = false): AndroidControlPoint | undefined {
  if (![x, y, width, height, video.width, video.height].every((v: number): boolean => Number.isFinite(v)) ||
    width <= 0 || height <= 0 || video.width <= 0 || video.height <= 0) return undefined;
  const scale = Math.min(width / video.width, height / video.height);
  const px = (x - (width - video.width * scale) / 2) / (video.width * scale);
  const py = (y - (height - video.height * scale) / 2) / (video.height * scale);
  if (!clamp && (px < 0 || py < 0 || px > 1 || py > 1)) return undefined;
  return { x: Math.max(0, Math.min(1, px)), y: Math.max(0, Math.min(1, py)) };
}
export function androidTouch(action: string, point: AndroidControlPoint): AndroidControlInput {
  if (!['down', 'move', 'up'].includes(action) || !Number.isFinite(point.x) || !Number.isFinite(point.y) ||
    point.x < 0 || point.x > 1 || point.y < 0 || point.y > 1) throw new Error('Android 触控数据无效');
  return { type: 'touch', action, x: point.x, y: point.y };
}
export function androidButton(type: string): AndroidControlInput {
  if (!['home', 'back', 'recents'].includes(type)) throw new Error('Android 按键无效');
  return { type };
}
export function androidKey(keycode: number): AndroidControlInput {
  if (![19, 20, 21, 22, 61, 66, 67, 112, 122, 123, 92, 93].includes(keycode)) throw new Error('Android 键码无效');
  return { type: 'key', keycode };
}
export function androidTextInputs(value: string): AndroidControlInput[] {
  const chunks: AndroidControlInput[] = []; let chunk = ''; let size = 0;
  for (let i = 0; i < value.length; i++) {
    const code = value.codePointAt(i) || 0;
    if (code >= 0xd800 && code <= 0xdfff) throw new Error('文字包含不完整的 Unicode 字符');
    const char = code > 0xffff ? value.slice(i, i + 2) : value[i];
    if (code > 0xffff) i++;
    const bytes = code <= 0x7f ? 1 : code <= 0x7ff ? 2 : code <= 0xffff ? 3 : 4;
    if (size + bytes > 300) { chunks.push({ type: 'text', text: chunk }); chunk = ''; size = 0; }
    if (chunks.length >= 64) throw new Error('设备文字超过 64 个输入包，请分批发送');
    chunk += char; size += bytes;
  }
  if (chunk) chunks.push({ type: 'text', text: chunk });
  return chunks;
}
export function androidControlJson(input: AndroidControlInput): string {
  if (input.type === 'touch') {
    if (input.x === undefined || input.y === undefined || input.action === undefined) throw new Error('触控字段缺失');
    return JSON.stringify(androidTouch(input.action, { x: input.x, y: input.y }));
  }
  if (input.type === 'key' && input.keycode !== undefined) return JSON.stringify(androidKey(input.keycode));
  if (input.type === 'text' && typeof input.text === 'string') {
    const chunks = androidTextInputs(input.text);
    if (chunks.length !== 1) throw new Error('文字包必须为 1–300 UTF-8 字节');
    return JSON.stringify(chunks[0]);
  }
  return JSON.stringify(androidButton(input.type));
}
