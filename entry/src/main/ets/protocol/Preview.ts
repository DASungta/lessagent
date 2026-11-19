export interface PreviewViewport { width: number; height: number; }
export interface PreviewPoint { x: number; y: number; }
export interface PreviewControl { canOperate: boolean; controller: string; generation: number; dialog: boolean; }
export const PREVIEW_MAX_FRAME_BYTES = 2 * 1024 * 1024;
export const PREVIEW_MAX_MESSAGE_CHARS = 65536;
export const PREVIEW_MAX_CONSECUTIVE_OVERSIZE_FRAMES = 3;

const PREVIEW_SOURCE_EDGE = 4096;
const PREVIEW_SOURCE_PIXELS = 8294400;
const PREVIEW_OUTPUT_EDGE = 1920;
const PREVIEW_OUTPUT_PIXELS = 2073600;

function boundedImageSize(size: PreviewViewport, maxEdge: number, maxPixels: number): boolean {
  return Number.isSafeInteger(size.width) && Number.isSafeInteger(size.height) &&
    size.width > 0 && size.height > 0 && size.width <= maxEdge && size.height <= maxEdge &&
    size.width * size.height <= maxPixels;
}
export function previewSourceOversized(source: PreviewViewport): boolean {
  if (!Number.isSafeInteger(source.width) || !Number.isSafeInteger(source.height) || source.width < 1 || source.height < 1) {
    throw new Error('预览 JPEG 原图尺寸信息无效');
  }
  return !boundedImageSize(source, PREVIEW_SOURCE_EDGE, PREVIEW_SOURCE_PIXELS);
}
export function previewDecodeSize(source: PreviewViewport): PreviewViewport {
  if (previewSourceOversized(source)) throw new Error('预览 JPEG 原图尺寸超限');
  const scale = Math.min(1, PREVIEW_OUTPUT_EDGE / source.width, PREVIEW_OUTPUT_EDGE / source.height,
    Math.sqrt(PREVIEW_OUTPUT_PIXELS / (source.width * source.height)));
  return { width: Math.max(1, Math.floor(source.width * scale)), height: Math.max(1, Math.floor(source.height * scale)) };
}
export function previewOutputSize(output: PreviewViewport, source: PreviewViewport): boolean {
  return boundedImageSize(output, PREVIEW_OUTPUT_EDGE, PREVIEW_OUTPUT_PIXELS) &&
    previewFrameMatchesViewport(output, source);
}

export function previewViewport(width: Object, height: Object): PreviewViewport {
  if (typeof width !== 'number' || typeof height !== 'number' || !Number.isFinite(width) || !Number.isFinite(height) ||
    width < 1 || height < 1 || width > 3840 || height > 3840 || width * height > 3840 * 2160) {
    throw new Error('预览画面尺寸无效');
  }
  return { width, height };
}
// Streaming reports CSS coordinates after zoom; these dimensions never allocate a bitmap.
export function previewStreamViewport(width: Object, height: Object): PreviewViewport {
  if (typeof width !== 'number' || typeof height !== 'number' || !Number.isFinite(width) || !Number.isFinite(height) ||
    width < 1 || height < 1 || width > 15360 || height > 15360 || width * height > 3840 * 2160 * 16) {
    throw new Error('预览 CSS 视口尺寸无效');
  }
  return { width, height };
}
export function previewPoint(x: number, y: number, width: number, height: number,
  viewport: PreviewViewport): PreviewPoint | undefined {
  if (viewport.width <= 0 || viewport.height <= 0 || ![x, y, width, height, viewport.width, viewport.height].every((value: number): boolean => Number.isFinite(value)) || width <= 0 || height <= 0) return undefined;
  const scale = Math.min(width / viewport.width, height / viewport.height);
  const left = (width - viewport.width * scale) / 2;
  const top = (height - viewport.height * scale) / 2;
  const px = (x - left) / scale; const py = (y - top) / scale;
  if (px < 0 || py < 0 || px >= viewport.width || py >= viewport.height) return undefined;
  return { x: px, y: py };
}
export function previewControl(value: Record<string, Object>): PreviewControl {
  if (typeof value.canOperate !== 'boolean' || typeof value.controller !== 'string' ||
    !['you', 'agent', 'another-viewer', 'unclaimed'].includes(value.controller) ||
    typeof value.generation !== 'number' || !Number.isSafeInteger(value.generation) || value.generation < 0) {
    throw new Error('预览控制状态无效');
  }
  return { canOperate: value.canOperate, controller: value.controller, generation: value.generation,
    dialog: value.dialog !== null && value.dialog !== undefined };
}
export function previewCanSend(control: PreviewControl | undefined, type: string): boolean {
  return !!control && control.canOperate && (control.controller === 'you' || (type === 'takeControl' && control.controller !== 'another-viewer'));
}
export function previewJpeg(data: ArrayBuffer): void {
  const bytes = new Uint8Array(data);
  if (bytes.length < 4 || bytes.length > PREVIEW_MAX_FRAME_BYTES || bytes[0] !== 255 || bytes[1] !== 216 ||
    bytes[bytes.length - 2] !== 255 || bytes[bytes.length - 1] !== 217) throw new Error('预览 JPEG 帧无效或超过 2 MiB');
}
export function previewMouse(point: PreviewPoint, down: boolean): Object {
  return { type: 'mouse', action: down ? 'down' : 'up', x: point.x, y: point.y,
    button: 'left', buttons: down ? 1 : 0, clickCount: 1, modifiers: 0 };
}
export function previewKey(key: string, down: boolean): Object {
  const code = key === 'Enter' ? 13 : key === 'Backspace' ? 8 : key === 'Tab' ? 9 : key === 'Escape' ? 27 : 0;
  if (!code) throw new Error('不支持的预览按键');
  const input: Record<string, Object> = { type: 'key', action: down ? 'down' : 'up', key, code: key, keyCode: code, modifiers: 0 };
  if (key === 'Enter' && down) input.text = '\r';
  return input;
}
export function previewNavigation(url: string): Object {
  const target = url.trim();
  if (target.length > 2048 || !/^https?:\/\/[^\s]+$/i.test(target) || /[\u0000-\u001f\u007f]/.test(target)) {
    throw new Error('请输入完整的 http(s) 网页地址');
  }
  return { type: 'navigate', url: target };
}

