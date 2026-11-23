// Pure media filename, extension, UTD, data-URI and gallery eligibility helpers
// shared across Markdown media, message attachments, and workspace file previews.

export interface ParsedDataUri {
  mimeType: string;
  base64: string;
  extension: string;
  kind: string;
}

const MIME_TO_EXT: Record<string, string> = {
  'image/png': 'png',
  'image/jpeg': 'jpg',
  'image/jpg': 'jpg',
  'image/gif': 'gif',
  'image/webp': 'webp',
  'image/bmp': 'bmp',
  'image/x-ms-bmp': 'bmp',
  'image/heic': 'heic',
  'image/heif': 'heif',
  'image/avif': 'avif',
  'image/svg+xml': 'svg',
  'image/x-icon': 'ico',
  'image/vnd.microsoft.icon': 'ico',
  'video/mp4': 'mp4',
  'video/quicktime': 'mov',
  'video/x-m4v': 'm4v',
  'video/webm': 'webm',
  'video/x-matroska': 'mkv',
  'video/x-msvideo': 'avi',
  'video/3gpp': '3gp',
  'video/ogg': 'ogv',
  'audio/mpeg': 'mp3',
  'audio/wav': 'wav',
  'audio/ogg': 'ogg',
  'audio/mp4': 'm4a',
  'application/pdf': 'pdf'
};

const GALLERY_IMAGE_EXTS: Set<string> = new Set([
  'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'heic', 'heif'
]);

const GALLERY_VIDEO_EXTS: Set<string> = new Set([
  'mp4', 'mov', 'm4v', 'mkv', 'webm', '3gp'
]);

const VIDEO_EXTS: Set<string> = new Set([
  'mp4', 'mov', 'm4v', 'mkv', 'webm', 'avi', '3gp', 'ogv', 'mpeg', 'mpg', 'ts'
]);

const IMAGE_EXTS: Set<string> = new Set([
  'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'heic', 'heif', 'avif', 'svg', 'ico'
]);

const AUDIO_EXTS: Set<string> = new Set([
  'mp3', 'wav', 'ogg', 'oga', 'flac', 'aac', 'm4a', 'opus', 'aiff', 'weba'
]);

function safeDecodePart(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch (_) {
    return value;
  }
}

function stripQueryHash(value: string): string {
  const hash = value.indexOf('#');
  const noHash = hash >= 0 ? value.slice(0, hash) : value;
  const query = noHash.indexOf('?');
  return query >= 0 ? noHash.slice(0, query) : noHash;
}

function normalizedMime(mimeType: string): string {
  const raw = (mimeType || '').trim().toLowerCase();
  const semi = raw.indexOf(';');
  return (semi >= 0 ? raw.slice(0, semi) : raw).trim();
}

function extractRawExtension(pathOrUrl: string): string {
  const trimmed = (pathOrUrl || '').trim();
  if (!trimmed || /^data:/i.test(trimmed) || trimmed.startsWith('t3-attachment://')) return '';
  const clean = safeDecodePart(stripQueryHash(trimmed));
  const slash = Math.max(clean.lastIndexOf('/'), clean.lastIndexOf('\\'));
  const base = slash >= 0 ? clean.slice(slash + 1) : clean;
  const dot = base.lastIndexOf('.');
  if (dot <= 0 || dot >= base.length - 1) return '';
  const ext = base.slice(dot + 1).toLowerCase();
  return /^[a-z0-9]{1,8}$/.test(ext) ? ext : '';
}

function extractBaseName(pathOrUrl: string): string {
  const trimmed = (pathOrUrl || '').trim();
  if (!trimmed || /^data:/i.test(trimmed) || trimmed.startsWith('t3-attachment://')) return '';
  let clean = safeDecodePart(stripQueryHash(trimmed));
  // Strip URL scheme + authority so we don't treat hostnames like "example.com" as filenames.
  if (/^[a-z][a-z0-9+.-]*:\/\//i.test(clean)) {
    const schemeEnd = clean.indexOf('://');
    const pathStart = clean.indexOf('/', schemeEnd + 3);
    if (pathStart < 0) return '';
    clean = clean.slice(pathStart + 1);
  }
  const normalized = clean.replace(/\\/g, '/').replace(/\/+$/, '');
  if (!normalized) return '';
  const slash = normalized.lastIndexOf('/');
  return slash >= 0 ? normalized.slice(slash + 1) : normalized;
}

