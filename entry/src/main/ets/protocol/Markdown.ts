// GFM subset matching the mobile Markdown surface: headings, lists, tables, quotes,
// fenced code, details folds, math, images, links and inline emphasis.
export type InlineKind = 'text' | 'strong' | 'em' | 'code' | 'strike' | 'link' | 'math' | 'image';

export interface InlineSpan {
  kind: InlineKind;
  text: string;
  href?: string;
}

export interface MarkdownListItem {
  depth: number;
  ordered: boolean;
  marker: string;
  checked: boolean | undefined;
  text: string;
  spans: InlineSpan[];
}

export interface MarkdownBlock {
  kind: string;
  text: string;
  level: number;
  spans: InlineSpan[];
  language: string;
  ordered: boolean;
  start: number;
  items: MarkdownListItem[];
  header: string[];
  align: string[];
  rows: string[][];
  summary: string;
  body: string;
  open: boolean;
  alt: string;
  url: string;
}

function block(kind: string): MarkdownBlock {
  return { kind, text: '', level: 0, spans: [], language: '', ordered: false, start: 1,
    items: [], header: [], align: [], rows: [], summary: '', body: '', open: false, alt: '', url: '' };
}

const FENCE = /^ {0,3}(`{3,}|~{3,})\s*([^`]*)$/;
const HEADING = /^ {0,3}(#{1,6})(?:\s+(.*))?$/;
const HR = /^ {0,3}(?:(?:\*\s*){3,}|(?:-\s*){3,}|(?:_\s*){3,})$/;
const LIST = /^(\s*)([-*+]|\d{1,9}[.)])\s+(.*)$/;
const TABLE_SEPARATOR = /^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)+\|?\s*$/;
const DETAILS = /^\s*<details\b/i;
const SUMMARY = /<summary\b[^>]*>([\s\S]*?)<\/summary\s*>/i;

function isBlank(line: string): boolean { return !line.trim(); }

function isBlockStart(line: string, next: string | undefined): boolean {
  if (isBlank(line)) return true;
  if (FENCE.test(line) || HEADING.test(line) || HR.test(line) || DETAILS.test(line)) return true;
  if (/^ {0,3}>/.test(line)) return true;
  if (LIST.test(line)) return true;
  if (/^\s*\$\$/.test(line)) return true;
  if (isTableHeader(line, next)) return true;
  if (next !== undefined && /^ {0,3}(=+|-+)\s*$/.test(next) && line.trim()) return true;
  return false;
}

function splitTableRow(line: string): string[] {
  let value = line.trim();
  if (value.startsWith('|')) value = value.slice(1);
  if (value.endsWith('|') && !value.endsWith('\\|')) value = value.slice(0, -1);
  const cells: string[] = [];
  let cell = '';
  for (let index = 0; index < value.length; index += 1) {
    const char = value[index];
    if (char === '\\' && value[index + 1] === '|') { cell += '|'; index += 1; continue; }
    if (char === '|') { cells.push(cell.trim()); cell = ''; continue; }
    cell += char;
  }
  cells.push(cell.trim());
  return cells;
}

function isTableHeader(line: string, next: string | undefined): boolean {
  return next !== undefined && line.includes('|') && TABLE_SEPARATOR.test(next);
}

function tableAlign(value: string): string {
  const cell = value.trim();
  const left = cell.startsWith(':');
  const right = cell.endsWith(':');
  return left && right ? 'center' : right ? 'right' : left ? 'left' : '';
}

