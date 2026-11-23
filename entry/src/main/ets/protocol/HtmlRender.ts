import { record } from './Wire';

export const HTML_RENDER_TOOL_NAME = 'html_render';
export const HTML_RENDER_MIN_HEIGHT = 80;
export const HTML_RENDER_MAX_HEIGHT = 2000;
export const HTML_RENDER_MAX_FIT_HEIGHT = 20000;
export const HTML_RENDER_MAX_TITLE_LENGTH = 200;
export const HTML_RENDER_COLUMN_WIDTH = 728;

const MAX_MEASURED_HEIGHTS = 24;
const MAX_PARSED_BYTES = 16384;
const MAX_ENVELOPE_DEPTH = 4;
const MAX_ENVELOPE_NODES = 128;
const MAX_CONTENT_BLOCKS = 32;
const OPENCODE_CODE_MODE_TOOL_NAME = 'execute';
const TERMINAL_OUTPUT_MARKER = '\nCommand output:\n';
const HOST_CONTEXT_CHANGED_METHOD = 'ui/notifications/host-context-changed';
const THEME_FRAGMENT_KEY = 't3-theme';

const T3_MCP_SERVER_ALIASES: string[] = [
  't3-code',
  't3_code',
  't3code',
  't3-code-direct',
  't3_code_direct'
];

export interface HtmlRenderMeasuredHeight {
  width: number;
  height: number;
}

export interface HtmlRenderReference {
  attachmentId: string;
  title: string;
  height: number;
  heights: HtmlRenderMeasuredHeight[];
}

export interface HtmlRenderEntry {
  id: string;
  itemId: string;
  runId: string;
  render: HtmlRenderReference;
}

export interface HtmlRenderTheme {
  appearance: 'dark' | 'light';
  variables: Record<string, string>;
}

interface ResultReadBudget {
  remainingBytes: number;
  remainingNodes: number;
  exceeded: boolean;
}

interface ResultEnvelope {
  data?: Record<string, Object>;
  failed: boolean;
}

export function clampHtmlRenderHeight(height: number): number {
  return Math.min(HTML_RENDER_MAX_HEIGHT, Math.max(HTML_RENDER_MIN_HEIGHT, Math.round(height)));
}

function readMeasuredHeights(value: Object | undefined): HtmlRenderMeasuredHeight[] {
  if (!Array.isArray(value) || value.length === 0 || value.length > MAX_MEASURED_HEIGHTS) {
    return [];
  }
  const heights: HtmlRenderMeasuredHeight[] = [];
  for (const entry of value as Object[]) {
    if (!Array.isArray(entry) || entry.length !== 2) return [];
    const widthVal = (entry as Object[])[0];
    const heightVal = (entry as Object[])[1];
    if (typeof widthVal !== 'number' || !Number.isInteger(widthVal) || widthVal < 1 || widthVal > 10000) {
      return [];
    }
    if (typeof heightVal !== 'number' || !Number.isFinite(heightVal)) {
      return [];
    }
    heights.push({ width: widthVal, height: clampHtmlRenderHeight(heightVal) });
  }
  heights.sort((left: HtmlRenderMeasuredHeight, right: HtmlRenderMeasuredHeight) => left.width - right.width);
  return heights;
}

export function readHtmlRenderReference(value: Object | undefined): HtmlRenderReference | undefined {
  if (value === undefined || value === null || typeof value !== 'object' || Array.isArray(value)) {
    return undefined;
  }
  const row = value as Record<string, Object>;
  const attachmentId = row.attachmentId;
  const title = row.title;
  const height = row.height;
  if (
    typeof attachmentId !== 'string' ||
    attachmentId.length === 0 ||
    attachmentId.length > 256 ||
    typeof title !== 'string' ||
    typeof height !== 'number' ||
    !Number.isFinite(height)
  ) {
    return undefined;
  }
  const trimmedTitle = title.trim().slice(0, HTML_RENDER_MAX_TITLE_LENGTH) || 'HTML';
  return {
    attachmentId,
    title: trimmedTitle,
    height: clampHtmlRenderHeight(height),
    heights: readMeasuredHeights(row.heights)
  };
}

