import { peekShortcut, consumeShortcut } from '../services/ShortcutInbox';
import { DraftDefaults, readDraftDefaults } from '../protocol/DraftDefaults';
import { registerSharedFile } from '../services/ShareCache';
import { AndroidDevicePanel } from '../components/AndroidDevicePanel';
import { KeyboardCommands, KeyboardInput, KeyboardContext } from '../protocol/Keyboard';
import { followUpDelivery } from '../protocol/Settings';
import { DevicePickerPanel } from '../components/DevicePickerPanel';
import { DevicePreviewPanel } from '../components/DevicePreviewPanel';
import { DevicePreviewChoice, DeviceStreamAccess, safeDeviceHubBase } from '../protocol/DevicePreview';
import { VoiceInputPanel } from '../components/VoiceInputPanel';
import { NotificationTarget, NotificationRun } from '../protocol/LocalNotifications';
import { configureNotificationTargets, setVisibleNotificationThread, observeThreadNotifications,
  peekNotificationTarget, clearNotificationTarget } from '../services/LocalNotifications';
import { PreviewPanel } from '../components/PreviewPanel';
import { image } from '@kit.ImageKit';
import { PreviewTab, previewTabs, PreviewResizeViewport, PreviewViewport, PreviewZoomResult,
  previewResizeInput, verifyPreviewResize, previewZoomInput, previewZoomTarget, verifyPreviewZoom, previewNeedsZoomRepair, repairPreviewZoom100 } from '../protocol/Preview';
import { ShareImportPanel } from '../components/ShareImportPanel';
import { loadStagedShareThumbnail, peekIncomingShare, removeIncomingShare, removeIncomingShareAttachment, withStagedShareAttachment } from '../services/ShareInbox';
import { IncomingShareAttachment, MAX_SHARED_TEXT_CHARS, SharePart, shareDraftText } from '../protocol/IncomingShare';
import { TerminalPanel } from '../components/TerminalPanel';
import { TerminalSize, terminalInput, terminalAccess } from '../protocol/Terminal';
import { TaskSettings, ModelSelection, OptionSelection, QueuedRun, queuedRuns, validateTaskSettings, modelOptionsSummary } from '../protocol/Composer';
import { BranchView, branches, ComposerContextRecord, ComposerDraft, composerDraftLabel, composerDraft, contextRecord,
  draftSettings, emptyWorkspace, DraftWorkspace, switchDraftWorkspaceMode, draftWorkspaceForBranch, mentionContext, skillContext, attachmentLimitError,
  terminalContext,
  BranchView as R4Branch, proposedPlans, PlanView, SubagentView, GuestShareView, GuestMessageView,
  BackgroundTaskView, tokenUsage, TokenUsage, DraftAttachment } from '../protocol/R4';
import { draftStore } from '../storage/DraftStore';
import { ComposerCommandPanel } from '../components/ComposerCommandPanel';
import { ThreadExtrasPanel } from '../components/ThreadExtrasPanel';
import { FloatingStatusCapsule } from '../components/FloatingStatusCapsule';
import { ThreadAgentsPanel } from '../components/ThreadAgentsPanel';
import { ThreadBackgroundWorkPanel } from '../components/ThreadBackgroundWorkPanel';
import {
  BACKGROUND_WORK_STOP_RETRY_AFTER_MS,
  BackgroundStopRequest,
  DelayedConnectionUiState,
  deriveFloatingCapsuleModel,
  emptyFloatingCapsule,
  FloatingCapsuleModel,
  initialDelayedConnectionUiState,
  isBackgroundWorkStopPending,
  PendingBackgroundTaskView,
  stepDelayedConnectionUi
} from '../protocol/FloatingStatus';
import { MessageFooter } from '../components/MessageFooter';
import { CollapsibleUserMessageBody } from '../components/CollapsibleUserMessageBody';
import { MessageWorkSlot, ThreadActivity, ThreadThinkingRow } from '../components/ThreadActivity';
import {
  ActivityLine, buildMessageFooterMap, deriveLiveThinkingRow, emptyLiveThinkingRow, emptyWorkMap,
  formatMessageTimestamp, groupWorkByMessage, isPlainUserText, LiveThinkingRow,
  MessageFooterMeta, MessageWorkMap, toggleExpandedUserMessage, TurnWorkGroup, visibleWorkItems
} from '../protocol/ThreadItems';
import { TaskSettingsPanel } from '../components/TaskSettingsPanel';
import { QueuePanel } from '../components/QueuePanel';
import { PeerLinkForm } from '../components/PeerLinkForm';
import { LinkMachine, linkReachableAddresses, linkOrigin } from '../protocol/LinkTarget';
import { LinkedEnvironmentGroup } from '../components/LinkedEnvironmentsSection';
import { takePairingLink } from '../services/PairingInbox';
import { pairingTarget } from '../protocol/Pairing';
import { AttachmentPicker } from '../services/AttachmentPicker';
import { client, bindClient, T3Client } from '../services/T3Client';
import { environments, EnvironmentRegistry } from '../services/EnvironmentRegistry';
import { EnvironmentEntry, environmentRoutes, DirectRoute } from '../protocol/Environment';
import { ConnectionsPanel } from '../components/ConnectionsPanel';
import { PairingScanCard } from '../components/PairingScanCard';
import { PairingTarget } from '../protocol/Pairing';
import { ChatMessage, objects, parseModelSelection, record, text } from '../protocol/Wire';
import { MarkdownView } from '../components/MarkdownView';
import { classifyMarkdownMediaSource, ResolvedMarkdownMedia } from '../protocol/Markdown';
import { FilesPanel } from '../components/FilesPanel';
import { ReviewPanel } from '../components/ReviewPanel';
import { GitPanel } from '../components/GitPanel';
import { PullRequestsPanel } from '../components/PullRequestsPanel';
import { picker, fileIo, fileUri } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { Choice, ModelChoice, ActionCard, cards, LinkRequestView, linkRequests, linkAccessChoices } from '../protocol/Core';
import { MessageSource } from '../components/MessageSource';
import { RequestCard } from '../components/RequestCard';
import { pasteboard } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { cloud, CloudEnvironmentView, CloudManager } from '../services/CloudManager';
import { CloudAccountPanel } from '../components/CloudAccountPanel';
import { takeCloudCallback } from '../services/CloudCallbackInbox';
import { CloudDevice, CloudPairingLink, deviceApprovalPrompts } from '../protocol/Cloud';
import {
  ArchiveEnvironmentEntry, ArchiveProjectGroup, ProjectGroup, ProjectView, ScopedProject, ScopedThread, ThreadCapabilities,
  ThreadProjectRef, ThreadShelfState, ThreadView, attachPendingSubagentRequests, buildArchiveGroups, buildProjectGroups, buildThreadShelves,
  newTaskDestination, pickableProjectGroups, projectGroupRefs, samePath, scopedProjectView, scopedThreadView,
  sortProjectGroups, topOfPinnedRun
} from '../protocol/Projects';
import { WorkspaceActions, WorkspaceUndo } from '../services/Workspace';
import { rememberThreadProject, saveWorkspacePreferences, setWorkingShelfEnabled, workspacePrefs } from '../services/WorkspacePrefs';
import { ThreadList } from '../components/ThreadList';
import { ProjectPicker } from '../components/ProjectPicker';
import { AddProjectPanel } from '../components/AddProjectPanel';
import { ProjectOverviewPanel } from '../components/ProjectOverviewPanel';
import { ArchivePanel } from '../components/ArchivePanel';
import { SettingsPanel } from '../components/SettingsPanel';
import { UsagePanel } from '../components/UsagePanel';
import { SnoozePanel } from '../components/SnoozePanel';
import { ThreadRenamePanel } from '../components/ThreadRenamePanel';
import { FontSize, LineHeight, Opacity, Radius, Sizes, Space, Weight } from '../common/Theme';
import { TopBar } from '../components/ui/TopBar';
import { GroupCard } from '../components/ui/GroupCard';
import { FormRow } from '../components/ui/FormRow';
import { IconButton } from '../components/ui/IconButton';
import { composerModelShortName, providerLogoKind } from '../protocol/ThreadRow';
import { AppButton } from '../components/ui/AppButton';
import { ProjectMonogram } from '../components/ui/ProjectMonogram';
import { ProviderLogo } from '../components/ui/ProviderLogo';
import { HomeBottomBar, HomeTab } from '../components/ui/HomeBottomBar';

interface PreviewViewportPayload { _tag: string; width: number; height: number; }
interface DeviceActionPayload { hostId: string; deviceId: string; type: string; value: string; }
interface DeviceOpenPayload { threadId: string; hostId: string; deviceId: string; platform: string; boot: boolean; }
interface PreviewRefPayload { threadId: string; tabId?: string; }
interface PreviewOpenPayload { threadId: string; url: string; runtime: string; viewport: PreviewViewportPayload; }
interface TerminalRefPayload { threadId: string; terminalId: string; }
interface TerminalAttachPayload { threadId: string; terminalId: string; cwd: string; cols: number; rows: number; resume: boolean; restartIfNotRunning: boolean; maxHistoryBytes: number; }
interface TerminalResizePayload { threadId: string; terminalId: string; cols: number; rows: number; }
interface TerminalClosePayload { threadId: string; terminalId: string; deleteHistory: boolean; }
interface ProjectUpdatePatch { title?: string; pinned?: boolean; archived?: boolean; }
interface ShareUploadPlan {
  shareId: number; draftId: string; localId: string; environmentId: string; projectId: string;
  uploaded: Map<string, DraftAttachment>;
}

@Entry
@Component
struct Index {
  private keyboard: KeyboardCommands = new KeyboardCommands();
  @State composerFocused: boolean = false;
  @State searchFocused: boolean = false;
  private composingText: boolean = false;

  @StorageLink('t3ShortcutGeneration') @Watch('openShortcut') shortcutGeneration: number = 0;
  private shortcutOpening: boolean = false;
  private shortcutDraftsLoaded: boolean = false;
  @StorageLink('t3NotificationTargetRevision') @Watch('openNotificationTarget') notificationRevision: number = 0;
  private openingNotification: boolean = false;
  private voiceTarget: string = '';
  @StorageLink('t3IncomingShareRevision') @Watch('shareChanged') shareRevision: number = 0;
  @State shareId: number = 0;
  @State shareParts: SharePart[] = [];
  @State shareAttachments: IncomingShareAttachment[] = [];
  @State shareDestination: string = '';
  @State shareError: string = '';
  @State savingShare: boolean = false;
  @State uploadingShare: boolean = false;
  @State shareUploadedCount: number = 0;
  private shareUploadPlan: ShareUploadPlan | undefined = undefined;
  private shareUploadOwner: T3Client | undefined = undefined;
  private shareUploadCancelled: boolean = false;
  private shareLocalId: string = '';
  private shareProjectId: string = '';
  private choosingShare: boolean = false;
  private startingNewTask: boolean = false;

  @StorageLink('t3CloudRevision') @Watch('cloudChanged') cloudRevision: number = 0;
  @StorageLink('t3CloudCallbackRevision') @Watch('incomingCloudCallback') cloudCallbackRevision: number = 0;
  @StorageLink('t3Foreground') @Watch('refreshLinkedOnForeground') appForeground: boolean = true;
  @State linkedGroups: LinkedEnvironmentGroup[] = [];
  private linkedSignature: string = '';
  private linkedGeneration: number = 0;
  @StorageLink('t3PairingRevision') @Watch('incomingPairing') pairingRevision: number = 0;
  private alive: boolean = false;
  @State selectedLocalId: string = '';
  @State environmentFilter: string = '';
  @State threadSortOrder: string = 'updated_at';
  @State scopedThreads: ScopedThread[] = [];
  @State scopedProjects: ScopedProject[] = [];
  @State projectFilterId: string = '';
  @State projectFilterLocalId: string = '';
  @State projectFilterKey: string = '';
  @State projectFilterRefs: string[] = [];
  @State projectFilterLabel: string = '所有项目';
  @State projectGroups: ProjectGroup[] = [];
  @State shelves: ThreadShelfState = {
    pinned: [], active: [], working: [], snoozed: [], settled: [], matches: [],
    workingShelfEnabled: true, workingCount: 0, snoozedCount: 0, settledCount: 0
  };
  @State threadCapabilities: Record<string, ThreadCapabilities> = {};
  @State turnableThreads: Record<string, boolean> = {};
  @State threadQuery: string = '';
  @State threadSearchHits: Record<string, string> = {};
  @State nowMs: number = Date.now();
  @State pickerEnvironmentId: string = '';
  @State pickerQuery: string = '';
  @State addProjectEnvironmentId: string = '';
  @State addProjectReturn: string = 'choose-project';
  @State projectPickerReturn: string = 'sessions';
  @State overviewGroupKey: string = '';
  @State archiveGroups: ArchiveProjectGroup[] = [];
  @State archiveEnvironmentId: string = '';
  @State archiveQuery: string = '';
  @State archiveSort: string = 'newest';
  @State archiveLoading: boolean = false;
  @State snoozeThread: ScopedThread | undefined = undefined;
  @State renameThread: ScopedThread | undefined = undefined;
  @State undoNotice: WorkspaceUndo | undefined = undefined;
  @State settledLimit: number = 10;
  @State workingExpanded: boolean = false;
  @State snoozedExpanded: boolean = false;
  @State settledExpanded: boolean = true;
  private workspaceActions: WorkspaceActions | undefined = undefined;
  private searchGeneration: number = 0;
  private searchTimer: number = 0;
  private archiveGeneration: number = 0;
  private archiveSnapshots: Record<string, Object> = {};
  private clockTimer: number = 0;
  private snoozeTimer: number = 0;
  private undoTimer: number = 0;
  @State environmentEntries: EnvironmentEntry[] = [];
  @State environmentStatuses: Record<string, string> = {};
  @State environmentReady: Record<string, boolean> = {};
  @State loaded: boolean = false;
  @State canResumeLatestRun: boolean = false;
  private pickers: Map<string, AttachmentPicker> = new Map();
  @State linkItems: LinkRequestView[] = [];
  @State linkMachines: LinkMachine[] = [];
  @State activeLink: LinkRequestView | undefined = undefined;
  @State peerCanAnswer: boolean = false;
  private linkOwner: T3Client | undefined = undefined;
  private linkPermissionKey: string = '';
  private linkPermissionGeneration: number = 0;
  @State deviceChoice: DevicePreviewChoice | undefined = undefined;
  private deviceHubPath: string = '';
  private previewConnection: T3Client | undefined = undefined;
  private previewThreadId: string = '';
  private previewGeneration: number = 0;
  private previewKey: string = '';
  private previewAddress: string = '';
  private previewTabs: Map<string, string> = new Map();
  private terminalConnection: T3Client | undefined = undefined;
  private terminalThreadId: string = '';
  private terminalCwd: string = '';
  @State restoringEnvironments: boolean = false;
  @State anyEnvironmentReady: boolean = false;
  @State anyEnvironmentHasShell: boolean = false;
  @State anyEnvironmentLiveSynced: boolean = false;
  @State reconnectingCount: number = 0;
  @State offlineCount: number = 0;
  @State settingsSection: string = '';
  @State page: string = 'sessions';
  @State searchOpen: boolean = false;
  @State homeTabDetailOpen: boolean = false;
  @State showTools: boolean = false;
  @State threadTerminalEnabled: boolean = false;
  @Provide('t3CanOpenDiff') canOpenDiff: boolean = false;
  @Provide('t3WorkMap') workMap: MessageWorkMap = emptyWorkMap();
  @Provide('t3ExpandedWork') expandedWorkGroups: Record<string, boolean> = {};
  @Provide('t3ExpandedUserMessages') expandedUserMessages: Record<string, boolean> = {};
  @Provide('t3MessageFooterMap') messageFooterMap: Record<string, MessageFooterMeta> = {};
  @Provide('t3ForkingMessageId') forkingMessageId: string = '';
  @Provide('t3CanOperateChat') canOperateChat: boolean = false;
  private lastWorkThreadKey: string = '';
  private renderedThreadKey: string = '';
  @State hasMoreHistory: boolean = false;
  @State chatAwayFromBottom: boolean = false;
  @State threadRunning: boolean = false;
  private pendingScrollBottomKey: string = '';
  private lastAutoWatchKey: string = '';
  @State cachedChatTitle: string = '';
  @State cachedChatProject: string = '';
  @State panelOpen: boolean = false;
  @State panel: string = 'server';
  @State address: string = '';
  @State credential: string = '';
  @State routeFor: string = '';
  @State pairingStatus: string = '填写地址与配对码后确认';
  @State pairingError: boolean = false;
  @State projectId: string = '';
  @State modelIndex: number = 0;
  @State draftMode: boolean = false;
  @State taskSettings: TaskSettings = { modelSelection: { instanceId: '', model: '' }, runtimeMode: 'approval-required', interactionMode: 'default' };
  @State activeModelInstanceId: string = '';
  @State activeModelDriver: string = '';
  @State activeModelSlug: string = '';
  @State activeModelLabel: string = '';
  @State activeModelSummary: string = '';
  @State activeDraftId: string = '';
  private draftModelCustomized: boolean = false;
  @State draftRecords: ComposerDraft[] = [];
  @State draftWorkspace: DraftWorkspace = emptyWorkspace();
  @State draftContext: ComposerContextRecord[] = [];
  @State branches: BranchView[] = [];
  @State branchesLoading: boolean = false;
  @State commandPanel: string = '';
  @State commandQuery: string = '';
  @State mentionFiles: string[] = [];
  @State attachments: DraftAttachment[] = [];
  @State requestAttachments: Record<string, DraftAttachment[]> = {};
  @State extraPlans: PlanView[] = [];
  @State extraSubagents: SubagentView[] = [];
  @State extraBackground: BackgroundTaskView[] = [];
  @State extraGuest: GuestShareView | undefined = undefined;
  @State extraUsage: TokenUsage | undefined = undefined;
  @State floatingCapsule: FloatingCapsuleModel = emptyFloatingCapsule();
  @State liveThinking: LiveThinkingRow = emptyLiveThinkingRow();
  @State turnSubagents: SubagentView[] = [];
  @State pendingBackgroundItems: PendingBackgroundTaskView[] = [];
  @State forceStoppingKey: string = '';
  @State backgroundStopRequest: BackgroundStopRequest | undefined = undefined;
  private backgroundStopTimer: number = 0;
  @State worktreeSetup: Record<string, Object> | undefined = undefined;
  @State selectedAttachment: DraftAttachment | undefined = undefined;
  @State attachmentPreviewUrl: string = '';
  @State attachmentStatus: string = '';
  @State markdownImageUrl: string = '';
  @State markdownImageKind: string = 'image';
  @State markdownImagePath: string = '';
  @State promptSuggestion: string = '';
  @State draftEnvironmentError: string = '';
  @State pendingDraftId: string = '';
  private draftSaveTimer: number = 0;
  @State sendMode: string = 'auto';
  @State queued: QueuedRun[] = [];
  @State threadId: string = '';
  @State prompt: string = '';
  @State status: string = '未连接';
  @State server: string = '';
  @State ready: boolean = false;
  private connUiState: DelayedConnectionUiState = initialDelayedConnectionUiState();
  private connUiTimer: number = 0;
  private connUiKey: string = '';
  @State suppressReconnectUi: boolean = false;
  @State showDelayedConnError: boolean = false;
  @State clientOffline: boolean = false;
  @State settingsWriteAllowed: boolean | undefined = undefined;
  @State scheduledConnectionKey: string = '';
  @State busy: boolean = false;
  @State messages: ChatMessage[] = [];
  @State projects: ProjectView[] = [];
  @State threads: ThreadView[] = [];
  @State models: ModelChoice[] = [];
  @State actions: ActionCard[] = [];
  @State tools: string[] = [];
  private picker: AttachmentPicker = new AttachmentPicker();
  @State attachmentName: string = '';
  @State uploadingAttachment: boolean = false;
  @State canRetryAttachment: boolean = false;
  private attachmentUploadCancelled: boolean = false;
  private source: MessageSource = new MessageSource();
  private scroller: Scroller = new Scroller();
  @State unknown: boolean = false;
  @State cloudConfigured: boolean = false;
  @State cloudSignInReady: boolean = false;
  @State cloudSignedIn: boolean = false;
  @State cloudAccountId: string = '';
  @State cloudStatus: string = '';
  @State cloudError: string = '';
  @State cloudBusy: boolean = false;
  @State cloudRefreshing: boolean = false;
  @State cloudEnvironments: CloudEnvironmentView[] = [];
  @State pendingDevices: CloudPairingLink[] = [];
  @State approvedDevices: CloudDevice[] = [];
  @State deviceEnvironmentLabel: string = '';
  private deviceWatchKey: string = '';
  private deviceWatchGeneration: number = 0;
  private shownApprovalIds: string[] = [];
  private approvalShowing: boolean = false;
  private cloudReturnPanel: string = 'server';
  private textDrafts: Map<string, string> = new Map();
  private settingsDrafts: Map<string, TaskSettings> = new Map();
  private contextDrafts: Map<string, ComposerContextRecord[]> = new Map();

  aboutToAppear(): void {
    this.alive = true;
    this.shareChanged();
    configureNotificationTargets((target: NotificationTarget): boolean => this.notificationValid(target));
    if (draftStore) void draftStore.load().then((rows: ComposerDraft[]) => {
      if (this.alive) { this.draftRecords = rows; this.shortcutDraftsLoaded = true; }
    }).catch(() => { this.status = '草稿记录不可读；新建草稿仍会尝试保存'; }).finally(() => {
      void this.openShortcut();
    });
    else this.shortcutDraftsLoaded = false;
    this.workspaceActions = new WorkspaceActions(this.registry());
    this.environmentFilter = workspacePrefs.environmentFilter;
    this.threadSortOrder = workspacePrefs.threadSortOrder;
    this.projectFilterKey = workspacePrefs.projectFilterKey;
    this.workingExpanded = workspacePrefs.workingShelfExpanded;
    this.snoozedExpanded = workspacePrefs.snoozedShelfExpanded;
    this.settledExpanded = workspacePrefs.settledShelfExpanded;
    const update = (): void => {
      if (!this.alive) return;
      this.bindEnvironment();
      this.status = client.status;
      this.server = client.server;
      this.ready = client.ready;
      this.threadTerminalEnabled = client.ready && !this.draftMode && !!client.threadCwd() && client.canScope('terminal:read') !== false;
      this.settingsWriteAllowed = client.ready ? client.canScope('settings:write') : false;
      this.scheduledConnectionKey = this.selectedLocalId + ':' + client.generationValue() + ':' +
        String(client.ready) + ':' + String(client.canScope('orchestration:operate') !== false);
      const currentThreadKey = this.selectedLocalId + ':' + this.threadId;
      const keepRenderedOnSync = !this.draftMode && this.renderedThreadKey === currentThreadKey &&
        (!client.thread || (client.thread.threadId === this.threadId && client.thread.cursor < 0));
      if (this.draftMode) {
        this.messages = [];
        this.renderedThreadKey = '';
        this.hasMoreHistory = false;
      } else if (client.thread && client.thread.threadId === this.threadId) {
        if (client.thread.cursor >= 0 || (client.thread.resumeCursor >= 0 && client.thread.messages.length > 0)) {
          this.messages = client.thread.messages.slice();
          this.renderedThreadKey = currentThreadKey;
          this.hasMoreHistory = client.thread.hasMoreHistory;
        } else if (!keepRenderedOnSync) {
          this.messages = [];
          this.hasMoreHistory = false;
        }
      } else if (!client.thread && !keepRenderedOnSync) {
        this.messages = [];
        this.hasMoreHistory = false;
      }
      this.queued = !this.draftMode && client.thread ? queuedRuns(client.thread.runs, client.thread.messageRecords) : [];
      this.threadRunning = !this.draftMode && !!client.thread?.runs.some((run: Record<string, Object>) =>
        ['preparing', 'starting', 'running', 'waiting'].includes(String(run.status)));
      if (client.recoveredMessageId && this.messages.some((m: ChatMessage) =>
        m.id === client.recoveredMessageId && m.text === this.prompt)) {
        this.prompt = '';
        this.textDrafts.delete(this.draftKey());
      }
      this.source.update(this.messages);
      this.attachmentName = client.attachment?.name || '';
      this.unknown = !!client.recovery?.pendingId;
      this.canOperateChat = !this.draftMode && client.ready && !this.unknown && client.canScope('orchestration:operate') !== false;
      this.canResumeLatestRun = !this.draftMode && !!client.thread && client.resumableRunId().length > 0;
      this.projects = client.shell.projects.slice();
      this.threads = client.shell.threads.slice();
      this.models = client.models.slice();
      this.actions = !this.draftMode && client.thread ? cards(client.thread.requests, client.thread.items) : [];
      this.refreshExtras();
      this.worktreeSetup = client.worktreeSetup;
      if (!this.busy) this.refreshAttachments();
      try { this.linkItems = !this.draftMode && client.thread ? linkRequests(client.thread.items, client.thread.threadId) : []; }
      catch (_) { this.linkItems = []; this.status = '环境链接请求格式无效'; }
      const permissionKey = this.selectedLocalId + ':' + String(client.ready) + ':' + this.linkItems.filter((item: LinkRequestView) => item.status === 'pending' && item.visibility === 'local').map((item: LinkRequestView) => item.id).join(',');
      if (permissionKey !== this.linkPermissionKey) { this.linkPermissionKey = permissionKey; void this.refreshPeerPermission(); }
      if (this.activeLink && this.linkOwner === client && !this.busy && this.panel === 'peer-link') {
        const current = this.linkItems.find((item: LinkRequestView) => item.id === this.activeLink?.id);
        if (current && current.status !== 'pending') this.panelOpen = false;
      }
      const workKey = this.selectedLocalId + ':' + (client.thread ? client.thread.threadId : '');
      if (workKey !== this.lastWorkThreadKey) {
        this.lastWorkThreadKey = workKey;
        this.expandedWorkGroups = {};
        this.expandedUserMessages = {};
      }
      if (!keepRenderedOnSync) {
        this.workMap = !this.draftMode && client.thread
          ? groupWorkByMessage(client.thread.items, client.thread.runs, client.thread.checkpoints, this.messages)
          : emptyWorkMap();
        this.messageFooterMap = !this.draftMode && client.thread
          ? buildMessageFooterMap(
              client.thread.threadId,
              this.messages,
              client.thread.items,
              client.thread.runs,
              client.thread.providerThreads,
              client.thread.providerSessions
            )
          : {};
      }
      this.tools = !this.draftMode && client.thread && this.workMap.hasVisible
        ? visibleWorkItems(client.thread.items).map((row: Record<string, Object>) => String(row.type) + ' · ' + String(row.status))
        : [];
      this.canOpenDiff = !this.draftMode && !!this.currentWorkspace();
      if (client.thread && !this.draftMode) {
        this.threadId = client.thread.threadId;
        if (this.page === 'chat') {
          this.projectId = this.threads.find((t: Choice) => t.id === this.threadId)?.projectId || this.projectId;
        }
      }
      if (this.page === 'chat' && !this.draftMode && this.threadId) {
        const matchedThread = this.threads.find((t: ThreadView) => t.id === this.threadId);
        const matchedScopedThread = this.scopedThreads.find((t: ScopedThread) =>
          t.localId === this.selectedLocalId && t.id === this.threadId);
        const resolvedTitle = matchedThread?.label || matchedScopedThread?.label || '';
        if (resolvedTitle) this.cachedChatTitle = resolvedTitle;
        const resolvedProjId = matchedThread?.projectId || matchedScopedThread?.projectId || this.projectId;
        if (resolvedProjId) this.projectId = resolvedProjId;
        const resolvedProject = this.projects.find((p: ProjectView) => p.id === this.projectId)?.label ||
          this.scopedProjects.find((p: ScopedProject) => p.localId === this.selectedLocalId && p.id === this.projectId)?.label || '';
        if (resolvedProject) this.cachedChatProject = resolvedProject;
      }
      this.resolveActiveModel(client);
      if (this.page === 'chat' && !this.draftMode && this.threadId && client.ready && !client.submitting && !this.busy &&
        client.pendingWatchThreadId !== this.threadId) {
        const watchKey = this.selectedLocalId + ':' + client.generationValue() + ':' + this.threadId;
        if (watchKey !== this.lastAutoWatchKey) {
          this.lastAutoWatchKey = watchKey;
          void client.watch(this.threadId).catch((error: Error) => { if (this.alive) this.status = error.message; });
        }
      }
      if (this.page === 'chat' && !this.draftMode && this.pendingScrollBottomKey === currentThreadKey &&
        client.thread && client.thread.threadId === this.threadId && client.thread.cursor >= 0 && this.messages.length > 0) {
        const scrolledThreadId = this.threadId;
        this.pendingScrollBottomKey = '';
        setTimeout(() => {
          if (this.alive && this.page === 'chat' && !this.draftMode && this.threadId === scrolledThreadId) {
            this.scroller.scrollEdge(Edge.Bottom);
            this.chatAwayFromBottom = false;
          }
        }, 80);
        setTimeout(() => {
          if (this.alive && this.page === 'chat' && !this.draftMode && this.threadId === scrolledThreadId) {
            this.scroller.scrollEdge(Edge.Bottom);
            this.chatAwayFromBottom = false;
          }
        }, 240);
      }
      this.ensureDeviceWatch();
      this.refreshLinkedWhenChanged();
      this.rebuildWorkspace();
      this.syncDelayedConnectionUi();
      this.refreshFloatingCapsule();
      this.updateTaskNotifications();
      void this.openNotificationTarget();
      void this.openShortcut();
      if (this.page === 'voice' && this.voiceTarget !== this.draftKey()) this.page = 'chat';
    };
    this.registry().onUpdate = update;
    update();
    this.syncCloudState();
    void this.restoreAddress();
    this.incomingPairing();
    this.incomingCloudCallback();
    this.clockTimer = setInterval(() => {
      if (!this.alive) return;
      this.nowMs = Date.now();
      this.rebuildWorkspace();
      this.refreshFloatingCapsule();
    }, 30000) as number;
  }

  private incomingPairing(): void {
    if (!this.alive || this.busy) return;
    const target = takePairingLink();
    if (target) {
      this.address = target.base; this.credential = target.code;
      this.pairingError = false;
      this.pairingStatus = '请确认目标后添加环境'; this.openPanel('connection-new');
    } else {
      const error = AppStorage.get<string>('t3PairingError');
      if (error) { this.credential = ''; this.pairingError = true; this.pairingStatus = error; this.status = error; AppStorage.setOrCreate('t3PairingError', ''); }
    }
  }