function decodeEntity(value: string): string {
  return value.replace(/&(?:#(\d+)|#x([0-9a-f]+)|amp|lt|gt|quot|apos|nbsp);/gi,
    (entity: string, decimal: string | undefined, hex: string | undefined): string => {
      if (decimal) return String.fromCodePoint(Number.parseInt(decimal, 10));
      if (hex) return String.fromCodePoint(Number.parseInt(hex, 16));
      switch (entity.toLowerCase()) {
        case '&amp;': return '&';
        case '&lt;': return '<';
        case '&gt;': return '>';
        case '&quot;': return '"';
        case '&apos;': return '\'';
        case '&nbsp;': return '\u00a0';
        default: return entity;
      }
    }).replace(/^<([^>]+)>$/, '$1');
}

/** Safe inverse of the small HTML set mdast accepts; raw tags never reach the UI. */
function plainInline(value: string): string {
  return decodeEntity(value.replace(/<\/?[a-z][^>]*>/gi, '')).replace(/\\([\\`*_{}\[\]()#+\-.!>~|])/g, '$1');
}

function findClosing(value: string, marker: string, from: number): number {
  let index = value.indexOf(marker, from);
  while (index >= 0) {
    let slashes = 0;
    while (value[index - 1 - slashes] === '\\') slashes += 1;
    if (slashes % 2 === 0) return index;
    index = value.indexOf(marker, index + marker.length);
  }
  return -1;
}

function scanLink(value: string, start: number): { text: string; url: string; end: number } | undefined {
  const close = value.indexOf(']', start + 1);
  if (close < 0 || value[close + 1] !== '(') return undefined;
  let depth = 1;
  let index = close + 2;
  let url = '';
  while (index < value.length) {
    const char = value[index];
    if (char === '\\' && index + 1 < value.length) { url += value[index + 1]; index += 2; continue; }
    if (char === '(') depth += 1;
    if (char === ')') { depth -= 1; if (depth === 0) break; }
    url += char;
    index += 1;
  }
  if (depth !== 0) return undefined;
  const destination = url.trim().replace(/^<|>$/g, '').split(/\s+/)[0];
  return { text: value.slice(start + 1, close), url: destination, end: index + 1 };
}

export function inlineSpans(source: string): InlineSpan[] {
  const spans: InlineSpan[] = [];
  let buffer = '';
  const push = (kind: InlineKind, text: string, href?: string): void => {
    if (!text) return;
    if (kind === 'text' && buffer) { spans.push({ kind: 'text', text: buffer }); buffer = ''; }
    spans.push({ kind, text, ...(href === undefined ? {} : { href }) });
  };
  const flush = (): void => { if (buffer) { spans.push({ kind: 'text', text: buffer }); buffer = ''; } };
  let index = 0;
  while (index < source.length) {
    const char = source[index];
    if (char === '\\' && index + 1 < source.length) { buffer += source[index + 1]; index += 2; continue; }
    if (char === '`') {
      let run = 1;
      while (source[index + run] === '`') run += 1;
      const marker = '`'.repeat(run);
      const close = source.indexOf(marker, index + run);
      if (close >= 0) {
        flush();
        push('code', source.slice(index + run, close).replace(/\n/g, ' '));
        index = close + run;
        continue;
      }
    }
    if (char === '!' && source[index + 1] === '[') {
      const link = scanLink(source, index + 1);
      if (link) {
        flush();
        push('image', plainInline(link.text), link.url);
        index = link.end;
        continue;
      }
    }
    if (char === '[') {
      const link = scanLink(source, index);
      if (link) {
        flush();
        push('link', plainInline(link.text), link.url);
        index = link.end;
        continue;
      }
    }
    if (char === '<') {
      const close = source.indexOf('>', index + 1);
      if (close > index) {
        const value = source.slice(index + 1, close);
        if (/^(https?:\/\/|mailto:)/i.test(value) || /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)) {
          flush();
          push('link', value, /^mailto:/i.test(value) || /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value) ? 'mailto:' + value.replace(/^mailto:/i, '') : value);
          index = close + 1;
          continue;
        }
      }
    }
    if (char === '$' && source[index + 1] !== '$') {
      const close = findClosing(source, '$', index + 1);
      if (close > index + 1) {
        flush(); push('math', source.slice(index + 1, close)); index = close + 1; continue;
      }
    }
    const strong = char === '*' || char === '_' ? char + char : '';
    if (strong) {
      const close = findClosing(source, strong, index + 2);
      if (close > index + 2) {
        flush(); push('strong', source.slice(index + 2, close)); index = close + 2; continue;
      }
    }
    if (char === '~' && source[index + 1] === '~') {
      const close = findClosing(source, '~~', index + 2);
      if (close > index + 2) {
        flush(); push('strike', source.slice(index + 2, close)); index = close + 2; continue;
      }
    }
    if (char === '*' || char === '_') {
      const close = findClosing(source, char, index + 1);
      if (close > index + 1) {
        flush(); push('em', source.slice(index + 1, close)); index = close + 1; continue;
      }
    }
    buffer += char;
    index += 1;
  }
  flush();
  return spans;
}

