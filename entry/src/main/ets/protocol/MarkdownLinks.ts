export interface ThreadLinkTarget {
  environmentId: string;
  threadId: string;
  decodedThreadId: string;
}

export interface FileLinkTarget {
  path: string;
  line: number;
  column: number;
  isAbsolute: boolean;
  isHomeRelative: boolean;
  isDirectoryHint: boolean;
}

export interface ClassifiedMarkdownLink {
  kind: 'external' | 'mailto' | 'thread' | 'file' | 'blocked';
  href: string;
  thread?: ThreadLinkTarget;
  file?: FileLinkTarget;
}

export interface ResolvedFileLink {
  path: string;
  absolutePath: string;
  line: number;
  column: number;
  isOutsideWorkspace: boolean;
  isDirectoryHint: boolean;
}

const V1_PREFIX = 't3-thread://v1/';
const V2_PREFIX = 't3-thread://v2/';
const HOSTED_PREFIX = 'https://app.t3.codes/threads/';
const HOSTED_PATH = /^([A-Za-z0-9_%-]+)\/([A-Za-z0-9_%-]+)$/;
const POSIX_FILE_ROOTS: string[] = [
  '/Users/', '/home/', '/tmp/', '/var/', '/etc/', '/opt/', '/mnt/', '/Volumes/',
  '/private/', '/root/', '/usr/', '/bin/', '/sbin/', '/lib/', '/lib64/', '/srv/',
  '/workspace/', '/workspaces/'
];
const EXTENSIONLESS_NAMES: string[] = [
  'Makefile', 'makefile', 'GNUmakefile', 'Dockerfile', 'Containerfile', 'Justfile', 'justfile',
  'Rakefile', 'Gemfile', 'Procfile', 'Brewfile', 'Caddyfile', 'Vagrantfile', 'Jenkinsfile',
  'Podfile', 'Fastfile', 'BUILD', 'WORKSPACE', 'LICENSE', 'LICENCE', 'COPYING', 'NOTICE',
  'AUTHORS', 'CONTRIBUTORS', 'CHANGELOG', 'README', 'CODEOWNERS'
];

function safeDecode(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch (_) {
    return value;
  }
}

function normalizeDestination(raw: string): string {
  const trimmed = (raw || '').trim();
  return trimmed.startsWith('<') && trimmed.endsWith('>') ? trimmed.slice(1, -1).trim() : trimmed;
}

function isWindowsDrivePath(value: string): boolean {
  return /^[A-Za-z]:[\\/]/.test(value);
}

function stripLeadingWindowsSlash(value: string): string {
  return /^\/[A-Za-z]:[\\/]/.test(value) ? value.slice(1) : value;
}

function isNetworkPath(value: string): boolean {
  return value.startsWith('//') || value.startsWith('\\\\');
}

export function parseThreadLinkHref(rawHref: string): ThreadLinkTarget | undefined {
  const href = normalizeDestination(rawHref);
  if (!href || /[\x00-\x1f\s]/.test(href)) return undefined;
  if (href.startsWith(HOSTED_PREFIX)) {
    const match = HOSTED_PATH.exec(href.slice(HOSTED_PREFIX.length));
    if (!match) return undefined;
    const environmentId = safeDecode(match[1]).trim();
    const threadId = safeDecode(match[2]).trim();
    if (!environmentId || !threadId || environmentId.length > 256 || threadId.length > 512) return undefined;
    return { environmentId, threadId, decodedThreadId: threadId };
  }
  if (href.startsWith(V1_PREFIX)) {
    const threadId = href.slice(V1_PREFIX.length).trim();
    if (!threadId || threadId.length > 512) return undefined;
    const decoded = safeDecode(threadId).trim();
    return { environmentId: '', threadId, decodedThreadId: decoded || threadId };
  }
  if (href.startsWith(V2_PREFIX)) {
    const rest = href.slice(V2_PREFIX.length);
    const slash = rest.indexOf('/');
    if (slash <= 0 || slash === rest.length - 1) return undefined;
    const environmentId = rest.slice(0, slash).trim();
    const threadId = rest.slice(slash + 1).trim();
    if (!environmentId || !threadId || environmentId.length > 256 || threadId.length > 512) return undefined;
    const decoded = safeDecode(threadId).trim();
    return { environmentId, threadId, decodedThreadId: decoded || threadId };
  }
  return undefined;
}

