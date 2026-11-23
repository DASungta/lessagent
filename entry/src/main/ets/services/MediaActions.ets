import { common } from '@kit.AbilityKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { systemShare } from '@kit.ShareKit';
import {
  isGalleryVideo,
  mediaAssetTitle,
  mediaExtension,
  mediaUtdType,
  parseBase64DataUri,
  photoGalleryExtension,
  sanitizeMediaFileName
} from '../protocol/MediaTransfer';
import { registerSharedFile } from './ShareCache';

export type MediaSaveOutcome = 'saved' | 'cancelled';

const MAX_LOCAL_MEDIA_BYTES: number = 100 * 1024 * 1024;

function writeBufferSync(fd: number, bytes: ArrayBuffer): void {
  const total = bytes.byteLength;
  let offset = 0;
  while (offset < total) {
    const slice = offset === 0 ? bytes : bytes.slice(offset);
    const written = fileIo.writeSync(fd, slice);
    if (written <= 0) throw new Error('写入文件失败');
    offset += written;
  }
  fileIo.fsyncSync(fd);
}

/** Decodes a `data:image/...;base64,...` or `data:video/...;base64,...` URI into raw bytes. */
export function decodeDataUriBytes(uri: string): ArrayBuffer | undefined {
  const parsed = parseBase64DataUri(uri);
  if (!parsed) return undefined;
  const helper = new util.Base64Helper();
  const decoded: Uint8Array = helper.decodeSync(parsed.base64);
  if (!decoded || decoded.byteLength === 0) throw new Error('媒体数据为空');
  return decoded.buffer.slice(decoded.byteOffset, decoded.byteOffset + decoded.byteLength);
}

/** Reads bytes from a local sandbox file path or `file://` URI. */
export function readLocalFileUriBytes(uriOrPath: string, maxBytes: number = MAX_LOCAL_MEDIA_BYTES): ArrayBuffer {
  const filePath = uriOrPath.startsWith('file://') ? new fileUri.FileUri(uriOrPath).path : uriOrPath;
  if (!filePath) throw new Error('本地媒体路径无效');
  const stat = fileIo.statSync(filePath);
  if (!stat || stat.size <= 0) throw new Error('本地媒体文件为空');
  if (stat.size > maxBytes) throw new Error('媒体文件大小超出限制');
  const out = new Uint8Array(stat.size);
  const file = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
  try {
    let offset = 0;
    while (offset < stat.size) {
      const remaining = stat.size - offset;
      const chunk = new ArrayBuffer(Math.min(remaining, 1024 * 1024));
      const read = fileIo.readSync(file.fd, chunk);
      if (read <= 0) break;
      out.set(new Uint8Array(chunk, 0, read), offset);
      offset += read;
    }
    if (offset <= 0) throw new Error('读取本地媒体失败');
    return offset === stat.size ? out.buffer : out.buffer.slice(0, offset);
  } finally {
    fileIo.closeSync(file);
  }
}

/** Resolves the best HarmonyOS UTD string for sharing a file/image/video. */
export function resolveShareUtd(fileName: string, mimeType: string = '', kind: string = ''): string {
  const fallback = mediaUtdType(fileName, mimeType, kind);
  const ext = mediaExtension(fileName, mimeType, kind);
  if (ext) {
    try {
      const byExt = uniformTypeDescriptor.getUniformDataTypeByFilenameExtension('.' + ext);
      if (byExt && typeof byExt === 'string') return byExt;
    } catch (_) {}
  }
  const cleanMime = (mimeType || '').split(';')[0].trim().toLowerCase();
  if (cleanMime) {
    try {
      const byMime = uniformTypeDescriptor.getUniformDataTypeByMIMEType(cleanMime);
      if (byMime && typeof byMime === 'string') return byMime;
    } catch (_) {}
  }
  return fallback;
}

