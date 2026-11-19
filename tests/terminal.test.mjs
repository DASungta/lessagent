import test from 'node:test';
import assert from 'node:assert/strict';
import { TerminalGrid, terminalInput, terminalSize, terminalAccess, terminalSnapshot, TERMINAL_MAX_FEED_CHARS, TERMINAL_MAX_CELL_CHARS } from '../entry/src/main/ets/protocol/Terminal.ts';
const line = (grid, row = 0) => grid.cells[row].map(cell => cell.char).join('');
test('VT grid handles split ANSI, overwrite, clear and color', () => {
 const g = new TerminalGrid(10, 3); g.feed('hello\rX\x1b['); g.feed('31mR');
 assert.equal(line(g).slice(0, 5), 'XRllo'); assert.equal(g.cells[0][1].color, '#f07178');
 g.feed('\x1b[2;3H中'); assert.equal(g.cells[1][2].char, '中'); assert.equal(g.cells[1][3].char, '');
 g.feed('\x1b[2J'); assert.equal(line(g), '          '); assert.equal(g.y, 1);
});
test('VT grid handles split surrogate, OSC, scroll and bounds', () => {
 const g = new TerminalGrid(5, 2); g.feed('\ud83d'); g.feed('\ude00\x1b]0;hidden\x07A');
 assert.equal(g.cells[0][0].char, '😀'); assert.equal(g.cells[0][2].char, 'A');
 g.feed('\r\n12345\r\nlast'); assert.equal(line(g, 0), '12345');
 g.resize(3, 1); assert.equal(line(g), '123'); assert.equal(g.y, 0);
 g.feed('\x1b[?1049h'); assert.equal(g.alternate, true); assert.equal(g.unsupported, false);
 assert.throws(() => terminalSize(0, 20)); assert.throws(() => terminalInput('t', '', 'ls'));
 assert.throws(() => terminalInput('t', 'term-1', 'a'.repeat(65537)));
});
test('VT grid rejects oversized shared grid and malformed control coordinates', () => {
 const g = new TerminalGrid(5, 2);
 assert.throws(() => g.resize(1000, 500));
 g.feed('\x1b[-2;3HX'); assert.equal(g.unsupported, true); assert.equal(g.cells[0][0].char, 'X');
 g.feed('\x1b[2;5H\x1b[s'); g.resize(2, 1); g.feed('\x1b[uY'); assert.equal(g.cells[0][1].char, 'Y');
});

test('terminal permissions preserve independent explicit denials and defer unknown scopes to server', () => {
  for (const read of [true, false, undefined]) {
    for (const operate of [true, false, undefined]) {
      const access = terminalAccess(read, operate);
      assert.equal(access.canRead, read !== false);
      assert.equal(access.canOperate, operate !== false);
    }
  }
  assert.deepEqual(terminalAccess(true, false), { canRead: true, canOperate: false });
  assert.deepEqual(terminalAccess(false, true), { canRead: false, canOperate: true });
  assert.deepEqual(terminalAccess(undefined, undefined), { canRead: true, canOperate: true });
});

test('real running terminal snapshot accepts omitted optional error/grid/sequence and null error', () => {
  const snapshot = { threadId: 't', terminalId: 'term-1', cwd: '/tmp/test', worktreePath: null,
    status: 'running', pid: 123, history: '\r\n$ ', exitCode: null, exitSignal: null,
    label: 'shell', updatedAt: '2026-11-18T12:00:00Z' };
  const value = terminalSnapshot(snapshot, 't', 'term-1');
  assert.equal(value.error, ''); assert.equal(value.sequence, -1); assert.equal(value.size, undefined);
  assert.equal(value.history, '\r\n$ '); assert.equal(value.status, 'running');
  assert.equal(terminalSnapshot({ ...snapshot, error: null }, 't', 'term-1').error, '');
  assert.deepEqual(terminalSnapshot({ ...snapshot, sequence: 4, cols: 40, rows: 24 }, 't', 'term-1').size,
    { cols: 40, rows: 24 });
  assert.throws(() => terminalSnapshot({ ...snapshot, error: 42 }, 't', 'term-1'));
  assert.throws(() => terminalSnapshot({ ...snapshot, sequence: -2 }, 't', 'term-1'));
  assert.throws(() => terminalSnapshot({ ...snapshot, cols: 40 }, 't', 'term-1'));
  assert.throws(() => terminalSnapshot(snapshot, 'other', 'term-1'));
});

