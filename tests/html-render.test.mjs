import test from 'node:test';
import assert from 'node:assert/strict';
import { htmlRenderUrl, threadItemsUrl } from './load-core.mjs';

const hr = await import(htmlRenderUrl);
const ti = await import(threadItemsUrl);

test('htmlRenderFromToolItem parses completed html_render dynamic_tool outputs across MCP tool name variants', () => {
  const sampleRef = {
    attachmentId: '20f9ceb4-3680-4bbd-a137-e049b6992025-628a8ead-06c1-49e8-9d4c-5c7606a25444-html',
    title: 'T3 Code 安卓/移动端上游改动评估与鸿蒙同步清单',
    height: 1207,
    heights: [[320, 1933], [375, 1799], [430, 1732], [728, 1207], [1144, 1092]]
  };

  for (const toolName of [
    't3-code.html_render',
    'mcp__t3-code__html_render',
    't3-code-direct.html_render',
    't3-code::html_render',
    '@t3-code/html_render',
    't3-code-thread1_html_render',
    'execute',
    'html_render'
  ]) {
    const parsed = hr.htmlRenderFromToolItem({
      type: 'dynamic_tool',
      status: 'completed',
      toolName,
      output: { htmlRender: sampleRef }
    });
    assert.ok(parsed, 'expected parsed render for toolName=' + toolName);
    assert.equal(parsed.attachmentId, sampleRef.attachmentId);
    assert.equal(parsed.title, sampleRef.title);
    assert.equal(parsed.height, 1207);
    assert.equal(parsed.heights.length, 5);
  }

  // JSON string & MCP content block envelopes
  const fromJson = hr.htmlRenderFromToolItem({
    type: 'dynamic_tool',
    status: 'completed',
    toolName: 't3-code.html_render',
    output: JSON.stringify({ htmlRender: { attachmentId: 'att-json', title: 'Report', height: 420 } })
  });
  assert.equal(fromJson?.attachmentId, 'att-json');
  assert.equal(fromJson?.height, 420);

  const fromContent = hr.htmlRenderFromToolItem({
    type: 'dynamic_tool',
    status: 'completed',
    toolName: 'mcp__t3-code__html_render',
    output: { content: [{ type: 'text', text: JSON.stringify({ htmlRender: { attachmentId: 'att-mcp', title: 'Chart', height: 300 } }) }] }
  });
  assert.equal(fromContent?.attachmentId, 'att-mcp');

  // Non-completed, error, or unrelated tool names must not produce an inline render
  assert.equal(hr.htmlRenderFromToolItem({
    type: 'dynamic_tool',
    status: 'running',
    toolName: 't3-code.html_render',
    output: { htmlRender: sampleRef }
  }), undefined);
  assert.equal(hr.htmlRenderFromToolItem({
    type: 'dynamic_tool',
    status: 'completed',
    toolName: 't3-code.html_render',
    output: { isError: true, htmlRender: sampleRef }
  }), undefined);
  assert.equal(hr.htmlRenderFromToolItem({
    type: 'dynamic_tool',
    status: 'completed',
    toolName: 'other-server.html_render',
    output: { htmlRender: sampleRef }
  }), undefined);
});

test('htmlRenderFrameHeight matches upstream width interpolation, clamping, and live contentHeight override', () => {
  const ref = hr.readHtmlRenderReference({
    attachmentId: 'att-1',
    title: 'Eval',
    height: 1207,
    heights: [[320, 1933], [375, 1799], [430, 1732], [728, 1207], [1144, 1092]]
  });
  assert.ok(ref);
  assert.equal(hr.htmlRenderFrameHeight(ref, 320), 1933);
  assert.equal(hr.htmlRenderFrameHeight(ref, 360), 1933);
  assert.equal(hr.htmlRenderFrameHeight(ref, 375), 1799);
  assert.equal(hr.htmlRenderFrameHeight(ref, 728), 1207);
  assert.equal(hr.htmlRenderFrameHeight(ref, 1144), 1092);
  assert.equal(hr.htmlRenderFrameHeight(ref, 1200), 1207);
  assert.equal(hr.htmlRenderFrameHeight(ref, 360, 2400.2), 2401);
  assert.equal(hr.htmlRenderFrameHeight(ref, 360, 20), 80);
  assert.equal(hr.htmlRenderFrameHeight(ref, 360, 99999), 20000);

  // Without measured heights, clamps reference height to [80, 2000]
  const plain = hr.readHtmlRenderReference({ attachmentId: 'att-2', title: '', height: 5000 });
  assert.equal(plain?.title, 'HTML');
  assert.equal(hr.htmlRenderFrameHeight(plain, 375), 2000);
});

