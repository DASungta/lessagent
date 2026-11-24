export const MOBILE_FULL_FILE_MAX_BYTES = 8 * 1024 * 1024;
export const LARGE_MARKDOWN_CHUNK_MAX_CHARS = 128 * 1024;
const CHUNK_TARGET_CHARS = 4 * 1024;
const FRONTMATTER_MAX_LINES = 1000;
const SHARED_DEFINITIONS_MAX_CHARS = 16 * 1024;
const MAX_DELIMITED_ROWS = 400;
const MAX_DELIMITED_COLS = 64;
const MAX_ZIP_ENTRIES = 5000;

export interface MarkdownChunk {
  text: string;
  lines: number;
}

export interface SplitMarkdown {
  chunks: MarkdownChunk[];
  definitions: string;
}

const FENCE_OPEN = /^ {0,3}(`{3,}(?![^`\n]*`)|~{3,})/;
const ATX_HEADING = /^#{1,6}(?:[ \t]|\r?$)/;
const THEMATIC_BREAK = /^ {0,3}(?:(?:-[ \t]*){3,}|(?:\*[ \t]*){3,}|(?:_[ \t]*){3,})\r?$/;
const BLOCK_START = /^[\p{L}\p{N}`[!|>]/u;
const ORDERED_ITEM = /^\d{1,9}[.)](?:[ \t]|\r?$)/;
const FRONTMATTER_OPEN = /^\uFEFF?---[ \t]*\r?$/;
const FRONTMATTER_CLOSE = /^(?:---|\.\.\.)[ \t]*\r?$/;
const HTML_BLOCK_START = /^ {0,3}<\/?[A-Za-z][A-Za-z0-9-]*(?=[\s/>]|$)/;
const LINK_DEFINITION =
  /^ {0,3}\[(?!\^)(?:[^\]\\]|\\.)+\]:[ \t]*(?:<[^<>\n]*>|[^\s<]\S*)(?:[ \t]+(?:"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|\((?:[^()\\]|\\.)*\)))?[ \t]*\r?$/;

interface SpanningPattern {
  open: RegExp;
  close: RegExp;
}

const SPANNING_BLOCKS: SpanningPattern[] = [
  { open: /^ {0,3}<(?:script|pre|style|textarea)(?=[\s>]|$)/i, close: /<\/(?:script|pre|style|textarea)>/i },
  { open: /^ {0,3}<!--/, close: /-->/ },
  { open: /^ {0,3}<\?/, close: /\?>/ },
  { open: /^ {0,3}<!\[CDATA\[/, close: /\]\]>/ },
  { open: /^ {0,3}<![A-Za-z]/, close: />/ },
  { open: /^ {0,3}\$\$/, close: /\$\$/ }
];

function blockCloser(line: string): ((next: string) => boolean) | undefined {
  const fenceMatch = FENCE_OPEN.exec(line);
  if (fenceMatch && fenceMatch[1]) {
    const fence = fenceMatch[1];
    return (next: string): boolean => {
      const closeMatch = FENCE_OPEN.exec(next);
      if (!closeMatch || !closeMatch[1]) return false;
      const closer = closeMatch[1];
      return closer[0] === fence[0] && closer.length >= fence.length && !next.trim().slice(closer.length);
    };
  }
  for (const pair of SPANNING_BLOCKS) {
    const openMatch = pair.open.exec(line);
    if (!openMatch) continue;
    const rest = line.slice(openMatch[0].length);
    if (pair.close.test(rest)) return undefined;
    return (next: string): boolean => pair.close.test(next);
  }
  if (HTML_BLOCK_START.test(line)) {
    return (next: string): boolean => next.trim() === '';
  }
  return undefined;
}

export function splitMarkdown(source: string, targetChars: number = CHUNK_TARGET_CHARS): SplitMarkdown {
  const chunks: MarkdownChunk[] = [];
  const definitions: string[] = [];
  let lines: string[] = [];
  let first = true;
  let chars = 0;
  let closes: ((next: string) => boolean) | undefined = undefined;
  let afterBlankLine = false;
  let afterDefinition = false;
  let afterHeading = false;
  let definitionChars = 0;

  const flush = (): void => {
    chunks.push({ text: lines.join('\n'), lines: lines.length });
    lines = [];
    chars = 0;
  };

  for (const line of source.split('\n')) {
    if (closes !== undefined) {
      if (closes(line)) closes = undefined;
    } else if (first && FRONTMATTER_OPEN.test(line)) {
      let seen = 0;
      closes = (next: string): boolean => FRONTMATTER_CLOSE.test(next) || ++seen >= FRONTMATTER_MAX_LINES;
    } else {
      const cut = chars >= targetChars &&
        (ATX_HEADING.test(line) || (afterBlankLine && BLOCK_START.test(line) && !ORDERED_ITEM.test(line)));
      if (cut) flush();
      closes = blockCloser(line);
      const isDef = (first || afterBlankLine || afterDefinition || afterHeading) && LINK_DEFINITION.test(line);
      afterDefinition = isDef;
      if (isDef && definitionChars + line.length < SHARED_DEFINITIONS_MAX_CHARS) {
        definitions.push(line.trim());
        definitionChars += line.length + 1;
      }
    }
    first = false;
    lines.push(line);
    chars += line.length + 1;
    afterBlankLine = line.trim() === '';
    afterHeading = closes === undefined && (ATX_HEADING.test(line) || THEMATIC_BREAK.test(line));
  }
  flush();
  return { chunks, definitions: definitions.join('\n') };
}

export function withMarkdownDefinitions(chunkText: string, definitions: string): string {
  return definitions ? chunkText + '\n\n' + definitions : chunkText;
}

export function hasOversizedMarkdownChunk(split: SplitMarkdown): boolean {
  return split.chunks.some((chunk: MarkdownChunk) => chunk.text.length > LARGE_MARKDOWN_CHUNK_MAX_CHARS);
}

// --- CSV / TSV Delimited Preview ---

export interface DelimitedTable {
  delimiter: string;
  headers: string[];
  rows: string[][];
  totalRows: number;
  truncated: boolean;
}

export function isDelimitedPath(path: string): boolean {
  const lower = (path || '').toLowerCase();
  return lower.endsWith('.csv') || lower.endsWith('.tsv');
}

export function parseDelimitedPreview(
  content: string,
  path: string = '',
  maxRows: number = MAX_DELIMITED_ROWS,
  maxCols: number = MAX_DELIMITED_COLS
): DelimitedTable {
  const delimiter = (path || '').toLowerCase().endsWith('.tsv') ? '\t' : ',';
  const rows: string[][] = [];
  let row: string[] = [];
  let field = '';
  let inQuotes = false;
  let totalRows = 0;
  let truncated = false;
  const input = content.startsWith('\uFEFF') ? content.slice(1) : content;

  const pushRow = (): void => {
    if (row.length === 1 && row[0] === '' && totalRows === 0) {
      row = [];
      return;
    }
    totalRows += 1;
    if (rows.length < maxRows + 1) {
      rows.push(row.slice(0, maxCols));
    } else {
      truncated = true;
    }
    row = [];
  };

  for (let i = 0; i < input.length; i += 1) {
    const ch = input[i];
    if (inQuotes) {
      if (ch === '"') {
        if (i + 1 < input.length && input[i + 1] === '"') {
          field += '"';
          i += 1;
        } else {
          inQuotes = false;
        }
      } else {
        field += ch;
      }
      continue;
    }
    if (ch === '"' && field.length === 0) {
      inQuotes = true;
      continue;
    }
    if (ch === delimiter) {
      if (row.length < maxCols) row.push(field);
      field = '';
      continue;
    }
    if (ch === '\r' || ch === '\n') {
      if (ch === '\r' && i + 1 < input.length && input[i + 1] === '\n') i += 1;
      if (row.length < maxCols) row.push(field);
      field = '';
      pushRow();
      continue;
    }
    field += ch;
  }
  if (field.length > 0 || row.length > 0) {
    if (row.length < maxCols) row.push(field);
    pushRow();
  }

  const headers = rows.length > 0 ? rows[0] : [];
  const body = rows.length > 1 ? rows.slice(1) : [];
  let colCount = headers.length;
  for (const r of body) {
    if (r.length > colCount) colCount = r.length;
  }
  const normalizedHeaders: string[] = [];
  for (let c = 0; c < colCount; c += 1) {
    normalizedHeaders.push(c < headers.length ? headers[c] : 'Col ' + (c + 1));
  }
  const normalizedRows: string[][] = body.map((r: string[]): string[] => {
    const out: string[] = [];
    for (let c = 0; c < colCount; c += 1) out.push(c < r.length ? r[c] : '');
    return out;
  });

  return {
    delimiter,
    headers: normalizedHeaders,
    rows: normalizedRows,
    totalRows: Math.max(0, totalRows - (rows.length > 0 ? 1 : 0)),
    truncated
  };
}

// --- RTF Preview Extractor ---

export function isRtfPath(path: string): boolean {
  return (path || '').toLowerCase().endsWith('.rtf');
}

const CP1252_EXTRA: Record<number, string> = {
  0x80: '\u20AC', 0x82: '\u201A', 0x83: '\u0192', 0x84: '\u201E', 0x85: '\u2026',
  0x86: '\u2020', 0x87: '\u2021', 0x88: '\u02C6', 0x89: '\u2030', 0x8A: '\u0160',
  0x8B: '\u2039', 0x8C: '\u0152', 0x8E: '\u017D', 0x91: '\u2018', 0x92: '\u2019',
  0x93: '\u201C', 0x94: '\u201D', 0x95: '\u2022', 0x96: '\u2013', 0x97: '\u2014',
  0x98: '\u02DC', 0x99: '\u2122', 0x9A: '\u0161', 0x9B: '\u203A', 0x9C: '\u0153',
  0x9E: '\u017E', 0x9F: '\u0178'
};

const RTF_SKIP_DESTINATIONS: string[] = [
  'fonttbl', 'colortbl', 'stylesheet', 'info', 'pict', 'object', 'header', 'footer',
  'headerl', 'headerr', 'headerf', 'footerl', 'footerr', 'footerf', 'listtable',
  'listoverridetable', 'rsidtbl', 'generator', 'xmlnstbl', 'mmathPr', 'themedata', 'colorschememapping'
];

function decodeCp1252Byte(byte: number): string {
  if (CP1252_EXTRA[byte] !== undefined) return CP1252_EXTRA[byte];
  return String.fromCharCode(byte);
}

interface RtfGroupState {
  uc: number;
  skip: boolean;
}

export function parseRtfToText(source: string): string {
  const input = source || '';
  if (!input.trim().startsWith('{\\rtf')) return input;
  const stack: RtfGroupState[] = [{ uc: 1, skip: false }];
  let out = '';
  let i = 0;

  while (i < input.length) {
    const state = stack[stack.length - 1];
    const ch = input[i];
    if (ch === '{') {
      stack.push({ uc: state.uc, skip: state.skip });
      i += 1;
      continue;
    }
    if (ch === '}') {
      if (stack.length > 1) stack.pop();
      i += 1;
      continue;
    }
    if (ch === '\r' || ch === '\n') {
      i += 1;
      continue;
    }
    if (ch === '\\') {
      i += 1;
      if (i >= input.length) break;
      const next = input[i];
      if (next === '\\' || next === '{' || next === '}') {
        if (!state.skip) out += next;
        i += 1;
        continue;
      }
      if (next === '*') {
        state.skip = true;
        i += 1;
        continue;
      }
      if (next === '~') {
        if (!state.skip) out += ' ';
        i += 1;
        continue;
      }
      if (next === '-' || next === '_') {
        if (!state.skip) out += '-';
        i += 1;
        continue;
      }
      if (next === '\r' || next === '\n') {
        if (!state.skip) out += '\n';
        i += 1;
        continue;
      }
      if (next === "'") {
        const hex = input.slice(i + 1, i + 3);
        const byte = Number.parseInt(hex, 16);
        if (!state.skip && Number.isFinite(byte)) out += decodeCp1252Byte(byte);
        i += 3;
        continue;
      }
      const wordMatch = /^([a-zA-Z]+)(-?\d+)?[ ]?/.exec(input.slice(i));
      if (wordMatch) {
        const word = wordMatch[1];
        const param = wordMatch[2] !== undefined ? Number.parseInt(wordMatch[2], 10) : NaN;
        i += wordMatch[0].length;
        if (RTF_SKIP_DESTINATIONS.includes(word)) {
          state.skip = true;
          continue;
        }
        if (word === 'uc' && Number.isFinite(param) && param >= 0) {
          state.uc = param;
          continue;
        }
        if (word === 'u' && Number.isFinite(param)) {
          const code = param < 0 ? param + 65536 : param;
          if (!state.skip) out += String.fromCharCode(code);
          // Skip replacement bytes for the unicode escape.
          let toSkip = state.uc;
          while (toSkip > 0 && i < input.length) {
            if (input[i] === '\\' && input[i + 1] === "'") {
              i += 4;
            } else {
              i += 1;
            }
            toSkip -= 1;
          }
          continue;
        }
        if (!state.skip) {
          if (word === 'par' || word === 'line') out += '\n';
          else if (word === 'tab') out += '\t';
          else if (word === 'emdash') out += '—';
          else if (word === 'endash') out += '–';
          else if (word === 'lquote') out += '‘';
          else if (word === 'rquote') out += '’';
          else if (word === 'ldblquote') out += '“';
          else if (word === 'rdblquote') out += '”';
          else if (word === 'bullet') out += '• ';
        }
        continue;
      }
      i += 1;
      continue;
    }
    if (!state.skip) out += ch;
    i += 1;
  }
  return out.replace(/\n{3,}/g, '\n\n').trim();
}

// --- ZIP Archive Central Directory Parser ---

export interface ZipEntry {
  path: string;
  name: string;
  isDirectory: boolean;
  compressedSize: number;
  uncompressedSize: number;
}

export interface ZipBrowserItem {
  path: string;
  name: string;
  isDirectory: boolean;
  sizeBytes: number;
  childCount: number;
}

export function isZipPath(path: string): boolean {
  return (path || '').toLowerCase().endsWith('.zip');
}

function readUint16LE(bytes: Uint8Array, offset: number): number {
  return bytes[offset] | (bytes[offset + 1] << 8);
}

function readUint32LE(bytes: Uint8Array, offset: number): number {
  return (bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24)) >>> 0;
}

function decodeUtf8Bytes(bytes: Uint8Array): string {
  let out = '';
  let i = 0;
  while (i < bytes.length) {
    const b0 = bytes[i];
    if (b0 < 0x80) {
      out += String.fromCharCode(b0);
      i += 1;
    } else if ((b0 & 0xe0) === 0xc0 && i + 1 < bytes.length) {
      out += String.fromCharCode(((b0 & 0x1f) << 6) | (bytes[i + 1] & 0x3f));
      i += 2;
    } else if ((b0 & 0xf0) === 0xe0 && i + 2 < bytes.length) {
      out += String.fromCharCode(((b0 & 0x0f) << 12) | ((bytes[i + 1] & 0x3f) << 6) | (bytes[i + 2] & 0x3f));
      i += 3;
    } else if ((b0 & 0xf8) === 0xf0 && i + 3 < bytes.length) {
      const cp = (((b0 & 0x07) << 18) | ((bytes[i + 1] & 0x3f) << 12) | ((bytes[i + 2] & 0x3f) << 6) | (bytes[i + 3] & 0x3f)) - 0x10000;
      out += String.fromCharCode(0xd800 + (cp >> 10), 0xdc00 + (cp & 0x3ff));
      i += 4;
    } else {
      out += String.fromCharCode(b0);
      i += 1;
    }
  }
  return out;
}

export function parseZipEntries(buffer: ArrayBuffer): ZipEntry[] {
  const bytes = new Uint8Array(buffer);
  if (bytes.length < 22) throw new Error('ZIP 文件不完整或格式无效');
  const minPos = Math.max(0, bytes.length - 65557);
  let eocdOffset = -1;
  for (let pos = bytes.length - 22; pos >= minPos; pos -= 1) {
    if (bytes[pos] === 0x50 && bytes[pos + 1] === 0x4b && bytes[pos + 2] === 0x05 && bytes[pos + 3] === 0x06) {
      eocdOffset = pos;
      break;
    }
  }
  if (eocdOffset < 0) throw new Error('未找到 ZIP 目录索引');
  const entryCount = readUint16LE(bytes, eocdOffset + 10);
  const cdSize = readUint32LE(bytes, eocdOffset + 12);
  const cdOffset = readUint32LE(bytes, eocdOffset + 16);
  if (cdOffset + cdSize > bytes.length) throw new Error('ZIP 目录索引越界');

  const entries: ZipEntry[] = [];
  let cursor = cdOffset;
  const end = cdOffset + cdSize;
  const limit = Math.min(entryCount, MAX_ZIP_ENTRIES);
  for (let i = 0; i < limit && cursor + 46 <= end; i += 1) {
    if (readUint32LE(bytes, cursor) !== 0x02014b50) break;
    const compressedSize = readUint32LE(bytes, cursor + 20);
    const uncompressedSize = readUint32LE(bytes, cursor + 24);
    const nameLen = readUint16LE(bytes, cursor + 28);
    const extraLen = readUint16LE(bytes, cursor + 30);
    const commentLen = readUint16LE(bytes, cursor + 32);
    if (cursor + 46 + nameLen > end) break;
    const rawPath = decodeUtf8Bytes(bytes.subarray(cursor + 46, cursor + 46 + nameLen));
    cursor += 46 + nameLen + extraLen + commentLen;
    const normalized = rawPath.replace(/\\/g, '/').replace(/^\/+/, '');
    if (!normalized || normalized.startsWith('__MACOSX/')) continue;
    const isDirectory = normalized.endsWith('/');
    const trimmed = isDirectory ? normalized.slice(0, -1) : normalized;
    if (!trimmed) continue;
    const slash = trimmed.lastIndexOf('/');
    const name = slash >= 0 ? trimmed.slice(slash + 1) : trimmed;
    entries.push({ path: trimmed, name, isDirectory, compressedSize, uncompressedSize });
  }
  return entries;
}

export function listZipDirectory(entries: ZipEntry[], dirPath: string): ZipBrowserItem[] {
  const prefix = dirPath ? dirPath.replace(/\/+$/, '') + '/' : '';
  const dirs: Map<string, number> = new Map();
  const files: ZipBrowserItem[] = [];

  for (const entry of entries) {
    if (prefix && !entry.path.startsWith(prefix)) continue;
    const rest = prefix ? entry.path.slice(prefix.length) : entry.path;
    if (!rest) continue;
    const slash = rest.indexOf('/');
    if (slash >= 0) {
      const dirName = rest.slice(0, slash);
      const fullDir = prefix + dirName;
      dirs.set(fullDir, (dirs.get(fullDir) ?? 0) + (entry.isDirectory ? 0 : 1));
    } else if (entry.isDirectory) {
      if (!dirs.has(entry.path)) dirs.set(entry.path, 0);
    } else {
      files.push({
        path: entry.path,
        name: entry.name,
        isDirectory: false,
        sizeBytes: entry.uncompressedSize,
        childCount: 0
      });
    }
  }

  const result: ZipBrowserItem[] = [];
  for (const fullDir of Array.from(dirs.keys()).sort()) {
    const slash = fullDir.lastIndexOf('/');
    result.push({
      path: fullDir,
      name: slash >= 0 ? fullDir.slice(slash + 1) : fullDir,
      isDirectory: true,
      sizeBytes: 0,
      childCount: dirs.get(fullDir) ?? 0
    });
  }
  files.sort((a: ZipBrowserItem, b: ZipBrowserItem) => a.name.localeCompare(b.name));
  return result.concat(files);
}

// --- Lightweight Syntax Highlighting Tokenizer ---

export type SyntaxTokenKind = 'plain' | 'keyword' | 'string' | 'comment' | 'number' | 'type';

export interface SyntaxToken {
  text: string;
  kind: SyntaxTokenKind;
}

const JS_KEYWORDS: string[] = [
  'import', 'export', 'from', 'default', 'const', 'let', 'var', 'function', 'return', 'if', 'else',
  'for', 'while', 'do', 'switch', 'case', 'break', 'continue', 'try', 'catch', 'finally', 'throw',
  'new', 'class', 'struct', 'interface', 'type', 'enum', 'extends', 'implements', 'async', 'await',
  'private', 'public', 'protected', 'readonly', 'static', 'true', 'false', 'null', 'undefined', 'void',
  'typeof', 'instanceof', 'in', 'of', 'as', 'this', 'super'
];

const PY_KEYWORDS: string[] = [
  'import', 'from', 'as', 'def', 'class', 'return', 'yield', 'if', 'elif', 'else', 'for', 'while',
  'break', 'continue', 'try', 'except', 'finally', 'raise', 'with', 'pass', 'lambda', 'and', 'or',
  'not', 'in', 'is', 'None', 'True', 'False', 'async', 'await', 'self'
];

const C_LIKE_KEYWORDS: string[] = [
  'fn', 'fun', 'func', 'pub', 'use', 'mod', 'struct', 'enum', 'impl', 'trait', 'let', 'mut', 'const',
  'static', 'var', 'val', 'package', 'import', 'return', 'if', 'else', 'for', 'while', 'loop', 'match',
  'switch', 'case', 'break', 'continue', 'try', 'catch', 'throw', 'class', 'interface', 'public',
  'private', 'protected', 'override', 'true', 'false', 'null', 'nil', 'void', 'int', 'long', 'bool',
  'boolean', 'char', 'float', 'double', 'auto', 'defer', 'go', 'chan', 'select', 'type', 'new', 'async', 'await'
];

const SQL_KEYWORDS: string[] = [
  'SELECT', 'FROM', 'WHERE', 'INSERT', 'INTO', 'VALUES', 'UPDATE', 'SET', 'DELETE', 'CREATE', 'TABLE',
  'ALTER', 'DROP', 'INDEX', 'JOIN', 'LEFT', 'RIGHT', 'INNER', 'OUTER', 'ON', 'GROUP', 'BY', 'ORDER',
  'LIMIT', 'OFFSET', 'AS', 'AND', 'OR', 'NOT', 'NULL', 'IS', 'IN', 'EXISTS', 'DISTINCT', 'PRIMARY', 'KEY'
];

export function detectCodeLanguage(path: string): string {
  const lower = (path || '').toLowerCase();
  const dot = lower.lastIndexOf('.');
  const ext = dot >= 0 ? lower.slice(dot + 1) : '';
  if (['ts', 'tsx', 'ets', 'js', 'jsx', 'mjs', 'cjs'].includes(ext)) return 'ts';
  if (ext === 'py') return 'py';
  if (['rs', 'go', 'java', 'kt', 'kts', 'swift', 'c', 'h', 'cc', 'cpp', 'hpp', 'cs'].includes(ext)) return 'clike';
  if (['json', 'jsonc', 'json5'].includes(ext)) return 'json';
  if (['yaml', 'yml'].includes(ext)) return 'yaml';
  if (['sh', 'bash', 'zsh'].includes(ext)) return 'shell';
  if (ext === 'sql') return 'sql';
  if (['html', 'htm', 'xml', 'svg'].includes(ext)) return 'xml';
  if (['css', 'scss', 'less'].includes(ext)) return 'css';
  return '';
}

function keywordsFor(lang: string): string[] {
  if (lang === 'ts') return JS_KEYWORDS;
  if (lang === 'py') return PY_KEYWORDS;
  if (lang === 'clike') return C_LIKE_KEYWORDS;
  if (lang === 'sql') return SQL_KEYWORDS;
  return [];
}

export function tokenizeCodeLine(line: string, lang: string): SyntaxToken[] {
  if (!line || !lang || line.length > 600) return [{ text: line, kind: 'plain' }];
  const tokens: SyntaxToken[] = [];
  const push = (text: string, kind: SyntaxTokenKind): void => {
    if (!text) return;
    if (tokens.length > 0 && tokens[tokens.length - 1].kind === kind) {
      tokens[tokens.length - 1].text += text;
    } else {
      tokens.push({ text, kind });
    }
  };

  const hashComment = lang === 'py' || lang === 'yaml' || lang === 'shell';
  const slashComment = lang === 'ts' || lang === 'clike' || lang === 'json' || lang === 'css';
  const sqlComment = lang === 'sql';
  const keywords = keywordsFor(lang);
  let i = 0;

  while (i < line.length) {
    const ch = line[i];
    if (slashComment && ch === '/' && line[i + 1] === '/') {
      push(line.slice(i), 'comment');
      break;
    }
    if (hashComment && ch === '#') {
      push(line.slice(i), 'comment');
      break;
    }
    if (sqlComment && ch === '-' && line[i + 1] === '-') {
      push(line.slice(i), 'comment');
      break;
    }
    if (slashComment && ch === '/' && line[i + 1] === '*') {
      const end = line.indexOf('*/', i + 2);
      if (end >= 0) {
        push(line.slice(i, end + 2), 'comment');
        i = end + 2;
      } else {
        push(line.slice(i), 'comment');
        break;
      }
      continue;
    }
    if (ch === '"' || ch === "'" || (ch === '`' && lang === 'ts')) {
      let j = i + 1;
      while (j < line.length) {
        if (line[j] === '\\') { j += 2; continue; }
        if (line[j] === ch) { j += 1; break; }
        j += 1;
      }
      push(line.slice(i, j), 'string');
      i = j;
      continue;
    }
    if (lang === 'xml' && ch === '<') {
      const end = line.indexOf('>', i + 1);
      if (end >= 0) {
        push(line.slice(i, end + 1), 'keyword');
        i = end + 1;
        continue;
      }
    }
    if (ch >= '0' && ch <= '9' && (i === 0 || !/[A-Za-z0-9_$]/.test(line[i - 1]))) {
      let j = i + 1;
      while (j < line.length && /[0-9a-fA-FxXoObB_.]/.test(line[j])) j += 1;
      push(line.slice(i, j), 'number');
      i = j;
      continue;
    }
    if (/[A-Za-z_$@]/.test(ch)) {
      let j = i + 1;
      while (j < line.length && /[A-Za-z0-9_$]/.test(line[j])) j += 1;
      const word = line.slice(i, j);
      if (ch === '@') {
        push(word, 'keyword');
      } else if (lang === 'sql' ? keywords.includes(word.toUpperCase()) : keywords.includes(word)) {
        push(word, 'keyword');
      } else if (lang === 'json' && (word === 'true' || word === 'false' || word === 'null')) {
        push(word, 'keyword');
      } else if (/^[A-Z][A-Za-z0-9_]*$/.test(word) && word.length > 1) {
        push(word, 'type');
      } else {
        push(word, 'plain');
      }
      i = j;
      continue;
    }
    push(ch, 'plain');
    i += 1;
  }
  return tokens;
}

// --- Intra-line Word-Level Diff ---

export interface WordDiffSegment {
  text: string;
  changed: boolean;
}

export interface WordDiffPair {
  oldSegments: WordDiffSegment[];
  newSegments: WordDiffSegment[];
}

function splitDiffWords(text: string): string[] {
  const parts: string[] = [];
  const regex = /[A-Za-z0-9_]+|\s+|[^\sA-Za-z0-9_]/g;
  let match: RegExpExecArray | null = regex.exec(text);
  while (match !== null) {
    parts.push(match[0]);
    match = regex.exec(text);
  }
  return parts;
}

function mergeSegments(segments: WordDiffSegment[]): WordDiffSegment[] {
  const merged: WordDiffSegment[] = [];
  for (const seg of segments) {
    if (!seg.text) continue;
    if (merged.length > 0 && merged[merged.length - 1].changed === seg.changed) {
      merged[merged.length - 1].text += seg.text;
    } else {
      merged.push({ text: seg.text, changed: seg.changed });
    }
  }
  return merged;
}

export function computeWordDiff(oldLine: string, newLine: string): WordDiffPair {
  if (oldLine === newLine) {
    return {
      oldSegments: [{ text: oldLine, changed: false }],
      newSegments: [{ text: newLine, changed: false }]
    };
  }
  const a = splitDiffWords(oldLine);
  const b = splitDiffWords(newLine);
  if (a.length * b.length > 40000) {
    // Fallback to common prefix/suffix for very long lines.
    let prefix = 0;
    while (prefix < a.length && prefix < b.length && a[prefix] === b[prefix]) prefix += 1;
    let suffix = 0;
    while (suffix < a.length - prefix && suffix < b.length - prefix &&
      a[a.length - 1 - suffix] === b[b.length - 1 - suffix]) {
      suffix += 1;
    }
    return {
      oldSegments: mergeSegments([
        { text: a.slice(0, prefix).join(''), changed: false },
        { text: a.slice(prefix, a.length - suffix).join(''), changed: true },
        { text: a.slice(a.length - suffix).join(''), changed: false }
      ]),
      newSegments: mergeSegments([
        { text: b.slice(0, prefix).join(''), changed: false },
        { text: b.slice(prefix, b.length - suffix).join(''), changed: true },
        { text: b.slice(b.length - suffix).join(''), changed: false }
      ])
    };
  }

  let prefix = 0;
  while (prefix < a.length && prefix < b.length && a[prefix] === b[prefix]) prefix += 1;
  let suffix = 0;
  while (suffix < a.length - prefix && suffix < b.length - prefix &&
    a[a.length - 1 - suffix] === b[b.length - 1 - suffix]) {
    suffix += 1;
  }

  const aMid = a.slice(prefix, a.length - suffix);
  const bMid = b.slice(prefix, b.length - suffix);
  const m = aMid.length;
  const n = bMid.length;
  const dp: number[][] = [];
  for (let i = 0; i <= m; i += 1) {
    const row: number[] = [];
    for (let j = 0; j <= n; j += 1) row.push(0);
    dp.push(row);
  }
  for (let i = m - 1; i >= 0; i -= 1) {
    for (let j = n - 1; j >= 0; j -= 1) {
      if (aMid[i] === bMid[j]) dp[i][j] = dp[i + 1][j + 1] + 1;
      else dp[i][j] = dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1];
    }
  }

  const oldSegs: WordDiffSegment[] = [];
  const newSegs: WordDiffSegment[] = [];
  if (prefix > 0) {
    const pText = a.slice(0, prefix).join('');
    oldSegs.push({ text: pText, changed: false });
    newSegs.push({ text: pText, changed: false });
  }
  let i = 0;
  let j = 0;
  while (i < m && j < n) {
    if (aMid[i] === bMid[j]) {
      oldSegs.push({ text: aMid[i], changed: false });
      newSegs.push({ text: bMid[j], changed: false });
      i += 1;
      j += 1;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      oldSegs.push({ text: aMid[i], changed: true });
      i += 1;
    } else {
      newSegs.push({ text: bMid[j], changed: true });
      j += 1;
    }
  }
  while (i < m) { oldSegs.push({ text: aMid[i], changed: true }); i += 1; }
  while (j < n) { newSegs.push({ text: bMid[j], changed: true }); j += 1; }
  if (suffix > 0) {
    const sText = a.slice(a.length - suffix).join('');
    oldSegs.push({ text: sText, changed: false });
    newSegs.push({ text: sText, changed: false });
  }
  return { oldSegments: mergeSegments(oldSegs), newSegments: mergeSegments(newSegs) };
}
