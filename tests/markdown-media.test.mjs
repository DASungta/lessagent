import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { compile, data, markdownUrl } from './load-core.mjs';

const md = await import(markdownUrl);

const cacheSource = (await readFile(new URL('../entry/src/main/ets/services/MarkdownMediaCache.ets', import.meta.url), 'utf8'))
  .replace("'../protocol/Markdown'", JSON.stringify(markdownUrl));
const { MarkdownMediaCache } = await import(data(compile(cacheSource)));

test('Markdown parses standalone, indented, angle-bracket and unencoded-space host images', () => {
  const doc = [
    '1. First item',
    '',
    '   ![TunBox 5G 已连接](/Users/zhangyc/.local/share/network-ops/mobile-gateway-20261121/mate70-tunbox-connected.jpeg)',
    '',
    '2. Second item',
    '   ![Adjacent shot](/Users/zhangyc/Screen Shot 2026.png)',
    'Paragraph line',
    '![No blank line](</Users/zhangyc/My Folder/pic (1).png> "title")',
    '![Nested [alt] text](file:///Users/zhangyc/demo%20file.jpg)'
  ].join('\n');

  const blocks = md.markdownDocument(doc);
  const images = blocks.filter(block => block.kind === 'image');
  assert.equal(images.length, 4);
  assert.deepEqual(images[0], {
    ...images[0],
    alt: 'TunBox 5G 已连接',
    url: '/Users/zhangyc/.local/share/network-ops/mobile-gateway-20261121/mate70-tunbox-connected.jpeg'
  });
  assert.equal(images[1].alt, 'Adjacent shot');
  assert.equal(images[1].url, '/Users/zhangyc/Screen Shot 2026.png');
  assert.equal(images[2].alt, 'No blank line');
  assert.equal(images[2].url, '/Users/zhangyc/My Folder/pic (1).png');
  assert.equal(images[3].alt, 'Nested [alt] text');
  assert.equal(images[3].url, 'file:///Users/zhangyc/demo%20file.jpg');
});

test('classifyMarkdownMediaSource handles direct URLs, absolute paths, file URLs, relative paths and blocks unsafe schemes', () => {
  const remote = md.classifyMarkdownMediaSource('https://example.com/a.png?size=2', '/repo');
  assert.equal(remote.access, 'direct');
  assert.equal(remote.kind, 'image');
  assert.equal(remote.uri, 'https://example.com/a.png?size=2');

  const remoteVideo = md.classifyMarkdownMediaSource('https://example.com/clip.mp4#t=2', '/repo');
  assert.equal(remoteVideo.access, 'direct');
  assert.equal(remoteVideo.kind, 'video');

  const dataImg = md.classifyMarkdownMediaSource('data:image/png;base64,AAAA', '');
  assert.equal(dataImg.access, 'direct');
  assert.equal(dataImg.kind, 'image');

  const hostAbs = md.classifyMarkdownMediaSource('/Users/zhangyc/.local/share/a.jpeg', '/repo');
  assert.equal(hostAbs.access, 'environment');
  assert.equal(hostAbs.kind, 'image');
  assert.equal(hostAbs.path, '/Users/zhangyc/.local/share/a.jpeg');
  assert.equal(hostAbs.relative, false);

  const hostWithoutCwd = md.classifyMarkdownMediaSource('/Users/zhangyc/shot%201.png', '');
  assert.equal(hostWithoutCwd.access, 'environment');
  assert.equal(hostWithoutCwd.path, '/Users/zhangyc/shot 1.png');

  const fileUrl = md.classifyMarkdownMediaSource('file:///Users/zhangyc/shot%202.webp?v=1#frag', '');
  assert.equal(fileUrl.access, 'environment');
  assert.equal(fileUrl.path, '/Users/zhangyc/shot 2.webp');

  const winFileUrl = md.classifyMarkdownMediaSource('file:///C:/Users/me/demo.mp4', '');
  assert.equal(winFileUrl.access, 'environment');
  assert.equal(winFileUrl.kind, 'video');
  assert.equal(winFileUrl.path, 'C:/Users/me/demo.mp4');

  const rel = md.classifyMarkdownMediaSource('./docs/assets/logo.png', '/repo/project');
  assert.equal(rel.access, 'environment');
  assert.equal(rel.kind, 'image');
  assert.equal(rel.path, '/repo/project/docs/assets/logo.png');
  assert.equal(rel.relative, true);
  assert.equal(rel.displayPath, 'docs/assets/logo.png');

  const relNoRoot = md.classifyMarkdownMediaSource('docs/assets/logo.png', '');
  assert.equal(relNoRoot.access, 'blocked');

  for (const blocked of [
    '',
    '#anchor',
    '?query',
    'javascript:alert(1)',
    'data:text/html,<b>x</b>',
    'mailto:a@b.c',
    '//evil.example/a.png',
    'file://remote-host/share/a.png',
    '~/secret.png',
    '../outside.png',
    '/Users/me/audio.mp3',
    '/Users/me/bad\npath.png'
  ]) {
    assert.equal(md.classifyMarkdownMediaSource(blocked, '/repo').access, 'blocked', 'expected blocked: ' + blocked);
  }
});

