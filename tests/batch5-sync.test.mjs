import test from 'node:test';
import assert from 'node:assert/strict';
import {
  filePreviewUrl,
  filesUrl,
  mcpAppUrl,
  r5Url,
  threadItemsUrl
} from './load-core.mjs';

const FilePreview = await import(filePreviewUrl);
const Files = await import(filesUrl);
const R5 = await import(r5Url);
const McpApp = await import(mcpAppUrl);
const ThreadItems = await import(threadItemsUrl);

function buildSyntheticZip(entries) {
  // Build a minimal valid ZIP archive with stored (uncompressed) entries and central directory.
  const localParts = [];
  const cdParts = [];
  let offset = 0;

  for (const entry of entries) {
    const nameBytes = Buffer.from(entry.name, 'utf8');
    const dataBytes = Buffer.from(entry.content || '', 'utf8');

    const local = Buffer.alloc(30 + nameBytes.length + dataBytes.length);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(0, 6);
    local.writeUInt16LE(0, 8);
    local.writeUInt32LE(dataBytes.length, 18);
    local.writeUInt32LE(dataBytes.length, 22);
    local.writeUInt16LE(nameBytes.length, 26);
    local.writeUInt16LE(0, 28);
    nameBytes.copy(local, 30);
    dataBytes.copy(local, 30 + nameBytes.length);
    localParts.push(local);

    const cd = Buffer.alloc(46 + nameBytes.length);
    cd.writeUInt32LE(0x02014b50, 0);
    cd.writeUInt16LE(20, 4);
    cd.writeUInt16LE(20, 6);
    cd.writeUInt16LE(0, 8);
    cd.writeUInt16LE(0, 10);
    cd.writeUInt32LE(dataBytes.length, 20);
    cd.writeUInt32LE(dataBytes.length, 24);
    cd.writeUInt16LE(nameBytes.length, 28);
    cd.writeUInt16LE(0, 30);
    cd.writeUInt16LE(0, 32);
    cd.writeUInt32LE(offset, 42);
    nameBytes.copy(cd, 46);
    cdParts.push(cd);

    offset += local.length;
  }

  const cdBuf = Buffer.concat(cdParts);
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(entries.length, 8);
  eocd.writeUInt16LE(entries.length, 10);
  eocd.writeUInt32LE(cdBuf.length, 12);
  eocd.writeUInt32LE(offset, 16);

  const full = Buffer.concat([...localParts, cdBuf, eocd]);
  return full.buffer.slice(full.byteOffset, full.byteOffset + full.byteLength);
}

test('Files recognizes zip, csv/tsv, rtf and builds full-file asset resource', () => {
  assert.equal(Files.isZip('archive/build.ZIP'), true);
  assert.equal(Files.isZip('archive/build.tar'), false);
  assert.equal(Files.isDelimited('data/metrics.csv'), true);
  assert.equal(Files.isDelimited('data/metrics.TSV'), true);
  assert.equal(Files.isRtf('docs/spec.rtf'), true);

  const res = Files.fullFileTextAssetResource('thr_1', '/repo/app', 'src/big.ts');
  assert.equal(res._tag, 'media-file');
  assert.equal(res.threadId, 'thr_1');
  assert.equal(res.path, '/repo/app/src/big.ts');
  assert.equal(res.disposition, 'attachment');
});

test('FilePreview splitMarkdown preserves fences, frontmatter, and link definitions', () => {
  const md = [
    '---',
    'title: Guide',
    '---',
    '# Intro',
    'See [Home][home-ref].',
    '',
    '```ts',
    'const x = 1;',
    '# Not a heading inside fence',
    'const y = 2;',
    '```',
    '',
    '## Second Section',
    'More body text here with [Home][home-ref].',
    '',
    '[home-ref]: https://example.com'
  ].join('\n');

  const split = FilePreview.splitMarkdown(md, 60);
  assert.ok(split.chunks.length >= 2);
  assert.ok(split.definitions.includes('[home-ref]: https://example.com'));
  // Code fence should not be split in half.
  const fenceChunk = split.chunks.find(c => c.text.includes('# Not a heading inside fence'));
  assert.ok(fenceChunk);
  assert.ok(fenceChunk.text.includes('```ts'));
  assert.ok(fenceChunk.text.includes('const y = 2;\n```'));
  assert.equal(FilePreview.hasOversizedMarkdownChunk(split), false);
  assert.ok(FilePreview.withMarkdownDefinitions(split.chunks[0].text, split.definitions).includes('[home-ref]'));
});

