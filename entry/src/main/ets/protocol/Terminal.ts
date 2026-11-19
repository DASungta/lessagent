export interface TerminalAccess { canRead: boolean; canOperate: boolean; }

// Unknown scopes defer to server authorization; an explicit denial never does.
export function terminalAccess(read: boolean | undefined, operate: boolean | undefined): TerminalAccess {
  return { canRead: read !== false, canOperate: operate !== false };
}

export interface TerminalSize { cols: number; rows: number; }
export interface TerminalSnapshot {
  history: string;
  status: string;
  error: string;
  sequence: number;
  size: TerminalSize | undefined;
}

export function terminalSnapshot(value: Record<string, Object>, threadId: string, terminalId: string): TerminalSnapshot {
  if (value.threadId !== threadId || value.terminalId !== terminalId) throw new Error('终端身份不匹配');
  if (typeof value.history !== 'string' || typeof value.status !== 'string' ||
    !['starting', 'running', 'exited', 'error'].includes(value.status)) throw new Error('终端快照无效');
  let error = '';
  if (value.error !== undefined && value.error !== null) {
    if (typeof value.error !== 'string') throw new Error('终端错误信息无效');
    error = value.error;
  }
  let sequence = -1;
  if (value.sequence !== undefined && value.sequence !== null) {
    if (typeof value.sequence !== 'number' || !Number.isSafeInteger(value.sequence) || value.sequence < 0) {
      throw new Error('终端序列无效');
    }
    sequence = value.sequence;
  }
  let size: TerminalSize | undefined = undefined;
  if (value.cols !== undefined || value.rows !== undefined) {
    if (typeof value.cols !== 'number' || typeof value.rows !== 'number') throw new Error('终端尺寸无效');
    size = terminalSize(value.cols, value.rows);
  }
  return { history: value.history, status: value.status, error, sequence, size };
}

export interface TerminalSessionSummary {
  terminalId: string;
  label: string;
  cwd: string;
  status: string;
  hasRunningSubprocess: boolean;
}
export interface TerminalSessions { loaded: boolean; terminals: TerminalSessionSummary[]; }

function terminalSessionId(value: Object): string {
  if (typeof value !== 'string' || !value.trim() || value.length > 128 || /[\u0000-\u001f\u007f]/.test(value)) {
    throw new Error('终端标识无效');
  }
  return value;
}
function terminalSummary(value: Object, threadId: string): TerminalSessionSummary | undefined {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('终端列表记录无效');
  const row = value as Record<string, Object>;
  if (row.threadId !== threadId) return undefined;
  const terminalId = terminalSessionId(row.terminalId);
  if (typeof row.status !== 'string' || !['starting', 'running', 'exited', 'error'].includes(row.status) ||
    typeof row.label !== 'string' || row.label.length > 128 || typeof row.cwd !== 'string' || !row.cwd ||
    typeof row.hasRunningSubprocess !== 'boolean') throw new Error('终端列表状态无效');
  return { terminalId, label: row.label.trim() || terminalId, cwd: row.cwd,
    status: row.status, hasRunningSubprocess: row.hasRunningSubprocess };
}
export function terminalSessions(current: TerminalSessions, value: Object, threadId: string): TerminalSessions {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('终端列表事件无效');
  const event = value as Record<string, Object>;
  if (event.type === 'snapshot') {
    if (!Array.isArray(event.terminals)) throw new Error('终端列表快照无效');
    const terminals: TerminalSessionSummary[] = [];
    for (const value of event.terminals as Object[]) {
      const terminal = terminalSummary(value, threadId);
      if (!terminal) continue;
      if (terminals.some((item: TerminalSessionSummary): boolean => item.terminalId === terminal.terminalId)) {
        throw new Error('终端列表包含重复标识');
      }
      terminals.push(terminal);
    }
    return { loaded: true, terminals };
  }
  if (event.type !== 'upsert' && event.type !== 'remove') throw new Error('终端列表事件类型无效');
  if (!current.loaded) throw new Error('尚未收到终端列表快照');
  if (event.type === 'remove') {
    if (event.threadId !== threadId) return current;
    const id = terminalSessionId(event.terminalId);
    return { loaded: true, terminals: current.terminals.filter((item: TerminalSessionSummary): boolean => item.terminalId !== id) };
  }
  const terminal = terminalSummary(event.terminal, threadId);
  if (!terminal) return current;
  const terminals = current.terminals.slice();
  const index = terminals.findIndex((item: TerminalSessionSummary): boolean => item.terminalId === terminal.terminalId);
  if (index < 0) terminals.push(terminal); else terminals[index] = terminal;
  return { loaded: true, terminals };
}
export function newTerminalId(existing: string[], uuid: string): string {
  if (!/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(uuid)) throw new Error('终端随机标识无效');
  let index = 1;
  while (existing.some((id: string): boolean => id === 'term-' + index || id.startsWith('term-' + index + '-'))) index++;
  return 'term-' + index + '-' + uuid;
}

