import { optionalRecord, record } from './Wire';

export const MCP_APP_PROTOCOL_VERSION = '2026-01-26';
export const MCP_APP_INLINE_MIN_HEIGHT = 120;
export const MCP_APP_INLINE_MAX_HEIGHT = 560;

export interface McpSignInNoticeView {
  id: string;
  threadId: string;
  providerThreadId: string;
  server: string;
  message: string;
  level: string;
}

export interface McpSignInStartResult {
  authorizationUrl: string;
  signedInAt: string;
}

export interface McpSignInCompleteResult {
  signedInAt: string;
}

export interface McpAppReference {
  attachmentId: string;
  server: string;
  tool: string;
  resourceUri: string;
  title: string;
}

export interface McpAppEntry {
  id: string;
  itemId: string;
  runId: string;
  revision: string;
  app: McpAppReference;
}

export interface McpAppToolInfoResult {
  callable: boolean;
  readOnly: boolean;
  title: string;
  tool: Object | undefined;
}

export interface McpAppCallToolResult {
  content: Object[];
  structuredContent?: Object;
  isError?: boolean;
  _meta?: Object;
}

function claudeMcpToolName(server: string, tool: string): string {
  return 'mcp__' + server.replace(/[^a-zA-Z0-9_-]/g, '_') + '__' + tool.replace(/[^a-zA-Z0-9_-]/g, '_');
}

function readMcpAppRef(value: Object | undefined): McpAppReference | undefined {
  const row = optionalRecord(value);
  if (!row) return undefined;
  const attachmentId = typeof row.attachmentId === 'string' ? row.attachmentId.trim() : '';
  const server = typeof row.server === 'string' ? row.server.trim() : '';
  const tool = typeof row.tool === 'string' ? row.tool.trim() : '';
  const resourceUri = typeof row.resourceUri === 'string' ? row.resourceUri.trim() : '';
  if (!attachmentId || !server || !tool || !resourceUri.startsWith('ui://')) return undefined;
  const title = typeof row.title === 'string' && row.title.trim() ? row.title.trim() : (server + ' · ' + tool);
  return { attachmentId, server, tool, resourceUri, title };
}

/**
 * Extracts a verified MCP App reference from a `dynamic_tool` item, rejecting outputs whose
 * declared `server`/`tool` do not match the item's actual `toolName`.
 */
export function mcpAppFromToolItem(item: Record<string, Object>): McpAppReference | undefined {
  if (item.type !== 'dynamic_tool') return undefined;
  const toolName = typeof item.toolName === 'string' ? item.toolName.trim() : '';
  if (!toolName) return undefined;
  const output = optionalRecord(item.output);
  if (!output) return undefined;
  const ref = readMcpAppRef(output.t3McpApp);
  if (!ref) return undefined;
  if (toolName !== ref.server + '.' + ref.tool && toolName !== claudeMcpToolName(ref.server, ref.tool)) {
    return undefined;
  }
  return ref;
}

export function extractMcpAppEntries(items: Record<string, Object>[]): McpAppEntry[] {
  const result: McpAppEntry[] = [];
  const seen: Set<string> = new Set();
  for (const item of items) {
    const app = mcpAppFromToolItem(item);
    if (!app) continue;
    const itemId = typeof item.id === 'string' ? item.id.trim() : '';
    if (!itemId || seen.has(itemId)) continue;
    seen.add(itemId);
    const runId = typeof item.runId === 'string' ? item.runId : '';
    const revision = typeof item.updatedAt === 'string' ? item.updatedAt : (typeof item.status === 'string' ? item.status : '');
    result.push({ id: itemId, itemId, runId, revision, app });
  }
  return result;
}

export function mcpAppFileName(app: McpAppReference): string {
  const safe = (app.server + '-' + app.tool).replace(/[^A-Za-z0-9._-]+/g, '_').slice(0, 80) || 'mcp-app';
  return safe + '.html';
}

export function mcpAppAssetResource(app: McpAppReference): Record<string, Object> {
  return {
    _tag: 'attachment',
    attachmentId: app.attachmentId,
    fileName: mcpAppFileName(app),
    mimeType: 'text/html',
    disposition: 'inline',
    renderIntent: 'mcp-app'
  };
}