test('common zsh prompt modes update actual state without spurious unsupported flags', () => {
 const g = new TerminalGrid(20, 4);
 g.feed('\x1b[?25l\x1b[1m\x1b[7m%\x1b[27m\x1b[1m\x1b[0m\r \r\x1b[K\x1b]2;shell title\x07\x1b(B\x1b[?2004h$ ');
 assert.equal(line(g).trim(), '$'); assert.equal(g.title, 'shell title');
 assert.equal(g.bracketedPaste, true); assert.equal(g.cursorVisible, false); assert.equal(g.unsupported, false);
 g.feed('\x1b[?1h'); assert.equal(g.cursorKey('A'), '\x1bOA'); assert.equal(g.cursorKey('C'), '\x1bOC');
 g.feed('\x1b[?1l\x1b[?2004l\x1b[?25h'); assert.equal(g.cursorKey('B'), '\x1b[B'); assert.equal(g.cursorKey('D'), '\x1b[D');
 assert.equal(g.bracketedPaste, false); assert.equal(g.cursorVisible, true);
});
test('alternate screen restores normal content, cursor and attributes after resize', () => {
 const g = new TerminalGrid(8, 4); g.feed('shell\x1b[31m');
 g.feed('\x1b[?1049h\x1b[2J\x1b[HTUI\x1b[32m!');
 assert.equal(line(g).trim(), 'TUI!'); assert.equal(g.alternate, true);
 g.resize(6, 3); g.feed('\x1b[?1049lR');
 assert.equal(line(g), 'shellR'); assert.equal(g.cells[0][5].color, '#f07178');
 assert.equal(g.cells.length, 3); assert.equal(g.alternate, false); assert.equal(g.unsupported, false);
 g.feed('\x1b[?1049h'); assert.equal(line(g).trim(), '');
});
test('scroll region, origin, insert/delete lines and reverse index preserve fixed headers', () => {
 const g = new TerminalGrid(4, 5); g.feed('HEAD\r\n1111\r\n2222\r\n3333\r\nFOOT');
 g.feed('\x1b[2;4r\x1b[4;1H\n');
 assert.deepEqual(g.cells.map(row=>row.map(c=>c.char).join('')), ['HEAD','2222','3333','    ','FOOT']);
 g.feed('\x1b[2;1H\x1bM'); assert.equal(line(g,1),'    '); assert.equal(line(g,2),'2222');
 g.feed('\x1b[?6hX'); assert.equal(g.cells[1][0].char,'X');
 g.feed('\x1b[1LY'); assert.equal(g.cells[1][1].char,'Y'); assert.equal(g.cells[2][0].char,'X');
 g.feed('\x1b[1M'); assert.equal(g.cells[1][0].char,'X');
 assert.equal(line(g,0),'HEAD'); assert.equal(line(g,4),'FOOT'); assert.equal(g.unsupported,false);
});
test('SGR 16/256/true colors and reverse/bold/underline/dim attributes survive screen cells', () => {
 const g = new TerminalGrid(10,2); g.feed('\x1b[1;2;4;91mA\x1b[22;24;38;5;196mB\x1b[48;2;1;2;3;7mC\x1b[0mD');
 assert.equal(g.cells[0][0].bold,true); assert.equal(g.cells[0][0].dim,true); assert.equal(g.cells[0][0].underline,true);
 assert.equal(g.cells[0][0].color,'#ff8b92'); assert.equal(g.cells[0][1].color,'rgb(255,0,0)');
 assert.equal(g.cells[0][1].bold,false); assert.equal(g.cells[0][2].color,'rgb(1,2,3)');
 assert.equal(g.cells[0][2].background,'rgb(255,0,0)'); assert.equal(g.cells[0][3].background,'#16181d');
 assert.equal(g.unsupported,false);
});
test('delayed wrap, overwrite of wide cells and DEC line drawing retain correct columns', () => {
 const g = new TerminalGrid(4,3); g.feed('ABCD\x1b[31mE');
 assert.equal(line(g,0),'ABCD'); assert.equal(line(g,1),'E   ');
 g.feed('\r中x\rZ'); assert.equal(line(g,1),'Z x ');
 g.feed('\x1b[3;1H\x1b(0lqk\x1b(B'); assert.equal(line(g,2),'┌─┐ ');
 g.feed('\x1b[1;1He\u0301'); assert.equal(g.cells[0][0].char,'é'); assert.equal(g.unsupported,false);
});
test('split OSC/ST and unsupported DCS are bounded and never print their payload', () => {
 const g = new TerminalGrid(8,2);
 g.feed('\x1b]2;title\x1b'); g.feed('\\OK'); assert.equal(g.title,'title'); assert.equal(line(g).trim(),'OK');
 g.feed('\x1bP'+'secret'.repeat(10000)); g.feed('\x1b\\X');
 assert.equal(line(g).trim(),'OKX'); assert.equal(g.unsupported,true);
 assert.throws(()=>g.feed('x'.repeat(TERMINAL_MAX_FEED_CHARS+1)));
 g.reset(); g.feed(('a\r\n').repeat(10000)); assert.equal(g.cells.length,2); assert.equal(g.cells[0].length,8);
});
test('insert/delete/erase chars and disabling wrap do not overrun the screen', () => {
 const g = new TerminalGrid(6,2); g.feed('abcdef\r\x1b[2@XY'); assert.equal(line(g),'XYabcd');
 g.feed('\r\x1b[2P'); assert.equal(line(g),'abcd  ');
 g.feed('\x1b[2X'); assert.equal(line(g),'  cd  ');
 g.feed('\x1b[?7l\x1b[1;6H123'); assert.equal(line(g),'  cd 3'); assert.equal(g.y,0);
 assert.equal(g.unsupported,false);
});
test('DSR and DA replies are finite, origin aware and explicitly drained', () => {
 const g = new TerminalGrid(20,6); g.feed('\x1b[3;5H\x1b[6n\x1b[5n\x1b[c\x1b[18t');
 assert.deepEqual(g.takeReplies(), ['\x1b[3;5R','\x1b[0n','\x1b[?1;0c','\x1b[8;6;20t']);
 assert.deepEqual(g.takeReplies(), []);
 g.feed('\x1b[2;5r\x1b[?6h\x1b[2;3H\x1b[?6n'); assert.deepEqual(g.takeReplies(),['\x1b[?2;3R']);
 assert.throws(()=>g.feed('\x1b[6n'.repeat(17)));
});
test('snapshot replay never answers historical queries; live output resumes query handling', () => {
 const g = new TerminalGrid(20,6);
 g.feed(('old\r\n\x1b[6n\x1b[c').repeat(1000), false);
 assert.deepEqual(g.takeReplies(), []);
 assert.equal(g.cells.length, 6); assert.equal(g.unsupported, false);
 g.feed('\x1b[1;1H\x1b[6n'); assert.deepEqual(g.takeReplies(), ['\x1b[1;1R']);
});
test('adversarial clear-screen batches stop before unbounded render work', () => {
 const g = new TerminalGrid(80,24);
 assert.throws(()=>g.feed('\x1b[2J'.repeat(2000)), /安全上限/);
 assert.equal(g.cells.length,24); assert.equal(g.cells[0].length,80);
 g.reset(); g.feed('OK'); assert.equal(line(g).trim(),'OK');
});

