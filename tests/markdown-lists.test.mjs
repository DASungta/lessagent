import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { markdownUrl } from './load-core.mjs';

const md = await import(markdownUrl);

function markers(block) {
  return block.items.map((item) => ({
    depth: item.depth,
    ordered: item.ordered,
    number: item.number,
    marker: item.displayMarker,
    text: item.text
  }));
}

test('ordered list with nested unordered bullets keeps sequential outer numbering across indent widths', () => {
  const blocks = md.markdownDocument([
    '1. 第一步',
    '  - 2空格子项 A',
    '  - 2空格子项 B',
    '2. 第二步',
    '   - 3空格子项 C',
    '     - 更深一层',
    '3. 第三步',
    '    - 4空格子项 D',
    '4. 第四步',
    '\t- Tab 子项 E',
    '5. 第五步'
  ].join('\n'));

  assert.equal(blocks.length, 1);
  assert.equal(blocks[0].kind, 'list');
  assert.equal(blocks[0].ordered, true);
  assert.equal(blocks[0].start, 1);
  assert.deepEqual(markers(blocks[0]), [
    { depth: 0, ordered: true, number: 1, marker: '1.', text: '第一步' },
    { depth: 1, ordered: false, number: 0, marker: '•', text: '2空格子项 A' },
    { depth: 1, ordered: false, number: 0, marker: '•', text: '2空格子项 B' },
    { depth: 0, ordered: true, number: 2, marker: '2.', text: '第二步' },
    { depth: 1, ordered: false, number: 0, marker: '•', text: '3空格子项 C' },
    { depth: 2, ordered: false, number: 0, marker: '•', text: '更深一层' },
    { depth: 0, ordered: true, number: 3, marker: '3.', text: '第三步' },
    { depth: 1, ordered: false, number: 0, marker: '•', text: '4空格子项 D' },
    { depth: 0, ordered: true, number: 4, marker: '4.', text: '第四步' },
    { depth: 1, ordered: false, number: 0, marker: '•', text: 'Tab 子项 E' },
    { depth: 0, ordered: true, number: 5, marker: '5.', text: '第五步' }
  ]);
});

test('nested ordered lists reset numbering per sublist without shifting outer numbering', () => {
  const blocks = md.markdownDocument([
    '1. 阶段一',
    '   1. 任务 A',
    '   2. 任务 B',
    '      1. 细项 i',
    '      2. 细项 ii',
    '   3. 任务 C',
    '2. 阶段二',
    '   1. 任务 D',
    '   2. 任务 E'
  ].join('\n'));

  assert.equal(blocks.length, 1);
  assert.deepEqual(markers(blocks[0]), [
    { depth: 0, ordered: true, number: 1, marker: '1.', text: '阶段一' },
    { depth: 1, ordered: true, number: 1, marker: '1.', text: '任务 A' },
    { depth: 1, ordered: true, number: 2, marker: '2.', text: '任务 B' },
    { depth: 2, ordered: true, number: 1, marker: '1.', text: '细项 i' },
    { depth: 2, ordered: true, number: 2, marker: '2.', text: '细项 ii' },
    { depth: 1, ordered: true, number: 3, marker: '3.', text: '任务 C' },
    { depth: 0, ordered: true, number: 2, marker: '2.', text: '阶段二' },
    { depth: 1, ordered: true, number: 1, marker: '1.', text: '任务 D' },
    { depth: 1, ordered: true, number: 2, marker: '2.', text: '任务 E' }
  ]);
});

test('ordered lists nested inside unordered bullets start each sublist from its own start number', () => {
  const blocks = md.markdownDocument([
    '- 方案一',
    '  1. 步骤一',
    '  2. 步骤二',
    '- 方案二',
    '  1. 步骤一',
    '  2. 步骤二'
  ].join('\n'));

  assert.equal(blocks.length, 1);
  assert.equal(blocks[0].ordered, false);
  assert.deepEqual(markers(blocks[0]), [
    { depth: 0, ordered: false, number: 0, marker: '•', text: '方案一' },
    { depth: 1, ordered: true, number: 1, marker: '1.', text: '步骤一' },
    { depth: 1, ordered: true, number: 2, marker: '2.', text: '步骤二' },
    { depth: 0, ordered: false, number: 0, marker: '•', text: '方案二' },
    { depth: 1, ordered: true, number: 1, marker: '1.', text: '步骤一' },
    { depth: 1, ordered: true, number: 2, marker: '2.', text: '步骤二' }
  ]);
});

test('auto-incremented 1./1./1., custom starts (0., 3.), and parenthesis delimiters (1)) are preserved', () => {
  const auto = md.markdownDocument('1. A\n1. B\n1. C');
  assert.equal(auto.length, 1);
  assert.deepEqual(auto[0].items.map((item) => item.displayMarker), ['1.', '2.', '3.']);

  const zeroStart = md.markdownDocument('0. Zero\n1. One\n2. Two');
  assert.equal(zeroStart[0].start, 0);
  assert.deepEqual(zeroStart[0].items.map((item) => item.displayMarker), ['0.', '1.', '2.']);

  const customStart = md.markdownDocument('3. Third\n3. Fourth');
  assert.equal(customStart[0].start, 3);
  assert.deepEqual(customStart[0].items.map((item) => item.displayMarker), ['3.', '4.']);

  const parens = md.markdownDocument('1) 选项一\n2) 选项二\n   1) 子选项');
  assert.equal(parens.length, 1);
  assert.deepEqual(parens[0].items.map((item) => item.displayMarker), ['1)', '2)', '1)']);
});