export interface TerminalCell {
  char: string; color: string; background: string; bold: boolean; dim: boolean; underline: boolean; hidden: boolean;
}
interface TerminalCursor {
  x: number; y: number; color: string; background: string;
  bold: boolean; dim: boolean; underline: boolean; inverse: boolean; hidden: boolean;
  origin: boolean; autoWrap: boolean; g0: boolean; g1: boolean; useG1: boolean;
}
export interface TerminalView {
  rows: TerminalCell[][]; offset: number; maxOffset: number; cursorRow: number; endLine: number;
}
interface TerminalHistoryRow { cells: TerminalCell[]; wrapped: number; textLength: number; }
export const TERMINAL_MAX_HISTORY_ROWS = 500;
export const TERMINAL_MAX_HISTORY_CELLS = 64000;
export const TERMINAL_MAX_HISTORY_CHARS = 256 * 1024;
export const TERMINAL_MAX_COPY_CHARS = 256 * 1024;
export const TERMINAL_MAX_CELL_CHARS = 128;
export const TERMINAL_MAX_FEED_CHARS = 1024 * 1024;
const BRIGHT_COLORS: string[] = ['#686868', '#ff8b92', '#ddffa7', '#ffe585', '#9cc4ff', '#e1acff', '#a3f7ff', '#ffffff'];
const COLORS: string[] = ['#16181d', '#f07178', '#c3e88d', '#ffcb6b', '#82aaff', '#c792ea', '#89ddff', '#eeeeee'];

export const DEFAULT_TERMINAL_FONT_SIZE = 14;
export const MIN_TERMINAL_FONT_SIZE = 10;
export const MAX_TERMINAL_FONT_SIZE = 24;

export function validTerminalFontSize(value: Object | undefined): boolean {
  return typeof value === 'number' && Number.isInteger(value) &&
    value >= MIN_TERMINAL_FONT_SIZE && value <= MAX_TERMINAL_FONT_SIZE;
}

export function terminalCanvasSize(width: number, height: number, cellWidth: number, cellHeight: number): TerminalSize {
  if (![width, height, cellWidth, cellHeight].every(value => Number.isFinite(value) && value > 0)) return { cols: 0, rows: 0 };
  return { cols: Math.min(240, Math.floor(width / cellWidth)), rows: Math.min(100, Math.floor(height / cellHeight)) };
}

export function terminalFitSize(visible: TerminalSize): TerminalSize | undefined {
  if (visible.cols < 20 || visible.rows < 5) return undefined;
  return { cols: Math.min(160, visible.cols), rows: visible.rows };
}

export function terminalSize(cols: number, rows: number): TerminalSize {
  if (!Number.isInteger(cols) || cols < 1 || cols > 1000 || !Number.isInteger(rows) || rows < 1 || rows > 500) {
    throw new Error('终端尺寸无效');
  }
  return { cols, rows };
}
export function terminalInput(threadId: string, terminalId: string, data: string): Object {
  if (!threadId.trim() || !terminalId.trim() || terminalId.length > 128 || !data || data.length > 65536) {
    throw new Error('终端输入无效或超过 65536 字符');
  }
  return { threadId, terminalId, data };
}