export const PREVIEW_ZOOM_LEVELS: number[] = [0.25, 0.33, 0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4, 5];
export const DEFAULT_PREVIEW_ZOOM_FACTOR = 1;

export interface PreviewSnapshotViewport {
  _tag: string;
  width?: number;
  height?: number;
  presetId?: string;
}
export interface PreviewTab {
  tabId: string;
  url: string;
  title: string;
  zoomFactor?: number;
  viewport?: PreviewSnapshotViewport;
  updatedAt?: string;
}
export interface PreviewZoomResult {
  zoomFactor: number;
  viewport?: PreviewViewport;
  viewportTolerance?: number;
}

function previewSnapshotViewport(value: Object | undefined): PreviewSnapshotViewport | undefined {
  if (value === undefined) return { _tag: 'fill' };
  if (!value || typeof value !== 'object' || Array.isArray(value)) return undefined;
  const raw = value as Record<string, Object>;
  if (raw._tag === 'fill') return { _tag: 'fill' };
  if (raw._tag !== 'freeform' && raw._tag !== 'preset') return undefined;
  if (raw._tag === 'preset' && (typeof raw.presetId !== 'string' || !raw.presetId)) return undefined;
  try {
    const size = previewViewport(raw.width, raw.height);
    if (!Number.isInteger(size.width) || !Number.isInteger(size.height) || size.width < 240 || size.height < 240) return undefined;
    return { _tag: raw._tag as string, width: size.width, height: size.height,
      presetId: raw._tag === 'preset' ? raw.presetId as string : undefined };
  } catch (_) { return undefined; }
}

function snapshotZoom(value: Object | undefined): number | undefined {
  if (value === undefined) return DEFAULT_PREVIEW_ZOOM_FACTOR;
  return typeof value === 'number' && PREVIEW_ZOOM_LEVELS.includes(value) ? value : undefined;
}
function cssViewport(width: number, height: number, zoom: number): PreviewViewport {
  return previewStreamViewport(Math.max(1, Math.round(width / zoom)), Math.max(1, Math.round(height / zoom)));
}
function previewTabIdentity(threadId: string, tabId: string): boolean {
  return !!threadId.trim() && !!tabId.trim() && tabId.length <= 128 && !/[\u0000-\u001f\u007f]/.test(threadId + tabId);
}
export function previewZoomInput(threadId: string, tabId: string, zoomFactor: number): Object {
  if (!previewTabIdentity(threadId, tabId) || !PREVIEW_ZOOM_LEVELS.includes(zoomFactor)) throw new Error('预览缩放或页面标识无效');
  return { threadId, tabId, zoomFactor };
}
export function previewZoomTarget(tab: PreviewTab, zoomFactor: number, measured?: PreviewViewport): PreviewZoomResult {
  const viewport = tab.viewport;
  if (!viewport || tab.zoomFactor === undefined || !PREVIEW_ZOOM_LEVELS.includes(zoomFactor)) throw new Error('当前预览尺寸或缩放比例不可用');
  if (viewport.width !== undefined && viewport.height !== undefined) {
    return { zoomFactor, viewport: cssViewport(viewport.width, viewport.height, zoomFactor) };
  }
  if (!measured) throw new Error('请等待当前预览画面后再缩放');
  const zoomRatio = tab.zoomFactor / zoomFactor;
  return { zoomFactor, viewport: cssViewport(measured.width, measured.height, 1 / zoomRatio),
    viewportTolerance: Math.ceil(zoomRatio / 2 + 0.5) };
}
export function verifyPreviewZoom(value: Object, threadId: string, tab: PreviewTab, expected: PreviewZoomResult): PreviewZoomResult {
  const result = value as Record<string, Object>;
  if (!result || result.threadId !== threadId || result.tabId !== tab.tabId ||
    (result.runtime !== undefined && result.runtime !== 'server')) throw new Error('预览缩放回读环境已变化');
  const viewport = previewSnapshotViewport(result.viewport);
  const before = tab.viewport;
  if (!before || !viewport || viewport._tag !== before._tag || viewport.width !== before.width ||
    viewport.height !== before.height || viewport.presetId !== before.presetId) throw new Error('远端预览尺寸已变化');
  if (result.zoomFactor !== expected.zoomFactor) throw new Error('远端预览缩放尚未确认');
  return expected;
}