  private cloudManager(): CloudManager {
    const manager = cloud;
    if (!manager) throw new Error('T3 Connect 尚未初始化');
    return manager;
  }
  private cloudChanged(): void {
    if (!this.alive) return;
    this.syncCloudState();
    this.bindEnvironment();
    this.incomingCloudCallback();
  }
  private syncCloudState(): void {
    const manager = cloud;
    if (!manager) return;
    this.cloudConfigured = manager.configured;
    this.cloudSignInReady = manager.signInReady;
    this.cloudSignedIn = manager.signedIn;
    this.cloudAccountId = manager.session?.accountId || '';
    this.cloudStatus = manager.status;
    const storedError = AppStorage.get<string>('t3CloudError') || '';
    this.cloudError = manager.error || storedError;
    if (storedError) AppStorage.setOrCreate('t3CloudError', '');
    this.cloudBusy = manager.busy;
    this.cloudRefreshing = manager.refreshing;
    this.cloudEnvironments = manager.environments.slice();
  }
  private incomingCloudCallback(): void {
    if (!this.alive || this.busy || !cloud) return;
    const uri = takeCloudCallback();
    if (!uri) return;
    this.busy = true; this.cloudBusy = true;
    void this.cloudManager().completeCallback(uri).catch((error: Error) => {
      this.cloudError = error.message;
    }).finally(() => {
      this.busy = false; this.cloudBusy = cloud?.busy || false;
      this.syncCloudState();
    });
  }
  private async cloudSignIn(): Promise<void> {
    if (this.cloudBusy) return;
    this.cloudBusy = true;
    try {
      await this.cloudManager().beginSignIn(this.getUIContext().getHostContext() as common.UIAbilityContext);
    } catch (error) { this.cloudError = (error as Error).message; }
    finally { this.cloudBusy = false; this.syncCloudState(); }
  }
  private async cloudSignOut(): Promise<void> {
    if (this.cloudBusy) return;
    this.cloudBusy = true;
    try { await this.cloudManager().signOut(); this.bindEnvironment(); }
    catch (error) { this.cloudError = (error as Error).message; }
    finally { this.cloudBusy = false; this.syncCloudState(); }
  }
  private async cloudRefresh(): Promise<void> {
    if (this.cloudBusy || this.cloudRefreshing) return;
    this.cloudBusy = true;
    try { await this.cloudManager().refresh(); }
    catch (error) { this.cloudError = (error as Error).message; }
    finally { this.cloudBusy = false; this.syncCloudState(); }
  }
  private async cloudConnect(environmentId: string): Promise<void> {
    if (this.cloudBusy) return;
    this.cloudBusy = true;
    try { await this.cloudManager().connectEnvironment(environmentId); this.bindEnvironment(); }
    catch (error) { this.cloudError = (error as Error).message; }
    finally { this.cloudBusy = false; this.syncCloudState(); }
  }
  private async cloudLink(localId: string): Promise<void> {
    if (this.cloudBusy) return;
    this.cloudBusy = true;
    try { await this.cloudManager().linkLocalEnvironment(localId); await this.cloudManager().refresh(); }
    catch (error) { this.cloudError = (error as Error).message; }
    finally { this.cloudBusy = false; this.syncCloudState(); }
  }
  private async cloudUnlink(environmentId: string): Promise<void> {
    if (this.cloudBusy) return;
    this.cloudBusy = true;
    try { await this.cloudManager().unlinkEnvironment(environmentId); this.bindEnvironment(); }
    catch (error) { this.cloudError = (error as Error).message; }
    finally { this.cloudBusy = false; this.syncCloudState(); }
  }
  private openCloudPanel(returnTo: string): void {
    this.cloudReturnPanel = returnTo;
    this.syncCloudState();
    this.panel = 'cloud'; this.panelOpen = true;
  }
  private async approveDevice(id: string): Promise<void> {
    this.busy = true;
    try { await client.approveDevice(id); }
    catch (error) { this.status = (error as Error).message; }
    finally { this.busy = false; this.updateDevices(); }
  }
  private async denyDevice(id: string): Promise<void> {
    this.busy = true;
    try { await client.denyDevice(id); }
    catch (error) { this.status = (error as Error).message; }
    finally { this.busy = false; this.updateDevices(); }
  }
  private async revokeDevice(thumbprint: string): Promise<void> {
    this.busy = true;
    try { await client.revokeDevice(thumbprint); }
    catch (error) { this.status = (error as Error).message; }
    finally { this.busy = false; this.updateDevices(); }
  }
  private updateDevices(): void {
    const source = client;
    this.pendingDevices = source.authAccess.pairingLinks.slice();
    this.approvedDevices = source.authAccess.devices.slice();
    this.deviceEnvironmentLabel = source.environmentLabel || this.environmentEntries.find((entry: EnvironmentEntry) =>
      entry.localId === this.selectedLocalId)?.label || '';
    this.offerDeviceApprovals();
  }
  private offerDeviceApprovals(): void {
    if (this.approvalShowing || !this.alive) return;
    const prompts = deviceApprovalPrompts(this.deviceEnvironmentLabel, this.pendingDevices,
      this.shownApprovalIds, Date.now());
    const prompt = prompts[0];
    if (!prompt) return;
    this.shownApprovalIds.push(prompt.pairingLinkId);
    this.approvalShowing = true;
    AlertDialog.show({
      title: prompt.title,
      message: prompt.message,
      primaryButton: { value: '拒绝', action: () => {
        void this.denyDevice(prompt.pairingLinkId).finally(() => { this.approvalShowing = false; setTimeout(() => this.offerDeviceApprovals(), 100); });
      } },
      secondaryButton: { value: '批准', action: () => {
        void this.approveDevice(prompt.pairingLinkId).finally(() => { this.approvalShowing = false; setTimeout(() => this.offerDeviceApprovals(), 100); });
      } }
    });
  }
  private ensureDeviceWatch(): void {
    const source = client;
    const key = this.selectedLocalId + ':' + String(source.ready) + ':' + String(source.requireDeviceApproval);
    if (!source.ready || !source.requireDeviceApproval) {
      if (this.deviceWatchKey) { this.deviceWatchGeneration++; this.deviceWatchKey = ''; source.stopAuthAccess(); }
      this.pendingDevices = []; this.approvedDevices = []; this.deviceEnvironmentLabel = '';
      return;
    }
    if (key === this.deviceWatchKey) { this.updateDevices(); return; }
    source.stopAuthAccess();
    this.pendingDevices = []; this.approvedDevices = []; this.deviceEnvironmentLabel = '';
    this.deviceWatchKey = key;
    const generation = ++this.deviceWatchGeneration;
    void source.refreshPeerAccess().then(() => {
      if (generation !== this.deviceWatchGeneration || source !== client || !source.canManagePeerAccess()) return;
      source.watchAuthAccess(() => { if (generation === this.deviceWatchGeneration) this.updateDevices(); });
      this.updateDevices();
    }).catch(() => {});
  }

  private registry(): EnvironmentRegistry {
    if (!environments) throw new Error('环境目录尚未准备');
    return environments;
  }
  private bindEnvironment(): void {
    const registry = this.registry();
    this.environmentEntries = registry.directory.entries.filter((entry: EnvironmentEntry) => registry.entryVisible(entry));
    const statuses: Record<string, string> = {};
    const readyMap: Record<string, boolean> = {};
    registry.clients.forEach((value: T3Client, id: string) => {
      statuses[id] = value.status;
      readyMap[id] = Boolean(value.ready);
    });
    this.environmentStatuses = statuses;
    this.environmentReady = readyMap;
    const threads: ScopedThread[] = [];
    const projects: ScopedProject[] = [];
    const capabilities: Record<string, ThreadCapabilities> = {};
    let anyReady = false;
    let anyHasShell = false;
    let anyLiveSynced = false;
    let reconnecting = 0;
    let offline = 0;
    registry.clients.forEach((value: T3Client, id: string) => {
      const entry = registry.directory.entries.find((e: EnvironmentEntry) => e.localId === id);
      if (!entry || entry.deleting || entry.enabled === false || !registry.entryVisible(entry)) return;
      const isReady = Boolean(value.ready);
      const liveSynced = value.shell.liveSynced === true;
      const hasShell = value.shell.hasSnapshot === true || value.shell.threads.length > 0 || value.shell.projects.length > 0;
      const isPending = Boolean(value.connectionPending) || Boolean(value.reconnectPending) ||
        (isReady && value.shell.liveSynced === false);
      if (isReady) anyReady = true;
      if (hasShell) anyHasShell = true;
      if (isReady && liveSynced) anyLiveSynced = true;
      if (isPending) reconnecting++;
      else if (!isReady) offline++;
      const caps: ThreadCapabilities = {
        settlement: value.supports('threadSettlement'), snooze: value.supports('threadSnooze'),
        pinning: value.supports('threadPinning'), pinReorder: value.supports('threadPinReorder'),
        activeReorder: value.supports('threadActiveReorder'),
        autoSettleOptOut: value.supports('threadAutoSettleOptOut'),
        titleRegeneration: value.supports('threadTitleRegeneration')
      };
      capabilities[id] = caps;
      value.shell.projects.forEach((project: ProjectView) => {
        projects.push(scopedProjectView(project, id, entry.environmentId, entry.label,
          !!value.scratchWorkspaceRoot && samePath(project.workspaceRoot, value.scratchWorkspaceRoot)));
      });
      value.shell.threads.forEach((thread: ThreadView) => {
        const project = value.shell.projects.find((p: ProjectView) => p.id === thread.projectId);
        threads.push(scopedThreadView(thread, id, entry.environmentId, entry.label,
          project?.label || '项目', project?.projectIcon));
      });
    });
    this.anyEnvironmentReady = anyReady;
    this.anyEnvironmentHasShell = anyHasShell;
    this.anyEnvironmentLiveSynced = anyLiveSynced;
    this.reconnectingCount = reconnecting;
    this.offlineCount = offline;
    this.scopedThreads = attachPendingSubagentRequests(threads); this.scopedProjects = projects;
    this.threadCapabilities = capabilities;
    this.projectGroups = buildProjectGroups(projects, workspacePrefs.projectGroupingMode);
    this.syncProjectFilter();
    const localId = registry.directory.selectedLocalId;
    const next = registry.clients.get(localId);
    if (localId !== this.selectedLocalId) {
      const previousKey = this.draftKey();
      if (this.draftMode) void this.persistDraft().catch(() => {});
      else if (this.threadId) {
        this.textDrafts.set(previousKey, this.prompt);
        this.contextDrafts.set(previousKey, this.draftContext.slice());
      }
      this.selectedLocalId = localId;
      this.draftMode = false;
      this.draftModelCustomized = false;
      if (next) next.draftScope = '';
      this.messages = []; this.source.update([]); this.actions = []; this.tools = [];
      this.workMap = emptyWorkMap();
      this.liveThinking = { visible: false, kind: 'thinking', label: '', runId: '' };
      this.messageFooterMap = {};
      this.forkingMessageId = '';
      this.canOperateChat = false;
      this.renderedThreadKey = '';
      this.hasMoreHistory = false;
      this.chatAwayFromBottom = false;
      this.threadRunning = false;
      this.activeModelInstanceId = '';
      this.activeModelDriver = '';
      this.activeModelSlug = '';
      this.activeModelLabel = '';
      this.activeModelSummary = '';
      this.pendingScrollBottomKey = '';
      this.lastAutoWatchKey = '';
      this.cachedChatTitle = '';
      this.cachedChatProject = '';
      this.expandedWorkGroups = {};
      this.expandedUserMessages = {};
      this.canOpenDiff = false;
      this.projectId = ''; this.modelIndex = 0;
      if (!this.savingShare || this.page !== 'share') this.page = 'sessions';
      this.threadId = next?.thread?.threadId || next?.recovery?.threadId || '';
      this.prompt = this.draftMode ? '' : this.textDrafts.get(this.draftKey()) || '';
      this.draftContext = (this.contextDrafts.get(this.draftKey()) || []).slice();
      if (this.panel !== 'connection-new') this.address = registry.directory.entries.find((e: EnvironmentEntry) => e.localId === localId)?.base || '';
    }
    bindClient(next);
    let picker = this.pickers.get(localId);
    if (!picker || !picker.belongsTo(client)) { picker = new AttachmentPicker(client); this.pickers.set(localId, picker); }
    this.picker = picker;
    this.canRetryAttachment = this.picker.canRetry();
  }
  private workspace(): WorkspaceActions {
    if (!this.workspaceActions) this.workspaceActions = new WorkspaceActions(this.registry());
    return this.workspaceActions;
  }
  private setThreadSortOrder(order: string): void {
    this.threadSortOrder = order;
    workspacePrefs.threadSortOrder = order;
    saveWorkspacePreferences();
    this.rebuildWorkspace();
  }

  private rebuildWorkspace(): void {
    this.nowMs = Date.now();
    const turnable: Record<string, boolean> = {};
    this.scopedThreads.forEach((thread: ScopedThread) => {
      const project = this.scopedProjects.find((candidate: ScopedProject) =>
        candidate.localId === thread.localId && candidate.id === thread.projectId);
      const connection = this.registry().clients.get(thread.localId);
      if (project?.isScratch && !!thread.worktreePath && connection?.supports('threadProjectFromScratch')) {
        turnable[thread.localId + ':' + thread.id] = true;
      }
    });
    this.turnableThreads = turnable;
    this.shelves = buildThreadShelves({
      threads: this.projectFilterKey && !this.projectFilterRefs.length ? [] : this.scopedThreads, environmentId: this.environmentFilter,
      projectRefs: this.projectFilterRefs, query: this.threadQuery, searchHits: this.threadSearchHits,
      nowMs: this.nowMs, capabilities: this.threadCapabilities, sortOrder: this.threadSortOrder,
      selectedKey: this.selectedLocalId + ':' + this.threadId, workingShelfEnabled: workspacePrefs.workingShelfEnabled
    });
    if (this.snoozeTimer) { clearTimeout(this.snoozeTimer); this.snoozeTimer = 0; }
    let next = 0;
    for (const thread of this.scopedThreads) {
      const wake = Date.parse(thread.snoozedUntil);
      if (Number.isFinite(wake) && wake > this.nowMs && (!next || wake < next)) next = wake;
    }
    if (next) {
      this.snoozeTimer = setTimeout(() => {
        this.snoozeTimer = 0;
        if (!this.alive) return;
        this.nowMs = Date.now(); this.rebuildWorkspace();
      }, Math.max(500, Math.min(next - this.nowMs + 100, 60000))) as number;
    }
  }
  private keyboardEvent(event: KeyEvent, beforeIme: boolean): boolean {
    if (!beforeIme && this.composerFocused) return false;
    if (!event.getModifierKeyState) { this.keyboard.reset(); return false; }
    const input: KeyboardInput = { keyCode: event.keyCode, down: event.type === KeyType.Down,
      keyboard: event.keySource === KeySource.Keyboard, deviceId: event.deviceId,
      ctrl: event.getModifierKeyState(['ctrl']), alt: event.getModifierKeyState(['alt']), shift: event.getModifierKeyState(['shift']) };
    const context: KeyboardContext = { foreground: this.appForeground, composing: this.composingText,
      textFocused: this.composerFocused || this.searchFocused, composerFocused: this.composerFocused && this.page === 'chat',
      blocked: this.panelOpen || !['sessions', 'chat'].includes(this.page) || this.actions.length > 0,
      busy: this.busy, unknownSubmission: this.unknown,
      canSend: this.ready && (this.prompt.trim().length > 0 || this.attachments.length > 0),
      canSearch: this.loaded && (this.ready || this.scopedThreads.length > 0), canNewTask: this.ready, canBack: this.page === 'chat' };
    const action = this.keyboard.handle(input, context);
    if (!action) return false;
    event.stopPropagation();
    if (action === 'send') { void this.send(); }
    else if (action === 'new-task') { void this.startNewTask(); }
    else if (action === 'back') this.onBackPress();
    else if (action === 'search') {
      this.page = 'sessions';
      this.searchOpen = true;
      setTimeout(() => { if (this.alive && this.page === 'sessions') this.getUIContext().getFocusController().requestFocus('thread-search'); }, 0);
    }
    return true;
  }
  private notificationValid(target: NotificationTarget): boolean {
    const registry = this.registry();
    const entry = registry.directory.entries.find((item: EnvironmentEntry) => item.localId === target.localId);
    return !!entry && !entry.deleting && entry.enabled && entry.environmentId === target.environmentId &&
      registry.entryVisible(entry) && !!registry.clients.get(target.localId)?.shell.threads.some((thread) => thread.id === target.threadId);
  }
  private updateTaskNotifications(): void {
    const visible: NotificationTarget | undefined = this.page === 'chat' && !this.draftMode && this.threadId ?
      { localId: this.selectedLocalId, environmentId: this.draftEnvironment(), threadId: this.threadId } : undefined;
    setVisibleNotificationThread(visible);
    for (const entry of this.registry().directory.entries) {
      const owner = this.registry().clients.get(entry.localId);
      const thread = owner?.thread;
      if (!owner || !owner.ready || !thread || thread.cursor < 0 || !this.registry().entryVisible(entry)) continue;
      const target: NotificationTarget = { localId: entry.localId, environmentId: entry.environmentId, threadId: thread.threadId };
      const runs: NotificationRun[] = thread.runs.filter((run: Record<string, Object>) =>
        typeof run.id === 'string' && typeof run.status === 'string').map((run: Record<string, Object>): NotificationRun =>
        ({ id: run.id as string, status: run.status as string }));
      void observeThreadNotifications(target, owner.generationValue(), thread, runs).catch(() => {});
    }
  }
  private async openShortcut(): Promise<void> {
    const request = peekShortcut();
    if (!request || !this.alive || !this.loaded || !this.appForeground || !this.shortcutDraftsLoaded ||
      this.shortcutOpening || this.busy || this.unknown || this.savingShare || this.shareId || this.startingNewTask ||
      this.openingNotification || peekNotificationTarget()) return;
    if (request.action === 'new-task' && !this.ready && this.environmentEntries.some((entry: EnvironmentEntry) =>
      entry.enabled && !entry.deleting)) return;
    if (this.page !== 'chat' && this.page !== 'sessions') {
      consumeShortcut(request.id); this.status = '请先返回会话，再使用快捷入口'; return;
    }
    this.shortcutOpening = true;
    const page = this.page; const localId = this.selectedLocalId;
    try {
      if (this.draftMode) await this.persistDraft();
      if (!this.alive || !this.appForeground || this.page !== page || this.selectedLocalId !== localId ||
        this.busy || this.unknown || this.shareId || !consumeShortcut(request.id)) return;
      this.panelOpen = false;
      if (request.action === 'sessions') this.page = 'sessions';
      else await this.startNewTask();
    } catch (_) {
      consumeShortcut(request.id); this.status = '快捷入口未完成，原输入已保留，请重试';
    } finally { this.shortcutOpening = false; }
  }

  private async openNotificationTarget(): Promise<void> {
    const target = peekNotificationTarget();
    if (!target || !this.alive || !this.loaded || this.openingNotification || this.busy || this.unknown || this.savingShare) return;
    const entry = this.registry().directory.entries.find((item: EnvironmentEntry) => item.localId === target.localId);
    if (!entry || entry.environmentId !== target.environmentId || entry.deleting || !this.registry().entryVisible(entry)) {
      clearNotificationTarget(); this.status = '通知所属环境已移除或账号已变化'; return;
    }
    if (!this.registry().clients.get(target.localId)?.ready) return;
    const thread = this.scopedThreads.find((item: ScopedThread) => item.localId === target.localId && item.id === target.threadId);
    if (!thread) { clearNotificationTarget(); this.status = '通知会话不可用，请在项目中查找'; return; }
    this.openingNotification = true;
    try {
      if (this.draftMode) await this.persistDraft();
      clearNotificationTarget(); this.panelOpen = false;
      await this.openScopedThread(thread);
    } catch (_) { this.status = '无法打开通知会话，请重试'; }
    finally { this.openingNotification = false; }
  }
  private insertVoice(value: string): void {
    if (this.voiceTarget !== this.draftKey() || this.busy || this.unknown) { this.status = '语音目标已变化，请重新打开'; return; }
    const next = this.prompt + (this.prompt && value ? '\n' : '') + value;
    if (next.length > MAX_SHARED_TEXT_CHARS) { this.status = '文字超过输入上限，请缩短后再加入'; return; }
    this.prompt = next; this.scheduleDraftSave(); this.page = 'chat';
  }
  private async previewShareAttachment(shareId: number, attachmentId: string, stillSelected: () => boolean): Promise<image.PixelMap> {
    const current = (): boolean => stillSelected() && this.alive && this.appForeground && !this.savingShare &&
      this.page === 'share' && this.shareId === shareId &&
      this.shareAttachments.some((item: IncomingShareAttachment) => item.id === attachmentId && item.type === 'image');
    if (!current()) throw new Error('分享图片已失效');
    const thumbnail = await loadStagedShareThumbnail(shareId, attachmentId, current);
    if (!current()) { void thumbnail.release().catch(() => {}); throw new Error('分享图片已失效'); }
    return thumbnail;
  }
  private shareChanged(): void {
    const incoming = peekIncomingShare();
    if (incoming && incoming.id !== this.shareId) {
      this.shareId = incoming.id; this.shareParts = incoming.parts;
      this.shareAttachments = incoming.attachments || [];
      this.resetShareUploads();
      this.shareDestination = ''; this.shareLocalId = ''; this.shareProjectId = ''; this.shareError = '';
    } else if (!incoming) {
      this.shareId = 0; this.shareParts = []; this.choosingShare = false;
      this.shareAttachments = []; this.resetShareUploads();
    }
    const error = AppStorage.get<string>('t3IncomingShareError');
    if (error) this.status = error;
  }
  private editSharePart(id: number, value: string): void {
    const part = this.shareParts.find((item: SharePart) => item.id === id);
    if (this.savingShare || !part || part.text === value) return;
    this.resetShareUploads();
    this.shareParts = this.shareParts.map((part: SharePart): SharePart =>
      part.id === id ? { id: part.id, kind: part.kind, text: value } : part);
  }
  private removeSharePart(id: number): void {
    if (this.savingShare || !this.shareParts.some((part: SharePart) => part.id === id)) return;
    this.resetShareUploads();
    this.shareParts = this.shareParts.filter((part: SharePart) => part.id !== id);
  }
  private removeShareAttachment(id: string): void {
    if (this.savingShare || !this.shareAttachments.some((item: IncomingShareAttachment) => item.id === id)) return;
    this.resetShareUploads();
    if (removeIncomingShareAttachment(this.shareId, id)) {
      this.shareAttachments = this.shareAttachments.filter((item: IncomingShareAttachment) => item.id !== id);
    }
  }
  private resetShareUploads(): void {
    this.shareUploadPlan = undefined;
    this.shareUploadedCount = 0;
  }
  private cancelShareUpload(): void {
    if (!this.uploadingShare) return;
    this.shareUploadCancelled = true;
    this.shareUploadOwner?.cancelUpload();
  }
  private async collectShareAttachments(plan: ShareUploadPlan, files: IncomingShareAttachment[], owner: T3Client,
    current: () => boolean): Promise<DraftAttachment[]> {
    const uploaded: DraftAttachment[] = [];
    for (const file of files) {
      if (!current()) throw new Error('分享或目标连接已变化，请重试');
      if (!plan.uploaded.has(file.id)) {
        await withStagedShareAttachment(plan.shareId, file.id, async (bytes: ArrayBuffer): Promise<void> => {
          if (!current()) throw new Error('分享或目标连接已变化，请重试');
          const item = await owner.uploadOne(file.name, bytes, file.mimeType, file.type, current);
          if (!current()) throw new Error('分享或目标连接已变化，请重试');
          plan.uploaded.set(file.id, item);
          this.shareUploadedCount = plan.uploaded.size;
        });
      }
      const item = plan.uploaded.get(file.id);
      if (!item) throw new Error('附件上传结果未确认，请手动重试');
      uploaded.push(item);
    }
    return uploaded;
  }
  private async confirmShare(): Promise<void> {
    if (this.savingShare || this.busy || this.unknown) return;
    const id = this.shareId;
    const pending = peekIncomingShare();
    if (!pending || pending.id !== id || !this.shareDestination) return;
    const value = shareDraftText(this.shareParts);
    const files = this.shareAttachments.slice();
    if ((!value.trim() && !files.length) || value.length > MAX_SHARED_TEXT_CHARS || value.includes('\u0000')) return;
    const limit = attachmentLimitError(files);
    if (limit) { this.shareError = limit; return; }
    this.savingShare = true; this.shareError = '';
    this.shareUploadCancelled = false;
    try {
      if (!draftStore) throw new Error('草稿存储尚未就绪');
      const project = this.scopedProjects.find((item: ScopedProject) => item.localId === this.shareLocalId && item.id === this.shareProjectId);
      if (!project || project.archivedAt) throw new Error('目标项目已变化，请重新选择');
      await this.persistDraft();
      await this.registry().select(project.localId);
      if (this.selectedLocalId !== project.localId || this.shareId !== id) throw new Error('分享或目标环境已变化，请重新选择');
      const owner = client;
      const generation = owner.generationValue();
      let plan = this.shareUploadPlan;
      if (!plan || plan.shareId !== id || plan.localId !== project.localId || plan.environmentId !== project.environmentId ||
        plan.projectId !== project.id) {
        plan = { shareId: id, draftId: util.generateRandomUUID(), localId: project.localId, environmentId: project.environmentId,
          projectId: project.id, uploaded: new Map<string, DraftAttachment>() };
        this.shareUploadPlan = plan;
        this.shareUploadedCount = 0;
      }
      const current = (): boolean => this.savingShare && !this.shareUploadCancelled && this.appForeground && this.page === 'share' &&
        this.shareId === id && this.shareUploadPlan === plan && this.shareLocalId === project.localId && this.shareProjectId === project.id &&
        this.selectedLocalId === project.localId && client === owner && owner.ready && owner.generationValue() === generation;
      const defaults = await this.newDraftDefaults(project.id);
      if (!current()) throw new Error('分享或目标连接已变化，请重试');
      this.shareUploadOwner = owner;
      this.uploadingShare = files.length > 0;
      const attachments = await this.collectShareAttachments(plan, files, owner, current);
      if (!current()) throw new Error('分享或目标连接已变化，请重试');
      this.uploadingShare = false;
      const model = owner.models[0];
      const preferredModel = defaults.modelSelection;
      const modelSelection: ModelSelection = preferredModel && preferredModel.instanceId && preferredModel.model
        ? (preferredModel.options && preferredModel.options.length > 0
          ? { instanceId: preferredModel.instanceId, model: preferredModel.model, options: preferredModel.options.slice() }
          : { instanceId: preferredModel.instanceId, model: preferredModel.model })
        : { instanceId: model?.instanceId || '', model: model?.model || '' };
      const draft: ComposerDraft = { version: 1, draftId: plan.draftId, localId: project.localId,
        environmentId: project.environmentId, projectId: project.id, text: value,
        modelSelection,
        runtimeMode: defaults.runtimeMode, interactionMode: 'default', workspace: defaults.workspace,
        attachments, context: [], updatedAt: Date.now() };
      const next = [draft].concat(this.draftRecords.filter((item: ComposerDraft) => item.draftId !== draft.draftId));
      await draftStore.save(next);
      this.draftRecords = next;
      removeIncomingShare(id);
      await this.beginDraft(project.id, draft.draftId);
      this.status = '分享已保存为新草稿，尚未发送';
    } catch (error) { this.shareError = this.shareUploadCancelled ? '已取消上传，可按当前目标手动重试。' : (error as Error).message; }
    finally { this.uploadingShare = false; this.shareUploadOwner = undefined; this.savingShare = false; }
  }
  private async startNewTask(): Promise<void> {
    if (this.startingNewTask || this.shareId || this.choosingShare) return;
    if (this.busy || this.unknown) { this.openProjectPicker(); return; }
    const registry = this.registry();
    const sourcePage = this.page;
    const sourceLocalId = this.selectedLocalId;
    const current: ThreadProjectRef | undefined = sourcePage === 'chat' && this.projectId
      ? { environmentId: this.draftEnvironment(), projectId: this.projectId } : undefined;
    const ready = this.environmentEntries.filter((entry: EnvironmentEntry) =>
      entry.enabled && !entry.deleting && !!registry.clients.get(entry.localId)?.ready &&
      (!this.environmentFilter || entry.localId === this.environmentFilter));
    const group = this.selectedProjectFilter();
    const projects = this.projectFilterKey ? group?.projects || [] : this.scopedProjects;
    const project = newTaskDestination(projects, ready.map((entry: EnvironmentEntry) => entry.localId),
      workspacePrefs.useLastProjectForNewThreads, current, group, this.environmentFilter || sourceLocalId,
      workspacePrefs.lastThreadProject);
    if (!project) { this.openProjectPicker(); return; }
    this.startingNewTask = true;
    this.keyboard.reset();
    try {
      if (this.draftMode) await this.persistDraft();
      if (!this.alive || this.shareId || this.page !== sourcePage || this.selectedLocalId !== sourceLocalId) return;
      await registry.select(project.localId);
      const expectedPage = sourceLocalId === project.localId ? sourcePage : 'sessions';
      if (!this.alive || this.shareId || this.page !== expectedPage) return;
      if (!registry.clients.get(project.localId)?.ready || this.selectedLocalId !== project.localId ||
        this.draftEnvironment() !== project.environmentId) {
        this.openProjectPicker();
        return;
      }
      this.pendingDraftId = '';
      const oldDraft = this.activeDraftId;
      await this.beginDraft(project.id);
      if (this.alive && !this.shareId && this.page === expectedPage && this.activeDraftId === oldDraft) {
        this.openProjectPicker();
      }
    } catch (error) {
      this.status = (error as Error).message;
      if (this.alive && !this.shareId && this.page === sourcePage) this.openProjectPicker();
    } finally { this.startingNewTask = false; }
  }

  private rememberProject(projectId: string): void {
    const project = this.scopedProjects.find((item: ScopedProject) =>
      item.localId === this.selectedLocalId && item.id === projectId && !item.isScratch && !item.archivedAt);
    if (project) rememberThreadProject({ environmentId: project.environmentId, projectId: project.id });
  }