test('combining marks remain bounded across feeds without blocking later terminal output',()=>{
 const g=new TerminalGrid(10,3);g.feed('e');g.feed('\u0301');
 assert.equal(g.cells[0][0].char,'e\u0301');assert.equal(g.unsupported,false);
 for(let i=0;i<100;i++)g.feed('\u0301'.repeat(100));
 assert.equal(g.cells[0][0].char.length,TERMINAL_MAX_CELL_CHARS);assert.equal(g.unsupported,true);
 g.feed('OK');assert.equal(g.cells[0][1].char,'O');assert.equal(g.cells[0][2].char,'K');
 g.reset();g.feed('中');g.feed('\u0301'.repeat(200));
 assert.equal(g.cells[0][0].char.length,TERMINAL_MAX_CELL_CHARS);assert.equal(g.cells[0][1].char,'');
 g.feed('\x1b[?1049hA');g.feed('\u0301'.repeat(200));assert.equal(g.cells[0][0].char.length,TERMINAL_MAX_CELL_CHARS);
 g.feed('\x1b[?1049l');assert.equal(g.cells[0][0].char.length,TERMINAL_MAX_CELL_CHARS);
});

test('terminal verification sequence keeps the header and footer fixed through IND, LF and RI', () => {
 const g = new TerminalGrid(12, 6);
 const enter = '\x1b[?1049h\x1b[2J\x1b[1;1HHEAD\x1b[2;1HONE\x1b[3;1HTWO\x1b[4;1HTHREE\x1b[5;1HFOOT\x1b[2;4r';
 g.feed(enter);
 g.feed('\x1b[4;1H\x1bDIND');
 assert.deepEqual(g.cells.map(row=>row.map(cell=>cell.char).join('').trimEnd()), ['HEAD','TWO','THREE','IND','FOOT','']);
 g.feed('\x1b[4;1H\nLF');
 assert.deepEqual(g.cells.map(row=>row.map(cell=>cell.char).join('').trimEnd()), ['HEAD','THREE','IND','LF','FOOT','']);
 g.feed('\x1b[2;1H\x1bMRI\x1b[6;1H');
 assert.deepEqual(g.cells.map(row=>row.map(cell=>cell.char).join('').trimEnd()), ['HEAD','RI','THREE','IND','FOOT','']);
 assert.equal(g.historyLength, 0);
 assert.equal(g.unsupported, false);
});

