import { DeviceStreamAccess, safeDeviceHubBase } from '../protocol/DevicePreview';
import { ModelSelection, TaskSettings, launchTask, validateTaskSettings, queueCommand } from '../protocol/Composer';
import { BranchView, branches, branchListInput, ComposerContextRecord, ComposerDraft, contextPayload,
  DraftAttachment, DraftWorkspace, draftSettings, emptyWorkspace, forceStopCommand, forkThreadCommand,
  guestShare, GuestShareView, launchWorkspace, promoteCommand, refreshStatusInput, switchBranchInput,
  SubagentView, subagents, BackgroundTaskView, tokenUsage, TokenUsage, attachmentLimitError,
  uploadAttachmentTarget, attachmentRecord, latestExecutedRun } from '../protocol/R4';
import {
  derivePendingBackgroundWork,
  deriveThreadTurnSubagents,
  PendingBackgroundTaskView,
  PendingBackgroundWorkView,
  presentPendingBackgroundWork,
  ThreadTurnSubagentsView
} from '../protocol/FloatingStatus';
import { http, webSocket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { bootstrapForm, createThread, DPOP_ACCESS_TOKEN_REFRESH_SKEW_MS, objects, record, RpcClient,
  RpcFailure, RpcSender, sendMessage, serverBase, socketUrl, text, ThreadState, tokenRenewalForm,
  validateDescriptor, validateServerConfig } from '../protocol/Wire';
import { dpopSigner } from './Dpop';
import { directHostKind, shouldBypassSystemProxy, urlHostname } from '../protocol/Hosts';

import { CachedShellEntry, ShellState, ModelChoice, models, SavedSession, SessionStorage, stopCommand, secretAnswer,
  secretValuesAnswer, parseSecretFields, mapSecretRequestError,
  secretReferenceAnswer, dismissInputCommand, respondCommand, RecoveryState, RecoveryStorage,
  recoveryState, Attachment, PeerLinkView, peerAccessGranted, peerLinkViews,
  LinkAnswer, linkAnswerPayload, peerPairingScopes } from '../protocol/Core';
import { contentMatches, ContentMatch, contentSearchInput, listEntriesInput, readFileInput,
  WorkspaceEntry, workspaceAssetResource, workspaceEntries, workspaceFile, WorkspaceFile } from '../protocol/Files';
import { classifyMarkdownMediaSource, markdownMediaAssetResource, ResolvedMarkdownMedia,
  safeAssetUrl } from '../protocol/Markdown';
import { MarkdownMediaCache } from './MarkdownMediaCache';
import { actionInput, applyVcsStatus, commentInput, emptyVcs, firstPullRequestCursor, gitActionInput, listRefs,
  parsePullRequestCursors, pullInput, pullRequestActivity, PullRequestActivityView, pullRequestDetail, PullRequestDetailView,
  pullRequestChecks, PullRequestChecksView, pullRequestGuide, PullRequestGuideView,
  pullRequestListInput, pullRequestRef, pullRequestRows, PullRequestPage, PullRequestRow, refs, RefView,
  ReviewerSelection, LinkedPullRequestView, linkedPullRequests, linkedPullRequestCommand,
  reviewPreview, reviewPreviewInput, ReviewPreview, reviewSubmitInput, switchRefInput, VcsView,
  vcsWatchInput } from '../protocol/R5';
import { applyAuthAccessEvent, AuthAccess } from '../protocol/Cloud';
import { capability, objectBool, objectText, offeredProvidersFrom, ProjectView, sessionAllows,
  snoozeSettingsFrom, SnoozePresetSetting } from '../protocol/Projects';

class NativeSender implements RpcSender {
  private socket: webSocket.WebSocket;
  constructor(socket: webSocket.WebSocket) { this.socket = socket; }
  async send(frame: string): Promise<void> {
    try {
      if (!await this.socket.send(frame)) throw new Error('发送失败');
    } catch (_) {
      throw new Error('发送失败');
    }
  }
}

class HttpFailure extends Error {
  status: number;
  constructor(status: number) {
    super(status === 401 || status === 403 ? '鉴权失败或权限不足，请检查配对凭据' :
      status === 426 ? '服务端协议不兼容' : 'HTTP 请求失败（' + status + '）');
    this.status = status;
  }
}

class ServerConfigIncompatibleError extends Error {
  constructor(message: string) {
    super(message);
  }
}

class ServerConfigUpdateError extends Error {
  constructor(message: string) {
    super(message);
  }
}

function withDirectProxyPolicy(target: string, options: http.HttpRequestOptions): http.HttpRequestOptions {
  if (shouldBypassSystemProxy(target)) options.usingProxy = false;
  return options;
}

function formatHttpNetworkError(path: string, base: string, code: number | undefined): string {
  if (typeof code !== 'number') return 'HTTP ' + path + ' 失败，响应格式无效';
  if (code === 2300028) {
    return shouldBypassSystemProxy(base)
      ? 'HTTP ' + path + ' 连接超时（系统错误码 2300028）：请确认手机与电脑在同一局域网或 VPN/Tailnet 路由可达，并检查防火墙与端口'
      : 'HTTP ' + path + ' 连接超时（系统错误码 2300028）：请检查网络连接与服务端状态';
  }
  if (code === 2300007) {
    return 'HTTP ' + path + ' 无法连接服务器（系统错误码 2300007）：请确认 T3 服务已运行且地址、端口与防火墙正确';
  }
  if (code === 2300006) {
    return 'HTTP ' + path + ' 无法解析域名（系统错误码 2300006）：请检查地址拼写与网络连接';
  }
  if (code === 2300060) {
    return 'HTTP ' + path + ' TLS 证书校验失败（系统错误码 2300060）：不接受不受信任或自签名证书';
  }
  if (code === 2300047) {
    return 'HTTP ' + path + ' 失败，服务端重定向被拒绝（系统错误码 2300047）';
  }
  if (code === 2300052 || code === 2300055 || code === 2300056) {
    return 'HTTP ' + path + ' 网络中断或服务端无响应（系统错误码 ' + code + '）';
  }
  return 'HTTP ' + path + ' 失败，系统错误码 ' + code;
}

interface PeerPairingPayload { label: string; scopes: string[]; }
interface EmptyPayload { }
interface NamePayload { name: string; }
interface ThreadIdPayload { threadId: string; }
interface SubscribeThreadPayload {
  threadId: string;
  acceptBoundedSnapshot: boolean;
  requestCompletionMarker: boolean;
  acceptDedupedBodies: boolean;
  afterSequence?: number;
}
interface SubscribeShellPayload {
  requestCompletionMarker: boolean;
  omitIdleSubagents: boolean;
  afterSequence?: number;
}
interface PathPayload { partialPath: string; }
interface RepositoryPayload { provider: string; repository: string; }
interface ProjectIdPayload { projectId: string; }
interface ThreadSettingPayload {
  type: string; commandId: string; threadId: string;
  modelSelection?: ModelSelection; runtimeMode?: string; interactionMode?: string;
}
interface MessageDispatchMode { type: string; }
interface FileSearchPayload { cwd: string; query: string; limit: number; imageOnly?: boolean; }
interface SubagentStopCommand { type: string; commandId: string; threadId: string; runId: string; subagentId: string; }
interface GuestCloseCommand { type: string; commandId: string; threadId: string; }
interface GuestMessageCommand {
  type: string; commandId: string; threadId: string; guestMessageId: string;
  messageId?: string; text?: string; attachments?: Object[]; createdBy?: string;
  creationSource?: string; dispatchMode?: MessageDispatchMode;
}
interface PreparedRetryCommand { type: string; commandId: string; threadId: string; runId: string; }
interface TurnItemPayload { threadId: string; itemId: string; }
interface ResumeMessageCommand {
  type: string; commandId: string; createdBy: string; creationSource: string; threadId: string;
  messageId: string; text: string; attachments: Object[]; manualContinuationOfRunId: string;
  modelSelection?: ModelSelection; dispatchMode: MessageDispatchMode;
}
interface WriteFileInput { cwd: string; relativePath: string; contents: string; }
interface LimitRecoveryUpdate {
  runId: string; resetAt?: string; autoResume?: boolean; snooze?: boolean;
}
interface MetadataLimitCommand {
  type: string; commandId: string; threadId: string; limitRecovery: LimitRecoveryUpdate;
}
interface ProviderRefreshPayload { fresh: boolean; refreshModels: boolean; instanceId?: string; }
interface ProviderInstancePayload { instanceId: string; }
interface ProviderAuthCancelPayload { instanceId: string; flowId: string; }
interface CommandOutputPayload { threadId: string; itemId: string; }
interface AttachmentResource { _tag: string; attachmentId: string; fileName?: string; mimeType?: string; disposition?: string; }
interface AssetUrlInput { resource: AttachmentResource; }

interface ServerConfigSubscribePayload {
  workspaceSnapshotsOnDemand: boolean;
  providerStatusDeltas: boolean;
}
export interface RouteProbeResult {
  ok: boolean;
  base: string;
  descriptor?: Record<string, Object>;
  error?: string;
  checkedAt: number;
}
const SHELL_CACHE_CAPABILITIES: string[] = [
  'threadSettlement', 'threadSnooze', 'threadPinning', 'threadPinReorder',
  'threadActiveReorder', 'threadAutoSettleOptOut', 'threadTitleRegeneration',
  'threadProjectFromScratch', 'projectOrganization'
];
const PRECHECKED_DESCRIPTOR_TTL_MS = 5000;
const NEARBY_DESCRIPTOR_TIMEOUT_MS = 3000;
const SOCKET_OPEN_TIMEOUT_MS = 15000;
const CONFIG_SYNC_TIMEOUT_MS = 45000;
const STREAM_SUBSCRIBE_TIMEOUT_MS = 45000;
const BACKOFF_RESET_AFTER_MS = 30000;
const SESSION_LOSS_RETRY_DELAY_MS = 250;
const LOCAL_PROBE_TIMEOUT_MS = 3000;
const REMOTE_PROBE_TIMEOUT_MS = 15000;
const LONG_BACKGROUND_PROBE_TIMEOUT_MS = 1500;
const SILENT_SOCKET_HTTP_DELAY_MS = 500;
const REMOTE_SILENT_SOCKET_AFTER_MS = 2500;
const HEARTBEAT_INTERVAL_MS = 5000;
const HEARTBEAT_TIMEOUT_MS = 15000;
const HEARTBEAT_FREEZE_GAP_MS = 12000;
const HEARTBEAT_RESUME_GRACE_MS = 5000;
const MAX_LOST_TRANSPORT_RESENDS = 2;
const MESSAGE_DISPATCH_TIMEOUT_MS = 60000;

export interface DirectDpopSigner {
  prove(method: string, target: string, accessToken?: string): Promise<string>;
}

interface DirectDpopSocketResult {
  url: string;
  session: SavedSession;
}

function supportsDirectDpopRenewal(descriptor: Record<string, Object>): boolean {
  const caps = descriptor.capabilities;
  return caps !== undefined && caps !== null && typeof caps === 'object' && !Array.isArray(caps) &&
    (caps as Record<string, Object>).accessTokenRenewal === true;
}

export interface CloudEndpoint { httpBaseUrl: string; wsBaseUrl: string; providerKind: string; }

export interface CloudTransport {
  environmentId: string;
  label: string;
  endpoint(): Promise<CloudEndpoint>;
  cachedEndpoint?(): Promise<CloudEndpoint | undefined>;
  tokenExpiresAt?(): number;
  requestJson(path: string, method: http.RequestMethod, body?: string, json?: boolean,
    extraHeaders?: Record<string, string>): Promise<Object>;
  socketUrl(): Promise<string>;
  renew(): Promise<number>;
  reset(): Promise<void>;
}

export class T3Client {
  status: string = '未连接';
  lastConnectionError: string = '';
  networkOffline: boolean = false;
  expectedEnvironmentId: string = '';
  recoveryBase: string = '';
  reconnectSavedRoutes: (() => Promise<void>) | undefined = undefined;
  dpop: DirectDpopSigner | undefined = dpopSigner;
  private connectionsPending: number = 0;
  get connectionPending(): boolean { return this.connectionsPending > 0; }
  get reconnectPending(): boolean { return this.connectionsPending > 0 || this.retryTimer !== 0; }
  get shellSynced(): boolean { return this.ready && this.shell.liveSynced; }
  get hasShellData(): boolean { return this.shell.hasSnapshot; }
  get connectedBase(): string { return this.activeBase(); }
  onShellUpdated: (() => void) | undefined = undefined;
  validateIdentity: (environmentId: string) => void = () => {};
  server: string = '';
  environmentLabel: string = '';
  private peerAccessState: Object | undefined = undefined;
  private offersPeerLinks: boolean = false;
  private peerAccessGeneration: number = 0;
  private sessionAccessRevision: number = 0;
  cloud: CloudTransport | undefined = undefined;
  private cloudBase: string = '';
  private cloudEnvironmentId: string = '';
  private cloudRenewal: number = 0;
  private directDpopRenewal: number = 0;
  private directDpopLocks: Map<string, Promise<void>> = new Map();
  requireDeviceApproval: boolean = false;
  authAccess: AuthAccess = { pairingLinks: [], devices: [] };
  authAccessLoaded: boolean = false;
  private accessChunk: ((value: Object) => void) | undefined = undefined;
  private accessListener: (() => void) | undefined = undefined;
  directAddresses: string[] = [];
  ready: boolean = false;
  thread: ThreadState | undefined = undefined;
  private preservedThread: ThreadState | undefined = undefined;
  onUpdate: () => void = () => {};
  private socket: webSocket.WebSocket | undefined = undefined;
  private rpc: RpcClient | undefined = undefined;
  private timer: number = 0;
  private lastInbound: number = 0;
  private lastHeartbeatTick: number = 0;
  private inboundFrames: number = 0;
  private probeInboundNotify: (() => void) | undefined = undefined;
  private generation: number = 0;
  private mediaCache: MarkdownMediaCache = new MarkdownMediaCache();
  private threadChunk: ((value: Object) => void) | undefined = undefined;
  private lastWatchedThreadId: string = '';
  private resumingWatchThreadId: string = '';
  get pendingWatchThreadId(): string { return this.thread?.threadId || this.resumingWatchThreadId; }
  private shellChunk: ((value: Object) => void) | undefined = undefined;
  private configChunk: ((value: Object) => void) | undefined = undefined;
  private worktreeChunk: ((value: Object) => void) | undefined = undefined;
  private shellRetryTimer: number = 0;
  private shellRetryDelay: number = 250;
  private threadRetryTimer: number = 0;
  private threadRetryDelay: number = 250;
  worktreeSetup: Record<string, Object> | undefined = undefined;
  store: SessionStorage | undefined = undefined;
  shell: ShellState = new ShellState();
  models: ModelChoice[] = [];
  capabilities: Record<string, Object> = {};
  private cachedCapabilities: Record<string, boolean> = {};
  private lastShellEnvironmentId: string = '';
  config: Record<string, Object> = {};
  private launching: boolean = false;
  serverSettings: Record<string, Object> = {};
  platform: string = '';
  newProjectsRoot: string = '';
  scratchWorkspaceRoot: string = '';
  addProjectBaseDirectory: string = '';
  ghqCloneLayout: boolean = false;
  snoozePresets: SnoozePresetSetting[] = snoozeSettingsFrom(undefined);
  offeredSourceControlProviders: Record<string, boolean> = {};
  sessionAccess: Object | undefined = undefined;
  private saved: SavedSession | undefined = undefined;
  recoveryStore: RecoveryStorage | undefined = undefined;
  recovery: RecoveryState | undefined = undefined;
  private mutating: boolean = false;
  private awaitingResend: boolean = false;
  private deferredResumeThreadId: string = '';
  private sessionWaiters: Set<() => void> = new Set();
  get mutationPending(): boolean { return this.launching || this.mutating || !!this.recovery?.pendingId; }
  get submitting(): boolean { return this.mutating || this.launching; }
  private reconciled: boolean = false;
  private resumeWanted: boolean = false;
  private inBackground: boolean = false;
  private probing: Promise<boolean> | undefined = undefined;
  private connectedAt: number = 0;
  private retryFailureCount: number = 0;
  private retryTimer: number = 0;
  private retryDelay: number = 1000;
  private notifyTimer: number = 0;

  private notify(): void {
    if (this.notifyTimer) return;
    this.notifyTimer = setTimeout(() => { this.notifyTimer = 0; this.onUpdate(); }, 50);
  }

  generationValue(): number { return this.generation; }
  canScope(scope: string): boolean | undefined { return sessionAllows(this.sessionAccess, scope); }
  supports(name: string): boolean {
    if (Object.keys(this.capabilities).length > 0) return capability({ capabilities: this.capabilities }, name);
    return this.cachedCapabilities[name] === true;
  }
  hydrateShellCache(cached: CachedShellEntry): void {
    if (this.ready || this.shell.liveSynced) return;
    if (this.expectedEnvironmentId && cached.environmentId !== this.expectedEnvironmentId) return;
    this.shell.hydrateCache(cached.projects, cached.threads);
    this.lastShellEnvironmentId = cached.environmentId;
    const caps: Record<string, boolean> = {};
    for (const key of Object.keys(cached.capabilities)) {
      if (cached.capabilities[key] === true) caps[key] = true;
    }
    this.cachedCapabilities = caps;
    if (cached.scratchWorkspaceRoot && !this.scratchWorkspaceRoot) {
      this.scratchWorkspaceRoot = cached.scratchWorkspaceRoot;
    }
  }
  exportShellCache(): CachedShellEntry | undefined {
    const environmentId = this.activeEnvironmentId();
    if (!this.shell.liveSynced || !environmentId) return undefined;
    const caps: Record<string, boolean> = {};
    for (const key of SHELL_CACHE_CAPABILITIES) {
      if (this.supports(key)) caps[key] = true;
    }
    return {
      environmentId,
      savedAt: Date.now(),
      scratchWorkspaceRoot: this.scratchWorkspaceRoot,
      capabilities: caps,
      projects: this.shell.projects.slice(),
      threads: this.shell.threads.slice()
    };
  }
  canCreateProject(): boolean {
    return this.ready && this.canScope('orchestration:operate') !== false;
  }
  canReadFiles(): boolean {
    return this.ready && this.canScope('filesystem:read') !== false;
  }
  canWriteSourceControl(): boolean {
    return this.ready && this.canScope('source-control:write') !== false;
  }
  async refreshSessionAccess(): Promise<void> {
    if (!this.ready || !this.activeBase()) return;
    const rpc = this.rpc;
    const generation = this.generation;
    const revision = ++this.sessionAccessRevision;
    let access: Object | undefined = undefined;
    try {
      access = record(await this.httpJson(this.activeBase(), '/api/auth/session', http.RequestMethod.GET,
        '', this.saved?.token || '', false, !!this.cloud));
    } catch (_) {}
    if (rpc !== this.rpc || generation !== this.generation || revision !== this.sessionAccessRevision) return;
    this.sessionAccess = access;
    this.onUpdate();
  }
  async rpcRequest(method: string, payload: Object, timeoutMs: number = 15000,
    fatalTimeout: boolean = true): Promise<Object> {
    const rpc = this.requireRpc();
    const generation = this.generation;
    const value = await rpc.request(method, payload, undefined, timeoutMs, fatalTimeout);
    if (rpc !== this.rpc || generation !== this.generation) throw new Error('连接已变更，请刷新后核对结果');
    return value;
  }
  watchRpcStream(method: string, payload: Object, onItem: (value: Object) => void): (value: Object) => void {
    const rpc = this.requireRpc();
    const generation = this.generation;
    const wrapped = (value: Object): void => {
      if (rpc === this.rpc && generation === this.generation) onItem(value);
    };
    void rpc.request(method, payload, wrapped, 600000, false).then(() => {}).catch(() => {});
    return wrapped;
  }
  async previewStreamUrl(threadId: string, tabId: string): Promise<string> {
    this.requireRpc();
    if (!threadId.trim() || !tabId.trim() || threadId.length > 256 || tabId.length > 256) throw new Error('预览标识无效');
    const generation = this.generation;
    const base = this.activeBase();
    const result = record(await this.httpJson(base, '/api/auth/websocket-ticket/media',
      http.RequestMethod.POST, '', this.saved?.token || '', false, !!this.cloud));
    if (generation !== this.generation || base !== this.activeBase()) throw new Error('环境连接已变化，请重新打开预览');
    const ticket = text(result.ticket);
    return base.replace(/^http/, 'ws') + '/api/preview-stream/ws?threadId=' + encodeURIComponent(threadId) +
      '&tabId=' + encodeURIComponent(tabId) + '&maxWidth=720&maxHeight=1280&wsTicket=' + encodeURIComponent(ticket);
  }
  async deviceStreamAccess(hubPath: string, hostId: string, deviceId: string): Promise<DeviceStreamAccess> {
    this.requireRpc();
    const path = safeDeviceHubBase(hubPath);
    if (!hostId || !deviceId || hostId.length > 256 || deviceId.length > 256) throw new Error('设备标识无效');
    const generation = this.generation;
    const base = this.activeBase();
    const jpegTicket = record(await this.httpJson(base, '/api/auth/websocket-ticket/media',
      http.RequestMethod.POST, '', this.saved?.token || '', false, !!this.cloud));
    if (generation !== this.generation) throw new Error('设备环境已变化');
    const inputTicket = record(await this.httpJson(base, '/api/auth/websocket-ticket/media',
      http.RequestMethod.POST, '', this.saved?.token || '', false, !!this.cloud));
    if (generation !== this.generation || base !== this.activeBase()) throw new Error('设备环境已变化');
    const host = encodeURIComponent(hostId);
    const device = encodeURIComponent(deviceId);
    return { mjpegUrl: base + path + '/vendor/serve-sim/helper/' + device + '/stream.mjpeg?hostId=' + host +
      '&wsTicket=' + encodeURIComponent(text(jpegTicket.ticket)),
      inputUrl: base.replace(/^http/, 'ws') + path + '/vendor/serve-sim/helper/ws?device=' + device + '&hostId=' + host +
        '&wsTicket=' + encodeURIComponent(text(inputTicket.ticket)) };
  }
  async androidDeviceStreamUrl(hubPath: string, hostId: string, deviceId: string): Promise<string> {
    this.requireRpc();
    const path = safeDeviceHubBase(hubPath);
    if (!hostId || !deviceId || hostId.length > 256 || deviceId.length > 256) throw new Error('设备标识无效');
    const generation = this.generation;
    const base = this.activeBase();
    const result = record(await this.httpJson(base, '/api/auth/websocket-ticket/media',
      http.RequestMethod.POST, '', this.saved?.token || '', false, !!this.cloud));
    if (generation !== this.generation || base !== this.activeBase()) throw new Error('设备环境已变化');
    return base.replace(/^http/, 'ws') + path + '/vendor/serve-emu/ws?device=' + encodeURIComponent(deviceId) +
      '&hostId=' + encodeURIComponent(hostId) + '&frame-meta=1&wsTicket=' + encodeURIComponent(text(result.ticket));
  }
  attachTerminal(payload: Object, onItem: (value: Object) => void,
    failed: (message: string) => void, observe: boolean = false): () => void {
    if (this.canScope('terminal:read') === false || (!observe && this.canScope('terminal:operate') === false)) {
      throw new Error('此连接无权执行此终端操作');
    }
    return this.terminalStream(observe ? 'terminal.observe' : 'terminal.attach', payload, onItem, failed);
  }
  watchTerminals(onItem: (value: Object) => void, failed: (message: string) => void): () => void {
    if (this.canScope('terminal:read') === false) throw new Error('此连接无权查看终端');
    return this.terminalStream('subscribeTerminalMetadata', {} as Record<string, Object>, onItem, failed);
  }
  private terminalStream(method: string, payload: Object, onItem: (value: Object) => void,
    failed: (message: string) => void): () => void {
    const rpc = this.requireRpc();
    const generation = this.generation;
    let cancelled = false;
    const current = (): boolean => !cancelled && rpc === this.rpc && generation === this.generation;
    const receive = (value: Object): void => { if (current()) onItem(value); };
    void rpc.request(method, payload, receive, 600000, false).then(() => {
      if (current()) failed('终端订阅已结束，请重新连接');
    }).catch(() => { if (current()) failed('终端订阅失败，请检查连接与权限后重试'); });
    return (): void => { cancelled = true; rpc.cancelStream(receive); };
  }
  stopRpcStream(onItem: (value: Object) => void): void {
    this.rpc?.cancelStream(onItem);
  }
  async dispatchCommand(command: Object): Promise<Object> {
    return this.rpcRequest('orchestration.dispatchCommand', command);
  }
  async projectMutate(mutation: Object): Promise<Object> {
    return this.rpcRequest('projects.mutate', mutation);
  }
  async ensureScratch(): Promise<Object> {
    const payload: EmptyPayload = {};
    return this.rpcRequest('projects.ensureScratch', payload);
  }
  async createNewProject(name: string): Promise<Object> {
    const payload: NamePayload = { name };
    return this.rpcRequest('projects.createNew', payload);
  }
  async createProjectFromThread(threadId: string): Promise<Object> {
    const payload: ThreadIdPayload = { threadId };
    return this.rpcRequest('projects.createFromThread', payload);
  }
  async browseFilesystem(partialPath: string): Promise<Object> {
    const payload: PathPayload = { partialPath };
    return this.rpcRequest('filesystem.browse', payload, 10000, false);
  }
  async discoverSourceControl(): Promise<Object> {
    const payload: EmptyPayload = {};
    return this.rpcRequest('server.discoverSourceControl', payload, 8000, false);
  }
  async lookupRepository(provider: string, repository: string): Promise<Object> {
    const payload: RepositoryPayload = { provider, repository };
    return this.rpcRequest('sourceControl.lookupRepository', payload, 15000, false);
  }
  async publishRepository(payload: Object): Promise<Object> {
    return this.rpcRequest('sourceControl.publishRepository', payload);
  }
  async startProjectClone(payload: Object): Promise<Object> {
    return this.rpcRequest('projectClone.start', payload);
  }
  async cancelProjectClone(projectId: string): Promise<Object> {
    const payload: ProjectIdPayload = { projectId };
    return this.rpcRequest('projectClone.cancel', payload);
  }
  async retryProjectClone(projectId: string): Promise<Object> {
    const payload: ProjectIdPayload = { projectId };
    return this.rpcRequest('projectClone.retry', payload);
  }
  async archivedShellSnapshot(): Promise<Object> {
    const payload: EmptyPayload = {};
    return this.rpcRequest('orchestration.getArchivedShellSnapshot', payload, 15000, false);
  }
  async searchThreads(payload: Object): Promise<Object> {
    return this.rpcRequest('orchestration.searchThreads', payload, 8000, false);
  }

  private startHeartbeat(rpc: RpcClient, generation: number): void {
    clearInterval(this.timer);
    const now = Date.now();
    this.lastInbound = now;
    this.lastHeartbeatTick = now;
    this.timer = setInterval(() => {
      if (generation !== this.generation || this.rpc !== rpc) {
        clearInterval(this.timer); this.timer = 0; return;
      }
      const tickNow = Date.now();
      const tickGap = tickNow - this.lastHeartbeatTick;
      this.lastHeartbeatTick = tickNow;
      if (tickGap > HEARTBEAT_FREEZE_GAP_MS) {
        // Timer was frozen by OS power/sleep policy; grant a short grace window and ping first.
        const minInbound = tickNow - (HEARTBEAT_TIMEOUT_MS - HEARTBEAT_RESUME_GRACE_MS);
        if (this.lastInbound < minInbound) this.lastInbound = minInbound;
        rpc.ping();
        return;
      }
      if (tickNow - this.lastInbound > HEARTBEAT_TIMEOUT_MS) rpc.fail('服务端响应超时；请重连并核对任务状态');
      else rpc.ping();
    }, HEARTBEAT_INTERVAL_MS);
  }

  private isFastRoute(): boolean {
    if (this.cloud) return false;
    const base = this.activeBase();
    if (!base) return false;
    const kind = directHostKind(urlHostname(base));
    return kind === 'loopback' || kind === 'lan';
  }

  private isLoopbackTarget(): boolean {
    if (this.cloud) return false;
    const base = this.activeBase() || this.recoveryBase;
    return !!base && directHostKind(urlHostname(base)) === 'loopback';
  }

  private probeTimeoutForRoute(backgroundDurationMs: number): number {
    if (backgroundDurationMs >= 10000) return LONG_BACKGROUND_PROBE_TIMEOUT_MS;
    if (this.isFastRoute()) return LOCAL_PROBE_TIMEOUT_MS;
    return REMOTE_PROBE_TIMEOUT_MS;
  }

  private async probeLiveSocket(timeoutMs: number, fastFailOnHttp: boolean = false): Promise<boolean> {
    if (!this.ready || !this.rpc) return false;
    if (this.probing) return this.probing;
    const rpc = this.rpc;
    const generation = this.generation;
    const framesBefore = this.inboundFrames;
    const base = this.activeBase();
    const envId = this.activeEnvironmentId();
    const startedAt = Date.now();
    let run: Promise<boolean> | undefined = undefined;
    run = new Promise<boolean>((resolve) => {
      let settled = false;
      let httpDelayTimer = 0;
      let silentTimer = 0;
      const finish = (alive: boolean): void => {
        if (settled) return;
        settled = true;
        if (httpDelayTimer) { clearTimeout(httpDelayTimer); httpDelayTimer = 0; }
        if (silentTimer) { clearTimeout(silentTimer); silentTimer = 0; }
        if (this.probeInboundNotify === onInbound) this.probeInboundNotify = undefined;
        if (this.probing === run) this.probing = undefined;
        resolve(alive);
      };
      const isCurrent = (): boolean => generation === this.generation && this.rpc === rpc && this.ready;
      const onInbound = (): void => {
        if (!isCurrent()) { finish(false); return; }
        if (this.inboundFrames > framesBefore) finish(true);
      };
      this.probeInboundNotify = onInbound;

      if (base && timeoutMs > SILENT_SOCKET_HTTP_DELAY_MS) {
        httpDelayTimer = setTimeout(() => {
          httpDelayTimer = 0;
          if (settled || !isCurrent() || this.inboundFrames > framesBefore) return;
          void this.probeRoute(base, envId, Math.min(2500, timeoutMs)).then((result: RouteProbeResult) => {
            if (settled || !isCurrent()) return;
            if (this.inboundFrames > framesBefore) { finish(true); return; }
            if (!result.ok) return;
            if (fastFailOnHttp) { finish(false); return; }
            const remaining = REMOTE_SILENT_SOCKET_AFTER_MS - (Date.now() - startedAt);
            if (remaining <= 0) { finish(false); return; }
            silentTimer = setTimeout(() => {
              silentTimer = 0;
              if (settled) return;
              finish(isCurrent() && this.inboundFrames > framesBefore);
            }, remaining) as number;
          }).catch(() => {});
        }, SILENT_SOCKET_HTTP_DELAY_MS) as number;
      }

      const empty: EmptyPayload = {};
      void rpc.request('server.probe', empty, undefined, timeoutMs, false).then(() => {
        finish(isCurrent());
      }).catch((error: Error) => {
        // A known RPC exit (e.g. an older host without server.probe) still proves the socket is alive.
        if (error instanceof RpcFailure && error.known && isCurrent()) {
          finish(true);
          return;
        }
        finish(isCurrent() && this.inboundFrames > framesBefore);
      });
    });
    this.probing = run;
    return run;
  }

  enterBackground(): void {
    this.inBackground = true;
    clearInterval(this.timer); this.timer = 0;
    clearTimeout(this.retryTimer); this.retryTimer = 0;
    clearTimeout(this.directDpopRenewal); this.directDpopRenewal = 0;
    clearTimeout(this.shellRetryTimer); this.shellRetryTimer = 0;
    clearTimeout(this.threadRetryTimer); this.threadRetryTimer = 0;
  }

  suspend(): void {
    const wanted = this.resumeWanted;
    this.disconnect('后台已暂停连接，任务在服务端继续', false, false);
    this.resumeWanted = wanted;
  }

  handleNetworkStatus(offline: boolean): void {
    const changed = this.networkOffline !== offline;
    this.networkOffline = offline;
    if (offline) {
      if (!this.isLoopbackTarget()) {
        clearTimeout(this.retryTimer); this.retryTimer = 0;
      }
      if (changed) this.onUpdate();
      return;
    }
    this.retryFailureCount = 0;
    if (this.inBackground) {
      if (changed) this.onUpdate();
      return;
    }
    if (this.ready && this.rpc) {
      void this.handleNetworkPathChange().catch(() => {});
      return;
    }
    if (this.resumeWanted && this.connectionsPending === 0) {
      clearTimeout(this.retryTimer); this.retryTimer = 0;
      void this.reconnectAttempt(0).catch(() => { this.status = '请解锁后安全重连'; this.onUpdate(); });
      return;
    }
    if (changed) this.onUpdate();
  }

  async handleNetworkPathChange(): Promise<void> {
    this.networkOffline = false;
    this.retryFailureCount = 0;
    if (this.inBackground || !this.resumeWanted) return;
    if (this.ready && this.rpc) {
      const alive = await this.probeLiveSocket(this.probeTimeoutForRoute(0), this.isFastRoute());
      if (alive) {
        if (!this.shell.liveSynced && !this.shellChunk) this.subscribeShell();
        if (this.thread && !this.threadChunk && !this.mutating && !this.launching) {
          void this.watch(this.thread.threadId).catch(() => {});
        }
        this.onUpdate();
        return;
      }
      if (!this.resumeWanted || this.inBackground) return;
    }
    if (this.connectionsPending === 0) {
      clearTimeout(this.retryTimer); this.retryTimer = 0;
      await this.reconnectAttempt(0);
    }
  }

  async resume(backgroundDurationMs: number = 0): Promise<void> {
    this.inBackground = false;
    this.retryFailureCount = 0;
    this.retryDelay = 1000;
    await this.reconnectAttempt(backgroundDurationMs);
  }

  private async reconnectAttempt(backgroundDurationMs: number = 0): Promise<void> {
    clearTimeout(this.retryTimer); this.retryTimer = 0;
    if (!this.resumeWanted) return;
    if (this.networkOffline && !this.isLoopbackTarget()) {
      this.onUpdate();
      return;
    }
    if (this.ready && this.rpc) {
      this.startHeartbeat(this.rpc, this.generation);
      const probeTimeout = this.probeTimeoutForRoute(backgroundDurationMs);
      const fastFailOnHttp = backgroundDurationMs >= 10000 || this.isFastRoute();
      const alive = await this.probeLiveSocket(probeTimeout, fastFailOnHttp);
      if (alive) {
        if (!this.shell.liveSynced) this.subscribeShell();
        if (this.thread && !this.threadChunk && !this.mutating && !this.launching) {
          void this.watch(this.thread.threadId).catch(() => {});
        }
        if (!this.cloud && this.saved?.kind === 'dpop') this.scheduleDirectDpopRenewal(this.generation);
        this.onUpdate();
        return;
      }
      if (!this.resumeWanted || this.inBackground) return;
    } else if (this.connectionsPending > 0) {
      if (backgroundDurationMs < 10000) return;
      const wanted = this.resumeWanted;
      this.disconnect('正在重新连接', false, false, true);
      this.resumeWanted = wanted;
    }
    if (this.reconnectSavedRoutes) { await this.reconnectSavedRoutes(); return; }
    const saved = this.store ? await this.store.load() : this.saved;
    if (saved && (saved.kind === 'dpop' || saved.expiresAt > Date.now())) await this.connect(saved.base);
  }

  private computeRetryDelay(fastDropRetry: boolean): number {
    if (fastDropRetry) {
      return Math.max(100, Math.round(SESSION_LOSS_RETRY_DELAY_MS * (0.5 + Math.random() * 0.5)));
    }
    const expStep = Math.max(0, this.retryFailureCount - 1);
    const baseDelay = Math.min(1000 * Math.pow(2, Math.min(expStep, 5)), 30000);
    return Math.max(250, Math.round(baseDelay * (0.5 + Math.random() * 0.5)));
  }

  private retry(delayMs: number): void {
    if (this.inBackground || !this.resumeWanted ||
      (!this.reconnectSavedRoutes && (!this.saved || (this.saved.kind !== 'dpop' && this.saved.expiresAt <= Date.now())))) return;
    if (this.networkOffline && !this.isLoopbackTarget()) return;
    this.retryDelay = delayMs;
    this.retryTimer = setTimeout(() => {
      this.retryTimer = 0;
      void this.reconnectAttempt(0).catch(() => { this.status = '请解锁后安全重连'; this.onUpdate(); });
    }, delayMs);
  }

  private async saveRecovery(): Promise<void> {
    if (this.recovery && this.recoveryStore) await this.recoveryStore.save(this.recovery);
  }

  async acknowledgeUnknown(): Promise<void> {
    if (this.mutating || !this.reconciled || !this.recovery) throw new Error('请先同步原会话并核对结果');
    const pending = this.recovery;
    this.recovery = { base: pending.base, environmentId: pending.environmentId, threadId: pending.threadId, pendingId: '', pendingKind: '' };
    try { await this.saveRecovery(); } catch (error) { this.recovery = pending; throw error as Error; }
    this.status = '已确认核对，允许手动提交新请求'; this.onUpdate();
  }

  private notifySessionWaiters(): void {
    if (this.sessionWaiters.size === 0) return;
    const waiters = Array.from(this.sessionWaiters);
    this.sessionWaiters.clear();
    for (const wake of waiters) {
      try { wake(); } catch (_) {}
    }
  }

  private waitForReplacementSession(previousRpc: RpcClient, expectedEnvironmentId: string): Promise<RpcClient | undefined> {
    const currentReplacement = (): RpcClient | undefined => {
      if (this.ready && this.rpc && this.rpc !== previousRpc) {
        if (expectedEnvironmentId && this.activeEnvironmentId() && this.activeEnvironmentId() !== expectedEnvironmentId) {
          return undefined;
        }
        return this.rpc;
      }
      return undefined;
    };
    const isStopped = (): boolean => {
      if (this.ready && this.rpc && this.rpc !== previousRpc) {
        return !!expectedEnvironmentId && !!this.activeEnvironmentId() && this.activeEnvironmentId() !== expectedEnvironmentId;
      }
      return !this.resumeWanted && this.connectionsPending === 0 && this.retryTimer === 0;
    };
    const readyNow = currentReplacement();
    if (readyNow) return Promise.resolve(readyNow);
    if (isStopped()) return Promise.resolve(undefined);
    return new Promise<RpcClient | undefined>((resolve) => {
      const onStateChange = (): void => {
        const replacement = currentReplacement();
        if (replacement) {
          resolve(replacement);
          return;
        }
        if (isStopped()) {
          resolve(undefined);
          return;
        }
        this.sessionWaiters.add(onStateChange);
      };
      this.sessionWaiters.add(onStateChange);
    });
  }

  private async mutate(method: string, payload: Object, id: string, kind: string, launchOwned: boolean = false,
    resendOnSocketLoss: boolean = false): Promise<void> {
    let rpc = this.requireRpc();
    if (this.launching && !launchOwned) throw new Error('新任务正在提交，请稍候');
    if (this.mutating || this.recovery?.pendingId) throw new Error('上次提交结果未知，请同步原会话并核对结果');
    if (!this.recovery) throw new Error('请先选择会话');
    const expectedEnvironmentId = this.recovery.environmentId || this.activeEnvironmentId();
    const previous = this.recovery;
    this.mutating = true;
    this.awaitingResend = false;
    this.reconciled = false;
    this.recovery.pendingId = id; this.recovery.pendingKind = kind;
    let sent = false;
    const timeoutMs = resendOnSocketLoss ? MESSAGE_DISPATCH_TIMEOUT_MS : 30000;
    try {
      try {
        await this.saveRecovery(); // Commit the marker before any modifying request leaves the device.
      } catch (error) {
        if (method === 'orchestration.launchThread') {
          this.recovery = undefined;
          this.thread = undefined;
          if (this.recoveryStore) {
            try { await this.recoveryStore.clear(); } catch (_) {}
          }
        } else this.recovery = previous;
        throw new Error('无法保存提交保护记录，未发送任何请求：' + (error as Error).message);
      }
      sent = true;
      let response: Object = {};
      for (let resends = 0; ; resends += 1) {
        if (rpc !== this.rpc) {
          if (!resendOnSocketLoss || resends >= MAX_LOST_TRANSPORT_RESENDS) {
            throw new Error('连接已变更，请同步原会话核对');
          }
          this.awaitingResend = true;
          this.status = '连接已断开，重连后将自动重发';
          this.onUpdate();
          const replacement = await this.waitForReplacementSession(rpc, expectedEnvironmentId);
          this.awaitingResend = false;
          if (!replacement) throw new Error('连接已变更，请同步原会话核对');
          rpc = replacement;
        }
        try {
          response = await rpc.request(method, payload, undefined, timeoutMs, false);
          if (rpc !== this.rpc) throw new Error('连接已变更，请核对原会话');
          break;
        } catch (error) {
          const knownRefusal = error instanceof RpcFailure && error.known;
          const lostTransport = !knownRefusal && (rpc !== this.rpc || !this.ready);
          if (!resendOnSocketLoss || !lostTransport || resends >= MAX_LOST_TRANSPORT_RESENDS) {
            throw error as Error;
          }
          this.awaitingResend = true;
          this.status = '连接已断开，等待重连后重发';
          this.onUpdate();
          const replacement = await this.waitForReplacementSession(rpc, expectedEnvironmentId);
          this.awaitingResend = false;
          if (!replacement) throw error as Error;
          rpc = replacement;
        }
      }
      if (method === 'orchestration.launchThread' && record(response).threadId !== this.recovery?.threadId) throw new Error('新任务响应身份不一致，请核对原会话');
      const pending = this.recovery;
      this.recovery = { base: pending.base, environmentId: pending.environmentId, threadId: pending.threadId, pendingId: '', pendingKind: '' };
      try { await this.saveRecovery(); } catch (error) { this.recovery = pending; throw error as Error; }
    } catch (error) {
      // An explicit launch rejection proves the server accepted no first run; keep transport failures unknown.
      if (sent && method === 'orchestration.launchThread' && error instanceof RpcFailure && error.known && this.recovery) {
        const rejected = this.recovery;
        this.recovery = { base: rejected.base, environmentId: rejected.environmentId, threadId: rejected.threadId, pendingId: '', pendingKind: '' };
        try { await this.saveRecovery(); } catch (_) { this.recovery = rejected; }
        this.reconciled = true;
      }
      throw error as Error;
    } finally {
      this.awaitingResend = false;
      this.mutating = false;
      const deferred = this.deferredResumeThreadId;
      this.deferredResumeThreadId = '';
      this.onUpdate();
      if (deferred && !launchOwned && this.ready && !this.threadChunk && !this.launching) {
        void this.watch(deferred).catch(() => {});
      }
    }
  }
  attachment: Attachment | undefined = undefined;
  attachments: Attachment[] = [];
  attachmentWriteError: string = '';
  private uploadRequest: http.HttpRequest | undefined = undefined;
  private attachmentDraftScope: string = '';
  private attachmentScopeRevision: number = 0;
  get draftScope(): string { return this.attachmentDraftScope; }
  set draftScope(value: string) {
    if (value === this.attachmentDraftScope) return;
    this.attachmentDraftScope = value;
    this.attachmentScopeRevision++;
  }
  captureAttachmentTarget(requireLiveConnection: boolean = true): () => boolean {
    const generation = this.generation;
    const revision = this.attachmentScopeRevision;
    const environment = this.activeEnvironmentId();
    const base = this.activeBase();
    const thread = this.thread;
    const recoveryThread = this.recovery?.threadId;
    const draft = this.draftScope;
    return (): boolean => this.attachmentScopeRevision === revision &&
      (!requireLiveConnection || (this.generation === generation && this.activeEnvironmentId() === environment &&
        this.activeBase() === base && (!!draft || (this.thread === thread && this.recovery?.threadId === recoveryThread))));
  }
  get uploadEnvironmentId(): string { return this.activeEnvironmentId(); }
  private attachmentThread: string = '';
  recoveredMessageId: string = '';

  private async withDirectDpopLock<T>(key: string, action: () => Promise<T>): Promise<T> {
    const previous = this.directDpopLocks.get(key) || Promise.resolve();
    let release: () => void = () => {};
    const gate = new Promise<void>((resolve) => { release = resolve; });
    const tail = previous.then(() => gate);
    this.directDpopLocks.set(key, tail);
    await previous;
    try {
      return await action();
    } finally {
      release();
      if (this.directDpopLocks.get(key) === tail) this.directDpopLocks.delete(key);
    }
  }

  private async signDirectDpopProof(method: string, target: string, accessToken?: string): Promise<string> {
    if (!this.dpop) throw new Error('设备 DPoP 密钥不可用，无法完成鉴权');
    try {
      return await this.dpop.prove(method, target, accessToken);
    } catch (_) {
      throw new Error('无法生成设备 DPoP 鉴权证明');
    }
  }

  private isBlockedDirectDpopError(error: Error): boolean {
    if (error instanceof HttpFailure) {
      return error.status === 400 || error.status === 401 || error.status === 403 || error.status === 404;
    }
    const msg = error.message || '';
    return msg.includes('无效') || msg.includes('不可用') || msg.includes('无法生成设备 DPoP') ||
      msg.includes('没有此服务器的有效会话');
  }

  private async ensureDirectDpopToken(seed: SavedSession, rejectedToken?: string,
    persist: boolean = true): Promise<SavedSession> {
    const key = seed.base + '\n' + seed.environmentId;
    return this.withDirectDpopLock(key, async (): Promise<SavedSession> => {
      let current: SavedSession = seed;
      if (persist && this.saved && this.saved.kind === 'dpop' &&
        this.saved.base === seed.base && this.saved.environmentId === seed.environmentId &&
        (current.token === rejectedToken || this.saved.expiresAt >= current.expiresAt)) {
        current = this.saved;
      }
      if (current.token !== rejectedToken &&
        current.expiresAt - DPOP_ACCESS_TOKEN_REFRESH_SKEW_MS > Date.now()) {
        return current;
      }
      if (persist && this.store) {
        try {
          const stored = await this.store.load(seed.base);
          if (stored && stored.kind === 'dpop' &&
            stored.base === seed.base && stored.environmentId === seed.environmentId) {
            if (stored.token !== rejectedToken &&
              stored.expiresAt - DPOP_ACCESS_TOKEN_REFRESH_SKEW_MS > Date.now()) {
              if (this.saved && this.saved.base === stored.base &&
                this.saved.environmentId === stored.environmentId) {
                this.saved = stored;
              }
              return stored;
            }
            if (current.token === rejectedToken || stored.expiresAt > current.expiresAt) current = stored;
          }
        } catch (_) {}
      }
      const proof = await this.signDirectDpopProof('POST', current.base + '/oauth/token');
      const headers: Record<string, string> = { 'DPoP': proof };
      const auth = record(await this.rawHttpJson(current.base, '/oauth/token',
        http.RequestMethod.POST, tokenRenewalForm(current.token), '', false, 10000, headers));
      const accessToken = text(auth.access_token);
      if (auth.token_type !== 'DPoP' || !accessToken) {
        throw new Error('环境返回了无效的 DPoP 续期令牌');
      }
      if (typeof auth.expires_in !== 'number' || !Number.isFinite(auth.expires_in) || auth.expires_in <= 0) {
        throw new Error('无效凭据有效期');
      }
      const renewed: SavedSession = {
        base: current.base,
        environmentId: current.environmentId,
        token: accessToken,
        expiresAt: Date.now() + auth.expires_in * 1000,
        kind: 'dpop'
      };
      if (persist && this.store) await this.store.save(renewed);
      if (persist && this.saved && this.saved.base === renewed.base &&
        this.saved.environmentId === renewed.environmentId) {
        this.saved = renewed;
      }
      return renewed;
    });
  }

  private async rawHttpJson(base: string, path: string, method: http.RequestMethod,
    body: string = '', authorization: string = '', json: boolean = false,
    timeoutMs: number = 10000, extraHeaders?: Record<string, string>): Promise<Object> {
    const request = http.createHttp();
    try {
      const headers: Record<string, string> = { 'Accept': 'application/json' };
      if (authorization) headers['Authorization'] = authorization;
      if (body) headers['Content-Type'] = json ? 'application/json' : 'application/x-www-form-urlencoded';
      if (extraHeaders) {
        for (const key of Object.keys(extraHeaders)) headers[key] = extraHeaders[key];
      }
      const options: http.HttpRequestOptions = withDirectProxyPolicy(base, {
        method, header: headers, connectTimeout: Math.min(timeoutMs, 10000), readTimeout: timeoutMs,
        usingCache: false, maxRedirects: 0, expectDataType: http.HttpDataType.STRING
      });
      // NetworkKit rejects an explicitly empty POST extraData with parameter error 401.
      if (body) options.extraData = body;
      const response = await request.request(base + path, options);
      if (response.responseCode < 200 || response.responseCode >= 300) throw new HttpFailure(response.responseCode);
      return JSON.parse(response.result as string) as Object;
    } catch (error) {
      if (error instanceof HttpFailure) throw error as Error;
      const code = (error as BusinessError).code;
      throw new Error(formatHttpNetworkError(path, base, typeof code === 'number' ? code : undefined));
    } finally {
      request.destroy();
    }
  }

  private async directDpopHttpJson(base: string, path: string, method: http.RequestMethod,
    body: string = '', json: boolean = false, timeoutMs: number = 10000,
    extraHeaders?: Record<string, string>): Promise<Object> {
    const initial = this.saved;
    if (!initial || initial.kind !== 'dpop' || initial.base !== base) {
      throw new Error('没有此服务器的有效会话，请输入新配对凭据');
    }
    let session = await this.ensureDirectDpopToken(initial, undefined, true);
    const send = async (current: SavedSession): Promise<Object> => {
      const proof = await this.signDirectDpopProof(method as string, base + path, current.token);
      const headers: Record<string, string> = {};
      if (extraHeaders) {
        for (const key of Object.keys(extraHeaders)) headers[key] = extraHeaders[key];
      }
      headers['DPoP'] = proof;
      return this.rawHttpJson(base, path, method, body, 'DPoP ' + current.token, json, timeoutMs, headers);
    };
    try {
      return await send(session);
    } catch (error) {
      if (!(error instanceof HttpFailure) || error.status !== 401) throw error as Error;
      session = await this.ensureDirectDpopToken(session, session.token, true);
      return send(session);
    }
  }

  private async issueDirectDpopRpcTicket(base: string, token: string): Promise<string> {
    const rpcPath = '/api/auth/websocket-ticket/rpc';
    const rpcProof = await this.signDirectDpopProof('POST', base + rpcPath, token);
    const rpcHeaders: Record<string, string> = { 'DPoP': rpcProof };
    try {
      const result = await this.rawHttpJson(base, rpcPath, http.RequestMethod.POST, '', 'DPoP ' + token,
        false, 10000, rpcHeaders);
      return text(record(result).ticket);
    } catch (error) {
      if (!(error instanceof HttpFailure) || error.status !== 404) throw error as Error;
      const barePath = '/api/auth/websocket-ticket';
      const bareProof = await this.signDirectDpopProof('POST', base + barePath, token);
      const bareHeaders: Record<string, string> = { 'DPoP': bareProof };
      const result = await this.rawHttpJson(base, barePath, http.RequestMethod.POST, '', 'DPoP ' + token,
        false, 10000, bareHeaders);
      return text(record(result).ticket);
    }
  }

  private async resolveDirectDpopSocketUrl(seed: SavedSession, persistRenewal: boolean,
    generation: number): Promise<DirectDpopSocketResult> {
    let active = await this.ensureDirectDpopToken(seed, undefined, persistRenewal);
    if (generation !== this.generation) return { url: '', session: active };
    let ticket = '';
    try {
      ticket = await this.issueDirectDpopRpcTicket(active.base, active.token);
    } catch (error) {
      if (generation !== this.generation) return { url: '', session: active };
      if (!(error instanceof HttpFailure) || error.status !== 401) throw error as Error;
      // A token the host refuses before its expiry (e.g. clock jump) renews once.
      active = await this.ensureDirectDpopToken(active, active.token, persistRenewal);
      if (generation !== this.generation) return { url: '', session: active };
      ticket = await this.issueDirectDpopRpcTicket(active.base, active.token);
    }
    if (!ticket || ticket.length > 8192) throw new Error('WebSocket 票据无效');
    const upgradeProof = await this.signDirectDpopProof('GET', active.base + '/ws', ticket);
    return { url: socketUrl(active.base, ticket, upgradeProof), session: active };
  }

  private async httpJson(base: string, path: string, method: http.RequestMethod,
    body: string = '', token: string = '', json: boolean = false,
    cloudAuth: boolean = false, timeoutMs: number = 10000,
    extraHeaders?: Record<string, string>): Promise<Object> {
    if (cloudAuth && this.cloud) return this.cloud.requestJson(path, method, body, json, extraHeaders);
    if (token && this.saved && this.saved.kind === 'dpop' && this.saved.base === base) {
      return this.directDpopHttpJson(base, path, method, body, json, timeoutMs, extraHeaders);
    }
    return this.rawHttpJson(base, path, method, body, token ? 'Bearer ' + token : '', json, timeoutMs, extraHeaders);
  }

  private captureDirectAddresses(config: Record<string, Object>): void {
    const addresses: string[] = [];
    if (Array.isArray(config.directEndpoints)) {
      for (const value of config.directEndpoints as Object[]) {
        try { const base = serverBase(text(record(value).httpBaseUrl)); if (!addresses.includes(base)) addresses.push(base); }
        catch (_) {}
      }
    }
    this.directAddresses = addresses;
  }
  private activeBase(): string { return this.saved?.base || this.cloudBase; }
  private activeEnvironmentId(): string { return this.saved?.environmentId || this.cloudEnvironmentId; }
  canListPeerLinks(): boolean { return this.ready && this.offersPeerLinks && peerAccessGranted(this.peerAccessState, false); }
  async refreshPeerAccess(): Promise<void> {
    const rpc = this.requireRpc(); const saved = this.saved;
    const generation = ++this.peerAccessGeneration;
    if (!this.activeEnvironmentId()) throw new Error('环境凭据未加载');
    this.peerAccessState = undefined;
    const config = record(await rpc.request('server.getConfig', {}, undefined, 15000, false));
    if (rpc !== this.rpc) throw new Error('连接已变更');
    if (generation !== this.peerAccessGeneration) throw new Error('权限查询已更新');
    const environmentId = this.activeEnvironmentId();
    if (text(record(config.environment).environmentId) !== environmentId) throw new Error('环境身份不一致');
    this.captureDirectAddresses(config);
    const capabilities = record(config.environment).capabilities; const settings = config.settings;
    this.offersPeerLinks = !!capabilities && record(capabilities).peerLinks === true &&
      !!settings && record(settings).linkedEnvironmentsEnabled === true;
    const state = record(await this.httpJson(this.activeBase(), '/api/auth/session', http.RequestMethod.GET,
      '', saved?.token || '', false, !!this.cloud));
    if (rpc !== this.rpc) throw new Error('连接已变更');
    if (generation !== this.peerAccessGeneration) throw new Error('权限查询已更新');
    if (typeof state.authenticated !== 'boolean') throw new Error('环境权限响应无效');
    this.peerAccessState = state;
  }
  canManagePeerAccess(): boolean { return this.ready && peerAccessGranted(this.peerAccessState, true); }
  async mintPeerPairingCode(access: string): Promise<string> {
    const rpc = this.requireRpc(); await this.refreshPeerAccess();
    if (rpc !== this.rpc || !this.canManagePeerAccess() || !this.activeEnvironmentId()) throw new Error('此连接不能创建配对码，请粘贴该环境提供的配对码');
    const payload: PeerPairingPayload = { label: 'T3 Code link', scopes: peerPairingScopes(access) };
    const result = record(await this.httpJson(this.activeBase(), '/api/auth/pairing-token', http.RequestMethod.POST,
      JSON.stringify(payload), this.saved?.token || '', true, !!this.cloud));
    if (rpc !== this.rpc) throw new Error('连接已变更，请重新获取配对码');
    const code = text(result.credential);
    if (!code.trim() || code.length > 4096) throw new Error('配对码响应无效');
    return code;
  }
  async linkProof(payload: Object): Promise<string> {
    const rpc = this.requireRpc();
    const result = text(await this.httpJson(this.activeBase(), '/api/connect/link-proof',
      http.RequestMethod.POST, JSON.stringify(payload), this.saved?.token || '', true, !!this.cloud));
    if (rpc !== this.rpc || !result || result.length > 8192) throw new Error('环境链接证明无效');
    return result;
  }
  async configureRelay(payload: Object): Promise<void> {
    const rpc = this.requireRpc();
    await this.httpJson(this.activeBase(), '/api/connect/relay-config', http.RequestMethod.POST,
      JSON.stringify(payload), this.saved?.token || '', true, !!this.cloud);
    if (rpc !== this.rpc) throw new Error('连接已变更，请重新确认链接');
  }
  async unlinkRelay(): Promise<void> {
    const rpc = this.requireRpc();
    await this.httpJson(this.activeBase(), '/api/connect/unlink', http.RequestMethod.POST,
      '', this.saved?.token || '', false, !!this.cloud);
    if (rpc !== this.rpc) throw new Error('连接已变更');
  }
  async answerLinkRequest(id: string, answer: LinkAnswer): Promise<void> {
    const rpc = this.requireRpc(); await this.refreshPeerAccess();
    if (rpc !== this.rpc || !this.canManagePeerAccess()) throw new Error('只有管理此环境访问权限的连接才能答复');
    const item = this.thread?.items.find((row: Record<string, Object>) => row.id === id && row.type === 'link_request');
    if (!this.thread || !item || item.linkStatus !== 'pending' || item.threadId !== this.thread.threadId) throw new Error('链接请求已结束或不属于当前会话');
    await this.mutate('peerLinks.answerRequest', linkAnswerPayload(this.thread.threadId, id, answer),
      util.generateRandomUUID(), 'response');
  }
  async linkedEnvironments(): Promise<PeerLinkView[]> {
    const rpc = this.requireRpc();
    if (!this.canListPeerLinks()) throw new Error('无权查看已链接环境或环境未开启链接');
    const value = await rpc.request('peerLinks.list', {}, undefined, 15000, false);
    if (rpc !== this.rpc) throw new Error('连接已变更');
    return peerLinkViews(value);
  }
  stopAuthAccess(): void {
    const rpc = this.rpc;
    const chunk = this.accessChunk;
    this.accessChunk = undefined;
    if (rpc && chunk) rpc.cancelStream(chunk);
  }
  watchAuthAccess(onUpdate: () => void): void {
    const rpc = this.requireRpc();
    if (!this.requireDeviceApproval) throw new Error('此环境未启用 T3 Connect 设备批准');
    if (!this.canManagePeerAccess()) throw new Error('无权管理此环境的 T3 Connect 设备');
    this.accessListener = onUpdate;
    this.stopAuthAccess();
    this.authAccessLoaded = false;
    const chunk = (value: Object): void => {
      if (rpc !== this.rpc) return;
      this.authAccess = applyAuthAccessEvent(this.authAccess, value);
      this.authAccessLoaded = true;
      onUpdate();
    };
    this.accessChunk = chunk;
    void rpc.request('subscribeAuthAccess', {}, chunk, 30000, false).then(() => {
      if (this.rpc === rpc && this.accessChunk === chunk) this.authAccessLoaded = false;
    }).catch(() => {
      if (this.rpc === rpc && this.accessChunk === chunk) {
        this.accessChunk = undefined;
        this.authAccessLoaded = false;
      }
    });
  }
  async approveDevice(pairingLinkId: string): Promise<void> {
    const rpc = this.requireRpc();
    if (!this.frameDeviceIdentity(pairingLinkId)) throw new Error('设备批准请求已失效');
    const result = record(await this.httpJson(this.activeBase(), '/api/auth/connect-devices/approve',
      http.RequestMethod.POST, JSON.stringify({ pairingLinkId }), this.saved?.token || '', true, !!this.cloud));
    if (rpc !== this.rpc) throw new Error('连接已变更');
    if (result.approved !== true) throw new Error('批准请求已过期或已被其他设备处理');
    this.authAccess.pairingLinks = this.authAccess.pairingLinks.filter((link) => link.id !== pairingLinkId);
    this.refreshAuthAccess();
  }
  async denyDevice(pairingLinkId: string): Promise<void> {
    const rpc = this.requireRpc();
    if (!this.frameDeviceIdentity(pairingLinkId)) throw new Error('设备批准请求已失效');
    const result = record(await this.httpJson(this.activeBase(), '/api/auth/pairing-links/revoke',
      http.RequestMethod.POST, JSON.stringify({ id: pairingLinkId }), this.saved?.token || '', true, !!this.cloud));
    if (rpc !== this.rpc) throw new Error('连接已变更');
    if (result.revoked !== true) throw new Error('拒绝请求已过期或已被处理');
    this.authAccess.pairingLinks = this.authAccess.pairingLinks.filter((link) => link.id !== pairingLinkId);
    this.refreshAuthAccess();
  }
  async revokeDevice(proofKeyThumbprint: string): Promise<void> {
    const rpc = this.requireRpc();
    if (!proofKeyThumbprint || proofKeyThumbprint.length > 256) throw new Error('设备密钥标识无效');
    const result = record(await this.httpJson(this.activeBase(), '/api/auth/connect-devices/revoke',
      http.RequestMethod.POST, JSON.stringify({ proofKeyThumbprint }), this.saved?.token || '', true, !!this.cloud));
    if (rpc !== this.rpc) throw new Error('连接已变更');
    if (result.revoked !== true) throw new Error('设备已撤销或不存在');
    this.authAccess.devices = this.authAccess.devices.filter((device) => device.proofKeyThumbprint !== proofKeyThumbprint);
    this.refreshAuthAccess();
  }
  private refreshAuthAccess(): void {
    const listener = this.accessListener;
    if (!listener || !this.ready || !this.requireDeviceApproval) return;
    try { this.watchAuthAccess(listener); } catch (_) {}
  }
  private frameDeviceIdentity(pairingLinkId: string): boolean {
    return !!pairingLinkId && pairingLinkId.length <= 256 &&
      this.authAccess.pairingLinks.some((link) => link.id === pairingLinkId && link.expiresAt > Date.now());
  }

  async verifyIdentity(address: string): Promise<void> {
    const descriptor = validateDescriptor(await this.httpJson(serverBase(address), '/.well-known/t3/environment', http.RequestMethod.GET));
    if (!this.expectedEnvironmentId || descriptor.environmentId !== this.expectedEnvironmentId) throw new Error('服务器身份不一致，未更新地址');
  }

  async probeRoute(address: string, expectedEnvironmentId: string, timeoutMs: number = 2500): Promise<RouteProbeResult> {
    let base = '';
    try {
      base = serverBase(address);
      const descriptor = validateDescriptor(await this.httpJson(base, '/.well-known/t3/environment',
        http.RequestMethod.GET, '', '', false, false, timeoutMs));
      const environmentId = text(descriptor.environmentId);
      if (expectedEnvironmentId && environmentId !== expectedEnvironmentId) {
        return { ok: false, base, error: '服务器身份已变化，未发送配对凭据', checkedAt: Date.now() };
      }
      return { ok: true, base, descriptor, checkedAt: Date.now() };
    } catch (error) {
      return { ok: false, base, error: (error as Error).message || '探测连接路径失败', checkedAt: Date.now() };
    }
  }

  async connect(address: string, credential: string = '', prechecked?: RouteProbeResult): Promise<void> {
    if (this.cloud) return this.connectCloud();
    if ((this.mutating || this.launching) && (!this.awaitingResend || !!credential.trim())) {
      throw new Error('请求正在提交，请稍候再重连');
    }
    this.disconnect('正在鉴权', false, false, true);
    this.resumeWanted = true;
    const generation = this.generation;
    const base = serverBase(address);
    this.server = '';
    this.status = '正在鉴权';
    this.onUpdate();
    this.connectionsPending++;
    try {
      const canReusePrechecked = !credential.trim() && prechecked !== undefined && prechecked.ok &&
        prechecked.base === base && prechecked.descriptor !== undefined &&
        (Date.now() - prechecked.checkedAt) <= PRECHECKED_DESCRIPTOR_TTL_MS &&
        (!this.expectedEnvironmentId || text(prechecked.descriptor.environmentId) === this.expectedEnvironmentId);
      let descriptor: Record<string, Object>;
      if (canReusePrechecked && prechecked?.descriptor) {
        descriptor = prechecked.descriptor;
      } else {
        const hostKind = directHostKind(urlHostname(base));
        const descriptorTimeout = !credential.trim() && (hostKind === 'loopback' || hostKind === 'lan')
          ? NEARBY_DESCRIPTOR_TIMEOUT_MS : 10000;
        descriptor = validateDescriptor(await this.httpJson(base, '/.well-known/t3/environment',
          http.RequestMethod.GET, '', '', false, false, descriptorTimeout));
      }
      if (generation !== this.generation) return;
      const environmentId = text(descriptor.environmentId);
      if (this.expectedEnvironmentId && environmentId !== this.expectedEnvironmentId) {
        throw new Error('服务器身份已变化，未发送配对凭据');
      }
      this.validateIdentity(environmentId);
      this.environmentLabel = text(descriptor.label);
      this.server = text(descriptor.label) + ' · ' + text(descriptor.serverVersion);
      let saved = this.store ? await this.store.load(base) : this.saved;
      if (generation !== this.generation) return;
      let credentialsChanged = false;
      if (credential.trim()) {
        let pairingProof: string | undefined = undefined;
        if (supportsDirectDpopRenewal(descriptor) && this.dpop) {
          try {
            // Create the proof before sending the one-time code so signing failure keeps the code for Bearer.
            pairingProof = await this.dpop.prove('POST', base + '/oauth/token');
          } catch (_) {
            pairingProof = undefined;
          }
        }
        if (generation !== this.generation) return;
        const authHeaders: Record<string, string> | undefined = pairingProof ? { 'DPoP': pairingProof } : undefined;
        const auth = record(await this.rawHttpJson(base, '/oauth/token',
          http.RequestMethod.POST, bootstrapForm(credential), '', false, 10000, authHeaders));
        if (generation !== this.generation) return;
        const expectedType = pairingProof ? 'DPoP' : 'Bearer';
        if (auth.token_type !== expectedType) {
          throw new Error(pairingProof ? '服务端未返回预期的 DPoP 令牌' : '该服务要求 DPoP，当前环境不支持或未启用设备密钥');
        }
        const accessToken = text(auth.access_token);
        if (!accessToken) throw new Error('无效访问凭据');
        if (typeof auth.expires_in !== 'number' || !Number.isFinite(auth.expires_in) || auth.expires_in <= 0) {
          throw new Error('无效凭据有效期');
        }
        saved = pairingProof
          ? { base, environmentId, token: accessToken, expiresAt: Date.now() + auth.expires_in * 1000, kind: 'dpop' }
          : { base, environmentId, token: accessToken, expiresAt: Date.now() + auth.expires_in * 1000 };
        credentialsChanged = true;
      }
      if (!saved || saved.base !== base || saved.environmentId !== environmentId ||
        (saved.kind !== 'dpop' && saved.expiresAt <= Date.now())) {
        throw new Error('没有此服务器的有效会话，请输入新配对凭据');
      }
      let targetUrl = '';
      if (saved.kind === 'dpop') {
        const resolved = await this.resolveDirectDpopSocketUrl(saved, !credentialsChanged, generation);
        if (generation !== this.generation) return;
        targetUrl = resolved.url;
        saved = resolved.session;
      } else {
        const token = saved.token;
        let ticket: Object;
        try {
          ticket = await this.rawHttpJson(base, '/api/auth/websocket-ticket/rpc', http.RequestMethod.POST, '', 'Bearer ' + token);
        } catch (error) {
          if (generation !== this.generation) return;
          if (!(error instanceof HttpFailure) || error.status !== 404) throw error as Error;
          ticket = await this.rawHttpJson(base, '/api/auth/websocket-ticket', http.RequestMethod.POST, '', 'Bearer ' + token);
        }
        if (generation !== this.generation) return;
        targetUrl = socketUrl(base, text(record(ticket).ticket));
      }
      await this.finishConnection(targetUrl, environmentId, base, saved, generation, credentialsChanged);
    } catch (error) {
      if (generation === this.generation) {
        const errMsg = (error as Error).message || '';
        const nonRecoverable = error instanceof ServerConfigIncompatibleError ||
          errMsg.includes('没有此服务器的有效会话') ||
          errMsg.includes('服务器身份') || errMsg.includes('不兼容') ||
          errMsg.includes('DPoP') || errMsg.includes('配对') || errMsg.includes('HTTP 400') ||
          errMsg.includes('HTTP 401') || errMsg.includes('HTTP 403') ||
          errMsg.includes('HTTP 404') || errMsg.includes('无效');
        const canRecover = (!!this.saved || !!this.cloud || (!!this.reconnectSavedRoutes && !!this.store)) && !nonRecoverable;
        this.disconnect(errMsg, canRecover, false);
      }
    } finally {
      this.connectionsPending--;
      this.notifySessionWaiters();
    }
  }

  private async connectCloud(): Promise<void> {
    const transport = this.cloud;
    if (!transport) throw new Error('T3 Connect 传输未就绪');
    if ((this.mutating || this.launching) && !this.awaitingResend) throw new Error('请求正在提交，请稍候再重连');
    this.disconnect('正在通过 T3 Connect 授权', false, false, true);
    this.resumeWanted = true;
    const generation = this.generation;
    this.server = '';
    this.status = '正在通过 T3 Connect 授权';
    this.onUpdate();
    this.connectionsPending++;
    try {
      let base = '';
      let descriptor: Record<string, Object> | undefined = undefined;
      if (transport.cachedEndpoint) {
        try {
          const cached = await transport.cachedEndpoint();
          if (generation !== this.generation) return;
          if (cached) {
            const candidateBase = serverBase(cached.httpBaseUrl);
            const candidateDescriptor = validateDescriptor(await this.httpJson(candidateBase,
              '/.well-known/t3/environment', http.RequestMethod.GET, '', '', false, false, 5000));
            if (generation !== this.generation) return;
            const candidateEnv = text(candidateDescriptor.environmentId);
            if (candidateEnv === transport.environmentId &&
              (!this.expectedEnvironmentId || candidateEnv === this.expectedEnvironmentId)) {
              base = candidateBase;
              descriptor = candidateDescriptor;
            }
          }
        } catch (_) {
          if (generation !== this.generation) return;
        }
      }
      if (!descriptor) {
        const endpoint = await transport.endpoint();
        if (generation !== this.generation) return;
        base = serverBase(endpoint.httpBaseUrl);
        descriptor = validateDescriptor(await this.httpJson(base, '/.well-known/t3/environment', http.RequestMethod.GET));
        if (generation !== this.generation) return;
      }
      const environmentId = text(descriptor.environmentId);
      if (environmentId !== transport.environmentId ||
        (this.expectedEnvironmentId && environmentId !== this.expectedEnvironmentId)) {
        throw new Error('中继服务器身份不一致，已中止连接');
      }
      this.validateIdentity(environmentId);
      this.environmentLabel = text(descriptor.label) || transport.label;
      this.server = text(descriptor.label) + ' · ' + text(descriptor.serverVersion);
      this.status = '正在连接中继环境';
      this.onUpdate();
      const target = await transport.socketUrl();
      if (generation !== this.generation) return;
      await this.finishConnection(target, environmentId, base, undefined, generation, false);
    } catch (error) {
      if (generation === this.generation) {
        const errMsg = (error as Error).message || '';
        const nonRecoverable = error instanceof ServerConfigIncompatibleError ||
          errMsg.includes('账号已切换') || errMsg.includes('身份不一致') || errMsg.includes('不兼容');
        this.disconnect(errMsg, !nonRecoverable, false);
      }
    } finally {
      this.connectionsPending--;
      this.notifySessionWaiters();
    }
  }

  private mergeProviderDeltas(previous: Object | undefined, deltas: Object): Object[] {
    const held: Map<string, Record<string, Object>> = new Map();
    if (Array.isArray(previous)) {
      for (const entry of previous as Object[]) {
        if (entry !== null && typeof entry === 'object' && !Array.isArray(entry)) {
          const row = entry as Record<string, Object>;
          if (typeof row.instanceId === 'string') held.set(row.instanceId, row);
        }
      }
    }
    const mergedList: Object[] = [];
    for (const raw of objects(deltas)) {
      const delta = record(raw);
      const instanceId = typeof delta.instanceId === 'string' ? delta.instanceId : '';
      const base = instanceId ? held.get(instanceId) : undefined;
      const merged: Record<string, Object> = {};
      for (const key of Object.keys(delta)) merged[key] = delta[key];
      if (merged.models === undefined && base?.models !== undefined) merged.models = base.models;
      if (merged.slashCommands === undefined && base?.slashCommands !== undefined) merged.slashCommands = base.slashCommands;
      if (merged.skills === undefined && base?.skills !== undefined) merged.skills = base.skills;
      if (merged.models !== undefined) mergedList.push(merged);
    }
    return mergedList;
  }

  private incompatibleConfigMessage(): string {
    const host = this.environmentLabel || '服务端';
    return host + ' 发送了不兼容的服务器配置（服务端版本不兼容），请将客户端和服务器更新到兼容的版本。';
  }

  private incompatibleConfigUpdateMessage(): string {
    const host = this.environmentLabel || '服务端';
    return host + ' 发送了此客户端无法读取的服务器配置更新。';
  }

  private decodeServerConfig(value: Object, environmentId: string, established: boolean): Record<string, Object> {
    let cfg: Record<string, Object>;
    try {
      cfg = validateServerConfig(value);
    } catch (_) {
      throw established
        ? new ServerConfigUpdateError(this.incompatibleConfigUpdateMessage())
        : new ServerConfigIncompatibleError(this.incompatibleConfigMessage());
    }
    if (text(record(cfg.environment).environmentId) !== environmentId) {
      throw new Error('服务器身份不一致，已中止连接');
    }
    return cfg;
  }

  private applyConfigStreamEvent(value: Object, environmentId: string,
    established: boolean): Record<string, Object> | undefined {
    let event: Record<string, Object>;
    try {
      event = record(value);
      text(event.type);
    } catch (_) {
      throw established
        ? new ServerConfigUpdateError(this.incompatibleConfigUpdateMessage())
        : new ServerConfigIncompatibleError(this.incompatibleConfigMessage());
    }
    const type = event.type as string;
    if (type === 'snapshot') {
      if (event.config === undefined || event.config === null) {
        throw established
          ? new ServerConfigUpdateError(this.incompatibleConfigUpdateMessage())
          : new ServerConfigIncompatibleError(this.incompatibleConfigMessage());
      }
      return this.decodeServerConfig(event.config, environmentId, established);
    }
    if (type === 'settingsUpdated') {
      let payload: Record<string, Object>;
      try {
        payload = record(event.payload);
        if (payload.settings !== undefined && payload.settings !== null) record(payload.settings);
      } catch (_) {
        throw established
          ? new ServerConfigUpdateError(this.incompatibleConfigUpdateMessage())
          : new ServerConfigIncompatibleError(this.incompatibleConfigMessage());
      }
      if (payload.settings !== undefined && payload.settings !== null && Object.keys(this.config).length > 0) {
        const next: Record<string, Object> = {};
        for (const key of Object.keys(this.config)) next[key] = this.config[key];
        next.settings = payload.settings;
        this.applyConfig(next);
        this.notify();
      }
      return undefined;
    }
    if (type === 'providerStatuses') {
      let payload: Record<string, Object>;
      try {
        payload = record(event.payload);
        if (payload.providers !== undefined && payload.providers !== null) objects(payload.providers);
      } catch (_) {
        throw established
          ? new ServerConfigUpdateError(this.incompatibleConfigUpdateMessage())
          : new ServerConfigIncompatibleError(this.incompatibleConfigMessage());
      }
      if (payload.providers !== undefined && payload.providers !== null && Object.keys(this.config).length > 0) {
        const next: Record<string, Object> = {};
        for (const key of Object.keys(this.config)) next[key] = this.config[key];
        next.providers = payload.providers;
        this.applyConfig(next);
        this.notify();
      }
      return undefined;
    }
    if (type === 'providerStatusDeltas') {
      let payload: Record<string, Object>;
      try {
        payload = record(event.payload);
        if (payload.providers !== undefined && payload.providers !== null) objects(payload.providers);
      } catch (_) {
        throw established
          ? new ServerConfigUpdateError(this.incompatibleConfigUpdateMessage())
          : new ServerConfigIncompatibleError(this.incompatibleConfigMessage());
      }
      if (payload.providers !== undefined && payload.providers !== null && Object.keys(this.config).length > 0) {
        const next: Record<string, Object> = {};
        for (const key of Object.keys(this.config)) next[key] = this.config[key];
        next.providers = this.mergeProviderDeltas(this.config.providers, payload.providers);
        this.applyConfig(next);
        this.notify();
      }
      return undefined;
    }
    return undefined;
  }

  private async loadInitialConfig(rpc: RpcClient, generation: number,
    environmentId: string): Promise<Record<string, Object>> {
    const payload: ServerConfigSubscribePayload = {
      workspaceSnapshotsOnDemand: true,
      providerStatusDeltas: true
    };
    let locallyCancelled = false;
    try {
      return await new Promise<Record<string, Object>>((resolve, reject) => {
        let settled = false;
        let established = false;
        const finish = (config: Record<string, Object>): void => {
          if (settled) return;
          settled = true;
          established = true;
          resolve(config);
        };
        const fail = (error: Error): void => {
          if (settled) return;
          settled = true;
          reject(error);
        };
        const chunk = (value: Object): void => {
          if (rpc !== this.rpc || generation !== this.generation) {
            fail(new Error('连接已变更'));
            return;
          }
          try {
            const snapshot = this.applyConfigStreamEvent(value, environmentId, established);
            if (snapshot) {
              if (!settled) {
                finish(snapshot);
              } else {
                this.applyConfig(snapshot);
                this.notify();
              }
            }
          } catch (error) {
            const err = error as Error;
            const wasEstablished = established;
            fail(err);
            if (wasEstablished && rpc === this.rpc && generation === this.generation) {
              locallyCancelled = true;
              if (this.configChunk === chunk) this.configChunk = undefined;
              rpc.cancelStream(chunk);
              if (err.message.includes('服务器身份不一致')) {
                this.disconnect(err.message, false, false);
              } else {
                this.disconnect(err instanceof ServerConfigUpdateError
                  ? err.message : this.incompatibleConfigUpdateMessage(), true, false);
              }
            }
          }
        };
        this.configChunk = chunk;
        void rpc.request('subscribeServerConfig', payload, chunk, CONFIG_SYNC_TIMEOUT_MS, false).then(() => {
          if (this.configChunk === chunk) this.configChunk = undefined;
          if (!settled) {
            fail(new Error('FALLBACK_GET_CONFIG'));
          } else if (established && !locallyCancelled && rpc === this.rpc && generation === this.generation) {
            this.disconnect((this.environmentLabel || '服务端') + ' 配置订阅已结束，正在重连', true, false);
          }
        }).catch((error: Error) => {
          if (this.configChunk === chunk) this.configChunk = undefined;
          if (!settled) {
            fail(error);
          } else if (established && !locallyCancelled && rpc === this.rpc && generation === this.generation) {
            this.disconnect((this.environmentLabel || '服务端') + ' 配置订阅中断，正在重连', true, false);
          }
        });
      });
    } catch (error) {
      if (rpc !== this.rpc || generation !== this.generation) throw error as Error;
      const err = error as Error;
      const message = err.message || '';
      if (this.configChunk) {
        locallyCancelled = true;
        rpc.cancelStream(this.configChunk);
        this.configChunk = undefined;
      }
      if (err instanceof ServerConfigIncompatibleError || message.includes('服务器身份不一致') ||
        message.includes('不兼容')) {
        throw err;
      }
      const empty: EmptyPayload = {};
      const raw = await rpc.request('server.getConfig', empty, undefined, 30000, false);
      return this.decodeServerConfig(raw, environmentId, false);
    }
  }

  private async finishConnection(target: string, environmentId: string, base: string,
    saved: SavedSession | undefined, generation: number, credentialsChanged: boolean = false): Promise<void> {
    const socket = webSocket.createWebSocket();
    const rpc = new RpcClient(new NativeSender(socket));
    this.socket = socket;
    this.rpc = rpc;
    this.lastInbound = Date.now();
    this.inboundFrames = 0;
    rpc.onFailure = (message: string) => {
      if (generation !== this.generation) return;
      this.disconnect(message, true, false);
    };
    let opened = false;
    let openTimer = 0;
    let resolveOpen: () => void = () => {};
    let rejectOpen: (error: Error) => void = () => {};
    const openPromise = new Promise<void>((resolve, reject) => {
      resolveOpen = resolve;
      rejectOpen = reject;
    });
    const clearOpenTimer = (): void => {
      if (openTimer) { clearTimeout(openTimer); openTimer = 0; }
    };
    const settleOpen = (): void => {
      if (opened) return;
      opened = true;
      clearOpenTimer();
      resolveOpen();
    };
    const failOpen = (message: string): void => {
      if (opened) return;
      opened = true;
      clearOpenTimer();
      rejectOpen(new Error(message));
    };
    openTimer = setTimeout(() => {
      openTimer = 0;
      if (generation !== this.generation) { settleOpen(); return; }
      failOpen('WebSocket 握手超时，请检查网络和服务器状态');
    }, SOCKET_OPEN_TIMEOUT_MS) as number;

    socket.on('open', (error: BusinessError) => {
      if (generation !== this.generation) { settleOpen(); return; }
      if (error && error.code !== 0) {
        const msg = 'WebSocket 握手失败（错误码 ' + error.code + '），请检查网络和服务端版本';
        failOpen(msg);
        rpc.fail(msg);
        return;
      }
      this.lastInbound = Date.now();
      settleOpen();
    });
    socket.on('message', (error: BusinessError, data: string | ArrayBuffer) => {
      if (generation !== this.generation) return;
      if (!opened) settleOpen();
      if ((error && error.code !== 0) || typeof data !== 'string') {
        rpc.fail('收到无效 WebSocket 消息');
        return;
      }
      this.lastInbound = Date.now();
      this.inboundFrames++;
      if (this.probeInboundNotify) this.probeInboundNotify();
      rpc.receive(data);
    });
    socket.on('error', (error: BusinessError) => {
      if (generation !== this.generation) { settleOpen(); return; }
      const detail = error && typeof error.code === 'number' && error.code !== 0 ? '（错误码 ' + error.code + '）' : '';
      const msg = 'WebSocket 连接失败或中断' + detail + '；提交中的请求结果未知，请重连并核对会话';
      failOpen(msg);
      rpc.fail(msg);
    });
    socket.on('close', (_error: BusinessError, value: webSocket.CloseResult) => {
      if (generation !== this.generation) { settleOpen(); return; }
      const code = value && typeof value.code === 'number' ? value.code : 0;
      const detail = code > 0 && code !== 1000 ? '（状态码 ' + code + '）' : '';
      const msg = '连接已断开' + detail + '；提交中的任务结果未知，请重连并同步会话';
      failOpen(msg);
      rpc.fail(msg);
    });
    this.status = '正在连接与校验服务器';
    this.onUpdate();
    try {
      const connectOptions: webSocket.WebSocketRequestOptions | undefined =
        shouldBypassSystemProxy(target) ? { proxy: 'no-proxy' } : undefined;
      const started = connectOptions ? await socket.connect(target, connectOptions) : await socket.connect(target);
      if (!started) throw new Error('连接失败');
      await openPromise;
    } catch (error) {
      clearOpenTimer();
      const message = (error as Error).message || '';
      if (message.includes('WebSocket') || message.includes('连接已断开')) throw error as Error;
      throw new Error('WebSocket 连接失败，请检查网络和服务端版本');
    } finally {
      clearOpenTimer();
    }
    if (generation !== this.generation) return;
    if (!this.inBackground) this.startHeartbeat(rpc, generation);
    const config = await this.loadInitialConfig(rpc, generation, environmentId);
    if (generation !== this.generation) return;
    if (this.lastShellEnvironmentId && this.lastShellEnvironmentId !== environmentId) {
      this.shell.clear();
      this.preservedThread = undefined;
    }
    this.lastShellEnvironmentId = environmentId;
    this.cachedCapabilities = {};
    this.applyConfig(config);
    if (saved) {
      if (this.store && credentialsChanged) await this.store.save(saved);
      if (generation !== this.generation) return;
      this.saved = saved;
    } else {
      this.saved = undefined;
    }
    this.cloudBase = base;
    this.cloudEnvironmentId = environmentId;
    const recovery = this.recoveryStore ? await this.recoveryStore.load() : this.recovery;
    if (generation !== this.generation) return;
    this.recovery = recovery ? recoveryState(recovery, this.recoveryBase || base, environmentId) : undefined;
    this.sessionAccess = undefined;
    this.ready = true;
    this.connectedAt = Date.now();
    this.lastConnectionError = '';
    this.shellRetryDelay = 250;
    this.threadRetryDelay = 250;
    this.subscribeShell();
    this.status = '已连接';
    void this.refreshSessionAccess();
    const resumeThreadId = this.recovery?.threadId || (!this.draftScope ? this.lastWatchedThreadId : '');
    if (this.awaitingResend) {
      this.deferredResumeThreadId = resumeThreadId;
      this.onUpdate();
      if (this.cloud) this.scheduleCloudRenewal(generation);
      else if (saved?.kind === 'dpop') this.scheduleDirectDpopRenewal(generation);
      this.notifySessionWaiters();
      return;
    }
    this.resumingWatchThreadId = resumeThreadId;
    this.onUpdate();
    if (this.cloud) this.scheduleCloudRenewal(generation);
    else if (saved?.kind === 'dpop') this.scheduleDirectDpopRenewal(generation);
    this.notifySessionWaiters();
    if (resumeThreadId) {
      try { await this.watch(resumeThreadId); }
      finally { if (this.resumingWatchThreadId === resumeThreadId) this.resumingWatchThreadId = ''; }
    }
  }

  applyVerifiedSettingsConfig(value: Object, environmentId: string, generation: number | undefined): void {
    const config = record(value);
    if (!this.ready || generation !== this.generation || !environmentId ||
      environmentId !== this.activeEnvironmentId() || record(config.environment).environmentId !== environmentId) {
      throw new Error('设置回读环境已变化');
    }
    this.applyConfig(config); this.onUpdate();
  }

  private applyConfig(config: Record<string, Object>): void {
    this.config = config;
    this.models = config.providers ? models(config) : [];
    const environment = record(config.environment);
    this.capabilities = environment.capabilities === undefined || environment.capabilities === null ?
      {} : record(environment.capabilities);
    const platform = environment.platform === undefined || environment.platform === null ? undefined : record(environment.platform);
    this.platform = platform === undefined ? '' : objectText(platform, 'os');
    this.serverSettings = config.settings === undefined || config.settings === null ? {} : record(config.settings);
    this.newProjectsRoot = objectText(config, 'newProjectsRoot');
    this.scratchWorkspaceRoot = objectText(config, 'scratchWorkspaceRoot');
    this.addProjectBaseDirectory = objectText(this.serverSettings, 'addProjectBaseDirectory');
    this.ghqCloneLayout = objectBool(this.serverSettings, 'ghqCloneLayout');
    this.snoozePresets = snoozeSettingsFrom(this.serverSettings.snoozePresets);
    this.offeredSourceControlProviders = offeredProvidersFrom(this.serverSettings.offeredSourceControlProviders);
    this.captureDirectAddresses(config);
    this.requireDeviceApproval = !!config.settings && record(config.settings).requireConnectDeviceApproval === true;
  }

  private scheduleDirectDpopRenewal(generation: number): void {
    clearTimeout(this.directDpopRenewal); this.directDpopRenewal = 0;
    if (this.cloud || !this.ready || !this.saved || this.saved.kind !== 'dpop') return;
    const scheduleNext = (expiresAt: number): void => {
      if (generation !== this.generation || !this.ready || this.cloud ||
        !this.saved || this.saved.kind !== 'dpop') return;
      const now = Date.now();
      const floor = now < expiresAt ? 5000 : DPOP_ACCESS_TOKEN_REFRESH_SKEW_MS;
      const delay = Math.max(floor, expiresAt - DPOP_ACCESS_TOKEN_REFRESH_SKEW_MS - now);
      this.directDpopRenewal = setTimeout(() => {
        this.directDpopRenewal = 0;
        if (generation !== this.generation || !this.ready || this.cloud ||
          !this.saved || this.saved.kind !== 'dpop') return;
        const current = this.saved;
        void this.ensureDirectDpopToken(current, undefined, true).then((renewed: SavedSession) => {
          if (generation !== this.generation || !this.ready || this.cloud) return;
          scheduleNext(Math.max(expiresAt, renewed.expiresAt));
        }).catch((error: Error) => {
          if (generation !== this.generation || !this.ready || this.cloud) return;
          if (this.isBlockedDirectDpopError(error)) return;
          scheduleNext(expiresAt);
        });
      }, delay) as number;
    };
    scheduleNext(this.saved.expiresAt);
  }

  private scheduleCloudRenewal(generation: number): void {
    if (!this.cloud) return;
    clearTimeout(this.cloudRenewal); this.cloudRenewal = 0;
    const transport = this.cloud;
    const renew = (): void => {
      if (generation !== this.generation || this.cloud !== transport) return;
      void transport.renew().then((next: number) => {
        if (generation !== this.generation || this.cloud !== transport) return;
        this.cloudRenewal = setTimeout(renew, Math.max(5000, next - Date.now() - 30000));
      }).catch(() => {
        if (generation !== this.generation || this.cloud !== transport) return;
        this.status = 'T3 Connect 凭证续期失败，正在重试';
        this.onUpdate();
        this.cloudRenewal = setTimeout(renew, 30000);
      });
    };
    const knownExpiresAt = transport.tokenExpiresAt ? transport.tokenExpiresAt() : 0;
    const initialDelay = knownExpiresAt > 0 ? Math.max(5000, knownExpiresAt - Date.now() - 30000) : 30000;
    this.cloudRenewal = setTimeout(renew, initialDelay);
  }

  disconnect(message: string = '已断开；提交中的请求结果未知，请重连并同步会话', recover: boolean = false,
    clearShell: boolean = false, keepBackoff: boolean = false): void {
    const wasReady = this.ready;
    const stayedStable = wasReady && this.connectedAt > 0 && (Date.now() - this.connectedAt) >= BACKOFF_RESET_AFTER_MS;
    if (stayedStable) this.retryFailureCount = 0;
    const useFastDropRetry = wasReady && this.retryFailureCount === 0;
    if (recover) {
      this.retryFailureCount++;
      this.lastConnectionError = message;
    } else if (!keepBackoff) {
      this.retryFailureCount = 0;
      this.lastConnectionError = '';
    }
    if (!clearShell && this.thread && this.thread.cursor >= 0) {
      this.preservedThread = this.thread;
    } else if (clearShell) {
      this.preservedThread = undefined;
    }
    this.connectedAt = 0;
    this.resumeWanted = recover;
    clearTimeout(this.retryTimer); this.retryTimer = 0;
    clearTimeout(this.notifyTimer); this.notifyTimer = 0;
    clearTimeout(this.cloudRenewal); this.cloudRenewal = 0;
    clearTimeout(this.directDpopRenewal); this.directDpopRenewal = 0;
    clearTimeout(this.shellRetryTimer); this.shellRetryTimer = 0;
    clearTimeout(this.threadRetryTimer); this.threadRetryTimer = 0;
    this.generation++;
    this.mediaCache.clear();
    this.probing = undefined;
    this.probeInboundNotify = undefined;
    this.ready = false; this.peerAccessState = undefined; this.offersPeerLinks = false;
    this.requireDeviceApproval = false;
    this.authAccessLoaded = false;
    this.accessChunk = undefined;
    this.accessListener = undefined;
    this.authAccess = { pairingLinks: [], devices: [] };
    this.threadChunk = undefined;
    this.shellChunk = undefined;
    this.configChunk = undefined;
    this.worktreeChunk = undefined;
    this.worktreeSetup = undefined;
    if (clearShell) {
      this.shell.clear();
      this.cachedCapabilities = {};
      this.lastShellEnvironmentId = '';
    } else {
      this.shell.resetForReconnect();
    }
    this.models = [];
    this.config = {};
    this.capabilities = {};
    this.serverSettings = {};
    this.platform = '';
    this.newProjectsRoot = '';
    if (clearShell) this.scratchWorkspaceRoot = '';
    this.addProjectBaseDirectory = '';
    this.ghqCloneLayout = false;
    this.snoozePresets = snoozeSettingsFrom(undefined);
    this.offeredSourceControlProviders = {};
    this.sessionAccess = undefined;
    this.thread = undefined;
    this.cloudBase = '';
    this.cloudEnvironmentId = '';
    clearInterval(this.timer);
    this.timer = 0;
    const rpc = this.rpc;
    const socket = this.socket;
    this.rpc = undefined;
    this.socket = undefined;
    rpc?.fail(message);
    if (socket) void socket.close().catch(() => {});
    this.status = message;
    this.onUpdate();
    if (recover) this.retry(this.computeRetryDelay(useFastDropRetry));
    if (!keepBackoff) this.notifySessionWaiters();
  }

  async launch(projectId: string, prompt: string, settings: TaskSettings,
    workspace: DraftWorkspace = emptyWorkspace(), context: ComposerContextRecord[] = []): Promise<string> {
    this.requireRpc();
    if (this.mutationPending) throw new Error('请先核对上次提交结果');
    validateTaskSettings(this.config, projectId, settings);
    const draft: ComposerDraft = { version: 1, draftId: 'launch', localId: '', environmentId: this.activeEnvironmentId(),
      projectId, text: prompt, modelSelection: settings.modelSelection, runtimeMode: settings.runtimeMode,
      interactionMode: settings.interactionMode, workspace, attachments: [], context, updatedAt: Date.now() };
    const attachments: DraftAttachment[] = this.attachments.slice();
    const limit = attachmentLimitError(attachments);
    if (limit) throw new Error(limit);
    const threadId = util.generateRandomUUID();
    const messageId = util.generateRandomUUID();
    const input = record(launchTask(util.generateRandomUUID(), threadId, messageId, projectId, prompt, settings,
      attachments, context.length ? contextPayload(context) : undefined, launchWorkspace(draft)));
    this.launching = true;
    try {
      await this.selectRecovery(threadId);
      // Retain the allocated identity if the launch acknowledgement is lost.
      this.thread = new ThreadState(threadId);
      await this.mutate('orchestration.launchThread', input, messageId, 'message', true, true);
      if (!this.thread) this.thread = new ThreadState(threadId);
      if (workspace.mode === 'worktree') this.watchWorktreeSetup();
      this.draftScope = ''; this.attachment = undefined; this.attachments = [];
      return threadId;
    } catch (error) {
      // A known rejection created no run. Drop the provisional marker so a reconnect does not
      // open a nonexistent thread and the user can retry from the intact draft.
      if (error instanceof RpcFailure && error.known && this.recovery && !this.recovery.pendingId) {
        this.recovery = undefined;
        this.thread = undefined;
        if (this.recoveryStore) {
          try { await this.recoveryStore.clear(); } catch (_) {}
        }
      }
      throw error as Error;
    } finally { this.launching = false; this.onUpdate(); }
  }

  async configureThread(settings: TaskSettings): Promise<void> {
    if (!this.thread || this.thread.cursor < 0) throw new Error('请先同步会话');
    const projectId = typeof this.thread.details.projectId === 'string' ? this.thread.details.projectId : '';
    validateTaskSettings(this.config, projectId, settings);
    const id = util.generateRandomUUID();
    const command: ThreadSettingPayload = { type: 'thread.model-selection.set', commandId: id,
      threadId: this.thread.threadId, modelSelection: settings.modelSelection };
    const state = this.thread;
    await this.mutate('orchestration.dispatchCommand', command, id, 'response');
    if (this.thread === state) state.details.modelSelection = settings.modelSelection;
  }

  async changeThreadMode(mode: string, interaction: boolean): Promise<void> {
    if (!this.thread || this.thread.cursor < 0) throw new Error('请先同步会话');
    const id = util.generateRandomUUID();
    const command: ThreadSettingPayload = interaction ? { type: 'thread.interaction-mode.set', commandId: id,
      threadId: this.thread.threadId, interactionMode: mode } : { type: 'thread.runtime-mode.set', commandId: id,
      threadId: this.thread.threadId, runtimeMode: mode };
    const current = this.thread.details;
    const settings: TaskSettings = { modelSelection: record(current.modelSelection) as Object as ModelSelection,
      runtimeMode: interaction ? text(current.runtimeMode) : mode,
      interactionMode: interaction ? mode : text(current.interactionMode) };
    validateTaskSettings(this.config, typeof current.projectId === 'string' ? current.projectId : '', settings);
    const state = this.thread;
    await this.mutate('orchestration.dispatchCommand', command, id, 'response');
    if (this.thread === state) { if (interaction) state.details.interactionMode = mode; else state.details.runtimeMode = mode; }
  }

  async queue(action: string, runId: string = '', beforeRunId: string | null = null, prompt: string = ''): Promise<void> {
    if (!this.thread || this.thread.cursor < 0) throw new Error('请先同步会话');
    if (action === 'start' && this.thread.runs.some((run: Record<string, Object>) =>
      ['preparing', 'starting', 'running', 'waiting'].includes(String(run.status)))) {
      throw new Error('运行中不能立即开始排队消息，请使用立即引导或等待结束');
    }
    if (action !== 'resume' && !this.thread.runs.some((run: Record<string, Object>) => run.id === runId && run.status === 'queued')) {
      throw new Error('队列任务状态已变化，请同步后再操作');
    }
    const id = util.generateRandomUUID();
    const resend = action === 'start' || action === 'resume';
    await this.mutate('orchestration.dispatchCommand', queueCommand(id, this.thread.threadId, action, runId, beforeRunId, prompt), id, 'response', false, resend);
  }

  async newThread(projectId: string, instanceId: string, model: string): Promise<string> {
    const rpc = this.requireRpc();
    if (this.launching) throw new Error('新任务正在提交，请稍候');
    if (this.mutating || this.recovery?.pendingId) throw new Error('请求正在提交，请稍候');
    const previousChunk = this.threadChunk;
    this.threadChunk = undefined;
    if (previousChunk) rpc.cancelStream(previousChunk);
    const threadId = util.generateRandomUUID();
    const command = createThread(util.generateRandomUUID(), threadId, projectId, instanceId, model);
    // Keep the allocated ID even if acknowledgement is lost, so the user can reconcile it.
    this.thread = new ThreadState(threadId);
    this.onUpdate();
    await this.selectRecovery(threadId);
    await this.mutate('orchestration.dispatchCommand', command, threadId, 'create');
    return threadId;
  }

  private scheduleThreadResubscribe(threadId: string, generation: number): void {
    if (this.inBackground || !this.ready || generation !== this.generation || this.lastWatchedThreadId !== threadId) return;
    if (this.threadRetryTimer) return;
    const delay = this.threadRetryDelay;
    this.threadRetryDelay = Math.min(this.threadRetryDelay * 2, 30000);
    this.threadRetryTimer = setTimeout(() => {
      this.threadRetryTimer = 0;
      if (this.inBackground || !this.ready || generation !== this.generation || this.lastWatchedThreadId !== threadId) return;
      if (this.mutating || this.launching) return;
      void this.watch(threadId).catch(() => {});
    }, delay) as number;
  }

  async watch(threadId: string): Promise<void> {
    if (!threadId.trim()) throw new Error('请输入会话 ID');
    const rpc = this.requireRpc();
    if (this.mutating || this.launching) throw new Error('请求正在提交，请稍候');
    const normalizedId = threadId.trim();
    const generation = this.generation;
    clearTimeout(this.threadRetryTimer); this.threadRetryTimer = 0;
    this.lastWatchedThreadId = normalizedId;
    const previousChunk = this.threadChunk;
    this.threadChunk = undefined;
    if (previousChunk) rpc.cancelStream(previousChunk);
    this.recoveredMessageId = '';
    await this.selectRecovery(normalizedId);
    if (rpc !== this.rpc || generation !== this.generation) return;
    const hasPendingRecovery = !!this.recovery?.pendingId && this.recovery.threadId === normalizedId;
    const currentReusable = !hasPendingRecovery && this.thread && this.thread.threadId === normalizedId &&
      (this.thread.cursor >= 0 || this.thread.resumeCursor >= 0) ? this.thread : undefined;
    const preservedReusable = !hasPendingRecovery && this.preservedThread && this.preservedThread.threadId === normalizedId &&
      (this.preservedThread.cursor >= 0 || this.preservedThread.resumeCursor >= 0) ? this.preservedThread : undefined;
    const reusable = currentReusable || preservedReusable;
    this.preservedThread = undefined;
    let state: ThreadState;
    let afterSequence: number | undefined = undefined;
    if (reusable) {
      state = reusable;
      state.resetForReconnect();
      if (state.resumeCursor >= 0) afterSequence = state.resumeCursor;
    } else {
      state = new ThreadState(normalizedId);
    }
    this.thread = state;
    this.status = '正在同步会话';
    this.onUpdate();
    const chunk = (value: Object): void => {
      if (rpc !== this.rpc || generation !== this.generation || this.threadChunk !== chunk) return;
      try {
        state.apply(value);
      } catch (_) {
        this.threadChunk = undefined;
        rpc.cancelStream(chunk);
        this.preservedThread = undefined;
        if (this.thread === state) this.thread = new ThreadState(state.threadId);
        this.scheduleThreadResubscribe(state.threadId, generation);
        return;
      }
      const kind = typeof record(value).kind === 'string' ? text(record(value).kind) : '';
      if (kind === 'snapshot' || kind === 'synchronized') this.threadRetryDelay = 250;
      this.status = state.notices || '会话已同步';
      if (kind === 'snapshot' && this.recovery?.pendingId && !this.mutating &&
        this.recovery.threadId === state.threadId) {
        this.reconciled = true;
        const found = this.recovery.pendingKind === 'message' && state.messages.some((m) => m.id === this.recovery?.pendingId);
        if (found) this.recoveredMessageId = this.recovery.pendingId;
        this.status = found ? '已核实上次指令已接收；请确认核对，不会重复发送' :
          '上次提交结果未知；已同步完整快照，请核对后确认，禁止自动重发';
      }
      this.notify();
    };
    this.threadChunk = chunk;
    const subscribePayload: SubscribeThreadPayload = {
      threadId: state.threadId,
      acceptBoundedSnapshot: true,
      requestCompletionMarker: true,
      acceptDedupedBodies: true
    };
    if (afterSequence !== undefined) subscribePayload.afterSequence = afterSequence;
    void rpc.request('orchestration.subscribeThread', subscribePayload, chunk, STREAM_SUBSCRIBE_TIMEOUT_MS, false).then(() => {
      if (this.rpc !== rpc || generation !== this.generation || this.threadChunk !== chunk) return;
      this.threadChunk = undefined;
      if (this.recovery?.pendingId && this.recovery.threadId === state.threadId) {
        this.disconnect('会话订阅已结束，请重新连接', true, false);
        return;
      }
      this.scheduleThreadResubscribe(state.threadId, generation);
    }).catch((error: Error) => {
      if (this.rpc !== rpc || generation !== this.generation || this.threadChunk !== chunk) return;
      this.threadChunk = undefined;
      if (error instanceof RpcFailure && error.known && state.cursor < 0 &&
        (!this.recovery?.pendingId || this.recovery.threadId !== state.threadId)) {
        if (this.thread === state) this.thread = undefined;
        if (this.recovery && !this.recovery.pendingId && this.recovery.threadId === state.threadId) {
          this.recovery = undefined;
          if (this.recoveryStore) void this.recoveryStore.clear().catch(() => {});
        }
        this.status = '已连接';
        this.onUpdate();
        return;
      }
      if (this.recovery?.pendingId && this.recovery.threadId === state.threadId) {
        this.disconnect(error.message, true);
        return;
      }
      this.scheduleThreadResubscribe(state.threadId, generation);
    });
  }

  async send(prompt: string, delivery: string = 'start', context: ComposerContextRecord[] = []): Promise<void> {
    const rpc = this.requireRpc();
    if (!this.thread || this.thread.cursor < 0) throw new Error('请先同步会话');
    const threadId = this.thread.threadId;
    const messageId = util.generateRandomUUID();
    const command = record(sendMessage(util.generateRandomUUID(), threadId, messageId, prompt));
    if (!['auto', 'start', 'queue', 'steer'].includes(delivery)) throw new Error('无效发送方式');
    if (delivery === 'queue') { const mode: MessageDispatchMode = { type: 'queue_after_active' }; command.dispatchMode = mode; }
    if (delivery === 'steer' || delivery === 'auto') command.deliveryIntent = delivery;
    if (this.attachments.length) {
      if (this.attachmentThread !== threadId) throw new Error('附件属于其他会话，请重新选择');
      command.attachments = this.attachments.slice();
    }
    if (context.length) command.context = contextPayload(context);

    this.status = '正在提交';
    this.onUpdate();
    await this.mutate('orchestration.dispatchCommand', command, messageId, 'message', false, true);
    this.attachment = undefined; this.attachments = [];
    this.status = '指令已确认，请等待回复';
    this.onUpdate();
  }

  async listBranches(cwd: string, query: string = ''): Promise<BranchView[]> {
    const rpc = this.requireRpc();
    const value = await rpc.request('vcs.listRefs', branchListInput(cwd, query), undefined, 15000, false);
    if (rpc !== this.rpc) throw new Error('连接已变更，请重新加载分支');
    return branches(value);
  }
  async refreshVcs(cwd: string): Promise<VcsView> {
    const rpc = this.requireRpc();
    const value = await rpc.request('vcs.refreshStatus', refreshStatusInput(cwd), undefined, 15000, false);
    if (rpc !== this.rpc) throw new Error('连接已变更');
    return applyVcsStatus(emptyVcs(), value);
  }
  async switchBranch(cwd: string, branch: string): Promise<void> {
    const rpc = this.requireRpc();
    await rpc.request('vcs.switchRef', switchBranchInput(cwd, branch), undefined, 30000, false);
    if (rpc !== this.rpc) throw new Error('连接已变更，请重新加载分支');
  }
  async searchFiles(cwd: string, query: string, imageOnly: boolean = false): Promise<string[]> {
    const rpc = this.requireRpc();
    const payload: FileSearchPayload = { cwd, query: query.slice(0, 256), limit: 40 };
    if (imageOnly) payload.imageOnly = true;
    const value = record(await rpc.request('projects.searchEntries', payload, undefined, 10000, false));
    if (rpc !== this.rpc) throw new Error('连接已变更');
    return objects(value.entries).map((entry: Object) => text(record(entry).path));
  }
  threadCwd(): string {
    if (this.thread && typeof this.thread.details.worktreePath === 'string') return this.thread.details.worktreePath;
    const projectId = this.thread && typeof this.thread.details.projectId === 'string' ? this.thread.details.projectId : '';
    const project = this.shell.projects.find((entry: ProjectView) => entry.id === projectId);
    return project ? project.workspaceRoot : '';
  }
  async listWorkspaceEntries(cwd: string, directoryPath: string): Promise<WorkspaceEntry[]> {
    const rpc = this.requireRpc();
    const value = await rpc.request('projects.listEntries', listEntriesInput(cwd, directoryPath), undefined, 15000, false);
    if (rpc !== this.rpc) throw new Error('连接已变更，请重新打开文件');
    return workspaceEntries(value);
  }
  async searchWorkspaceContents(cwd: string, query: string, regex: boolean = false): Promise<ContentMatch[]> {
    const rpc = this.requireRpc();
    const value = await rpc.request('projects.searchContents', contentSearchInput(cwd, query, regex), undefined, 20000, false);
    if (rpc !== this.rpc) throw new Error('连接已变更，请重新搜索');
    return contentMatches(value);
  }
  async readWorkspaceFile(cwd: string, relativePath: string): Promise<WorkspaceFile> {
    const rpc = this.requireRpc();
    const value = await rpc.request('projects.readFile', readFileInput(cwd, relativePath), undefined, 20000, false);
    if (rpc !== this.rpc) throw new Error('连接已变更，请重新打开文件');
    return workspaceFile(value);
  }
  async workspaceFileUrl(cwd: string, path: string, inline: boolean = true): Promise<string> {
    const rpc = this.requireRpc();
    const resource = workspaceAssetResource(!this.draftScope && this.thread ? this.thread.threadId : '', cwd, path, !inline);
    const payload: Record<string, Object> = {};
    payload.resource = resource;
    const value = record(await rpc.request('assets.createUrl', payload, undefined, 15000, false));
    if (rpc !== this.rpc) throw new Error('连接已变更');
    const relative = text(value.relativeUrl);
    if (typeof value.expiresAt !== 'number' || value.expiresAt <= Date.now()) throw new Error('文件链接已过期');
    return this.activeBase() + relative;
  }
  async markdownMediaUrl(source: string, cwd: string = '', refresh: boolean = false): Promise<ResolvedMarkdownMedia> {
    const effectiveCwd = cwd || this.threadCwd();
    const classified = classifyMarkdownMediaSource(source, effectiveCwd);
    if (classified.access === 'blocked') throw new Error('不支持此图片或媒体路径');
    if (classified.access === 'direct') {
      return {
        url: classified.uri,
        kind: classified.kind,
        displayPath: classified.displayPath,
        expiresAt: 0,
        width: 0,
        height: 0
      };
    }
    const rpc = this.requireRpc();
    const generation = this.generation;
    const threadId = !this.draftScope && this.thread ? this.thread.threadId : '';
    const resource = markdownMediaAssetResource(threadId, effectiveCwd, classified, false);
    const cacheKey = this.mediaCache.key(generation, threadId, effectiveCwd, classified.path);
    return this.mediaCache.resolve(generation, cacheKey, async (): Promise<ResolvedMarkdownMedia> => {
      const payload: Record<string, Object> = {};
      payload.resource = resource;
      const value = record(await rpc.request('assets.createUrl', payload, undefined, 15000, false));
      if (rpc !== this.rpc || generation !== this.generation) throw new Error('连接已变更');
      const relative = text(value.relativeUrl);
      const expiresAt = typeof value.expiresAt === 'number' ? value.expiresAt : 0;
      if (expiresAt <= Date.now()) throw new Error('文件链接已过期');
      const url = safeAssetUrl(this.activeBase(), relative);
      let width = 0;
      let height = 0;
      if (value.imageDimensions && typeof value.imageDimensions === 'object') {
        const dims = record(value.imageDimensions);
        if (typeof dims.width === 'number' && dims.width > 0 && typeof dims.height === 'number' && dims.height > 0) {
          width = dims.width;
          height = dims.height;
        }
      }
      return {
        url,
        kind: classified.kind,
        displayPath: classified.displayPath,
        expiresAt,
        width,
        height
      };
    }, refresh);
  }
  async downloadWorkspaceFile(cwd: string, path: string): Promise<ArrayBuffer> {
    const url = await this.workspaceFileUrl(cwd, path, false);
    const request = http.createHttp();
    try {
      const options: http.HttpRequestOptions = withDirectProxyPolicy(url, {
        method: http.RequestMethod.GET, usingCache: false,
        maxRedirects: 0, connectTimeout: 10000, readTimeout: 60000, expectDataType: http.HttpDataType.ARRAY_BUFFER
      });
      const response = await request.request(url, options);
      if (response.responseCode !== 200) throw new Error('文件下载失败（' + response.responseCode + '）');
      if (response.result instanceof ArrayBuffer) return response.result;
      throw new Error('文件响应不是二进制数据');
    } finally { request.destroy(); }
  }
  async reviewDiffPreview(cwd: string, baseRef: string = '', sourceKind: string = '',
    trackedOnly: boolean = false, ignoreWhitespace: boolean = false): Promise<ReviewPreview> {
    const rpc = this.requireRpc();
    const value = await rpc.request('review.getDiffPreview',
      reviewPreviewInput(cwd, baseRef, sourceKind, trackedOnly, ignoreWhitespace), undefined, 30000, false);
    if (rpc !== this.rpc) throw new Error('连接已变更，请重新加载 Diff');
    return reviewPreview(value);
  }
  watchVcsStatus(cwd: string, onUpdate: (value: VcsView) => void): ((value: Object) => void) {
    let current = emptyVcs();
    return this.watchRpcStream('subscribeVcsStatus', vcsWatchInput(cwd), (value: Object) => {
      current = applyVcsStatus(current, value);
      onUpdate(current);
    });
  }
  async gitAction(cwd: string, action: string, commitMessage: string = '', featureBranch: boolean = false,
    filePaths: string[] = [], onProgress: (label: string) => void = () => {}): Promise<Object> {
    if (!this.ready) throw new Error('连接尚未就绪');
    if (this.canScope('source-control:write') === false) throw new Error('此连接不能修改源码管理');
    const threadId = this.thread ? this.thread.threadId : '';
    const projectId = this.thread && typeof this.thread.details.projectId === 'string' ? this.thread.details.projectId : '';
    const payload = gitActionInput(util.generateRandomUUID(), cwd, action, commitMessage, featureBranch, filePaths,
      threadId, projectId);
    const rpc = this.requireRpc();
    const generation = this.generation;
    let result: Object | undefined = undefined;
    const chunk = (value: Object): void => {
      const row = record(value);
      const kind = typeof row.kind === 'string' ? row.kind : '';
      if (kind === 'action_started' || kind === 'phase_started') {
        onProgress(typeof row.label === 'string' ? row.label : kind);
      } else if (kind === 'hook_output' && typeof row.text === 'string' && row.text.trim()) {
        onProgress(row.text.trim().slice(0, 200));
      } else if (kind === 'action_finished' && row.result !== undefined && row.result !== null) {
        result = record(row.result);
      } else if (kind === 'action_failed') {
        onProgress('Git 操作失败');
      }
    };
    const exit = await rpc.request('git.runStackedAction', payload, chunk, 120000, false);
    if (rpc !== this.rpc || generation !== this.generation) throw new Error('连接已变更，请刷新后核对 Git 状态');
    if (result === undefined && exit !== null && exit !== undefined) result = record(exit);
    if (result === undefined) throw new Error('Git 操作已结束但未返回结果，请刷新状态核对');
    return result;
  }
  async pullRepository(cwd: string): Promise<Object> {
    if (this.canScope('source-control:write') === false) throw new Error('此连接不能拉取源码');
    return this.rpcRequest('vcs.pull', pullInput(cwd), 120000, false);
  }
  async workspaceRefs(cwd: string, query: string = ''): Promise<RefView[]> {
    const rpc = this.requireRpc();
    const value = await rpc.request('vcs.listRefs', listRefs(cwd, query), undefined, 20000, false);
    if (rpc !== this.rpc) throw new Error('连接已变更，请重新加载分支');
    return refs(value);
  }
  async checkoutRef(cwd: string, refName: string): Promise<void> {
    if (!this.canWriteSourceControl()) throw new Error('此连接不能切换 checkout 分支');
    await this.rpcRequest('vcs.switchRef', switchRefInput(cwd, refName), 60000, false);
  }
  async listPullRequests(state: string, query: string, cursor: string = '',
    projectId: string = '', cursors?: Record<string, string>): Promise<PullRequestPage> {
    const rpc = this.requireRpc();
    const value = record(await rpc.request('pullRequests.list',
      pullRequestListInput(state, query, cursor, projectId, cursors), undefined, 30000, false));
    if (rpc !== this.rpc) throw new Error('连接已变更，请重新加载拉取请求');
    const parsed = pullRequestRows(value);
    const nextCursors = parsePullRequestCursors(value.nextCursors);
    const next = firstPullRequestCursor(nextCursors);
    return { rows: parsed.rows, errors: parsed.errors, truncated: parsed.truncated, nextCursor: next, nextCursors };
  }
  async pullRequestDetail(ref: Object): Promise<PullRequestDetailView> {
    const rpc = this.requireRpc();
    const value = await rpc.request('pullRequests.detail', ref, undefined, 30000, false);
    if (rpc !== this.rpc) throw new Error('连接已变更，请重新打开拉取请求');
    return pullRequestDetail(value);
  }

  async pullRequestChecks(ref: Object): Promise<PullRequestChecksView | undefined> {
    const rpc = this.requireRpc();
    const value = await rpc.request('pullRequests.checks', ref, undefined, 30000, false);
    if (rpc !== this.rpc) throw new Error('连接已变更，请重新打开拉取请求');
    return pullRequestChecks(value);
  }

  async pullRequestReviewGuide(ref: Object): Promise<PullRequestGuideView> {
    const rpc = this.requireRpc();
    const value = await rpc.request('pullRequests.reviewGuide', ref, undefined, 30000, false);
    if (rpc !== this.rpc) throw new Error('连接已变更，请重新打开拉取请求');
    return pullRequestGuide(value);
  }

  async generatePullRequestReviewGuide(ref: Object): Promise<PullRequestGuideView> {
    const rpc = this.requireRpc();
    const value = await rpc.request('pullRequests.generateReviewGuide', ref, undefined, 60000, false);
    if (rpc !== this.rpc) throw new Error('连接已变更，请重新打开拉取请求');
    return pullRequestGuide(value);
  }
  linkedPullRequests(): LinkedPullRequestView[] {
    return this.thread ? linkedPullRequests(this.thread.details) : [];
  }
  async watchLinkedPullRequest(link: LinkedPullRequestView, watching: boolean): Promise<void> {
    if (!this.thread) throw new Error('请先选择会话');
    const id = util.generateRandomUUID();
    const command = linkedPullRequestCommand('thread.pull-request.watch', id, this.thread.threadId, link, watching);
    await this.mutate('orchestration.dispatchCommand', command, id, 'response');
  }
  async unlinkLinkedPullRequest(link: LinkedPullRequestView): Promise<void> {
    if (!this.thread) throw new Error('请先选择会话');
    const id = util.generateRandomUUID();
    const command = linkedPullRequestCommand('thread.pull-request.unlink', id, this.thread.threadId, link);
    await this.mutate('orchestration.dispatchCommand', command, id, 'response');
  }
  async pullRequestActivity(ref: Object): Promise<PullRequestActivityView> {
    const rpc = this.requireRpc();
    const value = await rpc.request('pullRequests.activity', ref, undefined, 30000, false);
    if (rpc !== this.rpc) throw new Error('连接已变更，请重新打开拉取请求');
    return pullRequestActivity(value);
  }
  async pullRequestDiff(ref: Object, cursor: string = '', path: string = ''): Promise<Object> {
    const source = record(ref);
    const payload: Record<string, Object> = {};
    for (const key of Object.keys(source)) payload[key] = source[key];
    if (cursor) payload.cursor = cursor;
    if (path) payload.path = path;
    return this.httpJson(this.activeBase(), '/api/pull-requests/diff', http.RequestMethod.POST,
      JSON.stringify(payload), this.saved?.token || '', true, !!this.cloud, 60000);
  }
  async pullRequestComment(ref: Object, body: string): Promise<Object> {
    return this.rpcRequest('pullRequests.comment', commentInput(ref, body), 60000, false);
  }
  async pullRequestReview(ref: Object, verdict: string, body: string, comments: Object[] = []): Promise<Object> {
    return this.rpcRequest('pullRequests.submitReview', reviewSubmitInput(ref, verdict, body, comments), 60000, false);
  }
  async pullRequestAction(ref: Object, action: string, mergeMethod: string = '',
    updateMethod: string = ''): Promise<Object> {
    return this.rpcRequest('pullRequests.runAction', actionInput(ref, action, mergeMethod, updateMethod), 120000, false);
  }
  async pullRequestStack(ref: Object): Promise<Object> {
    return this.rpcRequest('pullRequests.stack', ref, 30000, false);
  }
  async pullRequestLinkedThreads(ref: Object): Promise<Object> {
    return this.rpcRequest('pullRequests.linkedThreads', ref, 30000, false);
  }
  async setPullRequestReaction(ref: Object, subjectId: string, reaction: string): Promise<Object> {
    const source = record(ref);
    const payload: Record<string, Object> = {};
    for (const key of Object.keys(source)) payload[key] = source[key];
    if (subjectId) payload.subjectId = subjectId;
    payload.content = reaction;
    payload.reacted = true;
    return this.rpcRequest('pullRequests.setReaction', payload, 30000, false);
  }
  async pullRequestReply(ref: Object, threadId: string, body: string): Promise<Object> {
    const source = record(ref);
    const payload: Record<string, Object> = {};
    for (const key of Object.keys(source)) payload[key] = source[key];
    payload.threadId = threadId;
    payload.body = body;
    return this.rpcRequest('pullRequests.replyToThread', payload, 60000, false);
  }
  async pullRequestSetThreadResolution(ref: Object, threadId: string, resolved: boolean): Promise<Object> {
    const source = record(ref);
    const payload: Record<string, Object> = {};
    for (const key of Object.keys(source)) payload[key] = source[key];
    payload.threadId = threadId;
    payload.resolved = resolved;
    return this.rpcRequest('pullRequests.setThreadResolution', payload, 60000, false);
  }
  async pullRequestUpdate(ref: Object, title: string, body: string): Promise<Object> {
    const source = record(ref);
    const payload: Record<string, Object> = {};
    for (const key of Object.keys(source)) payload[key] = source[key];
    if (title.trim()) payload.title = title.trim();
    if (body) payload.body = body;
    return this.rpcRequest('pullRequests.update', payload, 60000, false);
  }
  async pullRequestRequestReviewers(ref: Object, reviewers: ReviewerSelection[],
    requested: boolean): Promise<Object> {
    const source = record(ref);
    const payload: Record<string, Object> = {};
    for (const key of Object.keys(source)) payload[key] = source[key];
    payload.reviewers = reviewers;
    payload.requested = requested;
    return this.rpcRequest('pullRequests.requestReviewers', payload, 60000, false);
  }
  async pullRequestReviewerCandidates(ref: Object): Promise<Object> {
    return this.rpcRequest('pullRequests.reviewerCandidates', ref, 30000, false);
  }
  async pullRequestSetLabels(ref: Object, labels: string[], applied: boolean): Promise<Object> {
    const source = record(ref);
    const payload: Record<string, Object> = {};
    for (const key of Object.keys(source)) payload[key] = source[key];
    payload.labels = labels;
    payload.applied = applied;
    return this.rpcRequest('pullRequests.setLabels', payload, 60000, false);
  }
  async pullRequestLabelCandidates(ref: Object): Promise<Object> {
    return this.rpcRequest('pullRequests.labelCandidates', ref, 30000, false);
  }
  providerSkills(): string[] {
    const result: string[] = [];
    for (const value of objects(this.config.providers || [])) {
      const provider = record(value);
      if (provider.enabled === false || provider.installed === false) continue;
      for (const skill of objects(provider.skills || [])) {
        const row = record(skill);
        if (row.enabled === false) continue;
        const name = typeof row.name === 'string' ? row.name : '';
        if (name && !result.includes(name)) result.push(name);
      }
    }
    return result;
  }
  providerCommands(): string[] {
    const result: string[] = [];
    for (const value of objects(this.config.providers || [])) {
      const provider = record(value);
      if (provider.enabled === false || provider.installed === false) continue;
      for (const command of objects(provider.slashCommands || [])) {
        const name = typeof record(command).name === 'string' ? text(record(command).name) : '';
        if (name && !result.includes(name)) result.push(name);
      }
    }
    return result;
  }
  async refreshProviders(instanceId: string = ''): Promise<void> {
    const rpc = this.requireRpc();
    const payload: ProviderRefreshPayload = { fresh: true, refreshModels: true };
    if (instanceId) payload.instanceId = instanceId;
    await rpc.request('server.refreshProviders', payload, undefined, 30000, false);
    if (rpc !== this.rpc) throw new Error('连接已变更');
    const config = record(await rpc.request('server.getConfig', {}));
    if (rpc !== this.rpc) throw new Error('连接已变更');
    this.applyConfig(config); this.onUpdate();
  }
  async installProvider(instanceId: string): Promise<Record<string, Object>> {
    if (!this.canScope('providers:manage') && this.canScope('providers:manage') === false) {
      throw new Error('此连接不能管理 Provider');
    }
    const rpc = this.requireRpc();
    const payload: ProviderInstancePayload = { instanceId };
    const value = record(await rpc.request('provider.install.start', payload, undefined, 30000, false));
    if (rpc !== this.rpc) throw new Error('连接已变更');
    return value;
  }
  async startProviderAuth(instanceId: string): Promise<Record<string, Object>> {
    const rpc = this.requireRpc();
    const payload: ProviderInstancePayload = { instanceId };
    const value = record(await rpc.request('provider.auth.start', payload, undefined, 30000, false));
    if (rpc !== this.rpc) throw new Error('连接已变更');
    return value;
  }
  async cancelProviderAuth(instanceId: string, flowId: string): Promise<void> {
    const payload: ProviderAuthCancelPayload = { instanceId, flowId };
    await this.rpcRequest('provider.auth.cancel', payload, 15000, false);
  }
  currentUsage(): TokenUsage | undefined {
    if (!this.thread) return undefined;
    const turns = this.thread.providerTurns.filter((row: Record<string, Object>) => row.turnTokenUsage !== undefined);
    if (!turns.length) return undefined;
    const latest = turns[turns.length - 1];
    const usage = record(latest.turnTokenUsage);
    const inputTokens = typeof usage.inputTokens === 'number' ? usage.inputTokens : 0;
    const outputTokens = typeof usage.outputTokens === 'number' ? usage.outputTokens : 0;
    if (usage.usageStatus !== 'complete' && inputTokens === 0 && outputTokens === 0) return undefined;
    const usageView: TokenUsage = { usedTokens: inputTokens + outputTokens, maxTokens: 0, inputTokens, outputTokens,
      cost: '', toolUses: 0, durationMs: 0 };
    return usageView;
  }
  threadSubagents(): SubagentView[] {
    if (!this.thread) return [];
    const rows = subagents(this.thread.subagents);
    for (const row of rows) {
      const child = this.shell.threads.find((thread) => thread.id === row.childThreadId ||
        (row.remoteThreadId !== '' && thread.id === row.remoteThreadId));
      row.pendingKind = child ? child.pendingKind : '';
    }
    return rows;
  }
  threadTurnSubagents(): ThreadTurnSubagentsView | undefined {
    if (!this.thread) return undefined;
    return deriveThreadTurnSubagents(this.thread.runs, this.thread.subagents, this.shell.threads);
  }
  threadPendingBackgroundTasks(): PendingBackgroundTaskView[] {
    if (!this.thread) return [];
    const shellThread = this.shell.threads.find((thread) => thread.id === this.thread?.threadId);
    return derivePendingBackgroundWork(
      this.thread.runs,
      this.thread.providerThreads,
      this.thread.items,
      this.thread.details,
      shellThread ? shellThread.pendingBackgroundTasks : []
    );
  }
  threadPendingBackgroundWork(): PendingBackgroundWorkView | undefined {
    return presentPendingBackgroundWork(this.threadPendingBackgroundTasks());
  }
  threadBackgroundTasks(): BackgroundTaskView[] {
    return this.threadPendingBackgroundTasks().map((task: PendingBackgroundTaskView): BackgroundTaskView => ({
      id: task.taskId,
      label: task.label,
      kind: task.kind,
      childThreadId: task.childThreadId
    }));
  }
  threadGuestShare(): GuestShareView | undefined {
    return this.thread ? guestShare(this.thread.details.guestShare) : undefined;
  }
  async forceStop(runId: string): Promise<void> {
    if (!this.thread) throw new Error('请先选择会话');
    if (!this.supports('threadForceStop')) throw new Error('服务端不支持强制停止');
    const id = util.generateRandomUUID();
    await this.rpcRequest('orchestration.forceStopThread',
      forceStopCommand(id, this.thread.threadId, runId));
  }
  async stopSubagent(subagentId: string): Promise<void> {
    if (!this.thread) throw new Error('请先选择会话');
    const subagent = this.thread.subagents.find((row: Record<string, Object>) => row.id === subagentId);
    if (!subagent || !this.threadSubagents().find((row: SubagentView) => row.id === subagentId)?.canStop) {
      throw new Error('子任务已结束或不可停止');
    }
    const childThreadId = typeof subagent.childThreadId === 'string' ? subagent.childThreadId : '';
    if (subagent.origin === 'app_owned' && childThreadId) {
      const id = util.generateRandomUUID();
      await this.mutate('orchestration.dispatchCommand', stopCommand(id, childThreadId), id, 'response');
      return;
    }
    const runId = typeof subagent.runId === 'string' ? subagent.runId : '';
    if (!runId) throw new Error('子任务缺少运行标识');
    const id = util.generateRandomUUID();
    const command: SubagentStopCommand = { type: 'subagent.stop', commandId: id,
      threadId: this.thread.threadId, runId, subagentId };
    await this.mutate('orchestration.dispatchCommand', command, id, 'response');
  }
  async promoteQueued(runId: string): Promise<void> {
    if (!this.thread) throw new Error('请先选择会话');
    const target = this.thread.runs.find((run: Record<string, Object>) =>
      ['preparing', 'starting', 'running', 'waiting'].includes(String(run.status)));
    if (!target) throw new Error('当前没有可引导的运行');
    const id = util.generateRandomUUID();
    await this.mutate('orchestration.dispatchCommand',
      promoteCommand(id, this.thread.threadId, runId, text(target.id)), id, 'response', false, true);
  }
  async forkThread(runId: string, sideChat: boolean = false, sourceThreadIdOverride: string = '', title: string = ''): Promise<string> {
    if (!this.thread) throw new Error('请先选择会话');
    const targetThreadId = util.generateRandomUUID();
    const sourceThreadId = sourceThreadIdOverride.trim() || this.thread.threadId;
    const id = util.generateRandomUUID();
    await this.mutate('orchestration.dispatchCommand',
      forkThreadCommand(id, sourceThreadId, targetThreadId, runId, title, sideChat), id, 'response');
    return targetThreadId;
  }
  async createGuestShare(): Promise<string> {
    if (!this.thread) throw new Error('请先选择会话');
    const rpc = this.requireRpc();
    const result = record(await rpc.request('guestShare.create', { threadId: this.thread.threadId }, undefined, 15000, false));
    if (rpc !== this.rpc) throw new Error('连接已变更');
    return text(result.url);
  }
  async closeGuestShare(): Promise<void> {
    if (!this.thread) throw new Error('请先选择会话');
    const id = util.generateRandomUUID();
    const command: GuestCloseCommand = { type: 'thread.guest-share.close', commandId: id, threadId: this.thread.threadId };
    await this.mutate('orchestration.dispatchCommand', command, id, 'response');
  }
  async resolveGuestMessage(guestMessageId: string, send: boolean): Promise<void> {
    if (!this.thread) throw new Error('请先选择会话');
    const id = util.generateRandomUUID();
    const mode: MessageDispatchMode = { type: 'queue_after_active' };
    const command: GuestMessageCommand = send ?
      { type: 'message.dispatch', commandId: id, threadId: this.thread.threadId,
        messageId: util.generateRandomUUID(), text: '', attachments: [], guestMessageId,
        createdBy: 'user', creationSource: 'mobile', dispatchMode: mode } :
      { type: 'thread.guest-message.dismiss', commandId: id, threadId: this.thread.threadId, guestMessageId };
    await this.mutate('orchestration.dispatchCommand', command, id, 'response');
  }
  async retryPreparedRun(runId: string): Promise<void> {
    if (!this.thread) throw new Error('请先选择会话');
    const id = util.generateRandomUUID();
    const command: PreparedRetryCommand = { type: 'prepared-run.retry', commandId: id,
      threadId: this.thread.threadId, runId };
    await this.mutate('orchestration.dispatchCommand', command, id, 'response');
  }
  async resumeLatestRun(): Promise<void> {
    if (!this.thread) throw new Error('请先选择会话');
    const runs = this.thread.runs;
    const latest = latestExecutedRun(runs);
    if (!latest) throw new Error('此会话没有可恢复的运行');
    const status = text(latest.status);
    const errorClass = typeof this.thread.details.lastErrorClass === 'string' ? this.thread.details.lastErrorClass : '';
    if (status !== 'interrupted' && !(status === 'failed' && errorClass === 'usage_limit')) {
      throw new Error('最近一次运行无需恢复');
    }
    const threadId = this.thread.threadId;
    const runId = text(latest.id);
    const id = util.generateRandomUUID();
    const mode: MessageDispatchMode = { type: 'start_immediately' };
    const command: ResumeMessageCommand = { type: 'message.dispatch', commandId: id, createdBy: 'user',
      creationSource: 'mobile', threadId, messageId: util.generateRandomUUID(),
      text: '', attachments: [], manualContinuationOfRunId: runId, dispatchMode: mode };
    if (this.thread.details.modelSelection !== undefined && this.thread.details.modelSelection !== null) {
      command.modelSelection = record(this.thread.details.modelSelection) as Object as ModelSelection;
    }
    await this.mutate('orchestration.dispatchCommand', command, id, 'message', false, true);
    const held = runs.some((run: Record<string, Object>) => run.status === 'queued' && run.queueHeld === true);
    if (held) {
      const queueId = util.generateRandomUUID();
      await this.mutate('orchestration.dispatchCommand',
        queueCommand(queueId, threadId, 'resume', ''), queueId, 'response', false, true);
    }
  }
  async writeWorkspaceFile(cwd: string, relativePath: string, contents: string): Promise<string> {
    if (!this.canWriteSourceControl()) throw new Error('此连接没有写入权限');
    if (!cwd.trim() || !relativePath.trim() || relativePath.startsWith('/') || relativePath.length > 512) {
      throw new Error('工作区路径无效');
    }
    const input: WriteFileInput = { cwd, relativePath, contents };
    const value = record(await this.rpcRequest('projects.writeFile', input, 30000, false));
    return text(value.relativePath);
  }
  async setLimitRecovery(autoResume: boolean | undefined, snooze: boolean | undefined): Promise<void> {
    if (!this.thread) throw new Error('请先选择会话');
    const details = this.thread.details;
    const latestRunId = typeof details.latestRunId === 'string' ? details.latestRunId : '';
    const resetAt = typeof details.usageLimitResetAt === 'string' ? details.usageLimitResetAt : '';
    if (!latestRunId || !resetAt) throw new Error('此运行没有可安排的用量恢复时间');
    const recovery: LimitRecoveryUpdate = { runId: latestRunId, resetAt };
    if (autoResume !== undefined) recovery.autoResume = autoResume;
    if (snooze !== undefined) recovery.snooze = snooze;
    const id = util.generateRandomUUID();
    const command: MetadataLimitCommand = { type: 'thread.metadata.update', commandId: id,
      threadId: this.thread.threadId, limitRecovery: recovery };
    await this.mutate('orchestration.dispatchCommand', command, id, 'response');
  }
  async turnItem(itemId: string): Promise<Record<string, Object> | undefined> {
    if (!this.thread) throw new Error('请先选择会话');
    if (!itemId || itemId.length > 256) throw new Error('会话条目标识无效');
    const payload: TurnItemPayload = { threadId: this.thread.threadId, itemId };
    const value = record(await this.rpcRequest('orchestration.getTurnItem', payload, 15000, false));
    return value.item === undefined || value.item === null ? undefined : record(value.item);
  }
  commandOutput(itemId: string, onFrame: (value: Object) => void): (value: Object) => void {
    if (!this.thread) throw new Error('请先选择会话');
    const payload: CommandOutputPayload = { threadId: this.thread.threadId, itemId };
    return this.watchRpcStream('orchestration.subscribeCommandOutput', payload, onFrame);
  }
  async loadOlderHistory(): Promise<boolean> {
    if (!this.ready || !this.thread || !this.thread.historyCursor || !this.thread.hasMoreHistory) return false;
    const state = this.thread;
    const path = '/api/orchestration/threads/' + encodeURIComponent(state.threadId) +
      '/history?cursor=' + encodeURIComponent(state.historyCursor);
    const protocolHeaders: Record<string, string> = { 'x-t3-orchestration-protocol': '2' };
    const value = record(await this.httpJson(this.activeBase(), path, http.RequestMethod.GET,
      '', this.saved?.token || '', false, !!this.cloud, 15000, protocolHeaders));
    if (this.thread !== state) return false;
    const items: Record<string, Object>[] = [];
    for (const projected of objects(value.items)) {
      const row = record(projected);
      if (row.item !== undefined && row.item !== null) {
        const extractedItem = record(row.item);
        if (row.visibility !== undefined) extractedItem.visibility = row.visibility;
        if (row.sourceThreadId !== undefined) extractedItem.sourceThreadId = row.sourceThreadId;
        items.push(extractedItem);
      }
    }
    state.prependHistory(items);
    state.historyCursor = typeof value.nextCursor === 'string' ? value.nextCursor : '';
    state.hasMoreHistory = value.hasMoreHistory === true;
    this.onUpdate();
    return true;
  }
  async attachmentUrl(id: string, name: string, mimeType: string, inline: boolean): Promise<string> {
    const rpc = this.requireRpc();
    const resource: AttachmentResource = { _tag: 'attachment', attachmentId: id, fileName: name,
      mimeType, disposition: inline ? 'inline' : 'attachment' };
    const input: AssetUrlInput = { resource };
    const value = record(await rpc.request('assets.createUrl', input, undefined, 15000, false));
    if (rpc !== this.rpc) throw new Error('连接已变更');
    const relative = text(value.relativeUrl);
    if (typeof value.expiresAt !== 'number' || value.expiresAt <= Date.now()) throw new Error('附件链接已过期');
    return this.activeBase() + relative;
  }
  async downloadAttachment(id: string, name: string, mimeType: string): Promise<ArrayBuffer> {
    const url = await this.attachmentUrl(id, name, mimeType, false);
    const request = http.createHttp();
    try {
      const options: http.HttpRequestOptions = withDirectProxyPolicy(url, {
        method: http.RequestMethod.GET, usingCache: false,
        maxRedirects: 0, connectTimeout: 10000, readTimeout: 60000, expectDataType: http.HttpDataType.ARRAY_BUFFER
      });
      const response = await request.request(url, options);
      if (response.responseCode !== 200) throw new Error('附件下载失败（' + response.responseCode + '）');
      if (response.result instanceof ArrayBuffer) return response.result;
      throw new Error('附件响应不是二进制数据');
    } finally { request.destroy(); }
  }
  async cancelWorktreeSetup(): Promise<void> {
    if (!this.thread) throw new Error('请先选择会话');
    const payload: ThreadIdPayload = { threadId: this.thread.threadId };
    await this.rpcRequest('worktreeSetup.cancel', payload, 10000, false);
  }

  watchWorktreeSetup(): void {
    if (!this.thread) return;
    const rpc = this.requireRpc();
    const previous = this.worktreeChunk;
    if (previous) rpc.cancelStream(previous);
    this.worktreeSetup = undefined;
    const threadId = this.thread.threadId;
    const chunk = (value: Object): void => {
      if (rpc !== this.rpc) return;
      if (typeof value !== 'object' || value === null || Array.isArray(value)) {
        this.worktreeSetup = undefined; return;
      }
      this.worktreeSetup = record(value);
      this.onUpdate();
    };
    this.worktreeChunk = chunk;
    void rpc.request('subscribeWorktreeSetup', { threadId }, chunk, 600000, false).catch(() => {
      if (rpc === this.rpc && this.worktreeChunk === chunk) this.worktreeSetup = undefined;
    });
  }

  private scheduleShellResubscribe(generation: number): void {
    if (this.inBackground || !this.ready || generation !== this.generation) return;
    if (this.shellRetryTimer) return;
    const delay = this.shellRetryDelay;
    this.shellRetryDelay = Math.min(this.shellRetryDelay * 2, 30000);
    this.shellRetryTimer = setTimeout(() => {
      this.shellRetryTimer = 0;
      if (this.inBackground || !this.ready || generation !== this.generation) return;
      this.subscribeShell();
    }, delay) as number;
  }

  private subscribeShell(): void {
    const rpc = this.requireRpc();
    const generation = this.generation;
    clearTimeout(this.shellRetryTimer); this.shellRetryTimer = 0;
    const previous = this.shellChunk;
    if (previous) rpc.cancelStream(previous);
    const chunk = (value: Object): void => {
      if (rpc !== this.rpc || generation !== this.generation || this.shellChunk !== chunk) return;
      try {
        this.shell.apply(value);
      } catch (_) {
        this.shellChunk = undefined;
        rpc.cancelStream(chunk);
        this.shell.resetForReconnect();
        this.shell.resumeCursor = -1;
        this.scheduleShellResubscribe(generation);
        return;
      }
      if (this.shell.liveSynced) {
        this.shellRetryDelay = 250;
        if (this.onShellUpdated) this.onShellUpdated();
      }
      this.onUpdate();
    };
    this.shellChunk = chunk;
    const payload: SubscribeShellPayload = {
      requestCompletionMarker: true,
      omitIdleSubagents: true
    };
    if (this.shell.hasSnapshot && this.shell.resumeCursor >= 0) {
      payload.afterSequence = this.shell.resumeCursor;
    }
    void rpc.request('orchestration.subscribeShell', payload, chunk, STREAM_SUBSCRIBE_TIMEOUT_MS, false).then(() => {
      if (this.rpc !== rpc || generation !== this.generation || this.shellChunk !== chunk) return;
      this.shellChunk = undefined;
      this.scheduleShellResubscribe(generation);
    }).catch(() => {
      if (this.rpc !== rpc || generation !== this.generation || this.shellChunk !== chunk) return;
      this.shellChunk = undefined;
      this.scheduleShellResubscribe(generation);
    });
  }
  refreshShell(): void {
    if (this.ready) this.subscribeShell();
  }

  async forget(): Promise<void> {
    this.disconnect('已断开；提交中的请求结果未知，请重连并同步会话', false, true);
    this.lastWatchedThreadId = '';
    this.resumingWatchThreadId = '';
    this.preservedThread = undefined;
    this.lastConnectionError = '';
    this.retryFailureCount = 0;
    this.saved = undefined;
    this.recovery = undefined;
    this.attachment = undefined; this.attachments = []; this.attachmentThread = ''; this.draftScope = '';
    if (this.recoveryStore) await this.recoveryStore.clear();
    if (this.store) await this.store.clear();
  }

  async stop(): Promise<void> {
    if (!this.thread) throw new Error('请先选择会话');
    const id = util.generateRandomUUID();
    await this.mutate('orchestration.dispatchCommand', stopCommand(id, this.thread.threadId), id, 'stop');
  }

  async respond(requestId: string, decision: string, answers: Record<string, Object>,
    attachmentsByQuestionId: Record<string, Object[]> = {}): Promise<void> {
    if (!this.thread) throw new Error('请先选择会话');
    const request = this.thread.requests.find((row: Record<string, Object>) => row.id === requestId);
    if (!request || request.status !== 'pending' || record(request.responseCapability).type === 'not_resumable') {
      throw new Error('请求已失效，请同步状态');
    }
    const commandId = util.generateRandomUUID();
    const command = record(respondCommand(commandId, this.thread.threadId, requestId, decision, answers));
    if (Object.keys(attachmentsByQuestionId).length) command.attachmentsByQuestionId = attachmentsByQuestionId;
    await this.mutate('orchestration.dispatchCommand', command, commandId, 'response');
  }

  async dismissInput(requestId: string): Promise<void> {
    if (!this.thread) throw new Error('请先选择会话');
    const request = this.thread.requests.find((row: Record<string, Object>) => row.id === requestId);
    const item = this.thread.items.find((row: Record<string, Object>) =>
      row.type === 'user_input_request' && row.requestId === requestId);
    if (!request || request.status !== 'pending' || !item ||
      !(item.responseMode === 'message' || record(request.responseCapability).type === 'message')) {
      throw new Error('此问题不能关闭');
    }
    const id = util.generateRandomUUID();
    await this.mutate('orchestration.dispatchCommand',
      dismissInputCommand(id, this.thread.threadId, requestId), id, 'response');
  }

  async secret(itemId: string, value: string, decline: boolean): Promise<void> {
    if (!this.thread) throw new Error('请先选择会话');
    const item = this.thread.items.find((row: Record<string, Object>) => row.id === itemId);
    if (!item || item.type !== 'secret_request' || item.secretStatus !== 'pending' ||
      (item.visibility !== undefined && item.visibility !== 'local')) throw new Error('敏感输入请求已失效或需在原会话回答');
    if (!decline && item.fields !== undefined) throw new Error('此敏感输入请求需要按字段提交');
    if (!decline && !value.trim()) throw new Error('请输入敏感值');
    try {
      await this.mutate('secrets.answerRequest', secretAnswer(this.thread.threadId, itemId, decline ? value : value.trim(), decline),
        util.generateRandomUUID(), 'secret');
    } catch (error) {
      throw mapSecretRequestError(error as Object);
    }
  }
  async secretValues(itemId: string, values: Record<string, string>): Promise<void> {
    if (!this.thread) throw new Error('请先选择会话');
    const item = this.thread.items.find((row: Record<string, Object>) => row.id === itemId);
    if (!item || item.type !== 'secret_request' || item.secretStatus !== 'pending' ||
      (item.visibility !== undefined && item.visibility !== 'local')) throw new Error('敏感输入请求已失效或需在原会话回答');
    const fields = parseSecretFields(item.fields);
    if (item.fields === undefined || fields.length === 0) throw new Error('此敏感输入请求不支持多字段提交');
    const payload = secretValuesAnswer(this.thread.threadId, itemId, values, fields);
    try {
      await this.mutate('secrets.answerRequest', payload, util.generateRandomUUID(), 'secret');
    } catch (error) {
      throw mapSecretRequestError(error as Object);
    }
  }
  async secretReference(itemId: string, provider: string, reference: string): Promise<void> {
    if (!this.thread) throw new Error('请先选择会话');
    const item = this.thread.items.find((row: Record<string, Object>) => row.id === itemId);
    if (!item || item.type !== 'secret_request' || item.secretStatus !== 'pending' ||
      (item.visibility !== undefined && item.visibility !== 'local')) throw new Error('敏感输入请求已失效或需在原会话回答');
    if (item.fields !== undefined) throw new Error('多字段敏感输入不支持秘密引用');
    if (this.config.secretRequestReferences !== true) throw new Error('服务端不支持秘密引用');
    const providers = this.serverSettings.secretProviders;
    if (!providers || typeof providers !== 'object' || Array.isArray(providers) ||
      !Object.keys(providers as Record<string, Object>).includes(provider)) {
      throw new Error('请选择服务端已配置的秘密来源');
    }
    try {
      await this.mutate('secrets.answerRequest',
        secretReferenceAnswer(this.thread.threadId, itemId, provider, reference), util.generateRandomUUID(), 'secret');
    } catch (error) {
      throw mapSecretRequestError(error as Object);
    }
  }

  async upload(name: string, bytes: ArrayBuffer, mimeType: string = 'application/octet-stream',
    type: string = 'file', stillSelected: () => boolean = () => true): Promise<void> {
    const rpc = this.requireRpc();
    if ((!this.draftScope && !this.thread) || !this.activeEnvironmentId() || this.mutationPending) throw new Error('请先同步会话并核对未知提交');
    const threadId = this.draftScope || this.thread!.threadId;
    const captured = this.captureAttachmentTarget();
    const current = (): boolean => captured() && stillSelected();
    if (!current()) throw new Error('附件目标已变化，请重新选择');
    const target = await this.uploadOne(name, bytes, mimeType, type, current);
    if (!current()) throw new Error('附件目标已变化，请重新选择');
    const next = (this.attachmentThread === threadId ? this.attachments : []).concat([target]);
    const limit = attachmentLimitError(next);
    if (limit) {
      void rpc.request('attachments.delete', { attachmentId: target.id }).catch(() => {});
      throw new Error(limit);
    }
    this.attachmentThread = threadId; this.attachments = next; this.attachment = target;
  }

  async uploadOne(name: string, bytes: ArrayBuffer, mimeType: string = 'application/octet-stream',
    type: string = 'file', stillSelected: () => boolean = () => true): Promise<Attachment> {
    const rpc = this.requireRpc();
    if (!this.activeEnvironmentId() || this.mutationPending) throw new Error('请先连接并核对未知提交');
    const base = this.activeBase();
    // Validate local metadata before requesting an upload capability.
    attachmentRecord({ type, id: 'validation', name, mimeType, sizeBytes: bytes.byteLength });
    const result = await rpc.request('attachments.createUploadUrl', { type, name,
      mimeType, sizeBytes: bytes.byteLength }, undefined, 15000, false);
    const target = uploadAttachmentTarget(result, type, name, mimeType, bytes.byteLength);
    const request = http.createHttp();
    try {
      if (rpc !== this.rpc || !stillSelected()) throw new Error('附件目标已变化，请重新选择');
      this.uploadRequest = request;
      const targetUrl = base + target.path;
      const options: http.HttpRequestOptions = withDirectProxyPolicy(targetUrl, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/octet-stream' }, extraData: bytes,
        maxRedirects: 0, usingCache: false, connectTimeout: 10000, readTimeout: 60000
      });
      const response = await request.request(targetUrl, options);
      if (response.responseCode !== 204) throw new Error('upload rejected');
      if (rpc !== this.rpc || this.uploadRequest !== request || !stillSelected()) throw new Error('attachment target changed');
      return target.attachment;
    } catch (error) {
      throw new Error('附件上传未确认；可重新选择或手动重试，不会自动提交消息');
    }
    finally { if (this.uploadRequest === request) this.uploadRequest = undefined; request.destroy(); }
  }

  cancelUpload(): void {
    const request = this.uploadRequest;
    this.uploadRequest = undefined;
    request?.destroy();
  }

  removeAttachment(id: string): void {
    if (this.attachmentThread !== (this.draftScope || this.thread?.threadId)) return;
    this.attachments = this.attachments.filter((item: Attachment) => item.id !== id);
    this.attachment = this.attachments.length ? this.attachments[0] : undefined;
  }
  bindDraftAttachments(scope: string): void {
    if (scope && this.attachments.length) this.attachmentThread = scope;
  }

  private async selectRecovery(threadId: string): Promise<void> {
    if (!this.activeEnvironmentId()) throw new Error('请先连接服务器');
    if (this.recovery?.pendingId && this.recovery.threadId !== threadId) throw new Error('请先核对原会话的未知提交');
    if (this.recovery?.threadId === threadId) return;
    if (!this.draftScope) this.attachmentScopeRevision++;
    this.attachment = undefined; this.attachments = []; this.attachmentThread = '';
    this.worktreeSetup = undefined;
    this.recovery = { base: this.recoveryBase || this.activeBase(), environmentId: this.activeEnvironmentId(), threadId,
      pendingId: '', pendingKind: '' };
    await this.saveRecovery();
  }

  private requireRpc(): RpcClient {
    if (!this.ready || !this.rpc) throw new Error('请先连接服务器');
    return this.rpc;
  }
}

const emptyClient = new T3Client();
export let client: T3Client = emptyClient;
export function bindClient(value: T3Client | undefined): void { client = value || emptyClient; }
