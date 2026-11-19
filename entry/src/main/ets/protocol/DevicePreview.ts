export interface DeviceStreamAccess { mjpegUrl: string; inputUrl: string; }
export interface DeviceScreen { width: number; height: number; orientation: string; inputUnavailable: boolean; }
export interface DevicePoint { x: number; y: number; }
export const DEVICE_FRAME_MAX = 4 * 1024 * 1024;
const HEADER_MAX = 8192;
export const DEVICE_ORIENTATIONS: string[] = ['portrait', 'landscape_left', 'portrait_upside_down', 'landscape_right'];

function ascii(value: string): Uint8Array {
  const bytes = new Uint8Array(value.length);
  for (let i = 0; i < value.length; i++) bytes[i] = value.charCodeAt(i);
  return bytes;
}
function find(bytes: Uint8Array, needle: Uint8Array, start: number = 0): number {
  for (let i = start; i <= bytes.length - needle.length; i++) {
    let match = true;
    for (let j = 0; j < needle.length; j++) if (bytes[i + j] !== needle[j]) { match = false; break; }
    if (match) return i;
  }
  return -1;
}
function headerText(bytes: Uint8Array): string {
  let text = '';
  for (let i = 0; i < bytes.length; i++) text += String.fromCharCode(bytes[i]);
  return text;
}

export class DeviceMjpegParser {
  private buffer: Uint8Array = new Uint8Array(0);
  private boundary: Uint8Array;
  private bodyBoundary: Uint8Array;
  private inBody: boolean = false;
  private bodyLength: number = -1;
  private scanOffset: number = 0;
  private ended: boolean = false;
  constructor(contentType: string) {
    const match = /^multipart\/x-mixed-replace\s*;[^\r\n]*\bboundary=(?:"([^"\r\n]+)"|([^;\s]+))/i.exec(contentType);
    const value = match ? match[1] || match[2] : '';
    if (!value || value.length > 100 || !/^[\x21-\x7e]+$/.test(value)) throw new Error('设备未提供可用的 MJPEG 流');
    this.boundary = ascii('--' + value); this.bodyBoundary = ascii('\r\n--' + value);
  }
  push(chunk: ArrayBuffer): ArrayBuffer[] {
    if (this.ended) return [];
    if (chunk.byteLength > DEVICE_FRAME_MAX + HEADER_MAX || this.buffer.length + chunk.byteLength > DEVICE_FRAME_MAX + HEADER_MAX) {
      throw new Error('设备帧缓冲超过限额');
    }
    const joined = new Uint8Array(this.buffer.length + chunk.byteLength);
    joined.set(this.buffer); joined.set(new Uint8Array(chunk), this.buffer.length); this.buffer = joined;
    const frames: ArrayBuffer[] = [];
    while (this.buffer.length) {
      if (!this.inBody) {
        const start = find(this.buffer, this.boundary);
        if (start < 0) { if (this.buffer.length > HEADER_MAX) throw new Error('设备帧边界无效'); break; }
        const markerEnd = start + this.boundary.length;
        if (this.buffer.length < markerEnd + 2) break;
        if (this.buffer[markerEnd] === 45 && this.buffer[markerEnd + 1] === 45) { this.ended = true; this.buffer = new Uint8Array(0); break; }
        if (this.buffer[markerEnd] !== 13 || this.buffer[markerEnd + 1] !== 10) throw new Error('设备帧边界无效');
        const end = find(this.buffer, ascii('\r\n\r\n'), markerEnd);
        if (end < 0) { if (this.buffer.length > HEADER_MAX) throw new Error('设备帧头超过限额'); break; }
        if (end - markerEnd > HEADER_MAX) throw new Error('设备帧头超过限额');
        const headers = headerText(this.buffer.slice(markerEnd, end));
        if (!/content-type:\s*image\/jpeg\s*(?:\r\n|$)/i.test(headers)) throw new Error('设备帧类型不是 JPEG');
        const length = /content-length:\s*(\d+)\s*(?:\r\n|$)/i.exec(headers);
        if (/content-length:/i.test(headers) && !length) throw new Error('设备帧长度无效');
        this.bodyLength = length ? Number(length[1]) : -1;
        if (this.bodyLength > DEVICE_FRAME_MAX || this.bodyLength >= 0 && this.bodyLength < 4) throw new Error('设备帧长度无效');
        this.buffer = this.buffer.slice(end + 4); this.inBody = true; this.scanOffset = 0;
      }
      let end = this.bodyLength;
      if (end < 0) {
        end = find(this.buffer, this.bodyBoundary, this.scanOffset);
        if (end < 0) { this.scanOffset = Math.max(0, this.buffer.length - this.bodyBoundary.length); break; }
      } else if (this.buffer.length < end) break;
      const frame = this.buffer.slice(0, end);
      if (frame.length < 4 || frame.length > DEVICE_FRAME_MAX || frame[0] !== 255 || frame[1] !== 216 || frame[end - 2] !== 255 || frame[end - 1] !== 217) {
        throw new Error('设备 JPEG 帧无效');
      }
      frames.push(frame.buffer); this.buffer = this.buffer.slice(end); this.inBody = false; this.bodyLength = -1;
      if (frames.length > 32) throw new Error('设备单批帧数超过限额');
    }
    return frames;
  }
}