function measuredHeightForWidth(heights: HtmlRenderMeasuredHeight[], width: number): number {
  let above = -1;
  for (let index = 0; index < heights.length; index += 1) {
    if (heights[index].width >= width) {
      above = index;
      break;
    }
  }
  const high = above === -1 ? heights.length - 1 : above;
  const low = heights[high].width === width ? high : Math.max(0, high - 1);
  return Math.max(heights[low].height, heights[high].height);
}

export function htmlRenderFrameHeight(
  reference: HtmlRenderReference,
  width: number,
  contentHeight?: number
): number {
  if (contentHeight !== undefined && Number.isFinite(contentHeight) && contentHeight > 0) {
    return Math.min(
      HTML_RENDER_MAX_FIT_HEIGHT,
      Math.max(HTML_RENDER_MIN_HEIGHT, Math.ceil(contentHeight))
    );
  }
  const safeWidth = Number.isFinite(width) && width > 0 ? width : 360;
  if (!reference.heights || reference.heights.length === 0) {
    return clampHtmlRenderHeight(reference.height);
  }
  const cap = measuredHeightForWidth(reference.heights, HTML_RENDER_COLUMN_WIDTH) > reference.height
    ? reference.height
    : HTML_RENDER_MAX_HEIGHT;
  return clampHtmlRenderHeight(Math.min(cap, measuredHeightForWidth(reference.heights, safeWidth)));
}