test('FilePreview parses CSV and TSV with quoted commas and escaped quotes', () => {
  const csv = '\uFEFFname,note,count\n"Alice, Jr.","He said ""hi""",42\nBob,plain,7\n';
  const parsed = FilePreview.parseDelimitedPreview(csv, 'report.csv');
  assert.deepEqual(parsed.headers, ['name', 'note', 'count']);
  assert.equal(parsed.totalRows, 2);
  assert.equal(parsed.truncated, false);
  assert.deepEqual(parsed.rows[0], ['Alice, Jr.', 'He said "hi"', '42']);
  assert.deepEqual(parsed.rows[1], ['Bob', 'plain', '7']);

  const tsv = 'k\tv\nalpha\t1\nbeta\t2';
  const parsedTsv = FilePreview.parseDelimitedPreview(tsv, 'table.tsv');
  assert.equal(parsedTsv.delimiter, '\t');
  assert.deepEqual(parsedTsv.rows[1], ['beta', '2']);
});

test('FilePreview extracts readable text from RTF and skips header destinations', () => {
  const rtf = '{\\rtf1\\ansi{\\fonttbl{\\f0 Helvetica;}}{\\colortbl;\\red0\\green0\\blue0;}Hello\\~World\\par\\u20013?\\u25991?\\emdash done\\\'80}';
  const text = FilePreview.parseRtfToText(rtf);
  assert.equal(text.includes('Helvetica'), false);
  assert.ok(text.includes('Hello World'));
  assert.ok(text.includes('中文—done€'));
});

test('FilePreview parses ZIP central directory and lists virtual folders', () => {
  const buf = buildSyntheticZip([
    { name: 'README.md', content: '# Hello' },
    { name: 'src/index.ts', content: 'export const ok = true;' },
    { name: 'src/utils/math.ts', content: 'export const add = (a,b)=>a+b;' },
    { name: '__MACOSX/._README.md', content: 'junk' }
  ]);
  const entries = FilePreview.parseZipEntries(buf);
  assert.equal(entries.length, 3);
  const rootItems = FilePreview.listZipDirectory(entries, '');
  assert.equal(rootItems[0].isDirectory, true);
  assert.equal(rootItems[0].name, 'src');
  assert.equal(rootItems[0].childCount, 2);
  assert.equal(rootItems[1].name, 'README.md');
  assert.equal(rootItems[1].sizeBytes, 7);

  const srcItems = FilePreview.listZipDirectory(entries, 'src');
  assert.equal(srcItems[0].name, 'utils');
  assert.equal(srcItems[0].isDirectory, true);
  assert.equal(srcItems[1].name, 'index.ts');
});

test('FilePreview detects code language, tokenizes lines, and computes word-level diffs', () => {
  assert.equal(FilePreview.detectCodeLanguage('src/App.ets'), 'ts');
  assert.equal(FilePreview.detectCodeLanguage('main.py'), 'py');
  assert.equal(FilePreview.detectCodeLanguage('query.sql'), 'sql');
  const tokens = FilePreview.tokenizeCodeLine('const count = 42; // total', 'ts');
  assert.ok(tokens.some(t => t.kind === 'keyword' && t.text === 'const'));
  assert.ok(tokens.some(t => t.kind === 'number' && t.text === '42'));
  assert.ok(tokens.some(t => t.kind === 'comment' && t.text.includes('total')));

  const diff = FilePreview.computeWordDiff('const timeout = 1000;', 'const timeout = 5000;');
  assert.ok(diff.oldSegments.some(s => s.changed && s.text === '1000'));
  assert.ok(diff.newSegments.some(s => s.changed && s.text === '5000'));
  assert.ok(diff.oldSegments.some(s => !s.changed && s.text.includes('const timeout')));
});