test('index outside partial margins moves at most to physical edges and never scrolls', () => {
 const g = new TerminalGrid(4, 5);
 g.feed('HEAD\r\n1111\r\n2222\r\n3333\r\nFOOT\x1b[2;4r');
 const before = g.cells.map(row=>row.map(cell=>cell.char).join(''));
 g.feed('\x1b[5;2H\x1bD\n'); assert.deepEqual([g.x,g.y], [1,4]);
 g.feed('\x1b[1;3H\x1bM'); assert.deepEqual([g.x,g.y], [2,0]);
 g.feed('\x1b[5;3H\x1bM'); assert.deepEqual([g.x,g.y], [2,3]);
 assert.deepEqual(g.cells.map(row=>row.map(cell=>cell.char).join('')), before);
 assert.equal(g.historyLength,0);
});

test('DECSTBM over-height bounds, unchanged resize and reset maintain margins predictably', () => {
 const g = new TerminalGrid(4, 5);
 g.feed('HEAD\r\n1111\r\n2222\r\n3333\r\nFOOT\x1b[2;999r');
 g.resize(4,5);
 g.feed('\x1b[5;1H\x1bD');
 assert.deepEqual(g.cells.map(row=>row.map(cell=>cell.char).join('')), ['HEAD','2222','3333','FOOT','    ']);
 assert.equal(g.historyLength,0);
 g.resize(4,6);
 g.feed('\x1b[6;1H\x1bD');
 assert.equal(g.historyLength,1);
 g.feed('\x1b[2;4r\x1b[6;4HX\x1b[!pY');
 assert.equal(g.cells[5][3].char,'Y');
 assert.equal(g.historyLength,1);
 g.feed('\x1b[6;1H\x1bD');
 assert.equal(g.historyLength,2);
});

test('alternate screen restores main margins unless real resize resets both screens', () => {
 const g = new TerminalGrid(4, 5);
 g.feed('HEAD\r\n1111\r\n2222\r\n3333\r\nFOOT\x1b[2;4r\x1b[?1049h\x1b[5;1H\x1bD');
 assert.equal(g.historyLength,0);
 g.feed('\x1b[?1049l\x1b[4;1H\x1bD');
 assert.equal(line(g,0),'HEAD');
 assert.equal(line(g,4),'FOOT');
 assert.equal(g.historyLength,0);
 g.feed('\x1b[?1049h'); g.resize(6,6); g.feed('\x1b[6;1H\x1bD\x1b[?1049l');
 assert.equal(g.historyLength,0);
 g.feed('\x1b[6;1H\x1bD');
 assert.equal(g.historyLength,1);
});

test('scroll margins move wide character cells together without leaking them into history', () => {
 const g = new TerminalGrid(6, 5);
 g.feed('\x1b[1;1HHEAD\x1b[3;1H中X\x1b[5;1HFOOT\x1b[2;4r\x1b[4;1H\x1bD');
 assert.deepEqual(g.cells[1].slice(0,3).map(cell=>cell.char), ['中','','X']);
 g.feed('\x1b[2;1H\x1bM');
 assert.deepEqual(g.cells[2].slice(0,3).map(cell=>cell.char), ['中','','X']);
 assert.equal(line(g,0).trimEnd(),'HEAD');
 assert.equal(line(g,4).trimEnd(),'FOOT');
 assert.equal(g.historyLength,0);
});
