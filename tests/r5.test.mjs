import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { compile, data, markdownUrl, filesUrl, r5Url } from './load-core.mjs';
const md = await import(markdownUrl);
const files = await import(filesUrl);
const r5 = await import(r5Url);

test('opening a search result positions the source list only at a verified, selectable line', async () => {
  const source = await readFile(new URL('../entry/src/main/ets/components/FilesPanel.ets', import.meta.url), 'utf8');
  const methods = source.slice(source.indexOf('  private async openFile('), source.indexOf('  private addSelectionContext('));
  const { FilePreview } = await import(data(compile(`
    import { fileLines, isImage, isVideo, isAudio, isPdf, isHtml, matchesContentSearchLine } from ${JSON.stringify(filesUrl)};
    export class FilePreview { ${methods} }
  `)));
  const firstPage = Array.from({ length: 5001 }, (_, index) => 'line ' + (index + 1));
  let contents = firstPage.join('\n');
  let truncated = false;
  let epoch = 0;
  const panel = Object.assign(new FilePreview(), {
    connection: { readWorkspaceFile: async () => ({ contents, truncated }) },
    beginRead: () => { const request = ++epoch; return () => request === epoch; },
    invalidateReads: () => { epoch++; },
    reportStatus: value => { panel.reported = value; },
  });
  const hit = (lineNumber, lineContent) => ({ path: 'test.md', lineNumber, lineContent, ranges: [] });
  await panel.openFile('test.md', hit(70, 'line 70'));
  assert.equal(panel.previewStartIndex, 69);
  assert.equal(panel.selectionStart, 69);
  assert.equal(panel.selectionEnd, 69);
  assert.match(source, /isMarkdown\(this\.selectedPath\) && !this\.selectedMatch/);
  assert.match(source, /List\(\{ space: 0, initialIndex: this\.previewStartIndex \}\)/);
  await panel.openFile('test.md', hit(5001, 'line 5001'));
  assert.equal(panel.selectionStart, -1);
  assert.equal(panel.previewStartIndex, 0);
  assert.match(panel.matchNotice, /不在当前预览/);
  contents = 'before\r\nreplaced';
  await panel.openFile('test.md', hit(2, 'previous'));
  assert.equal(panel.selectionStart, -1);
  assert.match(panel.matchNotice, /不一致/);
  await panel.openFile('test.md');
  assert.equal(panel.previewStartIndex, 0);
  assert.equal(panel.selectionStart, -1);
  assert.equal(panel.selectedMatch, undefined);
  const prefix = '\t' + 'x'.repeat(511);
  const longLine = prefix + 'A[B]' + 'y'.repeat(4500) + '\tend';
  panel.matchQuery = 'a[b]';
  panel.query = 'different unsubmitted search';
  contents = 'before\r\n' + longLine + '\r\nafter';
  await panel.openFile('test.md', hit(2, prefix));
  assert.equal(panel.previewStartIndex, 1);
  assert.equal(panel.selectedText(), longLine);
  assert.notEqual(panel.lines[1].text, longLine);
  assert.match(panel.matchNotice, /整行原文/);
  contents = 'before\r\n' + prefix + 'ab';
  await panel.openFile('test.md', hit(2, prefix));
  assert.equal(panel.selectionStart, -1);
  assert.match(panel.matchNotice, /不一致/);
  contents = 'before\r\n' + longLine;
  truncated = true;
  await panel.openFile('test.md', hit(2, prefix));
  assert.equal(panel.selectionStart, -1);
  assert.match(panel.matchNotice, /不在当前预览/);
  panel.selectLine(1);
  assert.equal(panel.selectionStart, -1);
  assert.match(panel.reported, /不完整/);
  contents += '\npartial tail';
  await panel.openFile('test.md', hit(2, prefix));
  assert.equal(panel.selectedText(), longLine);
});

test('diff gutters receive the largest actual line numbers per hunk, including an absent side', () => {
  const [file] = r5.parseDiff('--- a/a.ts\n+++ b/a.ts\n@@ -0,0 +1,2 @@\n+one\n+two\n' +
    '@@ -9999,2 +99,2 @@\n context\n-old\n+new\n@@ -30 +0,0 @@\n-removed');
  assert.deepEqual(file.hunks.map(hunk => [hunk.lastOldLine, hunk.lastNewLine]), [[0, 2], [10000, 100], [30, 0]]);
});