test('R5 supports PR advanced filters, saved views, viewed files, stack merge, agent tasks, and hunk word diffs', () => {
  const input = R5.pullRequestListInput('open', 'auth', '', 'proj_1', undefined, {
    involvement: 'reviewing',
    draft: 'hide',
    review: 'changes-requested',
    checks: 'failing',
    author: 'octocat'
  });
  assert.equal(input.involvement, 'reviewing');
  assert.deepEqual(input.filters, {
    draft: 'hide',
    review: 'changes-requested',
    checks: 'failing',
    author: 'octocat'
  });

  const saved = R5.parsePullRequestSavedViews([
    { id: 'v1', name: 'My Reviews', state: 'open', query: '', involvement: 'reviewing', draft: 'hide', review: '', checks: 'failing', author: '', environmentLocalId: '', projectKey: '' },
    { id: 'v1', name: 'Duplicate', state: 'open' },
    { id: '', name: 'Invalid' }
  ]);
  assert.equal(saved.length, 1);
  assert.equal(saved[0].involvement, 'reviewing');
  assert.ok(R5.pullRequestSavedViewSignature(saved[0]).includes('reviewing|hide'));

  const viewedRes = R5.parsePullRequestFilesViewed({
    files: [{ path: 'a.ts', state: 'viewed' }, { path: 'b.ts', state: 'unviewed' }],
    truncated: false
  });
  assert.equal(viewedRes.files.length, 2);
  assert.equal(R5.isPullRequestFileViewed('a.ts', { 'a.ts': 'viewed' }, {}), true);
  assert.equal(R5.isPullRequestFileViewed('a.ts', { 'a.ts': 'viewed' }, { 'a.ts': false }), false);

  const setInput = R5.setPullRequestFilesViewedInput({ projectId: 'p1', repository: 'o/r', number: 12 }, [{ path: 'a.ts', viewed: true }]);
  assert.equal(setInput.number, 12);
  assert.deepEqual(setInput.files, [{ path: 'a.ts', viewed: true }]);

  const act = R5.actionInput({ projectId: 'p1', repository: 'o/r', number: 12 }, 'merge', 'squash', '', {
    expectedHeadSha: 'abc123',
    stackNumber: 12,
    expectedStackHeads: [{ number: 11, headSha: 'def456' }, { number: 12, headSha: 'abc123' }]
  });
  assert.equal(act.expectedHeadSha, 'abc123');
  assert.equal(act.stackNumber, 12);
  assert.equal(act.expectedStackHeads.length, 2);

  const layers = R5.parsePullRequestStackLayers({
    stack: {
      layers: [
        { number: 11, title: 'Base', state: 'open', headSha: 'sha1', mergeability: 'mergeable', position: 1 },
        { number: 12, title: 'Top', state: 'open', headSha: 'sha2', mergeability: 'mergeable', position: 2 }
      ]
    }
  });
  assert.equal(layers.length, 2);
  assert.equal(layers[1].headSha, 'sha2');

  const detail = R5.pullRequestDetail({
    number: 12, title: 'Fix sync', body: '', url: 'https://github.com/o/r/pull/12',
    state: 'open', isDraft: false, repository: 'o/r', projectId: 'p1',
    headBranch: 'feat/sync', baseBranch: 'main', additions: 10, deletions: 2, changedFiles: 1,
    mergeability: 'conflicting', headSha: 'sha2', autoMerge: { mergeMethod: 'squash' },
    capabilities: { mergeMethods: ['squash'], viewedFiles: 'host', review: { verdicts: ['approve'], inlineComment: true } },
    viewerPermissions: { actions: ['merge', 'disable-auto-merge'], comment: true }
  });
  assert.equal(detail.headSha, 'sha2');
  assert.equal(detail.autoMergeEnabled, true);
  assert.equal(detail.viewedFilesSupported, true);

  const tasks = R5.pullRequestAgentTaskOptions(detail);
  const conflictTask = tasks.find(t => t.task === 'conflicts');
  assert.equal(conflictTask.disabled, false);
  assert.ok(R5.pullRequestAgentPrompt('conflicts', detail).includes('o/r#12'));

  const files = R5.parseDiff('diff --git a/a.ts b/a.ts\n--- a/a.ts\n+++ b/a.ts\n@@ -1,2 +1,2 @@\n-const a = 1;\n+const a = 2;\n const b = 3;');
  const wordDiffs = R5.computeHunkWordDiffs(files[0].hunks[0]);
  assert.ok(wordDiffs.get(0).some(s => s.changed && s.text === '1'));
  assert.ok(wordDiffs.get(1).some(s => s.changed && s.text === '2'));
});