/** Saves bytes to a user-selected document location via HarmonyOS DocumentViewPicker. */
export async function saveBytesToDocumentPicker(bytes: ArrayBuffer, fileName: string): Promise<MediaSaveOutcome> {
  const options = new picker.DocumentSaveOptions();
  options.newFileNames = [sanitizeMediaFileName(fileName, 'media')];
  const targets = await new picker.DocumentViewPicker().save(options);
  if (!targets || targets.length === 0) return 'cancelled';
  const handle = fileIo.openSync(targets[0], fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
  try {
    writeBufferSync(handle.fd, bytes);
  } finally {
    fileIo.closeSync(handle);
  }
  return 'saved';
}

/** Writes bytes to a managed share cache file and opens the HarmonyOS system Share Sheet. */
export async function shareBytesWithSystemSheet(
  context: common.UIAbilityContext,
  bytes: ArrayBuffer,
  fileName: string,
  localScopeId: string,
  mimeType: string = '',
  kind: string = ''
): Promise<void> {
  const safeName = sanitizeMediaFileName(fileName, kind === 'video' ? 'video.mp4' : 'image.png');
  const cacheName = 'share-' + Date.now() + '-' + safeName;
  const path = context.cacheDir + '/' + cacheName;
  const handle = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
  try {
    writeBufferSync(handle.fd, bytes);
  } finally {
    fileIo.closeSync(handle);
  }
  registerSharedFile(context.cacheDir, cacheName, localScopeId || 'media');
  const utd = resolveShareUtd(safeName, mimeType, kind);
  const shared = new systemShare.SharedData({
    utd,
    uri: fileUri.getUriFromPath(path),
    title: safeName
  });
  await new systemShare.ShareController(shared).show(context, {});
}

function isPermissionDeniedError(error: Object): boolean {
  const code = (error as BusinessError).code;
  return code === 201 || code === 13900012;
}

function isInvalidArgumentError(error: Object): boolean {
  const code = (error as BusinessError).code;
  return code === 401 || code === 13900020 || code === 23800151;
}

/**
 * Saves an image or video directly to HarmonyOS Photos / Gallery without declaring
 * restricted `ohos.permission.WRITE_IMAGEVIDEO` in `module.json5`:
 * - When called from a Security Component `SaveButton` (`viaSaveButton === true`), uses
 *   `photoAccessHelper.createAsset` directly (one tap, zero popup).
 * - When called from a regular menu (`viaSaveButton === false`) or if the 10-second
 *   SaveButton temporary grant expired during a slow download, falls back cleanly to
 *   `photoAccessHelper.showAssetsCreationDialog`.
 */
export async function saveBytesToPhotoGallery(
  context: common.UIAbilityContext,
  bytes: ArrayBuffer,
  fileName: string,
  mimeType: string = '',
  kind: string = '',
  viaSaveButton: boolean = false
): Promise<MediaSaveOutcome> {
  const video = isGalleryVideo(fileName, mimeType, kind);
  const photoType = video ? photoAccessHelper.PhotoType.VIDEO : photoAccessHelper.PhotoType.IMAGE;
  const ext = photoGalleryExtension(fileName, mimeType, video ? 'video' : 'image');
  const title = mediaAssetTitle(fileName, video ? 'video' : 'image');
  const helper = photoAccessHelper.getPhotoAccessHelper(context);

  if (viaSaveButton) {
    try {
      let assetUri = '';
      try {
        const createOptions: photoAccessHelper.CreateOptions = { title };
        assetUri = await helper.createAsset(photoType, ext, createOptions);
      } catch (innerError) {
        if (isInvalidArgumentError(innerError as Object)) {
          assetUri = await helper.createAsset(photoType, ext);
        } else {
          throw innerError as Error;
        }
      }
      if (!assetUri) throw new Error('相册创建媒体资源失败');
      const handle = fileIo.openSync(assetUri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      try {
        writeBufferSync(handle.fd, bytes);
      } finally {
        fileIo.closeSync(handle);
      }
      return 'saved';
    } catch (error) {
      if (!isPermissionDeniedError(error as Object)) {
        throw error as Error;
      }
      // 10-second temporary SaveButton authorization likely expired during a slow download;
      // fall through to showAssetsCreationDialog so the user can still complete the save.
    }
  }

  const stagePath = context.cacheDir + '/t3-gallery-stage-' + Date.now() + '-' + Math.floor(Math.random() * 10000) + '.' + ext;
  const stageFile = fileIo.openSync(stagePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
  try {
    writeBufferSync(stageFile.fd, bytes);
  } finally {
    fileIo.closeSync(stageFile);
  }

  try {
    const srcUri = fileUri.getUriFromPath(stagePath);
    const config: photoAccessHelper.PhotoCreationConfig = {
      title,
      fileNameExtension: ext,
      photoType,
      subtype: photoAccessHelper.PhotoSubtype.DEFAULT
    };
    const destUris = await helper.showAssetsCreationDialog([srcUri], [config]);
    if (!destUris || destUris.length === 0 || !destUris[0]) {
      return 'cancelled';
    }
    const handle = fileIo.openSync(destUris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
    try {
      writeBufferSync(handle.fd, bytes);
    } finally {
      fileIo.closeSync(handle);
    }
    return 'saved';
  } finally {
    try { fileIo.unlinkSync(stagePath); } catch (_) {}
  }
}