export function previewTabs(value: Object, threadId: string): PreviewTab[] {
  const result = value as Record<string, Object>;
  if (!result || !Array.isArray(result.sessions)) throw new Error('预览标签列表无效');
  const tabs: PreviewTab[] = [];
  for (const item of result.sessions as Object[]) {
    if (!item || typeof item !== 'object' || Array.isArray(item)) throw new Error('预览标签记录无效');
    const row = item as Record<string, Object>;
    if (row.threadId !== threadId || row.runtime !== 'server') continue;
    if (typeof row.tabId !== 'string' || !row.tabId.trim() || row.tabId.length > 128 ||
      /[\u0000-\u001f\u007f]/.test(row.tabId) || tabs.some((tab: PreviewTab): boolean => tab.tabId === row.tabId)) {
      throw new Error('预览标签标识无效或重复');
    }
    const nav = (row.navStatus || {}) as Record<string, Object>;
    const url = typeof nav.url === 'string' ? nav.url : '';
    const title = typeof nav.title === 'string' ? nav.title : '';
    tabs.push({ tabId: row.tabId, url, title: title || url || '未命名页面',
      zoomFactor: snapshotZoom(row.zoomFactor), viewport: previewSnapshotViewport(row.viewport),
      ...(typeof row.updatedAt === 'string' ? { updatedAt: row.updatedAt } : {}) });
  }
  return tabs;
}
export function previewNeedsZoomRepair(serverVersion: Object | undefined): boolean {
  return serverVersion === '0.1.10' || serverVersion === 'v0.1.10';
}

const REPAIR_PRESET_IDS: string[] = [
  'iphone-se', 'iphone-xr', 'iphone-12-pro', 'iphone-14-pro-max', 'pixel-7', 'samsung-galaxy-s8-plus',
  'samsung-galaxy-s20-ultra', 'ipad-mini', 'ipad-air', 'ipad-pro', 'surface-pro-7', 'surface-duo',
  'galaxy-z-fold-5', 'asus-zenbook-fold', 'samsung-galaxy-a51-71', 'nest-hub', 'nest-hub-max',
  'desktop-1920x1080', 'desktop-1440x900', 'laptop-1366x768', 'laptop-1280x800', 'ipad-pro-11',
  'iphone-15-pro', 'pixel-8', 'galaxy-s24'
];

function samePreviewViewport(left: PreviewSnapshotViewport | undefined, right: PreviewSnapshotViewport): boolean {
  return !!left && left._tag === right._tag && left.width === right.width && left.height === right.height && left.presetId === right.presetId;
}
function checkRepairState(tab: PreviewTab | undefined, previous: PreviewTab, viewport: PreviewSnapshotViewport): PreviewTab {
  if (!tab || tab.tabId !== previous.tabId || tab.url !== previous.url || tab.title !== previous.title || tab.zoomFactor !== 1 ||
    !samePreviewViewport(tab.viewport, viewport) || !tab.updatedAt || !previous.updatedAt ||
    !Number.isFinite(Date.parse(tab.updatedAt)) || Date.parse(tab.updatedAt) < Date.parse(previous.updatedAt)) {
    throw new Error('预览状态已变化，请选择固定尺寸并应用后核对');
  }
  return tab;
}