// shortcut: bounded full-screen scrollback without reflow, use native Ghostty for complete terminal equivalence.
export class TerminalGrid {
  cols: number;
  rows: number;
  cells: TerminalCell[][] = [];
  x: number = 0;
  y: number = 0;
  unsupported: boolean = false;
  cursorVisible: boolean = true;
  applicationCursor: boolean = false;
  bracketedPaste: boolean = false;
  alternate: boolean = false;
  title: string = '';
  historyTruncated: boolean = false;
  scrollCount: number = 0;
  private history: TerminalHistoryRow[] = [];
  private historyCells: number = 0;
  private historyChars: number = 0;
  private wrapped: number[] = [];
  private normalWrapped: number[] | undefined = undefined;
  private mode: string = '';
  private control: string = '';
  private stringKind: string = '';
  private foreground: string = '#eeeeee';
  private background: string = '#16181d';
  private bold: boolean = false;
  private dim: boolean = false;
  private underline: boolean = false;
  private inverse: boolean = false;
  private hidden: boolean = false;
  private saved: TerminalCursor | undefined = undefined;
  private normalCursor: TerminalCursor | undefined = undefined;
  private normalCells: TerminalCell[][] | undefined = undefined;
  private scrollTop: number = 0;
  private scrollBottom: number = 0;
  private normalTop: number = 0;
  private normalBottom: number = 0;
  private origin: boolean = false;
  private autoWrap: boolean = true;
  private insertMode: boolean = false;
  private pendingWrap: boolean = false;
  private charsetTarget: string = '';
  private g0: boolean = false;
  private g1: boolean = false;
  private useG1: boolean = false;
  private pendingSurrogate: string = '';
  private replies: string[] = [];
  private answerQueries: boolean = true;
  private workRemaining: number = 2000000;
  constructor(cols: number = 80, rows: number = 24) {
    this.checkSize(cols, rows); this.cols = cols; this.rows = rows; this.scrollBottom = rows - 1; this.clear();
  }
  private checkSize(cols: number, rows: number): void {
    terminalSize(cols, rows);
    if (cols > 240 || rows > 100) throw new Error('当前原生终端支持至 240 × 100，请在其他端缩小尺寸后重连');
  }
  private blank(): TerminalCell {
    return { char: ' ', color: this.foreground, background: this.background, bold: false, dim: false, underline: false, hidden: false };
  }
  private charge(count: number): void {
    this.workRemaining -= count;
    if (this.workRemaining < 0) throw new Error('终端输出渲染量超过安全上限，请重新连接后核对');
  }
  private line(): TerminalCell[] {
    this.charge(this.cols);
    const result: TerminalCell[] = [];
    for (let x = 0; x < this.cols; x++) result.push(this.blank());
    return result;
  }
  clear(): void { this.clearScreen(); this.x = 0; this.y = 0; this.pendingWrap = false; }
  private clearScreen(): void {
    const cells: TerminalCell[][] = [];
    for (let y = 0; y < this.rows; y++) cells.push(this.line());
    this.cells = cells; this.wrapped = cells.map((): number => 0);
  }
  private resetStyle(): void {
    this.foreground = '#eeeeee'; this.background = '#16181d';
    this.bold = false; this.dim = false; this.underline = false; this.inverse = false; this.hidden = false;
  }
  private resetMargins(): void {
    this.scrollTop = 0;
    this.scrollBottom = this.rows - 1;
    this.pendingWrap = false;
  }
  reset(keepWork: boolean = false): void {
    if (!keepWork) this.workRemaining = 2000000;
    this.mode = ''; this.control = ''; this.pendingSurrogate = ''; this.replies = []; this.resetStyle();
    this.clearHistory(); this.scrollCount = 0; this.normalWrapped = undefined;
    this.unsupported = false; this.alternate = false; this.normalCells = undefined; this.normalCursor = undefined;
    this.saved = undefined; this.cursorVisible = true; this.applicationCursor = false; this.bracketedPaste = false;
    this.resetMargins(); this.origin = false; this.autoWrap = true;
    this.insertMode = false; this.g0 = false; this.g1 = false; this.useG1 = false; this.title = ''; this.clear();
  }
  private resized(cells: TerminalCell[][], cols: number, rows: number): TerminalCell[][] {
    const result: TerminalCell[][] = [];
    for (let y = 0; y < rows; y++) {
      const row: TerminalCell[] = [];
      for (let x = 0; x < cols; x++) row.push(cells[y]?.[x] || this.blank());
      if (row.length && row[row.length - 1].char && this.charWidth(row[row.length - 1].char.codePointAt(0) || 0) === 2) row[row.length - 1] = this.blank();
      result.push(row);
    }
    return result;
  }
  resize(cols: number, rows: number): void {
    this.checkSize(cols, rows);
    if (cols === this.cols && rows === this.rows) return;
    this.workRemaining = 2000000;
    const oldCols = this.cols;
    this.cells = this.resized(this.cells, cols, rows);
    this.wrapped = this.cells.map((_, index: number): number => cols === oldCols ? this.wrapped[index] || 0 : 0);
    if (this.normalWrapped) {
      const oldWrapped = this.normalWrapped;
      this.normalWrapped = this.cells.map((_, index: number): number => cols === oldCols ? oldWrapped[index] || 0 : 0);
    }
    if (cols !== oldCols && this.history.length) this.history[this.history.length - 1].wrapped = 0;
    if (this.normalCells) this.normalCells = this.resized(this.normalCells, cols, rows);
    this.cols = cols; this.rows = rows;
    this.x = Math.min(this.x, cols - 1); this.y = Math.min(this.y, rows - 1);
    this.resetMargins(); this.normalTop = 0; this.normalBottom = rows - 1;
  }
  private capture(): TerminalCursor {
    return { x: this.x, y: this.y, color: this.foreground, background: this.background,
      bold: this.bold, dim: this.dim, underline: this.underline, inverse: this.inverse, hidden: this.hidden,
      origin: this.origin, autoWrap: this.autoWrap, g0: this.g0, g1: this.g1, useG1: this.useG1 };
  }
  private restore(cursor: TerminalCursor | undefined): void {
    if (!cursor) return;
    this.x = Math.min(cursor.x, this.cols - 1); this.y = Math.min(cursor.y, this.rows - 1);
    this.foreground = cursor.color; this.background = cursor.background;
    this.bold = cursor.bold; this.dim = cursor.dim; this.underline = cursor.underline;
    this.inverse = cursor.inverse; this.hidden = cursor.hidden; this.origin = cursor.origin; this.autoWrap = cursor.autoWrap;
    this.g0 = cursor.g0; this.g1 = cursor.g1; this.useG1 = cursor.useG1; this.pendingWrap = false;
  }
  private alternateScreen(enabled: boolean): void {
    if (this.alternate === enabled) return;
    if (enabled) {
      this.normalCells = this.cells; this.normalCursor = this.capture(); this.normalWrapped = this.wrapped;
      this.normalTop = this.scrollTop; this.normalBottom = this.scrollBottom;
      this.clear(); this.resetMargins();
    } else {
      if (this.normalCells) this.cells = this.normalCells;
      if (this.normalWrapped) this.wrapped = this.normalWrapped;
      this.restore(this.normalCursor); this.scrollTop = this.normalTop; this.scrollBottom = this.normalBottom;
      this.normalCells = undefined; this.normalCursor = undefined; this.normalWrapped = undefined;
    }
    this.alternate = enabled; this.pendingWrap = false;
  }
  get historyLength(): number { return this.alternate ? 0 : this.history.length; }
  private clearHistory(): void {
    this.history = []; this.historyCells = 0; this.historyChars = 0; this.historyTruncated = false;
  }
  private retainHistory(cells: TerminalCell[], wrapped: number): void {
    this.charge(cells.length);
    const saved: TerminalCell[] = cells.map((cell: TerminalCell): TerminalCell => ({ char: cell.char,
      color: cell.color, background: cell.background, bold: cell.bold, dim: cell.dim,
      underline: cell.underline, hidden: cell.hidden }));
    const textLength = saved.reduce((total: number, cell: TerminalCell): number => total + cell.char.length, 0);
    this.history.push({ cells: saved, wrapped, textLength }); this.scrollCount++;
    this.historyCells += saved.length; this.historyChars += textLength;
    while (this.history.length > TERMINAL_MAX_HISTORY_ROWS || this.historyCells > TERMINAL_MAX_HISTORY_CELLS ||
      this.historyChars > TERMINAL_MAX_HISTORY_CHARS) {
      const first = this.history.shift();
      if (first) { this.historyCells -= first.cells.length; this.historyChars -= first.textLength; }
      this.historyTruncated = true;
    }
  }
  private viewEnd(count: number): number {
    let end = Math.max(Math.min(count, this.rows), this.y + 1);
    for (let row = this.rows - 1; row >= end; row--) {
      if (this.cells[row].some((cell: TerminalCell): boolean =>
        cell.char !== ' ' && cell.char !== '' || cell.background !== '#16181d' || cell.underline)) return row + 1;
    }
    return end;
  }
  view(offset: number = 0, count: number = this.rows): TerminalView {
    if (!Number.isFinite(offset) || !Number.isInteger(count) || count < 1 || count > 100) {
      throw new Error('终端查看范围无效');
    }
    const end = this.viewEnd(count); const total = this.historyLength + end;
    const maxOffset = Math.max(0, total - count);
    const actual = Math.min(maxOffset, Math.max(0, Math.floor(offset)));
    const start = Math.max(0, total - count - actual); const last = Math.min(total, start + count);
    const rows: TerminalCell[][] = [];
    for (let index = start; index < last; index++) {
      rows.push(index < this.historyLength ? this.history[index].cells : this.cells[index - this.historyLength]);
    }
    const cursor = this.historyLength + this.y - start;
    return { rows, offset: actual, maxOffset, cursorRow: cursor >= 0 && cursor < rows.length ? cursor : -1,
      endLine: (this.alternate ? 0 : this.scrollCount) + end };
  }
  viewText(offset: number = 0, count: number = this.rows, maxColumns: number = 240): string {
    if (!Number.isInteger(maxColumns) || maxColumns < 0 || maxColumns > 240) throw new Error('终端列范围无效');
    const view = this.view(offset, count);
    const start = Math.max(0, this.historyLength + this.viewEnd(count) - count - view.offset);
    let result = '';
    for (let index = 0; index < view.rows.length; index++) {
      const position = start + index;
      const wrapped = position < this.historyLength ? this.history[position].wrapped : this.wrapped[position - this.historyLength];
      const row = view.rows[index];
      let line = '';
      const columns = Math.min(maxColumns, wrapped || row.length, row.length);
      const joinsNext = wrapped > 0 && wrapped <= columns;
      for (let x = 0; x < columns; x++) {
        const cell = row[x];
        if (cell.char === '') { if (cell.hidden) line += ' '; continue; }
        line += cell.hidden ? ' ' : cell.char;
      }
      // Soft wraps join unchanged; explicit line endings discard only terminal padding.
      if (!joinsNext) line = line.replace(/ +$/, '');
      if (result.length + line.length + 1 > TERMINAL_MAX_COPY_CHARS) throw new Error('复制内容超过 256 Ki 字符，请缩小查看范围');
      result += line;
      if (index < view.rows.length - 1 && !joinsNext) result += '\n';
    }
    return result;
  }
  private scroll(up: boolean, count: number = 1): void {
    const n = Math.min(count, this.scrollBottom - this.scrollTop + 1);
    for (let i = 0; i < n; i++) {
      const row = this.line();
      if (up && !this.alternate && this.scrollTop === 0 && this.scrollBottom === this.rows - 1) {
        this.retainHistory(this.cells[0], this.wrapped[0] || 0);
      }
      this.cells.splice(up ? this.scrollTop : this.scrollBottom, 1);
      this.wrapped.splice(up ? this.scrollTop : this.scrollBottom, 1);
      this.cells.splice(up ? this.scrollBottom : this.scrollTop, 0, row);
      this.wrapped.splice(up ? this.scrollBottom : this.scrollTop, 0, 0);
    }
  }
  private down(softWrap: number = 0): void {
    if (this.y === this.scrollBottom) {
      this.wrapped[this.y] = softWrap;
      this.scroll(true);
    } else if (this.y < this.rows - 1) {
      this.wrapped[this.y] = softWrap;
      this.y++;
    }
    this.pendingWrap = false;
  }
  private reverseIndex(): void {
    if (this.y === this.scrollTop) this.scroll(false);
    else this.y = Math.max(0, this.y - 1);
    this.pendingWrap = false;
  }
  private charWidth(code: number): number {
    return code >= 0x1100 && (code <= 0x115f || code >= 0x2e80 && code <= 0xa4cf ||
      code >= 0xac00 && code <= 0xd7a3 || code >= 0xf900 && code <= 0xfaff || code >= 0xff01 && code <= 0xff60 ||
      code >= 0x1f300 && code <= 0x1faff || code >= 0x20000 && code <= 0x3ffff) ? 2 : 1;
  }
  private eraseCell(x: number): void {
    const row = this.cells[this.y];
    if (row[x].char === '' && x > 0) row[x - 1] = this.blank();
    if (x + 1 < this.cols && row[x + 1].char === '') row[x + 1] = this.blank();
    row[x] = this.blank();
  }
  private put(char: string, code: number): void {
    this.charge(this.insertMode ? this.cols : 1);
    if (code >= 0x300 && code <= 0x36f) {
      let x = this.pendingWrap ? this.x : this.x - 1;
      if (x >= 0 && this.cells[this.y][x].char === '') x--;
      if (x >= 0) {
        const cell = this.cells[this.y][x];
        if (cell.char.length + char.length <= TERMINAL_MAX_CELL_CHARS) cell.char += char;
        else this.unsupported = true;
      }
      return;
    }
    if (code === 0x200d || code >= 0xfe00 && code <= 0xfe0f) { this.unsupported = true; return; }
    const width = this.charWidth(code);
    if (this.pendingWrap || width === 2 && this.x === this.cols - 1) {
      if (this.autoWrap) { const wrapColumn = this.pendingWrap ? this.cols : this.x; this.x = 0; this.down(wrapColumn); }
      this.pendingWrap = false;
    }
    if (width > this.cols || width === 2 && this.x === this.cols - 1) { this.unsupported = true; return; }
    if (this.useG1 ? this.g1 : this.g0) {
      const from = '`abcdefghijklmnopqrstuvwxyz{|}~';
      const to = '◆▒␉␌␍␊°±␤␋┘┐┌└┼⎺⎻─⎼⎽├┤┴┬│≤≥π≠£·';
      const index = from.indexOf(char); if (index >= 0) char = to[index];
    }
    if (this.insertMode) {
      for (let i = 0; i < width; i++) this.cells[this.y].splice(this.x, 0, this.blank());
      this.cells[this.y].length = this.cols;
    }
    this.eraseCell(this.x);
    if (width === 2) this.eraseCell(this.x + 1);
    const cell: TerminalCell = { char, color: this.inverse ? this.background : this.foreground,
      background: this.inverse ? this.foreground : this.background, bold: this.bold, dim: this.dim,
      underline: this.underline, hidden: this.hidden };
    this.cells[this.y][this.x] = cell;
    if (width === 2) this.cells[this.y][this.x + 1] = { char: '', color: cell.color,
      background: cell.background, bold: cell.bold, dim: cell.dim, underline: cell.underline, hidden: cell.hidden };
    // Repainting the deferred-wrap padding makes it part of the visible line.
    if (this.wrapped[this.y] > 0) this.wrapped[this.y] = Math.max(this.wrapped[this.y], this.x + width);
    this.x += width;
    if (this.x >= this.cols) { this.x = this.cols - 1; this.pendingWrap = this.autoWrap; }
  }
  feed(data: string, answerQueries: boolean = true): void {
    this.answerQueries = answerQueries;
    this.workRemaining = 2000000;
    if (data.length > TERMINAL_MAX_FEED_CHARS) throw new Error('终端输出超过安全上限，请缩短历史后重连');
    data = this.pendingSurrogate + data; this.pendingSurrogate = '';
    if (data.length && data.charCodeAt(data.length - 1) >= 0xd800 && data.charCodeAt(data.length - 1) <= 0xdbff) {
      this.pendingSurrogate = data.slice(-1); data = data.slice(0, -1);
    }
    for (let i = 0; i < data.length; i++) {
      let char = data[i]; const code = data.codePointAt(i) || 0;
      if (code > 0xffff) { char = data.slice(i, i + 2); i++; }
      if (char === '\x18' || char === '\x1a') { this.mode = ''; this.control = ''; continue; }
      if (this.mode === 'string' || this.mode === 'stringEscape') {
        if (char === '\x07' && this.stringKind === 'osc' || this.mode === 'stringEscape' && char === '\\') {
          this.finishString(); this.mode = ''; this.control = '';
        } else {
          this.mode = char === '\x1b' ? 'stringEscape' : 'string';
          if (this.control.length < 256 && char !== '\x1b') this.control += char;
        }
        continue;
      }
      if (char === '\x1b') { this.mode = 'escape'; this.control = ''; continue; }
      if (char === '\r') { this.x = 0; this.pendingWrap = false; continue; }
      if (char === '\n' || char === '\v' || char === '\f') { this.down(); continue; }
      if (char === '\b') { this.x = Math.max(0, this.x - 1); this.pendingWrap = false; continue; }
      if (char === '\t') { this.x = Math.min(this.cols - 1, (Math.floor(this.x / 8) + 1) * 8); this.pendingWrap = false; continue; }
      if (char === '\x0e') { this.useG1 = true; continue; }
      if (char === '\x0f') { this.useG1 = false; continue; }
      if (code < 32 || code === 127) continue;
      if (this.mode === 'escape') { this.escape(char); continue; }
      if (this.mode === 'charset') {
        if (char !== 'B' && char !== '0') this.unsupported = true;
        else if (this.charsetTarget === '(') this.g0 = char === '0'; else this.g1 = char === '0';
        this.mode = ''; continue;
      }
      if (this.mode === 'csi' || this.mode === 'csiDiscard') {
        if (code >= 0x40 && code <= 0x7e) {
          if (this.mode === 'csi') this.csi(char);
          this.control = ''; this.mode = '';
        } else if (this.control.length < 128 && this.mode === 'csi') this.control += char;
        else { this.mode = 'csiDiscard'; this.unsupported = true; }
        continue;
      }
      this.put(char, code);
    }
  }
  private finishString(): void {
    if (this.stringKind !== 'osc') { this.unsupported = true; return; }
    const separator = this.control.indexOf(';');
    const command = this.control.slice(0, separator < 0 ? this.control.length : separator);
    if (command === '0' || command === '1' || command === '2') this.title = this.control.slice(separator + 1);
    // These metadata-only sequences do not affect the grid or execute clipboard/file operations.
    else if (!['7', '8', '133'].includes(command)) this.unsupported = true;
  }
  private escape(char: string): void {
    this.mode = '';
    if (char === '[') this.mode = 'csi';
    else if (char === ']' || char === 'P' || char === '_' || char === '^' || char === 'X') {
      this.mode = 'string'; this.stringKind = char === ']' ? 'osc' : 'unsupported';
    } else if (char === '(' || char === ')') { this.mode = 'charset'; this.charsetTarget = char; }
    else if (char === 'c') this.reset(true);
    else if (char === '7') this.saved = this.capture();
    else if (char === '8') this.restore(this.saved);
    else if (char === 'D') this.down();
    else if (char === 'E') { this.x = 0; this.down(); }
    else if (char === 'M') this.reverseIndex();
    else if (char !== '=' && char !== '>') this.unsupported = true;
  }
  private privateMode(args: number[], enabled: boolean): void {
    for (const value of args) {
      if (value === 1) this.applicationCursor = enabled;
      else if (value === 6) { this.origin = enabled; this.y = enabled ? this.scrollTop : 0; this.x = 0; }
      else if (value === 7) this.autoWrap = enabled;
      else if (value === 25) this.cursorVisible = enabled;
      else if (value === 1049) this.alternateScreen(enabled);
      else if (value === 1048) { if (enabled) this.saved = this.capture(); else this.restore(this.saved); }
      else if (value === 2004) this.bracketedPaste = enabled;
      else if (value !== 12) this.unsupported = true;
    }
  }
  takeReplies(): string[] { const result = this.replies; this.replies = []; return result; }
  private reply(value: string): void {
    if (!this.answerQueries) return;
    if (this.replies.length >= 16) throw new Error('终端查询过于频繁，请重新连接后核对');
    this.replies.push(value);
  }
  private csi(final: string): void {
    this.charge(['J', 'L', 'M', 'S', 'T'].includes(final) ? this.rows * this.cols : this.cols);
    if (/^[0-6]? $/.test(this.control) && final === 'q') return;
    if (this.control === '!' && final === 'p') {
      this.resetStyle(); this.origin = false; this.autoWrap = true; this.insertMode = false;
      this.resetMargins(); this.cursorVisible = true; return;
    }
    const privateMode = this.control.startsWith('?');
    const parameters = privateMode ? this.control.slice(1) : this.control;
    if (!/^\d*(;\d*)*$/.test(parameters)) { this.unsupported = true; return; }
    const args = parameters.split(';').map((value: string): number => Number(value) || 0);
    if (args.some((value: number): boolean => !Number.isSafeInteger(value) || value < 0)) { this.unsupported = true; return; }
    if (privateMode) {
      if (final === 'h' || final === 'l') this.privateMode(args, final === 'h');
      else if (final === 'n' && args[0] === 6) this.reply('\x1b[?' + (this.y - (this.origin ? this.scrollTop : 0) + 1) + ';' + (this.x + 1) + 'R');
      else this.unsupported = true;
      this.pendingWrap = false; return;
    }
    const n = args[0] || 1;
    const top = this.origin ? this.scrollTop : 0;
    const bottom = this.origin ? this.scrollBottom : this.rows - 1;
    if (final === 'n') {
      if (args[0] === 5) this.reply('\x1b[0n');
      else if (args[0] === 6) this.reply('\x1b[' + (this.y - top + 1) + ';' + (this.x + 1) + 'R');
      else this.unsupported = true;
      return;
    } else if (final === 'c' && args[0] === 0) { this.reply('\x1b[?1;0c'); return; }
    else if (final === 't' && args[0] === 18) { this.reply('\x1b[8;' + this.rows + ';' + this.cols + 't'); return; }
    else if (final === 'A') this.y = Math.max(top, this.y - n);
    else if (final === 'B' || final === 'e') this.y = Math.min(bottom, this.y + n);
    else if (final === 'C' || final === 'a') this.x = Math.min(this.cols - 1, this.x + n);
    else if (final === 'D') this.x = Math.max(0, this.x - n);
    else if (final === 'E' || final === 'F') { this.x = 0; this.y = Math.max(top, Math.min(bottom, this.y + (final === 'E' ? n : -n))); }
    else if (final === 'G' || final === '`') this.x = Math.min(this.cols - 1, n - 1);
    else if (final === 'd') this.y = Math.min(bottom, top + n - 1);
    else if (final === 'H' || final === 'f') { this.y = Math.min(bottom, top + n - 1); this.x = Math.min(this.cols - 1, (args[1] || 1) - 1); }
    else if (final === 's') this.saved = this.capture();
    else if (final === 'u') this.restore(this.saved);
    else if (final === 'r') {
      const start = n - 1; const end = Math.min(args[1] || this.rows, this.rows) - 1;
      if (start < end) { this.scrollTop = start; this.scrollBottom = end; this.x = 0; this.y = this.origin ? start : 0; }
    } else if (final === 'S' || final === 'T') this.scroll(final === 'S', n);
    else if (final === 'L' || final === 'M') {
      if (this.y >= this.scrollTop && this.y <= this.scrollBottom) {
        const count = Math.min(n, this.scrollBottom - this.y + 1);
        for (let i = 0; i < count; i++) {
          const row = this.line();
          this.cells.splice(final === 'L' ? this.scrollBottom : this.y, 1);
          this.wrapped.splice(final === 'L' ? this.scrollBottom : this.y, 1);
          this.cells.splice(final === 'L' ? this.y : this.scrollBottom, 0, row);
          this.wrapped.splice(final === 'L' ? this.y : this.scrollBottom, 0, 0);
        }
      }
    } else if (final === '@' || final === 'P') {
      const count = Math.min(n, this.cols - this.x);
      for (let i = 0; i < count; i++) {
        if (final === '@') { this.cells[this.y].splice(this.x, 0, this.blank()); this.cells[this.y].pop(); }
        else { this.cells[this.y].splice(this.x, 1); this.cells[this.y].push(this.blank()); }
      }
    } else if (final === 'X') {
      for (let x = this.x; x < Math.min(this.cols, this.x + n); x++) this.eraseCell(x);
    } else if (final === 'J') {
      if (args[0] === 2) this.clearScreen();
      else if (args[0] === 0 || args[0] === 1) {
        for (let y = 0; y < this.rows; y++) if (args[0] === 0 ? y >= this.y : y <= this.y) this.wrapped[y] = 0;
        for (let y = 0; y < this.rows; y++) for (let x = 0; x < this.cols; x++) {
          if (args[0] === 0 ? y > this.y || y === this.y && x >= this.x : y < this.y || y === this.y && x <= this.x) this.cells[y][x] = this.blank();
        }
      } else if (args[0] === 3) { if (!this.alternate) this.clearHistory(); }
      else this.unsupported = true;
    } else if (final === 'K') {
      if (args[0] === 0 || args[0] === 2) this.wrapped[this.y] = 0;
      if (args[0] > 2) this.unsupported = true;
      else for (let x = 0; x < this.cols; x++) if (args[0] === 2 || (args[0] === 1 ? x <= this.x : x >= this.x)) this.eraseCell(x);
    } else if (final === 'm') { this.sgr(args); return; }
    else if (final === 'h' || final === 'l') {
      for (const value of args) { if (value === 4) this.insertMode = final === 'h'; else this.unsupported = true; }
    } else this.unsupported = true;
    this.pendingWrap = false;
  }
  private palette(index: number): string {
    if (index < 8) return COLORS[index];
    if (index < 16) return BRIGHT_COLORS[index - 8];
    if (index >= 232) { const value = 8 + (index - 232) * 10; return 'rgb(' + value + ',' + value + ',' + value + ')'; }
    const cube = [0, 95, 135, 175, 215, 255]; const n = index - 16;
    return 'rgb(' + cube[Math.floor(n / 36)] + ',' + cube[Math.floor(n / 6) % 6] + ',' + cube[n % 6] + ')';
  }
  private sgr(args: number[]): void {
    for (let i = 0; i < args.length; i++) {
      const value = args[i];
      if (value === 0) this.resetStyle();
      else if (value === 1) this.bold = true;
      else if (value === 2) this.dim = true;
      else if (value === 4) this.underline = true;
      else if (value === 7) this.inverse = true;
      else if (value === 8) this.hidden = true;
      else if (value === 22) { this.bold = false; this.dim = false; }
      else if (value === 24) this.underline = false;
      else if (value === 27) this.inverse = false;
      else if (value === 28) this.hidden = false;
      else if (value === 39) this.foreground = '#eeeeee';
      else if (value === 49) this.background = '#16181d';
      else if (value >= 30 && value <= 37) this.foreground = COLORS[value - 30];
      else if (value >= 40 && value <= 47) this.background = COLORS[value - 40];
      else if (value >= 90 && value <= 97) this.foreground = BRIGHT_COLORS[value - 90];
      else if (value >= 100 && value <= 107) this.background = BRIGHT_COLORS[value - 100];
      else if (value === 38 || value === 48) {
        const mode = args[i + 1]; const count = mode === 5 ? 1 : mode === 2 ? 3 : 0;
        if (!count || i + count + 1 >= args.length) { this.unsupported = true; return; }
        const channels = args.slice(i + 2, i + 2 + count);
        if (channels.some((channel: number): boolean => channel > 255)) { this.unsupported = true; return; }
        const color = mode === 5 ? this.palette(channels[0]) : 'rgb(' + channels.join(',') + ')';
        if (value === 38) this.foreground = color; else this.background = color;
        i += count + 1;
      } else this.unsupported = true;
    }
  }
  cursorKey(code: 'A' | 'B' | 'C' | 'D'): string { return '\x1b' + (this.applicationCursor ? 'O' : '[') + code; }
}