test('htmlRenderFileName, theme fragments, and navigation policy', () => {
  assert.equal(hr.htmlRenderFileName('T3 Code / 评估:清单'), 'T3 Code 评估 清单.html');
  assert.equal(hr.htmlRenderFileName('   '), 'Page.html');

  const dark = hr.harmonyHtmlRenderTheme(true);
  assert.equal(dark.appearance, 'dark');
  assert.equal(dark.variables['--background'], '#0a0a0a');
  const fragment = hr.htmlRenderThemeFragment(dark);
  assert.ok(fragment.startsWith('#t3-theme='));
  const decoded = JSON.parse(decodeURIComponent(fragment.slice('#t3-theme='.length)));
  assert.equal(decoded.appearance, 'dark');
  assert.equal(decoded.variables['--foreground'], '#f5f5f5');

  const msg = JSON.parse(hr.htmlRenderThemeMessageJson(hr.harmonyHtmlRenderTheme(false)));
  assert.equal(msg.jsonrpc, '2.0');
  assert.equal(msg.method, 'ui/notifications/host-context-changed');
  assert.equal(msg.params.theme, 'light');
  assert.equal(msg.params.styles.variables['--background'], '#fcfcfc');

  const fallbackDark = hr.htmlRenderFallbackCssScript(dark);
  assert.ok(fallbackDark.includes('t3-fallback-theme'));
  assert.ok(fallbackDark.includes('--chart-1:#5585f5'));
  assert.ok(fallbackDark.includes('color-scheme:dark'));
  const fallbackLight = hr.htmlRenderFallbackCssScript(hr.harmonyHtmlRenderTheme(false));
  assert.ok(fallbackLight.includes('--chart-1:#1b4ed8'));
  assert.ok(fallbackLight.includes('color-scheme:light'));

  assert.equal(hr.shouldAllowHtmlRenderNavigation('https://host/api/assets/tok#t3-theme=1', 'https://host/api/assets/tok', true), true);
  assert.equal(hr.shouldAllowHtmlRenderNavigation('https://host/api/assets/tok#section', 'https://host/api/assets/tok', true), true);
  assert.equal(hr.shouldAllowHtmlRenderNavigation('https://evil.example/x', 'https://host/api/assets/tok', true), false);
  assert.equal(hr.shouldAllowHtmlRenderNavigation('https://cdn.example/frame', 'https://host/api/assets/tok', false), true);
});

test('groupWorkByMessage promotes completed html_render out of collapsed steps into htmlRenders', () => {
  const runs = [{
    id: 'run-3',
    status: 'completed',
    startedAt: '2026-11-22T14:03:53.000Z',
    completedAt: '2026-11-22T14:04:39.000Z'
  }];
  const items = [
    { id: 'u1', type: 'user_message', messageId: 'u1', runId: 'run-3', text: 'eval' },
    { id: 'r1', type: 'reasoning', status: 'completed', runId: 'run-3', text: 'thinking' },
    {
      id: 'tool-html',
      type: 'dynamic_tool',
      status: 'completed',
      runId: 'run-3',
      toolName: 't3-code.html_render',
      output: {
        htmlRender: {
          attachmentId: 'att-eval-html',
          title: 'Android Eval Report',
          height: 1207,
          heights: [[375, 1799], [728, 1207]]
        }
      }
    },
    { id: 'a1', type: 'assistant_message', messageId: 'a1', runId: 'run-3', text: 'Done' }
  ];
  const messages = [
    { id: 'u1', role: 'user', text: 'eval', streaming: false, runId: 'run-3' },
    { id: 'a1', role: 'assistant', text: 'Done', streaming: false, runId: 'run-3' }
  ];

  const work = ti.groupWorkByMessage(items, runs, [], messages);
  const group = work.before.a1;
  assert.ok(group, 'expected before group on assistant message');
  assert.equal(group.items.length, 1);
  assert.equal(group.items[0].id, 'r1');
  assert.equal(group.htmlRenders.length, 1);
  assert.equal(group.htmlRenders[0].render.attachmentId, 'att-eval-html');
  assert.equal(group.htmlRenders[0].render.title, 'Android Eval Report');
  assert.equal(ti.activityLines(items).some(line => line.itemId === 'tool-html'), false);

  // Standalone html_render with no other steps still surfaces without empty work chrome
  const soloItems = [
    { id: 'u2', type: 'user_message', messageId: 'u2', runId: 'run-4', text: 'chart' },
    {
      id: 'tool-solo',
      type: 'dynamic_tool',
      status: 'completed',
      runId: 'run-4',
      toolName: 't3-code.html_render',
      output: { htmlRender: { attachmentId: 'att-solo', title: 'Solo Chart', height: 320 } }
    }
  ];
  const soloWork = ti.groupWorkByMessage(soloItems, [{ id: 'run-4', status: 'completed' }], [], [
    { id: 'u2', role: 'user', text: 'chart', streaming: false, runId: 'run-4' }
  ]);
  assert.ok(soloWork.tail, 'expected tail group for standalone html_render');
  assert.equal(soloWork.tail.htmlRenders.length, 1);
  assert.equal(soloWork.tail.items.length, 0);
  assert.equal(soloWork.tail.runMeta, undefined);
});
