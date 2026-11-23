import test from 'node:test';
import assert from 'node:assert/strict';
import { filesUrl, markdownLinksUrl, markdownUrl } from './load-core.mjs';

const ml = await import(markdownLinksUrl);
const files = await import(filesUrl);
const md = await import(markdownUrl);

test('parseThreadLinkHref parses v1, v2 (including percent-encoded subagent ids), and hosted links', () => {
  const v2 = ml.parseThreadLinkHref(
    't3-thread://v2/dc57a033-de32-439e-97b6-65dcdb2d16ae/thread:delegated-task:command%3Amcp%3A816f26d7'
  );
  assert.deepEqual(v2, {
    environmentId: 'dc57a033-de32-439e-97b6-65dcdb2d16ae',
    threadId: 'thread:delegated-task:command%3Amcp%3A816f26d7',
    decodedThreadId: 'thread:delegated-task:command:mcp:816f26d7'
  });

  const v1 = ml.parseThreadLinkHref('<t3-thread://v1/thread_abc>');
  assert.deepEqual(v1, { environmentId: '', threadId: 'thread_abc', decodedThreadId: 'thread_abc' });

  const hosted = ml.parseThreadLinkHref('https://app.t3.codes/threads/env-1/thread%3A1');
  assert.deepEqual(hosted, { environmentId: 'env-1', threadId: 'thread:1', decodedThreadId: 'thread:1' });

  assert.equal(ml.parseThreadLinkHref('t3-thread://v2/missing-slash'), undefined);
  assert.equal(ml.parseThreadLinkHref('https://example.com/threads/a/b'), undefined);
});

test('classifyMarkdownLink classifies external, mailto, thread, local/workspace file links, and blocks unsafe schemes', () => {
  const htmlFile = ml.classifyMarkdownLink(
    '/Users/zhangyc/.t3/userdata/providers/antigravity/abc/scratch/t3code-android-upstream-eval.html'
  );
  assert.equal(htmlFile.kind, 'file');
  assert.equal(htmlFile.file.isAbsolute, true);
  assert.equal(htmlFile.file.path, '/Users/zhangyc/.t3/userdata/providers/antigravity/abc/scratch/t3code-android-upstream-eval.html');
  assert.equal(htmlFile.file.line, 0);

  const repoDir = ml.classifyMarkdownLink('/Users/zhangyc/WorkStation/Projects/IdeaProjects/t3code');
  assert.equal(repoDir.kind, 'file');
  assert.equal(repoDir.file.isAbsolute, true);
  assert.equal(repoDir.file.path, '/Users/zhangyc/WorkStation/Projects/IdeaProjects/t3code');

  const withLine = ml.classifyMarkdownLink('file:///Users/zhangyc/repo/src/Index.ets:42:7');
  assert.equal(withLine.kind, 'file');
  assert.equal(withLine.file.path, '/Users/zhangyc/repo/src/Index.ets');
  assert.equal(withLine.file.line, 42);
  assert.equal(withLine.file.column, 7);

  const withHashLine = ml.classifyMarkdownLink('entry/src/main/ets/pages/Index.ets#L2713');
  assert.equal(withHashLine.kind, 'file');
  assert.equal(withHashLine.file.isAbsolute, false);
  assert.equal(withHashLine.file.path, 'entry/src/main/ets/pages/Index.ets');
  assert.equal(withHashLine.file.line, 2713);

  assert.equal(ml.classifyMarkdownLink('https://github.com/pingdotgg/t3code').kind, 'external');
  assert.equal(ml.classifyMarkdownLink('mailto:test@example.com').kind, 'mailto');
  assert.equal(ml.classifyMarkdownLink('t3-thread://v2/env-1/thread-1').kind, 'thread');

  for (const unsafe of [
    '',
    '#anchor',
    'javascript:alert(1)',
    'data:text/html,<h1>x</h1>',
    'file://evil.example/etc/passwd',
    '\\\\evil-server\\share\\file.html',
    '//evil.example/file.html',
    'ftp://example.com/a.html'
  ]) {
    assert.equal(ml.classifyMarkdownLink(unsafe).kind, 'blocked', 'expected blocked: ' + unsafe);
  }
});