function nestedDetailsCount(value: string): number {
  const opens = value.match(/<details\b/gi);
  const closes = value.match(/<\/details\s*>/gi);
  return (opens ? opens.length : 0) - (closes ? closes.length : 0);
}

/** Folds run to their end while streaming: an unclosed <details> shows the rest. */
function collectDetails(lines: string[], start: number): { body: string; open: boolean; next: number } {
  const openTag = lines[start];
  const open = /\sopen(\s|=|>)/i.test(openTag.replace(/"[^"]*"|'[^']*'/g, ''));
  const chunks: string[] = [];
  let depth = 0;
  let index = start;
  while (index < lines.length) {
    const line = lines[index];
    if (index > start) chunks.push(line);
    depth += nestedDetailsCount(line);
    const close = /<\/details\s*>/i.test(line);
    if (index === start && /<\/details\s*>/i.test(openTag)) {
      chunks.push(openTag.replace(/<details\b[^>]*>/i, '').replace(/<\/details\s*>/i, ''));
      break;
    }
    if (index > start && close && depth <= 0) { chunks.pop(); break; }
    index += 1;
  }
  const body = chunks.join('\n');
  const summaryMatch = SUMMARY.exec(body);
  const summary = summaryMatch ? plainInline(summaryMatch[1]) : 'Details';
  return { body: summaryMatch ? body.replace(SUMMARY, '') : body, open, next: index + 1 };
}

function parseItems(lines: string[], start: number): { items: MarkdownListItem[]; next: number } {
  const items: MarkdownListItem[] = [];
  let index = start;
  let orderStart = 0;
  while (index < lines.length) {
    const match = LIST.exec(lines[index]);
    if (!match) break;
    const indent = match[1].replace(/\t/g, '    ').length;
    const marker = match[2];
    const ordered = /\d/.test(marker);
    if (ordered && orderStart === 0) orderStart = Number.parseInt(marker, 10);
    let text = match[3];
    let checked: boolean | undefined = undefined;
    const task = /^\[([ xX])\]\s+(.*)$/.exec(text);
    if (task) { checked = task[1].toLowerCase() === 'x'; text = task[2]; }
    index += 1;
    while (index < lines.length && !isBlank(lines[index]) && !LIST.test(lines[index]) &&
      /^\s{2,}|^\t/.test(lines[index]) && !FENCE.test(lines[index])) {
      text += ' ' + lines[index].trim();
      index += 1;
    }
    items.push({ depth: Math.floor(indent / 2), ordered, marker, checked,
      text: plainInline(text), spans: inlineSpans(text) });
    while (index < lines.length && isBlank(lines[index])) {
      const ahead = lines.findIndex((line: string, position: number) => position > index && !isBlank(line));
      if (ahead < 0 || !LIST.test(lines[ahead])) break;
      index = ahead;
    }
  }
  return { items, next: index };
}

export function markdownDocument(source: string): MarkdownBlock[] {
  const blocks: MarkdownBlock[] = [];
  const lines = source.replace(/\r\n?/g, '\n').split('\n');
  let index = 0;
  while (index < lines.length) {
    const line = lines[index];
    if (isBlank(line)) { index += 1; continue; }
    const fence = FENCE.exec(line);
    if (fence) {
      const marker = fence[1][0];
      const language = fence[2].trim().split(/\s+/)[0] || '';
      const body: string[] = [];
      index += 1;
      while (index < lines.length && !new RegExp('^ {0,3}' + marker + '{3,}\\s*$').test(lines[index])) {
        body.push(lines[index]);
        index += 1;
      }
      index += 1;
      const code = block('code');
      code.text = body.join('\n');
      code.language = language;
      blocks.push(code);
      continue;
    }
    if (DETAILS.test(line)) {
      const fold = collectDetails(lines, index);
      const details = block('details');
      const summaryMatch = SUMMARY.exec(line);
      details.summary = summaryMatch ? plainInline(summaryMatch[1]) : 'Details';
      details.body = fold.body;
      details.open = fold.open;
      blocks.push(details);
      index = fold.next;
      continue;
    }
    if (/^\s*\$\$/.test(line)) {
      const body: string[] = [];
      const rest = line.replace(/^\s*\$\$\s*/, '');
      const singleLine = /^(.*?)\s*\$\$\s*$/.exec(rest);
      if (singleLine) {
        const math = block('math');
        math.text = singleLine[1].trim();
        blocks.push(math);
        index += 1;
        continue;
      }
      if (rest.trim()) body.push(rest);
      index += 1;
      while (index < lines.length && !/\$\$\s*$/.test(lines[index])) { body.push(lines[index]); index += 1; }
      if (index < lines.length) {
        const tail = lines[index].replace(/\s*\$\$\s*$/, '');
        if (tail.trim()) body.push(tail);
        index += 1;
      }
      const math = block('math');
      math.text = body.join('\n');
      blocks.push(math);
      continue;
    }
    const heading = HEADING.exec(line);
    if (heading) {
      const text = plainInline((heading[2] || '').replace(/\s+#+\s*$/, ''));
      const title = block('heading');
      title.level = heading[1].length;
      title.text = text;
      title.spans = inlineSpans(text);
      blocks.push(title);
      index += 1;
      continue;
    }
    if (index + 1 < lines.length && line.trim() && /^ {0,3}(=+|-+)\s*$/.test(lines[index + 1])) {
      const text = plainInline(line.trim());
      const title = block('heading');
      title.level = lines[index + 1].trim().startsWith('=') ? 1 : 2;
      title.text = text;
      title.spans = inlineSpans(text);
      blocks.push(title);
      index += 2;
      continue;
    }
    if (HR.test(line)) { blocks.push(block('hr')); index += 1; continue; }
    if (/^ {0,3}>/.test(line)) {
      const body: string[] = [];
      while (index < lines.length && (/^ {0,3}>/.test(lines[index]) || (body.length > 0 && !isBlank(lines[index])))) {
        body.push(lines[index].replace(/^ {0,3}>\s?/, ''));
        index += 1;
      }
      const textValue = plainInline(body.join('\n'));
      const quote = block('quote');
      quote.text = textValue;
      quote.spans = inlineSpans(body.join('\n'));
      blocks.push(quote);
      continue;
    }
    if (LIST.test(line)) {
      const parsed = parseItems(lines, index);
      const ordered = parsed.items.length > 0 && parsed.items[0].ordered;
      const startValue = ordered ? Number.parseInt(parsed.items[0].marker, 10) : 1;
      const list = block('list');
      list.ordered = ordered;
      list.start = Number.isFinite(startValue) ? startValue : 1;
      list.items = parsed.items;
      blocks.push(list);
      index = parsed.next;
      continue;
    }
    if (isTableHeader(line, lines[index + 1])) {
      const header = splitTableRow(line);
      const align = splitTableRow(lines[index + 1]).map(tableAlign);
      index += 2;
      const rows: string[][] = [];
      while (index < lines.length && lines[index].includes('|') && !isBlank(lines[index])) {
        rows.push(splitTableRow(lines[index]));
        index += 1;
      }
      const table = block('table');
      table.header = header;
      table.align = align;
      table.rows = rows;
      blocks.push(table);
      continue;
    }
    const image = /^\s*!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)\s*$/.exec(line);
    if (image) {
      const imageBlock = block('image');
      imageBlock.alt = plainInline(image[1]);
      imageBlock.url = image[2];
      blocks.push(imageBlock);
      index += 1;
      continue;
    }
    const paragraphLines: string[] = [line];
    index += 1;
    while (index < lines.length && !isBlank(lines[index]) &&
      !isBlockStart(lines[index], lines[index + 1])) {
      paragraphLines.push(lines[index]);
      index += 1;
    }
    const textValue = paragraphLines.map((value: string) => value.trim()).join('\n');
    const paragraph = block('paragraph');
    paragraph.text = plainInline(textValue);
    paragraph.spans = inlineSpans(textValue);
    blocks.push(paragraph);
  }
  return blocks;
}

const MATH_COMMANDS: Record<string, string> = {
  '\\alpha': 'α', '\\beta': 'β', '\\gamma': 'γ', '\\delta': 'δ', '\\epsilon': 'ε', '\\theta': 'θ',
  '\\lambda': 'λ', '\\mu': 'μ', '\\pi': 'π', '\\sigma': 'σ', '\\phi': 'φ', '\\omega': 'ω',
  '\\Gamma': 'Γ', '\\Delta': 'Δ', '\\Theta': 'Θ', '\\Lambda': 'Λ', '\\Pi': 'Π', '\\Sigma': 'Σ',
  '\\Phi': 'Φ', '\\Omega': 'Ω', '\\times': '×', '\\cdot': '·', '\\pm': '±', '\\mp': '∓',
  '\\le': '≤', '\\leq': '≤', '\\ge': '≥', '\\geq': '≥', '\\neq': '≠', '\\ne': '≠',
  '\\approx': '≈', '\\infty': '∞', '\\sum': '∑', '\\prod': '∏', '\\int': '∫', '\\partial': '∂',
  '\\nabla': '∇', '\\in': '∈', '\\notin': '∉', '\\subset': '⊂', '\\cup': '∪', '\\cap': '∩',
  '\\to': '→', '\\rightarrow': '→', '\\leftarrow': '←', '\\Rightarrow': '⇒', '\\Leftrightarrow': '⇔',
  '\\ldots': '…', '\\dots': '…', '\\quad': ' ', '\\qquad': '  ', '\\,': ' ',
  '\\circ': '°', '\\degree': '°', '\\log': 'log', '\\ln': 'ln', '\\sin': 'sin', '\\cos': 'cos',
  '\\tan': 'tan', '\\lim': 'lim', '\\max': 'max', '\\min': 'min', '\\exp': 'exp',
  '\\mathbb{R}': 'ℝ', '\\mathbb{N}': 'ℕ', '\\mathbb{Z}': 'ℤ', '\\mathbb{Q}': 'ℚ', '\\mathbb{C}': 'ℂ'
};

const SUPERSCRIPTS: Record<string, string> = {
  '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴', '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹',
  'n': 'ⁿ', 'i': 'ⁱ', '+': '⁺', '-': '⁻', '=': '⁼', '(': '⁽', ')': '⁾'
};

const SUBSCRIPTS: Record<string, string> = {
  '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄', '5': '₅', '6': '₆', '7': '₇', '8': '₈', '9': '₉',
  'i': 'ᵢ', 'j': 'ⱼ', 'n': 'ₙ', '+': '₊', '-': '₋', '=': '₌', '(': '₍', ')': '₎'
};

function script(value: string, table: Record<string, string>): string | undefined {
  let result = '';
  for (const char of value) {
    const mapped = table[char];
    if (mapped === undefined) return undefined;
    result += mapped;
  }
  return result;
}

function balanced(value: string, start: number): { body: string; end: number } | undefined {
  if (value[start] !== '{') return undefined;
  let depth = 1;
  for (let index = start + 1; index < value.length; index += 1) {
    if (value[index] === '{') depth += 1;
    else if (value[index] === '}') {
      depth -= 1;
      if (depth === 0) return { body: value.slice(start + 1, index), end: index + 1 };
    }
  }
  return undefined;
}

/** Reader-sized math: commands become Unicode, not a fake TeX layout engine. */
export function mathText(latex: string): string {
  let value = latex.trim();
  value = value.replace(/\\[dt]?frac\{([^{}]*)\}\{([^{}]*)\}/g, '($1)/($2)');
  value = value.replace(/\\sqrt(?:\[([^\]]*)\])?\{([^{}]*)\}/g,
    (match: string, index: string | undefined, body: string): string => {
      if (!index) return '√(' + body + ')';
      const power = script(index, SUPERSCRIPTS);
      return power === undefined ? '(' + index + ')√(' + body + ')' : power + '√(' + body + ')';
    });
  value = value.replace(/\^\\circ/g, '°');
  value = value.replace(/\\text\{([^{}]*)\}/g, '$1');
  value = value.replace(/\\mathrm\{([^{}]*)\}/g, '$1');
  value = value.replace(/\\mathbf\{([^{}]*)\}/g, '$1');
  for (const command of Object.keys(MATH_COMMANDS)) {
    value = value.split(command).join(MATH_COMMANDS[command]);
    if (command.endsWith('m') || command.endsWith('a')) value = value.split(command + ' ').join(MATH_COMMANDS[command]);
  }
  value = value.replace(/\^\{([^{}]*)\}|\^([A-Za-z0-9+\-=()])/g,
    (match: string, group: string | undefined, single: string | undefined): string => {
      const body = script(group === undefined ? (single || '') : group, SUPERSCRIPTS);
      return body === undefined ? match : body;
    });
  value = value.replace(/_\{([^{}]*)\}|_([A-Za-z0-9+\-=()])/g,
    (match: string, group: string | undefined, single: string | undefined): string => {
      const body = script(group === undefined ? (single || '') : group, SUBSCRIPTS);
      return body === undefined ? match : body;
    });
  value = value.replace(/[{}]/g, '');
  value = value.replace(/\\left|\\right/g, '');
  value = value.replace(/\\[a-zA-Z]+/g, '');
  return value.replace(/\s+/g, ' ').trim();
}

/** Workspace-relative path guard used by file links and image sources. */
export function workspacePath(value: string): string {
  const path = value.trim().replace(/\\/g, '/');
  if (!path || path.length > 2048 || path.startsWith('/') || /^[a-z]+:/i.test(path) ||
    path.split('/').some((part: string) => part === '..' || part === '.')) {
    throw new Error('工作区路径无效');
  }
  return path;
}

export function imageSource(value: string): string {
  return /^(https?:\/\/|data:image\/)/i.test(value) ? value : '';
}

export interface CodeToken {
  kind: string;
  text: string;
}

const KEYWORDS: Record<string, string> = {
  ts: 'const let var function return if else for while do switch case break continue class extends implements interface type enum import export from default new this super async await try catch finally throw typeof instanceof in of as public private protected static readonly void null undefined true false',
  js: 'const let var function return if else for while do switch case break continue class extends new this super async await try catch finally throw typeof instanceof in of as void null undefined true false',
  py: 'def return if elif else for while break continue class import from as try except finally raise with lambda pass yield async await in is not and or None True False',
  go: 'func var const type struct interface return if else for range switch case break continue go defer map chan package import select nil true false',
  rs: 'fn let mut const struct enum impl trait return if else for while loop match break continue use mod pub crate self super unsafe async await move ref where dyn true false',
  java: 'class interface enum extends implements public private protected static final void return if else for while switch case break continue new this super try catch finally throw import package null true false',
  kt: 'fun val var class interface object companion data enum return if else for while when break continue new this super try catch finally throw import package null true false',
  swift: 'func let var class struct enum protocol extension return if else for while switch case break continue import guard defer throw try catch nil true false',
  c: 'int char float double void long short unsigned signed struct enum union typedef const static extern return if else for while switch case break continue sizeof NULL true false',
  sql: 'select from where insert into update delete create table drop alter join left right inner outer on group by order having limit offset union distinct as and or not null is in values set primary key foreign references',
  sh: 'if then else elif fi for while do done case esac function return export local in'
};

function languageFamily(language: string): string {
  const value = language.toLowerCase();
  if (['ts', 'tsx', 'typescript', 'ets'].includes(value)) return 'ts';
  if (['js', 'jsx', 'javascript', 'mjs'].includes(value)) return 'js';
  if (['py', 'python'].includes(value)) return 'py';
  if (value === 'go') return 'go';
  if (['rs', 'rust'].includes(value)) return 'rs';
  if (['java', 'kt', 'kotlin', 'swift'].includes(value)) return value === 'swift' ? 'swift' : 'java';
  if (['c', 'h', 'cpp', 'hpp', 'cc', 'cxx'].includes(value)) return 'c';
  if (['sql'].includes(value)) return 'sql';
  if (['sh', 'bash', 'zsh', 'shell'].includes(value)) return 'sh';
  return '';
}

function hashComment(family: string): boolean { return family === 'py' || family === 'sh'; }

/** Lightweight tokenizer: enough for readable colours without a new dependency. */
export function codeTokens(code: string, language: string): CodeToken[][] {
  const family = languageFamily(language);
  const keywords = new Set((KEYWORDS[family] || '').split(' ').filter((word: string) => !!word));
  const lines: CodeToken[][] = [];
  for (const line of code.split('\n')) {
    const tokens: CodeToken[] = [];
    let plain = '';
    const flush = (): void => { if (plain) { tokens.push({ kind: 'plain', text: plain }); plain = ''; } };
    let index = 0;
    while (index < line.length) {
      const char = line[index];
      if ((family && (line.startsWith('//', index) || (hashComment(family) && char === '#')) ||
        (family === 'sql' && line.startsWith('--', index)))) {
        flush(); tokens.push({ kind: 'comment', text: line.slice(index) }); index = line.length; continue;
      }
      if (family && line.startsWith('/*', index)) {
        const close = line.indexOf('*/', index + 2);
        flush();
        tokens.push({ kind: 'comment', text: line.slice(index, close < 0 ? line.length : close + 2) });
        index = close < 0 ? line.length : close + 2; continue;
      }
      if (char === '"' || char === '\'' || char === '`') {
        let end = index + 1;
        while (end < line.length && line[end] !== char) {
          if (line[end] === '\\') end += 1;
          end += 1;
        }
        flush(); tokens.push({ kind: 'string', text: line.slice(index, Math.min(end + 1, line.length)) });
        index = end + 1; continue;
      }
      if (/[0-9]/.test(char) && (index === 0 || !/[A-Za-z_$]/.test(line[index - 1]))) {
        let end = index + 1;
        while (end < line.length && /[0-9a-fA-FxX._]/.test(line[end])) end += 1;
        flush(); tokens.push({ kind: 'number', text: line.slice(index, end) }); index = end; continue;
      }
      if (/[A-Za-z_$]/.test(char)) {
        let end = index + 1;
        while (end < line.length && /[A-Za-z0-9_$]/.test(line[end])) end += 1;
        const word = line.slice(index, end);
        if (keywords.has(word)) { flush(); tokens.push({ kind: 'keyword', text: word }); }
        else plain += word;
        index = end; continue;
      }
      plain += char;
      index += 1;
    }
    flush();
    lines.push(tokens.length ? tokens : [{ kind: 'plain', text: '' }]);
  }
  return lines;
}