export async function repairPreviewZoom100(threadId: string, before: PreviewTab,
  rpc: (method: string, payload: Object) => Promise<Object>, stillControlled: () => boolean): Promise<PreviewZoomResult> {
  const original = before.viewport;
  if (!stillControlled()) throw new Error('请保持当前页面的控制权');
  if (!original || original.width === undefined || original.height === undefined ||
    (original._tag !== 'freeform' && (original._tag !== 'preset' || !original.presetId || !REPAIR_PRESET_IDS.includes(original.presetId)))) {
    throw new Error('请先选择固定尺寸并应用，再恢复 100%');
  }
  if (before.zoomFactor === undefined || !before.updatedAt || !Number.isFinite(Date.parse(before.updatedAt))) {
    throw new Error('无法核对预览版本，请重新连接');
  }
  const width = original.width;
  const height = original.height;
  const temporary: PreviewResizeViewport = { _tag: 'freeform',
    width: width < 3840 && (width + 1) * height <= 3840 * 2160 ? width + 1 : width - 1, height };
  const restore: PreviewResizeViewport = original._tag === 'preset'
    ? { _tag: 'preset', width, height, presetId: original.presetId }
    : { _tag: 'freeform', width, height };
  const apply = async (method: string, payload: Object, previous: PreviewTab, viewport: PreviewSnapshotViewport): Promise<PreviewTab> => {
    if (!stillControlled()) throw new Error('预览环境、页面或控制权已变化');
    const replied = await rpc(method, payload);
    if (!stillControlled()) throw new Error('预览环境、页面或控制权已变化');
    const ack = checkRepairState(previewTabs({ sessions: [replied] }, threadId)[0], previous, viewport);
    const listed = await rpc('preview.list', { threadId });
    if (!stillControlled()) throw new Error('预览环境、页面或控制权已变化');
    const observed = checkRepairState(previewTabs(listed, threadId).find(item => item.tabId === before.tabId), ack, viewport);
    if (observed.updatedAt !== ack.updatedAt) throw new Error('预览状态已变化，请选择固定尺寸并应用后核对');
    return observed;
  };
  const at100 = await apply('preview.adjust', previewZoomInput(threadId, before.tabId, 1), before, original);
  const small = await apply('preview.resize', previewResizeInput(threadId, before.tabId, temporary), at100, temporary);
  await apply('preview.resize', { threadId, tabId: before.tabId, viewport: restore }, small, restore);
  return { zoomFactor: 1, viewport: cssViewport(width, height, 1) };
}

export function previewHistory(delta: number): Object {
  if (delta !== -1 && delta !== 1) throw new Error('预览历史方向无效');
  return { type: 'history', delta };
}

export interface PreviewResizeViewport extends PreviewViewport {
  _tag: string;
  presetId?: string;
}
export interface PreviewResizeChoice {
  label: string;
  viewport: PreviewResizeViewport;
}
export const PREVIEW_RESIZE_CHOICES: PreviewResizeChoice[] = [
  { label: '手机 · 390 × 844', viewport: { _tag: 'preset', presetId: 'iphone-12-pro', width: 390, height: 844 } },
  { label: '平板 · 768 × 1024', viewport: { _tag: 'preset', presetId: 'ipad-mini', width: 768, height: 1024 } },
  { label: '桌面 · 1280 × 800', viewport: { _tag: 'freeform', width: 1280, height: 800 } }
];
export function previewResizeInput(threadId: string, tabId: string, viewport: PreviewResizeViewport): Object {
  const size = previewViewport(viewport.width, viewport.height);
  if (!previewTabIdentity(threadId, tabId) ||
    !Number.isInteger(size.width) || !Number.isInteger(size.height) || size.width < 240 || size.height < 240 ||
    (viewport._tag === 'preset' ? !PREVIEW_RESIZE_CHOICES.some(item =>
      item.viewport.presetId === viewport.presetId && item.viewport._tag === 'preset' &&
      item.viewport.width === size.width && item.viewport.height === size.height)
      : viewport._tag !== 'freeform' || viewport.presetId !== undefined)) {
    throw new Error('预览尺寸或页面标识无效');
  }
  return { threadId, tabId, viewport };
}
export function verifyPreviewResize(value: Object, threadId: string, tabId: string,
  expected: PreviewResizeViewport): PreviewViewport {
  const result = value as Record<string, Object>;
  if (!result || result.threadId !== threadId || result.tabId !== tabId ||
    (result.runtime !== undefined && result.runtime !== 'server')) throw new Error('预览尺寸回读环境已变化');
  const viewport = result.viewport as Record<string, Object>;
  if (!viewport || viewport._tag !== expected._tag || viewport.width !== expected.width ||
    viewport.height !== expected.height || viewport.presetId !== expected.presetId) {
    throw new Error('远端预览尺寸尚未确认');
  }
  const zoom = snapshotZoom(result.zoomFactor);
  if (zoom === undefined) throw new Error('远端预览缩放比例无效');
  return cssViewport(expected.width, expected.height, zoom);
}
export function previewFrameMatchesViewport(frame: PreviewViewport, viewport: PreviewViewport): boolean {
  return Math.abs(frame.width * viewport.height - frame.height * viewport.width) <=
    Math.max(viewport.width, viewport.height) * 2;
}