export function htmlRenderFileName(title: string): string {
  const name = (title || '')
    .replace(/[\\/:*?"<>|\x00-\x1f\x7f]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 120)
    .trim();
  return (name || 'Page') + '.html';
}

function resolveT3McpToolName(rawName: string): string {
  const label = rawName.replace(/\s+(?:complete|completed)\s*$/i, '').trim();
  if (!label) return '';
  const mcpMatch = /^mcp__(.+?)__(.+)$/i.exec(label);
  if (mcpMatch) {
    const server = mcpMatch[1].toLowerCase();
    const tool = mcpMatch[2];
    return T3_MCP_SERVER_ALIASES.includes(server) ? tool : '';
  }
  const namespaceMatch = /^(?:@)?(t3[-_]code[-_]direct|t3-code|t3_code|t3code)(?:::|[.:/]|\s*·\s*)(.+)$/i.exec(label);
  if (namespaceMatch) {
    return namespaceMatch[2];
  }
  const prefixed = /^(?:mcp[-_]{1,2})?t3[-_ ]?code(?:__|[-_.:/ ])(.+)$/i.exec(label);
  const candidate = prefixed ? prefixed[1] : label;
  if (candidate === HTML_RENDER_TOOL_NAME) {
    return HTML_RENDER_TOOL_NAME;
  }
  if (/^t3-code-/i.test(label) && label.endsWith('_' + HTML_RENDER_TOOL_NAME)) {
    return HTML_RENDER_TOOL_NAME;
  }
  return candidate;
}

export function isHtmlRenderToolName(toolName: string): boolean {
  const trimmed = (toolName || '').trim();
  if (!trimmed) return false;
  if (trimmed === OPENCODE_CODE_MODE_TOOL_NAME) return true;
  return resolveT3McpToolName(trimmed) === HTML_RENDER_TOOL_NAME;
}

function estimateUtf8Length(value: string): number {
  let bytes = 0;
  for (let index = 0; index < value.length; index += 1) {
    const code = value.charCodeAt(index);
    if (code < 0x80) bytes += 1;
    else if (code < 0x800) bytes += 2;
    else if (code >= 0xd800 && code <= 0xdbff) {
      bytes += 4;
      index += 1;
    } else {
      bytes += 3;
    }
  }
  return bytes;
}

function readResultEnvelope(value: Object | undefined, budget: ResultReadBudget, depth: number = 0): ResultEnvelope {
  if (depth > MAX_ENVELOPE_DEPTH || budget.remainingNodes <= 0) {
    budget.exceeded = true;
    return { failed: false };
  }
  budget.remainingNodes -= 1;
  if (value === undefined || value === null) return { failed: false };
  if (typeof value === 'string') {
    if (value.length > budget.remainingBytes) {
      budget.exceeded = true;
      return { failed: false };
    }
    const bytes = estimateUtf8Length(value);
    if (bytes > budget.remainingBytes) {
      budget.exceeded = true;
      return { failed: false };
    }
    budget.remainingBytes -= bytes;
    try {
      const parsed: Object = JSON.parse(value) as Object;
      return readResultEnvelope(parsed, budget, depth + 1);
    } catch (_) {
      return { failed: false };
    }
  }
  if (Array.isArray(value)) {
    if (value.length > MAX_CONTENT_BLOCKS) {
      budget.exceeded = true;
      return { failed: false };
    }
    let data: Record<string, Object> | undefined = undefined;
    let failed = false;
    for (const block of value as Object[]) {
      let textField: Object | undefined = undefined;
      if (block !== null && block !== undefined && typeof block === 'object' && !Array.isArray(block)) {
        const blockRec = block as Record<string, Object>;
        const rawText = blockRec.text;
        if (rawText !== null && rawText !== undefined && typeof rawText === 'object' && !Array.isArray(rawText)) {
          const inner = rawText as Record<string, Object>;
          textField = inner.text !== undefined ? inner.text : rawText;
        } else {
          textField = rawText;
        }
      }
      const nested = readResultEnvelope(textField, budget, depth + 1);
      if (data === undefined && nested.data !== undefined) data = nested.data;
      if (nested.failed) failed = true;
      if (budget.exceeded) break;
    }
    return { data, failed };
  }
  if (typeof value !== 'object') return { failed: false };
  const row = value as Record<string, Object>;
  const failed =
    row.isError === true ||
    row.is_error === true ||
    row._tag === 'OrchestratorMcpFailure' ||
    (row.error !== undefined && row.error !== null);
  const terminal = typeof row.output === 'string' ? row.output : '';
  const marker = terminal.indexOf(TERMINAL_OUTPUT_MARKER);
  const content: Object | undefined =
    row.structuredContent !== undefined
      ? row.structuredContent
      : row.content !== undefined
        ? row.content
        : marker >= 0
          ? terminal.slice(marker + TERMINAL_OUTPUT_MARKER.length)
          : undefined;
  if (content !== undefined) {
    const nested = readResultEnvelope(content, budget, depth + 1);
    return { data: nested.data, failed: failed || nested.failed };
  }
  return { data: row, failed };
}

export function htmlRenderFromToolItem(item: Record<string, Object>): HtmlRenderReference | undefined {
  const type = typeof item.type === 'string' ? item.type : '';
  if (type && type !== 'dynamic_tool') return undefined;
  const status = typeof item.status === 'string' ? item.status : '';
  if (status && status !== 'completed') return undefined;
  const toolName = typeof item.toolName === 'string' ? item.toolName : '';
  const titleName = typeof item.title === 'string' ? item.title : '';
  if (!isHtmlRenderToolName(toolName) && !isHtmlRenderToolName(titleName)) {
    return undefined;
  }
  const budget: ResultReadBudget = {
    remainingBytes: MAX_PARSED_BYTES,
    remainingNodes: MAX_ENVELOPE_NODES,
    exceeded: false
  };
  const envelope = readResultEnvelope(item.output, budget);
  if (envelope.failed || budget.exceeded || !envelope.data) return undefined;
  return readHtmlRenderReference(envelope.data.htmlRender);
}

export function harmonyHtmlRenderTheme(dark: boolean): HtmlRenderTheme {
  const sans = '-apple-system, BlinkMacSystemFont, "HarmonyOS Sans", "Segoe UI", system-ui, sans-serif';
  const mono = '"SF Mono", "HarmonyOS Sans", Menlo, Consolas, "Liberation Mono", monospace';
  if (dark) {
    const vars: Record<string, string> = {};
    vars['--background'] = '#0a0a0a';
    vars['--foreground'] = '#f5f5f5';
    vars['--muted'] = '#1a1b1b';
    vars['--muted-foreground'] = '#838383';
    vars['--card'] = '#111111';
    vars['--card-foreground'] = '#f5f5f5';
    vars['--popover'] = '#161616';
    vars['--popover-foreground'] = '#f5f5f5';
    vars['--secondary'] = '#1a1b1b';
    vars['--secondary-foreground'] = '#f5f5f5';
    vars['--border'] = '#262626';
    vars['--input'] = '#1e1e1e';
    vars['--ring'] = '#346bf1';
    vars['--primary'] = '#f5f5f5';
    vars['--primary-foreground'] = '#0a0a0a';
    vars['--accent'] = '#5585f5';
    vars['--accent-foreground'] = '#ffffff';
    vars['--accent-surface'] = '#121b34';
    vars['--accent-surface-foreground'] = '#5585f5';
    vars['--destructive'] = '#ff6467';
    vars['--destructive-foreground'] = '#ffffff';
    vars['--destructive-surface'] = '#301214';
    vars['--warning'] = '#ffb900';
    vars['--warning-foreground'] = '#0a0a0a';
    vars['--warning-surface'] = '#312108';
    vars['--success'] = '#10b981';
    vars['--success-foreground'] = '#34d399';
    vars['--info'] = '#3b82f6';
    vars['--info-foreground'] = '#60a5fa';
    vars['--code-background'] = '#161616';
    vars['--code-foreground'] = '#f5f5f5';
    vars['--chart-1'] = '#5585f5';
    vars['--chart-2'] = '#2dd4bf';
    vars['--chart-3'] = '#fbbf24';
    vars['--chart-4'] = '#c084fc';
    vars['--chart-5'] = '#fb7185';
    vars['--chart-6'] = '#a3e635';
    vars['--radius'] = '0.625rem';
    vars['--font-sans'] = sans;
    vars['--font-mono'] = mono;
    return { appearance: 'dark', variables: vars };
  }
  const vars: Record<string, string> = {};
  vars['--background'] = '#fcfcfc';
  vars['--foreground'] = '#27272a';
  vars['--muted'] = '#f4f4f5';
  vars['--muted-foreground'] = '#6f6f79';
  vars['--card'] = '#ffffff';
  vars['--card-foreground'] = '#27272a';
  vars['--popover'] = '#ffffff';
  vars['--popover-foreground'] = '#27272a';
  vars['--secondary'] = '#efeff1';
  vars['--secondary-foreground'] = '#27272a';
  vars['--border'] = '#e4e4e7';
  vars['--input'] = '#d4d4d8';
  vars['--ring'] = '#1b4ed8';
  vars['--primary'] = '#27272a';
  vars['--primary-foreground'] = '#fcfcfc';
  vars['--accent'] = '#1b4ed8';
  vars['--accent-foreground'] = '#ffffff';
  vars['--accent-surface'] = '#e0e6f7';
  vars['--accent-surface-foreground'] = '#1b4ed8';
  vars['--destructive'] = '#c10007';
  vars['--destructive-foreground'] = '#ffffff';
  vars['--destructive-surface'] = '#fcebec';
  vars['--warning'] = '#bb4d00';
  vars['--warning-foreground'] = '#ffffff';
  vars['--warning-surface'] = '#fcf4e8';
  vars['--success'] = '#10b981';
  vars['--success-foreground'] = '#047857';
  vars['--info'] = '#3b82f6';
  vars['--info-foreground'] = '#1d4ed8';
  vars['--code-background'] = '#f4f4f5';
  vars['--code-foreground'] = '#27272a';
  vars['--chart-1'] = '#1b4ed8';
  vars['--chart-2'] = '#0d9488';
  vars['--chart-3'] = '#d97706';
  vars['--chart-4'] = '#9333ea';
  vars['--chart-5'] = '#e11d48';
  vars['--chart-6'] = '#65a30d';
  vars['--radius'] = '0.625rem';
  vars['--font-sans'] = sans;
  vars['--font-mono'] = mono;
  return { appearance: 'light', variables: vars };
}

export function htmlRenderThemeFragment(theme: HtmlRenderTheme): string {
  return '#' + THEME_FRAGMENT_KEY + '=' + encodeURIComponent(JSON.stringify(theme));
}

export function htmlRenderThemeMessageJson(theme: HtmlRenderTheme): string {
  const styles: Record<string, Object> = {};
  styles.variables = theme.variables;
  const params: Record<string, Object> = {};
  params.theme = theme.appearance;
  params.styles = styles;
  const payload: Record<string, Object> = {};
  payload.jsonrpc = '2.0';
  payload.method = HOST_CONTEXT_CHANGED_METHOD;
  payload.params = params;
  return JSON.stringify(payload);
}

export function htmlRenderFallbackCssScript(theme: HtmlRenderTheme): string {
  const keys = Object.keys(theme.variables);
  const parts: string[] = [];
  for (const key of keys) {
    parts.push(key + ':' + theme.variables[key]);
  }
  const varsCss = ':root{' + parts.join(';') + ';color-scheme:' + theme.appearance + ';}';
  const baseCss = 'html,body{background:var(--background);color:var(--foreground);font-family:var(--font-sans);}';
  return '(function(){' +
    'var d=document.documentElement,h=document.head||d;if(!h)return;' +
    'var el=document.getElementById("t3-fallback-theme");' +
    'if(!el){' +
    'if(getComputedStyle(d).getPropertyValue("--foreground").trim())return;' +
    'el=document.createElement("style");el.id="t3-fallback-theme";' +
    'if(h.firstChild)h.insertBefore(el,h.firstChild);else h.appendChild(el);' +
    '}' +
    'var usesT3=false;' +
    'var styles=document.querySelectorAll("style");' +
    'for(var i=0;i<styles.length;i++){' +
    'if(styles[i]===el)continue;' +
    'var txt=styles[i].textContent||"";' +
    'if(txt.indexOf("--foreground")>=0||txt.indexOf("--card")>=0||txt.indexOf("--chart-1")>=0){usesT3=true;break;}' +
    '}' +
    'el.textContent=' + JSON.stringify(varsCss) + '+(usesT3?' + JSON.stringify(baseCss) + ':"");' +
    '})()';
}

export function stripUrlFragment(url: string): string {
  const hash = url.indexOf('#');
  return hash >= 0 ? url.slice(0, hash) : url;
}

export function shouldAllowHtmlRenderNavigation(
  requestUrl: string,
  allowedUrl: string,
  isMainFrame: boolean
): boolean {
  if (!isMainFrame) return true;
  if (!requestUrl || !allowedUrl) return false;
  return stripUrlFragment(requestUrl) === stripUrlFragment(allowedUrl);
}

export function readHtmlRenderOverflow(raw: string): { x: boolean; y: boolean; contentHeight: number } | undefined {
  try {
    const parsed = record(JSON.parse(raw) as Object);
    if (typeof parsed.x !== 'boolean' || typeof parsed.y !== 'boolean') return undefined;
    const height = typeof parsed.height === 'number' && Number.isFinite(parsed.height) && parsed.height > 0
      ? Math.ceil(parsed.height)
      : 0;
    return { x: parsed.x, y: parsed.y, contentHeight: height };
  } catch (_) {
    return undefined;
  }
}