export function deviceScreen(value: Record<string, Object>): DeviceScreen {
  if (typeof value.width !== 'number' || typeof value.height !== 'number' ||
    !Number.isFinite(value.width) || !Number.isFinite(value.height) || value.width < 1 || value.height < 1 ||
    value.width > 4096 || value.height > 4096 || value.width * value.height > 10000000 ||
    typeof value.orientation !== 'string' || !DEVICE_ORIENTATIONS.includes(value.orientation)) throw new Error('设备屏幕配置无效');
  return { width: value.width, height: value.height, orientation: value.orientation, inputUnavailable: value.inputUnavailable === true };
}
export function deviceRotation(screen: DeviceScreen): number {
  if (screen.width > screen.height) return 0;
  return screen.orientation === 'landscape_left' ? 90 : screen.orientation === 'landscape_right' ? -90 :
    screen.orientation === 'portrait_upside_down' ? 180 : 0;
}
export function devicePoint(x: number, y: number, width: number, height: number, screen: DeviceScreen): DevicePoint | undefined {
  if (![x, y, width, height].every((v: number): boolean => Number.isFinite(v)) || width <= 0 || height <= 0) return undefined;
  const angle = deviceRotation(screen);
  const sideways = Math.abs(angle) === 90;
  const w = sideways ? screen.height : screen.width; const h = sideways ? screen.width : screen.height;
  const scale = Math.min(width / w, height / h);
  const px = (x - (width - w * scale) / 2) / (w * scale);
  const py = (y - (height - h * scale) / 2) / (h * scale);
  if (px < 0 || py < 0 || px > 1 || py > 1) return undefined;
  return angle === 90 ? { x: py, y: 1 - px } : angle === -90 ? { x: 1 - py, y: px } :
    angle === 180 ? { x: 1 - px, y: 1 - py } : { x: px, y: py };
}
export function deviceTouch(phase: string, point: DevicePoint): Object {
  if (!['begin', 'move', 'end'].includes(phase) || !Number.isFinite(point.x) || !Number.isFinite(point.y) ||
    point.x < 0 || point.x > 1 || point.y < 0 || point.y > 1) throw new Error('设备触控坐标无效');
  return { type: phase, x: point.x, y: point.y };
}
export function deviceButton(button: string): Object {
  if (!['home', 'app_switcher'].includes(button)) throw new Error('不支持的设备按键');
  return { button };
}
export function deviceNextOrientation(screen: DeviceScreen): Object {
  const index = DEVICE_ORIENTATIONS.indexOf(screen.orientation);
  return { orientation: DEVICE_ORIENTATIONS[(index + 1) % DEVICE_ORIENTATIONS.length] };
}

export function deviceKey(usage: number, down: boolean): Object {
  if (![40, 41, 42, 43, 79, 80, 81, 82].includes(usage)) throw new Error('不支持的设备 HID 按键');
  return { type: down ? 'down' : 'up', usage };
}

export interface DevicePreviewChoice {
  hostId: string; id: string; platform: string; name: string; version: string;
  booted: boolean; physical: boolean; hostLabel: string; hostKind: string; supported: boolean; reason: string;
}
export function safeDeviceHubBase(value: Object): string {
  if (typeof value !== 'string' || value.length > 256 || !/^\/api\/[A-Za-z0-9_-]+(?:\/[A-Za-z0-9_-]+)*\/?$/.test(value)) {
    throw new Error('设备 Hub 路径无效，已阻止申请或传递媒体票据');
  }
  return value.replace(/\/$/, '');
}
function deviceIdentifier(value: Object, max: number): string {
  if (typeof value !== 'string' || !value.trim() || value.length > max || /[\u0000-\u001f\u007f]/.test(value)) {
    throw new Error('设备或主机标识无效');
  }
  return value;
}
export function deviceChoices(devices: Object[], hosts: Object[]): DevicePreviewChoice[] {
  if (devices.length > 500 || hosts.length > 100) throw new Error('设备清单超过显示限额');
  const hostLabels: Map<string, string> = new Map();
  const hostKinds: Map<string, string> = new Map();
  for (const value of hosts) {
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('设备主机清单无效');
    const host = value as Record<string, Object>;
    const id = deviceIdentifier(host.id, 128);
    if (hostKinds.has(id)) throw new Error('设备主机标识重复');
    hostLabels.set(id, typeof host.label === 'string' ? host.label.slice(0, 256) : id);
    hostKinds.set(id, typeof host.kind === 'string' ? host.kind : 'unknown');
  }
  const results: DevicePreviewChoice[] = [];
  const keys: Set<string> = new Set();
  for (const value of devices) {
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('设备清单无效');
    const row = value as Record<string, Object>;
    const hostId = deviceIdentifier(row.hostId, 128); const id = deviceIdentifier(row.id, 256);
    const key = JSON.stringify([hostId, id]);
    if (keys.has(key)) throw new Error('设备标识重复'); keys.add(key);
    const platform = typeof row.platform === 'string' ? row.platform : 'unknown';
    const hostKind = hostKinds.get(hostId) || 'unknown';
    const physical = row.physical !== false;
    const supported = (platform === 'ios' || platform === 'android') && !physical && (hostKind === 'local' || hostKind === 'ssh');
    const reason = platform !== 'ios' && platform !== 'android' ? '尚未支持此设备平台' : physical ? '当前只支持模拟器，不支持真机' :
        hostKind === 'eas' || hostKind === 'simlock' ? '此宿主可能仅支持 WebRTC，当前未接入' :
          !supported ? '设备主机类型未知，不能建立媒体连接' : platform === 'android' ? '原生 H.264 画面与竖屏控制' : row.booted === true ? '可打开 MJPEG 设备预览' : '打开时需由服务端启动模拟器';
    results.push({ hostId, id, platform, name: typeof row.name === 'string' ? row.name.slice(0, 256) : id,
      version: typeof row.version === 'string' ? row.version.slice(0, 128) : '', booted: row.booted === true,
      physical, hostLabel: hostLabels.get(hostId) || hostId, hostKind, supported, reason });
  }
  return results;
}