test('switching top-level list kind or delimiter splits into separate list blocks with fresh numbering', () => {
  const bulletThenOrdered = md.markdownDocument([
    '- 背景一',
    '- 背景二',
    '',
    '1. 下一步',
    '2. 再下一步'
  ].join('\n'));
  assert.equal(bulletThenOrdered.length, 2);
  assert.equal(bulletThenOrdered[0].ordered, false);
  assert.deepEqual(bulletThenOrdered[0].items.map((item) => item.displayMarker), ['•', '•']);
  assert.equal(bulletThenOrdered[1].ordered, true);
  assert.equal(bulletThenOrdered[1].start, 1);
  assert.deepEqual(bulletThenOrdered[1].items.map((item) => item.displayMarker), ['1.', '2.']);

  const dotThenParen = md.markdownDocument('1. A\n2. B\n1) C\n2) D');
  assert.equal(dotThenParen.length, 2);
  assert.deepEqual(dotThenParen[0].items.map((item) => item.displayMarker), ['1.', '2.']);
  assert.deepEqual(dotThenParen[1].items.map((item) => item.displayMarker), ['1)', '2)']);

  const alternating = md.markdownDocument('1. A\n- B\n1. C');
  assert.equal(alternating.length, 3);
  assert.deepEqual(alternating[0].items.map((item) => item.displayMarker), ['1.']);
  assert.deepEqual(alternating[1].items.map((item) => item.displayMarker), ['•']);
  assert.deepEqual(alternating[2].items.map((item) => item.displayMarker), ['1.']);
});

test('switching list kind at nested depth preserves parent ordered counter', () => {
  const blocks = md.markdownDocument([
    '1. 顶层一',
    '   - 嵌套无序',
    '   1. 嵌套有序一',
    '   2. 嵌套有序二',
    '2. 顶层二'
  ].join('\n'));

  assert.equal(blocks.length, 1);
  assert.deepEqual(markers(blocks[0]), [
    { depth: 0, ordered: true, number: 1, marker: '1.', text: '顶层一' },
    { depth: 1, ordered: false, number: 0, marker: '•', text: '嵌套无序' },
    { depth: 1, ordered: true, number: 1, marker: '1.', text: '嵌套有序一' },
    { depth: 1, ordered: true, number: 2, marker: '2.', text: '嵌套有序二' },
    { depth: 0, ordered: true, number: 2, marker: '2.', text: '顶层二' }
  ]);
});

test('1-space indent jitter and right-aligned multi-digit numbers keep siblings at the same depth', () => {
  const jitter = md.markdownDocument([
    '1. 第一步',
    '   - 子项',
    ' 2. 第二步（误多1空格）',
    '3. 第三步'
  ].join('\n'));
  assert.equal(jitter.length, 1);
  assert.deepEqual(markers(jitter[0]), [
    { depth: 0, ordered: true, number: 1, marker: '1.', text: '第一步' },
    { depth: 1, ordered: false, number: 0, marker: '•', text: '子项' },
    { depth: 0, ordered: true, number: 2, marker: '2.', text: '第二步（误多1空格）' },
    { depth: 0, ordered: true, number: 3, marker: '3.', text: '第三步' }
  ]);

  const rightAligned = md.markdownDocument([
    ' 9. 第九项',
    '   - 子项',
    '10. 第十项',
    '    - 子项',
    '11. 第十一项'
  ].join('\n'));
  assert.equal(rightAligned.length, 1);
  assert.equal(rightAligned[0].start, 9);
  assert.deepEqual(markers(rightAligned[0]), [
    { depth: 0, ordered: true, number: 9, marker: '9.', text: '第九项' },
    { depth: 1, ordered: false, number: 0, marker: '•', text: '子项' },
    { depth: 0, ordered: true, number: 10, marker: '10.', text: '第十项' },
    { depth: 1, ordered: false, number: 0, marker: '•', text: '子项' },
    { depth: 0, ordered: true, number: 11, marker: '11.', text: '第十一项' }
  ]);
});

test('ordered list interrupted by code block or paragraph preserves subsequent explicit start number', () => {
  const blocks = md.markdownDocument([
    '1. 安装依赖',
    '',
    '```bash',
    'npm install',
    '```',
    '',
    '2. 运行测试',
    '',
    '补充说明段落。',
    '',
    '3. 发布版本'
  ].join('\n'));

  assert.deepEqual(blocks.map((b) => b.kind), ['list', 'code', 'list', 'paragraph', 'list']);
  assert.deepEqual(blocks[0].items.map((i) => i.displayMarker), ['1.']);
  assert.deepEqual(blocks[2].items.map((i) => i.displayMarker), ['2.']);
  assert.deepEqual(blocks[4].items.map((i) => i.displayMarker), ['3.']);
});

test('list block populates text for streaming updates and MarkdownView renders displayMarker safely', async () => {
  const partial = md.markdownDocument('1. 第一项\n2. 第二');
  const complete = md.markdownDocument('1. 第一项\n2. 第二项');
  assert.ok(partial[0].text.length > 0);
  assert.notEqual(partial[0].text, complete[0].text);

  const viewSource = await readFile(
    new URL('../entry/src/main/ets/components/MarkdownView.ets', import.meta.url),
    'utf8'
  );
  assert.ok(viewSource.includes('item.displayMarker'));
  assert.ok(!viewSource.includes('(block.start + index)'));
  assert.ok(viewSource.includes('.maxLines(1)'));
  assert.ok(viewSource.includes('.flexShrink(0)'));
  assert.ok(viewSource.includes('private blockKey('));
});