function parseFileUrlPath(href: string): { path: string; hash: string } | undefined {
  const match = /^file:\/\/([^/?#]*)(\/[^?#]*)(?:\?[^#]*)?(#.*)?$/i.exec(href);
  if (!match) return undefined;
  const authority = match[1].toLowerCase();
  if (authority && authority !== 'localhost') return undefined;
  return {
    path: stripLeadingWindowsSlash(safeDecode(match[2])),
    hash: safeDecode(match[3] || '')
  };
}

function splitPathPosition(rawPath: string, hash: string): { path: string; line: number; column: number } {
  let path = rawPath;
  let line = 0;
  let column = 0;
  const lineColMatch = /^(.*?):(\d+):(\d+)$/.exec(path);
  if (lineColMatch && lineColMatch[1]) {
    path = lineColMatch[1];
    line = Number.parseInt(lineColMatch[2], 10);
    column = Number.parseInt(lineColMatch[3], 10);
  } else {
    const lineRangeMatch = /^(.*?):(\d+)(?:-\d+)?$/.exec(path);
    if (lineRangeMatch && lineRangeMatch[1]) {
      path = lineRangeMatch[1];
      line = Number.parseInt(lineRangeMatch[2], 10);
    }
  }
  if (line <= 0 && hash) {
    const hashMatch = /^#L(\d+)(?:C(\d+))?(?:-L?\d+)?$/i.exec(hash);
    if (hashMatch) {
      line = Number.parseInt(hashMatch[1], 10);
      if (hashMatch[2]) column = Number.parseInt(hashMatch[2], 10);
    }
  }
  return {
    path,
    line: Number.isSafeInteger(line) && line > 0 ? line : 0,
    column: Number.isSafeInteger(column) && column > 0 ? column : 0
  };
}

function hasDisallowedScheme(value: string): boolean {
  if (isWindowsDrivePath(value)) return false;
  const match = /^([A-Za-z][A-Za-z0-9+.-]*):(.*)$/.exec(value);
  if (!match) return false;
  const rest = match[2] || '';
  if (rest.startsWith('//')) return true;
  return !/^\d+(?::\d+|-\d+)?$/.test(rest);
}

function looksLikeFilePath(path: string, hasLine: boolean): boolean {
  if (!path || path.length > 1024 || /[\x00-\x1f]/.test(path)) return false;
  if (isNetworkPath(path)) return false;
  if (/(?:^|[\\/])(?:\.{3,}|…)(?:[\\/]|$)/.test(path)) return false;
  if (path.startsWith('~/') || path.startsWith('~\\') || isWindowsDrivePath(path)) return true;
  if (path.startsWith('./') || path.startsWith('../')) return true;
  if (path.startsWith('/')) {
    if (POSIX_FILE_ROOTS.some((prefix: string) => path.startsWith(prefix))) return true;
    if (hasLine || path.endsWith('/')) return true;
    const base = path.slice(path.lastIndexOf('/') + 1);
    return EXTENSIONLESS_NAMES.includes(base) || /\.[A-Za-z0-9_-]+$/.test(base);
  }
  const clean = path.replace(/\\/g, '/');
  if (EXTENSIONLESS_NAMES.includes(clean)) return true;
  if (clean.includes('/')) return true;
  // Bare relative filename like `README.md` or `t3code-android-upstream-eval.html` (avoid emails).
  if (clean.includes('@')) return false;
  return /^[^/\\:*?"<>|]+\.[A-Za-z0-9_-]+$/.test(clean);
}

export function parseMarkdownFileLink(rawHref: string): FileLinkTarget | undefined {
  const href = normalizeDestination(rawHref);
  if (!href || href.startsWith('#') || href.startsWith('?') || isNetworkPath(href) || /[\x00-\x1f]/.test(href)) {
    return undefined;
  }
  let rawPath = '';
  let hash = '';
  if (/^file:/i.test(href)) {
    const parsed = parseFileUrlPath(href);
    if (!parsed) return undefined;
    rawPath = parsed.path;
    hash = parsed.hash;
  } else {
    // Split literal URL `#` and `?` BEFORE percent-decoding so encoded filename characters
    // (`%23` '#', `%3F` '?', `%26` '&', `%27` "'", `%2C` ',', `%25` '%', `%21` '!', `%7E` '~')
    // survive intact.
    const hashIdx = href.indexOf('#');
    const withoutHash = hashIdx >= 0 ? href.slice(0, hashIdx) : href;
    hash = hashIdx >= 0 ? safeDecode(href.slice(hashIdx)) : '';
    const queryIdx = withoutHash.indexOf('?');
    const withoutQuery = queryIdx >= 0 ? withoutHash.slice(0, queryIdx) : withoutHash;
    rawPath = stripLeadingWindowsSlash(safeDecode(withoutQuery.trim()));
  }
  if (!rawPath || hasDisallowedScheme(rawPath)) return undefined;
  const split = splitPathPosition(rawPath, hash);
  if (!looksLikeFilePath(split.path, split.line > 0)) return undefined;
  const isDirectoryHint = /[\\/]$/.test(split.path);
  const trimmedPath = isDirectoryHint && split.path.length > 1
    ? split.path.replace(/[\\/]+$/, '')
    : split.path;
  const isHomeRelative = trimmedPath.startsWith('~/') || trimmedPath.startsWith('~\\');
  const isAbsolute = trimmedPath.startsWith('/') || isWindowsDrivePath(trimmedPath);
  return {
    path: trimmedPath,
    line: split.line,
    column: split.column,
    isAbsolute,
    isHomeRelative,
    isDirectoryHint
  };
}

export function classifyMarkdownLink(rawHref: string): ClassifiedMarkdownLink {
  const href = normalizeDestination(rawHref);
  if (!href || href.startsWith('#') || /[\x00-\x1f]/.test(href)) {
    return { kind: 'blocked', href };
  }
  const thread = parseThreadLinkHref(href);
  if (thread) {
    return { kind: 'thread', href, thread };
  }
  if (/^https?:\/\//i.test(href)) {
    return { kind: 'external', href };
  }
  if (/^(?:mailto|tel):/i.test(href)) {
    return { kind: 'mailto', href };
  }
  const file = parseMarkdownFileLink(href);
  if (file) {
    return { kind: 'file', href, file };
  }
  return { kind: 'blocked', href };
}

function normalizeRelativeSegments(value: string): string {
  const stack: string[] = [];
  for (const segment of value.replace(/\\/g, '/').split('/')) {
    if (!segment || segment === '.') continue;
    if (segment === '..') {
      if (stack.length === 0) return '';
      stack.pop();
    } else {
      stack.push(segment);
    }
  }
  return stack.join('/');
}

export function resolveFileLinkForWorkspace(cwd: string, target: FileLinkTarget): ResolvedFileLink | undefined {
  const root = (cwd || '').trim().replace(/[\\/]+$/, '');
  if (target.isHomeRelative) {
    return {
      path: target.path,
      absolutePath: target.path,
      line: target.line,
      column: target.column,
      isOutsideWorkspace: true,
      isDirectoryHint: target.isDirectoryHint
    };
  }
  if (target.isAbsolute) {
    const normalizedTarget = target.path.replace(/\\/g, '/');
    const normalizedRoot = root.replace(/\\/g, '/');
    if (normalizedRoot && normalizedTarget === normalizedRoot) {
      return {
        path: '',
        absolutePath: target.path,
        line: target.line,
        column: target.column,
        isOutsideWorkspace: false,
        isDirectoryHint: true
      };
    }
    if (normalizedRoot && normalizedTarget.startsWith(normalizedRoot + '/')) {
      const rel = normalizeRelativeSegments(normalizedTarget.slice(normalizedRoot.length + 1));
      if (rel) {
        return {
          path: rel,
          absolutePath: target.path,
          line: target.line,
          column: target.column,
          isOutsideWorkspace: false,
          isDirectoryHint: target.isDirectoryHint
        };
      }
    }
    return {
      path: target.path,
      absolutePath: target.path,
      line: target.line,
      column: target.column,
      isOutsideWorkspace: true,
      isDirectoryHint: target.isDirectoryHint
    };
  }
  const rel = normalizeRelativeSegments(target.path);
  if (!rel || !root) return undefined;
  const sep = isWindowsDrivePath(root) ? '\\' : '/';
  return {
    path: rel,
    absolutePath: root + sep + rel.replace(/\//g, sep),
    line: target.line,
    column: target.column,
    isOutsideWorkspace: false,
    isDirectoryHint: target.isDirectoryHint
  };
}

export interface ProjectFileCandidate {
  path: string;
  kind: string;
}

export interface ProjectSearchRoot {
  root: string;
  entries: ProjectFileCandidate[];
}

function basenameOf(path: string): string {
  const normalized = path.replace(/\\/g, '/');
  const idx = normalized.lastIndexOf('/');
  return idx >= 0 ? normalized.slice(idx + 1) : normalized;
}

function joinRootPath(root: string, rel: string): string {
  const cleanRoot = root.replace(/[\\/]+$/, '');
  const cleanRel = rel.replace(/^[\\/]+/, '');
  const sep = isWindowsDrivePath(cleanRoot) ? '\\' : '/';
  return cleanRoot + sep + cleanRel.replace(/\//g, sep);
}

/**
 * Resolves a bare basename across candidate project roots, returning `undefined` when
 * multiple distinct files (including case-insensitive collisions across roots) make it ambiguous.
 */
export function pickProjectLinkMatch(relativePath: string, searches: ProjectSearchRoot[]): string | undefined {
  const target = (relativePath || '').trim();
  if (!target) return undefined;
  const isBasename = !target.includes('/') && !target.includes('\\');
  const folded = target.toLowerCase();
  const matches: Map<string, string> = new Map();
  let rootHits = 0;

  const addMatch = (resolved: string): void => {
    const key = resolved.replace(/\\/g, '/').toLowerCase();
    if (!matches.has(key)) matches.set(key, resolved);
  };

  for (const search of searches) {
    if (isBasename) {
      let hasAnyFolded = false;
      const exact: string[] = [];
      const ci: string[] = [];
      for (const entry of search.entries) {
        if (entry.kind !== 'file') continue;
        const base = basenameOf(entry.path);
        if (base.toLowerCase() !== folded) continue;
        hasAnyFolded = true;
        if (base === target) exact.push(entry.path);
        ci.push(entry.path);
      }
      if (!hasAnyFolded) continue;
      rootHits += 1;
      if (exact.length === 1) {
        addMatch(joinRootPath(search.root, exact[0]));
      } else if (exact.length === 0 && ci.length === 1) {
        addMatch(joinRootPath(search.root, ci[0]));
      } else {
        for (const p of ci) addMatch(joinRootPath(search.root, p));
      }
    } else {
      const normalizedTarget = target.replace(/\\/g, '/').replace(/^\.\//, '');
      for (const entry of search.entries) {
        if (entry.kind !== 'file') continue;
        const normalizedEntry = entry.path.replace(/\\/g, '/').replace(/^\.\//, '');
        if (normalizedEntry === normalizedTarget || normalizedEntry.toLowerCase() === normalizedTarget.toLowerCase()) {
          addMatch(joinRootPath(search.root, entry.path));
        }
      }
    }
  }

  if (isBasename && rootHits > 1) {
    for (const search of searches) {
      for (const entry of search.entries) {
        if (entry.kind === 'file' && basenameOf(entry.path).toLowerCase() === folded) {
          addMatch(joinRootPath(search.root, entry.path));
        }
      }
    }
  }

  if (matches.size !== 1) return undefined;
  const first = matches.values().next();
  return first.done ? undefined : first.value;
}