  private openProjectPicker(forShare: boolean = false, fromDraft: boolean = false): void {
    this.keyboard.reset();
    if (this.busy || this.unknown) { this.status = '请先等待提交完成或核对上次结果'; return; }
    if (!forShare && !this.ready && !this.environmentEntries.some((entry: EnvironmentEntry) =>
      entry.enabled && !entry.deleting && !!this.registry().clients.get(entry.localId)?.ready)) {
      this.openPanel('server');
      return;
    }
    this.panelOpen = false;
    this.threadQuery = ''; this.threadSearchHits = {};
    this.pickerQuery = '';
    this.pickerEnvironmentId = '';
    if (fromDraft && this.draftMode && this.activeDraftId) {
      if (this.draftSaveTimer) { clearTimeout(this.draftSaveTimer); this.draftSaveTimer = 0; }
      const current = this.draftRecord();
      if (current) {
        this.draftRecords = [current].concat(this.draftRecords.filter((item: ComposerDraft) => item.draftId !== current.draftId));
      }
      void this.persistDraft().catch(() => {});
      this.pendingDraftId = this.activeDraftId;
      this.projectPickerReturn = 'chat';
    } else {
      this.pendingDraftId = '';
      this.projectPickerReturn = forShare ? 'share' : 'sessions';
    }
    this.choosingShare = forShare; this.page = 'choose-project';
  }
  private pickerGroups(): ProjectGroup[] {
    const projects = this.scopedProjects.filter((project: ScopedProject) => !project.archivedAt &&
      (!this.pickerEnvironmentId || project.environmentId === this.pickerEnvironmentId));
    return pickableProjectGroups(sortProjectGroups(buildProjectGroups(projects, workspacePrefs.projectGroupingMode),
      this.scopedThreads));
  }
  private pickerEnvironments() {
    return this.workspace().addEnvironments().filter((environment) =>
      !!environment.scratchWorkspaceRoot || this.scopedProjects.some((project: ScopedProject) =>
        project.environmentId === environment.environmentId && !project.isScratch));
  }
  private closeProjectPicker(): void {
    const next = this.choosingShare ? 'share' : (this.projectPickerReturn === 'chat' && this.draftMode ? 'chat' : 'sessions');
    this.choosingShare = false;
    this.pendingDraftId = '';
    this.projectPickerReturn = 'sessions';
    this.page = next;
  }
  private async chooseProject(project: ScopedProject): Promise<void> {
    if (this.choosingShare) {
      if (this.shareLocalId !== project.localId || this.shareProjectId !== project.id) this.resetShareUploads();
      this.shareLocalId = project.localId; this.shareProjectId = project.id;
      this.shareDestination = project.environmentLabel + ' · ' + project.label; this.shareError = '';
      this.choosingShare = false; this.projectPickerReturn = 'sessions'; this.page = 'share'; return;
    }
    const pending = this.pendingDraftId;
    try {
      await this.registry().select(project.localId);
      this.pendingDraftId = '';
      if (pending && await this.retargetDraft(project, pending)) {
        this.projectPickerReturn = 'sessions';
        return;
      }
      this.projectPickerReturn = 'sessions';
      await this.beginDraft(project.id);
    }
    catch (error) {
      if (pending && this.page === 'choose-project') this.pendingDraftId = pending;
      this.status = (error as Error).message;
    }
  }
  private async startScratch(environmentId: string): Promise<void> {
    if (this.busy) return;
    const environment = this.workspace().addEnvironments().find((entry) =>
      entry.environmentId === environmentId && !!entry.scratchWorkspaceRoot && entry.ready);
    if (!environment) { this.status = '此环境未启用 No project'; return; }
    this.busy = true;
    const pending = this.pendingDraftId;
    try {
      const projectId = await this.workspace().ensureScratch(environment);
      this.registry().clients.get(environment.localId)?.refreshShell();
      const found = await this.workspace().waitForProject(environment, projectId, 3000);
      const project = this.scopedProjects.find((entry: ScopedProject) => entry.localId === environment.localId && entry.id === projectId);
      await this.registry().select(environment.localId);
      this.busy = false;
      this.pendingDraftId = '';
      this.projectPickerReturn = 'sessions';
      if (pending && project && await this.retargetDraft(project, pending)) {
        if (!found) this.rebuildWorkspace();
        return;
      }
      if (pending) {
        const oldDraft = this.draftRecords.find((item: ComposerDraft) => item.draftId === pending);
        if (oldDraft && !oldDraft.text.trim() && oldDraft.attachments.length === 0 && oldDraft.context.length === 0) {
          await this.deleteDraft(pending);
        }
      }
      await this.beginDraft(projectId);
      if (!found || !project) this.rebuildWorkspace();
    } catch (error) {
      if (pending && this.page === 'choose-project') this.pendingDraftId = pending;
      this.status = (error as Error).message;
    }
    finally { this.busy = false; this.rebuildWorkspace(); }
  }
  private openAddProject(returnTo: string): void {
    void this.refreshSessions();
    const environments = this.workspace().addEnvironments();
    const selected = this.environmentEntries.find((entry: EnvironmentEntry) =>
      entry.localId === this.registry().directory.selectedLocalId);
    this.addProjectEnvironmentId = environments.find((environment) =>
      environment.environmentId === selected?.environmentId)?.environmentId || environments[0]?.environmentId || '';
    this.addProjectReturn = returnTo;
    this.page = 'add-project';
  }
  private async openProjectAfterCreate(project: ScopedProject): Promise<void> {
    await this.chooseProject(project);
    this.status = '项目已添加：' + project.label;
  }
  private openSettings(): void {
    void this.refreshSessions();
    this.page = 'settings';
  }
  private selectedGroup(): ProjectGroup | undefined {
    return this.projectGroups.find((group: ProjectGroup) => group.key === this.overviewGroupKey);
  }
  private archivedThreadCount(): number {
    let count = 0;
    this.registry().clients.forEach((value: T3Client) => { count += value.shell.archived.length; });
    return count;
  }
  private openProjectOverview(): void {
    void this.refreshSessions();
    if (!this.projectGroups.some((group: ProjectGroup) => group.key === this.overviewGroupKey)) {
      this.overviewGroupKey = this.projectGroups[0]?.key || '';
    }
    this.page = 'project-overview';
  }
  private openArchive(): void {
    if (this.archiveEnvironmentId && !this.environmentEntries.some((entry: EnvironmentEntry) =>
      entry.environmentId === this.archiveEnvironmentId && !entry.deleting)) {
      this.archiveEnvironmentId = '';
    }
    this.page = 'archive';
    void this.loadArchive();
  }
  private archiveScratchRoots(): Record<string, string> {
    const roots: Record<string, string> = {};
    this.registry().clients.forEach((value: T3Client, localId: string) => {
      if (value.scratchWorkspaceRoot) roots[localId] = value.scratchWorkspaceRoot;
    });
    return roots;
  }
  private rebuildArchiveGroups(): void {
    this.archiveGroups = buildArchiveGroups({
      snapshots: this.archiveSnapshots, entries: this.environmentEntries.map((entry: EnvironmentEntry): ArchiveEnvironmentEntry => {
        return { localId: entry.localId, environmentId: entry.environmentId, label: entry.label };
      }), environmentId: this.archiveEnvironmentId, query: this.archiveQuery,
      sortOrder: this.archiveSort, scratchRoots: this.archiveScratchRoots()
    });
  }
  private async loadArchive(): Promise<void> {
    const generation = ++this.archiveGeneration;
    this.archiveLoading = true;
    try {
      void this.refreshSessions();
      const snapshots = await this.workspace().archiveSnapshot(this.environmentEntries.filter((entry: EnvironmentEntry) =>
        !entry.deleting && entry.enabled && this.registry().entryVisible(entry)));
      if (generation !== this.archiveGeneration || !this.alive) return;
      this.archiveSnapshots = snapshots;
      this.rebuildArchiveGroups();
    } catch (error) { this.status = (error as Error).message; }
    finally { if (generation === this.archiveGeneration) this.archiveLoading = false; }
  }
  private async refreshSessions(): Promise<void> {
    await Promise.all(this.environmentEntries.filter((entry: EnvironmentEntry) =>
      !entry.deleting && entry.enabled && this.registry().entryVisible(entry)).map(async (entry: EnvironmentEntry) => {
      const connection = this.registry().clients.get(entry.localId);
      if (connection?.ready) {
        try { await connection.refreshSessionAccess(); } catch (_) {}
      }
    }));
  }
  private async openArchivedThread(thread: ScopedThread): Promise<void> {
    try {
      await this.registry().select(thread.localId);
      this.projectId = thread.projectId;
      await this.workspace().visit(thread, true, '');
      await this.watch(thread.id);
    } catch (error) { this.status = (error as Error).message; }
  }
  private showUndo(undo: WorkspaceUndo): void {
    this.undoNotice = undo;
    if (this.undoTimer) clearTimeout(this.undoTimer);
    this.undoTimer = setTimeout(() => { this.undoNotice = undefined; this.undoTimer = 0; }, 5000) as number;
  }
  private async executeUndo(): Promise<void> {
    const undo = this.undoNotice;
    if (!undo) return;
    this.undoNotice = undefined;
    if (this.undoTimer) { clearTimeout(this.undoTimer); this.undoTimer = 0; }
    this.busy = true;
    try { await this.workspace().executeUndo(undo); this.status = '已撤销'; }
    catch (error) { this.status = (error as Error).message; }
    finally { this.busy = false; this.rebuildWorkspace(); }
  }
  private confirmDeleteThread(thread: ScopedThread): void {
    AlertDialog.show({
      title: '删除会话？', message: '“' + thread.label + '”将被永久删除，包括终端记录。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '删除', action: () => { void this.threadAction(thread, 'delete-confirmed'); } }
    });
  }
  private async threadAction(thread: ScopedThread, action: string): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    try {
      if (action === 'settle') this.showUndo(await this.workspace().settle(thread));
      else if (action === 'unsettle') await this.workspace().unsettle(thread);
      else if (action === 'unsnooze') await this.workspace().unsnooze(thread);
      else if (action === 'pin') await this.workspace().pin(thread, topOfPinnedRun(this.shelves.pinned));
      else if (action === 'unpin') { await this.workspace().unpin(thread); this.showUndo(this.workspace().undoPlan('unpin', thread)); }
      else if (action === 'archive') await this.workspace().archive(thread);
      else if (action === 'delete') this.confirmDeleteThread(thread);
      else if (action === 'delete-confirmed') await this.workspace().deleteThread(thread);
      else if (action === 'rename') { this.renameThread = thread; this.openPanel('rename'); }
      else if (action === 'regenerate') await this.workspace().regenerateTitle(thread);
      else if (action === 'unread') await this.workspace().markUnread(thread);
      else if (action === 'auto-settle-on') await this.workspace().setAutoSettle(thread, true);
      else if (action === 'auto-settle-off') await this.workspace().setAutoSettle(thread, false);
      else if (action === 'turn-into-project') await this.workspace().turnIntoProject(thread);
      if (action !== 'delete' && action !== 'rename') this.status = '操作已提交';
    } catch (error) { this.status = (error as Error).message; }
    finally { this.busy = false; this.rebuildWorkspace(); }
  }
  private async snoozeSelected(thread: ScopedThread, value: string): Promise<void> {
    await this.workspace().snooze(thread, value);
    this.showUndo(this.workspace().undoPlan('snooze', thread));
    this.panelOpen = false; this.snoozeThread = undefined; this.rebuildWorkspace();
  }
  private async renameSelected(thread: ScopedThread, title: string): Promise<void> {
    await this.workspace().rename(thread, title);
    this.panelOpen = false; this.renameThread = undefined; this.rebuildWorkspace();
  }
  private canOrganize(group: ProjectGroup | undefined): boolean {
    if (!group) return false;
    return group.projects.every((project: ScopedProject) => {
      const connection = this.registry().clients.get(project.localId);
      return !!connection?.ready && connection.supports('projectOrganization') &&
        connection.canScope('orchestration:operate') !== false;
    });
  }
  private async updateGroup(group: ProjectGroup, patch: ProjectUpdatePatch): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    try { await this.workspace().updateProjects(group.projects, patch); }
    catch (error) { this.status = (error as Error).message; }
    finally { this.busy = false; this.rebuildWorkspace(); }
  }
  private renameGroup(group: ProjectGroup, title: string): void {
    const patch: ProjectUpdatePatch = { title };
    void this.updateGroup(group, patch);
  }
  private pinGroup(group: ProjectGroup, pinned: boolean): void {
    const patch: ProjectUpdatePatch = { pinned };
    void this.updateGroup(group, patch);
  }
  private archiveGroup(group: ProjectGroup, archived: boolean): void {
    const patch: ProjectUpdatePatch = { archived };
    void this.updateGroup(group, patch);
  }
  private confirmRemoveCheckout(project: ScopedProject): void {
    AlertDialog.show({
      title: '移除 checkout？', message: '删除此机器上的项目记录和会话，不删除磁盘文件。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '移除', action: () => { void this.removeCheckout(project); } }
    });
  }
  private async removeCheckout(project: ScopedProject): Promise<void> {
    this.busy = true;
    try { await this.workspace().deleteProject(project); this.status = 'checkout 已移除'; }
    catch (error) { this.status = (error as Error).message; }
    finally { this.busy = false; this.rebuildWorkspace(); }
  }
  private confirmRemoveProject(group: ProjectGroup): void {
    AlertDialog.show({
      title: group.projects.length > 1 ? '删除所有 checkout？' : '删除项目？',
      message: '将删除项目记录和会话；磁盘文件保留。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '删除', action: () => { void this.removeProject(group); } }
    });
  }
  private async removeProject(group: ProjectGroup): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    try {
      for (const project of group.projects) await this.workspace().deleteProject(project);
      this.status = '项目已删除';
      this.overviewGroupKey = this.projectGroups.find((item: ProjectGroup) => item.key !== group.key)?.key || '';
    } catch (error) { this.status = (error as Error).message; }
    finally { this.busy = false; this.rebuildWorkspace(); }
  }
  private chooseGrouping(mode: string): void {
    workspacePrefs.projectGroupingMode = mode;
    saveWorkspacePreferences();
    this.projectGroups = buildProjectGroups(this.scopedProjects, mode);
    this.syncProjectFilter();
    this.rebuildWorkspace();
  }
  private selectedProjectFilter(): ProjectGroup | undefined {
    if (!this.projectFilterKey) return undefined;
    const mode = workspacePrefs.projectFilterGroupingMode || workspacePrefs.projectGroupingMode;
    const groups = mode === workspacePrefs.projectGroupingMode ? this.projectGroups : buildProjectGroups(this.scopedProjects, mode);
    return groups.find((group: ProjectGroup) => group.key === this.projectFilterKey);
  }
  private syncProjectFilter(): void {
    const selected = this.selectedProjectFilter();
    this.projectFilterRefs = projectGroupRefs(selected);
    this.projectFilterLabel = selected?.label || (this.projectFilterKey ? '已选项目暂不可用' : '所有项目');
  }
  private setThreadQuery(value: string): void {
    this.threadQuery = value;
    this.threadSearchHits = {};
    if (this.searchTimer) clearTimeout(this.searchTimer);
    const generation = ++this.searchGeneration;
    const query = value.trim();
    if (query.length < 2) { this.rebuildWorkspace(); return; }
    this.searchTimer = setTimeout(() => {
      if (!this.alive || generation !== this.searchGeneration) return;
      const group = this.selectedProjectFilter();
      if (this.projectFilterKey && !group) return;
      const projectIds = group ? group.projectRefs.map((ref) => ref.projectId) : [];
      void this.workspace().search(this.environmentEntries.filter((entry: EnvironmentEntry) =>
        !entry.deleting && entry.enabled && this.registry().entryVisible(entry) &&
        (!this.environmentFilter || entry.localId === this.environmentFilter)), query, projectIds)
        .then((hits: Record<string, string>) => {
          if (!this.alive || generation !== this.searchGeneration) return;
          this.threadSearchHits = hits; this.bindEnvironment(); this.rebuildWorkspace();
        }).catch(() => {});
    }, 300) as number;
    this.rebuildWorkspace();
  }
  private filterProjectKey(key: string): void {
    const group = this.projectGroups.find((entry: ProjectGroup) => entry.key === key);
    this.projectFilterKey = group?.key || '';
    workspacePrefs.projectFilterKey = this.projectFilterKey;
    workspacePrefs.projectFilterGroupingMode = group ? workspacePrefs.projectGroupingMode : undefined;
    this.syncProjectFilter();
    saveWorkspacePreferences();
    this.rebuildWorkspace();
  }
  private async restoreAddress(): Promise<void> {
    if (this.restoringEnvironments || !this.alive) return;
    this.restoringEnvironments = true;
    try {
      const registry = this.registry();
      if (!registry.initialized) await registry.initialize();
      if (!this.alive) return;
      this.loaded = true; registry.onUpdate();
      await Promise.all(registry.directory.entries.filter((e: EnvironmentEntry) => e.enabled && !e.deleting && registry.entryVisible(e))
        .map(async (e: EnvironmentEntry) => {
          try { await registry.reconnect(e.localId); }
          catch (_) {}
        }));
    } catch (error) { if (this.alive) this.status = (error as Error).message; }
    finally { this.restoringEnvironments = false; }
  }
  aboutToDisappear(): void {
    this.keyboard.reset();
    this.alive = false; this.linkPermissionGeneration++; this.linkOwner = undefined; this.linkedGeneration++;
    this.deviceWatchGeneration++; this.deviceWatchKey = ''; client.stopAuthAccess();
    if (this.clockTimer) clearInterval(this.clockTimer);
    if (this.snoozeTimer) clearTimeout(this.snoozeTimer);
    if (this.searchTimer) clearTimeout(this.searchTimer);
    if (this.undoTimer) clearTimeout(this.undoTimer);
    if (this.backgroundStopTimer) clearTimeout(this.backgroundStopTimer);
    if (this.connUiTimer) clearTimeout(this.connUiTimer);
    this.clockTimer = 0; this.snoozeTimer = 0; this.searchTimer = 0; this.undoTimer = 0;
    this.backgroundStopTimer = 0; this.connUiTimer = 0;
    this.registry().onUpdate = () => {};
  }

  private async connect(): Promise<void> {
    if (!this.loaded || this.busy) return;
    this.busy = true;
    this.pairingError = false;
    this.pairingStatus = '正在连接与校验环境';
    try {
      const target = pairingTarget(this.address, this.credential);
      if (this.routeFor) await this.registry().addRoute(this.routeFor, target.base, target.code);
      else await this.registry().add(target.base, target.code);
      this.credential = '';
      this.address = target.base; this.routeFor = ''; this.openPanel('server'); void this.loadLinkedEnvironments();
    } catch (error) {
      const message = (error as Error).message;
      if (message.includes('服务器身份')) this.credential = '';
      this.pairingError = true;
      this.pairingStatus = message;
    }
    finally { this.busy = false; this.incomingPairing(); }
  }
  private draftKey(): string {
    return this.selectedLocalId + '\n' + (this.draftMode ? 'D:' + this.activeDraftId : 'T:' + this.threadId);
  }

  private draftEnvironment(): string {
    return this.environmentEntries.find((entry: EnvironmentEntry) =>
      entry.localId === this.selectedLocalId)?.environmentId || '';
  }

  private draftRecord(): ComposerDraft | undefined {
    if (!this.draftMode || !this.activeDraftId) return undefined;
    const draft: ComposerDraft = { version: 1, draftId: this.activeDraftId, localId: this.selectedLocalId,
      environmentId: this.draftEnvironment(), projectId: this.projectId, text: this.prompt,
      modelSelection: this.taskSettings.modelSelection, runtimeMode: this.taskSettings.runtimeMode,
      interactionMode: this.taskSettings.interactionMode, workspace: this.draftWorkspace,
      attachments: client.attachments.slice(), context: this.draftContext.slice(), updatedAt: Date.now() };
    if (this.draftModelCustomized) draft.modelCustomized = true;
    return draft;
  }

  private scheduleDraftSave(): void {
    if (!this.draftMode) {
      if (this.threadId) {
        this.textDrafts.set(this.draftKey(), this.prompt);
        this.contextDrafts.set(this.draftKey(), this.draftContext.slice());
      }
      return;
    }
    if (this.draftSaveTimer) clearTimeout(this.draftSaveTimer);
    this.draftSaveTimer = setTimeout(() => {
      this.draftSaveTimer = 0;
      void this.persistDraft().catch((error: Error) => { this.status = '草稿未保存：' + error.message; });
    }, 250) as number;
  }

  private async persistDraft(): Promise<void> {
    const value = this.draftRecord();
    if (!value || !draftStore) return;
    const others = this.draftRecords.filter((item: ComposerDraft) => item.draftId !== value.draftId);
    const next = [value].concat(others);
    await draftStore.save(next);
    this.draftRecords = next;
  }

  private async deleteDraft(id: string): Promise<void> {
    if (!id) return;
    const next = this.draftRecords.filter((item: ComposerDraft) => item.draftId !== id);
    this.draftRecords = next;
    if (draftStore) await draftStore.save(next);
  }

  private projectForDraft(draft: ComposerDraft): ScopedProject | undefined {
    return this.scopedProjects.find((project: ScopedProject) =>
      project.localId === draft.localId && project.id === draft.projectId);
  }

  private async resumeDraft(draft: ComposerDraft): Promise<void> {
    if (this.busy || this.unknown) { this.status = '请先等待提交完成或核对上次结果'; return; }
    const entry = this.environmentEntries.find((item: EnvironmentEntry) => item.localId === draft.localId);
    if (!entry || (draft.environmentId && entry.environmentId && entry.environmentId !== draft.environmentId)) {
      this.status = '草稿所属环境已变化，不能恢复';
      return;
    }
    const project = this.projectForDraft(draft);
    if (!project) {
      this.pendingDraftId = draft.draftId;
      this.projectPickerReturn = 'sessions';
      this.status = '原项目已移除，请为草稿重新选择项目';
      this.page = 'choose-project';
      return;
    }
    if (this.pendingDraftId && this.pendingDraftId !== draft.draftId) {
      const oldDraft = this.draftRecords.find((item: ComposerDraft) => item.draftId === this.pendingDraftId);
      if (oldDraft && !oldDraft.text.trim() && oldDraft.attachments.length === 0 && oldDraft.context.length === 0) {
        await this.deleteDraft(this.pendingDraftId);
      }
    }
    this.pendingDraftId = '';
    this.projectPickerReturn = 'sessions';
    await this.registry().select(draft.localId);
    await this.beginDraft(project.id, draft.draftId);
  }

  private resolveDraftModelChoice(preferred: ModelSelection | undefined, fallback: ModelChoice | undefined): ModelSelection {
    if (preferred && preferred.instanceId && preferred.model) {
      return preferred.options && preferred.options.length > 0
        ? { instanceId: preferred.instanceId, model: preferred.model, options: preferred.options.slice() }
        : { instanceId: preferred.instanceId, model: preferred.model };
    }
    return { instanceId: fallback?.instanceId || '', model: fallback?.model || '' };
  }

  private isDraftModelSelectableForProject(selection: ModelSelection, projectId: string): boolean {
    if (!selection.instanceId || !selection.model) return false;
    if (!this.models.some((item: ModelChoice) => item.instanceId === selection.instanceId && item.model === selection.model)) {
      return false;
    }
    const rawConfig = client ? (client as Object as Record<string, Object>).config : undefined;
    if (rawConfig !== undefined && rawConfig !== null && typeof rawConfig === 'object' && !Array.isArray(rawConfig)) {
      const root = rawConfig as Record<string, Object>;
      const settings = root.settings !== undefined && root.settings !== null && typeof root.settings === 'object' && !Array.isArray(root.settings)
        ? root.settings as Record<string, Object> : undefined;
      const overridesMap = settings && settings.projectSettingsOverrides !== undefined && settings.projectSettingsOverrides !== null &&
        typeof settings.projectSettingsOverrides === 'object' && !Array.isArray(settings.projectSettingsOverrides)
        ? settings.projectSettingsOverrides as Record<string, Object> : undefined;
      const projectOverride = overridesMap && overridesMap[projectId] !== undefined && overridesMap[projectId] !== null &&
        typeof overridesMap[projectId] === 'object' && !Array.isArray(overridesMap[projectId])
        ? overridesMap[projectId] as Record<string, Object> : undefined;
      const projectProviders = projectOverride && projectOverride.providerInstances !== undefined && projectOverride.providerInstances !== null &&
        typeof projectOverride.providerInstances === 'object' && !Array.isArray(projectOverride.providerInstances)
        ? projectOverride.providerInstances as Record<string, Object> : undefined;
      const providerOverride = projectProviders && projectProviders[selection.instanceId] !== undefined && projectProviders[selection.instanceId] !== null &&
        typeof projectProviders[selection.instanceId] === 'object' && !Array.isArray(projectProviders[selection.instanceId])
        ? projectProviders[selection.instanceId] as Record<string, Object> : undefined;
      if (providerOverride && providerOverride.enabled === false) return false;
      const policy = root.managedPolicy !== undefined && root.managedPolicy !== null && typeof root.managedPolicy === 'object' && !Array.isArray(root.managedPolicy)
        ? root.managedPolicy as Record<string, Object> : undefined;
      const limits = policy && policy.limits !== undefined && policy.limits !== null && typeof policy.limits === 'object' && !Array.isArray(policy.limits)
        ? policy.limits as Record<string, Object> : undefined;
      const providerLimits = limits && limits.providers !== undefined && limits.providers !== null && typeof limits.providers === 'object' && !Array.isArray(limits.providers)
        ? limits.providers as Record<string, Object> : undefined;
      if (providerLimits && Array.isArray(providerLimits.allowedDrivers) && Array.isArray(root.providers)) {
        const providerRow = (root.providers as Object[]).find((entry: Object) =>
          entry !== null && typeof entry === 'object' && !Array.isArray(entry) &&
          (entry as Record<string, Object>).instanceId === selection.instanceId) as Record<string, Object> | undefined;
        const driver = providerRow && typeof providerRow.driver === 'string' ? providerRow.driver as string : '';
        if (!driver || !(providerLimits.allowedDrivers as Object[]).includes(driver)) return false;
      }
    }
    return true;
  }

  private async newDraftDefaults(projectId: string): Promise<DraftDefaults> {
    const owner = client;
    const localId = this.selectedLocalId;
    const page = this.page;
    const generation = owner.generationValue();
    const project = this.scopedProjects.find((item: ScopedProject) => item.localId === localId && item.id === projectId);
    if (!project || project.archivedAt) throw new Error('目标项目不可用，请重新选择');
    const environmentId = project.environmentId;
    const workspaceRoot = project.workspaceRoot;
    const defaults = await readDraftDefaults(owner, environmentId, {
      id: project.id, workspaceRoot: project.workspaceRoot, isScratch: project.isScratch,
      hasThreads: this.scopedThreads.some((item: ScopedThread) => item.localId === localId && item.projectId === projectId),
      defaultThreadEnvMode: project.defaultThreadEnvMode,
      defaultModelSelection: project.defaultModelSelection
    });
    const current = this.scopedProjects.find((item: ScopedProject) => item.localId === localId && item.id === projectId);
    if (client !== owner || !owner.ready || owner.generationValue() !== generation || this.selectedLocalId !== localId ||
      this.page !== page || !current || current.archivedAt || current.environmentId !== environmentId ||
      current.workspaceRoot !== workspaceRoot) throw new Error('环境或项目已变化，请重新选择');
    return defaults;
  }

  private async beginDraft(projectId: string, draftId: string = ''): Promise<void> {
    if (this.busy || this.unknown) { this.status = '请先等待提交完成或核对上次结果'; return; }
    if (this.draftMode && this.activeDraftId && this.activeDraftId !== draftId) void this.persistDraft().catch(() => {});
    else if (this.threadId) {
      this.textDrafts.set(this.draftKey(), this.prompt);
      this.contextDrafts.set(this.draftKey(), this.draftContext.slice());
    }
    const existing = draftId ? this.draftRecords.find((item: ComposerDraft) => item.draftId === draftId) : undefined;
    if (draftId && !existing) { this.status = '草稿不存在或已删除'; return; }
    if (existing && (existing.localId !== this.selectedLocalId || existing.projectId !== projectId)) {
      this.status = '草稿所属环境或项目已变化，不能恢复';
      return;
    }
    let defaults: DraftDefaults | undefined = undefined;
    if (!existing) {
      this.busy = true;
      try { defaults = await this.newDraftDefaults(projectId); }
      catch (error) { this.status = (error as Error).message; return; }
      finally { this.busy = false; }
    }
    this.activeDraftId = existing?.draftId || util.generateRandomUUID();
    this.draftMode = true; this.projectId = projectId; this.threadId = ''; this.modelIndex = 0;
    this.draftModelCustomized = existing?.modelCustomized === true;
    client.draftScope = 'draft:' + this.activeDraftId;
    this.picker.clear(); this.canRetryAttachment = false; this.attachmentName = ''; client.attachments = []; client.attachment = undefined;
    client.worktreeSetup = undefined; this.worktreeSetup = undefined;
    const model = this.models[0];
    this.taskSettings = existing ? draftSettings(existing) : {
      modelSelection: this.resolveDraftModelChoice(defaults?.modelSelection, model),
      runtimeMode: defaults!.runtimeMode, interactionMode: 'default' };
    this.prompt = existing?.text || '';
    this.draftWorkspace = existing?.workspace || defaults!.workspace;
    this.draftContext = existing?.context ? existing.context.slice() : [];
    this.attachments = existing?.attachments ? existing.attachments.slice() : [];
    client.attachments = this.attachments.slice();
    client.bindDraftAttachments(client.draftScope);
    this.branches = []; this.branchesLoading = false; this.commandPanel = '';
    this.messages = []; this.source.update([]); this.actions = []; this.tools = []; this.linkItems = [];
    this.workMap = emptyWorkMap();
    this.messageFooterMap = {};
    this.forkingMessageId = '';
    this.canOperateChat = false;
    this.renderedThreadKey = '';
    this.hasMoreHistory = false;
    this.chatAwayFromBottom = false;
    this.threadRunning = false;
    this.pendingScrollBottomKey = '';
    this.lastAutoWatchKey = '';
    this.cachedChatTitle = '';
    this.cachedChatProject = '';
    this.expandedWorkGroups = {}; this.expandedUserMessages = {}; this.canOpenDiff = false;
    this.queued = []; this.extraPlans = []; this.extraSubagents = []; this.extraBackground = [];
    this.extraGuest = undefined; this.extraUsage = undefined;
    this.floatingCapsule = emptyFloatingCapsule();
    this.liveThinking = emptyLiveThinkingRow();
    this.turnSubagents = [];
    this.pendingBackgroundItems = [];
    this.page = 'chat'; this.panelOpen = false; this.sendMode = 'auto';
    this.activeModelInstanceId = this.taskSettings.modelSelection.instanceId;
    this.activeModelDriver = '';
    this.activeModelSlug = this.taskSettings.modelSelection.model;
    this.activeModelLabel = '';
    this.activeModelSummary = '';
    this.rememberProject(projectId);
    this.status = existing ? '已恢复本地草稿' : '新任务草稿已保存';
    if (!existing) { this.draftRecords = [this.draftRecord()!].concat(this.draftRecords); void this.persistDraft().catch(() => {}); }
    void this.loadBranches();
  }

  private refreshAttachments(): void {
    this.attachments = client.attachments.slice();
    this.attachmentName = this.attachments.map((item: DraftAttachment) => item.name).join('、');
    this.canRetryAttachment = this.picker.canRetry();
  }

  private draftCwd(): string {
    if (this.draftWorkspace.worktreePath) return this.draftWorkspace.worktreePath;
    return this.scopedProjects.find((project: ScopedProject) =>
      project.localId === this.selectedLocalId && project.id === this.projectId)?.workspaceRoot || '';
  }

  private branchRequest: number = 0;

  private draftBranchContext(owner: T3Client, generation: number, draft: string, projectId: string, cwd: string): boolean {
    return this.alive && this.appForeground && this.page === 'chat' && this.draftMode && client === owner && owner.ready &&
      owner.generationValue() === generation && this.draftKey() === draft && this.projectId === projectId && this.draftCwd() === cwd;
  }

  private async loadBranches(): Promise<void> {
    const owner = client;
    const cwd = this.draftCwd();
    const request = ++this.branchRequest;
    if (!cwd || !owner.ready || !this.draftMode || !this.appForeground || this.page !== 'chat') {
      this.branches = []; this.branchesLoading = false; return;
    }
    const generation = owner.generationValue();
    const draft = this.draftKey();
    const projectId = this.projectId;
    const currentRequest = (): boolean => request === this.branchRequest &&
      this.draftBranchContext(owner, generation, draft, projectId, cwd);
    this.branchesLoading = true;
    try {
      const refs = await owner.listBranches(cwd);
      if (!currentRequest()) return;
      this.branches = refs;
      const current = refs.find((ref: BranchView) => ref.current);
      if (this.draftWorkspace.mode === 'local' && !this.draftWorkspace.branch && current) {
        this.draftWorkspace.branch = current.name;
      }
      if (this.draftWorkspace.mode === 'worktree' && !this.draftWorkspace.branch) {
        this.draftWorkspace.branch = refs.find((ref: BranchView) => ref.isDefault)?.name || current?.name || '';
      }
    } catch (error) {
      if (currentRequest()) { this.status = (error as Error).message; this.branches = []; }
    } finally { if (request === this.branchRequest) this.branchesLoading = false; }
  }

  private setWorkspaceMode(mode: string): void {
    if (!this.draftMode || this.busy || this.unknown || mode === this.draftWorkspace.mode) return;
    this.draftWorkspace = switchDraftWorkspaceMode(this.draftWorkspace, mode, this.branches);
    this.scheduleDraftSave();
  }

  private async selectBranch(ref: BranchView): Promise<void> {
    const owner = client;
    const cwd = this.draftCwd();
    const generation = owner.generationValue();
    const draft = this.draftKey();
    const projectId = this.projectId;
    const current = (): boolean => this.draftBranchContext(owner, generation, draft, projectId, cwd);
    if (this.busy || this.unknown || !current()) return;
    if (this.draftWorkspace.mode === 'local' && !ref.isRemote && !ref.current && !ref.worktreePath) {
      if (!owner.canWriteSourceControl()) throw new Error('此连接不能切换 checkout 分支');
      if (!cwd) throw new Error('项目没有工作目录');
      this.busy = true;
      try { await owner.switchBranch(cwd, ref.name); }
      catch (error) { if (current()) throw error as Error; else return; }
      finally { this.busy = false; }
    }
    if (!current()) return;
    this.draftWorkspace = draftWorkspaceForBranch(this.draftWorkspace, ref);
    this.panelOpen = false; this.scheduleDraftSave();
    await this.loadBranches();
  }

  private async applyCurrentCheckoutBranch(): Promise<void> {
    if (this.draftWorkspace.mode !== 'local' || !this.draftWorkspace.branch) return;
    const cwd = this.draftCwd();
    if (!cwd) throw new Error('项目没有工作目录');
    this.busy = true;
    try {
      await client.switchBranch(cwd, this.draftWorkspace.branch);
      await this.loadBranches();
      this.status = '当前 checkout 已切换分支';
    } finally { this.busy = false; }
  }

  private async retargetDraft(project: ScopedProject, draftId: string): Promise<boolean> {
    const found = draftId ? this.draftRecords.find((draft: ComposerDraft) => draft.draftId === draftId) : undefined;
    if (!found) return false;
    const sameTarget = found.localId === project.localId && found.projectId === project.id;
    const envChanged = found.localId !== project.localId ||
      (!!found.environmentId && !!project.environmentId && found.environmentId !== project.environmentId);
    if (!sameTarget) {
      let defaults: DraftDefaults;
      this.busy = true;
      try { defaults = await this.newDraftDefaults(project.id); }
      finally { this.busy = false; }
      const droppedAttachments = envChanged && found.attachments.length > 0;
      const fallbackModel = this.models[0];
      const explicitKeep = found.modelCustomized === true && this.isDraftModelSelectableForProject(found.modelSelection, project.id);
      found.localId = project.localId;
      found.environmentId = project.environmentId;
      found.projectId = project.id;
      found.workspace = defaults.workspace;
      if (envChanged || found.modelCustomized !== true) {
        found.runtimeMode = defaults.runtimeMode;
      }
      if (envChanged) found.attachments = [];
      if (!explicitKeep) {
        if (defaults.modelSelection && defaults.modelSelection.instanceId && defaults.modelSelection.model) {
          found.modelSelection = this.resolveDraftModelChoice(defaults.modelSelection, fallbackModel);
          found.modelCustomized = undefined;
        } else if (envChanged && !this.models.some((item: ModelChoice) =>
          item.instanceId === found.modelSelection.instanceId && item.model === found.modelSelection.model)) {
          found.modelSelection = { instanceId: fallbackModel?.instanceId || '', model: fallbackModel?.model || '' };
          found.modelCustomized = undefined;
        }
      }
      found.context = found.context.filter((item: ComposerContextRecord) => item.kind !== 'mention');
      found.updatedAt = Date.now();
      if (draftStore) await draftStore.save(this.draftRecords);
      await this.beginDraft(project.id, draftId);
      this.status = droppedAttachments ? '已切换项目与环境；原环境附件未带入' : '已切换项目：' + project.label;
      return true;
    }
    await this.beginDraft(project.id, draftId);
    return true;
  }

  private async switchDraftEnvironment(environmentId: string): Promise<void> {
    const target = this.environmentEntries.find((entry: EnvironmentEntry) =>
      entry.environmentId === environmentId && !entry.deleting);
    if (!target) throw new Error('环境不可用');
    const currentProject = this.scopedProjects.find((item: ScopedProject) =>
      item.localId === this.selectedLocalId && item.id === this.projectId);
    const repoKey = currentProject?.repository?.groupingKey || '';
    const project = (repoKey ? this.scopedProjects.find((item: ScopedProject) =>
      item.localId === target.localId && !item.archivedAt && item.repository?.groupingKey === repoKey) : undefined) ||
      this.scopedProjects.find((item: ScopedProject) =>
        item.localId === target.localId && item.id === this.projectId && !item.archivedAt) ||
      this.scopedProjects.find((item: ScopedProject) =>
        item.localId === target.localId && !item.archivedAt && !item.isScratch) ||
      this.scopedProjects.find((item: ScopedProject) => item.localId === target.localId && !item.archivedAt);
    if (!project) throw new Error('该环境没有可用项目');
    await this.persistDraft();
    await this.registry().select(target.localId);
    this.panelOpen = false;
    if (this.activeDraftId && await this.retargetDraft(project, this.activeDraftId)) return;
    await this.beginDraft(project.id);
  }

  private addFileContext(path: string): void {
    const contextId = 'mention-' + util.generateRandomUUID();
    this.draftContext = this.draftContext.concat([mentionContext(path, contextId)]);
    this.scheduleDraftSave();
  }

  private addSkillContext(name: string): void {
    const contextId = 'skill-' + util.generateRandomUUID();
    this.draftContext = this.draftContext.concat([skillContext(name, contextId)]);
    this.scheduleDraftSave();
  }

  private addTerminalContext(line: ActivityLine): void {
    try {
      const rows = line.text.split('\n');
      const context = terminalContext(line.itemId, '终端 · ' + line.label, 0,
        Math.max(0, rows.length - 1), line.text.slice(0, 64000),
        'terminal-' + util.generateRandomUUID());
      this.draftContext = this.draftContext.concat([context]);
      this.status = '已引用终端输出；发送时作为结构化上下文';
      this.scheduleDraftSave();
    } catch (error) { this.status = (error as Error).message; }
  }

  private removeContext(id: string): void {
    this.draftContext = this.draftContext.filter((item: ComposerContextRecord) => item.contextId !== id);
    this.scheduleDraftSave();
  }

  private async pasteContext(): Promise<void> {
    try {
      const board = pasteboard.getSystemPasteboard();
      const data = await board.getData();
      const plain = await data.getPrimaryText();
      if (!plain || plain.length > 2000000) throw new Error('剪贴板没有可用上下文');
      const value = record(JSON.parse(plain) as Object);
      if (value.version !== 1 || !Array.isArray(value.records)) throw new Error('剪贴板不是 T3 上下文片段');
      const rows: ComposerContextRecord[] = [];
      for (const item of value.records as Object[]) {
        const parsed = contextRecord(item);
        if (!this.draftContext.some((current: ComposerContextRecord) => current.contextId === parsed.contextId) &&
          !rows.some((current: ComposerContextRecord) => current.contextId === parsed.contextId)) rows.push(parsed);
      }
      if (!rows.length) throw new Error('没有新的上下文记录');
      this.draftContext = this.draftContext.concat(rows);
      this.scheduleDraftSave();
      this.status = '已粘贴 ' + rows.length + ' 条结构化上下文';
    } catch (error) { this.status = (error as Error).message; }
  }

  private async openFileMention(): Promise<void> {
    this.commandPanel = 'mention'; this.commandQuery = '';
  }

  private openComposerCommand(mode: string): void {
    this.commandPanel = mode; this.commandQuery = ''; this.mentionFiles = [];
    if (mode === 'branch' && !this.branches.length) void this.loadBranches();
    this.openPanel('composer-command');
  }

  private async searchMentionFiles(query: string): Promise<void> {
    this.commandQuery = query;
    if (!query.trim()) { this.mentionFiles = []; return; }
    try { this.mentionFiles = await client.searchFiles(this.draftCwd(), query); }
    catch (error) { this.status = (error as Error).message; this.mentionFiles = []; }
  }

  private environmentLabels(): string[] {
    return this.environmentEntries.filter((entry: EnvironmentEntry) => !entry.deleting &&
      entry.enabled).map((entry: EnvironmentEntry) => entry.label);
  }

  private environmentIdForLabel(label: string): string {
    return this.environmentEntries.find((entry: EnvironmentEntry) => entry.label === label)?.environmentId || '';
  }

  private insertCommand(value: string): void {
    if (value === 'model') { this.openTaskSettings(); return; }
    if (value === 'skill') { this.commandPanel = 'skill'; this.commandQuery = ''; return; }
    this.prompt = (this.prompt.length ? this.prompt + '\n' : '') + '/' + value + ' ';
    this.panelOpen = false; this.scheduleDraftSave();
  }

  private openThreadExtras(): void {
    this.refreshExtras();
    this.openPanel('extras');
  }

  private async copyGuestLink(): Promise<void> {
    try {
      const url = await client.createGuestShare();
      await this.copy(url);
      this.status = '访客链接已复制';
    } catch (error) { this.status = (error as Error).message; }
  }

  private async runFork(sideChat: boolean): Promise<void> {
    if (!client.thread || this.busy) return;
    const latestRun = client.thread.runs.length ? client.thread.runs[client.thread.runs.length - 1] : undefined;
    const runId = latestRun && typeof latestRun.id === 'string' ? latestRun.id : '';
    this.busy = true;
    try {
      const id = await client.forkThread(runId, sideChat);
      this.panelOpen = false;
      await this.watch(id);
    } catch (error) { this.status = (error as Error).message; }
    finally { this.busy = false; }
  }

  private currentChatTitle(): string {
    const matched = this.threads.find((t: ThreadView) => t.id === this.threadId);
    if (matched?.label) return matched.label.trim();
    if (this.cachedChatTitle) return this.cachedChatTitle.trim();
    if (client.thread && typeof client.thread.details.title === 'string') {
      return client.thread.details.title.trim();
    }
    return '';
  }

  private async forkFromMessage(messageId: string, runId: string, sourceThreadId: string): Promise<void> {
    if (!client.thread || this.busy || this.unknown || this.forkingMessageId !== '' || !runId) return;
    if (!this.ready || client.canScope('orchestration:operate') === false) return;
    const owner = client;
    const localId = this.selectedLocalId;
    const originThreadId = this.threadId;
    const sourceTitle = this.currentChatTitle();
    const forkTitle = sourceTitle ? sourceTitle + ' fork' : '';
    this.busy = true;
    this.forkingMessageId = messageId;
    try {
      const id = await owner.forkThread(runId, false, sourceThreadId, forkTitle);
      if (!this.alive || client !== owner || this.selectedLocalId !== localId || this.threadId !== originThreadId) {
        return;
      }
      this.panelOpen = false;
      await this.watch(id);
    } catch (error) {
      if (this.alive && client === owner && this.selectedLocalId === localId) {
        this.status = (error as Error).message;
      }
    } finally {
      if (this.forkingMessageId === messageId) this.forkingMessageId = '';
      this.busy = false;
    }
  }

  private refreshExtras(): void {
    if (!client.thread) { this.extraPlans = []; this.extraSubagents = []; this.extraBackground = [];
      this.extraGuest = undefined; this.extraUsage = undefined; return; }
    this.extraPlans = proposedPlans(client.thread.plans);
    this.extraSubagents = client.threadSubagents();
    this.extraBackground = client.threadBackgroundTasks();
    this.extraGuest = client.threadGuestShare();
    this.extraUsage = client.currentUsage();
  }

  private syncDelayedConnectionUi(): void {
    if (this.selectedLocalId !== this.connUiKey) {
      this.connUiKey = this.selectedLocalId;
      this.connUiState = initialDelayedConnectionUiState();
    }
    const result = stepDelayedConnectionUi(this.connUiState, {
      ready: this.ready,
      connecting: client.reconnectPending,
      offline: client.networkOffline,
      error: client.lastConnectionError,
      nowMs: Date.now()
    });
    this.connUiState = result.state;
    this.suppressReconnectUi = result.suppressConnecting;
    this.showDelayedConnError = result.showError;
    this.clientOffline = client.networkOffline;
    if (this.connUiTimer) {
      clearTimeout(this.connUiTimer);
      this.connUiTimer = 0;
    }
    if (result.nextTickMs > 0 && this.alive) {
      this.connUiTimer = setTimeout(() => {
        this.connUiTimer = 0;
        if (!this.alive) return;
        this.syncDelayedConnectionUi();
        this.refreshFloatingCapsule();
      }, Math.max(50, result.nextTickMs)) as number;
    }
  }

  private refreshFloatingCapsule(): void {
    if (this.draftMode || !this.threadId) {
      this.turnSubagents = [];
      this.pendingBackgroundItems = [];
      this.floatingCapsule = emptyFloatingCapsule();
      this.liveThinking = emptyLiveThinkingRow();
      return;
    }
    const thread = client.thread && client.thread.threadId === this.threadId ? client.thread : undefined;
    const synced = !!thread && thread.cursor >= 0;
    const shellThread = this.threads.find((row: ThreadView) => row.id === this.threadId);
    const entry = this.environmentEntries.find((candidate: EnvironmentEntry) => candidate.localId === this.selectedLocalId);
    const threadKey = this.selectedLocalId + ':' + this.threadId;
    const turn = thread ? client.threadTurnSubagents() : undefined;
    const bgTasks = thread ? client.threadPendingBackgroundTasks() : [];
    this.turnSubagents = turn ? turn.subagents : [];
    this.pendingBackgroundItems = bgTasks;
    const stopPending = isBackgroundWorkStopPending(this.backgroundStopRequest, threadKey, bgTasks, this.nowMs);
    if (!stopPending && this.backgroundStopRequest && this.backgroundStopRequest.threadKey === threadKey &&
      this.backgroundStopRequest.retryAt > 0) {
      this.backgroundStopRequest = undefined;
    }
    const caps = this.threadCapabilities[this.selectedLocalId];
    const effectiveReady = this.ready || this.suppressReconnectUi;
    const connectionError = !effectiveReady && this.showDelayedConnError
      ? (client.lastConnectionError || (client.status && client.status !== '未连接' ? client.status : ''))
      : '';
    this.floatingCapsule = deriveFloatingCapsuleModel({
      draftMode: false,
      ready: effectiveReady,
      connecting: client.reconnectPending,
      offline: this.clientOffline,
      environmentLabel: entry?.label || client.environmentLabel || '',
      connectionError,
      unknown: this.unknown,
      pendingActionCount: this.actions.length,
      canOperateThread: this.ready && client.canScope('orchestration:operate') !== false,
      canForceStop: this.ready && client.supports('threadForceStop') && client.canScope('orchestration:operate') !== false,
      forceStopping: this.forceStoppingKey === threadKey,
      backgroundStopPending: stopPending,
      nowMs: this.nowMs,
      threadSynced: synced,
      runs: thread ? thread.runs : [],
      turnItems: thread ? thread.items : [],
      messages: this.messages,
      subagents: thread ? thread.subagents : [],
      providerThreads: thread ? thread.providerThreads : [],
      nodes: thread ? thread.nodes : [],
      details: thread ? thread.details : {},
      shellThread,
      allThreads: this.threads,
      selectedLocalId: this.selectedLocalId,
      queuedCount: this.queued.length,
      hasWorktreeSetupCard: this.worktreeSetup !== undefined,
      supportsSnooze: caps === undefined || caps.snooze,
      supportsSettlement: caps === undefined || caps.settlement
    });
    const pendingLocalLinks = this.linkItems.filter((item: LinkRequestView) =>
      item.status === 'pending' && item.visibility === 'local').length;
    const rawConfigProviders = client.config ? client.config.providers : undefined;
    const configProviders = Array.isArray(rawConfigProviders) ? rawConfigProviders as Object[] : undefined;
    this.liveThinking = deriveLiveThinkingRow({
      draftMode: false,
      threadSynced: synced,
      runs: thread ? thread.runs : [],
      items: thread ? thread.items : [],
      messages: this.messages,
      providerTurns: thread ? thread.providerTurns : [],
      providerSessions: thread ? thread.providerSessions : [],
      nodes: thread ? thread.nodes : [],
      details: thread ? thread.details : {},
      tailGroup: this.workMap.tail,
      pendingActionCount: this.actions.length + pendingLocalLinks,
      hasPendingBackgroundWork: bgTasks.length > 0,
      hasWorktreeSetupCard: this.worktreeSetup !== undefined,
      isCompacting: this.floatingCapsule.status?.kind === 'compacting',
      isStopping: this.floatingCapsule.status?.kind === 'stop',
      fallbackProviderDriver: this.activeModelDriver,
      configProviders
    });
  }

  private openCapsuleStatus(): void {
    const status = this.floatingCapsule.status;
    if (!status) return;
    if (status.kind === 'connection') {
      const entry = this.environmentEntries.find((candidate: EnvironmentEntry) => candidate.localId === this.selectedLocalId);
      if (entry && entry.enabled && !client.connectionPending) {
        void this.registry().reconnect(entry.localId).catch((error: Error) => {
          this.status = error.message;
          this.openPanel('server');
        });
      } else {
        this.openPanel('server');
      }
      return;
    }
    if (status.kind === 'action-needed') {
      this.scroller.scrollEdge(Edge.Bottom);
      this.chatAwayFromBottom = false;
      return;
    }
    if (status.kind === 'child-input' && status.targetThreadId) {
      void this.watch(status.targetThreadId);
      return;
    }
    if (status.kind === 'background') {
      this.refreshFloatingCapsule();
      this.openPanel('background-work');
    }
  }

  private triggerCapsuleAction(): void {
    const status = this.floatingCapsule.status;
    if (!status || status.actionDisabled || !status.actionKind) return;
    if (status.actionKind === 'stop-background') {
      this.stopBackgroundWork();
      return;
    }
    if (status.actionKind === 'force-stop') {
      const runId = status.targetRunId;
      const threadKey = this.selectedLocalId + ':' + this.threadId;
      AlertDialog.show({
        title: '强制停止任务？',
        message: '任务未响应停止请求。强制停止会立即终止当前运行并结束相关进程（若其他会话未共用）。',
        primaryButton: { value: '取消', action: () => {} },
        secondaryButton: {
          value: '强制停止',
          fontColor: $r('app.color.danger'),
          action: () => {
            this.forceStoppingKey = threadKey;
            this.refreshFloatingCapsule();
            void client.forceStop(runId)
              .catch((error: Error) => { this.status = error.message; })
              .finally(() => {
                if (this.forceStoppingKey === threadKey) {
                  this.forceStoppingKey = '';
                  this.refreshFloatingCapsule();
                }
              });
          }
        }
      });
      return;
    }
    const scoped = this.scopedThreads.find((row: ScopedThread) =>
      row.localId === this.selectedLocalId && row.id === this.threadId);
    if (!scoped) return;
    if (status.actionKind === 'wake') {
      const details = client.thread?.details;
      const recovery = details && details.limitRecovery !== undefined && details.limitRecovery !== null
        ? record(details.limitRecovery) : undefined;
      const recoveryOwns = !!recovery && recovery.snooze === true &&
        typeof details?.latestRunId === 'string' && recovery.runId === details.latestRunId &&
        typeof details?.usageLimitResetAt === 'string' && recovery.resetAt === details.usageLimitResetAt &&
        Date.parse(scoped.snoozedUntil) === Date.parse(String(recovery.resetAt));
      this.busy = true;
      const work = recoveryOwns
        ? client.setLimitRecovery(undefined, false)
        : this.workspace().unsnooze(scoped);
      void work.catch((error: Error) => { this.status = error.message; })
        .finally(() => { this.busy = false; this.rebuildWorkspace(); this.refreshFloatingCapsule(); });
      return;
    }
    if (status.actionKind === 'unsettle') {
      this.busy = true;
      void this.workspace().unsettle(scoped)
        .catch((error: Error) => { this.status = error.message; })
        .finally(() => { this.busy = false; this.rebuildWorkspace(); this.refreshFloatingCapsule(); });
      return;
    }
    if (status.actionKind === 'dismiss-woke') {
      this.busy = true;
      void this.workspace().visit(scoped, false, '')
        .catch((error: Error) => { this.status = error.message; })
        .finally(() => { this.busy = false; this.rebuildWorkspace(); this.refreshFloatingCapsule(); });
    }
  }

  private stopBackgroundWork(): void {
    if (!this.threadId || !client.thread) return;
    const threadKey = this.selectedLocalId + ':' + this.threadId;
    const taskIds = this.pendingBackgroundItems.map((task: PendingBackgroundTaskView) => task.taskId);
    if (this.backgroundStopTimer) {
      clearTimeout(this.backgroundStopTimer);
      this.backgroundStopTimer = 0;
    }
    const req: BackgroundStopRequest = { threadKey, taskIds, retryAt: 0 };
    this.backgroundStopRequest = req;
    this.nowMs = Date.now();
    this.refreshFloatingCapsule();
    void client.stop().then(() => {
      if (!this.alive || this.backgroundStopRequest !== req) return;
      const withRetry: BackgroundStopRequest = {
        threadKey: req.threadKey,
        taskIds: req.taskIds,
        retryAt: Date.now() + BACKGROUND_WORK_STOP_RETRY_AFTER_MS
      };
      this.backgroundStopRequest = withRetry;
      this.nowMs = Date.now();
      this.refreshFloatingCapsule();
      this.backgroundStopTimer = setTimeout(() => {
        this.backgroundStopTimer = 0;
        if (!this.alive) return;
        if (this.backgroundStopRequest === withRetry) {
          this.backgroundStopRequest = undefined;
          this.nowMs = Date.now();
          this.refreshFloatingCapsule();
        }
      }, BACKGROUND_WORK_STOP_RETRY_AFTER_MS + 50) as number;
    }).catch((error: Error) => {
      if (this.backgroundStopRequest === req) {
        this.backgroundStopRequest = undefined;
      }
      this.status = error.message;
      this.nowMs = Date.now();
      this.refreshFloatingCapsule();
    });
  }

  private threadAttachments(): DraftAttachment[] {
    if (!client.thread) return [];
    const rows: DraftAttachment[] = [];
    const add = (value: Object): void => {
      try {
        const item = record(value);
        const attachment: DraftAttachment = { type: text(item.type || 'file'), id: text(item.id),
          name: text(item.name), mimeType: text(item.mimeType), sizeBytes: Number(item.sizeBytes) };
        if (attachment.id && attachment.name && attachment.sizeBytes > 0 &&
          !rows.some((row: DraftAttachment) => row.id === attachment.id)) rows.push(attachment);
      } catch (_) {}
    };
    for (const message of client.thread.messageRecords) {
      if (message.attachments !== undefined) for (const item of message.attachments as Object[]) add(item);
    }
    for (const item of client.thread.items) {
      if (item.attachments !== undefined) {
        try { for (const value of item.attachments as Object[]) add(value); } catch (_) {}
      }
    }
    return rows;
  }

  private findAttachment(name: string): DraftAttachment | undefined {
    return this.attachments.find((item: DraftAttachment) => item.name === name) ||
      this.threadAttachments().find((item: DraftAttachment) => item.name === name);
  }

  private async openAttachment(name: string): Promise<void> {
    const item = this.findAttachment(name);
    if (!item) { this.status = '附件已不在当前快照中'; return; }
    this.selectedAttachment = item; this.attachmentPreviewUrl = ''; this.attachmentStatus = '';
    this.openPanel('attachment');
    try {
      this.attachmentPreviewUrl = await client.attachmentUrl(item.id, item.name, item.mimeType, true);
    } catch (error) { this.attachmentStatus = (error as Error).message; }
  }

  private async saveAttachment(): Promise<void> {
    const item = this.selectedAttachment;
    if (!item) return;
    this.busy = true; this.attachmentStatus = '正在下载…';
    try {
      const bytes = await client.downloadAttachment(item.id, item.name, item.mimeType);
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [item.name];
      const target = await new picker.DocumentViewPicker().save(options);
      if (!target.length) { this.attachmentStatus = '已取消保存'; return; }
      const file = fileIo.openSync(target[0], fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try { fileIo.writeSync(file.fd, bytes); fileIo.fsyncSync(file.fd); } finally { fileIo.closeSync(file); }
      this.attachmentStatus = '已保存到所选位置';
    } catch (error) { this.attachmentStatus = (error as Error).message; }
    finally { this.busy = false; }
  }

  private async shareAttachment(): Promise<void> {
    const item = this.selectedAttachment;
    if (!item || this.busy) return;
    const owner = client; const scope = this.selectedLocalId; const threadId = this.threadId;
    this.busy = true; this.attachmentStatus = '正在准备分享…';
    try {
      const bytes = await owner.downloadAttachment(item.id, item.name, item.mimeType);
      if (owner !== client || scope !== this.selectedLocalId || threadId !== this.threadId) throw new Error('分享目标已变化');
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const safeName = item.name.replace(/[\\/:*?"<>|\x00-\x1f]/g, '_').slice(-180) || 'attachment';
      const path = context.cacheDir + '/share-' + Date.now() + '-' + safeName;
      const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try { fileIo.writeSync(file.fd, bytes); fileIo.fsyncSync(file.fd); } finally { fileIo.closeSync(file); }
      registerSharedFile(context.cacheDir, path.substring(context.cacheDir.length + 1), scope);
      const shared = new systemShare.SharedData({ utd: 'general.file',
        uri: fileUri.getUriFromPath(path), title: item.name });
      await new systemShare.ShareController(shared).show(context, {});
      this.attachmentStatus = '已打开系统分享';
    } catch (error) { this.attachmentStatus = '分享失败：' + (error as Error).message; }
    finally { this.busy = false; }
  }

  private async shareMessage(value: string): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const data = new systemShare.SharedData({ utd: 'general.plain-text', content: value });
      await new systemShare.ShareController(data).show(context, {});
    } catch (_) { this.status = '无法打开系统分享，请重试'; }
  }
  private openTaskSettings(): void {
    if (!this.draftMode && client.thread) {
      const details = client.thread.details;
      if (details.modelSelection) this.taskSettings = { modelSelection: record(details.modelSelection) as Object as ModelSelection,
        runtimeMode: typeof details.runtimeMode === 'string' ? details.runtimeMode : 'approval-required',
        interactionMode: typeof details.interactionMode === 'string' ? details.interactionMode : 'default' };
    }
    this.openPanel('task-settings');
  }

  private async saveTaskSettings(settings: TaskSettings): Promise<void> {
    if (this.busy || this.unknown) return;
    const owner = client; this.busy = true;
    let applied = this.taskSettings;
    let failure = '';
    try {
      validateTaskSettings(owner.config, this.projectId, settings);
      if (!this.draftMode) {
        if (JSON.stringify(applied.modelSelection) !== JSON.stringify(settings.modelSelection)) {
          await owner.configureThread(settings);
          applied = { modelSelection: settings.modelSelection, runtimeMode: applied.runtimeMode,
            interactionMode: applied.interactionMode };
        }
        if (applied.runtimeMode !== settings.runtimeMode) {
          await owner.changeThreadMode(settings.runtimeMode, false);
          applied = { modelSelection: applied.modelSelection, runtimeMode: settings.runtimeMode,
            interactionMode: applied.interactionMode };
        }
        if (applied.interactionMode !== settings.interactionMode) {
          await owner.changeThreadMode(settings.interactionMode, true);
          applied = { modelSelection: applied.modelSelection, runtimeMode: applied.runtimeMode,
            interactionMode: settings.interactionMode };
        }
      }
      if (this.draftMode) applied = settings;
    } catch (error) { failure = (error as Error).message; }
    if (owner === client) {
      const partial = JSON.stringify(applied) !== JSON.stringify(this.taskSettings);
      if (this.draftMode && !failure && JSON.stringify(applied.modelSelection) !== JSON.stringify(this.taskSettings.modelSelection)) {
        this.draftModelCustomized = true;
      }
      this.taskSettings = applied;
      this.activeModelInstanceId = applied.modelSelection.instanceId;
      this.activeModelDriver = '';
      this.activeModelSlug = applied.modelSelection.model;
      this.activeModelLabel = '';
      this.activeModelSummary = '';
      if (this.draftMode) this.scheduleDraftSave();
      if (failure) this.status = (partial ? '部分设置已生效：' : '设置保存失败：') + failure;
      else { this.status = '设置已保存'; this.panelOpen = false; }
    }
    this.busy = false;
  }

  private async installProvider(instanceId: string): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    try {
      const state = await client.installProvider(instanceId);
      this.status = 'Provider 安装：' + String(state.phase || '已开始');
      await client.refreshProviders(instanceId);
    } catch (error) { this.status = (error as Error).message; }
    finally { this.busy = false; }
  }
  private async startProviderAuth(instanceId: string): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    try {
      const state = await client.startProviderAuth(instanceId);
      const url = typeof state.authorizationUrl === 'string' ? state.authorizationUrl : '';
      this.status = String(state.message || state.phase || 'Provider 登录已开始');
      if (url) {
        const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
        await context.openLink(url);
      }
    } catch (error) { this.status = (error as Error).message; }
    finally { this.busy = false; }
  }
  private async refreshProvider(instanceId: string): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    try { await client.refreshProviders(instanceId); this.status = 'Provider 状态已刷新'; }
    catch (error) { this.status = (error as Error).message; }
    finally { this.busy = false; }
  }

  private async queueAction(action: string, id: string, before: string | null, prompt: string): Promise<void> {
    if (this.busy || this.unknown) return;
    const owner = client; this.busy = true;
    try {
      if (action === 'promote') await owner.promoteQueued(id);
      else await owner.queue(action, id, before, prompt);
      if (owner === client) this.status = '队列操作已确认';
    }
    catch (error) { this.status = (error as Error).message; }
    finally { this.busy = false; }
  }

  private async watch(id: string): Promise<void> {
    const previousKey = this.draftKey();
    if (this.draftMode) await this.persistDraft();
    else {
      this.textDrafts.set(previousKey, this.prompt);
      this.contextDrafts.set(previousKey, this.draftContext.slice());
    }
    this.draftMode = false; client.draftScope = '';
    this.canRetryAttachment = this.picker.canRetry();
    const targetKey = this.selectedLocalId + ':' + id;
    if (targetKey !== this.renderedThreadKey) {
      this.messages = [];
      this.source.update([]);
      this.workMap = emptyWorkMap();
      this.messageFooterMap = {};
      this.forkingMessageId = '';
      this.renderedThreadKey = '';
      this.hasMoreHistory = false;
      this.cachedChatTitle = '';
      this.cachedChatProject = '';
      const matched = this.scopedThreads.find((item: ScopedThread) => item.localId === this.selectedLocalId && item.id === id);
      this.activeModelInstanceId = matched?.providerInstanceId || '';
      this.activeModelDriver = '';
      this.activeModelSlug = matched?.model || '';
      this.activeModelLabel = '';
      this.activeModelSummary = '';
      this.turnSubagents = [];
      this.pendingBackgroundItems = [];
      this.floatingCapsule = emptyFloatingCapsule();
      this.liveThinking = emptyLiveThinkingRow();
    }
    this.chatAwayFromBottom = false;
    this.threadRunning = false;
    this.pendingScrollBottomKey = targetKey;
    this.lastAutoWatchKey = this.selectedLocalId + ':' + client.generationValue() + ':' + id;
    this.threadId = id;
    this.prompt = this.textDrafts.get(this.draftKey()) || '';
    this.draftContext = (this.contextDrafts.get(this.draftKey()) || []).slice();
    this.page = 'chat'; this.showTools = false; this.panelOpen = false;
    this.refreshFloatingCapsule();
    this.busy = true;
    try {
      await client.watch(id);
      this.resolveActiveModel(client);
      this.expandedWorkGroups = {};
      this.expandedUserMessages = {};
      this.lastWorkThreadKey = this.selectedLocalId + ':' + id;
      this.canOpenDiff = !this.draftMode && !!this.currentWorkspace();
      this.threadTerminalEnabled = this.ready && !this.draftMode && !!this.currentWorkspace() && client.canScope('terminal:read') !== false;
      const thread = this.scopedThreads.find((item: ScopedThread) => item.localId === this.selectedLocalId && item.id === id);
      if (thread) {
        if (thread.label) this.cachedChatTitle = thread.label;
        const proj = this.scopedProjects.find((p: ScopedProject) => p.localId === this.selectedLocalId && p.id === thread.projectId);
        if (proj?.label) this.cachedChatProject = proj.label;
        if (!thread.archivedAt) this.rememberProject(thread.projectId);
      }
    }
    catch (error) { this.status = (error as Error).message; }
    finally { this.busy = false; this.incomingPairing(); }
  }

  private async send(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    const submitted = this.prompt;
    const submittedContext = Array.isArray(this.draftContext) ? this.draftContext.slice() : [];
    const owner = client;
    const key = this.draftKey();
    const draftId = this.activeDraftId;
    const localId = this.selectedLocalId;
    try {
      if (this.draftMode) {
        await this.persistDraft();
        const id = await owner.launch(this.projectId, submitted, this.taskSettings, this.draftWorkspace, submittedContext);
        if (owner !== client || localId !== this.selectedLocalId) return;
        this.draftMode = false; this.threadId = id; this.activeDraftId = '';
        this.pendingScrollBottomKey = localId + ':' + id;
        if (this.prompt === submitted) this.prompt = '';
        else this.textDrafts.set(this.draftKey(), this.prompt);
        this.draftContext = []; this.attachments = [];
        this.contextDrafts.delete(key);
        try { await this.deleteDraft(draftId); }
        catch (error) { this.status = '会话已创建，但草稿清理失败：' + (error as Error).message; }
        await owner.watch(id);
      } else {
        const running = !!owner.thread?.runs.some((run: Record<string, Object>) => ['preparing', 'starting', 'running', 'waiting'].includes(String(run.status)));
        await owner.send(submitted, followUpDelivery(this.sendMode || 'auto', running, workspacePrefs.followUpBehavior), submittedContext);
        if (owner === client) {
          this.pendingScrollBottomKey = localId + ':' + this.threadId;
          if (this.prompt === submitted) {
            this.prompt = ''; this.textDrafts.delete(key); this.draftContext = [];
            this.contextDrafts.delete(key);
          }
        }
      }
    } catch (error) {
      if (owner !== client || localId !== this.selectedLocalId) return;
      this.status = (error as Error).message;
      if (owner.recovery?.pendingId && this.draftMode) {
        this.textDrafts.set(localId + '\nT:' + owner.recovery.threadId, submitted);
        this.contextDrafts.set(localId + '\nT:' + owner.recovery.threadId, submittedContext.slice());
        await this.deleteDraft(draftId);
        this.draftMode = false; this.activeDraftId = ''; owner.draftScope = ''; this.threadId = owner.recovery.threadId;
        this.status = '任务提交结果未知，请同步原会话核对，不会再次创建';
      }
    }
    finally { this.busy = false; this.incomingPairing(); }
  }

  private async stop(): Promise<void> {
    this.busy = true;
    try { await client.stop(); this.status = '停止请求已确认'; }
    catch (error) { this.status = (error as Error).message; }
    finally { this.busy = false; this.incomingPairing(); }
  }

  private async forget(localId: string): Promise<void> {
    await this.registry().remove(localId);
    this.pickers.get(localId)?.clear(); this.pickers.delete(localId);
    if (localId === this.selectedLocalId) this.canRetryAttachment = false;
    const prefix = localId + '\n';
    this.textDrafts.forEach((value: string, key: string) => { if (key.startsWith(prefix)) this.textDrafts.delete(key); });
    this.settingsDrafts.forEach((value: TaskSettings, key: string) => { if (key.startsWith(prefix)) this.settingsDrafts.delete(key); });
    this.contextDrafts.forEach((value: ComposerContextRecord[], key: string) => { if (key.startsWith(prefix)) this.contextDrafts.delete(key); });
    const kept = this.draftRecords.filter((item: ComposerDraft) => item.localId !== localId);
    this.draftRecords = kept;
    if (draftStore) await draftStore.save(kept);
  }

  private async attach(mode: 'file' | 'photo' | 'retry'): Promise<void> {
    if (!this.ready || this.busy || this.unknown) return;
    this.busy = true;
    this.uploadingAttachment = true;
    this.attachmentUploadCancelled = false;
    try {
      const uploaded = mode === 'retry' ? await this.picker.retry() :
        mode === 'photo' ? await this.picker.choosePhotos() : await this.picker.choose();
      this.refreshAttachments();
      if (uploaded) {
        this.scheduleDraftSave();
        this.status = '附件已上传，发送指令时附带';
      }
    } catch (error) {
      this.refreshAttachments();
      if (this.attachmentUploadCancelled) this.status = '附件上传已取消';
      else this.status = (error as Error).message || '附件选择失败，请重试';
    }
    finally {
      this.uploadingAttachment = false;
      this.busy = false;
      this.canRetryAttachment = this.picker.canRetry();
      this.incomingPairing();
    }
  }

  private cancelAttachmentUpload(): void {
    this.attachmentUploadCancelled = true;
    this.picker.cancel();
    this.canRetryAttachment = false;
    this.status = '附件上传已取消';
  }

  private clearAttachments(): void {
    if (this.busy || this.unknown) return;
    client.attachments = [];
    client.attachment = undefined;
    this.picker.clear();
    this.refreshAttachments();
    this.scheduleDraftSave();
  }

  private composerSendModeMenu(): MenuElement[] {
    return [
      { value: this.sendMode === 'auto' ? '✓ 自动发送' : '自动发送', action: () => { this.sendMode = 'auto'; } },
      { value: this.sendMode === 'queue' ? '✓ 排队发送' : '排队发送', action: () => { this.sendMode = 'queue'; } },
      { value: this.sendMode === 'steer' ? '✓ 引导运行' : '引导运行', action: () => { this.sendMode = 'steer'; } }
    ];
  }

  private composerAttachmentMenu(uploading: boolean, canRetry: boolean, hasAttachments: boolean,
    draftMode: boolean = false, sendMode: string = 'auto', queuedCount: number = 0,
    threadRunning: boolean = false): MenuElement[] {
    if (uploading) {
      return [
        { value: '取消上传', action: () => { this.cancelAttachmentUpload(); } },
        { value: '粘贴结构化上下文', action: () => { this.openPanel('paste-context'); } }
      ];
    }
    const items: MenuElement[] = [
      { value: '从图库选择', action: () => { void this.attach('photo'); } },
      { value: '选择文件', action: () => { void this.attach('file'); } }
    ];
    if (canRetry) {
      items.push({ value: '重试上传', action: () => { void this.attach('retry'); } });
    }
    items.push({ value: '引用文件 @', action: () => { this.openComposerCommand('mention'); } });
    items.push({ value: '命令 /', action: () => { this.openComposerCommand('commands'); } });
    items.push({ value: '技能', action: () => { this.openComposerCommand('skill'); } });
    items.push({ value: '语音输入', action: () => { this.voiceTarget = this.draftKey(); this.page = 'voice'; } });
    items.push({ value: '粘贴结构化上下文', action: () => { this.openPanel('paste-context'); } });
    if (!draftMode) {
      items.push({ value: queuedCount > 0 ? '队列 (' + queuedCount + ')' : '队列', action: () => { this.openPanel('queue'); } });
      if (sendMode !== 'auto') {
        items.push({ value: '恢复自动发送', action: () => { this.sendMode = 'auto'; } });
      } else if (threadRunning) {
        items.push({ value: '排队发送', action: () => { this.sendMode = 'queue'; } });
        items.push({ value: '引导运行', action: () => { this.sendMode = 'steer'; } });
      }
    }
    if (hasAttachments) {
      items.push({ value: '清空附件', action: () => { this.clearAttachments(); } });
    }
    return items;
  }

  private async acknowledge(): Promise<void> {
    try { await client.acknowledgeUnknown(); }
    catch (error) { this.status = (error as Error).message; }
  }

  private async copy(value: string): Promise<boolean> {
    try {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, value));
      return true;
    } catch (_) {
      this.status = '复制失败';
      return false;
    }
  }
  private async openLink(url: string): Promise<void> {
    if (!/^(https?:\/\/|mailto:)/i.test(url)) { this.status = '已阻止非 HTTP(S)/mailto 链接'; return; }
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await context.startAbility({ action: 'ohos.want.action.viewData', uri: url });
    } catch (error) { this.status = '无法打开链接：' + (error as Error).message; }
  }
  private markdownMediaScopeKey(): string {
    return this.selectedLocalId + ':' + this.threadId + ':' + client.generationValue() + ':' + (this.ready ? '1' : '0');
  }
  private resolveMarkdownMedia(source: string, refresh: boolean): Promise<ResolvedMarkdownMedia> {
    return client.markdownMediaUrl(source, this.currentWorkspace(), refresh);
  }
  private async openMarkdownImage(value: string): Promise<void> {
    const cwd = this.currentWorkspace();
    const classified = classifyMarkdownMediaSource(value, cwd);
    if (classified.access === 'direct') {
      this.markdownImageUrl = classified.uri;
      this.markdownImageKind = classified.kind;
      this.markdownImagePath = '';
      this.openPanel('markdown-image');
      return;
    }
    if (classified.access === 'blocked') {
      this.status = '不支持打开此媒体路径';
      return;
    }
    try {
      const resolved = await client.markdownMediaUrl(value, cwd, true);
      this.markdownImageUrl = resolved.url;
      this.markdownImageKind = resolved.kind;
      this.markdownImagePath = resolved.displayPath;
      this.openPanel('markdown-image');
    } catch (error) { this.status = (error as Error).message; }
  }
  private addExternalContext(value: Object, label: string): void {
    try {
      const item = contextRecord(value);
      if (!this.draftContext.some((current: ComposerContextRecord) => current.contextId === item.contextId)) {
        this.draftContext = this.draftContext.concat([item]);
      }
      this.status = '已加入上下文：' + label;
    } catch (error) { this.status = (error as Error).message; }
  }
  private currentWorkspace(): string {
    return this.draftMode ? this.draftCwd() : client.threadCwd();
  }
  private async openPreview(): Promise<void> {
    if (this.busy || this.draftMode || !this.ready) return;
    this.busy = true;
    this.previewConnection = client; this.previewThreadId = this.threadId;
    this.previewGeneration = client.generationValue(); this.previewKey = this.selectedLocalId + ':' + this.threadId;
    try {
      const result = record(await client.rpcRequest('preview.list', { threadId: this.previewThreadId } as PreviewRefPayload, 15000, false));
      if (!this.previewCurrent()) throw new Error('预览环境已变化');
      const existing = previewTabs(result, this.previewThreadId);
      const known = this.previewTabs.get(this.previewKey);
      const selected = existing.find((item: PreviewTab): boolean => item.tabId === known) || existing[0];
      this.previewTabs.set(this.previewKey, selected ? selected.tabId : '');
      this.previewAddress = selected ? selected.url : '';
      this.panelOpen = false; this.page = 'preview';
    } catch (error) { this.status = (error as Error).message; }
    finally { this.busy = false; }
  }
  private async openDevice(device: DevicePreviewChoice, hubPath: string, hostKind: string): Promise<void> {
    if (this.busy || !this.previewCurrent() || !['ios', 'android'].includes(device.platform) || device.physical ||
      (hostKind !== 'local' && hostKind !== 'ssh')) return;
    this.busy = true;
    try {
      const path = safeDeviceHubBase(hubPath);
      const opened = record(await client.rpcRequest('device.open', { threadId: this.previewThreadId, hostId: device.hostId,
        deviceId: device.id, platform: device.platform, boot: true } as DeviceOpenPayload, 60000, false));
      if (opened.threadId !== this.previewThreadId || opened.hostId !== device.hostId || opened.platform !== device.platform) throw new Error('设备打开结果身份不匹配');
      const openedId = text(opened.deviceId);
      if (!openedId || openedId.length > 256) throw new Error('设备打开结果标识无效');
      device.id = openedId;
      if (!this.previewCurrent()) throw new Error('设备环境已变化');
      this.deviceChoice = device; this.deviceHubPath = path; this.page = device.platform === 'android' ? 'android-device' : 'device-preview';
    } catch (error) { this.status = (error as Error).message; throw error as Error; }
    finally { this.busy = false; }
  }
  private rebindPreviewConnection(): void {
    if (!this.previewConnection || this.previewConnection !== client || this.previewThreadId !== this.threadId || !client.ready) {
      throw new Error('请先恢复原环境连接，或返回会话重新打开预览');
    }
    this.previewGeneration = client.generationValue();
  }
  private previewCurrent(): boolean {
    return !!this.previewConnection && this.previewConnection === client &&
      this.previewThreadId === this.threadId && this.previewGeneration === client.generationValue();
  }
  private async createPreviewTab(address: string): Promise<string> {
    if (!this.previewCurrent() || client.canScope('preview:operate') === false) throw new Error('预览环境或权限已变化');
    const result = record(await client.rpcRequest('preview.open', { threadId: this.previewThreadId,
      url: address, runtime: 'server', viewport: { _tag: 'freeform', width: 390, height: 740 } } as PreviewOpenPayload, 30000, false));
    if (!this.previewCurrent() || result.threadId !== this.previewThreadId) throw new Error('预览结果所属会话不匹配');
    return text(result.tabId);
  }
  private previewZoomRepairRequired(): boolean {
    return this.previewCurrent() && !!this.previewConnection?.ready &&
      previewNeedsZoomRepair(record(this.previewConnection.config.environment).serverVersion);
  }
  private async adjustPreviewZoom(tabId: string, zoomFactor: number, viewport?: PreviewViewport,
    stillControlled?: () => boolean): Promise<PreviewZoomResult> {
    const owner = this.previewConnection;
    const threadId = this.previewThreadId;
    const key = this.previewKey;
    const generation = this.previewGeneration;
    const current = (): boolean => !!owner && this.page === 'preview' && this.appForeground && this.previewCurrent() &&
      owner === this.previewConnection && owner.ready && owner.generationValue() === generation &&
      owner.supports('serverBrowser') && owner.canScope('preview:operate') === true &&
      this.previewThreadId === threadId && this.previewKey === key && this.previewTabs.get(key) === tabId;
    if (!owner || !current()) throw new Error('预览环境、页面或权限已变化');
    const input = previewZoomInput(threadId, tabId, zoomFactor);
    const listed = await owner.rpcRequest('preview.list', { threadId } as PreviewRefPayload, 15000, false);
    if (!current()) throw new Error('预览环境、页面或权限已变化');
    const tab = previewTabs(listed, threadId).find((item: PreviewTab) => item.tabId === tabId);
    if (!tab) throw new Error('远端预览页面已关闭');
    if (zoomFactor === 1 && this.previewZoomRepairRequired()) {
      if (!stillControlled) throw new Error('此服务恢复 100% 需要显式确认');
      const canRepair = (): boolean => current() && this.previewZoomRepairRequired() && stillControlled();
      return repairPreviewZoom100(threadId, tab,
        (method: string, payload: Object): Promise<Object> => owner.rpcRequest(method, payload, 15000, false), canRepair);
    }
    const expected = previewZoomTarget(tab, zoomFactor, viewport);
    if (tab.zoomFactor === zoomFactor) return expected;
    const changed = await owner.rpcRequest('preview.adjust', input, 15000, false);
    if (!current()) throw new Error('预览环境、页面或权限已变化');
    return verifyPreviewZoom(changed, threadId, tab, expected);
  }

  private terminalOwner(): T3Client {
    if (!this.terminalConnection || this.terminalConnection !== client || this.terminalThreadId !== this.threadId) {
      throw new Error('终端所属环境或会话已变化，请重新打开终端');
    }
    return this.terminalConnection;
  }
  private openFiles(): void {
    if (!this.currentWorkspace()) { this.status = '当前会话没有工作目录'; return; }
    this.panelOpen = false; this.page = 'files';
  }
  private openReview(): void {
    if (!this.currentWorkspace()) { this.status = '当前会话没有工作目录'; return; }
    this.panelOpen = false; this.page = 'review';
  }
  private openGit(): void {
    if (!this.currentWorkspace()) { this.status = '当前会话没有工作目录'; return; }
    this.panelOpen = false; this.page = 'git';
  }
  private openPullRequests(): void {
    this.panelOpen = false; this.page = 'pull-requests';
  }
  private messageTime(value: string | undefined): string {
    return formatMessageTimestamp(value);
  }

  onBackPress(): boolean {
    this.keyboard.reset();
    if (this.savingShare) return true;
    if (this.choosingShare) { this.choosingShare = false; this.page = 'share'; return true; }
    if (this.page === 'share') { this.page = 'sessions'; return true; }
    if (this.page === 'voice') { this.page = 'chat'; return true; }
    if (this.page === 'settings' && this.settingsSection) {
      this.settingsSection = this.settingsSection === 'worktree-project' ? 'worktrees' : '';
      return true;
    }
    if (this.panelOpen && ['peer-link', 'task-settings', 'queue'].includes(this.panel) && this.busy) return true;
    if (this.panelOpen) {
      if (this.panel === 'cloud') { this.panel = this.cloudReturnPanel; return true; }
      if (this.panel === 'connection-new') { this.panel = 'server'; this.credential = ''; this.pairingError = false; }
      else {
        if (this.panel === 'snooze') this.snoozeThread = undefined;
        if (this.panel === 'rename') this.renameThread = undefined;
        this.panelOpen = false;
      }
      return true;
    }
    if (this.page === 'sessions' && this.searchOpen) {
      this.searchOpen = false;
      this.searchFocused = false;
      if (this.threadQuery) this.setThreadQuery('');
      return true;
    }
    if (this.page === 'home-pulls' || this.page === 'usage') {
      this.homeTabDetailOpen = false;
      this.page = 'sessions';
      return true;
    }
    if (this.page === 'chat') { this.page = 'sessions'; return true; }
    if (this.page === 'settings') { this.page = 'sessions'; return true; }
    if (this.page === 'choose-project') {
      const next = this.choosingShare ? 'share' : (this.projectPickerReturn === 'chat' && this.draftMode ? 'chat' : 'sessions');
      this.choosingShare = false; this.pendingDraftId = ''; this.projectPickerReturn = 'sessions';
      this.page = next;
      return true;
    }
    if (this.page === 'add-project') { this.page = this.addProjectReturn; return true; }
    if (this.page === 'project-overview' || this.page === 'archive') { this.page = 'settings'; return true; }
    if (this.page === 'android-device') { this.page = 'device-picker'; return true; }
    if (this.page === 'device-preview') { this.page = 'device-picker'; return true; }
    if (this.page === 'device-picker') { this.page = 'chat'; return true; }
    if (this.page === 'preview') { this.page = 'chat'; return true; }
    if (this.page === 'terminal') { this.page = 'chat'; return true; }
    if (this.page === 'files') { this.page = 'chat'; return true; }
    if (this.page === 'review') { this.page = 'chat'; return true; }
    if (this.page === 'git') { this.page = 'chat'; return true; }
    if (this.page === 'pull-requests') { this.page = 'chat'; return true; }
    return false;
  }

  private async refreshPeerPermission(): Promise<void> {
    const generation = ++this.linkPermissionGeneration; const source = client; this.peerCanAnswer = false;
    if (!source.ready || !this.linkItems.some((item: LinkRequestView) => item.status === 'pending' && item.visibility === 'local')) return;
    try {
      await source.refreshPeerAccess();
      if (source === client && generation === this.linkPermissionGeneration) this.peerCanAnswer = source.canManagePeerAccess();
    } catch (_) {}
  }
  private async openPeerLink(item: LinkRequestView): Promise<void> {
    this.activeLink = item; this.linkOwner = client; this.linkMachines = []; this.openPanel('peer-link');
    const source = this.linkOwner;
    let linkedIds: string[] = [];
    try { linkedIds = (await source.linkedEnvironments()).filter((link) => link.status !== 'expired' && link.expiresAt > Date.now()).map((link) => link.environmentId); }
    catch (_) {}
    if (this.linkOwner !== source || this.activeLink?.id !== item.id) return;
    this.linkMachines = this.registry().directory.entries.filter((entry: EnvironmentEntry) => !entry.deleting && entry.localId !== this.selectedLocalId).map((entry: EnvironmentEntry): LinkMachine => {
      const connection = this.registry().clients.get(entry.localId);
      return { localId: entry.localId, environmentId: entry.environmentId, label: entry.label, connected: !!connection?.ready,
        linked: linkedIds.includes(entry.environmentId), urls: linkReachableAddresses(environmentRoutes(entry).map((route: DirectRoute) => route.base).concat(connection?.directAddresses || [])) };
    });
  }
  private async declinePeerLink(item: LinkRequestView): Promise<void> {
    if (this.busy) return; const source = client; this.busy = true;
    try { await source.answerLinkRequest(item.id, { type: 'decline' }); }
    catch (_) { this.status = '无法答复链接请求，请同步原会话核对结果'; }
    finally { this.busy = false; this.peerCanAnswer = source === client && source.canManagePeerAccess(); this.incomingPairing(); }
  }
  private peerOutcome(item: LinkRequestView): string {
    if (item.status === 'pending') return '等待在原会话中答复';
    if (item.status === 'linked') return '已链接 ' + (item.linkedLabel || linkOrigin(item.url) || '环境') +
      (item.linkedAccess ? ' · ' + (linkAccessChoices.find((choice) => choice.value === item.linkedAccess)?.label || item.linkedAccess) : '');
    if (item.status === 'declined') return '已拒绝';
    if (item.status === 'failed') return '无法链接：' + (item.failure || '目标环境拒绝');
    return '请求已结束';
  }

  private async filterEnvironment(index: number): Promise<void> {
    const entries = this.environmentEntries.filter((e: EnvironmentEntry) => !e.deleting);
    this.environmentFilter = index === 0 ? '' : entries[index - 1].localId;
    this.projectFilterId = ''; this.projectFilterLocalId = '';
    this.projectFilterKey = ''; this.projectFilterRefs = []; this.projectFilterLabel = '所有项目';
    workspacePrefs.environmentFilter = this.environmentFilter;
    workspacePrefs.projectFilterKey = '';
    workspacePrefs.projectFilterGroupingMode = undefined;
    saveWorkspacePreferences();
    this.rebuildWorkspace();
  }
  private async openScopedThread(thread: ScopedThread): Promise<void> {
    try {
      await this.registry().select(thread.localId);
      this.projectId = thread.projectId;
      const owner = this.registry().clients.get(thread.localId);
      if (owner?.ready) {
        await this.workspace().visit(thread, true, this.threadQuery);
        await this.watch(thread.id);
      } else {
        this.draftMode = false;
        this.threadId = thread.id;
        this.cachedChatTitle = thread.label;
        this.cachedChatProject = thread.projectLabel;
        this.page = 'chat';
        if (owner && !owner.connectionPending) {
          void this.registry().reconnect(thread.localId).catch(() => {});
        }
      }
    } catch (error) { this.status = (error as Error).message; }
  }

  private environmentOptions(): SelectOption[] {
    const all: SelectOption = { value: '所有环境' };
    return [all].concat(this.environmentEntries.filter((e: EnvironmentEntry) => !e.deleting)
      .map((e: EnvironmentEntry): SelectOption => { return { value: e.label }; }));
  }

  private visibleThreads(): ScopedThread[] {
    return this.scopedThreads.filter((t: ScopedThread) => (!this.environmentFilter || t.localId === this.environmentFilter) &&
      (!this.projectFilterId || (t.localId === this.projectFilterLocalId && t.projectId === this.projectFilterId)));
  }
  private projectChoices(): ScopedProject[] {
    return this.scopedProjects.filter((p: ScopedProject) => !this.environmentFilter || p.localId === this.environmentFilter);
  }
  private projectOptions(): SelectOption[] {
    const all: SelectOption = { value: '所有项目' };
    return [all].concat(this.projectChoices().map((p: ScopedProject): SelectOption => { return { value: p.label }; }));
  }
  private filterProject(index: number): void {
    const project = index > 0 ? this.projectChoices()[index - 1] : undefined;
    this.projectFilterId = project?.id || ''; this.projectFilterLocalId = project?.localId || '';
  }

  private openPanel(name: string): void {
    this.panel = name; this.panelOpen = true;
    this.linkedSignature = ''; this.linkedGeneration++;
    this.refreshLinkedWhenChanged();
  }
  private refreshLinkedOnForeground(): void {
    if (!this.appForeground) { this.keyboard.reset(); this.composingText = false; }
    if (this.appForeground && this.alive && !this.loaded) void this.restoreAddress();
    if (this.appForeground) void this.openShortcut();
    this.linkedSignature = ''; this.linkedGeneration++;
    this.refreshLinkedWhenChanged();
  }
  private refreshLinkedWhenChanged(): void {
    if (!this.appForeground || !this.panelOpen || this.panel !== 'server') return;
    const registry = this.registry();
    const signature = registry.directory.entries.map((entry: EnvironmentEntry) =>
      entry.localId + ':' + entry.label + ':' + String(entry.enabled) + ':' + String(entry.deleting) + ':' + String(registry.clients.get(entry.localId)?.ready)).join('\n');
    if (signature === this.linkedSignature) return;
    this.linkedSignature = signature; void this.loadLinkedEnvironments();
  }
  private async loadLinkedEnvironments(): Promise<void> {
    const generation = ++this.linkedGeneration;
    const registry = this.registry();
    const groups = await Promise.all(registry.directory.entries.filter((entry: EnvironmentEntry) => entry.enabled && !entry.deleting && !entry.pendingBase)
      .map(async (entry: EnvironmentEntry): Promise<LinkedEnvironmentGroup | undefined> => {
        try {
          const connection = registry.clients.get(entry.localId);
          if (!connection?.ready) return undefined;
          await connection.refreshPeerAccess();
          if (!connection.canListPeerLinks()) return undefined;
          return { localId: entry.localId, label: entry.label, links: await connection.linkedEnvironments() };
        } catch (_) { return undefined; }
      }));
    if (generation !== this.linkedGeneration || !this.appForeground || !this.panelOpen || this.panel !== 'server') return;
    const visible: LinkedEnvironmentGroup[] = [];
    for (const group of groups) if (group) visible.push(group);
    this.linkedGroups = visible;
  }

  private hasEnabledEnvironment(): boolean {
    return this.environmentEntries.some((entry: EnvironmentEntry) => !entry.deleting && entry.enabled !== false);
  }
  private homeWaitingForFirstSnapshot(): boolean {
    return this.loaded && this.hasEnabledEnvironment() && this.scopedThreads.length === 0 &&
      !this.anyEnvironmentHasShell &&
      (this.restoringEnvironments || this.reconnectingCount > 0 || this.anyEnvironmentReady);
  }
  private homeAllOfflineWithoutCache(): boolean {
    return this.loaded && this.hasEnabledEnvironment() && this.scopedThreads.length === 0 &&
      !this.anyEnvironmentHasShell && !this.anyEnvironmentReady &&
      !this.restoringEnvironments && this.reconnectingCount === 0;
  }
  private homeThreadListLoading(): boolean {
    return !this.loaded || (this.scopedThreads.length === 0 && !this.anyEnvironmentLiveSynced &&
      (this.restoringEnvironments || this.reconnectingCount > 0));
  }
  private homeShowReconnectingHeader(): boolean {
    if (this.clientOffline) return false;
    return this.scopedThreads.length > 0 && (this.restoringEnvironments || this.reconnectingCount > 0);
  }
  private homeShowOfflineHeader(): boolean {
    if (this.clientOffline && this.scopedThreads.length > 0) return true;
    return this.scopedThreads.length > 0 && !this.restoringEnvironments &&
      this.reconnectingCount === 0 && this.offlineCount > 0;
  }
  private homeConnectionLabel(): string {
    if (this.clientOffline) return '当前离线';
    if (this.restoringEnvironments || this.reconnectingCount > 0) {
      const count = this.reconnectingCount > 0 ? this.reconnectingCount : 1;
      return count > 1 ? ('正在重连 ' + count + ' 个环境') : '正在重连环境';
    }
    return this.offlineCount > 1 ? (this.offlineCount + ' 个环境离线') : '工作环境离线';
  }
  private showChatStatusBanner(): boolean {
    if (!this.status || this.status === '会话已同步' || this.status === '已连接' || this.status === '未连接') {
      return false;
    }
    if (!this.draftMode && !this.ready && (client.reconnectPending || this.clientOffline || this.suppressReconnectUi)) {
      return false;
    }
    if (this.status === '正在鉴权' || this.status === '正在连接与校验服务器' ||
      this.status === '正在通过 T3 Connect 授权' || this.status === '正在连接中继环境' ||
      this.status === '正在同步会话' || this.status === '正在重新连接' ||
      this.status === '后台已暂停连接，任务在服务端继续' || this.status.startsWith('任务状态') ||
      this.status === '正在提交' || this.status === '指令已确认，请等待回复' ||
      this.status === '附件已上传，发送指令时附带') {
      return false;
    }
    return true;
  }
  private showHomeStatusBanner(): boolean {
    if (!this.status || this.homeShowReconnectingHeader() || this.homeWaitingForFirstSnapshot()) return false;
    if (this.status === '会话已同步' || this.status === '已连接' || this.status === '未连接' ||
      this.status === '正在鉴权' || this.status === '正在连接与校验服务器' ||
      this.status === '正在通过 T3 Connect 授权' || this.status === '正在连接中继环境' ||
      this.status === '正在同步会话' || this.status === '正在重新连接' ||
      this.status === '后台已暂停连接，任务在服务端继续' || this.status.startsWith('任务状态')) {
      return false;
    }
    return true;
  }

  @Builder
  iconButton(icon: Resource, label: string, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Image(icon).width(21).height(21)
    }.width(44).height(44).backgroundColor(Color.Transparent).borderRadius(22)
      .accessibilityText(label).onClick(action)
  }

  @Builder
  emptyState(title: string, detail: string) {
    Column({ space: Space.xs }) {
      Text(title).fontSize(FontSize.title).fontWeight(Weight.bold).lineHeight(LineHeight.title)
        .fontColor($r('app.color.ink')).textAlign(TextAlign.Center)
      Text(detail).fontSize(FontSize.body).lineHeight(LineHeight.body)
        .fontColor($r('app.color.muted')).textAlign(TextAlign.Center)
    }.width('100%').padding(Space.lg)
  }

  @Builder
  panelContent() {
    if (this.panel === 'attachment' && this.selectedAttachment) {
      Column() {
        TopBar({
          title: this.selectedAttachment.name,
          subtitle: this.selectedAttachment.mimeType + ' · ' + Math.ceil(this.selectedAttachment.sizeBytes / 1024) + ' KB',
          showBack: true,
          closeStyle: true,
          onBack: () => { this.panelOpen = false; }
        })
        Column({ space: Space.sm }) {
          if (this.selectedAttachment.type === 'image' && this.attachmentPreviewUrl) {
            Image(this.attachmentPreviewUrl).width('100%').constraintSize({ maxHeight: 420 })
              .objectFit(ImageFit.Contain).backgroundColor($r('app.color.card')).borderRadius(Radius.card)
          }
          if (this.selectedAttachment.mimeType.startsWith('video/') && this.attachmentPreviewUrl) {
            Video({ src: this.attachmentPreviewUrl }).width('100%').height(320).controls(true)
              .backgroundColor(Color.Black).borderRadius(Radius.card)
          }
          if (this.attachmentPreviewUrl) {
            AppButton({
              label: '复制预览链接',
              kind: 'secondary',
              fill: true,
              compact: true,
              onTap: () => { void this.copy(this.attachmentPreviewUrl); }
            })
          }
          AppButton({
            label: this.busy ? '保存中…' : '保存到文件',
            kind: 'primary',
            fill: true,
            disabled: this.busy,
            onTap: () => { void this.saveAttachment(); }
          })
          AppButton({
            label: '分享文件',
            kind: 'secondary',
            fill: true,
            disabled: this.busy,
            onTap: () => { void this.shareAttachment(); }
          })
          if (this.attachmentStatus) {
            Text(this.attachmentStatus).fontSize(FontSize.caption).fontColor($r('app.color.muted')).width('100%')
          }
        }.layoutWeight(1).width('100%').padding({ left: Space.page, right: Space.page, top: Space.xs, bottom: Space.md }).alignItems(HorizontalAlign.Start)
      }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
    } else if (this.panel === 'markdown-image') {
      Column() {
        TopBar({
          title: '图片预览',
          showBack: true,
          closeStyle: true,
          onBack: () => { this.panelOpen = false; }
        })
        Column({ space: Space.sm }) {
          Column({ space: Space.sm }) {
            if (this.markdownImageUrl && this.markdownImageKind === 'video') {
              Video({ src: this.markdownImageUrl }).width('100%').height(320).controls(true)
                .backgroundColor(Color.Black).borderRadius(Radius.tool)
            } else if (this.markdownImageUrl) {
              Image(this.markdownImageUrl).width('100%').constraintSize({ maxHeight: 460 })
                .objectFit(ImageFit.Contain).borderRadius(Radius.tool)
            } else {
              Text('没有可显示的图片').fontSize(FontSize.callout).fontColor($r('app.color.muted')).width('100%')
            }
            if (this.markdownImagePath) {
              Text(this.markdownImagePath)
                .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted'))
                .width('100%').maxLines(2).wordBreak(WordBreak.BREAK_ALL)
              AppButton({
                label: '复制路径',
                kind: 'secondary',
                compact: true,
                fill: true,
                onTap: () => { void this.copy(this.markdownImagePath); }
              })
            }
          }.padding(Space.md).width('100%').backgroundColor($r('app.color.card')).borderRadius(Radius.card).alignItems(HorizontalAlign.Start)
        }.layoutWeight(1).width('100%').padding({ left: Space.page, right: Space.page, top: Space.xs, bottom: Space.md }).alignItems(HorizontalAlign.Start)
      }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
    } else if (this.panel === 'paste-context') {
      Column() {
        TopBar({
          title: '粘贴结构化上下文',
          showBack: true,
          closeStyle: true,
          onBack: () => { this.panelOpen = false; }
        })
        Column({ space: Space.sm }) {
          Column({ space: Space.sm }) {
            Text('使用系统粘贴按钮读取剪贴板中的 T3 上下文片段；不会读取密码或任意页面。')
              .fontSize(FontSize.callout).lineHeight(LineHeight.callout).fontColor($r('app.color.muted')).width('100%')
            PasteButton({ icon: PasteIconStyle.LINES, text: PasteDescription.PASTE, buttonType: ButtonType.Capsule })
              .height(44).onClick((event: ClickEvent, result: PasteButtonOnClickResult) => {
                if (result !== PasteButtonOnClickResult.SUCCESS) {
                  this.status = '未获得剪贴板临时授权';
                  return;
                }
                void this.pasteContext();
              })
            if (this.status) {
              Text(this.status).fontSize(FontSize.caption).fontColor($r('app.color.muted')).width('100%')
            }
          }.padding(Space.md).width('100%').backgroundColor($r('app.color.card')).borderRadius(Radius.card).alignItems(HorizontalAlign.Start)
        }.layoutWeight(1).width('100%').padding({ left: Space.page, right: Space.page, top: Space.xs, bottom: Space.md }).alignItems(HorizontalAlign.Start)
      }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
    } else if (this.panel === 'composer-command') {
      ComposerCommandPanel({ mode: this.commandPanel, query: this.commandQuery, busy: this.busy,
        commands: client.providerCommands(), skills: client.providerSkills(), files: this.mentionFiles,
        branches: this.branches, environments: this.environmentLabels(),
        worktree: this.draftWorkspace.mode === 'worktree',
        startFromOrigin: this.draftWorkspace.startFromOrigin,
        onClose: () => this.panelOpen = false,
        onQuery: (value: string) => {
          if (this.commandPanel === 'mention') void this.searchMentionFiles(value);
          else this.commandQuery = value;
        },
        onCommand: (value: string) => this.insertCommand(value),
        onSkill: (name: string) => { this.addSkillContext(name); this.panelOpen = false; },
        onFile: (path: string) => { this.addFileContext(path); this.panelOpen = false; },
        onBranch: (ref: BranchView) => { void this.selectBranch(ref).catch((error: Error) => this.status = error.message); },
        onEnvironment: (label: string) => {
          const id = this.environmentIdForLabel(label);
          if (id) void this.switchDraftEnvironment(id).catch((error: Error) => this.status = error.message);
        },
        onWorktree: (value: boolean) => this.setWorkspaceMode(value ? 'worktree' : 'local'),
        onStartFromOrigin: (value: boolean) => {
          if (!this.draftMode || this.busy || this.unknown || this.draftWorkspace.mode !== 'worktree') return;
          this.draftWorkspace.startFromOrigin = value; this.scheduleDraftSave();
        },
        onSwitchCheckout: () => { void this.applyCurrentCheckoutBranch().catch((error: Error) => this.status = error.message); }
      })
    } else if (this.panel === 'extras') {
      ThreadExtrasPanel({ busy: this.busy, plans: this.extraPlans, subagents: this.extraSubagents,
        backgroundTasks: this.extraBackground,
        usage: this.extraUsage, guest: this.extraGuest, connected: this.ready,
        onClose: () => this.panelOpen = false,
        onCopy: (value: string) => { void this.copy(value); },
        onOpenThread: (threadId: string, remoteEnvironmentId: string) => {
          if (remoteEnvironmentId) {
            const entry = this.environmentEntries.find((candidate: EnvironmentEntry) => candidate.environmentId === remoteEnvironmentId);
            if (!entry) { this.status = '子会话所在环境未连接'; return; }
            void this.registry().select(entry.localId).then(() => this.watch(threadId));
          } else void this.watch(threadId);
        },
        onStopSubagent: (id: string) => {
          this.busy = true;
          void client.stopSubagent(id).then(() => { this.status = '已请求停止子 Agent'; })
            .catch((error: Error) => this.status = error.message)
            .finally(() => { this.busy = false; this.refreshExtras(); });
        },
        onFork: (sideChat: boolean) => { void this.runFork(sideChat); },
        onCreateGuest: () => { void this.copyGuestLink(); },
        onResolveGuest: (id: string, send: boolean) => {
          this.busy = true;
          void client.resolveGuestMessage(id, send).then(() => {
            this.status = send ? '访客消息已提交' : '访客消息已忽略';
          }).catch((error: Error) => this.status = error.message)
            .finally(() => { this.busy = false; this.refreshExtras(); });
        },
        onCloseGuest: () => {
          this.busy = true;
          void client.closeGuestShare().catch((error: Error) => this.status = error.message)
            .finally(() => { this.busy = false; this.refreshExtras(); });
        },
        onUsage: () => { this.panel = 'thread'; }
      })
    } else if (this.panel === 'agents') {
      ThreadAgentsPanel({
        subagents: this.turnSubagents.length ? this.turnSubagents : this.extraSubagents,
        busy: this.busy,
        connected: this.ready,
        onClose: () => { this.panelOpen = false; },
        onOpenThread: (threadId: string, remoteEnvironmentId: string) => {
          if (remoteEnvironmentId) {
            const entry = this.environmentEntries.find((candidate: EnvironmentEntry) => candidate.environmentId === remoteEnvironmentId);
            if (!entry) { this.status = '子会话所在环境未连接'; return; }
            void this.registry().select(entry.localId).then(() => this.watch(threadId));
          } else {
            void this.watch(threadId);
          }
        },
        onStopSubagent: (id: string) => {
          this.busy = true;
          void client.stopSubagent(id).then(() => { this.status = '已请求停止子 Agent'; })
            .catch((error: Error) => { this.status = error.message; })
            .finally(() => { this.busy = false; this.refreshExtras(); this.refreshFloatingCapsule(); });
        }
      })
    } else if (this.panel === 'background-work') {
      ThreadBackgroundWorkPanel({
        tasks: this.pendingBackgroundItems,
        canOperate: this.ready && client.canScope('orchestration:operate') !== false,
        stopPending: isBackgroundWorkStopPending(this.backgroundStopRequest, this.selectedLocalId + ':' + this.threadId, this.pendingBackgroundItems, this.nowMs),
        busy: this.busy,
        onClose: () => { this.panelOpen = false; },
        onOpenThread: (threadId: string) => { void this.watch(threadId); },
        onStopAll: () => { this.stopBackgroundWork(); }
      })
    } else if (this.panelOpen && this.panel === 'task-settings') {
      TaskSettingsPanel({ models: this.models, config: client.config, settings: this.taskSettings, busy: this.busy || this.unknown, status: this.status,
        onSave: (settings: TaskSettings) => { void this.saveTaskSettings(settings); }, onClose: () => this.panelOpen = false,
        onInstall: (id: string) => { void this.installProvider(id); },
        onAuth: (id: string) => { void this.startProviderAuth(id); },
        onRefreshProviders: (id: string) => { void this.refreshProvider(id); } })
    } else if (this.panel === 'queue') {
      QueuePanel({ runs: this.queued, busy: this.busy || this.unknown,
        active: !!client.thread && client.thread.runs.some((run: Record<string, Object>) =>
          ['preparing', 'starting', 'running', 'waiting'].includes(String(run.status))),
        status: this.status, onClose: () => this.panelOpen = false,
        onAction: (action: string, id: string, before: string | null, prompt: string) => { void this.queueAction(action, id, before, prompt); } })
    } else if (this.panel === 'snooze' && this.snoozeThread) {
      SnoozePanel({ thread: this.snoozeThread, settings: this.workspace().presets(this.snoozeThread.localId),
        onClose: () => { this.panelOpen = false; this.snoozeThread = undefined; },
        onSnooze: (thread: ScopedThread, value: string) => this.snoozeSelected(thread, value) })
    } else if (this.panel === 'rename' && this.renameThread) {
      ThreadRenamePanel({ thread: this.renameThread,
        onClose: () => { this.panelOpen = false; this.renameThread = undefined; },
        onRename: (thread: ScopedThread, title: string) => this.renameSelected(thread, title) })
    } else if (this.panel === 'filter') {
      Column({ space: 0 }) {
        TopBar({
          title: '筛选与排序',
          showBack: true,
          closeStyle: true,
          backLabel: '关闭筛选',
          onBack: () => { this.panelOpen = false; }
        })
        Scroll() {
          Column({ space: 0 }) {
            GroupCard({ title: '筛选范围' }) {
              Row({ space: 10 }) {
                Text('环境').fontSize(FontSize.body).fontColor($r('app.color.ink')).flexShrink(0)
                Select(this.environmentOptions()).value(this.environmentEntries.find((entry: EnvironmentEntry) =>
                  entry.localId === this.environmentFilter && !entry.deleting)?.label ||
                  (this.environmentFilter ? '已选环境暂不可用' : '所有环境'))
                  .onSelect((index: number) => void this.filterEnvironment(index))
                  .layoutWeight(1).constraintSize({ minHeight: 38 })
                  .backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
              .constraintSize({ minHeight: Sizes.formRowMin })
              Row({ space: 10 }) {
                Text('项目').fontSize(FontSize.body).fontColor($r('app.color.ink')).flexShrink(0)
                Select([{ value: '所有项目' } as SelectOption].concat(
                  pickableProjectGroups(this.projectGroups).map((group: ProjectGroup) => {
                    return { value: group.label } as SelectOption;
                  }))).value(this.projectFilterLabel)
                  .onSelect((index: number) => this.filterProjectKey(index === 0 ? '' : pickableProjectGroups(this.projectGroups)[index - 1]?.key || ''))
                  .layoutWeight(1).constraintSize({ minHeight: 38 })
                  .backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
              .constraintSize({ minHeight: Sizes.formRowMin })
              .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
            }

            GroupCard({ title: '会话排序' }) {
              FormRow({
                kind: 'choice',
                label: '最近用户消息',
                checked: this.threadSortOrder === 'updated_at',
                isFirst: true,
                onTap: () => this.setThreadSortOrder('updated_at')
              })
              FormRow({
                kind: 'choice',
                label: '创建时间',
                checked: this.threadSortOrder === 'created_at',
                onTap: () => this.setThreadSortOrder('created_at')
              })
            }

            Column() {
              AppButton({
                label: '清除环境与项目筛选',
                kind: 'secondary',
                fill: true,
                onTap: () => { void this.filterEnvironment(0); }
              })
            }.width('100%').padding({ top: Space.md })
          }.width('100%').padding({ left: Space.sm, right: Space.sm, bottom: Space.lg }).alignItems(HorizontalAlign.Start)
        }.width('100%').layoutWeight(1).align(Alignment.TopStart)
      }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
    } else if (this.panel === 'cloud') {
      CloudAccountPanel({ configured: this.cloudConfigured, signInReady: this.cloudSignInReady,
        signedIn: this.cloudSignedIn, accountId: this.cloudAccountId, status: this.cloudStatus,
        error: this.cloudError, busy: this.cloudBusy, refreshing: this.cloudRefreshing,
        environments: this.cloudEnvironments, entries: this.environmentEntries,
        onClose: () => { this.panel = this.cloudReturnPanel; },
        onSignIn: () => this.cloudSignIn(), onSignOut: () => this.cloudSignOut(),
        onRefresh: () => this.cloudRefresh(), onConnect: (id: string) => this.cloudConnect(id),
        onLink: (id: string) => this.cloudLink(id), onUnlink: (id: string) => this.cloudUnlink(id) })
    } else if (this.panel === 'peer-link' && this.activeLink && this.linkOwner) {
      PeerLinkForm({ request: this.activeLink, machines: this.linkMachines, connection: this.linkOwner,
        onClose: () => { this.panelOpen = false; },
        onBusy: (busy: boolean) => { this.busy = busy; if (!busy) { this.peerCanAnswer = this.linkOwner === client && !!this.linkOwner?.canManagePeerAccess(); this.incomingPairing(); } } })
    } else if (this.panel === 'server') {
          ConnectionsPanel({ entries: this.environmentEntries, linkedGroups: this.linkedGroups, statuses: this.environmentStatuses, readyMap: this.environmentReady, initialized: this.loaded,
            cloudConfigured: this.cloudConfigured, cloudSignedIn: this.cloudSignedIn, cloudStatus: this.cloudStatus,
            deviceEnvironmentLabel: this.deviceEnvironmentLabel, pendingDevices: this.pendingDevices,
            approvedDevices: this.approvedDevices,
            onClose: () => { this.panelOpen = false; this.credential = ''; },
            onAdd: () => { this.routeFor = ''; this.address = ''; this.credential = ''; this.pairingError = false; this.pairingStatus = '填写地址与配对码后确认'; this.panel = 'connection-new'; },
            onAddRoute: (id: string) => { this.routeFor = id; this.address = ''; this.credential = ''; this.pairingError = false; this.pairingStatus = '为当前环境添加连接路径'; this.panel = 'connection-new'; },
            onInitialize: () => this.restoreAddress(),
            onRetry: (id: string) => this.registry().reconnect(id),
            onEnabled: (id: string, enabled: boolean) => this.registry().setEnabled(id, enabled),
            onEdit: (id: string, label: string, address: string) => this.registry().edit(id, label, address),
            onRemove: (id: string) => this.forget(id),
            onReorderRoutes: (id: string, references: string[]) => this.registry().reorderRoutes(id, references),
            onRemoveRoute: (id: string, reference: string) => this.registry().removeRoute(id, reference),
            onRouting: (id: string, permission: string) => this.registry().setPullRequestRouting(id, permission),
            onCloudAccount: () => this.openCloudPanel('server'),
            onLinkCloud: (id: string) => this.cloudLink(id),
            onApproveDevice: (id: string) => this.approveDevice(id),
            onDenyDevice: (id: string) => this.denyDevice(id),
            onRevokeDevice: (id: string) => this.revokeDevice(id) })
    } else if (this.panel === 'connection-new') {
      Column({ space: 0 }) {
        TopBar({
          title: this.routeFor ? '添加路径' : '添加环境',
          showBack: true,
          backLabel: '返回环境',
          onBack: () => { this.panel = 'server'; this.credential = ''; this.routeFor = ''; this.pairingError = false; }
        }) {
          AppButton({
            label: this.busy ? '连接中' : '确认',
            kind: 'text',
            a11yLabel: this.routeFor ? '确认添加路径' : '确认添加环境',
            disabled: !this.loaded || this.busy || !this.address.trim(),
            onTap: () => this.connect()
          })
        }
        Scroll() {
          Column({ space: 0 }) {
            PairingScanCard({ active: this.panelOpen && this.panel === 'connection-new' && !this.busy,
              onTarget: (target: PairingTarget) => { this.address = target.base; this.credential = target.code; this.pairingError = false; this.pairingStatus = this.routeFor ? '请确认目标后添加连接路径' : '请确认目标后添加环境'; } })

            GroupCard({
              title: '或在这里输入',
              footnote: '适用于局域网或 tailnet 中的机器。凭据由目标机器保管。'
            }) {
              Row({ space: 12 }) {
                Text('地址').fontSize(FontSize.body).fontColor($r('app.color.ink')).width(64).flexShrink(0)
                TextInput({ placeholder: '192.168.1.100:3773', text: this.address }).layoutWeight(1).height(42)
                  .fontSize(FontSize.body).fontColor($r('app.color.ink')).placeholderColor($r('app.color.placeholder'))
                  .backgroundColor(Color.Transparent).padding(0)
                  .accessibilityText('服务器地址').enabled(!this.busy).onChange((value: string) => this.address = value)
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
              .constraintSize({ minHeight: Sizes.formRowMin })
              Row({ space: 12 }) {
                Text('配对码').fontSize(FontSize.body).fontColor($r('app.color.ink')).width(64).flexShrink(0)
                TextInput({ placeholder: 'Code', text: this.credential }).layoutWeight(1).height(42)
                  .fontSize(FontSize.body).fontColor($r('app.color.ink')).placeholderColor($r('app.color.placeholder'))
                  .backgroundColor(Color.Transparent).padding(0)
                  .type(InputType.Password).enableAutoFill(false).enabled(!this.busy).onChange((value: string) => this.credential = value)
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
              .constraintSize({ minHeight: Sizes.formRowMin })
              .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
            }

            if (this.pairingStatus) {
              Text(this.pairingStatus).fontSize(FontSize.caption).lineHeight(LineHeight.caption)
                .fontColor(this.pairingError ? $r('app.color.danger') : $r('app.color.muted'))
                .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs }).width('100%')
            }

            if (this.cloudConfigured) {
              GroupCard({ title: '云托管' }) {
                FormRow({
                  kind: 'value',
                  label: this.cloudSignedIn ? 'T3 Connect 已登录' : '使用 T3 Connect',
                  subtitle: this.cloudSignedIn ? (this.cloudStatus || '使用托管中继') : '通过中继访问已链接的机器',
                  value: '',
                  disabled: this.busy,
                  isFirst: true,
                  onTap: () => this.openCloudPanel('connection-new')
                })
              }
            }
          }.width('100%').padding({ left: Space.sm, right: Space.sm, top: Space.xs, bottom: Space.lg }).alignItems(HorizontalAlign.Start)
        }.width('100%').layoutWeight(1).align(Alignment.TopStart)
      }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
    } else {
      Column() {
        TopBar({
          title: '会话操作',
          showBack: true,
          closeStyle: true,
          onBack: () => { this.panelOpen = false; }
        })
        Scroll() {
          Column({ space: Space.xs }) {
            if (this.draftMode) {
              GroupCard({ title: '新任务' }) {
                FormRow({
                  label: '切换项目',
                  subtitle: this.projects.find((p: ProjectView) => p.id === this.projectId)?.label || '选择目标项目',
                  isFirst: true,
                  disabled: this.busy || this.unknown,
                  onTap: () => this.openProjectPicker(false, true)
                })
              }
            }
            GroupCard({ title: '工作区工具' }) {
              FormRow({
                label: '文件与源码',
                subtitle: '浏览目录并查看文件内容',
                isFirst: true,
                disabled: !this.currentWorkspace(),
                onTap: () => this.openFiles()
              })
              FormRow({
                label: '审阅 Diff',
                subtitle: '查看工作区或分支改动',
                disabled: !this.currentWorkspace(),
                onTap: () => this.openReview()
              })
              FormRow({
                label: 'Git 状态与提交',
                subtitle: '暂存、提交、分支与推送同步',
                disabled: !this.currentWorkspace(),
                onTap: () => this.openGit()
              })
              FormRow({
                label: '拉取请求',
                subtitle: '查看、评审、回复与合并 PR',
                onTap: () => this.openPullRequests()
              })
              FormRow({
                label: '终端',
                subtitle: '打开当前工作区远端终端',
                disabled: !(this.ready && !this.draftMode && !!this.currentWorkspace() && client.canScope('terminal:read') !== false),
                onTap: () => {
                  this.terminalConnection = client;
                  this.terminalThreadId = this.threadId;
                  this.terminalCwd = this.currentWorkspace();
                  this.panelOpen = false;
                  this.page = 'terminal';
                }
              })
              FormRow({
                label: '浏览器预览',
                subtitle: '查看与控制本地开发页面',
                disabled: !(this.ready && !this.draftMode && client.canScope('preview:operate') !== false),
                onTap: () => { void this.openPreview(); }
              })
              FormRow({
                label: '设备预览',
                subtitle: 'iOS Simulator 与 Android Emulator',
                disabled: !(this.ready && !this.draftMode && !this.busy),
                onTap: () => {
                  this.previewConnection = client;
                  this.previewThreadId = this.threadId;
                  this.previewGeneration = client.generationValue();
                  this.panelOpen = false;
                  this.page = 'device-picker';
                }
              })
            }
            GroupCard({ title: '任务与连接', footnote: this.status }) {
              FormRow({
                label: '同步会话',
                isFirst: true,
                chevron: false,
                disabled: !(this.ready && !this.busy && !this.draftMode),
                onTap: () => this.watch(this.threadId)
              })
              FormRow({
                label: '会话状态、计划与子 Agent',
                onTap: () => this.openThreadExtras()
              })
              if (this.canResumeLatestRun) {
                FormRow({
                  label: '恢复最近的运行',
                  chevron: false,
                  disabled: !(this.ready && !this.busy && !this.unknown && !this.draftMode),
                  onTap: () => {
                    this.busy = true;
                    void client.resumeLatestRun().catch((error: Error) => { this.status = error.message; })
                      .finally(() => { this.busy = false; });
                  }
                })
              }
              FormRow({
                label: '停止任务',
                destructive: true,
                chevron: false,
                disabled: !(this.ready && !this.busy && !this.unknown && !this.draftMode),
                onTap: () => this.stop()
              })
              FormRow({
                label: '强制停止最近的运行',
                destructive: true,
                chevron: false,
                disabled: !(this.ready && !this.busy && !this.unknown && !this.draftMode && client.supports('threadForceStop')),
                onTap: () => {
                  const runs = client.thread?.runs || [];
                  const active = runs.slice().reverse().find((run: Record<string, Object>) =>
                    ['preparing', 'starting', 'running', 'waiting'].includes(String(run.status)));
                  if (!active) { this.status = '没有正在运行的运行'; return; }
                  this.busy = true;
                  void client.forceStop(String(active.id)).catch((error: Error) => { this.status = error.message; })
                    .finally(() => { this.busy = false; });
                }
              })
              FormRow({
                label: '管理连接',
                onTap: () => { this.panel = 'server'; }
              })
            }
          }.padding({ left: Space.page, right: Space.page, top: Space.xs, bottom: Space.lg }).width('100%').alignItems(HorizontalAlign.Start)
        }.width('100%').layoutWeight(1).align(Alignment.TopStart)
      }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
    }
  }

  @Builder
  sessionsPage() {
    if (!this.loaded || this.environmentEntries.length === 0 || !this.hasEnabledEnvironment() ||
      this.homeWaitingForFirstSnapshot() || this.homeAllOfflineWithoutCache()) {
      Column() {
        Blank()
        if (!this.loaded) {
          this.emptyState(this.restoringEnvironments ? '正在读取工作环境' : '未能恢复工作环境',
            this.restoringEnvironments ? '正在安全读取已保存的连接。' : this.status)
          if (this.restoringEnvironments) { LoadingProgress().width(28).height(28) }
          else { AppButton({ label: '重试恢复', kind: 'primary', onTap: () => { void this.restoreAddress(); } }) }
        } else if (this.environmentEntries.length === 0) {
          this.emptyState('添加你的工作环境', '连接 T3 Code，在手机上继续工作。')
          AppButton({ label: '＋ 添加环境', kind: 'primary', onTap: () => this.openPanel('server') })
        } else if (!this.hasEnabledEnvironment()) {
          this.emptyState('工作环境已停用', '启用已保存的环境后继续工作。')
          AppButton({ label: '管理连接', kind: 'secondary', onTap: () => this.openPanel('server') })
        } else if (this.homeWaitingForFirstSnapshot()) {
          this.emptyState(this.anyEnvironmentReady ? '正在同步会话' : '正在连接工作环境',
            '已保留你的环境和会话，连接恢复后继续工作。')
          LoadingProgress().width(28).height(28).margin({ bottom: Space.md })
          AppButton({ label: '管理连接', kind: 'secondary', onTap: () => this.openPanel('server') })
        } else {
          this.emptyState('工作环境尚未连接', '已保留你的环境和会话，连接恢复后继续工作。')
          Row({ space: Space.sm }) {
            AppButton({ label: '重试连接', kind: 'primary', onTap: () => { void this.restoreAddress(); } })
            AppButton({ label: '管理连接', kind: 'secondary', onTap: () => this.openPanel('server') })
          }
        }
        Blank()
      }.layoutWeight(1).width('100%').padding({ bottom: 88 })
    } else {
      ThreadList({
        shelves: this.shelves, query: this.threadQuery, searchHits: this.threadSearchHits,
        turnable: this.turnableThreads, capabilities: this.threadCapabilities,
        selectedKey: this.selectedLocalId + ':' + this.threadId,
        nowMs: this.nowMs, environmentEntries: this.environmentEntries,
        environmentFilter: this.environmentFilter, projectFiltered: !!this.projectFilterKey, projectFilterLabel: this.projectFilterLabel,
        loading: this.homeThreadListLoading(), workingShelfExpanded: this.workingExpanded,
        snoozedShelfExpanded: this.snoozedExpanded, settledShelfExpanded: this.settledExpanded,
        settledLimit: this.settledLimit,
        searchOpen: this.searchOpen,
        bottomInset: 88,
        onSelect: (thread: ScopedThread) => { void this.openScopedThread(thread); },
        onAction: (thread: ScopedThread, action: string) => { void this.threadAction(thread, action); },
        onSnooze: (thread: ScopedThread) => { this.snoozeThread = thread; this.openPanel('snooze'); },
        onMove: (thread: ScopedThread, ordered: ScopedThread[], up: boolean) => {
          if (!thread.pinnedAt && workspacePrefs.workingShelfEnabled) return;
          this.busy = true;
          void this.workspace().move(thread, ordered, up)
            .catch((error: Error) => this.status = error.message)
            .finally(() => { this.busy = false; this.rebuildWorkspace(); });
        },
        onFilterEnvironment: () => this.openPanel('filter'),
        onFilterProject: () => this.openPanel('filter'),
        onClearFilters: () => { void this.filterEnvironment(0); },
        onSearch: (value: string) => this.setThreadQuery(value),
        onSearchFocus: (focused: boolean) => { this.searchFocused = focused; this.keyboard.reset(); },
        onCloseSearch: () => { this.searchOpen = false; this.searchFocused = false; if (this.threadQuery) this.setThreadQuery(''); },
        onNewTask: () => { void this.startNewTask(); },
        onSettings: () => this.openSettings(),
        onAddProject: () => this.openAddProject('choose-project'),
        onToggleWorking: () => {
          this.workingExpanded = !this.workingExpanded;
          workspacePrefs.workingShelfExpanded = this.workingExpanded; saveWorkspacePreferences();
        },
        onToggleSnoozed: () => {
          this.snoozedExpanded = !this.snoozedExpanded;
          workspacePrefs.snoozedShelfExpanded = this.snoozedExpanded; saveWorkspacePreferences();
        },
        onToggleSettled: () => {
          this.settledExpanded = !this.settledExpanded;
          workspacePrefs.settledShelfExpanded = this.settledExpanded; saveWorkspacePreferences();
        },
        onShowMoreSettled: () => { this.settledLimit += 25; }
      }).layoutWeight(1).width('100%')
    }
  }

  @Builder
  messageMenu(message: ChatMessage) {
    Menu() {
      MenuItem({ content: '复制消息' }).onClick(() => { void this.copy(message.text); })
      if (this.messageFooterMap[message.id]?.canFork && this.canOperateChat) {
        MenuItem({ content: '从此处分叉会话' }).onClick(() => {
          const meta = this.messageFooterMap[message.id];
          if (meta && meta.canFork) {
            void this.forkFromMessage(message.id, meta.forkRunId, meta.forkSourceThreadId);
          }
        })
      }
      MenuItem({ content: '分享消息' }).onClick(() => { void this.shareMessage(message.text); })
    }
  }

  @Builder
  sendModeContextMenu() {
    Menu() {
      MenuItem({ content: this.sendMode === 'auto' ? '✓ 自动发送' : '自动发送' }).onClick(() => { this.sendMode = 'auto'; })
      MenuItem({ content: this.sendMode === 'queue' ? '✓ 排队发送' : '排队发送' }).onClick(() => { this.sendMode = 'queue'; })
      MenuItem({ content: this.sendMode === 'steer' ? '✓ 引导运行' : '引导运行' }).onClick(() => { this.sendMode = 'steer'; })
    }
  }

  private toggleUserMessage(messageId: string): void {
    this.expandedUserMessages = toggleExpandedUserMessage(this.expandedUserMessages, messageId);
  }

  @Builder
  userBubble(message: ChatMessage) {
    Row() {
      Column({ space: Space.xs }) {
        ForEach(message.attachmentNames || [], (name: string) => {
          Button('附件 · ' + name, { type: ButtonType.Normal })
            .fontSize(FontSize.callout).fontColor($r('app.color.ink'))
            .backgroundColor($r('app.color.card')).border({ width: Sizes.hairline, color: $r('app.color.border') })
            .borderRadius(Radius.tool).constraintSize({ minHeight: 36 }).padding({ left: Space.sm, right: Space.sm })
            .onClick(() => { void this.openAttachment(name); })
        })
        if (isPlainUserText(message.text)) {
          Column() {
            CollapsibleUserMessageBody({
              messageKey: message.id,
              collapsible: true,
              onToggle: () => { this.toggleUserMessage(message.id); }
            }) {
              Text(message.text)
                .fontSize(FontSize.body).lineHeight(LineHeight.body)
                .fontColor($r('app.color.bubble_ink'))
                .copyOption(CopyOptions.InApp)
            }
          }.alignItems(HorizontalAlign.Start)
            .constraintSize({ maxWidth: '84%' })
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .backgroundColor($r('app.color.bubble'))
            .borderRadius({ topLeft: Radius.bubble, topRight: Radius.bubble, bottomLeft: Radius.bubble, bottomRight: 6 })
        } else {
          Column({ space: Space.xs }) {
            CollapsibleUserMessageBody({
              messageKey: message.id,
              collapsible: true,
              onToggle: () => { this.toggleUserMessage(message.id); }
            }) {
              MarkdownView({ markdown: message.text, selectable: true,
                mediaScopeKey: this.markdownMediaScopeKey(),
                mediaReady: this.ready,
                onCopy: (value: string) => { void this.copy(value); },
                onOpenLink: (url: string) => { void this.openLink(url); },
                onOpenImage: (url: string) => { void this.openMarkdownImage(url); },
                resolveMedia: (source: string, refresh: boolean): Promise<ResolvedMarkdownMedia> =>
                  this.resolveMarkdownMedia(source, refresh) })
            }
          }.alignItems(HorizontalAlign.Start)
            .width('84%').clip(true)
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .backgroundColor($r('app.color.bubble'))
            .borderRadius({ topLeft: Radius.bubble, topRight: Radius.bubble, bottomLeft: Radius.bubble, bottomRight: 6 })
        }
      }.alignItems(HorizontalAlign.End)
    }.width('100%').justifyContent(FlexAlign.End)
      .accessibilityText('我的消息：' + message.text)
  }

  @Builder
  assistantBlock(message: ChatMessage) {
    Column({ space: Space.xs }) {
      if (message.streaming) {
        Text('正在回复…').fontSize(FontSize.caption).fontColor($r('app.color.muted')).width('100%')
      }
      ForEach(message.attachmentNames || [], (name: string) => {
        Button('附件 · ' + name, { type: ButtonType.Normal }).width('100%')
          .fontSize(FontSize.callout).fontColor($r('app.color.ink'))
          .backgroundColor($r('app.color.card')).border({ width: Sizes.hairline, color: $r('app.color.border') })
          .borderRadius(Radius.tool).constraintSize({ minHeight: 36 }).padding({ left: Space.sm, right: Space.sm })
          .onClick(() => { void this.openAttachment(name); })
      })
      MarkdownView({ markdown: message.text, selectable: true,
        mediaScopeKey: this.markdownMediaScopeKey(),
        mediaReady: this.ready,
        onCopy: (value: string) => { void this.copy(value); },
        onOpenLink: (url: string) => { void this.openLink(url); },
        onOpenImage: (url: string) => { void this.openMarkdownImage(url); },
        resolveMedia: (source: string, refresh: boolean): Promise<ResolvedMarkdownMedia> =>
          this.resolveMarkdownMedia(source, refresh) })
    }.width('100%').alignItems(HorizontalAlign.Start)
      .accessibilityText('回复：' + message.text)
  }

  private toggleWorkGroup(group: TurnWorkGroup): void {
    const next: Record<string, boolean> = {};
    for (const key of Object.keys(this.expandedWorkGroups)) {
      next[key] = this.expandedWorkGroups[key];
    }
    const current = next[group.groupId] !== undefined ? next[group.groupId] : group.defaultExpanded;
    next[group.groupId] = !current;
    this.expandedWorkGroups = next;
  }

  @Builder
  turnWorkView(group: TurnWorkGroup) {
    ThreadActivity({
      connection: client,
      groupId: group.groupId,
      items: group.items,
      prominentItems: group.prominent,
      headerLabel: group.runMeta ? group.runMeta.headerLabel : '',
      summaryLabel: group.summary.label,
      failureLabel: group.summary.failureLabel,
      checkpointText: group.checkpoint ? group.checkpoint.label : '',
      checkpointAdditions: group.checkpoint ? group.checkpoint.additionsText : '',
      checkpointDeletions: group.checkpoint ? group.checkpoint.deletionsText : '',
      checkpointFiles: group.checkpoint ? group.checkpoint.filePaths.join('\n') : '',
      checkpointAccessible: group.checkpoint ? group.checkpoint.accessibleLabel : '',
      isRunning: group.runMeta ? group.runMeta.running : group.summary.running,
      isInterrupted: group.runMeta ? group.runMeta.interrupted : false,
      defaultExpanded: group.defaultExpanded,
      canOpenDiff: this.canOpenDiff,
      revision: group.revision,
      onToggleGroup: () => this.toggleWorkGroup(group),
      onCopy: (value: string) => { void this.copy(value); },
      onReference: (line: ActivityLine) => this.addTerminalContext(line),
      onOpenDiff: () => this.openReview()
    })
  }

  private draftProject(): ProjectView | undefined {
    return this.projects.find((project: ProjectView) => project.id === this.projectId);
  }

  @Builder
  chatPage() {
    if (this.draftMode) {
      Column({ space: Space.xs }) {
        Row({ space: Space.xs }) {
          Button({ type: ButtonType.Normal }) {
            Row({ space: 6 }) {
              if (this.draftProject()) {
                ProjectMonogram({
                  projectId: this.draftProject()!.id,
                  name: this.draftProject()!.label,
                  icon: this.draftProject()!.projectIcon,
                  boxSize: 18
                })
              } else {
                Image($r('app.media.ui_folder')).width(14).height(14).opacity(0.75).accessibilityLevel('no')
              }
              Text(this.draftProject()?.label || '选择项目')
                .fontSize(FontSize.callout).fontColor($r('app.color.ink')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
              Image($r('app.media.ui_chevron_right')).width(12).height(12).accessibilityLevel('no')
            }.width('100%').alignItems(VerticalAlign.Center)
          }.constraintSize({ minHeight: 38 }).padding({ left: Space.sm, right: Space.xs })
            .backgroundColor($r('app.color.group')).borderRadius(Radius.button).layoutWeight(1).enabled(!this.busy && !this.unknown)
            .accessibilityDescription('切换项目').onClick(() => this.openProjectPicker(false, true))
          Button({ type: ButtonType.Normal }) {
            Row({ space: 6 }) {
              Image($r('app.media.ui_env_desktop')).width(14).height(14).opacity(0.75).accessibilityLevel('no')
              Text(this.environmentEntries.find((entry: EnvironmentEntry) => entry.localId === this.selectedLocalId)?.label || '环境')
                .fontSize(FontSize.callout).fontColor($r('app.color.ink')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
              Image($r('app.media.ui_chevron_right')).width(12).height(12).accessibilityLevel('no')
            }.width('100%').alignItems(VerticalAlign.Center)
          }.constraintSize({ minHeight: 38 }).padding({ left: Space.sm, right: Space.xs })
            .backgroundColor($r('app.color.group')).borderRadius(Radius.button).layoutWeight(1).enabled(!this.busy && !this.unknown)
            .accessibilityDescription('选择环境').onClick(() => this.openComposerCommand('environment'))
        }.width('100%')
        Button({ type: ButtonType.Normal }) {
          Row({ space: 4 }) {
            Text((this.draftWorkspace.mode === 'worktree' ? '新工作树' :
              this.draftWorkspace.worktreePath ? '已有工作树' : '当前 checkout') + ' · ' +
              (this.draftWorkspace.branch || '未选分支'))
              .fontSize(FontSize.callout).fontColor($r('app.color.ink')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            Image($r('app.media.ui_chevron_right')).width(12).height(12).accessibilityLevel('no')
          }.width('100%').alignItems(VerticalAlign.Center)
        }.width('100%').constraintSize({ minHeight: 36 }).padding({ left: Space.sm, right: Space.xs })
          .backgroundColor($r('app.color.group')).borderRadius(Radius.button).enabled(!this.busy)
          .accessibilityDescription('选择分支与工作区').onClick(() => this.openComposerCommand('branch'))
      }.width('100%').padding({ left: Space.md, right: Space.md, top: Space.sm, bottom: Space.xs })
    }
    Stack({ alignContent: Alignment.Bottom }) {
      List({ space: 14, scroller: this.scroller }) {
      if (!this.draftMode && this.hasMoreHistory) {
        ListItem() {
          AppButton({ label: '加载更早的记录', kind: 'text', fill: true, disabled: this.busy,
            onTap: () => {
              this.busy = true;
              void client.loadOlderHistory().catch((error: Error) => this.status = error.message)
                .finally(() => this.busy = false);
            } })
        }
      }
      if (!this.messages.length) {
        if (!this.draftMode && (!this.ready || !client.thread || client.thread.cursor < 0)) {
          ListItem() {
            this.emptyState(client.threadSyncError ? client.threadSyncError : (this.ready ? '正在同步会话…' : '正在连接服务器…'),
              this.status || '连接恢复后将自动加载最新消息。')
          }
        } else {
          ListItem() { this.emptyState(this.draftMode ? '新任务' : '开始对话', '描述你想完成的任务。') }
        }
      }
      LazyForEach(this.source, (message: ChatMessage) => {
        ListItem() {
          Column({ space: 0 }) {
            if (message.role !== 'user' && !this.draftMode) {
              MessageWorkSlot({
                connection: client,
                messageId: message.id,
                slotKind: 'before',
                onToggleGroup: (group: TurnWorkGroup) => this.toggleWorkGroup(group),
                onCopy: (value: string) => { void this.copy(value); },
                onReference: (line: ActivityLine) => this.addTerminalContext(line),
                onOpenDiff: () => this.openReview()
              })
            }
            Column({ space: 4 }) {
              if (message.role === 'user') {
                this.userBubble(message)
              } else {
                this.assistantBlock(message)
              }
              MessageFooter({
                messageId: message.id,
                role: message.role,
                text: message.text,
                timestampLabel: this.messageTime(message.timestamp),
                onCopy: (value: string): Promise<boolean> => this.copy(value),
                onFork: (msgId: string, runId: string, sourceThreadId: string) => {
                  void this.forkFromMessage(msgId, runId, sourceThreadId);
                }
              })
            }.width('100%')
              .bindContextMenu(this.messageMenu(message), ResponseType.LongPress)
            if (message.role === 'user' && !this.draftMode) {
              MessageWorkSlot({
                connection: client,
                messageId: message.id,
                slotKind: 'afterUser',
                onToggleGroup: (group: TurnWorkGroup) => this.toggleWorkGroup(group),
                onCopy: (value: string) => { void this.copy(value); },
                onReference: (line: ActivityLine) => this.addTerminalContext(line),
                onOpenDiff: () => this.openReview()
              })
            } else if (message.role !== 'user' && !this.draftMode) {
              MessageWorkSlot({
                connection: client,
                messageId: message.id,
                slotKind: 'afterAssistant',
                onToggleGroup: (group: TurnWorkGroup) => this.toggleWorkGroup(group),
                onCopy: (value: string) => { void this.copy(value); },
                onReference: (line: ActivityLine) => this.addTerminalContext(line),
                onOpenDiff: () => this.openReview()
              })
            }
          }.width('100%')
        }
      }, (message: ChatMessage) => message.id + ':' + message.role + ':' + message.text.length + ':' +
        (message.streaming ? '1' : '0') + ':' + (message.timestamp || '') + ':' +
        (message.attachmentNames ? message.attachmentNames.length : 0) + ':' + message.text.slice(-16))
      if (!this.draftMode && this.workMap.tail) {
        ListItem() {
          this.turnWorkView(this.workMap.tail)
        }
      }
      if (!this.draftMode && this.liveThinking.visible) {
        ListItem() {
          ThreadThinkingRow({
            label: this.liveThinking.label,
            active: true
          })
        }
      }
      ForEach(this.actions, (card: ActionCard) => { ListItem() { RequestCard({ card, connection: client }) } }, (card: ActionCard) => this.selectedLocalId + ':' + card.id)
      ForEach(this.linkItems, (item: LinkRequestView) => {
        ListItem() {
          if (item.status === 'pending' && item.visibility === 'local') {
            Column({ space: Space.sm }) {
              Text(item.url || item.environmentId ? '将 ' + (linkOrigin(item.url) || '目标环境') + ' 链接到此环境' : '将一台机器链接到此环境')
                .fontSize(FontSize.body).fontWeight(Weight.semibold).fontColor($r('app.color.ink')).width('100%')
              if (item.reason.trim()) { Text(item.reason).fontSize(FontSize.callout).fontColor($r('app.color.muted')).width('100%') }
              if (this.peerCanAnswer) {
                Row({ space: Space.xs }) {
                  Column() {
                    AppButton({ label: '拒绝', kind: 'secondary', compact: true, fill: true, disabled: this.busy || this.unknown,
                      onTap: () => this.declinePeerLink(item) })
                  }.layoutWeight(1)
                  Column() {
                    AppButton({ label: item.url || item.environmentId ? '审阅链接…' : '选择机器…', kind: 'primary', compact: true, fill: true,
                      disabled: this.busy || this.unknown, onTap: () => { void this.openPeerLink(item); } })
                  }.layoutWeight(1)
                }.width('100%')
              } else { Text('只有管理此环境访问权限的连接才能答复此请求。').fontSize(FontSize.callout).fontColor($r('app.color.muted')).width('100%') }
            }.padding(Space.md).width('100%').backgroundColor($r('app.color.card')).border({ width: 1, color: $r('app.color.border') }).borderRadius(Radius.card)
          } else { Text(this.peerOutcome(item)).fontSize(FontSize.callout).fontColor($r('app.color.muted')).width('100%') }
        }
      }, (item: LinkRequestView) => this.selectedLocalId + ':' + item.id)
      if (!this.draftMode) {
        ForEach(this.extraPlans, (plan: PlanView) => {
          ListItem() {
            Column({ space: Space.xs }) {
              Text(plan.streaming ? '正在生成计划…' : '计划').fontSize(FontSize.caption).fontWeight(Weight.semibold).fontColor($r('app.color.muted')).width('100%')
              Text(plan.markdown).fontSize(FontSize.callout).lineHeight(LineHeight.callout).width('100%').copyOption(CopyOptions.InApp)
              Row({ space: Space.xs }) {
                AppButton({ label: '复制计划', kind: 'secondary', compact: true, onTap: () => { void this.copy(plan.markdown); } })
                AppButton({ label: '保存 plan.md', kind: 'secondary', compact: true, disabled: this.busy || !client.canWriteSourceControl(),
                  onTap: () => {
                    const project = this.scopedProjects.find((item: ScopedProject) =>
                      item.localId === this.selectedLocalId && item.id === this.projectId) ||
                      this.scopedProjects.find((item: ScopedProject) => item.localId === this.selectedLocalId);
                    if (!project) { this.status = '找不到工作区'; return; }
                    this.busy = true;
                    void client.writeWorkspaceFile(project.workspaceRoot, 'plan.md', plan.markdown.trimEnd() + '\n')
                      .then((path: string) => this.status = '计划已保存：' + path)
                      .catch((error: Error) => this.status = error.message)
                      .finally(() => this.busy = false);
                  } })
              }.width('100%')
            }.padding(Space.md).width('100%').backgroundColor($r('app.color.card')).border({ width: 1, color: $r('app.color.border') }).borderRadius(Radius.card)
          }
        }, (plan: PlanView) => plan.id)
        if (this.extraUsage) {
          ListItem() {
            Text(this.extraUsage.inputTokens + ' 输入 · ' + this.extraUsage.outputTokens + ' 输出')
              .fontSize(FontSize.badge).fontColor($r('app.color.muted')).width('100%')
          }
        }
        if (this.extraGuest) {
          ForEach(this.extraGuest.messages.filter((message: GuestMessageView) => message.status === 'pending'), (message: GuestMessageView) => {
            ListItem() {
              Column({ space: Space.xs }) {
                Text('来自访客 ' + (this.extraGuest?.guestName || '') + (message.text ? '\n' + message.text : ''))
                  .fontSize(FontSize.callout).width('100%')
                Row({ space: Space.xs }) {
                  Column() {
                    AppButton({ label: '忽略', kind: 'secondary', compact: true, fill: true, disabled: this.busy,
                      onTap: () => {
                        this.busy = true;
                        void client.resolveGuestMessage(message.id, false).catch((error: Error) => this.status = error.message)
                          .finally(() => { this.busy = false; this.refreshExtras(); });
                      } })
                  }.layoutWeight(1)
                  Column() {
                    AppButton({ label: '发送', kind: 'primary', compact: true, fill: true, disabled: this.busy,
                      onTap: () => {
                        this.busy = true;
                        void client.resolveGuestMessage(message.id, true).catch((error: Error) => this.status = error.message)
                          .finally(() => { this.busy = false; this.refreshExtras(); });
                      } })
                  }.layoutWeight(1)
                }.width('100%')
              }.padding(Space.md).width('100%').backgroundColor($r('app.color.card')).border({ width: 1, color: $r('app.color.border') }).borderRadius(Radius.card)
            }
          })
        }
      }
      if (this.worktreeSetup) {
        ListItem() {
          Column({ space: Space.xs }) {
            Text('工作树准备 · ' + String(this.worktreeSetup.phase || 'running')).fontSize(FontSize.callout).fontWeight(Weight.semibold).width('100%')
            if (typeof this.worktreeSetup.branch === 'string') {
              Text('分支 ' + this.worktreeSetup.branch + (typeof this.worktreeSetup.worktreePath === 'string' ? '\n' + this.worktreeSetup.worktreePath : ''))
                .fontSize(FontSize.caption).fontColor($r('app.color.muted')).width('100%')
            }
            if (typeof this.worktreeSetup.error === 'string' && this.worktreeSetup.error) {
              Text(this.worktreeSetup.error).fontSize(FontSize.caption).fontColor($r('app.color.danger')).width('100%')
            }
            if (this.worktreeSetup.phase === 'failed') {
              Row({ space: Space.xs }) {
                AppButton({ label: '重试准备', kind: 'secondary', compact: true, disabled: this.busy, onTap: () => {
                  const runs = client.thread?.runs || [];
                  const failed = runs.slice().reverse().find((run: Record<string, Object>) =>
                    ['preparing', 'failed'].includes(String(run.status)));
                  if (!failed) { this.status = '没有可重试的准备运行'; return; }
                  this.busy = true;
                  void client.retryPreparedRun(String(failed.id)).catch((error: Error) => this.status = error.message)
                    .finally(() => this.busy = false);
                } })
                AppButton({ label: '取消准备', kind: 'secondary', compact: true, disabled: this.busy, onTap: () => {
                  this.busy = true;
                  void client.cancelWorktreeSetup().catch((error: Error) => this.status = error.message)
                    .finally(() => this.busy = false);
                } })
              }.width('100%')
            }
          }.padding(Space.md).width('100%').backgroundColor($r('app.color.card')).border({ width: 1, color: $r('app.color.border') }).borderRadius(Radius.card)
        }
      }
      if (!this.draftMode && client.thread && typeof client.thread.details.usageLimitResetAt === 'string') {
        ListItem() {
          Column({ space: Space.xs }) {
            Text('用量限制').fontSize(FontSize.callout).fontWeight(Weight.semibold).width('100%')
            Text('重置时间：' + String(client.thread.details.usageLimitResetAt))
              .fontSize(FontSize.caption).fontColor($r('app.color.muted')).width('100%')
            Flex({ wrap: FlexWrap.Wrap }) {
              AppButton({ label: '到点自动恢复', kind: 'secondary', compact: true, disabled: this.busy, onTap: () => {
                this.busy = true;
                void client.setLimitRecovery(true, undefined).catch((error: Error) => this.status = error.message)
                  .finally(() => this.busy = false);
              } })
              AppButton({ label: '取消自动恢复', kind: 'secondary', compact: true, disabled: this.busy, onTap: () => {
                this.busy = true;
                void client.setLimitRecovery(false, undefined).catch((error: Error) => this.status = error.message)
                  .finally(() => this.busy = false);
              } })
              AppButton({ label: '暂缓到重置', kind: 'secondary', compact: true, disabled: this.busy, onTap: () => {
                this.busy = true;
                void client.setLimitRecovery(undefined, true).catch((error: Error) => this.status = error.message)
                  .finally(() => this.busy = false);
              } })
            }.width('100%')
          }.padding(Space.md).width('100%').backgroundColor($r('app.color.card')).border({ width: 1, color: $r('app.color.border') }).borderRadius(Radius.card)
        }
      }
      if (this.unknown) {
        ListItem() {
          Column({ space: Space.sm }) {
            Text('核对上次提交').fontSize(FontSize.body).fontWeight(Weight.semibold).width('100%')
            Text('同步原会话并核对结果后，才能再次发送。').fontSize(FontSize.callout).fontColor($r('app.color.muted')).width('100%')
            Row({ space: Space.xs }) {
              Column() {
                AppButton({ label: '同步会话', kind: 'secondary', compact: true, fill: true,
                  disabled: !this.ready || this.busy || this.draftMode, onTap: () => { void this.watch(this.threadId); } })
              }.layoutWeight(1)
              Column() {
                AppButton({ label: '已核对提交结果', kind: 'primary', compact: true, fill: true,
                  disabled: !this.ready || this.busy, onTap: () => this.acknowledge() })
              }.layoutWeight(1)
            }.width('100%')
          }.padding(Space.md).width('100%').backgroundColor($r('app.color.card')).border({ width: 1, color: $r('app.color.border') }).borderRadius(Radius.card)
        }
      }
      }.width('100%').height('100%').cachedCount(2)
        .padding({ left: Space.md, right: Space.md })
        .contentStartOffset(Space.xs)
        .contentEndOffset(this.floatingCapsule.visible ? 56 : Space.sm)
        .scrollBar(BarState.Off)
        .onDidScroll((): void => {
          this.chatAwayFromBottom = this.messages.length > 0 && !this.scroller.isAtEnd();
        })
        .onReachEnd((): void => {
          this.chatAwayFromBottom = false;
        })
      FloatingStatusCapsule({
        model: this.floatingCapsule,
        showScrollToEnd: this.chatAwayFromBottom && this.messages.length > 0,
        onStatusTap: () => this.openCapsuleStatus(),
        onActionTap: () => this.triggerCapsuleAction(),
        onOpenAgents: () => {
          this.refreshExtras();
          this.refreshFloatingCapsule();
          this.openPanel('agents');
        },
        onOpenQueue: () => this.openPanel('queue'),
        onScrollToEnd: () => {
          this.scroller.scrollEdge(Edge.Bottom);
          this.chatAwayFromBottom = false;
        }
      })
        .hitTestBehavior(HitTestMode.Transparent)
    }.width('100%').layoutWeight(1)
    Column({ space: 0 }) {
      if (this.draftContext.length || this.attachments.length) {
        Scroll() {
          Row({ space: 6 }) {
            ForEach(this.draftContext, (item: ComposerContextRecord) => {
              Row({ space: 4 }) {
                Text(item.kind + ': ' + item.label)
                  .fontSize(FontSize.caption).lineHeight(LineHeight.caption)
                  .fontColor($r('app.color.ink'))
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .constraintSize({ maxWidth: 168 })
                Text('×')
                  .fontSize(FontSize.callout).fontColor($r('app.color.muted'))
              }
              .height(30).padding({ left: 10, right: 8 })
              .backgroundColor($r('app.color.card')).borderRadius(Radius.tool)
              .border({ width: 0.5, color: $r('app.color.border') })
              .alignItems(VerticalAlign.Center)
              .accessibilityDescription('移除引用 ' + item.label)
              .onClick(() => this.removeContext(item.contextId))
            }, (item: ComposerContextRecord) => item.contextId)
            ForEach(this.attachments, (item: DraftAttachment) => {
              Row({ space: 0 }) {
                Button({ type: ButtonType.Normal, stateEffect: true }) {
                  Text((item.type === 'image' ? '图 · ' : '文件 · ') + item.name)
                    .fontSize(FontSize.caption).lineHeight(LineHeight.caption)
                    .fontColor($r('app.color.ink'))
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    .constraintSize({ maxWidth: 176 })
                }
                .height(30).padding({ left: 10, right: 6 })
                .backgroundColor(Color.Transparent)
                .onClick(() => { void this.openAttachment(item.name); })
                Button({ type: ButtonType.Normal, stateEffect: true }) {
                  Text('×').fontSize(FontSize.callout).fontColor($r('app.color.muted'))
                }
                .width(26).height(30).padding(0)
                .backgroundColor(Color.Transparent)
                .accessibilityText('移除附件 ' + item.name)
                .onClick(() => { client.removeAttachment(item.id); this.refreshAttachments(); this.scheduleDraftSave(); })
              }
              .backgroundColor($r('app.color.card')).borderRadius(Radius.tool)
              .border({ width: 0.5, color: $r('app.color.border') })
              .alignItems(VerticalAlign.Center)
            }, (item: DraftAttachment) => item.id)
          }.padding({ left: 12, right: 12, top: 10, bottom: 2 })
        }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).align(Alignment.Start).width('100%')
      }
      TextArea({ placeholder: this.draftMode ? '描述要完成的任务…' : '继续追问…', text: this.prompt })
        .width('100%')
        .fontSize(FontSize.body).lineHeight(LineHeight.body)
        .fontColor($r('app.color.ink')).placeholderColor($r('app.color.placeholder'))
        .onChange((value: string, preview: PreviewText) => { this.composingText = !!preview?.value; this.prompt = value; this.scheduleDraftSave(); })
        .onFocus(() => { this.composerFocused = true; this.keyboard.reset(); })
        .onBlur(() => { this.composerFocused = false; this.composingText = false; this.keyboard.reset(); })
        .onKeyPreIme((event: KeyEvent): boolean => this.keyboardEvent(event, true))
        .constraintSize({ minHeight: 42 }).maxLines(5, { overflowMode: MaxLinesMode.SCROLL })
        .padding({ left: 14, right: 14, top: (this.draftContext.length || this.attachments.length) ? 6 : 12, bottom: 4 })
        .backgroundColor(Color.Transparent).accessibilityText('消息输入框')
      Row({ space: 4 }) {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          Image($r('app.media.ui_plus'))
            .width(20).height(20)
            .opacity(this.busy || this.unknown ? Opacity.disabled : 0.9)
            .accessibilityLevel('no')
        }.width(38).height(38)
          .backgroundColor(Color.Transparent)
          .accessibilityText('添加附件与工具')
          .bindMenu(this.composerAttachmentMenu(
            this.uploadingAttachment,
            this.canRetryAttachment,
            this.attachments.length > 0,
            this.draftMode,
            this.sendMode,
            this.queued.length,
            this.threadRunning
          ))
        if (!this.draftMode && this.sendMode !== 'auto') {
          Button({ type: ButtonType.Capsule, stateEffect: true }) {
            Text(this.sendMode === 'queue' ? '排队' : '引导')
              .fontSize(FontSize.caption).lineHeight(LineHeight.caption)
              .fontWeight(Weight.medium)
              .fontColor($r('app.color.primary_text'))
          }.height(28).padding({ left: 10, right: 10 })
            .backgroundColor($r('app.color.info_bg'))
            .accessibilityText('消息发送方式，' + (this.sendMode === 'queue' ? '排队' : '引导'))
            .bindMenu(this.composerSendModeMenu())
        }
        Row() {
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Row({ space: 5 }) {
              if (this.hasCurrentModelLogo()) {
                ProviderLogo({ driver: this.currentModelDriver(), model: this.currentModelSlug(), logoSize: 17 })
              } else {
                Image($r('app.media.ui_settings')).width(16).height(16).opacity(0.75).flexShrink(0).accessibilityLevel('no')
              }
              Text(this.currentModelDisplayLabel() || '模型')
                .fontSize(FontSize.body).lineHeight(LineHeight.body)
                .fontWeight(Weight.medium)
                .fontColor($r('app.color.ink'))
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .wordBreak(WordBreak.BREAK_ALL)
                .constraintSize({ minWidth: 0 })
                .flexShrink(1)
              if (this.currentModelSummary()) {
                Text(this.currentModelSummary())
                  .fontSize(FontSize.callout).lineHeight(LineHeight.callout)
                  .fontColor($r('app.color.muted'))
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .flexShrink(0)
              }
              Image($r('app.media.ui_chevron_down')).width(12).height(12).opacity(0.7).flexShrink(0).accessibilityLevel('no')
            }.alignItems(VerticalAlign.Center)
          }.height(36).padding({ left: 8, right: 6 })
            .backgroundColor(Color.Transparent)
            .borderRadius(Radius.button)
            .constraintSize({ minWidth: 0 })
            .enabled(!this.busy && !this.unknown)
            .opacity(!this.busy && !this.unknown ? 1 : Opacity.disabled)
            .accessibilityText('模型与选项，' + (this.currentModelDisplayLabel() || '模型') +
              (this.currentModelSummary() ? ' ' + this.currentModelSummary() : ''))
            .onClick(() => this.openTaskSettings())
        }.layoutWeight(1).constraintSize({ minWidth: 0 }).justifyContent(FlexAlign.End).alignItems(VerticalAlign.Center)
        if (!this.draftMode && this.threadRunning && !this.busy && !this.unknown &&
          this.prompt.trim().length === 0 && this.attachments.length === 0) {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            Rect().width(11).height(11).radius(2.5).fill($r('app.color.danger'))
          }.width(36).height(36)
            .backgroundColor($r('app.color.danger_bg'))
            .border({ width: 1, color: $r('app.color.danger_border') })
            .enabled(this.ready)
            .opacity(this.ready ? 1 : Opacity.disabled)
            .accessibilityText('停止任务')
            .onClick(() => this.stop())
        } else if (this.draftMode) {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            if (this.busy) {
              LoadingProgress().width(16).height(16).color($r('app.color.on_prominent')).accessibilityLevel('no')
            } else {
              Image($r('app.media.ui_send')).width(17).height(17).accessibilityLevel('no')
            }
          }.width(36).height(36).backgroundColor($r('app.color.prominent'))
            .opacity(this.busy || (this.ready && !this.unknown && (this.prompt.trim().length > 0 || this.attachments.length > 0)) ? 1 : 0.28)
            .accessibilityText(this.busy ? '正在提交' : '发送消息')
            .enabled(this.ready && !this.busy && !this.unknown && (this.prompt.trim().length > 0 || this.attachments.length > 0))
            .onClick(() => this.send())
        } else {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            if (this.busy) {
              LoadingProgress().width(16).height(16).color($r('app.color.on_prominent')).accessibilityLevel('no')
            } else {
              Image($r('app.media.ui_send')).width(17).height(17).accessibilityLevel('no')
            }
          }.width(36).height(36).backgroundColor($r('app.color.prominent'))
            .opacity(this.busy || (this.ready && !this.unknown && (this.prompt.trim().length > 0 || this.attachments.length > 0)) ? 1 : 0.28)
            .accessibilityText(this.busy ? '正在提交' : '发送消息')
            .enabled(this.ready && !this.busy && !this.unknown && (this.prompt.trim().length > 0 || this.attachments.length > 0))
            .bindContextMenu(this.sendModeContextMenu(), ResponseType.LongPress)
            .onClick(() => this.send())
        }
      }.width('100%').padding({ left: 6, right: 8, top: 2, bottom: 6 }).alignItems(VerticalAlign.Center)
    }.margin({ left: Space.sm, right: Space.sm, top: Space.xxs, bottom: this.composerFocused ? Space.xs : Space.sm })
      .backgroundColor($r('app.color.group')).borderRadius(Radius.composer)
      .border({ width: 1, color: $r('app.color.border') })
  }

  private resolveActiveModel(owner: T3Client): void {
    let instanceId = '';
    let slug = '';
    let selection: ModelSelection | undefined = undefined;
    let reportedSelection: ModelSelection | undefined = undefined;
    if (this.draftMode) {
      selection = this.taskSettings.modelSelection;
      instanceId = selection.instanceId || '';
      slug = selection.model || '';
    } else if (this.threadId) {
      if (owner.thread && owner.thread.threadId === this.threadId) {
        const details = owner.thread.details;
        selection = parseModelSelection(details.modelSelection);
        reportedSelection = parseModelSelection(details.reportedModelSelection);
        if (selection) {
          instanceId = selection.instanceId;
          slug = selection.model;
        }
        if (!reportedSelection && typeof details.activeProviderThreadId === 'string' && details.activeProviderThreadId) {
          const activeProviderThreadId = details.activeProviderThreadId;
          const providerThread = owner.thread.providerThreads.find((candidate: Record<string, Object>) =>
            candidate.id === activeProviderThreadId &&
            (!instanceId || candidate.providerInstanceId === instanceId));
          if (providerThread && providerThread.nativeMetadata !== undefined && providerThread.nativeMetadata !== null) {
            reportedSelection = parseModelSelection(record(providerThread.nativeMetadata).modelSelection);
          }
        }
        if (!instanceId && typeof details.providerInstanceId === 'string') {
          instanceId = details.providerInstanceId;
        }
      }
      if (!instanceId || !slug) {
        const matchedThread = this.threads.find((t: ThreadView) => t.id === this.threadId);
        const matchedScopedThread = this.scopedThreads.find((t: ScopedThread) =>
          t.localId === this.selectedLocalId && t.id === this.threadId);
        if (!instanceId) instanceId = matchedThread?.providerInstanceId || matchedScopedThread?.providerInstanceId || '';
        if (!slug) slug = matchedThread?.model || matchedScopedThread?.model || '';
      }
      if (!instanceId && !slug && this.renderedThreadKey === (this.selectedLocalId + ':' + this.threadId)) {
        instanceId = this.activeModelInstanceId;
        slug = this.activeModelSlug;
      }
    }
    if (!selection && instanceId && slug) {
      selection = { instanceId, model: slug };
    }
    let driver = instanceId;
    let rawName = slug;
    const rawProviders = owner.config ? record(owner.config).providers : undefined;
    const providers = Array.isArray(rawProviders) ? objects(rawProviders as Object) : [];
    for (const value of providers) {
      const provider = record(value);
      if (typeof provider.instanceId !== 'string' || provider.instanceId !== instanceId) continue;
      if (typeof provider.driver === 'string' && provider.driver.trim()) driver = provider.driver;
      const modelsList = Array.isArray(provider.models) ? objects(provider.models as Object) : [];
      for (const item of modelsList) {
        const model = record(item);
        if (typeof model.slug === 'string' && model.slug === slug) {
          const shortText = typeof model.shortName === 'string' ? model.shortName : '';
          const nameText = typeof model.name === 'string' ? model.name : '';
          rawName = shortText || nameText || slug;
          break;
        }
      }
      break;
    }
    this.activeModelInstanceId = instanceId;
    this.activeModelDriver = driver;
    this.activeModelSlug = slug;
    this.activeModelLabel = composerModelShortName(rawName, slug, driver);
    this.activeModelSummary = selection ? modelOptionsSummary(owner.config, selection, reportedSelection) : '';
  }

  private currentModelSlug(): string {
    return this.activeModelSlug || (this.draftMode ? this.taskSettings.modelSelection.model : '');
  }

  private currentModelDriver(): string {
    if (this.activeModelDriver) return this.activeModelDriver;
    const instanceId = this.activeModelInstanceId || (this.draftMode ? this.taskSettings.modelSelection.instanceId : '');
    const rawProviders = client.config ? record(client.config).providers : undefined;
    const providers = Array.isArray(rawProviders) ? objects(rawProviders as Object) : [];
    for (const value of providers) {
      const provider = record(value);
      if (typeof provider.instanceId === 'string' && provider.instanceId === instanceId &&
        typeof provider.driver === 'string' && provider.driver.trim()) {
        return provider.driver;
      }
    }
    return instanceId;
  }

  private hasCurrentModelLogo(): boolean {
    return providerLogoKind(this.currentModelDriver(), this.currentModelSlug()) !== 'none';
  }

  private currentModelDisplayLabel(): string {
    if (this.activeModelLabel) return this.activeModelLabel;
    const instanceId = this.activeModelInstanceId || (this.draftMode ? this.taskSettings.modelSelection.instanceId : '');
    const slug = this.currentModelSlug();
    const hit = this.models.find((item: ModelChoice) => item.instanceId === instanceId && item.model === slug);
    return composerModelShortName(hit?.label || slug, slug, this.currentModelDriver());
  }

  private currentModelSummary(): string {
    if (this.activeModelSummary) return this.activeModelSummary;
    if (this.draftMode) return modelOptionsSummary(client.config, this.taskSettings.modelSelection);
    if (this.taskSettings.modelSelection.instanceId === this.activeModelInstanceId &&
      this.taskSettings.modelSelection.model === this.activeModelSlug) {
      return modelOptionsSummary(client.config, this.taskSettings.modelSelection);
    }
    return '';
  }

  private isRootTab(): boolean {
    return this.page === 'sessions' || this.page === 'home-pulls' || this.page === 'usage' || this.page === 'settings';
  }

  private showHomeBottomBar(): boolean {
    return (this.page === 'sessions' && !this.searchFocused) ||
      (this.page === 'home-pulls' && !this.homeTabDetailOpen) ||
      (this.page === 'usage' && !this.homeTabDetailOpen) ||
      (this.page === 'settings' && !this.settingsSection);
  }

  private activeHomeTab(): HomeTab {
    if (this.page === 'home-pulls') return 'home-pulls';
    if (this.page === 'usage') return 'usage';
    if (this.page === 'settings') return 'settings';
    return 'sessions';
  }

  private selectHomeTab(tab: HomeTab): void {
    this.homeTabDetailOpen = false;
    if (tab === 'settings') {
      this.settingsSection = '';
      void this.refreshSessions();
    }
    this.page = tab;
  }

  private toggleHomeSearch(): void {
    if (this.searchOpen && !this.threadQuery) {
      this.searchOpen = false;
      this.searchFocused = false;
      return;
    }
    this.searchOpen = true;
    setTimeout(() => {
      if (this.alive && this.page === 'sessions' && this.searchOpen) {
        try { this.getUIContext().getFocusController().requestFocus('thread-search'); } catch (_) {}
      }
    }, 50);
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        if (this.shareId && this.page !== 'share' && !this.choosingShare) {
          Column() {
            AppButton({
              label: '收到分享 · 审阅并保存草稿',
              kind: 'secondary',
              compact: true,
              fill: true,
              disabled: this.busy || this.unknown,
              onTap: () => { this.panelOpen = false; this.page = 'share'; }
            })
          }.width('100%').padding({ left: Space.page, right: Space.page, top: Space.xs, bottom: Space.xxs })
        }
        if (this.page === 'voice') {
          VoiceInputPanel({ onBack: () => this.page = 'chat', onInsert: (value: string) => this.insertVoice(value) })
        } else if (this.page === 'share') {
          ShareImportPanel({ shareId: this.shareId, parts: this.shareParts, destination: this.shareDestination, busy: this.savingShare,
            attachments: this.shareAttachments, uploading: this.uploadingShare, uploadedCount: this.shareUploadedCount,
            error: this.shareError, onEdit: (id: number, value: string) => this.editSharePart(id, value),
            onRemove: (id: number) => this.removeSharePart(id),
            onRemoveAttachment: (id: string) => this.removeShareAttachment(id), onCancelUpload: () => this.cancelShareUpload(),
            loadThumbnail: (shareId: number, attachmentId: string, stillSelected: () => boolean): Promise<image.PixelMap> =>
              this.previewShareAttachment(shareId, attachmentId, stillSelected),
            onConfirm: () => { void this.confirmShare(); },
            onChooseDestination: () => {
              this.shareError = ''; this.openProjectPicker(true);
            }, onCancel: () => { removeIncomingShare(this.shareId); this.page = 'sessions'; } })
        } else if (this.page === 'settings') {
          SettingsPanel({ environments: this.environmentEntries, projects: this.scopedProjects, connection: client, connectionReady: this.ready,
            activeLocalId: this.selectedLocalId,
            scheduledConnectionKey: this.scheduledConnectionKey,
            settingsWriteAllowed: this.settingsWriteAllowed,
            embedded: true, bottomInset: 88,
            connectionFor: (localId: string): T3Client | undefined => this.registry().clients.get(localId), section: $settingsSection, groupingMode: workspacePrefs.projectGroupingMode, projectCount: this.projectGroups.length,
            archivedCount: this.archivedThreadCount(), environmentCount: this.environmentEntries.filter((entry: EnvironmentEntry) => !entry.deleting).length,
            onBack: () => this.page = 'sessions', onEnvironments: () => this.openPanel('server'),
            onProjects: () => this.openProjectOverview(), onArchive: () => this.openArchive(),
            onGrouping: (mode: string) => this.chooseGrouping(mode),
            workingShelfEnabled: this.shelves.workingShelfEnabled,
            onWorkingShelf: async (enabled: boolean): Promise<void> => {
              await setWorkingShelfEnabled(enabled);
              this.rebuildWorkspace();
            } })
        } else if (this.page === 'home-pulls') {
          PullRequestsPanel({ connection: client,
            environments: this.environmentEntries,
            projects: this.scopedProjects,
            activeLocalId: this.selectedLocalId,
            connectionFor: (localId: string): T3Client | undefined => this.registry().clients.get(localId),
            projectId: '', projectLabel: '',
            embedded: true, bottomInset: 88,
            onDetailChange: (open: boolean) => { this.homeTabDetailOpen = open; },
            onBack: () => { this.homeTabDetailOpen = false; this.page = 'sessions'; },
            onStatus: (value: string) => this.status = value,
            onCopy: (value: string) => { void this.copy(value); } })
        } else if (this.page === 'usage') {
          UsagePanel({ connection: client, environments: this.environmentEntries,
            connectionFor: (localId: string): T3Client | undefined => this.registry().clients.get(localId),
            embedded: true, bottomInset: 88,
            onDetailChange: (open: boolean) => { this.homeTabDetailOpen = open; },
            onBack: () => { this.homeTabDetailOpen = false; this.page = 'sessions'; } })
        } else if (this.page === 'choose-project') {
        ProjectPicker({ groups: this.pickerGroups(), environments: this.pickerEnvironments(), shareTarget: this.choosingShare,
          drafts: this.choosingShare ? [] : this.draftRecords.filter((draft: ComposerDraft) =>
            draft.draftId !== this.pendingDraftId &&
            (!draft.localId || this.environmentEntries.some((entry: EnvironmentEntry) => entry.localId === draft.localId))),
          environmentId: this.pickerEnvironmentId, query: this.pickerQuery,
          scratchAvailable: !this.choosingShare && this.pickerEnvironments().some((environment) => !!environment.scratchWorkspaceRoot && environment.ready),
          busy: this.busy, onBack: () => this.closeProjectPicker(),
          onAddProject: () => { if (this.choosingShare) this.openPanel('server'); else this.openAddProject('choose-project'); },
          onSelect: (project: ScopedProject) => { void this.chooseProject(project); },
          onScratch: (environmentId: string) => { void this.startScratch(environmentId); },
          onResumeDraft: (draft: ComposerDraft) => { void this.resumeDraft(draft); },
          onDeleteDraft: (draft: ComposerDraft) => {
            AlertDialog.show({ title: '删除草稿？', message: '仅删除本机草稿「' + composerDraftLabel(draft).slice(0, 100) + '」。',
              primaryButton: { value: '取消', action: () => {} },
              secondaryButton: { value: '删除', action: () => { void this.deleteDraft(draft.draftId).then(() => this.status = '草稿已删除'); } } });
          },
          onQuery: (value: string) => this.pickerQuery = value,
          onEnvironment: (environmentId: string) => this.pickerEnvironmentId = environmentId })
      } else if (this.page === 'add-project') {
        AddProjectPanel({ environments: this.workspace().addEnvironments(),
          initialEnvironmentId: this.addProjectEnvironmentId, actions: this.workspace(),
          onClose: () => this.page = this.addProjectReturn,
          onEnvironments: () => this.openPanel('server'),
          onOpenProject: (project: ScopedProject) => { void this.openProjectAfterCreate(project); } })
      } else if (this.page === 'project-overview') {
        ProjectOverviewPanel({ groups: this.projectGroups, groupKey: this.overviewGroupKey,
          onAddProject: () => this.openAddProject('project-overview'),
          canOrganize: this.canOrganize(this.selectedGroup()), busy: this.busy,
          onBack: () => this.page = 'settings',
          onSelectGroup: (key: string) => this.overviewGroupKey = key,
          onRename: (group: ProjectGroup, title: string) => this.renameGroup(group, title),
          onPin: (group: ProjectGroup, pinned: boolean) => this.pinGroup(group, pinned),
          onArchive: (group: ProjectGroup, archived: boolean) => this.archiveGroup(group, archived),
          onRemoveCheckout: (project: ScopedProject) => this.confirmRemoveCheckout(project),
          onRemoveProject: (group: ProjectGroup) => this.confirmRemoveProject(group) })
      } else if (this.page === 'archive') {
        ArchivePanel({ groups: this.archiveGroups, environments: this.environmentEntries.filter((entry: EnvironmentEntry) => !entry.deleting),
          environmentId: this.archiveEnvironmentId, query: this.archiveQuery, sortOrder: this.archiveSort,
          loading: this.archiveLoading, busy: this.busy, nowMs: this.nowMs,
          onBack: () => this.page = 'settings',
          onEnvironment: (environmentId: string) => { this.archiveEnvironmentId = environmentId; this.rebuildArchiveGroups(); },
          onQuery: (value: string) => { this.archiveQuery = value; this.rebuildArchiveGroups(); },
          onSort: (value: string) => { this.archiveSort = value; this.rebuildArchiveGroups(); },
          onRefresh: () => { void this.loadArchive(); },
          onOpen: (thread: ScopedThread) => { void this.openArchivedThread(thread); },
          onUnarchive: (thread: ScopedThread) => {
            this.busy = true;
            void this.workspace().unarchive(thread).catch((error: Error) => this.status = error.message)
              .finally(() => { this.busy = false; void this.loadArchive(); });
          },
          onDelete: (thread: ScopedThread) => {
            AlertDialog.show({ title: '删除归档会话？', message: '“' + thread.label + '”将被永久删除。',
              primaryButton: { value: '取消', action: () => {} },
              secondaryButton: { value: '删除', action: () => {
                this.busy = true;
                void this.workspace().deleteThread(thread).catch((error: Error) => this.status = error.message)
                  .finally(() => { this.busy = false; void this.loadArchive(); });
              } } });
          } })
      } else if (this.page === 'device-picker') {
        DevicePickerPanel({ connection: this.previewConnection, threadId: this.previewThreadId,
          onOpen: (device: DevicePreviewChoice, hubPath: string, kind: string): Promise<void> => this.openDevice(device, hubPath, kind),
          onBack: () => this.page = 'chat' })
      } else if (this.page === 'android-device' && this.deviceChoice) {
        AndroidDevicePanel({ deviceName: this.deviceChoice.name, hostLabel: this.deviceChoice.hostLabel,
          canOperate: (): boolean => this.previewCurrent() && client.canScope('orchestration:operate') !== false,
          setOrientation: async (value: string): Promise<void> => {
            if (!this.previewCurrent() || !this.deviceChoice || client.canScope('orchestration:operate') === false ||
              !['portrait', 'landscape_left', 'portrait_upside_down', 'landscape_right'].includes(value)) throw new Error('设备目标或权限已变化');
            await client.rpcRequest('device.action', { hostId: this.deviceChoice.hostId, deviceId: this.deviceChoice.id,
              type: 'setOrientation', value } as DeviceActionPayload, 15000, false);
          },
          prepareConnection: () => this.rebindPreviewConnection(), isCurrent: (): boolean => this.previewCurrent(),
          getStreamUrl: async (): Promise<string> => {
            if (!this.previewCurrent() || !this.deviceChoice) throw new Error('设备环境已变化');
            return this.previewConnection!.androidDeviceStreamUrl(this.deviceHubPath, this.deviceChoice.hostId, this.deviceChoice.id);
          }, onBack: () => this.page = 'device-picker' })
      } else if (this.page === 'device-preview' && this.deviceChoice) {
        DevicePreviewPanel({ deviceName: this.deviceChoice.name, hostLabel: this.deviceChoice.hostLabel,
          platform: this.deviceChoice.platform, prepareConnection: () => this.rebindPreviewConnection(), isCurrent: (): boolean => this.previewCurrent(),
          getAccess: async (): Promise<DeviceStreamAccess> => {
            if (!this.previewCurrent() || !this.deviceChoice) throw new Error('设备环境已变化');
            return this.previewConnection!.deviceStreamAccess(this.deviceHubPath, this.deviceChoice.hostId, this.deviceChoice.id);
          }, onBack: () => this.page = 'device-picker' })
      } else if (this.page === 'preview') {
        PreviewPanel({ initialUrl: this.previewAddress, initialTabId: this.previewTabs.get(this.previewKey) || '',
          createTab: (address: string): Promise<string> => this.createPreviewTab(address),
          resizeTab: async (tabId: string, viewport: PreviewResizeViewport): Promise<PreviewViewport> => {
            if (!this.previewCurrent() || client.canScope('preview:operate') === false) throw new Error('预览环境或权限已变化');
            const owner = this.previewConnection!; const threadId = this.previewThreadId;
            const result = await owner.rpcRequest('preview.resize', previewResizeInput(threadId, tabId, viewport), 15000, false);
            if (!this.previewCurrent() || owner !== this.previewConnection || threadId !== this.previewThreadId) throw new Error('预览环境已变化');
            return verifyPreviewResize(result, threadId, tabId, viewport);
          },
          requiresZoomRepair: (): boolean => this.previewZoomRepairRequired(),
          zoomTab: (tabId: string, zoomFactor: number, viewport?: PreviewViewport,
            stillControlled?: () => boolean): Promise<PreviewZoomResult> =>
            this.adjustPreviewZoom(tabId, zoomFactor, viewport, stillControlled),
          watchTabs: (changed: () => void): (() => void) => {
            if (!this.previewCurrent()) throw new Error('预览环境已变化');
            const owner = this.previewConnection!;
            const threadId = this.previewThreadId;
            const listener = owner.watchRpcStream('subscribePreviewEvents', {} as Record<string, Object>, (value: Object): void => {
              if (this.previewCurrent() && owner === this.previewConnection && threadId === this.previewThreadId &&
                record(value).threadId === threadId) changed();
            });
            return (): void => owner.stopRpcStream(listener);
          },
          listTabs: async (): Promise<PreviewTab[]> => {
            if (!this.previewCurrent()) throw new Error('预览环境已变化');
            const owner = this.previewConnection!;
            const threadId = this.previewThreadId;
            const result = await owner.rpcRequest('preview.list', { threadId } as PreviewRefPayload, 15000, false);
            if (!this.previewCurrent() || owner !== this.previewConnection || threadId !== this.previewThreadId) {
              throw new Error('预览环境已变化');
            }
            return previewTabs(result, threadId);
          },
          streamUrl: async (tabId: string): Promise<string> => {
            if (!this.previewCurrent()) throw new Error('预览环境已变化');
            return this.previewConnection!.previewStreamUrl(this.previewThreadId, tabId);
          }, closeTab: async (tabId: string): Promise<void> => {
            if (!this.previewCurrent() || client.canScope('preview:operate') === false) throw new Error('预览环境或权限已变化');
            await client.rpcRequest('preview.close', { threadId: this.previewThreadId, tabId } as PreviewRefPayload, 15000, false);
          }, prepareConnection: () => this.rebindPreviewConnection(), isCurrent: (): boolean => this.previewCurrent(),
          onTab: (tabId: string) => { this.previewTabs.set(this.previewKey, tabId); },
          onBack: () => this.page = 'chat' })
      } else if (this.page === 'terminal') {
        TerminalPanel({ threadId: this.terminalThreadId,
          onCopy: async (value: string): Promise<void> => {
            this.terminalOwner();
            await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, value));
          },
          canOperate: (): boolean => {
            try { return this.terminalOwner().canScope('terminal:operate') !== false; } catch (_) { return false; }
          },
          watchTerminals: (receive: (value: Object) => void, failed: (message: string) => void): (() => void) =>
            this.terminalOwner().watchTerminals(receive, failed),
          attach: (terminalId: string, size: TerminalSize, resume: boolean, receive: (value: Object) => void,
            failed: (message: string) => void): (() => void) => {
            const owner = this.terminalOwner();
            const threadId = this.terminalThreadId;
            if (owner.canScope('terminal:operate') === false) {
              return owner.attachTerminal({ threadId, terminalId } as TerminalRefPayload, receive, failed, true);
            }
            return owner.attachTerminal({ threadId, terminalId, cwd: this.terminalCwd,
              cols: size.cols, rows: size.rows, resume, restartIfNotRunning: !resume,
              maxHistoryBytes: 524288 } as TerminalAttachPayload, receive, failed);
          },
          write: async (terminalId: string, data: string): Promise<void> => {
            const owner = this.terminalOwner();
            if (!terminalAccess(owner.canScope('terminal:read'), owner.canScope('terminal:operate')).canOperate) throw new Error('此连接无权操作终端');
            await owner.rpcRequest('terminal.write', terminalInput(this.terminalThreadId, terminalId, data), 15000, false);
          },
          reply: async (terminalId: string, data: string): Promise<void> => {
            const owner = this.terminalOwner();
            if (!terminalAccess(owner.canScope('terminal:read'), owner.canScope('terminal:operate')).canOperate) throw new Error('此连接无权操作终端');
            const payload = record(terminalInput(this.terminalThreadId, terminalId, data));
            payload.reply = true;
            await owner.rpcRequest('terminal.write', payload, 15000, false);
          },
          resize: async (terminalId: string, size: TerminalSize): Promise<void> => {
            const owner = this.terminalOwner();
            if (owner.canScope('terminal:operate') === false) throw new Error('此连接无权操作终端');
            await owner.rpcRequest('terminal.resize', { threadId: this.terminalThreadId, terminalId,
              cols: size.cols, rows: size.rows } as TerminalResizePayload, 15000, false);
          },
          closeTerminal: async (terminalId: string): Promise<void> => {
            const owner = this.terminalOwner();
            if (owner.canScope('terminal:operate') === false) throw new Error('此连接无权操作终端');
            await owner.rpcRequest('terminal.close', { threadId: this.terminalThreadId, terminalId,
              deleteHistory: false } as TerminalClosePayload, 15000, false);
          }, onBack: () => this.page = 'chat' })
      } else if (this.page === 'files') {
        FilesPanel({ cacheScope: this.selectedLocalId, connection: client, cwd: this.currentWorkspace(),
          threadId: this.draftMode ? '' : this.threadId,
          title: this.draftMode ? '草稿文件' : '文件与源码',
          onBack: () => this.page = 'chat',
          onCompose: (value: Object, label: string) => this.addExternalContext(value, label),
          onCopy: (value: string) => { void this.copy(value); },
          onStatus: (value: string) => this.status = value })
      } else if (this.page === 'review') {
        ReviewPanel({ connection: client, cwd: this.currentWorkspace(), threadId: this.threadId,
          onBack: () => this.page = 'chat',
          onCompose: (value: Object, label: string) => this.addExternalContext(value, label),
          onCopy: (value: string) => { void this.copy(value); },
          onStatus: (value: string) => this.status = value })
      } else if (this.page === 'git') {
        GitPanel({ connection: client, cwd: this.currentWorkspace(), threadId: this.threadId,
          projectId: this.projectId,
          onBack: () => this.page = 'chat', onStatus: (value: string) => this.status = value })
      } else if (this.page === 'pull-requests') {
        PullRequestsPanel({ connection: client, projectId: this.projectId,
          projectLabel: this.projects.find((project: ProjectView) => project.id === this.projectId)?.label || '',
          onBack: () => this.page = 'chat', onStatus: (value: string) => this.status = value,
          onCopy: (value: string) => { void this.copy(value); } })
        } else if (this.page === 'chat') {
          Row({ space: Space.xxs }) {
            IconButton({ icon: $r('app.media.ui_back'), label: '返回会话列表', onTap: () => { this.page = 'sessions'; } })
            Column() {
              Text(this.draftMode ? '新任务' : this.threads.find((t: ThreadView) => t.id === this.threadId)?.label || this.cachedChatTitle || '会话')
                .fontSize(FontSize.headline).lineHeight(LineHeight.headline).fontWeight(Weight.semibold)
                .fontColor($r('app.color.ink')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              Row({ space: 3 }) {
                Text((this.projects.find((p: ProjectView) => p.id === this.projectId)?.label || this.cachedChatProject || 'No project') + ' · ' +
                  (this.environmentEntries.find((e: EnvironmentEntry) => e.localId === this.selectedLocalId)?.label || '环境'))
                  .fontSize(FontSize.caption).lineHeight(LineHeight.caption)
                  .fontColor($r('app.color.muted')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .constraintSize({ maxWidth: '92%' })
                if (this.draftMode) {
                  Image($r('app.media.ui_chevron_right')).width(10).height(10).opacity(0.6).accessibilityLevel('no')
                }
              }.alignItems(VerticalAlign.Center)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.Center)
              .padding({ left: Space.xxs }).accessibilityGroup(true)
              .accessibilityDescription(this.draftMode ? '点击切换项目' : '')
              .onClick(() => { if (this.draftMode) this.openProjectPicker(false, true); })
            if (!this.draftMode) {
              IconButton({
                icon: $r('app.media.ui_terminal'),
                label: '打开终端',
                disabled: !this.threadTerminalEnabled,
                onTap: () => {
                  this.terminalConnection = client;
                  this.terminalThreadId = this.threadId;
                  this.terminalCwd = this.currentWorkspace();
                  this.panelOpen = false;
                  this.page = 'terminal';
                }
              })
            }
            IconButton({ icon: $r('app.media.ui_more'), label: '会话操作', onTap: () => this.openPanel('thread') })
          }.width('100%').constraintSize({ minHeight: Sizes.topBar }).padding({ left: Space.xs, right: Space.xs })
            .alignItems(VerticalAlign.Center)
          Column() {
            if (this.showChatStatusBanner()) {
              Text(this.status).fontSize(FontSize.caption).lineHeight(LineHeight.caption)
                .fontColor($r('app.color.muted')).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%').padding({ left: Space.md, right: Space.md, top: Space.xs, bottom: Space.xxs })
                .accessibilityText('状态：' + this.status).onClick(() => this.openPanel('thread'))
            }
            this.chatPage()
          }.width('100%').layoutWeight(1).backgroundColor($r('app.color.screen'))
            .borderRadius({ topLeft: 26, topRight: 26 }).clip(true)
        } else {
          Row({ space: 4 }) {
            Button({ type: ButtonType.Normal }) {
              if (this.homeShowReconnectingHeader()) {
                Row({ space: 6 }) {
                  LoadingProgress().width(16).height(16).color($r('app.color.muted'))
                  Text(this.homeConnectionLabel())
                    .fontSize(FontSize.headline).fontWeight(Weight.semibold).fontColor($r('app.color.muted'))
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }.alignItems(VerticalAlign.Center)
              } else if (this.homeShowOfflineHeader()) {
                Row({ space: 6 }) {
                  Circle().width(7).height(7).fill($r('app.color.warning'))
                  Text(this.homeConnectionLabel())
                    .fontSize(FontSize.headline).fontWeight(Weight.semibold).fontColor($r('app.color.muted'))
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }.alignItems(VerticalAlign.Center)
              } else {
                Row({ space: 5 }) {
                  Text('T3').fontSize(FontSize.title).fontWeight(Weight.bold).fontColor($r('app.color.ink'))
                  Text('Code').fontSize(FontSize.title).fontWeight(Weight.regular).fontColor($r('app.color.muted'))
                }.alignItems(VerticalAlign.Center)
              }
            }.constraintSize({ minHeight: Sizes.iconHit }).padding({ left: Space.xxs, right: Space.xs })
              .backgroundColor(Color.Transparent)
              .accessibilityText((this.homeShowReconnectingHeader() || this.homeShowOfflineHeader())
                ? (this.homeConnectionLabel() + '，管理环境') : 'T3 Code，管理环境')
              .onClick(() => this.openPanel('server'))
            Blank()
            IconButton({ icon: $r('app.media.ui_search'), label: '搜索会话', onTap: () => this.toggleHomeSearch() })
            Stack({ alignContent: Alignment.TopEnd }) {
              IconButton({ icon: $r('app.media.ui_filter'),
                label: (this.environmentFilter || this.projectFilterKey) ? '筛选环境与项目，已启用' : '筛选环境与项目',
                onTap: () => this.openPanel('filter') })
              if (this.environmentFilter || this.projectFilterKey) {
                Circle().width(6).height(6).fill($r('app.color.primary')).margin({ top: 7, right: 7 })
                  .hitTestBehavior(HitTestMode.None)
              }
            }
          }.width('100%').constraintSize({ minHeight: Sizes.topBar }).padding({ left: Space.md, right: Space.sm })
          Column() {
            if (this.showHomeStatusBanner()) {
              Text(this.status).fontSize(FontSize.caption).lineHeight(LineHeight.caption)
                .fontColor($r('app.color.muted')).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%').padding({ left: Space.md, right: Space.md, top: Space.sm, bottom: Space.xxs })
                .accessibilityText('状态：' + this.status).onClick(() => this.openPanel('server'))
            }
            this.sessionsPage()
          }.width('100%').layoutWeight(1).backgroundColor($r('app.color.screen'))
            .borderRadius({ topLeft: 26, topRight: 26 }).clip(true)
        }
      }.width('100%').height('100%')
      if (this.undoNotice || this.showHomeBottomBar()) {
        Column({ space: Space.xs }) {
          if (this.undoNotice) {
            Row({ space: 10 }) {
              Text(this.undoNotice.label).fontSize(FontSize.callout).fontColor($r('app.color.ink')).layoutWeight(1)
              Button('撤销').height(34).backgroundColor(Color.Transparent).fontColor($r('app.color.ink')).fontWeight(Weight.medium)
                .onClick(() => { void this.executeUndo(); })
              Button('×').height(34).width(34).backgroundColor(Color.Transparent).fontColor($r('app.color.muted'))
                .onClick(() => { this.undoNotice = undefined; })
            }.width('100%').padding({ left: Space.md, right: Space.sm, top: Space.xs, bottom: Space.xs })
              .margin({ left: this.isRootTab() ? Space.md : 0, right: this.isRootTab() ? Space.md : 0, bottom: this.showHomeBottomBar() ? 0 : Space.sm })
              .backgroundColor($r('app.color.card')).borderRadius(Radius.card)
              .border({ width: 0.5, color: $r('app.color.border') })
              .shadow({ radius: 12, color: '#1a000000', offsetX: 0, offsetY: 2 })
          }
          if (this.showHomeBottomBar()) {
            HomeBottomBar({ activeTab: this.activeHomeTab(),
              onSelectTab: (tab: HomeTab) => this.selectHomeTab(tab),
              onNewTask: () => { void this.startNewTask(); } })
          }
        }.width('100%').hitTestBehavior(HitTestMode.Transparent)
      }
    }.width('100%').height('100%')
      .focusable(true).onKeyEvent((event: KeyEvent) => { this.keyboardEvent(event, false); })
      .backgroundColor($r('app.color.group'))
      .foregroundColor($r('app.color.ink'))
      .bindSheet($$this.panelOpen, this.panelContent(), { height: this.panel === 'thread' ? '66%' :
        this.panel === 'attachment' ? '80%' :
        this.panel === 'extras' || this.panel === 'agents' ? '62%' :
        this.panel === 'background-work' ? '52%' :
        this.panel === 'composer-command' ? '78%' :
        this.panel === 'paste-context' ? '48%' : this.panel === 'markdown-image' ? '80%' :
        this.panel === 'rename' ? '36%' : this.panel === 'filter' ? '58%' :
        this.panel === 'cloud' || this.panel === 'snooze' ? '85%' : '70%',
        showClose: false,
        onWillDismiss: (action: DismissSheetAction) => { if (this.panel !== 'peer-link' || !this.busy) action.dismiss(); },
        backgroundColor: $r('app.color.group') })
  }
}