export function clampMcpAppInlineHeight(height: number): number {
  if (!Number.isFinite(height) || height <= 0) return MCP_APP_INLINE_MAX_HEIGHT;
  return Math.min(MCP_APP_INLINE_MAX_HEIGHT, Math.max(MCP_APP_INLINE_MIN_HEIGHT, Math.round(height)));
}

function resolveProviderThreadId(
  item: Record<string, Object>,
  details: Record<string, Object>,
  providerThreads: Record<string, Object>[]
): string {
  if (typeof item.providerThreadId === 'string' && item.providerThreadId.trim()) {
    return item.providerThreadId.trim();
  }
  if (typeof details.activeProviderThreadId === 'string' && details.activeProviderThreadId.trim()) {
    return details.activeProviderThreadId.trim();
  }
  for (let i = providerThreads.length - 1; i >= 0; i -= 1) {
    const row = providerThreads[i];
    if (typeof row.id === 'string' && row.id.trim()) return row.id.trim();
  }
  return '';
}

export function parseMcpSignInNotices(
  items: Record<string, Object>[],
  threadId: string,
  details: Record<string, Object> = {},
  providerThreads: Record<string, Object>[] = []
): McpSignInNoticeView[] {
  const result: McpSignInNoticeView[] = [];
  const seenServers: Set<string> = new Set();
  for (let i = items.length - 1; i >= 0; i -= 1) {
    const item = items[i];
    if (item.type !== 'system_notice') continue;
    const mcpSignIn = optionalRecord(item.mcpSignIn);
    if (!mcpSignIn) continue;
    const server = typeof mcpSignIn.server === 'string' ? mcpSignIn.server.trim() : '';
    const id = typeof item.id === 'string' ? item.id.trim() : '';
    if (!server || !id) continue;
    const key = server.toLowerCase();
    if (seenServers.has(key)) continue;
    seenServers.add(key);
    const providerThreadId = resolveProviderThreadId(item, details, providerThreads);
    result.push({
      id,
      threadId: typeof item.threadId === 'string' && item.threadId.trim() ? item.threadId.trim() : threadId,
      providerThreadId,
      server,
      message: typeof item.message === 'string' ? item.message : ('需要登录到 ' + server),
      level: typeof item.level === 'string' ? item.level : 'warning'
    });
  }
  result.reverse();
  return result;
}

export function mcpSignInStartPayload(threadId: string, providerThreadId: string, server: string): Record<string, Object> {
  const tid = threadId.trim();
  const ptid = providerThreadId.trim();
  const srv = server.trim();
  if (!tid || !ptid || !srv || srv.length > 256) throw new Error('MCP 登录参数无效');
  return { threadId: tid, providerThreadId: ptid, server: srv };
}

export function parseMcpSignInStartResult(value: Object): McpSignInStartResult {
  const row = record(value);
  const authUrl = typeof row.authorizationUrl === 'string' ? row.authorizationUrl.trim() : '';
  if (authUrl && !/^https?:\/\//i.test(authUrl)) {
    throw new Error('MCP 授权地址无效');
  }
  return {
    authorizationUrl: authUrl,
    signedInAt: typeof row.signedInAt === 'string' ? row.signedInAt : ''
  };
}

export function mcpSignInCompletePayload(
  threadId: string,
  providerThreadId: string,
  server: string,
  callbackUrl: string
): Record<string, Object> {
  const tid = threadId.trim();
  const ptid = providerThreadId.trim();
  const srv = server.trim();
  const cb = callbackUrl.trim();
  if (!tid || !ptid || !srv || srv.length > 256) throw new Error('MCP 登录参数无效');
  if (!cb || cb.length > 16384 || !/^https?:\/\//i.test(cb)) {
    throw new Error('请粘贴以 http:// 或 https:// 开头的完整回调地址');
  }
  return { threadId: tid, providerThreadId: ptid, server: srv, callbackUrl: cb };
}

export function parseMcpSignInCompleteResult(value: Object): McpSignInCompleteResult {
  const row = record(value);
  return { signedInAt: typeof row.signedInAt === 'string' ? row.signedInAt : '' };
}