/** Parses a `data:image/...;base64,...` or `data:video/...;base64,...` URI. */
export function parseBase64DataUri(uri: string): ParsedDataUri | undefined {
  const trimmed = (uri || '').trim();
  const match = /^data:((image|video)\/[a-z0-9.+-]+)(?:;[a-z0-9.+=-]+)*;base64,([a-z0-9+/=\s]+)$/i.exec(trimmed);
  if (!match) return undefined;
  const mimeType = match[1].toLowerCase();
  const kind = match[2].toLowerCase();
  const base64 = match[3].replace(/\s+/g, '');
  if (!base64) return undefined;
  const extension = MIME_TO_EXT[mimeType] || (kind === 'video' ? 'mp4' : 'png');
  return { mimeType, base64, extension, kind };
}

/** Sanitizes a filename so it is safe for HarmonyOS DocumentViewPicker, ShareCache and systemShare. */
export function sanitizeMediaFileName(name: string, fallback: string = 'media'): string {
  const cleaned = (name || '')
    .replace(/[\\/:*?"<>|\x00-\x1f]/g, '_')
    .replace(/\s+/g, ' ')
    .trim()
    .replace(/^\.+/, '')
    .trim();
  if (!cleaned) return fallback;
  if (cleaned.length <= 160) return cleaned;
  const dot = cleaned.lastIndexOf('.');
  if (dot > 0 && cleaned.length - dot <= 10) {
    const ext = cleaned.slice(dot);
    return cleaned.slice(0, 160 - ext.length) + ext;
  }
  return cleaned.slice(0, 160);
}

/** Returns lowercase extension without leading dot. */
export function mediaExtension(fileNameOrPath: string, mimeType: string = '', kind: string = 'image'): string {
  const parsed = parseBase64DataUri(fileNameOrPath);
  if (parsed) return parsed.extension;
  const fromName = extractRawExtension(fileNameOrPath);
  if (fromName) return fromName;
  const mime = normalizedMime(mimeType);
  if (mime && MIME_TO_EXT[mime]) return MIME_TO_EXT[mime];
  return kind === 'video' ? 'mp4' : 'png';
}

/** Extension normalized for HarmonyOS photoAccessHelper (`jpeg` -> `jpg`). */
export function photoGalleryExtension(fileNameOrPath: string, mimeType: string = '', kind: string = 'image'): string {
  const ext = mediaExtension(fileNameOrPath, mimeType, kind);
  return ext === 'jpeg' ? 'jpg' : ext;
}

/** Builds a safe, user-facing filename with a proper extension for saving/sharing/display. */
export function mediaFileName(displayPath: string, alt: string = '', url: string = '',
  mimeType: string = '', kind: string = 'image'): string {
  const parsed = parseBase64DataUri(url) || parseBase64DataUri(displayPath);
  const effectiveKind = kind || (parsed ? parsed.kind : (normalizedMime(mimeType).startsWith('video/') ? 'video' : 'image'));
  const effectiveMime = mimeType || (parsed ? parsed.mimeType : '');

  const fromDisplay = extractBaseName(displayPath);
  const fromUrl = extractBaseName(url);
  const altClean = sanitizeMediaFileName(alt, '');

  let candidate = fromDisplay || fromUrl || altClean || (effectiveKind === 'video' ? 'video' : 'image');
  candidate = sanitizeMediaFileName(candidate, effectiveKind === 'video' ? 'video' : 'image');

  const existingExt = extractRawExtension(candidate);
  if (existingExt) return candidate;

  const fallbackExt = extractRawExtension(displayPath) || extractRawExtension(url) ||
    mediaExtension(displayPath || url, effectiveMime, effectiveKind);
  return sanitizeMediaFileName(candidate + '.' + fallbackExt, (effectiveKind === 'video' ? 'video.' : 'image.') + fallbackExt);
}

/** Builds a strictly sanitized title for HarmonyOS `photoAccessHelper` (no forbidden punctuation). */
export function mediaAssetTitle(fileName: string, kind: string = 'image'): string {
  const trimmed = (fileName || '').trim();
  const dot = trimmed.lastIndexOf('.');
  const stem = dot > 0 ? trimmed.slice(0, dot) : trimmed;
  const safe = stem
    .replace(/[^A-Za-z0-9_\u4e00-\u9fa5-]/g, '_')
    .replace(/_+/g, '_')
    .replace(/^[_-]+|[_-]+$/g, '')
    .slice(0, 64);
  if (safe) return safe;
  return kind === 'video' ? 'T3_video' : 'T3_image';
}

/** Whether the media should be saved as PhotoType.VIDEO rather than PhotoType.IMAGE. */
export function isGalleryVideo(fileName: string, mimeType: string = '', kind: string = ''): boolean {
  const mime = normalizedMime(mimeType);
  if (mime.startsWith('video/')) return true;
  if (mime.startsWith('image/')) return false;
  const ext = extractRawExtension(fileName);
  if (ext) {
    if (VIDEO_EXTS.has(ext)) return true;
    if (IMAGE_EXTS.has(ext)) return false;
  }
  return kind === 'video';
}

/**
 * Whether this file can be saved directly to the system Photo Gallery.
 * Excludes non-gallery formats such as SVG, ICO, PDF, HTML and plain documents.
 */
export function canSaveToPhotoGallery(fileName: string, mimeType: string = '', kind: string = ''): boolean {
  const mime = normalizedMime(mimeType);
  if (mime === 'image/svg+xml' || mime === 'image/x-icon' || mime === 'image/vnd.microsoft.icon') {
    return false;
  }
  const ext = extractRawExtension(fileName);
  if (ext) {
    return GALLERY_IMAGE_EXTS.has(ext) || GALLERY_VIDEO_EXTS.has(ext);
  }
  if (mime) {
    const mapped = MIME_TO_EXT[mime];
    if (mapped) return GALLERY_IMAGE_EXTS.has(mapped) || GALLERY_VIDEO_EXTS.has(mapped);
    return mime.startsWith('image/') || mime.startsWith('video/');
  }
  return kind === 'image' || kind === 'video';
}

/** Pure fallback HarmonyOS Uniform Type Descriptor (UTD) string for `systemShare.SharedData`. */
export function mediaUtdType(fileName: string, mimeType: string = '', kind: string = ''): string {
  const ext = extractRawExtension(fileName) || MIME_TO_EXT[normalizedMime(mimeType)] || '';
  if (ext === 'png') return 'general.png';
  if (ext === 'jpg' || ext === 'jpeg') return 'general.jpeg';
  if (ext === 'gif') return 'general.gif';
  if (ext === 'bmp') return 'com.microsoft.bmp';
  if (ext === 'mp4' || ext === 'm4v') return 'general.mpeg-4';
  if (ext === 'avi') return 'general.avi';
  if (ext === '3gp') return 'general.3gpp';
  if (ext === 'mkv') return 'org.matroska.mkv';
  if (ext === 'mpeg' || ext === 'mpg') return 'general.mpeg';
  if (ext === 'ts') return 'general.ts';
  if (ext === 'pdf') return 'com.adobe.pdf';
  if (ext === 'mp3') return 'general.mpeg-audio';
  if (ext === 'm4a') return 'general.mpeg-4-audio';
  if (ext === 'wav') return 'com.microsoft.waveform-audio';

  const mime = normalizedMime(mimeType);
  if (VIDEO_EXTS.has(ext) || mime.startsWith('video/') || kind === 'video') return 'general.video';
  if (IMAGE_EXTS.has(ext) || mime.startsWith('image/') || kind === 'image') return 'general.image';
  if (AUDIO_EXTS.has(ext) || mime.startsWith('audio/') || kind === 'audio') return 'general.audio';
  return 'general.file';
}

/** Returns the path or remote URL worth copying to clipboard (skips huge data URIs and sandbox paths). */
export function mediaCopyValue(displayPath: string, url: string = ''): string {
  const path = (displayPath || '').trim();
  if (path && !/^data:/i.test(path) && !path.startsWith('t3-attachment://') && !/^file:\/\/[^/]+\/data\/storage\//i.test(path)) {
    return path;
  }
  const remote = (url || '').trim();
  if (/^https?:\/\//i.test(remote)) return remote;
  return '';
}

/** Returns the localized action label for copying a media path or URL. */
export function mediaCopyLabel(displayPath: string, url: string = ''): string {
  const value = mediaCopyValue(displayPath, url);
  if (!value) return '';
  return /^https?:\/\//i.test(value) ? '复制链接' : '复制路径';
}