test('line number columns use the same native font metrics for hidden measurement and visible numbers', async () => {
  const component = filename => readFile(new URL('../entry/src/main/ets/components/' + filename + '.ets', import.meta.url), 'utf8');
  const [gutter, source, review, pullRequest] = await Promise.all(
    ['DiffLineNumber', 'FilesPanel', 'ReviewPanel', 'PullRequestsPanel'].map(component));
  assert.match(gutter, /Stack\(\{ alignContent: Alignment\.TopEnd \}\)/);
  const font = /\.fontSize\(Math\.max\(8, this\.codeFontSize - 3\)\)\.fontFamily\('monospace'\)/g;
  assert.equal([...gutter.matchAll(font)].length, 2);
  assert.match(gutter, /Text\(String\(this\.lastLine\)\)[\s\S]*?\.maxLines\(1\)\.opacity\(0\)\.accessibilityLevel\('no'\)/);
  assert.doesNotMatch(gutter, /\.width\(/);
  assert.match(source, /DiffLineNumber\(\{ line: line\.number, lastLine: this\.lines\.length/);
  for (const panel of [review, pullRequest]) {
    assert.match(panel, /if \(hunk\.lastOldLine\) \{\s*DiffLineNumber\(\{ line: row\.oldLine, lastLine: hunk\.lastOldLine \}\)/);
    assert.match(panel, /if \(hunk\.lastNewLine\) \{\s*DiffLineNumber\(\{ line: row\.newLine, lastLine: hunk\.lastNewLine \}\)/);
  }
});

test('source and both diffs opt into code appearance without changing chat Markdown or splitting content', async () => {
  const component = filename => readFile(new URL('../entry/src/main/ets/components/' + filename + '.ets', import.meta.url), 'utf8');
  const [line, source, review, pullRequest, markdown] = await Promise.all(
    ['CodeLine', 'FilesPanel', 'ReviewPanel', 'PullRequestsPanel', 'MarkdownView'].map(component));
  assert.match(line, /@StorageProp\('t3CodeFontSize'\)/);
  assert.match(line, /@StorageProp\('t3CodeWordBreak'\)/);
  assert.match(line, /this\.codeWordBreak[\s\S]*?Text\(this\.text \|\| ' '\)[\s\S]*?WordBreak\.BREAK_ALL/);
  assert.match(line, /else \{[\s\S]*?Text\(this\.text \|\| ' '\)[\s\S]*?ScrollDirection\.Horizontal\)\.align\(Alignment\.TopStart\)/);
  assert.match(source, /CodeLine\(\{ text: line\.text \}\)/);
  for (const panel of [review, pullRequest]) {
    assert.match(panel, /CodeLine\(\{ text: row\.text,/);
    assert.match(panel, /this\.codeFontSize \+ 9\) \+ 'fp'/);
  }
  assert.doesNotMatch(markdown, /t3CodeFontSize|t3CodeWordBreak/);

  const contents = '    ' + 'a'.repeat(500);
  assert.deepEqual(files.fileLines(contents), [{ number: 1, text: contents }]);
  const [file] = r5.parseDiff('diff --git a/a.ts b/a.ts\n--- a/a.ts\n+++ b/a.ts\n@@ -1 +1 @@\n-old\n+' + contents);
  assert.ok(r5.selectedDiff(file, file.hunks[0], 1, 1).diff.includes('+' + contents));
});

test('Markdown parses GFM blocks without leaking raw tags', () => {
  const blocks = md.markdownDocument([
    '# Title', '', 'Setext', '======', '', '| A | B |', '| :-- | --: |', '| 1 | 2 |', '',
    '- [x] done', '- [ ] todo', '  - nested', '', '> quoted **bold**', '',
    '<details open><summary>More</summary>', 'inside', '</details>', '',
    '```ts', 'const a = 1;', '```', '', '$$', 'x^2 + y_1', '$$', ''
  ].join('\n'));
  assert.equal(blocks[0].kind, 'heading');
  assert.equal(blocks[0].level, 1);
  assert.equal(blocks[1].kind, 'heading');
  assert.equal(blocks[1].level, 1);
  assert.equal(blocks[2].kind, 'table');
  assert.deepEqual(blocks[2].align, ['left', 'right']);
  assert.deepEqual(blocks[2].rows, [['1', '2']]);
  assert.equal(blocks[3].kind, 'list');
  assert.equal(blocks[3].items[0].checked, true);
  assert.equal(blocks[3].items[1].checked, false);
  assert.equal(blocks[3].items[2].depth, 1);
  assert.equal(blocks[4].kind, 'quote');
  assert.equal(blocks[5].kind, 'details');
  assert.equal(blocks[5].open, true);
  assert.equal(blocks[5].summary, 'More');
  assert.equal(blocks[6].kind, 'code');
  assert.equal(blocks[6].language, 'ts');
  assert.equal(blocks[7].kind, 'math');
  assert.equal(md.mathText(blocks[7].text), 'x² + y₁');
});

test('Markdown keeps streaming code and folds unclosed details', () => {
  const blocks = md.markdownDocument('```\npartial');
  assert.equal(blocks[0].kind, 'code');
  assert.equal(blocks[0].text, 'partial');
  assert.equal(blocks[0].language, '');
  const fold = md.markdownDocument('<details><summary>S</summary>\nstill streaming');
  assert.equal(fold[0].kind, 'details');
  assert.match(fold[0].body, /still streaming/);
});

test('code fences tokenize keywords, strings, comments and numbers', () => {
  const lines = md.codeTokens('const value = 42; // note\nreturn "ok";', 'ts');
  assert.equal(lines.length, 2);
  assert.deepEqual(lines[0].map(token => token.kind),
    ['keyword', 'plain', 'number', 'plain', 'comment']);
  assert.equal(lines[0][0].text, 'const');
  assert.equal(lines[1][2].kind, 'string');
  assert.equal(md.codeTokens('plain', 'unknown')[0][0].kind, 'plain');
});

test('Markdown inline spans separate code, links, images and math', () => {
  const spans = md.inlineSpans('a `b` **c** [d](https://x.y "t") ![alt](z.png) $x^2$');
  assert.deepEqual(spans.map((span) => span.kind),
    ['text', 'code', 'text', 'strong', 'text', 'link', 'text', 'image', 'text', 'math']);
  assert.equal(spans.find((span) => span.kind === 'link').href, 'https://x.y');
  assert.equal(spans.find((span) => span.kind === 'image').href, 'z.png');
  assert.equal(md.imageSource('javascript:alert(1)'), '');
  assert.equal(md.imageSource('https://example.com/a.png'), 'https://example.com/a.png');
});

test('workspace paths reject traversal and absolute roots', () => {
  assert.equal(files.joinPath('/repo', '/src/a.ts'), '/repo/src/a.ts');
  assert.throws(() => md.workspacePath('../etc/passwd'));
  assert.throws(() => md.workspacePath('/etc/passwd'));
  assert.equal(files.mimeType('a/b/photo.PNG'), 'image/png');
  assert.equal(files.isImage('a.png'), true);
  assert.equal(files.isMarkdown('README.md'), true);
  assert.deepEqual(files.fileLines('a\r\nb\tc'), [{ number: 1, text: 'a' }, { number: 2, text: 'b    c' }]);
  assert.equal(files.fileLines('1\n2\n3', 2).length, 2);
});

test('unified Diff keeps file, rename and line numbers', () => {
  const patch = [
    'diff --git a/src/a.ts b/src/b.ts', 'similarity index 90%', 'rename from src/a.ts', 'rename to src/b.ts',
    '--- a/src/a.ts', '+++ b/src/b.ts', '@@ -3,3 +3,4 @@', ' keep', '-old', '+new', '+added', ' end', ''
  ].join('\n');
  const parsed = r5.parseDiff(patch);
  assert.equal(parsed.length, 1);
  assert.equal(parsed[0].changeType, 'rename-pure');
  assert.equal(parsed[0].path, 'src/b.ts');
  assert.equal(parsed[0].additions, 2);
  assert.equal(parsed[0].deletions, 1);
  assert.equal(parsed[0].hunks[0].rows[0].newLine, 3);
  assert.equal(parsed[0].hunks[0].rows[1].oldLine, 4);
  assert.equal(parsed[0].hunks[0].rows[2].newLine, 4);
  assert.equal(r5.diffStats(parsed).additions, 2);
});

test('review selection produces upstream review_comment context', () => {
  const file = r5.parseDiff('diff --git a/a.ts b/a.ts\n--- a/a.ts\n+++ b/a.ts\n@@ -1,2 +1,2 @@\n-old\n+new\n keep')[0];
  const selection = r5.selectedDiff(file, file.hunks[0], 0, 1);
  assert.equal(selection.rangeLabel, '行 1–1');
  const context = r5.reviewCommentContext(selection, 'please check', 'ctx_1');
  assert.equal(context.kind, 'review-comment');
  assert.match(context.payload.text, /<review_comment/);
  assert.match(context.payload.text, /\+new/);
  assert.match(context.payload.text, /```diff/);
  const fileComment = r5.fileCommentContext('src/a.ts', 'whole file note', 'ctx_2');
  assert.equal(fileComment.payload.rangeLabel, '文件评论');
  assert.equal(fileComment.payload.diff, '');
  assert.match(fileComment.payload.text, /whole file note/);
  assert.throws(() => r5.fileCommentContext('src/a.ts', '   ', 'ctx_3'));
});

test('VCS status snapshots merge local and remote facts', () => {
  const local = { isRepo: true, hasPrimaryRemote: true, isDefaultRef: false, refName: 'main',
    hasWorkingTreeChanges: true, workingTree: { rootPath: '/repo', insertions: 3, deletions: 1,
      files: [{ path: 'a.ts', insertions: 3, deletions: 1 }] } };
  const snapshot = r5.applyVcsStatus(r5.emptyVcs(), { _tag: 'snapshot', local, remote: {
    hasUpstream: true, aheadCount: 2, behindCount: 0, pr: null } });
  assert.equal(snapshot.isRepo, true);
  assert.equal(snapshot.hasPrimaryRemote, true);
  assert.equal(snapshot.files[0].path, 'a.ts');
  assert.equal(snapshot.ahead, 2);
  const after = r5.applyVcsStatus(snapshot, { _tag: 'remoteUpdated',
    remote: { hasUpstream: true, aheadCount: 0, behindCount: 1, pr: { number: 7, state: 'open', title: 'T', url: 'u' } } });
  assert.equal(after.behind, 1);
  assert.equal(after.prNumber, 7);
  assert.equal(after.refName, 'main');
  const direct = r5.applyVcsStatus(r5.emptyVcs(), { isRepo: true, refName: 'dev', hasWorkingTreeChanges: false,
    workingTree: { files: [], insertions: 0, deletions: 0 }, hasUpstream: false, aheadCount: 0, behindCount: 0, pr: null });
  assert.equal(direct.isRepo, true);
  assert.equal(direct.refName, 'dev');
});

test('Git and PR commands validate before sending', () => {
  assert.throws(() => r5.gitActionInput('action_1', '/repo', 'commit', ''));
  assert.equal(r5.gitActionInput('action_1', '/repo', 'commit', 'msg').action, 'commit');
  assert.throws(() => r5.pullRequestListInput('bogus', ''));
  assert.deepEqual(r5.pullRequestListInput('open', 'fix', 'c1'), {
    state: 'open', involvement: 'all', limit: 30, query: 'fix', cursors: { default: 'c1' } });
  assert.deepEqual(r5.pullRequestListInput('all', '', '', 'p1', { 'gitlab:org/repo': 'tok-1' }), {
    state: 'all', involvement: 'all', limit: 30, cursors: { 'gitlab:org/repo': 'tok-1' }, projectId: 'p1' });
  assert.deepEqual(r5.parsePullRequestCursors({ 'gitlab:org/repo': ' tok-1 ', empty: '' }), { 'gitlab:org/repo': 'tok-1' });
  assert.equal(r5.firstPullRequestCursor({ 'gitlab:org/repo': 'tok-1' }), 'tok-1');
  assert.throws(() => r5.pullRequestRef('', 'repo', 1));
  assert.throws(() => r5.reviewSubmitInput({ projectId: 'p', repository: 'r', number: 1 }, 'nope', ''));
});

test('PR list and detail parse provider status and permissions', () => {
  const list = r5.pullRequestRows({
    providers: [{ kind: 'github', host: 'github.com', configured: false, detail: 'Sign in required', projectCount: 1 }],
    entries: [{ provider: 'github', projectId: 'p', projectTitle: 'P', repository: 'o/r', number: 3,
      title: 'Fix', url: 'https://example/3', author: { login: 'me' }, headBranch: 'a', baseBranch: 'main',
      state: 'open', isDraft: false, additions: 2, deletions: 1, viewerReviewRequested: false, labels: [{ name: 'bug' }],
      stack: { position: 2, size: 3 } }],
    errors: [{ projectId: 'q', projectTitle: 'Q', message: 'offline' }], truncated: false, cursors: {} });
  assert.equal(list.rows[0].author, 'me');
  assert.equal(list.rows[0].stackPosition, 2);
  assert.deepEqual(list.rows[0].labels, ['bug']);
  assert.equal(list.providers[0].configured, false);
  const detail = r5.pullRequestDetail({ number: 3, title: 'Fix', body: 'b', url: 'u', state: 'open', isDraft: false,
    repository: 'o/r', projectId: 'p', headBranch: 'a', baseBranch: 'main', additions: 2, deletions: 1,
    changedFiles: 1, mergeability: 'mergeable', checks: [{ name: 'ci', state: 'success' }],
    capabilities: { diff: true, comment: true, actions: ['merge'], mergeMethods: ['squash'],
      review: { inlineComment: true, reply: true, resolve: true, verdicts: ['comment', 'approve'] } },
    viewerPermissions: { actions: ['merge'], comment: true, resolve: true } });
  assert.deepEqual(detail.mergeMethods, ['squash']);
  assert.equal(r5.prActionDisabled('merge', detail), '');
  assert.match(r5.prActionDisabled('close', detail), /不允许/);
});

test('PR project filter choices exclude non-repo/scratch, disambiguate across environments, and sort pinned first', () => {
  const choices = r5.pullRequestProjectChoices([
    { localId: 'mac', environmentId: 'env-mac', environmentLabel: 'iMac', id: 'scratch', label: 'No project',
      workspaceRoot: '/tmp', archivedAt: '', pinnedAt: '', isScratch: true, repository: undefined },
    { localId: 'mac', environmentId: 'env-mac', environmentLabel: 'iMac', id: 'docs', label: '造价',
      workspaceRoot: '/docs', archivedAt: '', pinnedAt: '', isScratch: false, repository: undefined },
    { localId: 'mac', environmentId: 'env-mac', environmentLabel: 'iMac', id: 'p-yx-1', label: 'yxbuddy',
      workspaceRoot: '/yx', archivedAt: '', pinnedAt: '', isScratch: false,
      repository: { canonicalKey: 'gitlab.example/base/yxbuddy', displayName: 'base/yxbuddy' } },
    { localId: 'ca02', environmentId: 'env-ca02', environmentLabel: 'ca02', id: 'p-yx-2', label: 'yxbuddy',
      workspaceRoot: '/home/yx', archivedAt: '', pinnedAt: '', isScratch: false,
      repository: { canonicalKey: 'gitlab.example/base/yxbuddy', displayName: 'base/yxbuddy' } },
    { localId: 'mac', environmentId: 'env-mac', environmentLabel: 'iMac', id: 'p-harm', label: 't3code-harmony',
      workspaceRoot: '/harm', archivedAt: '', pinnedAt: '2026-11-21T00:00:00Z', isScratch: false,
      repository: { canonicalKey: 'github.com/dasungta/t3code-harmony', displayName: 'DASungta/t3code-harmony' } }
  ]);
  assert.deepEqual(choices.map(c => c.key), ['mac:p-harm', 'ca02:p-yx-2', 'mac:p-yx-1']);
  assert.equal(choices[0].title, 't3code-harmony');
  assert.equal(choices[1].title, 'yxbuddy · ca02');
  assert.equal(choices[2].title, 'yxbuddy · iMac');
  const onlyMac = r5.pullRequestProjectChoices([
    { localId: 'mac', environmentId: 'env-mac', environmentLabel: 'iMac', id: 'p-yx-1', label: 'yxbuddy',
      workspaceRoot: '/yx', archivedAt: '', pinnedAt: '', isScratch: false,
      repository: { canonicalKey: 'gitlab.example/base/yxbuddy', displayName: 'base/yxbuddy' } },
    { localId: 'ca02', environmentId: 'env-ca02', environmentLabel: 'ca02', id: 'p-yx-2', label: 'yxbuddy',
      workspaceRoot: '/home/yx', archivedAt: '', pinnedAt: '', isScratch: false,
      repository: { canonicalKey: 'gitlab.example/base/yxbuddy', displayName: 'base/yxbuddy' } }
  ], 'mac');
  assert.deepEqual(onlyMac.map(c => [c.key, c.title]), [['mac:p-yx-1', 'yxbuddy']]);
});

test('PR row merge deduplicates same repo across environments preferring active environment and sorts newest first', () => {
  const make = (localId, number, updatedAt, repo = 'base/yxbuddy') => ({
    provider: 'gitlab', host: 'gitlab.example', projectId: 'p-' + localId, projectTitle: 'yxbuddy',
    repository: repo, number, title: 'PR #' + number, url: 'u', author: 'a', headBranch: 'h', baseBranch: 'main',
    state: 'open', draft: false, additions: 0, deletions: 0, updatedAt, reviewDecision: '', checksState: '',
    labels: [], stackPosition: 0, stackSize: 0, localId, environmentLabel: localId
  });
  const merged = r5.mergePullRequestRows(
    [],
    [make('ca02', 39, '2026-11-22T02:00:00Z'), make('mac', 39, '2026-11-22T02:00:00Z'), make('mac', 40, '2026-11-22T03:00:00Z', 'org/harmony')],
    true,
    'mac'
  );
  assert.equal(merged.length, 2);
  assert.equal(merged[0].number, 40);
  assert.equal(merged[1].number, 39);
  assert.equal(merged[1].localId, 'mac');
});

test('PR review guide parses stops, attention, stale and running state', () => {
  const guide = r5.pullRequestGuide({
    guide: {
      headSha: 'aaa111', generatedAt: '2026-11-18T00:00:00Z',
      modelSelection: { provider: 'openai', model: 'm' },
      stops: [{
        title: 'Read the state machine', summary: 'Start at the reducer',
        attention: { kind: 'risk', note: 'Check retry ordering' },
        excerpts: [{ path: 'src/a.ts', side: 'new', start: 10, end: 14, caption: 'reducer' }],
        files: [{ path: 'src/a.ts', note: 'main change' }],
        notes: [{ path: 'src/a.ts', line: 12, title: 'Ordering', body: 'retry before settle' }],
        questions: ['Can retry duplicate work?']
      }]
    },
    run: { _tag: 'Running', headSha: 'bbb222', startedAt: '2026-11-18T00:01:00Z' },
    currentHeadSha: 'bbb222'
  });
  assert.equal(guide.running, true);
  assert.equal(guide.stale, true);
  assert.equal(guide.stops[0].attentionKind, 'risk');
  assert.equal(guide.stops[0].excerpts[0].start, 10);
  assert.deepEqual(guide.stops[0].questions, ['Can retry duplicate work?']);
  const failed = r5.pullRequestGuide({ guide: null, run: { _tag: 'Failed', detail: 'no model' }, currentHeadSha: null });
  assert.equal(failed.running, false);
  assert.equal(failed.runDetail, 'no model');
  assert.equal(failed.stops.length, 0);
});

test('PR detail carries activity for the discussion fallback', () => {
  const detail = r5.pullRequestDetail({
    number: 1, title: 'T', body: '', url: 'u', state: 'open', repository: 'o/r', projectId: 'p',
    headBranch: 'a', baseBranch: 'main', additions: 1, deletions: 0, changedFiles: 1,
    mergeability: 'mergeable', capabilities: { review: {} }, viewerPermissions: {},
    comments: [{ id: 'c1', author: { login: 'me' }, body: 'hi', createdAt: 'now' }],
    reviewThreads: [{ id: 't1', path: 'a.ts', resolved: false,
      comments: [{ id: 'tc1', author: { login: 'rev' }, body: 'nit' }] }],
    commits: [{ sha: 'abc', subject: 'fix' }]
  });
  assert.equal(detail.activity.comments[0].author, 'me');
  assert.equal(detail.activity.threads[0].path, 'a.ts');
  assert.equal(detail.activity.commits[0].subject, 'fix');
});

test('PR activity tolerates null bodies and authors', () => {
  const activity = r5.pullRequestActivity({
    comments: [{ id: 'c1', author: null, body: null, createdAt: null }],
    reviewThreads: [{ id: 't1', path: null, resolved: false, comments: [{ id: 'x', author: null, body: null }] }],
    commits: [{ sha: 'abc', message: null }]
  });
  assert.equal(activity.comments[0].body, '');
  assert.equal(activity.comments[0].author, '');
  assert.equal(activity.threads[0].path, '');
  assert.equal(activity.commits[0].subject, '');
});

test('PR checks parse status, url and overall state', () => {
  const checks = r5.pullRequestChecks({
    state: 'passing', checks: [
      { name: 'ci', status: 'passing', description: 'ok', url: 'https://example/ci' },
      { name: 'lint', status: 'failing', description: null, url: null }
    ]
  });
  assert.equal(checks.state, 'passing');
  assert.equal(checks.checks[0].status, 'passing');
  assert.equal(checks.checks[1].url, '');
  assert.equal(r5.pullRequestChecks(null), undefined);
});

test('Markdown math keeps fractions, indexed roots and common functions', () => {
  assert.equal(md.mathText('\\dfrac{a}{b}'), '(a)/(b)');
  assert.equal(md.mathText('\\sqrt[3]{x}'), '³√(x)');
  assert.equal(md.mathText('\\log_2 n'), 'log₂ n');
  assert.equal(md.mathText('45^\\circ'), '45°');
  assert.equal(md.mathText('x \\in \\mathbb{R}'), 'x ∈ ℝ');
});

test('Markdown keeps single-line display math and following content', () => {
  const blocks = md.markdownDocument('$$x^2 + 1$$\n\nafter');
  assert.equal(blocks[0].kind, 'math');
  assert.equal(blocks[0].text, 'x^2 + 1');
  assert.equal(blocks[1].kind, 'paragraph');
  assert.equal(blocks[1].text, 'after');
});

test('U3: classifyChangedFile and isTestChangedFile match upstream rules across source, tests, mocks, generated and docs', () => {
  const cases = [
    ['src/contest.py', 'code', false],
    ['test/fixtures/pr.json', 'mocks', true],
    ['pnpm-lock.yaml', 'generated', false],
    ['convex/_generated/api.d.ts', 'generated', false],
    ['src/agent.eval.ts', 'tests', true],
    ['evals/title-generation.ts', 'tests', true],
    ['src/Button.stories.tsx', 'tests', true],
    ['src\\Button.STORIES.TSX', 'tests', true],
    ['src/Button.stories.generated.ts', 'generated', false],
    ['__mocks__/Button.stories.tsx', 'mocks', true],
    ['src/stories.ts', 'code', false],
    ['src/stories/Button.tsx', 'code', false],
    ['.storybook/main.ts', 'code', false],
    ['README.md', 'docs', false],
    ['tests/README.md', 'tests', true],
    ['src/FooTest.java', 'tests', true],
    ['src/Latest.java', 'code', false],
    ['requirements.txt', 'code', false]
  ];
  for (const [path, kind, isTest] of cases) {
    assert.equal(r5.classifyChangedFile(path), kind, path);
    assert.equal(r5.isTestChangedFile(path), isTest, path);
  }
});

test('U3: orderDiffFilesForReview orders dependencies before dependents, pairs tests, groups directories, and keeps symlinks', () => {
  const make = (name, additionLines = [], deletionLines = []) => ({ name, additionLines, deletionLines });
  const order = (list) => r5.orderDiffFilesForReview(list, (entry) => entry.name).map((entry) => entry.name);

  // Dependencies before dependents across relative climbs, index, .mts/.cts, queries, require, and cycles
  assert.deepEqual(
    order([make('src/ui/a.ts', ['import { b } from "../lib/b";']), make('src/lib/b.ts')]),
    ['src/lib/b.ts', 'src/ui/a.ts']
  );
  assert.deepEqual(
    order([make('src/a.ts', ['import { b } from "./lib";']), make('src/lib/index.ts')]),
    ['src/lib/index.ts', 'src/a.ts']
  );
  assert.deepEqual(
    order([make('a.mts', ['import { z } from "./z.mjs";']), make('z.mts')]),
    ['z.mts', 'a.mts']
  );
  assert.deepEqual(
    order([make('src/a.js', ['import Worker from "./z.js?worker";']), make('src/z.js')]),
    ['src/z.js', 'src/a.js']
  );
  assert.deepEqual(
    order([make('src/a.ts', ['const b = require("./b");', 'import "./c";']), make('src/b.ts'), make('src/c.ts')]),
    ['src/b.ts', 'src/c.ts', 'src/a.ts']
  );
  assert.deepEqual(
    order([make('src/b.ts', ['import { a } from "./a";']), make('src/a.ts', ['import { b } from "./b";'])]),
    ['src/a.ts', 'src/b.ts']
  );

  // Ambiguous last segment ignored rather than guessed
  assert.deepEqual(
    order([make('src/a.ts', ['import { b } from "~/somewhere/b";']), make('one/b.ts'), make('two/b.ts')]),
    ['one/b.ts', 'src/a.ts', 'two/b.ts']
  );

  // Tiers + paired tests + directory contiguity
  assert.deepEqual(
    order([
      make('pnpm-lock.yaml'),
      make('src/a.test.ts'),
      make('src/__tests__/b.ts'),
      make('src/a.ts', ['import { b } from "./b";']),
      make('src/b.ts'),
      make('dist/a.js')
    ]),
    ['src/b.ts', 'src/a.ts', 'src/__tests__/b.ts', 'src/a.test.ts', 'dist/a.js', 'pnpm-lock.yaml']
  );
  assert.deepEqual(
    order([
      make('server/device/Host.ts'),
      make('web/settings.ts'),
      make('server/ws.ts'),
      make('server/device/Host.test.ts'),
      make('web/settings.test.ts')
    ]),
    ['server/device/Host.ts', 'server/device/Host.test.ts', 'server/ws.ts', 'web/settings.ts', 'web/settings.test.ts']
  );
  assert.deepEqual(
    order([
      make('src/c.browser.test.tsx'),
      make('src/b.test.ts'),
      make('src/a.logic.test.ts'),
      make('src/c.tsx'),
      make('src/b.ts'),
      make('src/a.logic.ts')
    ]),
    ['src/a.logic.ts', 'src/b.ts', 'src/c.tsx', 'src/a.logic.test.ts', 'src/b.test.ts', 'src/c.browser.test.tsx']
  );

  // Duplicate path (file replaced by symlink) keeps both entries
  const deleted = make('AGENTS.md', [], ['# Agents']);
  const added = make('AGENTS.md', ['CLAUDE.md']);
  assert.deepEqual(
    r5.orderDiffFilesForReview([make('CLAUDE.md'), deleted, added], (entry) => entry.name),
    [deleted, added, make('CLAUDE.md')]
  );
});

test('U3: orderParsedDiffFilesForReview, filterDiffTestFiles, and Review/PR panels share t3HideTestFiles', async () => {
  const patch = [
    'diff --git a/pnpm-lock.yaml b/pnpm-lock.yaml',
    '--- a/pnpm-lock.yaml', '+++ b/pnpm-lock.yaml', '@@ -1 +1 @@', '-a', '+b',
    'diff --git a/src/app.test.ts b/src/app.test.ts',
    '--- a/src/app.test.ts', '+++ b/src/app.test.ts', '@@ -1 +1 @@', '-old', '+new',
    'diff --git a/src/app.ts b/src/app.ts',
    '--- a/src/app.ts', '+++ b/src/app.ts', '@@ -1 +1 @@', '+import { core } from "./core";',
    'diff --git a/src/core.ts b/src/core.ts',
    '--- a/src/core.ts', '+++ b/src/core.ts', '@@ -1 +1 @@', '+export const core = 1;'
  ].join('\n');
  const ordered = r5.orderParsedDiffFilesForReview(r5.parseDiff(patch));
  assert.deepEqual(ordered.map((f) => f.path), ['src/core.ts', 'src/app.ts', 'src/app.test.ts', 'pnpm-lock.yaml']);

  const shownAll = r5.filterDiffTestFiles(ordered, false);
  assert.equal(shownAll.hiddenCount, 0);
  assert.equal(shownAll.files.length, 4);

  const hiddenTests = r5.filterDiffTestFiles(ordered, true);
  assert.equal(hiddenTests.hiddenCount, 1);
  assert.deepEqual(hiddenTests.files.map((f) => f.path), ['src/core.ts', 'src/app.ts', 'pnpm-lock.yaml']);

  const onlyTests = r5.filterDiffTestFiles([ordered[2]], true);
  assert.equal(onlyTests.files.length, 0);
  assert.equal(onlyTests.hiddenCount, 1);

  for (const name of ['ReviewPanel', 'PullRequestsPanel']) {
    const src = await readFile(new URL(`../entry/src/main/ets/components/${name}.ets`, import.meta.url), 'utf8');
    assert.match(src, /@StorageProp\('t3HideTestFiles'\)/, name);
    assert.match(src, /orderParsedDiffFilesForReview/, name);
    assert.match(src, /filterDiffTestFiles/, name);
    assert.match(src, /隐藏测试文件/, name);
    assert.match(src, /仅变更了测试文件/, name);
    assert.match(src, /显示测试文件/, name);
  }
});
