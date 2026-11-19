import test from 'node:test';
import assert from 'node:assert/strict';
import { TerminalGrid, TERMINAL_MAX_HISTORY_ROWS, TERMINAL_MAX_HISTORY_CELLS,
 TERMINAL_MAX_HISTORY_CHARS, TERMINAL_MAX_COPY_CHARS } from '../entry/src/main/ets/protocol/Terminal.ts';
const rowText=row=>row.map(cell=>cell.char).join('').trimEnd();

test('full-screen upward scroll preserves ordered rows and bottom offsets clamp safely',()=>{
 const g=new TerminalGrid(12,3);g.feed('one\r\ntwo\r\nthree\r\nfour');
 assert.equal(g.historyLength,1);assert.equal(g.scrollCount,1);
 assert.deepEqual(g.view(0,3).rows.map(rowText),['two','three','four']);
 assert.deepEqual(g.view(1,3).rows.map(rowText),['one','two','three']);
 assert.equal(g.view(1000,3).offset,1);assert.equal(g.view(-1,3).offset,0);
 assert.equal(g.view(1,3).cursorRow,-1);assert.equal(g.view(0,3).cursorRow,2);
 assert.throws(()=>g.view(NaN,3));assert.throws(()=>g.view(0,101));
 const fresh=new TerminalGrid(40,24);fresh.feed('prompt');
 assert.equal(rowText(fresh.view(0,10).rows[0]),'prompt');assert.equal(fresh.view(0,10).cursorRow,0);
});
test('visible text joins soft wraps, retains hard newlines and handles wide deferred padding and hidden cells',()=>{
 const soft=new TerminalGrid(4,2);soft.feed('abcdEF');assert.equal(soft.viewText(0,2),'abcdEF');
 const hard=new TerminalGrid(4,2);hard.feed('abcd\r\nEF');assert.equal(hard.viewText(0,2),'abcd\nEF');
 const wide=new TerminalGrid(4,2);wide.feed('abc中Z');assert.equal(wide.viewText(0,2),'abc中Z');
 const hidden=new TerminalGrid(12,2);hidden.feed('A\x1b[8m中x\x1b[28mB');
 assert.equal(hidden.viewText(0,1),'A   B');assert.equal(hidden.viewText(0,1).includes('中'),false);
 const spaces=new TerminalGrid(4,2);spaces.feed('ab  cd');assert.equal(spaces.viewText(0,2),'ab  cd');
});
test('alternate screen and partial scroll regions do not pollute main-screen history',()=>{
 const g=new TerminalGrid(8,3);g.feed('a\r\nb\r\nc\r\nd');const before=g.viewText(1,3);
 g.feed('\x1b[?1049h');g.feed(('alternate\r\n').repeat(10));
 assert.equal(g.historyLength,0);assert.equal(g.scrollCount,1);assert.equal(g.viewText(999,3).includes('a\nb'),false);g.feed('\x1b[3J');
 g.feed('\x1b[?1049l');assert.equal(g.historyLength,1);assert.equal(g.viewText(1,3),before);
 g.feed('\x1b[2;3r\x1b[3;1H');g.feed('partial\r\n');assert.equal(g.historyLength,1);
 g.feed('\x1b[1;3r\x1b[T');assert.equal(g.historyLength,1);
});
test('ED2 preserves history, ED3 drops history only, and reset+replay does not duplicate old lines or query replies',()=>{
 const g=new TerminalGrid(10,2);const history='a\r\nb\r\nc\x1b[6n';
 g.feed(history,false);assert.equal(g.historyLength,1);assert.deepEqual(g.takeReplies(),[]);
 g.reset();g.feed(history,false);assert.equal(g.historyLength,1);assert.equal(g.scrollCount,1);
 g.feed('\x1b[2J');assert.equal(g.historyLength,1);g.feed('\x1b[1;1Hscreen\x1b[3J');
 assert.equal(g.historyLength,0);assert.equal(g.viewText(0,1),'screen');assert.equal(g.historyTruncated,false);
 g.reset();assert.equal(g.scrollCount,0);assert.equal(g.historyLength,0);
});
test('history is bounded by rows and cells and logical end keeps advancing after eviction',()=>{
 const lines=new TerminalGrid(4,2);for(let i=0;i<600;i++)lines.feed('x\r\n');
 assert.equal(lines.historyLength,TERMINAL_MAX_HISTORY_ROWS);assert.equal(lines.historyTruncated,true);
 const end=lines.view(10,2).endLine;lines.feed('y\r\n');assert.equal(lines.view(11,2).endLine,end+1);
 const cells=new TerminalGrid(240,2);for(let i=0;i<400;i++)cells.feed('x\r\n');
 assert.ok(cells.historyLength*240<=TERMINAL_MAX_HISTORY_CELLS);assert.equal(cells.historyTruncated,true);
 assert.equal(cells.historyCells,cells.historyLength*240);
});
test('text budget bounds combined clusters and copy fails explicitly instead of silently truncating',()=>{
 const g=new TerminalGrid(240,2);const line=('e'+'\u0301'.repeat(127)).repeat(240)+'\r\n';
 for(let i=0;i<20;i++)g.feed(line);
 assert.ok(g.historyChars<=TERMINAL_MAX_HISTORY_CHARS);assert.ok(g.historyLength<20);assert.equal(g.historyTruncated,true);
 const copy=new TerminalGrid(240,100);
 for(let i=0;i<10;i++)copy.feed(line);
 assert.throws(()=>copy.viewText(0,100),/256 Ki/);
 assert.ok(copy.viewText(0,1).length<=TERMINAL_MAX_COPY_CHARS);
});
test('history snapshots are immutable and row metadata follows resize and insert/delete lines',()=>{
 const g=new TerminalGrid(4,3);g.feed('abcdEFGHij');g.feed('\r\nlast');
 const saved=g.view(1,3).rows[0];assert.equal(rowText(saved),'abcd');
 g.feed('\x1b[1;1HZ');assert.equal(rowText(saved),'abcd');
 g.resize(6,3);assert.equal(g.view(1,3).rows[0].length,4);
 assert.equal(g.wrapped.length,3);g.feed('\x1b[2;1H\x1b[L');assert.equal(g.wrapped.length,3);
 g.feed('\x1b[M');assert.equal(g.wrapped.length,3);
 g.feed('\x1b[?1049h');g.resize(8,4);g.feed('\x1b[?1049l');
 assert.equal(g.wrapped.length,4);assert.equal(g.cells.length,4);assert.equal(g.cells[0].length,8);
});

test('copy includes a later write into the padding left by a deferred wide wrap', () => {
 const g = new TerminalGrid(4, 3);
 g.feed('abc中\u0301Z\r\nnext');
 assert.equal(g.viewText(), 'abc中\u0301Z\nnext');
 g.feed('\x1b[1;4H!');
 assert.equal(g.viewText(), 'abc!中\u0301Z\nnext');
});