test('markdownMediaAssetResource builds upstream media-file and draft-workspace-file payloads', () => {
  const hostAbs = md.classifyMarkdownMediaSource('/Users/zhangyc/shot.jpeg', '/repo');
  assert.deepEqual(md.markdownMediaAssetResource('thread-1', '/repo', hostAbs), {
    _tag: 'media-file',
    threadId: 'thread-1',
    path: '/Users/zhangyc/shot.jpeg'
  });

  const rel = md.classifyMarkdownMediaSource('docs/pic.png', '/repo');
  assert.deepEqual(md.markdownMediaAssetResource('thread-1', '/repo', rel), {
    _tag: 'media-file',
    threadId: 'thread-1',
    path: '/repo/docs/pic.png',
    hostOnly: true
  });

  assert.deepEqual(md.markdownMediaAssetResource('', '/repo', hostAbs), {
    _tag: 'draft-workspace-file',
    cwd: '/repo',
    path: '/Users/zhangyc/shot.jpeg'
  });

  assert.deepEqual(md.markdownMediaAssetResource('thread-1', '/repo', hostAbs, true), {
    _tag: 'media-file',
    threadId: 'thread-1',
    path: '/Users/zhangyc/shot.jpeg',
    disposition: 'attachment'
  });

  assert.throws(() => md.markdownMediaAssetResource('', '', hostAbs));
  assert.throws(() => md.markdownMediaAssetResource('thread-1', '/repo', md.classifyMarkdownMediaSource('javascript:1', '/repo')));
});

test('resolveRelativeMarkdownPath and safeAssetUrl handle doc-relative paths and reject bad URLs', () => {
  assert.equal(md.resolveRelativeMarkdownPath('docs/r8-progress.md', 'evidence/r8/shot.png'), 'docs/evidence/r8/shot.png');
  assert.equal(md.resolveRelativeMarkdownPath('docs/sub/guide.md', '../assets/logo.png'), 'docs/assets/logo.png');
  assert.equal(md.resolveRelativeMarkdownPath('docs/guide.md', '/Users/me/abs.png'), '/Users/me/abs.png');
  assert.equal(md.resolveRelativeMarkdownPath('docs/guide.md', 'https://a.b/c.png'), 'https://a.b/c.png');

  assert.equal(md.safeAssetUrl('https://t3-mac.dasungta.cn/', '/api/assets/tok/a.jpeg'), 'https://t3-mac.dasungta.cn/api/assets/tok/a.jpeg');
  assert.throws(() => md.safeAssetUrl('https://t3-mac.dasungta.cn', '//evil.com/x'));
  assert.throws(() => md.safeAssetUrl('https://t3-mac.dasungta.cn', 'http://evil.com/x'));
  assert.throws(() => md.safeAssetUrl('', '/api/assets/tok/a.jpeg'));
});

test('MarkdownMediaCache deduplicates in-flight requests, refreshes near expiry, prunes generations and never caches errors', async () => {
  const cache = new MarkdownMediaCache();
  const key = cache.key(1, 't1', '/repo', '/Users/me/a.jpeg');
  let calls = 0;
  let release;
  const fetcher = () => {
    calls += 1;
    return new Promise((resolve) => {
      release = () => resolve({
        url: 'https://host/api/assets/v' + calls,
        kind: 'image',
        displayPath: '/Users/me/a.jpeg',
        expiresAt: 1000000,
        width: 1200,
        height: 2400
      });
    });
  };

  const p1 = cache.resolve(1, key, fetcher, false, 500000);
  const p2 = cache.resolve(1, key, fetcher, false, 500000);
  assert.equal(calls, 1);
  release();
  const [r1, r2] = await Promise.all([p1, p2]);
  assert.equal(r1.url, 'https://host/api/assets/v1');
  assert.equal(r2.url, 'https://host/api/assets/v1');

  // Cached hit before expiry margin
  const r3 = await cache.resolve(1, key, async () => { calls += 1; throw new Error('should not fetch'); }, false, 900000);
  assert.equal(r3.url, 'https://host/api/assets/v1');
  assert.equal(calls, 1);

  // Near expiry (within 60s) forces refresh
  const r4 = await cache.resolve(1, key, async () => {
    calls += 1;
    return { url: 'https://host/api/assets/v2', kind: 'image', displayPath: '/Users/me/a.jpeg', expiresAt: 2000000, width: 10, height: 10 };
  }, false, 950000);
  assert.equal(r4.url, 'https://host/api/assets/v2');
  assert.equal(calls, 2);

  // Explicit refresh bypasses cache
  const r5 = await cache.resolve(1, key, async () => {
    calls += 1;
    return { url: 'https://host/api/assets/v3', kind: 'image', displayPath: '/Users/me/a.jpeg', expiresAt: 3000000, width: 10, height: 10 };
  }, true, 950000);
  assert.equal(r5.url, 'https://host/api/assets/v3');
  assert.equal(calls, 3);

  // Pruning old generation drops stale entries
  cache.pruneGeneration(2);
  assert.equal(cache.peek(key, 950000), undefined);

  // Failures are not cached
  const failKey = cache.key(2, 't1', '/repo', '/Users/me/missing.jpeg');
  await assert.rejects(cache.resolve(2, failKey, async () => { throw new Error('not found'); }, false, 100));
  const recovered = await cache.resolve(2, failKey, async () => ({
    url: 'https://host/api/assets/ok',
    kind: 'image',
    displayPath: '/Users/me/missing.jpeg',
    expiresAt: 5000000,
    width: 100,
    height: 100
  }), false, 200);
  assert.equal(recovered.url, 'https://host/api/assets/ok');
});
