import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';

interface CacheOwner { name: string; localId: string; }
interface CacheIndex { version: number; files: CacheOwner[]; }
export interface ShareCacheEntry { name: string; localId: string; bytes: number; createdAt: number; }
export interface ShareCacheResult { removed: number; failed: number; }
const RETAIN_MS: number = 60 * 60 * 1000;

function ownedName(name: string): boolean { return /^share-[0-9]{13,16}-[^/\\\x00-\x1f]+$/.test(name); }
function readIndex(directory: string): CacheIndex {
  let value: Object;
  try {
    const stat = fileIo.lstatSync(directory + '/t3-share-index.json');
    if (!stat.isFile() || stat.isSymbolicLink()) throw new Error('临时文件索引类型无效');
    value = JSON.parse(fileIo.readTextSync(directory + '/t3-share-index.json')) as Object;
  }
  catch (error) {
    if ((error as BusinessError).code === 13900002) return { version: 1, files: [] };
    throw new Error('临时文件索引不可读，未清理文件');
  }
  const root = value as Record<string, Object>;
  if (!root || root.version !== 1 || !Array.isArray(root.files) || root.files.length > 10000) throw new Error('临时文件索引无效');
  const files: CacheOwner[] = [];
  for (const value of root.files as Object[]) {
    const row = value as Record<string, Object>;
    if (!row || typeof row.name !== 'string' || !ownedName(row.name) || typeof row.localId !== 'string' || row.localId.length > 256) throw new Error('临时文件索引无效');
    files.push({ name: row.name, localId: row.localId });
  }
  return { version: 1, files };
}
function writeIndex(directory: string, index: CacheIndex): void {
  const content = JSON.stringify(index);
  const temporary = directory + '/t3-share-index.json.tmp';
  try {
    const stat = fileIo.lstatSync(temporary);
    if (!stat.isFile() || stat.isSymbolicLink()) throw new Error('临时文件索引路径无效');
  } catch (error) { if ((error as BusinessError).code !== 13900002) throw error as Error; }
  const file = fileIo.openSync(temporary, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
  try { fileIo.writeSync(file.fd, content); fileIo.fsyncSync(file.fd); } finally { fileIo.closeSync(file.fd); }
  if (fileIo.readTextSync(temporary) !== content) throw new Error('临时文件索引保存失败');
  fileIo.renameSync(temporary, directory + '/t3-share-index.json');
}
export function registerSharedFile(directory: string, name: string, localId: string): void {
  if (!ownedName(name) || !localId || localId.length > 256) throw new Error('临时文件归属无效');
  const index = readIndex(directory);
  index.files = index.files.filter((entry: CacheOwner) => entry.name !== name && fileIo.accessSync(directory + '/' + entry.name));
  if (index.files.length >= 10000) throw new Error('临时分享文件过多，请先清理');
  index.files.push({ name, localId }); writeIndex(directory, index);
}
export function inspectShareCache(directory: string): ShareCacheEntry[] {
  const index = readIndex(directory);
  const entries: ShareCacheEntry[] = [];
  for (const name of fileIo.listFileSync(directory)) {
    if (!ownedName(name)) continue;
    const stat = fileIo.lstatSync(directory + '/' + name);
    if (!stat.isFile() || stat.isSymbolicLink() || !Number.isSafeInteger(stat.size) || stat.size < 0) continue;
    const owner = index.files.find((entry: CacheOwner) => entry.name === name);
    entries.push({ name, localId: owner?.localId || '', bytes: stat.size, createdAt: Number(name.split('-')[1]) });
  }
  return entries;
}
export function cacheRemovable(entry: ShareCacheEntry, now: number): boolean {
  return Number.isSafeInteger(entry.createdAt) && entry.createdAt > 0 && now - entry.createdAt >= RETAIN_MS;
}
export function clearShareCache(directory: string, localId: string | undefined, now: number): ShareCacheResult {
  const candidates = inspectShareCache(directory).filter((entry: ShareCacheEntry) =>
    (localId === undefined || entry.localId === localId) && cacheRemovable(entry, now));
  const index = readIndex(directory);
  const removed: string[] = []; let failed = 0;
  for (const entry of candidates) {
    try {
      const path = directory + '/' + entry.name;
      const stat = fileIo.lstatSync(path);
      if (!stat.isFile() || stat.isSymbolicLink() || stat.size !== entry.bytes) { failed++; continue; }
      fileIo.unlinkSync(path); removed.push(entry.name);
    } catch (_) { failed++; }
  }
  index.files = index.files.filter((entry: CacheOwner) => !removed.includes(entry.name));
  writeIndex(directory, index);
  return { removed: removed.length, failed };
}
export function cacheSizeLabel(bytes: number): string {
  return bytes < 1024 ? bytes + ' B' : bytes < 1024 * 1024 ? (bytes / 1024).toFixed(1) + ' KB' : (bytes / 1048576).toFixed(1) + ' MB';
}