test('resolveFileLinkForWorkspace maps inside-workspace paths to relative and keeps outside-workspace host paths intact', () => {
  const cwd = '/Users/zhangyc/WorkStation/Projects/Other/t3code-harmony';

  const inside = ml.resolveFileLinkForWorkspace(cwd, ml.parseMarkdownFileLink(cwd + '/docs/design/style-guide.html'));
  assert.equal(inside.path, 'docs/design/style-guide.html');
  assert.equal(inside.isOutsideWorkspace, false);

  const outside = ml.resolveFileLinkForWorkspace(
    cwd,
    ml.parseMarkdownFileLink('/Users/zhangyc/.t3/userdata/scratch/t3code-android-upstream-eval.html')
  );
  assert.equal(outside.path, '/Users/zhangyc/.t3/userdata/scratch/t3code-android-upstream-eval.html');
  assert.equal(outside.isOutsideWorkspace, true);

  const rel = ml.resolveFileLinkForWorkspace(cwd, ml.parseMarkdownFileLink('./entry/src/main/ets/pages/Index.ets:10'));
  assert.equal(rel.path, 'entry/src/main/ets/pages/Index.ets');
  assert.equal(rel.absolutePath, cwd + '/entry/src/main/ets/pages/Index.ets');
  assert.equal(rel.line, 10);
  assert.equal(rel.isOutsideWorkspace, false);

  // Relative traversal escaping workspace is rejected
  assert.equal(ml.resolveFileLinkForWorkspace(cwd, ml.parseMarkdownFileLink('../../etc/passwd')), undefined);
});

test('Files.isHtml and hostOrWorkspaceAssetResource handle both workspace and outside-workspace HTML files safely', () => {
  assert.equal(files.isHtml('report.html'), true);
  assert.equal(files.isHtml('REPORT.HTM'), true);
  assert.equal(files.isHtml('README.md'), false);

  assert.deepEqual(
    files.hostOrWorkspaceAssetResource('thread-1', '/repo', '/Users/me/scratch/eval.html', false),
    { _tag: 'media-file', threadId: 'thread-1', path: '/Users/me/scratch/eval.html' }
  );
  assert.deepEqual(
    files.hostOrWorkspaceAssetResource('thread-1', '/repo', '/Users/me/scratch/eval.html', true),
    { _tag: 'media-file', threadId: 'thread-1', path: '/Users/me/scratch/eval.html', disposition: 'attachment' }
  );
  assert.deepEqual(
    files.hostOrWorkspaceAssetResource('thread-1', '/repo', 'docs/design/style-guide.html', false),
    { _tag: 'workspace-file', threadId: 'thread-1', path: '/repo/docs/design/style-guide.html' }
  );
  assert.deepEqual(
    files.hostOrWorkspaceAssetResource('', '/repo', '/Users/me/scratch/eval.html', false),
    { _tag: 'draft-workspace-file', cwd: '/repo', path: '/Users/me/scratch/eval.html' }
  );
  assert.throws(() => files.hostOrWorkspaceAssetResource('thread-1', '/repo', '\\\\host\\share\\x.html'));
  assert.throws(() => files.hostOrWorkspaceAssetResource('thread-1', '/repo', '../secret.html'));
});

test('Markdown inlineSpans parses t3-thread autolinks and preserves file link hrefs', () => {
  const spans = md.inlineSpans(
    'See [eval.html](/Users/me/eval.html) and <t3-thread://v2/env-1/t-1>.'
  );
  const links = spans.filter(s => s.kind === 'link');
  assert.equal(links.length, 2);
  assert.equal(links[0].text, 'eval.html');
  assert.equal(links[0].href, '/Users/me/eval.html');
  assert.equal(links[1].href, 't3-thread://v2/env-1/t-1');
});