export function parseMcpAppToolInfo(value: Object): McpAppToolInfoResult {
  const row = record(value);
  return {
    callable: row.callable === true,
    readOnly: row.readOnly === true,
    title: typeof row.title === 'string' ? row.title : '',
    tool: row.tool
  };
}

export function parseMcpAppCallToolResult(value: Object): McpAppCallToolResult {
  const row = record(value);
  const res: McpAppCallToolResult = {
    content: Array.isArray(row.content) ? (row.content as Object[]) : []
  };
  if (row.structuredContent !== undefined) res.structuredContent = row.structuredContent;
  if (typeof row.isError === 'boolean') res.isError = row.isError as boolean;
  if (row._meta !== undefined) res._meta = row._meta;
  return res;
}

export function buildMcpAppJsonRpcResult(id: string | number, result: Object): string {
  const envelope: Record<string, Object> = {
    jsonrpc: '2.0',
    id,
    result
  };
  return JSON.stringify(envelope);
}

export function buildMcpAppJsonRpcError(id: string | number, code: number, message: string): string {
  const errObj: Record<string, Object> = { code, message };
  const envelope: Record<string, Object> = {
    jsonrpc: '2.0',
    id,
    error: errObj
  };
  return JSON.stringify(envelope);
}

export function buildMcpAppJsonRpcNotification(method: string, params: Object): string {
  const envelope: Record<string, Object> = {
    jsonrpc: '2.0',
    method,
    params
  };
  return JSON.stringify(envelope);
}

export function buildMcpAppHostContext(
  appearance: 'dark' | 'light',
  variables: Record<string, string>,
  displayMode: 'inline' | 'fullscreen',
  width: number,
  height: number,
  toolDefinition?: Object
): Record<string, Object> {
  const styles: Record<string, Object> = { variables };
  const dims: Record<string, Object> = displayMode === 'fullscreen'
    ? { width: Math.max(240, Math.round(width)), height: Math.max(240, Math.round(height)) }
    : { width: Math.max(240, Math.round(width)), maxHeight: MCP_APP_INLINE_MAX_HEIGHT };
  const caps: Record<string, Object> = { touch: true, hover: false };
  const ctx: Record<string, Object> = {
    theme: appearance,
    styles,
    displayMode,
    availableDisplayModes: ['inline', 'fullscreen'],
    containerDimensions: dims,
    platform: 'mobile',
    deviceCapabilities: caps
  };
  if (toolDefinition !== undefined) {
    const info: Record<string, Object> = { tool: toolDefinition };
    ctx.toolInfo = info;
  }
  return ctx;
}

/**
 * Injected into ArkWeb MCP App pages so standard `window.parent.postMessage(...)` calls
 * route directly to the native `window.__t3McpHost.post(json)` bridge.
 */
export const MCP_APP_BRIDGE_SHIM_JS = '(function(){' +
  'if(window.__t3McpBridgeInstalled)return;' +
  'window.__t3McpBridgeInstalled=true;' +
  'var origParent=window.parent;' +
  'var forward=function(msg){' +
  'try{if(window.__t3McpHost&&typeof window.__t3McpHost.post==="function"){' +
  'window.__t3McpHost.post(typeof msg==="string"?msg:JSON.stringify(msg));}}catch(e){}' +
  '};' +
  'try{Object.defineProperty(window,"parent",{configurable:true,value:{postMessage:function(m){forward(m);}}});}catch(e){' +
  'if(origParent&&origParent===window){window.postMessage=(function(orig){return function(m,o){' +
  'if(m&&typeof m==="object"&&m.jsonrpc==="2.0"&&typeof m.method==="string"&&!m.__fromHost){forward(m);return;}' +
  'return orig.call(window,m,o);};})(window.postMessage);}}' +
  'window.__t3McpReceive=function(raw){' +
  'try{var data=typeof raw==="string"?JSON.parse(raw):raw;' +
  'if(data&&typeof data==="object")data.__fromHost=true;' +
  'window.dispatchEvent(new MessageEvent("message",{data:data,origin:window.location.origin}));}catch(e){}' +
  '};})();';