test('McpApp verifies tool outputs, parses sign-in notices, and hides MCP App items from work log', () => {
  const validItem = {
    id: 'item_1',
    type: 'dynamic_tool',
    toolName: 'linear.board',
    status: 'completed',
    output: {
      t3McpApp: {
        attachmentId: 'att_1',
        server: 'linear',
        tool: 'board',
        resourceUri: 'ui://linear/board',
        title: 'Linear Board'
      }
    }
  };
  const claudePrefixed = {
    id: 'item_2',
    type: 'dynamic_tool',
    toolName: 'mcp__linear_prod__issue_view',
    status: 'completed',
    output: {
      t3McpApp: {
        attachmentId: 'att_2',
        server: 'linear.prod',
        tool: 'issue/view',
        resourceUri: 'ui://linear/issue'
      }
    }
  };
  const spoofedItem = {
    id: 'item_3',
    type: 'dynamic_tool',
    toolName: 'other.tool',
    status: 'completed',
    output: {
      t3McpApp: {
        attachmentId: 'att_3',
        server: 'linear',
        tool: 'board',
        resourceUri: 'ui://linear/board'
      }
    }
  };

  assert.equal(McpApp.mcpAppFromToolItem(validItem)?.attachmentId, 'att_1');
  assert.equal(McpApp.mcpAppFromToolItem(claudePrefixed)?.attachmentId, 'att_2');
  assert.equal(McpApp.mcpAppFromToolItem(spoofedItem), undefined);

  const entries = McpApp.extractMcpAppEntries([validItem, claudePrefixed, spoofedItem]);
  assert.equal(entries.length, 2);

  // Verified MCP App items are suppressed from collapsed work log rows.
  assert.equal(ThreadItems.visibleWorkItems([validItem, spoofedItem]).length, 1);
  assert.equal(ThreadItems.visibleWorkItems([validItem, spoofedItem])[0].id, 'item_3');

  const notices = McpApp.parseMcpSignInNotices([
    { id: 'n1', type: 'system_notice', message: 'Sign in required', mcpSignIn: { server: 'github' } },
    { id: 'n2', type: 'system_notice', message: 'Latest notice', mcpSignIn: { server: 'github' } }
  ], 'thr_1', { activeProviderThreadId: 'pt_1' }, []);
  assert.equal(notices.length, 1);
  assert.equal(notices[0].id, 'n2');
  assert.equal(notices[0].providerThreadId, 'pt_1');

  assert.throws(() => McpApp.mcpSignInCompletePayload('thr_1', 'pt_1', 'github', 'javascript:alert(1)'));
  const complete = McpApp.mcpSignInCompletePayload('thr_1', 'pt_1', 'github', 'https://localhost:8765/cb?code=xyz');
  assert.equal(complete.callbackUrl, 'https://localhost:8765/cb?code=xyz');

  const rpcOk = JSON.parse(McpApp.buildMcpAppJsonRpcResult(7, { ok: true }));
  assert.equal(rpcOk.jsonrpc, '2.0');
  assert.equal(rpcOk.id, 7);
  assert.deepEqual(rpcOk.result, { ok: true });
});
