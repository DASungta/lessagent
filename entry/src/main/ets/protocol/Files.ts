import { compactArray, objects, record, text } from './Wire';

export interface WorkspaceEntry {
  path: string;
  name: string;
  kind: string;
  ignored: boolean;
  depth: number;
}

export interface WorkspaceFile {
  relativePath: string;
  contents: string;
  byteLength: number;
  truncated: boolean;
  exists: boolean;
}

export interface ContentMatch {
  path: string;
  lineNumber: number;
  lineContent: string;
  ranges: Array<{ start: number; end: number }>;
}

export interface FileLine {
  number: number;
  text: string;
}

export function matchesContentSearchLine(line: string, excerpt: string, query: string): boolean {
  if (line === excerpt) return true;
  // Upstream git grep caps excerpts at 512 UTF-16 units. Ambiguous shorter excerpts are not trusted.
  if (excerpt.length !== 512 || /[\uD800-\uDBFF]$/.test(excerpt) || !line.startsWith(excerpt) || !query) return false;
  const foldAscii = (value: string): string => value.replace(/[A-Z]/g, (letter: string) => letter.toLowerCase());
  return foldAscii(line).includes(foldAscii(query));
}

const MAX_DISPLAY_LINE = 4000;

export function workspaceEntries(value: Object): WorkspaceEntry[] {
  return compactArray(objects(record(value).entries), (entry: Object): WorkspaceEntry => {
    const row = record(entry);
    const path = text(row.path).replace(/\\/g, '/').replace(/^\.\//, '');
    const kind = text(row.kind);
    if (!path || path.length > 2048 || path.startsWith('/') ||
      path.split('/').some((part: string) => part === '..' || part === '.')) {
      throw new Error('工作区条目路径无效');
    }
    if (kind !== 'file' && kind !== 'directory') throw new Error('工作区条目类型无效');
    const parts = path.split('/').filter((part: string) => part);
    return { path, name: parts[parts.length - 1] || path, kind,
      ignored: row.ignored === true, depth: Math.max(0, parts.length - 1) };
  });
}

/** The server may return the whole subtree; a browser pane shows only one level. */
export function directEntries(entries: WorkspaceEntry[], directoryPath: string): WorkspaceEntry[] {
  const prefix = directoryPath ? directoryPath.replace(/\/+$/, '') + '/' : '';
  return entries.filter((entry: WorkspaceEntry) => {
    if (prefix && !entry.path.startsWith(prefix)) return false;
    const rest = prefix ? entry.path.slice(prefix.length) : entry.path;
    return !!rest && rest.indexOf('/') < 0;
  }).map((entry: WorkspaceEntry): WorkspaceEntry => ({
    path: entry.path, name: entry.name, kind: entry.kind, ignored: entry.ignored, depth: 0
  }));
}

export function workspaceFile(value: Object): WorkspaceFile {
  const row = record(value);
  const relativePath = text(row.relativePath).replace(/\\/g, '/');
  const contents = text(row.contents);
  const byteLength = row.byteLength;
  if (!relativePath || typeof byteLength !== 'number' || !Number.isSafeInteger(byteLength) || byteLength < 0) {
    throw new Error('文件读取结果无效');
  }
  return { relativePath, contents, byteLength, truncated: row.truncated === true, exists: row.exists !== false };
}

export function contentMatches(value: Object): ContentMatch[] {
  return compactArray(objects(record(value).matches), (match: Object): ContentMatch => {
    const row = record(match);
    return {
      path: text(row.path), lineNumber: Number(row.lineNumber), lineContent: text(row.lineContent),
      ranges: compactArray(row.matchRanges, (range: Object) => {
        const item = record(range);
        return { start: Number(item.start), end: Number(item.end) };
      })
    };
  }).filter((match: ContentMatch) => match.path && match.lineNumber > 0 && match.lineContent.length <= 100000);
}

export function contentSearchInput(cwd: string, query: string, regex: boolean = false): Object {
  const value = query.slice(0, 256);
  if (!cwd.trim() || !value) throw new Error('请输入搜索内容');
  return { cwd, query: value, limit: 100, caseSensitive: false, wholeWord: false, useRegex: regex };
}

export function readFileInput(cwd: string, relativePath: string): Object {
  if (!cwd.trim() || !relativePath.trim()) throw new Error('文件路径无效');
  return { cwd, relativePath };
}

export function listEntriesInput(cwd: string, directoryPath: string): Object {
  if (!cwd.trim()) throw new Error('缺少工作目录');
  return directoryPath ? { cwd, directoryPath } : { cwd };
}

const MIME: Record<string, string> = {
  png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', gif: 'image/gif', webp: 'image/webp',
  svg: 'image/svg+xml', bmp: 'image/bmp', ico: 'image/x-icon',
  mp4: 'video/mp4', webm: 'video/webm', mov: 'video/quicktime', m4v: 'video/x-m4v',
  mp3: 'audio/mpeg', wav: 'audio/wav', m4a: 'audio/mp4', ogg: 'audio/ogg',
  pdf: 'application/pdf', zip: 'application/zip', gz: 'application/gzip',
  md: 'text/markdown', markdown: 'text/markdown', json: 'application/json', jsonc: 'application/json',
  ts: 'text/typescript', tsx: 'text/typescript', js: 'text/javascript', jsx: 'text/javascript',
  css: 'text/css', html: 'text/html', xml: 'text/xml', yaml: 'text/yaml', yml: 'text/yaml',
  toml: 'text/toml', sh: 'text/x-sh', py: 'text/x-python', go: 'text/x-go', rs: 'text/x-rust',
  java: 'text/x-java', kt: 'text/x-kotlin', swift: 'text/x-swift', c: 'text/x-c', h: 'text/x-c',
  cpp: 'text/x-c++', hpp: 'text/x-c++', sql: 'text/x-sql', ets: 'text/typescript'
};

export function mimeType(path: string): string {
  const name = path.split('/').pop() || path;
  const dot = name.lastIndexOf('.');
  const extension = dot >= 0 ? name.slice(dot + 1).toLowerCase() : '';
  return MIME[extension] || 'application/octet-stream';
}

export function isImage(path: string): boolean { return mimeType(path).startsWith('image/'); }
export function isVideo(path: string): boolean { return mimeType(path).startsWith('video/'); }
export function isAudio(path: string): boolean { return mimeType(path).startsWith('audio/'); }
export function isPdf(path: string): boolean { return mimeType(path) === 'application/pdf'; }
export function isMarkdown(path: string): boolean { return mimeType(path) === 'text/markdown'; }
export function isBinary(path: string): boolean {
  const mime = mimeType(path);
  return !(mime.startsWith('text/') || mime === 'application/json' || mime === 'application/xml' ||
    mime === 'application/javascript');
}

export function fileLines(contents: string, limit: number = 100000): FileLine[] {
  const lines = contents.replace(/\r\n?/g, '\n').split('\n');
  const count = Math.min(lines.length, Math.max(0, limit));
  const result: FileLine[] = [];
  for (let index = 0; index < count; index += 1) {
    result.push({ number: index + 1, text: lines[index].replace(/\t/g, '    ').slice(0, MAX_DISPLAY_LINE) });
  }
  return result;
}

export function relativePath(cwd: string, absolutePath: string): string {
  const root = cwd.replace(/\/+$/, '');
  if (!absolutePath.startsWith(root + '/')) throw new Error('文件不在当前工作区');
  return absolutePath.slice(root.length + 1);
}

export function joinPath(cwd: string, path: string): string {
  const clean = path.replace(/^\/+/, '');
  return cwd.replace(/\/+$/, '') + '/' + clean;
}

export function workspaceAssetResource(threadId: string, cwd: string, path: string, download: boolean = false): Object {
  const relative = path.replace(/\\/g, '/');
  if (!cwd.trim() || !relative.trim() || relative.startsWith('/') || /^[a-z]+:/i.test(relative) ||
    /[\x00-\x1f]/.test(relative) || relative.split('/').some((part: string) => part === '..' || part === '.')) throw new Error('工作区路径无效');
  const absolute = joinPath(cwd, relative);
  if (absolute.length > 1024) throw new Error('文件路径过长');
  if (threadId.trim()) {
    if (download) return { _tag: 'media-file', threadId, path: absolute, disposition: 'attachment', hostOnly: true };
    if (isVideo(relative) || isAudio(relative)) return { _tag: 'media-file', threadId, path: absolute, hostOnly: true };
    return { _tag: 'workspace-file', threadId, path: absolute };
  }
  return { _tag: 'draft-workspace-file', cwd, path: relative };
}

export function pathAncestors(path: string): string[] {
  const parts = path.split('/').filter((part: string) => part);
  const result: string[] = [];
  for (let index = 1; index < parts.length; index += 1) result.push(parts.slice(0, index).join('/'));
  return result;
}

export function fileIcon(kind: string, path: string): string {
  if (kind === 'directory') return '▸';
  if (isImage(path)) return '▣';
  if (isVideo(path) || isAudio(path)) return '▶';
  if (isMarkdown(path)) return '¶';
  return '·';
}
