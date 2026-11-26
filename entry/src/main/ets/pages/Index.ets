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
  previewResizeInput, verifyPreviewResize, previewZoomInput, previewZoomTarget, verifyPreviewZoom, previewNeedsZoomRepair, repairPreviewZoom100,
  ThreadPreviewTabsState, emptyThreadPreviewTabsState, applyPreviewListResult, applyPreviewEvent } from '../protocol/Preview';
import { ShareImportPanel } from '../components/ShareImportPanel';
import { loadStagedShareThumbnail, peekIncomingShare, removeIncomingShare, removeIncomingShareAttachment, withStagedShareAttachment } from '../services/ShareInbox';
import { IncomingShareAttachment, MAX_SHARED_TEXT_CHARS, SharePart, shareDraftText } from '../protocol/IncomingShare';
import { TerminalPanel } from '../components/TerminalPanel';
import { TerminalSize, terminalInput, terminalAccess } from '../protocol/Terminal';
import {
  TaskSettings, ModelSelection, OptionSelection, QueuedRun, queuedRuns, validateTaskSettings, modelOptionsSummary,
  ModelFavoriteEntry,
  CompactEditorGeometry, ExpandedModelLayout, shouldExpandComposer, resolveCompactEditorGeometry, layoutExpandedModelControl,
  composerAttachmentKind
} from '../protocol/Composer';
import { BranchView, branches, ComposerContextRecord, ComposerDraft, composerDraftLabel, composerDraft, contextRecord,
  draftSettings, emptyWorkspace, DraftWorkspace, switchDraftWorkspaceMode, draftWorkspaceForBranch, mentionContext, skillContext, attachmentLimitError,
  terminalContext, R4_MAX_CONTEXT_RECORDS,
  BranchView as R4Branch, proposedPlans, PlanView, SubagentView, GuestShareView, GuestMessageView,
  BackgroundTaskView, tokenUsage, TokenUsage, DraftAttachment } from '../protocol/R4';
import {
  ComposerInlineTrigger, deterministicEnvironmentContext, deterministicFileContext, deterministicThreadContext,
  detectInlineMentionTrigger, extractMentionModelCandidates, formatComposerModelMention,
  matchMentionEnvironments, matchMentionModels, matchMentionThreads,
  MentionEnvironmentCandidate, MentionFileEntry, mentionFileItems, MentionItem,
  parseComposerContextHref, replaceTextRange
} from '../protocol/Mentions';
import { draftStore } from '../storage/DraftStore';
import { ComposerCommandPanel } from '../components/ComposerCommandPanel';
import { ComposerAttachmentStrip } from '../components/ComposerAttachmentStrip';
import { ComposerMentionPopover } from '../components/ComposerMentionPopover';
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
import { HtmlRenderEntry, htmlRenderFileName } from '../protocol/HtmlRender';
import { HtmlRenderWebView } from '../components/HtmlRenderView';
import { classifyMarkdownLink, resolveFileLinkForWorkspace, ThreadLinkTarget } from '../protocol/MarkdownLinks';
import { isHtml } from '../protocol/Files';
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
import { ChatAttachment, ChatMessage, objects, optionalRecord, parseModelSelection, record, text } from '../protocol/Wire';
import { MarkdownMediaBlock, MarkdownView } from '../components/MarkdownView';
import { classifyMarkdownMediaSource, ResolvedMarkdownMedia } from '../protocol/Markdown';
import { canSaveToPhotoGallery, mediaCopyLabel, mediaCopyValue, mediaFileName } from '../protocol/MediaTransfer';
import {
  decodeDataUriBytes,
  readLocalFileUriBytes,
  saveBytesToDocumentPicker,
  saveBytesToPhotoGallery,
  shareBytesWithSystemSheet
} from '../services/MediaActions';
import { FilesPanel } from '../components/FilesPanel';
import { ReviewPanel } from '../components/ReviewPanel';
import { GitPanel } from '../components/GitPanel';
import { PullRequestsPanel } from '../components/PullRequestsPanel';
import { picker, fileIo, fileUri } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { Attachment, Choice, ModelChoice, ActionCard, cards, LinkRequestView, linkRequests, linkAccessChoices } from '../protocol/Core';
import { MessageSource } from '../components/MessageSource';
import { RequestCard } from '../components/RequestCard';
import { pasteboard } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { cloud, CloudEnvironmentView, CloudManager, prepareCloud } from '../services/CloudManager';
import { startNetworkMonitor } from '../services/NetworkMonitor';
import { acceptPrivacyConsent, PRIVACY_POLICY_DETAIL, PRIVACY_POLICY_SUMMARY } from '../services/PrivacyConsent';
import { CloudAccountPanel } from '../components/CloudAccountPanel';
import { takeCloudCallback } from '../services/CloudCallbackInbox';
import { ClerkSsoProvider, CloudDevice, CloudPairingLink, DEFAULT_SSO_PROVIDERS, deviceApprovalPrompts } from '../protocol/Cloud';
import {
  ArchiveEnvironmentEntry, ArchiveProjectGroup, ProjectGroup, ProjectView, ScopedProject, ScopedThread, ThreadCapabilities,
  ThreadProjectRef, ThreadShelfState, ThreadView, attachPendingSubagentRequests, buildArchiveGroups, buildProjectGroups, buildThreadShelves,
  isListedThread, newTaskDestination, pickableProjectGroups, projectGroupRefs, samePath, scopedProjectView, scopedThreadView,
  sortProjectGroups, threadView, topOfPinnedRun
} from '../protocol/Projects';
import {
  WorktreeRepositoryChoice,
  resolveWorktreeRepositorySelection,
  worktreeRepositoryChoices
} from '../protocol/ThreadRepositories';
import {
  linkedManualReasonMessage,
  LinkedThreadTarget,
  ParsedThreadLink,
  parseThreadLinkHref,
  peerLinkRemoveMessage,
  prepareLinkedEnvironmentConnection,
  resolveLinkedThreadOpen,
  threadLinkCandidates
} from '../protocol/LinkedThread';
import {
  AgentFeedbackAnswer,
  AgentFeedbackRequestView,
  agentFeedbackErrorMessage,
  parseAgentFeedbackRequests
} from '../protocol/AgentFeedback';
import { FeedbackRequestCard } from '../components/FeedbackRequestCard';
import {
  extractMcpAppEntries,
  McpAppEntry,
  McpSignInNoticeView,
  parseMcpSignInNotices
} from '../protocol/McpApp';
import { McpSignInPanel } from '../components/McpSignInPanel';
import { McpAppView } from '../components/McpAppView';
import { LinkedThreadPanel } from '../components/LinkedThreadPanel';
import {
  parseSideThreadOpenTarget,
  popSideThreadReturn,
  pushSideThreadReturn,
  resolveSideThreadOpenTarget,
  sideChatsForThread,
  sideThreadKindOf,
  SideThreadKind,
  SideThreadOpenIntent,
  SideThreadReturnPoint,
  SideThreadTarget
} from '../protocol/SideThread';
import { SideThreadPanel } from '../components/SideThreadPanel';
import { LinkSeveralEnvironmentsPanel } from '../components/LinkSeveralEnvironmentsPanel';
import { WorkspaceActions, WorkspaceUndo } from '../services/Workspace';
import {
  localModelFavorites,
  rememberThreadProject,
  saveWorkspacePreferences,
  setLocalModelFavorite,
  setWorkingShelfEnabled,
  workspacePrefs
} from '../services/WorkspacePrefs';
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
interface MentionSearchThreadsPayload { query: string; limit: number; titlesOnly: boolean; }
interface MentionGroupsView {
  threads: MentionItem[];
  environments: MentionItem[];
  models: MentionItem[];
  files: MentionItem[];
}
interface TerminalClosePayload { threadId: string; terminalId: string; deleteHistory: boolean; }
interface ProjectUpdatePatch { title?: string; pinned?: boolean; archived?: boolean; }
interface ShareUploadPlan {
  shareId: number; draftId: string; localId: string; environmentId: string; projectId: string;
  uploaded: Map<string, DraftAttachment>;
}

interface MediaCacheEntry {
  full: string;
  mtime: number;
}

@Entry
@Component
struct Index {
  private keyboard: KeyboardCommands = new KeyboardCommands();
  private composerController: TextAreaController = new TextAreaController();
  @State composerFocused: boolean = false;
  @State composerExpanded: boolean = false;
  @State composerRowWidth: number = 0;
  @State compactSlotLeft: number = 0;
  @State compactSlotWidth: number = 0;
  @State expandedModelSlotWidth: number = 0;
  @State searchFocused: boolean = false;
  private composingText: boolean = false;
  private composerPreviewText: string = '';
  private lastComposerEditorHeight: number = 0;

  @StorageLink('t3PrivacyAccepted') privacyAccepted: boolean = true;
  @State privacyDetailExpanded: boolean = false;
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
  @State environmentApprovalCodes: Record<string, string> = {};
  @State loaded: boolean = false;
  @State canResumeLatestRun: boolean = false;
  private pickers: Map<string, AttachmentPicker> = new Map();
  @State linkItems: LinkRequestView[] = [];
  @State feedbackItems: AgentFeedbackRequestView[] = [];
  @State mcpSignInNotices: McpSignInNoticeView[] = [];
  @State activeMcpSignIn: McpSignInNoticeView | undefined = undefined;
  @State mcpAppEntries: McpAppEntry[] = [];
  @State fullscreenMcpApp: McpAppEntry | undefined = undefined;
  @State localFavorites: ModelFavoriteEntry[] = [];
  @State gitBannerThreadKey: string = '';
  @State gitBannerText: string = '';
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
  private previewAutoConnect: boolean = false;
  private previewTabs: Map<string, string> = new Map();
  private browserPreviewWatchKey: string = '';
  private browserPreviewWatchGeneration: number = 0;
  private browserPreviewWatchOwner: T3Client | undefined = undefined;
  private browserPreviewWatchListener: ((value: Object) => void) | undefined = undefined;
  private browserPreviewState: ThreadPreviewTabsState = emptyThreadPreviewTabsState();
  private browserPreviewListing: boolean = false;
  private browserPreviewListAgain: boolean = false;
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
  @State @Watch('onPageChanged') page: string = 'sessions';
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
  @State draftRepoChoices: WorktreeRepositoryChoice[] = [];
  @State draftRepoChoicesLoaded: boolean = true;
  @State draftIsGitRepo: boolean = true;
  private draftRepoRequest: number = 0;
  @State linkedThreadTarget: LinkedThreadTarget | undefined = undefined;
  @State linkedConnecting: boolean = false;
  @State linkedConnectNotice: string = '';
  @State linkedConnectError: boolean = false;
  @State linkedConnectTarget: LinkedThreadTarget | undefined = undefined;
  @State sideThreadTarget: SideThreadTarget | undefined = undefined;
  @State sideThreadReturnStack: SideThreadReturnPoint[] = [];
  @State linkBatchSourceLocalId: string = '';
  private chatScrollIndex: number = 0;
  private pendingScrollRestore: SideThreadReturnPoint | undefined = undefined;
  @State commandPanel: string = '';
  @State commandQuery: string = '';
  @State mentionFiles: string[] = [];
  @State mentionFileEntries: MentionFileEntry[] = [];
  @State mentionExtraThreads: ScopedThread[] = [];
  @State mentionLoading: boolean = false;
  @State mentionLinkedLabels: Record<string, string> = {};
  @State inlineMentionTrigger: ComposerInlineTrigger | undefined = undefined;
  @State inlineMentionItems: MentionItem[] = [];
  @State inlineMentionLoading: boolean = false;
  private inlineMentionDismissedKey: string = '';
  private composerCursor: number = 0;
  private composerSelectionEnd: number = 0;
  private mentionSearchTimer: number = 0;
  private mentionSearchSeq: number = 0;
  private inlineMentionTimer: number = 0;
  private inlineMentionSeq: number = 0;
  private inlineMentionFileEntries: MentionFileEntry[] = [];
  private inlineMentionExtraThreads: ScopedThread[] = [];
  private inlineMentionLastQuery: string = '';
  private inlineMentionLastCwd: string = '';
  @State attachments: DraftAttachment[] = [];
  @State attachmentPreviewMap: Record<string, string> = {};
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
  @State htmlViewerEntry: HtmlRenderEntry | undefined = undefined;
  @State htmlViewerUri: string = '';
  @State htmlViewerError: string = '';
  @State htmlViewerAttempt: number = 0;
  @State filesOverrideCwd: string = '';
  @State filesInitialPath: string = '';
  @State filesInitialDir: string = '';
  @State filesInitialLine: number = 0;
  @State filesDirectFileOnly: boolean = false;
  @State markdownImageUrl: string = '';
  @State markdownImageKind: string = 'image';
  @State markdownImagePath: string = '';
  @State markdownImageAlt: string = '';
  @State markdownImageSource: string = '';
  @State markdownImageStatus: string = '';
  @State markdownImageBusy: boolean = false;
  private markdownImageOwner: T3Client | undefined = undefined;
  private markdownImageThreadId: string = '';
  private markdownImageCwd: string = '';
  private markdownImageScopeId: string = '';
  @State promptSuggestion: string = '';
  @State draftEnvironmentError: string = '';
  @State pendingDraftId: string = '';
  private draftSaveTimer: number = 0;
  @State @Watch('onComposerChromeChanged') sendMode: string = 'auto';
  @State queued: QueuedRun[] = [];
  @State threadId: string = '';
  @State @Watch('onPromptStateChanged') prompt: string = '';
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
  @State cloudAccountEmail: string = '';
  @State cloudAccountDisplayName: string = '';
  @State cloudDeviceCode: string = '';
  @State cloudRelayUrl: string = '';
  @State cloudPublishableKey: string = '';
  @State cloudJwtTemplate: string = '';
  @State cloudCustomConfig: boolean = false;
  @State cloudShowOnboarding: boolean = false;
  @State cloudStatus: string = '';
  @State cloudError: string = '';
  @State cloudBusy: boolean = false;
  @State cloudRefreshing: boolean = false;
  @State cloudEnvironments: CloudEnvironmentView[] = [];
  @State cloudSsoProviders: ClerkSsoProvider[] = DEFAULT_SSO_PROVIDERS.slice();
  @State cloudEmailCodeEnabled: boolean = true;
  @State cloudPasswordEnabled: boolean = true;
  @State cloudPendingSsoStrategy: string = '';
  @State cloudSignInStep: string = '';
  @State cloudSignInEmail: string = '';
  @State cloudCanUseEmailCode: boolean = false;
  @State cloudCanUsePassword: boolean = false;
  @State cloudSecondFactors: string[] = [];
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
    this.picker.setOnUploaded((uploaded: Attachment, bytes: ArrayBuffer) => {
      this.cacheComposerAttachmentPreview(uploaded, bytes);
    });
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
    this.localFavorites = localModelFavorites();
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
      this.feedbackItems = !this.draftMode && client.thread
        ? parseAgentFeedbackRequests(client.thread.items, client.thread.threadId) : [];
      this.mcpSignInNotices = !this.draftMode && client.thread
        ? parseMcpSignInNotices(client.thread.items, client.thread.threadId, client.thread.details, client.thread.providerThreads) : [];
      this.mcpAppEntries = !this.draftMode && client.thread
        ? extractMcpAppEntries(client.thread.items) : [];
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
        const snapshotTitle = client.thread && client.thread.threadId === this.threadId &&
          typeof client.thread.details['title'] === 'string'
          ? (client.thread.details['title'] as string).trim() : '';
        const resolvedTitle = matchedThread?.label || matchedScopedThread?.label || snapshotTitle;
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
      if (this.page === 'chat' && !this.draftMode && this.pendingScrollRestore &&
        this.pendingScrollRestore.localId === this.selectedLocalId &&
        this.pendingScrollRestore.threadId === this.threadId &&
        client.thread && client.thread.threadId === this.threadId && client.thread.cursor >= 0 && this.messages.length > 0) {
        const restore = this.pendingScrollRestore;
        this.pendingScrollRestore = undefined;
        const applyRestore = (): void => {
          if (!this.alive || this.page !== 'chat' || this.draftMode || this.threadId !== restore.threadId) return;
          if (restore.scrollY > 0) {
            this.scroller.scrollTo({ xOffset: 0, yOffset: restore.scrollY });
          } else if (restore.scrollIndex > 0) {
            this.scroller.scrollToIndex(restore.scrollIndex);
          }
          this.chatAwayFromBottom = this.messages.length > 0 && !this.scroller.isAtEnd();
        };
        setTimeout(applyRestore, 80);
        setTimeout(applyRestore, 240);
      } else if (this.page === 'chat' && !this.draftMode && this.pendingScrollBottomKey === currentThreadKey &&
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
      this.ensureBrowserPreviewWatch();
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
    this.cloudAccountEmail = manager.session?.email || '';
    this.cloudAccountDisplayName = manager.session?.displayName || '';
    this.cloudDeviceCode = manager.deviceCode;
    this.cloudRelayUrl = manager.config.relay.url;
    this.cloudPublishableKey = manager.config.clerk.publishableKey;
    this.cloudJwtTemplate = manager.config.clerk.jwtTemplate;
    this.cloudCustomConfig = manager.isCustomConfig;
    this.cloudShowOnboarding = manager.showOnboarding;
    this.cloudStatus = manager.status;
    const storedError = AppStorage.get<string>('t3CloudError') || '';
    this.cloudError = manager.error || storedError;
    if (storedError) AppStorage.setOrCreate('t3CloudError', '');
    this.cloudBusy = manager.busy;
    this.cloudRefreshing = manager.refreshing;
    this.cloudEnvironments = manager.environments.slice();
    this.cloudSsoProviders = manager.environmentInfo.socialProviders.slice();
    this.cloudEmailCodeEnabled = manager.environmentInfo.emailCodeEnabled;
    this.cloudPasswordEnabled = manager.environmentInfo.passwordEnabled;
    this.cloudPendingSsoStrategy = manager.pendingSsoStrategy;
    const attempt = manager.signInAttempt;
    if (attempt) {
      this.cloudSignInStep = attempt.status === 'needs_second_factor' ? 'needs_second_factor' : 'needs_first_factor';
      this.cloudSignInEmail = attempt.identifier;
      this.cloudCanUseEmailCode = attempt.supportedFirstFactors.some((item) => item.strategy === 'email_code');
      this.cloudCanUsePassword = attempt.supportedFirstFactors.some((item) => item.strategy === 'password');
      this.cloudSecondFactors = attempt.supportedSecondFactors.map((item) => item.strategy);
    } else {
      this.cloudSignInStep = '';
      this.cloudSignInEmail = '';
      this.cloudCanUseEmailCode = false;
      this.cloudCanUsePassword = false;
      this.cloudSecondFactors = [];
    }
  }
  private cloudAccountSummary(): string {
    if (this.cloudAccountEmail) return this.cloudAccountEmail;
    if (this.cloudAccountDisplayName) return this.cloudAccountDisplayName;
    return this.cloudAccountId;
  }
  private closeCloudPanel(): void {
    if (this.cloudReturnPanel) this.panel = this.cloudReturnPanel;
    else this.panelOpen = false;
  }
  private incomingCloudCallback(): void {
    if (!this.alive || this.busy || !cloud) return;
    const uri = takeCloudCallback();
    if (!uri) return;
    this.busy = true; this.cloudBusy = true;
    void this.cloudManager().completeCallback(uri).then(() => {
      this.bindEnvironment();
      if (!this.panelOpen || this.panel !== 'cloud') {
        this.openCloudPanel(this.panelOpen ? this.panel : '');
      }
    }).catch((error: Error) => {
      this.cloudError = error.message;
      if (!this.panelOpen || this.panel !== 'cloud') {
        this.openCloudPanel(this.panelOpen ? this.panel : '');
      }
    }).finally(() => {
      this.busy = false; this.cloudBusy = cloud?.busy || false;
      this.syncCloudState();
    });
  }
  private async cloudBeginSso(strategy: string): Promise<void> {
    if (this.cloudBusy) return;
    this.cloudBusy = true;
    try {
      await this.cloudManager().beginSsoSignIn(strategy, this.getUIContext().getHostContext() as common.UIAbilityContext);
    } catch (error) { this.cloudError = (error as Error).message; }
    finally { this.cloudBusy = false; this.syncCloudState(); }
  }
  private async cloudStartEmail(email: string): Promise<void> {
    if (this.cloudBusy) return;
    this.cloudBusy = true;
    try { await this.cloudManager().startEmailSignIn(email); this.bindEnvironment(); }
    catch (error) { this.cloudError = (error as Error).message; }
    finally { this.cloudBusy = false; this.syncCloudState(); }
  }
  private async cloudSendEmailCode(): Promise<void> {
    if (this.cloudBusy) return;
    this.cloudBusy = true;
    try { await this.cloudManager().sendEmailCode(); }
    catch (error) { this.cloudError = (error as Error).message; }
    finally { this.cloudBusy = false; this.syncCloudState(); }
  }
  private async cloudVerifyEmailCode(code: string): Promise<void> {
    if (this.cloudBusy) return;
    this.cloudBusy = true;
    try { await this.cloudManager().verifyEmailCode(code); this.bindEnvironment(); }
    catch (error) { this.cloudError = (error as Error).message; }
    finally { this.cloudBusy = false; this.syncCloudState(); }
  }
  private async cloudVerifyPassword(password: string): Promise<void> {
    if (this.cloudBusy) return;
    this.cloudBusy = true;
    try { await this.cloudManager().verifyPassword(password); this.bindEnvironment(); }
    catch (error) { this.cloudError = (error as Error).message; }
    finally { this.cloudBusy = false; this.syncCloudState(); }
  }
  private async cloudPrepareSecondFactor(strategy: string): Promise<void> {
    if (this.cloudBusy) return;
    this.cloudBusy = true;
    try { await this.cloudManager().prepareSecondFactor(strategy); }
    catch (error) { this.cloudError = (error as Error).message; }
    finally { this.cloudBusy = false; this.syncCloudState(); }
  }
  private async cloudVerifySecondFactor(strategy: string, code: string): Promise<void> {
    if (this.cloudBusy) return;
    this.cloudBusy = true;
    try { await this.cloudManager().verifySecondFactor(strategy, code); this.bindEnvironment(); }
    catch (error) { this.cloudError = (error as Error).message; }
    finally { this.cloudBusy = false; this.syncCloudState(); }
  }
  private async cloudCancelSignIn(): Promise<void> {
    if (this.cloudBusy) return;
    this.cloudBusy = true;
    try { await this.cloudManager().cancelPendingSignIn(); }
    catch (error) { this.cloudError = (error as Error).message; }
    finally { this.cloudBusy = false; this.syncCloudState(); }
  }
  private async cloudResetDeviceKey(): Promise<void> {
    if (this.cloudBusy) return;
    this.cloudBusy = true;
    try { await this.cloudManager().resetDeviceKey(); this.bindEnvironment(); }
    catch (error) { this.cloudError = (error as Error).message; }
    finally { this.cloudBusy = false; this.syncCloudState(); }
  }
  private async cloudSaveCustomConfig(publishableKey: string, jwtTemplate: string, relayUrl: string): Promise<void> {
    if (this.cloudBusy) return;
    this.cloudBusy = true;
    try { await this.cloudManager().saveConfigOverride(publishableKey, jwtTemplate, relayUrl); this.bindEnvironment(); }
    catch (error) { this.cloudError = (error as Error).message; throw error as Error; }
    finally { this.cloudBusy = false; this.syncCloudState(); }
  }
  private async cloudResetCustomConfig(): Promise<void> {
    if (this.cloudBusy) return;
    this.cloudBusy = true;
    try { await this.cloudManager().resetConfigOverride(); this.bindEnvironment(); }
    catch (error) { this.cloudError = (error as Error).message; throw error as Error; }
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

  private blurChatFocus(): void {
    try {
      this.getUIContext().getFocusController().clearFocus();
    } catch (_) {}
  }

  private onPageChanged(): void {
    if (this.isChatSubpage()) {
      this.blurChatFocus();
    }
    this.ensureBrowserPreviewWatch();
  }

  private stopBrowserPreviewWatch(clearState: boolean = true): void {
    this.browserPreviewWatchGeneration++;
    this.browserPreviewWatchKey = '';
    this.browserPreviewListing = false;
    this.browserPreviewListAgain = false;
    if (this.browserPreviewWatchOwner && this.browserPreviewWatchListener) {
      this.browserPreviewWatchOwner.stopRpcStream(this.browserPreviewWatchListener);
    }
    this.browserPreviewWatchOwner = undefined;
    this.browserPreviewWatchListener = undefined;
    if (clearState) {
      const hadTabs = this.browserPreviewState.tabs.length > 0;
      this.browserPreviewState = emptyThreadPreviewTabsState();
      if (hadTabs) this.refreshFloatingCapsule();
    }
  }

  private ensureBrowserPreviewWatch(): void {
    const source = client;
    const active = this.alive && this.appForeground &&
      (this.page === 'chat' || this.page === 'preview') &&
      !this.draftMode && !!this.threadId &&
      source.ready && source.supports('serverBrowser') &&
      source.canScope('orchestration:read') !== false;
    if (!active) {
      if (this.browserPreviewWatchKey || this.browserPreviewState.tabs.length > 0) {
        this.stopBrowserPreviewWatch(true);
      }
      return;
    }
    const key = this.selectedLocalId + ':' + source.generationValue() + ':' + this.threadId;
    if (key === this.browserPreviewWatchKey && source === this.browserPreviewWatchOwner) return;
    this.stopBrowserPreviewWatch(true);
    this.browserPreviewWatchKey = key;
    this.browserPreviewWatchOwner = source;
    const generation = ++this.browserPreviewWatchGeneration;
    const threadId = this.threadId;
    try {
      this.browserPreviewWatchListener = source.watchRpcStream(
        'subscribePreviewEvents',
        {} as Record<string, Object>,
        (value: Object): void => {
          if (!this.alive || generation !== this.browserPreviewWatchGeneration ||
            source !== this.browserPreviewWatchOwner || source !== client || this.threadId !== threadId) return;
          const prevCount = this.browserPreviewState.tabs.length;
          const applied = applyPreviewEvent(this.browserPreviewState, value, threadId);
          this.browserPreviewState = applied.state;
          if (applied.state.tabs.length !== prevCount) {
            this.refreshFloatingCapsule();
          }
          if (applied.needsListRefresh) {
            void this.refreshBrowserPreviewTabs(source, threadId, generation);
          }
        }
      );
    } catch (_) {}
    void this.refreshBrowserPreviewTabs(source, threadId, generation);
  }

  private async refreshBrowserPreviewTabs(source: T3Client, threadId: string, generation: number): Promise<void> {
    if (this.browserPreviewListing) {
      this.browserPreviewListAgain = true;
      return;
    }
    this.browserPreviewListing = true;
    try {
      const result = record(await source.rpcRequest('preview.list', { threadId } as PreviewRefPayload, 15000, false));
      if (!this.alive || generation !== this.browserPreviewWatchGeneration ||
        source !== this.browserPreviewWatchOwner || source !== client || this.threadId !== threadId) return;
      const prevCount = this.browserPreviewState.tabs.length;
      this.browserPreviewState = applyPreviewListResult(this.browserPreviewState, result, threadId);
      if (this.browserPreviewState.tabs.length !== prevCount) {
        this.refreshFloatingCapsule();
      }
    } catch (_) {
    } finally {
      if (generation === this.browserPreviewWatchGeneration) {
        this.browserPreviewListing = false;
        if (this.browserPreviewListAgain) {
          this.browserPreviewListAgain = false;
          void this.refreshBrowserPreviewTabs(source, threadId, generation);
        }
      }
    }
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
    const approvalCodes: Record<string, string> = {};
    registry.clients.forEach((value: T3Client, id: string) => {
      statuses[id] = value.status;
      readyMap[id] = Boolean(value.ready);
      if (value.approvalPendingCode) approvalCodes[id] = value.approvalPendingCode;
    });
    this.environmentStatuses = statuses;
    this.environmentReady = readyMap;
    this.environmentApprovalCodes = approvalCodes;
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
      this.clearInlineMention();
      this.draftMode = false;
      this.draftModelCustomized = false;
      if (next) next.draftScope = '';
      this.messages = []; this.source.update([]); this.actions = []; this.feedbackItems = [];
      this.mcpSignInNotices = []; this.mcpAppEntries = []; this.tools = [];
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
    if (!picker || !picker.belongsTo(client)) {
      picker = new AttachmentPicker(client, (uploaded: Attachment, bytes: ArrayBuffer) => {
        this.cacheComposerAttachmentPreview(uploaded, bytes);
      });
      this.pickers.set(localId, picker);
    }
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
          try { this.cacheComposerAttachmentPreview(item, bytes); } catch (_) {}
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
  private acceptPrivacy(): void {
    acceptPrivacyConsent();
    this.privacyAccepted = true;
    startNetworkMonitor({
      onOffline: () => { environments?.handleNetworkStatus(true); },
      onOnline: () => { environments?.handleNetworkStatus(false); },
      onPathChanged: () => { environments?.handleNetworkPathChange(); }
    });
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      void prepareCloud(context, context.filesDir).catch((error: Error) => {
        AppStorage.setOrCreate('t3CloudError', error.message || 'T3 Connect 初始化失败');
      });
    } catch (_) {}
    void this.restoreAddress();
  }
  private declinePrivacy(): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      void context.terminateSelf();
    } catch (_) {}
  }
  private async restoreAddress(): Promise<void> {
    if (this.privacyAccepted === false || this.restoringEnvironments || !this.alive) return;
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
    this.stopBrowserPreviewWatch(false);
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
      const linkedTarget = this.linkedConnectTarget;
      let addedLocalId = '';
      if (this.routeFor) await this.registry().addRoute(this.routeFor, target.base, target.code);
      else if (linkedTarget) addedLocalId = await this.registry().add(target.base, target.code, linkedTarget.environmentId);
      else await this.registry().add(target.base, target.code);
      this.credential = '';
      this.address = target.base; this.routeFor = '';
      if (linkedTarget) {
        this.linkedConnectTarget = undefined;
        this.linkedThreadTarget = undefined;
        this.linkedConnectNotice = '';
        this.linkedConnectError = false;
        this.panelOpen = false;
        this.page = 'chat';
        if (addedLocalId && addedLocalId !== this.selectedLocalId) {
          await this.registry().select(addedLocalId);
        }
        this.bindEnvironment();
        void this.loadLinkedEnvironments();
        await this.watch(linkedTarget.threadId);
      } else {
        this.openPanel('server'); void this.loadLinkedEnvironments();
      }
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
      hasThreads: this.scopedThreads.some((item: ScopedThread) =>
        item.localId === localId && item.projectId === projectId && isListedThread(item)),
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
    this.messages = []; this.source.update([]); this.actions = []; this.feedbackItems = [];
    this.mcpSignInNotices = []; this.mcpAppEntries = []; this.tools = []; this.linkItems = [];
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
    this.stopBrowserPreviewWatch(false);
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
    void this.loadDraftRepositories();
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
      if (refs.length > 0) this.draftIsGitRepo = true;
      const current = refs.find((ref: BranchView) => ref.current);
      if (this.draftWorkspace.mode === 'local' && !this.draftWorkspace.branch && current) {
        this.draftWorkspace.branch = current.name;
      }
      if (this.draftWorkspace.mode === 'worktree' && !this.draftWorkspace.branch) {
        this.draftWorkspace.branch = refs.find((ref: BranchView) => ref.isDefault)?.name || current?.name || '';
      }
    } catch (error) {
      if (currentRequest()) {
        this.branches = [];
        const trackedCount = this.draftProject()?.trackedFolders?.length || 0;
        if (trackedCount === 0) this.status = (error as Error).message;
      }
    } finally { if (request === this.branchRequest) this.branchesLoading = false; }
  }

  private async loadDraftRepositories(): Promise<void> {
    const owner = client;
    const request = ++this.draftRepoRequest;
    if (!owner.ready || !this.draftMode || !owner.canReadFiles()) {
      this.draftRepoChoices = [];
      this.draftRepoChoicesLoaded = true;
      this.draftIsGitRepo = true;
      return;
    }
    const project = this.draftProject();
    if (!project) {
      this.draftRepoChoices = [];
      this.draftRepoChoicesLoaded = true;
      this.draftIsGitRepo = true;
      return;
    }
    const trackedCount = project.trackedFolders?.length || 0;
    if (trackedCount === 0) {
      this.draftRepoChoices = [];
      this.draftRepoChoicesLoaded = true;
      this.draftIsGitRepo = true;
      return;
    }
    const generation = owner.generationValue();
    const projectId = project.id;
    const workspaceRoot = project.workspaceRoot;
    const currentRequest = (): boolean => request === this.draftRepoRequest && this.alive &&
      this.draftMode && client === owner && owner.ready && owner.generationValue() === generation &&
      this.projectId === projectId;
    this.draftRepoChoicesLoaded = false;
    try {
      const folders = await owner.listWorkspaceFolders(projectId);
      if (!currentRequest()) return;
      this.draftRepoChoices = worktreeRepositoryChoices(folders, workspaceRoot);
      this.draftRepoChoicesLoaded = true;
      if (workspaceRoot) {
        try {
          const scanned = await owner.scanWorkspaceFolders(workspaceRoot);
          if (currentRequest()) this.draftIsGitRepo = scanned.isGitRepository;
        } catch (_) {}
      }
    } catch (_) {
      if (currentRequest()) {
        this.draftRepoChoices = [];
        this.draftRepoChoicesLoaded = true;
      }
    }
  }

  private updateDraftRepositories(paths: string[]): void {
    if (!this.draftMode || this.busy || this.unknown) return;
    this.draftWorkspace = {
      mode: this.draftWorkspace.mode,
      branch: this.draftWorkspace.branch,
      worktreePath: this.draftWorkspace.worktreePath,
      startFromOrigin: this.draftWorkspace.startFromOrigin,
      repositories: paths.slice()
    };
    this.scheduleDraftSave();
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

  private upsertDraftContext(item: ComposerContextRecord, message: string): boolean {
    const existingIdx = this.draftContext.findIndex((current: ComposerContextRecord) =>
      current.contextId === item.contextId);
    if (existingIdx >= 0) {
      const next = this.draftContext.slice();
      next[existingIdx] = item;
      this.draftContext = next;
      if (message) this.status = message;
      this.scheduleDraftSave();
      return true;
    }
    if (this.draftContext.length >= R4_MAX_CONTEXT_RECORDS) {
      this.status = '上下文数量已达上限（最多 ' + R4_MAX_CONTEXT_RECORDS + ' 条）';
      return false;
    }
    this.draftContext = this.draftContext.concat([item]);
    if (message) this.status = message;
    this.scheduleDraftSave();
    return true;
  }

  private addFileContext(path: string): void {
    try {
      this.upsertDraftContext(deterministicFileContext(path), '已引用文件：' + path);
    } catch (error) {
      this.status = (error as Error).message;
    }
  }

  private addSkillContext(name: string): void {
    try {
      const contextId = 'skill-' + util.generateRandomUUID();
      this.upsertDraftContext(skillContext(name, contextId), '已附加 Skill：' + name);
    } catch (error) {
      this.status = (error as Error).message;
    }
  }

  private addTerminalContext(line: ActivityLine): void {
    try {
      const rows = line.text.split('\n');
      const context = terminalContext(line.itemId, '终端 · ' + line.label, 0,
        Math.max(0, rows.length - 1), line.text.slice(0, 64000),
        'terminal-' + util.generateRandomUUID());
      this.upsertDraftContext(context, '已引用终端输出；发送时作为结构化上下文');
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
      if (value.version !== 1 || !Array.isArray(value.records)) throw new Error('剪贴板不是受支持的结构化上下文片段');
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

  private currentMentionEnvironmentId(): string {
    return this.draftEnvironment() || client.currentEnvironmentId();
  }

  private currentMentionLinkedLabels(): Record<string, string> {
    const map: Record<string, string> = {};
    if (!client.linkedEnvironmentsEnabled()) return map;
    for (const key of Object.keys(this.mentionLinkedLabels)) {
      if (this.mentionLinkedLabels[key]) map[key] = this.mentionLinkedLabels[key];
    }
    for (const item of client.peerLinkNamesSnapshot()) {
      if (item.environmentId && !map[item.environmentId]) {
        map[item.environmentId] = item.label || item.environmentId;
      }
    }
    return map;
  }

  private async refreshMentionLinkedLabels(): Promise<void> {
    if (!client.ready || !client.linkedEnvironmentsEnabled()) {
      this.mentionLinkedLabels = {};
      return;
    }
    const owner = client;
    const initial: Record<string, string> = {};
    for (const item of owner.peerLinkNamesSnapshot()) {
      if (item.environmentId) initial[item.environmentId] = item.label || item.environmentId;
    }
    this.mentionLinkedLabels = initial;
    try {
      const names = await owner.peerLinkNames();
      if (owner !== client || !this.alive) return;
      const fresh: Record<string, string> = {};
      for (const item of names) {
        if (item.environmentId) fresh[item.environmentId] = item.label || item.environmentId;
      }
      this.mentionLinkedLabels = fresh;
      if (this.inlineMentionTrigger) this.refreshInlineMentionItems();
    } catch (_) {}
  }

  private mentionEnvironmentCandidates(): MentionEnvironmentCandidate[] {
    return this.environmentEntries
      .filter((entry: EnvironmentEntry) => !entry.deleting && entry.enabled && !!entry.environmentId)
      .map((entry: EnvironmentEntry): MentionEnvironmentCandidate => ({
        environmentId: entry.environmentId,
        label: entry.label
      }));
  }

  private computeMentionGroups(
    query: string,
    fileEntries: MentionFileEntry[],
    extraThreads: ScopedThread[],
    forSheet: boolean
  ): MentionGroupsView {
    const currentEnvironmentId = this.currentMentionEnvironmentId();
    const linkedLabels = this.currentMentionLinkedLabels();
    const offersLinked = client.linkedEnvironmentsEnabled();
    const excludeThreadId = this.draftMode ? '' : this.threadId;
    const pool = extraThreads.length ? this.scopedThreads.concat(extraThreads) : this.scopedThreads;
    const hasQuery = query.trim().length > 0;
    const threads = currentEnvironmentId
      ? matchMentionThreads({
          threads: pool,
          currentEnvironmentId,
          linkedEnvironmentLabels: linkedLabels,
          excludeThreadId,
          query,
          limit: forSheet ? (hasQuery ? 12 : 6) : (hasQuery ? 5 : 4),
          allowEmptyQuery: true
        })
      : [];
    const environments = currentEnvironmentId
      ? matchMentionEnvironments({
          environments: this.mentionEnvironmentCandidates(),
          linkedEnvironmentLabels: linkedLabels,
          currentEnvironmentId,
          offersLinkedEnvironments: offersLinked,
          query,
          limit: 5,
          allowEmptyQuery: forSheet
        })
      : [];
    const models = matchMentionModels(
      extractMentionModelCandidates(client.config, this.models),
      query,
      8,
      true
    );
    const files = mentionFileItems(fileEntries, forSheet ? 30 : 12);
    return { threads, environments, models, files };
  }

  private async searchOlderThreadsForMention(query: string): Promise<ScopedThread[]> {
    const trimmed = query.trim().slice(0, 200);
    if (trimmed.length < 2) return [];
    const currentEnvId = this.currentMentionEnvironmentId();
    const linkedLabels = this.currentMentionLinkedLabels();
    const registry = this.registry();
    const targets: EnvironmentEntry[] = this.environmentEntries.filter((entry: EnvironmentEntry) =>
      !entry.deleting && entry.enabled && !!entry.environmentId &&
      (entry.environmentId === currentEnvId || !!linkedLabels[entry.environmentId])
    );
    const collected: ScopedThread[] = [];
    await Promise.all(targets.map(async (entry: EnvironmentEntry) => {
      const conn = registry.clients.get(entry.localId);
      if (!conn || !conn.ready) return;
      try {
        const payload: MentionSearchThreadsPayload = { query: trimmed, limit: 20, titlesOnly: true };
        const value = record(await conn.searchThreads(payload));
        if (!Array.isArray(value.threads)) return;
        for (const raw of value.threads as Object[]) {
          try {
            const parsed = threadView(raw);
            const project = this.scopedProjects.find((p: ScopedProject) =>
              p.localId === entry.localId && p.id === parsed.projectId);
            collected.push(scopedThreadView(
              parsed,
              entry.localId,
              entry.environmentId,
              entry.label,
              project ? project.label : '',
              project?.projectIcon
            ));
          } catch (_) {}
        }
      } catch (_) {}
    }));
    return collected;
  }

  private sheetMentionGroups(): MentionGroupsView {
    return this.computeMentionGroups(
      this.commandQuery,
      this.mentionFileEntries,
      this.mentionExtraThreads,
      true
    );
  }

  private async openFileMention(): Promise<void> {
    this.openComposerCommand('mention');
  }

  private openComposerCommand(mode: string): void {
    this.commandPanel = mode; this.commandQuery = ''; this.mentionFiles = [];
    this.mentionFileEntries = []; this.mentionExtraThreads = []; this.mentionLoading = false;
    if (mode === 'branch' && !this.branches.length) void this.loadBranches();
    if ((mode === 'branch' || mode === 'repositories') && !this.draftRepoChoices.length &&
      (this.draftProject()?.trackedFolders?.length || 0) > 0) {
      void this.loadDraftRepositories();
    }
    this.openPanel('composer-command');
    if (mode === 'mention') {
      void this.refreshMentionLinkedLabels();
      this.triggerSheetMentionSearch('', true);
    }
  }

  private triggerSheetMentionSearch(query: string, immediate: boolean = false): void {
    this.commandQuery = query;
    if (this.mentionSearchTimer) {
      clearTimeout(this.mentionSearchTimer);
      this.mentionSearchTimer = 0;
    }
    const seq = ++this.mentionSearchSeq;
    const cwd = this.currentWorkspace();
    const owner = client;
    const canSearchFiles = owner.ready && !!cwd;
    const canSearchThreads = owner.ready && query.trim().length >= 2;
    if (!canSearchFiles && !canSearchThreads) {
      this.mentionFileEntries = [];
      this.mentionFiles = [];
      this.mentionExtraThreads = [];
      this.mentionLoading = false;
      return;
    }
    this.mentionLoading = true;
    const execute = async (): Promise<void> => {
      try {
        const filesPromise: Promise<MentionFileEntry[]> = canSearchFiles
          ? owner.searchEntries(cwd, query, 30).catch(() => [])
          : Promise.resolve([]);
        const threadsPromise: Promise<ScopedThread[]> = canSearchThreads
          ? this.searchOlderThreadsForMention(query).catch(() => [])
          : Promise.resolve([]);
        const results = await Promise.all([filesPromise, threadsPromise]);
        if (seq !== this.mentionSearchSeq || owner !== client || !this.alive ||
          !this.panelOpen || this.panel !== 'composer-command' || this.commandPanel !== 'mention') {
          return;
        }
        this.mentionFileEntries = results[0];
        this.mentionFiles = results[0].map((entry: MentionFileEntry) => entry.path);
        this.mentionExtraThreads = results[1];
      } finally {
        if (seq === this.mentionSearchSeq) {
          this.mentionLoading = false;
        }
      }
    };
    if (immediate) {
      void execute();
    } else {
      this.mentionSearchTimer = setTimeout(() => {
        this.mentionSearchTimer = 0;
        void execute();
      }, 180) as number;
    }
  }

  private clearInlineMention(resetDismissed: boolean = true): void {
    if (this.inlineMentionTimer) {
      clearTimeout(this.inlineMentionTimer);
      this.inlineMentionTimer = 0;
    }
    this.inlineMentionSeq += 1;
    this.inlineMentionTrigger = undefined;
    this.inlineMentionItems = [];
    this.inlineMentionLoading = false;
    if (resetDismissed) this.inlineMentionDismissedKey = '';
  }

  private dismissInlineMention(): void {
    if (this.inlineMentionTrigger) {
      this.inlineMentionDismissedKey = this.inlineMentionTrigger.rangeStart + ':' + this.inlineMentionTrigger.query;
    }
    this.clearInlineMention(false);
  }

  private refreshInlineMentionItems(): void {
    const trigger = this.inlineMentionTrigger;
    if (!trigger) {
      this.inlineMentionItems = [];
      return;
    }
    const groups = this.computeMentionGroups(
      trigger.query,
      this.inlineMentionFileEntries,
      this.inlineMentionExtraThreads,
      false
    );
    this.inlineMentionItems = groups.threads
      .concat(groups.environments)
      .concat(groups.models)
      .concat(groups.files);
  }

  private syncInlineMention(value: string, cursorStart: number, cursorEnd: number): void {
    if (this.busy || this.unknown || this.panelOpen || cursorStart !== cursorEnd) {
      this.clearInlineMention();
      return;
    }
    const trigger = detectInlineMentionTrigger(value, cursorEnd);
    if (!trigger) {
      this.clearInlineMention();
      return;
    }
    const triggerKey = trigger.rangeStart + ':' + trigger.query;
    if (this.inlineMentionDismissedKey === triggerKey) {
      this.inlineMentionTrigger = undefined;
      this.inlineMentionItems = [];
      this.inlineMentionLoading = false;
      return;
    }
    if (this.inlineMentionDismissedKey && this.inlineMentionDismissedKey !== triggerKey) {
      this.inlineMentionDismissedKey = '';
    }
    const cwd = this.currentWorkspace();
    const queryChanged = trigger.query !== this.inlineMentionLastQuery || cwd !== this.inlineMentionLastCwd;
    const wasOpen = this.inlineMentionTrigger !== undefined;
    this.inlineMentionTrigger = trigger;
    if (queryChanged) {
      this.inlineMentionLastQuery = trigger.query;
      this.inlineMentionLastCwd = cwd;
      this.inlineMentionFileEntries = [];
      this.inlineMentionExtraThreads = [];
    }
    this.refreshInlineMentionItems();
    if (!wasOpen) {
      void this.refreshMentionLinkedLabels();
    }
    if (!queryChanged && wasOpen) return;
    if (this.inlineMentionTimer) {
      clearTimeout(this.inlineMentionTimer);
      this.inlineMentionTimer = 0;
    }
    const owner = client;
    const canSearchFiles = owner.ready && !!cwd;
    const canSearchThreads = owner.ready && trigger.query.trim().length >= 2;
    if (!canSearchFiles && !canSearchThreads) {
      this.inlineMentionLoading = false;
      return;
    }
    const seq = ++this.inlineMentionSeq;
    this.inlineMentionLoading = true;
    this.inlineMentionTimer = setTimeout(() => {
      this.inlineMentionTimer = 0;
      void (async (): Promise<void> => {
        try {
          const filesPromise: Promise<MentionFileEntry[]> = canSearchFiles
            ? owner.searchEntries(cwd, trigger.query, 15).catch(() => [])
            : Promise.resolve([]);
          const threadsPromise: Promise<ScopedThread[]> = canSearchThreads
            ? this.searchOlderThreadsForMention(trigger.query).catch(() => [])
            : Promise.resolve([]);
          const results = await Promise.all([filesPromise, threadsPromise]);
          if (seq !== this.inlineMentionSeq || owner !== client || !this.alive || !this.inlineMentionTrigger) {
            return;
          }
          this.inlineMentionFileEntries = results[0];
          this.inlineMentionExtraThreads = results[1];
          this.refreshInlineMentionItems();
        } finally {
          if (seq === this.inlineMentionSeq) {
            this.inlineMentionLoading = false;
          }
        }
      })();
    }, 160) as number;
  }

  private applyMentionItem(item: MentionItem, trigger?: ComposerInlineTrigger): void {
    const activeTrigger = trigger;
    if (item.kind === 'model') {
      const token = formatComposerModelMention(item.instanceId, item.model) + ' ';
      if (activeTrigger) {
        const replaced = replaceTextRange(this.prompt, activeTrigger.rangeStart, activeTrigger.rangeEnd, token);
        this.prompt = replaced.text;
        this.composerCursor = replaced.cursor;
        this.composerSelectionEnd = replaced.cursor;
        this.clearInlineMention();
        this.syncComposerExpanded(replaced.text, '');
        setTimeout(() => {
          try { this.composerController.caretPosition(replaced.cursor); } catch (_) {}
        }, 16);
      } else {
        const prefix = this.prompt && !/\s$/.test(this.prompt) ? this.prompt + ' ' : this.prompt;
        this.prompt = prefix + token;
        this.panelOpen = false;
        this.syncComposerExpanded(this.prompt, '');
      }
      this.status = '已插入模型引用：' + item.label;
      this.scheduleDraftSave();
      return;
    }

    let ok = false;
    try {
      if (item.kind === 'thread') {
        ok = this.upsertDraftContext(
          deterministicThreadContext(item.environmentId, item.threadId, item.label),
          '已引用会话：' + item.label
        );
      } else if (item.kind === 'environment') {
        ok = this.upsertDraftContext(
          deterministicEnvironmentContext(item.environmentId, item.label),
          '已引用环境：' + item.label
        );
      } else if (item.kind === 'file') {
        ok = this.upsertDraftContext(
          deterministicFileContext(item.path),
          '已引用文件：' + item.path
        );
      }
    } catch (error) {
      this.status = (error as Error).message;
      return;
    }
    if (!ok) return;

    if (activeTrigger) {
      const replaced = replaceTextRange(this.prompt, activeTrigger.rangeStart, activeTrigger.rangeEnd, '');
      this.prompt = replaced.text;
      this.composerCursor = replaced.cursor;
      this.composerSelectionEnd = replaced.cursor;
      this.clearInlineMention();
      this.syncComposerExpanded(replaced.text, '');
      setTimeout(() => {
        try { this.composerController.caretPosition(replaced.cursor); } catch (_) {}
      }, 16);
    } else {
      this.panelOpen = false;
    }
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
      if (sideChat) {
        this.busy = false;
        await this.openSideThread('side-chat', id, '', '');
      } else {
        await this.watch(id);
      }
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
      browserPreviewCount: this.browserPreviewState.tabs.length,
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

  private async openAttachmentItem(item: DraftAttachment): Promise<void> {
    const cached = this.lookupLocalAttachmentPreview ? this.lookupLocalAttachmentPreview(item) : '';
    this.selectedAttachment = item;
    this.attachmentPreviewUrl = cached;
    this.attachmentStatus = '';
    this.openPanel('attachment');
    if (cached && this.attachmentMediaKind(item) === 'image') return;
    try {
      const url = await client.attachmentUrl(item.id, item.name, item.mimeType, true);
      if (this.selectedAttachment && this.selectedAttachment.id === item.id) {
        this.attachmentPreviewUrl = url;
      }
    } catch (error) {
      if (!cached && this.selectedAttachment && this.selectedAttachment.id === item.id) {
        this.attachmentStatus = (error as Error).message;
      }
    }
  }

  private async openAttachment(name: string): Promise<void> {
    const item = this.findAttachment(name);
    if (!item) { this.status = '附件已不在当前快照中'; return; }
    await this.openAttachmentItem(item);
  }

  private async saveAttachment(): Promise<void> {
    const item = this.selectedAttachment;
    if (!item || this.busy) return;
    this.busy = true; this.attachmentStatus = '正在下载…';
    try {
      const bytes = await client.downloadAttachment(item.id, item.name, item.mimeType);
      const outcome = await saveBytesToDocumentPicker(bytes, item.name);
      this.attachmentStatus = outcome === 'saved' ? '已保存到所选位置' : '已取消保存';
    } catch (error) { this.attachmentStatus = '保存失败：' + (error as Error).message; }
    finally { this.busy = false; }
  }

  private async saveAttachmentToGallery(viaSaveButton: boolean): Promise<void> {
    const item = this.selectedAttachment;
    if (!item || this.busy) return;
    const kind = this.attachmentMediaKind(item);
    if (!canSaveToPhotoGallery(item.name, item.mimeType, kind)) {
      await this.saveAttachment();
      return;
    }
    this.busy = true; this.attachmentStatus = '正在保存到相册…';
    try {
      const bytes = await client.downloadAttachment(item.id, item.name, item.mimeType);
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const outcome = await saveBytesToPhotoGallery(context, bytes, item.name, item.mimeType, kind, viaSaveButton);
      this.attachmentStatus = outcome === 'saved' ? '已保存到相册' : '已取消保存';
    } catch (error) { this.attachmentStatus = '保存失败：' + (error as Error).message; }
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
      const kind = this.attachmentMediaKind(item);
      await shareBytesWithSystemSheet(context, bytes, item.name, scope, item.mimeType, kind);
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

  private async watch(id: string, preserveScroll: boolean = false): Promise<void> {
    this.clearInlineMention();
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
    this.pendingScrollBottomKey = preserveScroll ? '' : targetKey;
    if (!preserveScroll) this.pendingScrollRestore = undefined;
    this.lastAutoWatchKey = this.selectedLocalId + ':' + client.generationValue() + ':' + id;
    this.threadId = id;
    this.prompt = this.textDrafts.get(this.draftKey()) || '';
    this.draftContext = (this.contextDrafts.get(this.draftKey()) || []).slice();
    this.page = 'chat'; this.showTools = false; this.panelOpen = false;
    this.ensureBrowserPreviewWatch();
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
    this.inlineMentionTrigger = undefined;
    this.inlineMentionItems = [];
    this.inlineMentionLoading = false;
    const submitted = this.prompt;
    const submittedContext = Array.isArray(this.draftContext) ? this.draftContext.slice() : [];
    const owner = client;
    const key = this.draftKey();
    const draftId = this.activeDraftId;
    const localId = this.selectedLocalId;
    try {
      if (this.draftMode) {
        await this.persistDraft();
        const isRootGit = this.draftIsGitRepo !== false || !Array.isArray(this.draftRepoChoices) || this.draftRepoChoices.length === 0;
        const id = await owner.launch(this.projectId, submitted, this.taskSettings, this.draftWorkspace, submittedContext, isRootGit);
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
    items.push({ value: '文件与提及 @', action: () => { this.openComposerCommand('mention'); } });
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
  private async openExternalUrl(url: string): Promise<void> {
    if (!/^(https?:\/\/|mailto:|tel:)/i.test(url)) { this.status = '不支持打开此链接'; return; }
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await context.startAbility({ action: 'ohos.want.action.viewData', uri: url });
    } catch (error) { this.status = '无法打开链接：' + (error as Error).message; }
  }
  private captureCurrentChatPosition(): SideThreadReturnPoint | undefined {
    if (this.page !== 'chat' || this.draftMode || !this.selectedLocalId || !this.threadId) return undefined;
    let scrollY = 0;
    try {
      const offset = this.scroller.currentOffset();
      if (offset && typeof offset.yOffset === 'number' && Number.isFinite(offset.yOffset) && offset.yOffset > 0) {
        scrollY = offset.yOffset;
      }
    } catch (_) {}
    return {
      localId: this.selectedLocalId,
      threadId: this.threadId,
      scrollY,
      scrollIndex: this.chatScrollIndex > 0 ? this.chatScrollIndex : 0
    };
  }
  private async returnToParentThread(): Promise<boolean> {
    const popped = popSideThreadReturn(this.sideThreadReturnStack);
    if (!popped.point) return false;
    this.sideThreadReturnStack = popped.rest;
    const point = popped.point;
    this.panelOpen = false;
    this.linkedThreadTarget = undefined;
    this.sideThreadTarget = undefined;
    this.pendingScrollRestore = point;
    this.page = 'chat';
    if (point.localId !== this.selectedLocalId) {
      await this.registry().select(point.localId);
      this.bindEnvironment();
      this.page = 'chat';
    }
    if (this.threadId === point.threadId && client.thread && client.thread.threadId === point.threadId && this.messages.length > 0) {
      const restore = this.pendingScrollRestore;
      this.pendingScrollRestore = undefined;
      if (restore && this.needsChatScrollFallback(restore)) {
        const applySameThreadRestore = (): void => {
          if (!this.alive || this.page !== 'chat' || this.threadId !== restore.threadId) return;
          if (!this.needsChatScrollFallback(restore)) return;
          if (restore.scrollY > 0) this.scroller.scrollTo({ xOffset: 0, yOffset: restore.scrollY });
          else if (restore.scrollIndex > 0) this.scroller.scrollToIndex(restore.scrollIndex);
        };
        setTimeout(applySameThreadRestore, 60);
        setTimeout(applySameThreadRestore, 220);
      }
      return true;
    }
    await this.watch(point.threadId, true);
    return true;
  }
  private async leaveChatOrReturnParent(): Promise<void> {
    if (this.sideThreadReturnStack.length > 0) {
      const returned = await this.returnToParentThread();
      if (returned) return;
    }
    this.sideThreadReturnStack = [];
    this.pendingScrollRestore = undefined;
    this.page = 'sessions';
  }
  private async leaveLinkedThreadPage(): Promise<void> {
    this.linkedThreadTarget = undefined;
    this.linkedConnectNotice = '';
    this.linkedConnectError = false;
    if (this.sideThreadReturnStack.length > 0) {
      const returned = await this.returnToParentThread();
      if (returned) return;
    }
    this.page = 'chat';
  }
  private async openSideThread(
    requestedKind: SideThreadKind,
    threadId: string,
    remoteEnvironmentId: string,
    remoteLabel: string = '',
    intent: SideThreadOpenIntent = 'primary'
  ): Promise<void> {
    if (this.busy) return;
    const tid = threadId.trim();
    const envId = remoteEnvironmentId.trim();
    if (!tid) return;
    const currentEntry = this.environmentEntries.find((candidate: EnvironmentEntry) =>
      !candidate.deleting && candidate.localId === this.selectedLocalId);
    const viaEnvId = currentEntry?.environmentId || '';
    const targetMode = resolveSideThreadOpenTarget(
      parseSideThreadOpenTarget(workspacePrefs.sideThreadOpenTarget),
      intent,
      true
    );

    const openConnectedInTarget = async (entry: EnvironmentEntry | undefined, targetThreadId: string): Promise<void> => {
      const targetLocalId = entry ? entry.localId : this.selectedLocalId;
      const targetEnvId = entry ? entry.environmentId : viaEnvId;
      const targetEnvLabel = entry ? entry.label : (currentEntry?.label || this.server || '当前环境');
      const matched = this.scopedThreads.find((t: ScopedThread) => t.localId === targetLocalId && t.id === targetThreadId);
      const inferredKind = sideThreadKindOf(matched);
      const effectiveKind: 'side-chat' | 'subagent' | 'provider-subagent' =
        inferredKind || (requestedKind === 'side-chat' ? 'side-chat' : requestedKind === 'provider-subagent' ? 'provider-subagent' : 'subagent');
      if (targetMode === 'panel') {
        this.sideThreadTarget = {
          kind: effectiveKind,
          localId: targetLocalId,
          environmentId: targetEnvId,
          environmentLabel: targetEnvLabel,
          threadId: targetThreadId,
          title: matched?.label || ''
        };
        this.panel = 'side-thread';
        this.panelOpen = true;
        return;
      }
      const parentPos = this.captureCurrentChatPosition();
      if (parentPos && (parentPos.localId !== targetLocalId || parentPos.threadId !== targetThreadId)) {
        this.sideThreadReturnStack = pushSideThreadReturn(this.sideThreadReturnStack, parentPos);
      }
      this.sideThreadTarget = undefined;
      this.panelOpen = false;
      this.page = 'chat';
      if (targetLocalId !== this.selectedLocalId) {
        await this.registry().select(targetLocalId);
        this.bindEnvironment();
        this.page = 'chat';
      }
      await this.watch(targetThreadId);
    };

    if (!envId || envId === viaEnvId) {
      await openConnectedInTarget(currentEntry, tid);
      return;
    }
    const ownEntry = this.environmentEntries.find((candidate: EnvironmentEntry) =>
      !candidate.deleting && candidate.enabled && candidate.environmentId === envId);
    const resolution = resolveLinkedThreadOpen({
      ownConnected: ownEntry !== undefined,
      targetEnvironmentId: envId,
      viaEnvironmentId: viaEnvId,
      linkedEnvironmentsEnabled: client.ready && client.linkedEnvironmentsEnabled()
    });
    if (resolution === 'direct' && ownEntry) {
      await openConnectedInTarget(ownEntry, tid);
      return;
    }
    if (resolution === 'linked') {
      let label = remoteLabel.trim() || client.peerLinkLabel(envId);
      if (!label) {
        try {
          const names = await client.peerLinkNames();
          const matched = names.find((item) => item.environmentId === envId);
          if (matched) label = matched.label;
        } catch (_) {}
      }
      this.linkedThreadTarget = {
        viaLocalId: this.selectedLocalId,
        viaEnvironmentId: viaEnvId,
        viaLabel: currentEntry?.label || this.server || '当前环境',
        environmentId: envId,
        threadId: tid,
        label: label || envId
      };
      this.linkedConnecting = false;
      this.linkedConnectNotice = '';
      this.linkedConnectError = false;
      if (targetMode === 'main') {
        const parentPos = this.captureCurrentChatPosition();
        if (parentPos) {
          this.sideThreadReturnStack = pushSideThreadReturn(this.sideThreadReturnStack, parentPos);
        }
        this.panelOpen = false;
        this.page = 'linked-thread';
      } else {
        this.panel = 'linked-thread';
        this.panelOpen = true;
      }
      return;
    }
    this.status = '目标会话所在环境未连接，且当前环境未开启链接环境';
  }
  private async openRemoteOrLocalThread(threadId: string, remoteEnvironmentId: string, remoteLabel: string = ''): Promise<void> {
    await this.openSideThread('subagent', threadId, remoteEnvironmentId, remoteLabel);
  }
  private async connectLinkedThreadEnvironment(target: LinkedThreadTarget): Promise<void> {
    if (this.linkedConnecting || this.busy) return;
    const existing = this.environmentEntries.find((candidate: EnvironmentEntry) =>
      !candidate.deleting && candidate.enabled && candidate.environmentId === target.environmentId);
    const viaOwner = this.registry().clients.get(target.viaLocalId) || client;
    this.linkedConnecting = true;
    this.linkedConnectError = false;
    this.linkedConnectNotice = '正在获取「' + (target.label || target.environmentId) + '」的连接信息…';
    try {
      const outcome = await prepareLinkedEnvironmentConnection({
        environmentId: target.environmentId,
        label: target.label || target.environmentId,
        alreadyConnectedLocalId: existing ? existing.localId : '',
        requestPairing: () => viaOwner.requestPeerClientPairing(target.environmentId),
        reaches: async (url: string): Promise<boolean> => {
          const probe = await viaOwner.probeRoute(url, target.environmentId, 3000);
          return probe.ok;
        }
      });
      if (outcome.type === 'already_connected') {
        this.linkedConnectNotice = '';
        this.linkedConnectError = false;
        this.linkedThreadTarget = undefined;
        this.linkedConnectTarget = undefined;
        this.panelOpen = false;
        this.page = 'chat';
        if (outcome.localId !== this.selectedLocalId) {
          await this.registry().select(outcome.localId);
          this.bindEnvironment();
        }
        await this.watch(target.threadId);
        return;
      }
      if (outcome.type === 'unreachable') {
        this.linkedConnectError = true;
        this.linkedConnectNotice = '当前设备无法直接访问「' + outcome.label + '」，请加入同一局域网或 Tailscale 后重试；你仍可继续只读查看。';
        return;
      }
      if (outcome.prefill) {
        this.linkedConnectNotice = '';
        this.linkedConnectError = false;
        this.routeFor = '';
        this.address = outcome.prefill.host;
        this.credential = outcome.prefill.credential;
        this.pairingError = false;
        this.pairingStatus = outcome.prefill.credential
          ? '已获取「' + outcome.prefill.label + '」的一次性配对材料，请确认目标地址后点击确认连接'
          : linkedManualReasonMessage(outcome.prefill.label, outcome.prefill.manualReason);
        this.linkedConnectTarget = target;
        this.panel = 'connection-new';
        this.panelOpen = true;
      }
    } catch (error) {
      this.linkedConnectError = true;
      this.linkedConnectNotice = '连接准备失败：' + (error as Error).message;
    } finally {
      this.linkedConnecting = false;
    }
  }
  private async openParsedThreadLink(parsed: ParsedThreadLink): Promise<void> {
    if (this.busy) return;
    const candidates = threadLinkCandidates(parsed.threadId, parsed.decodedThreadId);
    const pickThreadId = (pool: ThreadView[]): string => {
      for (const id of candidates) {
        if (pool.some((t: ThreadView) => t.id === id)) return id;
      }
      return parsed.threadId || parsed.decodedThreadId;
    };
    if (parsed.environmentId) {
      const ownEntry = this.environmentEntries.find((candidate: EnvironmentEntry) =>
        !candidate.deleting && candidate.enabled && candidate.environmentId === parsed.environmentId);
      if (ownEntry) {
        const pool = this.scopedThreads.filter((t: ScopedThread) => t.localId === ownEntry.localId);
        await this.openSideThread('linked', pickThreadId(pool), parsed.environmentId, ownEntry.label);
        return;
      }
      await this.openSideThread('linked', parsed.threadId || parsed.decodedThreadId, parsed.environmentId, '');
      return;
    }
    for (const id of candidates) {
      if (this.threads.some((t: ThreadView) => t.id === id)) {
        await this.openSideThread('linked', id, '', '');
        return;
      }
    }
    const crossMatches = this.scopedThreads.filter((t: ScopedThread) =>
      candidates.includes(t.id));
    if (crossMatches.length === 1) {
      const match = crossMatches[0];
      await this.openSideThread('linked', match.id, match.environmentId, match.environmentLabel);
      return;
    }
    await this.openSideThread('linked', parsed.threadId || parsed.decodedThreadId, '', '');
  }
  private async openThreadLink(target: ThreadLinkTarget): Promise<void> {
    await this.openParsedThreadLink({
      environmentId: target.environmentId,
      threadId: target.threadId,
      decodedThreadId: target.decodedThreadId
    });
  }
  private findContextRecordById(contextId: string): Record<string, Object> | undefined {
    const records = client.thread?.messageRecords || [];
    for (let i = records.length - 1; i >= 0; i -= 1) {
      const msgCtx = optionalRecord(records[i].context);
      if (!msgCtx || !Array.isArray(msgCtx.records)) continue;
      for (const entry of msgCtx.records as Object[]) {
        const row = optionalRecord(entry);
        if (row && row.contextId === contextId) return row;
      }
    }
    for (const draftItem of this.draftContext) {
      if (draftItem.contextId === contextId) {
        const merged: Record<string, Object> = {};
        merged['version'] = 1;
        merged['kind'] = draftItem.kind;
        merged['contextId'] = draftItem.contextId;
        merged['label'] = draftItem.label;
        for (const key of Object.keys(draftItem.payload)) merged[key] = draftItem.payload[key];
        return merged;
      }
    }
    return undefined;
  }

  private async openLink(url: string): Promise<void> {
    const contextRef = parseComposerContextHref(url);
    if (contextRef) {
      const row = this.findContextRecordById(contextRef.contextId);
      if (contextRef.kind === 'thread' && row && typeof row.threadId === 'string' && row.threadId.trim()) {
        const envId = typeof row.environmentId === 'string' ? row.environmentId.trim() : '';
        await this.openSideThread('linked', row.threadId.trim(), envId, '');
        return;
      }
      if (contextRef.kind === 'mention' && row && typeof row.path === 'string' && row.path.trim()) {
        await this.openLink(row.path.trim());
        return;
      }
      if (contextRef.kind === 'environment' && row && typeof row.label === 'string' && row.label.trim()) {
        this.status = '已提及环境：' + row.label.trim();
        return;
      }
      this.status = '上下文记录不可用';
      return;
    }
    const classified = classifyMarkdownLink(url);
    if (classified.kind === 'external' || classified.kind === 'mailto') {
      await this.openExternalUrl(classified.href);
      return;
    }
    if (classified.kind === 'thread' && classified.thread) {
      try {
        await this.openThreadLink(classified.thread);
      } catch (error) {
        this.status = '无法打开会话链接：' + (error as Error).message;
      }
      return;
    }
    if (classified.kind === 'file' && classified.file) {
      const cwd = this.currentWorkspace();
      const resolved = resolveFileLinkForWorkspace(cwd, classified.file);
      if (!resolved) {
        this.status = '缺少工作目录，无法解析相对路径';
        return;
      }
      let metaKind = '';
      if (client.ready && resolved.absolutePath) {
        metaKind = await client.fileMetadataKind(resolved.absolutePath);
      }
      if (this.page === 'chat' && !this.draftMode && this.threadId) {
        this.pendingScrollRestore = this.captureCurrentChatPosition();
      }
      this.panelOpen = false;
      if (metaKind === 'directory' || resolved.isDirectoryHint) {
        this.filesInitialPath = '';
        this.filesInitialLine = 0;
        this.filesDirectFileOnly = false;
        if (resolved.isOutsideWorkspace) {
          this.filesOverrideCwd = resolved.absolutePath;
          this.filesInitialDir = '';
        } else {
          this.filesOverrideCwd = '';
          this.filesInitialDir = resolved.path;
        }
        this.page = 'files';
        return;
      }
      this.filesOverrideCwd = '';
      this.filesInitialDir = '';
      this.filesInitialPath = resolved.path;
      this.filesInitialLine = resolved.line;
      this.filesDirectFileOnly = true;
      this.page = 'files';
      return;
    }
    this.status = '暂不支持打开此链接';
  }
  private needsChatScrollFallback(restore: SideThreadReturnPoint): boolean {
    if (restore.scrollY <= 0 && restore.scrollIndex <= 0) return false;
    let currentY = 0;
    let atEnd = false;
    try {
      const offset = this.scroller.currentOffset();
      if (offset && typeof offset.yOffset === 'number' && Number.isFinite(offset.yOffset)) {
        currentY = offset.yOffset;
      }
      atEnd = this.scroller.isAtEnd();
    } catch (_) {}
    return currentY < 1 && !atEnd;
  }

  private returnToChatWithScrollRestore(): void {
    const restore = this.pendingScrollRestore;
    this.pendingScrollRestore = undefined;
    this.page = 'chat';
    if (restore && restore.localId === this.selectedLocalId && restore.threadId === this.threadId &&
      !this.draftMode && this.messages.length > 0 && this.needsChatScrollFallback(restore)) {
      const apply = (): void => {
        if (!this.alive || this.page !== 'chat' || this.draftMode || this.threadId !== restore.threadId) return;
        if (!this.needsChatScrollFallback(restore)) return;
        if (restore.scrollY > 0) this.scroller.scrollTo({ xOffset: 0, yOffset: restore.scrollY });
        else if (restore.scrollIndex > 0) this.scroller.scrollToIndex(restore.scrollIndex);
      };
      setTimeout(apply, 60);
      setTimeout(apply, 220);
    }
  }
  private openHtmlFullscreen(entry: HtmlRenderEntry, uri: string): void {
    if (this.page === 'chat' && !this.draftMode && this.threadId) {
      this.pendingScrollRestore = this.captureCurrentChatPosition();
    }
    this.htmlViewerEntry = entry;
    this.htmlViewerUri = uri;
    this.htmlViewerError = '';
    this.htmlViewerAttempt = 0;
    this.panelOpen = false;
    this.page = 'html-viewer';
    if (!uri) {
      void this.reloadHtmlFullscreen();
    }
  }
  private async reloadHtmlFullscreen(): Promise<void> {
    const entry = this.htmlViewerEntry;
    if (!entry) return;
    this.htmlViewerError = '';
    try {
      const next = await client.htmlRenderUrl(entry.render.attachmentId, entry.render.title);
      if (this.htmlViewerEntry?.id !== entry.id) return;
      this.htmlViewerUri = next;
      this.htmlViewerAttempt += 1;
    } catch (error) {
      if (this.htmlViewerEntry?.id === entry.id) {
        this.htmlViewerError = (error as Error).message || 'HTML 页面加载失败';
      }
    }
  }
  private async saveHtmlRender(): Promise<void> {
    const entry = this.htmlViewerEntry;
    if (!entry || this.busy) return;
    const fileName = htmlRenderFileName(entry.render.title);
    this.busy = true;
    try {
      const bytes = await client.downloadAttachment(entry.render.attachmentId, fileName, 'text/html');
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [fileName];
      const target = await new picker.DocumentViewPicker().save(options);
      if (!target.length) { this.status = '已取消保存'; return; }
      const file = fileIo.openSync(target[0], fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try { fileIo.writeSync(file.fd, bytes); fileIo.fsyncSync(file.fd); } finally { fileIo.closeSync(file); }
      this.status = '已保存：' + fileName;
    } catch (error) {
      this.status = '保存失败：' + (error as Error).message;
    } finally {
      this.busy = false;
    }
  }
  private async shareHtmlRender(): Promise<void> {
    const entry = this.htmlViewerEntry;
    if (!entry || this.busy) return;
    const owner = client; const scope = this.selectedLocalId; const threadId = this.threadId;
    const fileName = htmlRenderFileName(entry.render.title);
    this.busy = true;
    try {
      const bytes = await owner.downloadAttachment(entry.render.attachmentId, fileName, 'text/html');
      if (owner !== client || scope !== this.selectedLocalId || threadId !== this.threadId) throw new Error('分享目标已变化');
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const safeName = fileName.replace(/[\\/:*?"<>|\x00-\x1f]/g, '_').slice(-180) || 'page.html';
      const path = context.cacheDir + '/share-' + Date.now() + '-' + safeName;
      const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try { fileIo.writeSync(file.fd, bytes); fileIo.fsyncSync(file.fd); } finally { fileIo.closeSync(file); }
      registerSharedFile(context.cacheDir, path.substring(context.cacheDir.length + 1), scope);
      const shared = new systemShare.SharedData({ utd: 'general.html',
        uri: fileUri.getUriFromPath(path), title: entry.render.title || fileName });
      await new systemShare.ShareController(shared).show(context, {});
      this.status = '已打开系统分享';
    } catch (error) {
      this.status = '分享失败：' + (error as Error).message;
    } finally {
      this.busy = false;
    }
  }
  private markdownMediaScopeKey(): string {
    return this.selectedLocalId + ':' + this.threadId + ':' + client.generationValue() + ':' + (this.ready ? '1' : '0');
  }
  private attachmentMediaKind(att: ChatAttachment): string {
    const mime = (att.mimeType || '').toLowerCase();
    const name = att.name || '';
    if (mime.startsWith('video/') || /\.(?:mp4|webm|mov|m4v|ogv|mkv|avi|3gp)$/i.test(name)) return 'video';
    if (att.type === 'image' || mime.startsWith('image/') || /\.(?:png|jpe?g|gif|webp|bmp|svg|avif|heic)$/i.test(name)) return 'image';
    return '';
  }
  private resolveAttachmentById(attachmentId: string): ChatAttachment | undefined {
    const draftAtt = this.attachments.find((item: DraftAttachment) => item.id === attachmentId);
    if (draftAtt) {
      return { id: draftAtt.id, type: draftAtt.type, name: draftAtt.name, mimeType: draftAtt.mimeType, sizeBytes: draftAtt.sizeBytes };
    }
    for (const msg of this.messages) {
      if (!msg.attachments) continue;
      const found = msg.attachments.find((item: ChatAttachment) => item.id === attachmentId);
      if (found) return found;
    }
    const threadAtt = this.threadAttachments().find((item: DraftAttachment) => item.id === attachmentId);
    if (threadAtt) {
      return { id: threadAtt.id, type: threadAtt.type, name: threadAtt.name, mimeType: threadAtt.mimeType, sizeBytes: threadAtt.sizeBytes };
    }
    return undefined;
  }
  private async resolveMarkdownMedia(source: string, refresh: boolean): Promise<ResolvedMarkdownMedia> {
    if (source.startsWith('t3-attachment://')) {
      const id = source.slice('t3-attachment://'.length);
      const att = this.resolveAttachmentById(id);
      if (!att) throw new Error('附件已不在当前快照中');
      const url = await client.attachmentUrl(att.id, att.name, att.mimeType || 'application/octet-stream', true);
      return {
        url,
        kind: this.attachmentMediaKind(att) || 'image',
        displayPath: att.name,
        expiresAt: 0,
        width: 0,
        height: 0
      };
    }
    return client.markdownMediaUrl(source, this.currentWorkspace(), refresh);
  }
  private mediaFileExtension(hint: string, url: string, kind: string): string {
    const combined = (hint || '') + ' ' + (url || '');
    const match = /\.(mp4|webm|mov|m4v|ogv|mkv|avi|3gp|png|jpe?g|gif|webp|bmp|svg|avif|heic)(?:[?#\s]|$)/i.exec(combined);
    if (match) return '.' + match[1].toLowerCase();
    return kind === 'video' ? '.mp4' : '.png';
  }
  private async downloadMediaToLocalCache(owner: T3Client, url: string, kind: string, displayPath: string): Promise<string> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const dir = context.cacheDir + '/t3-media-cache';
    try { fileIo.mkdirSync(dir); } catch (_) {}
    let hash = 2166136261;
    for (let i = 0; i < url.length; i += 1) {
      hash ^= url.charCodeAt(i);
      hash = Math.imul(hash, 16777619) >>> 0;
    }
    const ext = this.mediaFileExtension(displayPath, url, kind);
    const filePath = dir + '/m-' + hash.toString(16) + '-' + url.length + ext;
    try {
      const stat = fileIo.statSync(filePath);
      if (stat.size > 0) return fileUri.getUriFromPath(filePath);
    } catch (_) {}
    const bytes = await owner.downloadUrlBytes(url);
    const tmpPath = filePath + '.tmp-' + Date.now();
    const file = fileIo.openSync(tmpPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, bytes);
      fileIo.fsyncSync(file.fd);
    } finally {
      fileIo.closeSync(file);
    }
    try { fileIo.renameSync(tmpPath, filePath); }
    catch (_) {
      try { fileIo.unlinkSync(tmpPath); } catch (_) {}
      const direct = fileIo.openSync(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try { fileIo.writeSync(direct.fd, bytes); fileIo.fsyncSync(direct.fd); } finally { fileIo.closeSync(direct); }
    }
    try {
      const entries = fileIo.listFileSync(dir);
      if (entries.length > 24) {
        const dated: MediaCacheEntry[] = entries.map((name: string): MediaCacheEntry => {
          const full = dir + '/' + name;
          let mtime = 0;
          try { mtime = fileIo.statSync(full).mtime; } catch (_) {}
          return { full, mtime };
        }).sort((a: MediaCacheEntry, b: MediaCacheEntry): number => a.mtime - b.mtime);
        for (let i = 0; i < dated.length - 24; i += 1) {
          if (dated[i].full !== filePath) {
            try { fileIo.unlinkSync(dated[i].full); } catch (_) {}
          }
        }
      }
    } catch (_) {}
    return fileUri.getUriFromPath(filePath);
  }
  private setAttachmentPreviewUri(attachmentId: string, uri: string): void {
    if (!attachmentId || !uri || this.attachmentPreviewMap[attachmentId] === uri) return;
    const next: Record<string, string> = {};
    for (const key of Object.keys(this.attachmentPreviewMap)) {
      next[key] = this.attachmentPreviewMap[key];
    }
    next[attachmentId] = uri;
    this.attachmentPreviewMap = next;
  }
  private attachmentPreviewCachePath(item: DraftAttachment): string {
    const safeId = (item.id || '').replace(/[^A-Za-z0-9_-]/g, '');
    if (!safeId) return '';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const dir = context.cacheDir + '/t3-media-cache';
      try { fileIo.mkdirSync(dir); } catch (_) {}
      const ext = this.mediaFileExtension(item.name, '', 'image');
      return dir + '/att-' + safeId + ext;
    } catch (_) {
      return '';
    }
  }
  private lookupLocalAttachmentPreview(item: DraftAttachment): string {
    const existing = this.attachmentPreviewMap[item.id];
    if (existing) return existing;
    if (composerAttachmentKind(item.type, item.name, item.mimeType) !== 'image') return '';
    const filePath = this.attachmentPreviewCachePath(item);
    if (!filePath) return '';
    try {
      const stat = fileIo.statSync(filePath);
      if (stat.size > 0) {
        const uri = fileUri.getUriFromPath(filePath);
        this.setAttachmentPreviewUri(item.id, uri);
        return uri;
      }
    } catch (_) {}
    return '';
  }
  private cacheComposerAttachmentPreview(item: DraftAttachment, bytes: ArrayBuffer): string {
    if (composerAttachmentKind(item.type, item.name, item.mimeType) !== 'image' || bytes.byteLength <= 0) return '';
    const filePath = this.attachmentPreviewCachePath(item);
    if (!filePath) return '';
    try {
      const tmpPath = filePath + '.tmp-' + Date.now();
      const file = fileIo.openSync(tmpPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(file.fd, bytes);
        fileIo.fsyncSync(file.fd);
      } finally {
        fileIo.closeSync(file);
      }
      try { fileIo.renameSync(tmpPath, filePath); }
      catch (_) {
        try { fileIo.unlinkSync(tmpPath); } catch (_) {}
        const direct = fileIo.openSync(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
        try { fileIo.writeSync(direct.fd, bytes); fileIo.fsyncSync(direct.fd); } finally { fileIo.closeSync(direct); }
      }
      const uri = fileUri.getUriFromPath(filePath);
      this.setAttachmentPreviewUri(item.id, uri);
      return uri;
    } catch (_) {
      return '';
    }
  }
  private async resolveComposerAttachmentPreview(item: DraftAttachment): Promise<string> {
    const local = this.lookupLocalAttachmentPreview(item);
    if (local) return local;
    return client.attachmentUrl(item.id, item.name, item.mimeType || 'application/octet-stream', true);
  }
  private async downloadComposerAttachmentPreview(url: string, item: DraftAttachment): Promise<string> {
    const localUri = await this.downloadMediaToLocalCache(client, url, 'image', item.name);
    if (localUri) this.setAttachmentPreviewUri(item.id, localUri);
    return localUri;
  }
  private async loadMediaBytesFor(
    owner: T3Client,
    threadId: string,
    cwd: string,
    source: string,
    currentUrl: string
  ): Promise<ArrayBuffer> {
    if (source.startsWith('t3-attachment://')) {
      const id = source.slice('t3-attachment://'.length);
      const att = this.resolveAttachmentById(id);
      if (!att) throw new Error('附件已不在当前快照中');
      return owner.downloadAttachment(att.id, att.name, att.mimeType || 'application/octet-stream');
    }
    if (currentUrl && currentUrl.startsWith('file://')) {
      try {
        return readLocalFileUriBytes(currentUrl);
      } catch (_) {}
    }
    if (currentUrl && /^data:/i.test(currentUrl)) {
      const decoded = decodeDataUriBytes(currentUrl);
      if (decoded) return decoded;
    }
    if (source && /^data:/i.test(source)) {
      const decoded = decodeDataUriBytes(source);
      if (decoded) return decoded;
    }
    if (currentUrl && /^https?:\/\//i.test(currentUrl)) {
      try {
        return await owner.downloadUrlBytes(currentUrl);
      } catch (firstError) {
        if (source) {
          const classified = classifyMarkdownMediaSource(source, cwd);
          if (classified.access === 'environment') {
            const refreshed = await owner.markdownMediaUrlForThread(threadId, source, cwd, true);
            if (refreshed.url) return owner.downloadUrlBytes(refreshed.url);
          }
        }
        throw firstError as Error;
      }
    }
    if (source) {
      const resolved = await owner.markdownMediaUrlForThread(threadId, source, cwd, false);
      if (resolved.url) {
        if (/^data:/i.test(resolved.url)) {
          const decoded = decodeDataUriBytes(resolved.url);
          if (decoded) return decoded;
        }
        return owner.downloadUrlBytes(resolved.url);
      }
    }
    throw new Error('没有可下载的媒体资源');
  }

  private markdownPreviewFileName(): string {
    return mediaFileName(this.markdownImagePath, this.markdownImageAlt, this.markdownImageUrl, '', this.markdownImageKind);
  }

  private markdownPreviewCanSaveGallery(): boolean {
    return !!this.markdownImageUrl && canSaveToPhotoGallery(this.markdownPreviewFileName(), '', this.markdownImageKind);
  }

  private async saveMarkdownMediaToGallery(viaSaveButton: boolean): Promise<void> {
    if (this.markdownImageBusy || (!this.markdownImageUrl && !this.markdownImageSource)) return;
    const owner = this.markdownImageOwner || client;
    const fileName = this.markdownPreviewFileName();
    if (!canSaveToPhotoGallery(fileName, '', this.markdownImageKind)) {
      await this.saveMarkdownMediaToFile();
      return;
    }
    this.markdownImageBusy = true;
    this.markdownImageStatus = '正在保存到相册…';
    try {
      const bytes = await this.loadMediaBytesFor(
        owner,
        this.markdownImageThreadId,
        this.markdownImageCwd,
        this.markdownImageSource,
        this.markdownImageUrl
      );
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const outcome = await saveBytesToPhotoGallery(context, bytes, fileName, '', this.markdownImageKind, viaSaveButton);
      this.markdownImageStatus = outcome === 'saved' ? '已保存到相册' : '已取消保存';
    } catch (error) {
      this.markdownImageStatus = '保存失败：' + (error as Error).message;
    } finally {
      this.markdownImageBusy = false;
    }
  }

  private async saveMarkdownMediaToFile(): Promise<void> {
    if (this.markdownImageBusy || (!this.markdownImageUrl && !this.markdownImageSource)) return;
    const owner = this.markdownImageOwner || client;
    const fileName = this.markdownPreviewFileName();
    this.markdownImageBusy = true;
    this.markdownImageStatus = '正在下载…';
    try {
      const bytes = await this.loadMediaBytesFor(
        owner,
        this.markdownImageThreadId,
        this.markdownImageCwd,
        this.markdownImageSource,
        this.markdownImageUrl
      );
      const outcome = await saveBytesToDocumentPicker(bytes, fileName);
      this.markdownImageStatus = outcome === 'saved' ? '已保存到所选位置' : '已取消保存';
    } catch (error) {
      this.markdownImageStatus = '保存失败：' + (error as Error).message;
    } finally {
      this.markdownImageBusy = false;
    }
  }

  private async shareMarkdownMedia(): Promise<void> {
    if (this.markdownImageBusy || (!this.markdownImageUrl && !this.markdownImageSource)) return;
    const owner = this.markdownImageOwner || client;
    const scope = this.markdownImageScopeId || this.selectedLocalId || 'media';
    const expectedUrl = this.markdownImageUrl;
    const expectedSource = this.markdownImageSource;
    const fileName = this.markdownPreviewFileName();
    this.markdownImageBusy = true;
    this.markdownImageStatus = '正在准备分享…';
    try {
      const bytes = await this.loadMediaBytesFor(
        owner,
        this.markdownImageThreadId,
        this.markdownImageCwd,
        expectedSource,
        expectedUrl
      );
      if (this.panel !== 'markdown-image' || this.markdownImageSource !== expectedSource) {
        throw new Error('分享目标已变化');
      }
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await shareBytesWithSystemSheet(context, bytes, fileName, scope, '', this.markdownImageKind);
      this.markdownImageStatus = '已打开系统分享';
    } catch (error) {
      this.markdownImageStatus = '分享失败：' + (error as Error).message;
    } finally {
      this.markdownImageBusy = false;
    }
  }

  private async saveInlineMediaToGalleryFor(
    owner: T3Client,
    threadId: string,
    cwd: string,
    source: string,
    alt: string,
    kind: string,
    resolvedUrl: string,
    displayPath: string
  ): Promise<void> {
    if (this.busy) return;
    const att = source.startsWith('t3-attachment://') ? this.resolveAttachmentById(source.slice('t3-attachment://'.length)) : undefined;
    const mime = att ? att.mimeType : '';
    const fileName = att ? att.name : mediaFileName(displayPath || source, alt, resolvedUrl, mime, kind);
    if (!canSaveToPhotoGallery(fileName, mime, kind)) {
      await this.saveInlineMediaToFileFor(owner, threadId, cwd, source, alt, kind, resolvedUrl, displayPath);
      return;
    }
    this.busy = true;
    this.status = '正在保存到相册…';
    try {
      const bytes = await this.loadMediaBytesFor(owner, threadId, cwd, source, resolvedUrl);
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const outcome = await saveBytesToPhotoGallery(context, bytes, fileName, mime, kind, false);
      this.status = outcome === 'saved' ? '已保存到相册' : '已取消保存';
    } catch (error) {
      this.status = '保存失败：' + (error as Error).message;
    } finally {
      this.busy = false;
    }
  }

  private async saveInlineMediaToFileFor(
    owner: T3Client,
    threadId: string,
    cwd: string,
    source: string,
    alt: string,
    kind: string,
    resolvedUrl: string,
    displayPath: string
  ): Promise<void> {
    if (this.busy) return;
    const att = source.startsWith('t3-attachment://') ? this.resolveAttachmentById(source.slice('t3-attachment://'.length)) : undefined;
    const mime = att ? att.mimeType : '';
    const fileName = att ? att.name : mediaFileName(displayPath || source, alt, resolvedUrl, mime, kind);
    this.busy = true;
    this.status = '正在下载…';
    try {
      const bytes = await this.loadMediaBytesFor(owner, threadId, cwd, source, resolvedUrl);
      const outcome = await saveBytesToDocumentPicker(bytes, fileName);
      this.status = outcome === 'saved' ? '已保存到所选位置' : '已取消保存';
    } catch (error) {
      this.status = '保存失败：' + (error as Error).message;
    } finally {
      this.busy = false;
    }
  }

  private async shareInlineMediaFor(
    owner: T3Client,
    scopeId: string,
    threadId: string,
    cwd: string,
    source: string,
    alt: string,
    kind: string,
    resolvedUrl: string,
    displayPath: string
  ): Promise<void> {
    if (this.busy) return;
    const att = source.startsWith('t3-attachment://') ? this.resolveAttachmentById(source.slice('t3-attachment://'.length)) : undefined;
    const mime = att ? att.mimeType : '';
    const fileName = att ? att.name : mediaFileName(displayPath || source, alt, resolvedUrl, mime, kind);
    this.busy = true;
    this.status = '正在准备分享…';
    try {
      const bytes = await this.loadMediaBytesFor(owner, threadId, cwd, source, resolvedUrl);
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await shareBytesWithSystemSheet(context, bytes, fileName, scopeId || this.selectedLocalId || 'media', mime, kind);
      this.status = '已打开系统分享';
    } catch (error) {
      this.status = '分享失败：' + (error as Error).message;
    } finally {
      this.busy = false;
    }
  }

  private async openMarkdownImageFor(
    owner: T3Client,
    threadId: string,
    cwd: string,
    value: string,
    scopeId: string = '',
    alt: string = ''
  ): Promise<void> {
    if (value.startsWith('t3-attachment://')) {
      const id = value.slice('t3-attachment://'.length);
      const att = this.resolveAttachmentById(id);
      if (att) {
        await this.openAttachment(att.name);
        return;
      }
    }
    const classified = classifyMarkdownMediaSource(value, cwd);
    if (classified.access === 'direct') {
      this.markdownImageOwner = owner;
      this.markdownImageScopeId = scopeId || this.selectedLocalId;
      this.markdownImageThreadId = threadId;
      this.markdownImageCwd = cwd;
      this.markdownImageSource = value;
      this.markdownImageAlt = alt;
      this.markdownImageUrl = classified.uri;
      this.markdownImageKind = classified.kind;
      this.markdownImagePath = /^https?:\/\//i.test(classified.uri) ? classified.uri : '';
      this.markdownImageStatus = '';
      this.markdownImageBusy = false;
      this.openPanel('markdown-image');
      return;
    }
    if (classified.access === 'blocked') {
      this.status = '不支持打开此媒体路径';
      return;
    }
    try {
      const resolved = await owner.markdownMediaUrlForThread(threadId, value, cwd, true);
      this.markdownImageOwner = owner;
      this.markdownImageScopeId = scopeId || this.selectedLocalId;
      this.markdownImageThreadId = threadId;
      this.markdownImageCwd = cwd;
      this.markdownImageSource = value;
      this.markdownImageAlt = alt;
      this.markdownImageUrl = resolved.url;
      this.markdownImageKind = resolved.kind;
      this.markdownImagePath = resolved.displayPath;
      this.markdownImageStatus = '';
      this.markdownImageBusy = false;
      this.openPanel('markdown-image');
    } catch (error) { this.status = (error as Error).message; }
  }
  private async openMarkdownImage(value: string): Promise<void> {
    const tid = !this.draftMode && client.thread ? client.thread.threadId : '';
    await this.openMarkdownImageFor(client, tid, this.currentWorkspace(), value, this.selectedLocalId);
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
      let latest: PreviewTab | undefined = undefined;
      for (const item of existing) {
        if (!latest || (item.updatedAt || '') > (latest.updatedAt || '')) latest = item;
      }
      const selected = existing.find((item: PreviewTab): boolean => item.tabId === known) || latest || existing[0];
      this.previewTabs.set(this.previewKey, selected ? selected.tabId : '');
      this.previewAddress = selected ? selected.url : '';
      this.previewAutoConnect = !!selected;
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
    const env = this.previewConnection ? optionalRecord(this.previewConnection.config.environment) : undefined;
    return this.previewCurrent() && !!this.previewConnection?.ready &&
      previewNeedsZoomRepair(env ? env.serverVersion : undefined);
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
    this.filesOverrideCwd = '';
    this.filesInitialPath = '';
    this.filesInitialDir = '';
    this.filesInitialLine = 0;
    this.filesDirectFileOnly = false;
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
      if (this.panel === 'cloud') { this.closeCloudPanel(); return true; }
      if (this.panel === 'connection-new') {
        const backToLinked = this.linkedConnectTarget !== undefined && this.linkedThreadTarget !== undefined;
        this.panel = backToLinked ? 'linked-thread' : 'server';
        this.credential = '';
        this.routeFor = '';
        this.linkedConnectTarget = undefined;
        this.pairingError = false;
      }
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
    if (this.page === 'linked-thread') {
      void this.leaveLinkedThreadPage();
      return true;
    }
    if (this.page === 'chat') {
      if (this.sideThreadReturnStack && this.sideThreadReturnStack.length > 0) {
        void this.returnToParentThread();
        return true;
      }
      this.page = 'sessions';
      return true;
    }
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
    if (this.page === 'files' || this.page === 'html-viewer') { this.returnToChatWithScrollRestore(); return true; }
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
    this.clearInlineMention();
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
    this.ensureBrowserPreviewWatch();
  }
  private refreshLinkedWhenChanged(): void {
    if (!this.appForeground || !this.panelOpen || this.panel !== 'server') return;
    const registry = this.registry();
    const signature = registry.directory.entries.map((entry: EnvironmentEntry) =>
      entry.localId + ':' + entry.label + ':' + String(entry.enabled) + ':' + String(entry.deleting) + ':' + String(registry.clients.get(entry.localId)?.ready)).join('\n');
    if (signature === this.linkedSignature) return;
    this.linkedSignature = signature; void this.loadLinkedEnvironments();
  }
  private canLinkBatchMap(): Record<string, boolean> {
    const result: Record<string, boolean> = {};
    for (const entry of this.environmentEntries) {
      if (entry.deleting || !entry.enabled) continue;
      const conn = this.registry().clients.get(entry.localId);
      if (conn && conn.ready && conn.linkedEnvironmentsEnabled()) {
        result[entry.localId] = true;
      }
    }
    return result;
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
    if (visible.length >= 0) this.linkedGroups = visible;
  }

  private async removePeerLinkFromConnections(
    sourceLocalId: string,
    targetEnvironmentId: string,
    targetLabel: string
  ): Promise<void> {
    const owner = this.registry().clients.get(sourceLocalId);
    if (!owner || !owner.ready) throw new Error('源环境未连接，无法解除互链');
    const result = await owner.removePeerLink(targetEnvironmentId);
    this.status = peerLinkRemoveMessage(targetLabel, result);
    await this.loadLinkedEnvironments();
  }

  private async answerAgentFeedbackItem(
    turnItemId: string,
    answer: AgentFeedbackAnswer,
    includeConversation: boolean
  ): Promise<void> {
    if (this.draftMode || !this.threadId) throw new Error('当前会话不可答复反馈');
    try {
      await client.answerAgentFeedback(this.threadId, turnItemId, answer, includeConversation);
      this.status = answer === 'send' ? '反馈报告已发送' : '已拒绝发送该反馈报告';
    } catch (reason) {
      const msg = agentFeedbackErrorMessage(reason as Object);
      this.status = msg;
      throw new Error(msg);
    }
  }

  private async toggleModelFavorite(provider: string, model: string, favorite: boolean): Promise<void> {
    const previousLocal = this.localFavorites.slice();
    const updatedLocal = await setLocalModelFavorite(provider, model, favorite);
    this.localFavorites = updatedLocal;
    if (client.ready && client.canScope('settings:write') !== false) {
      try {
        await client.setModelFavorite(provider, model, favorite, previousLocal);
      } catch (reason) {
        this.status = (reason as Error).message || '模型收藏同步失败（已保存在本机）';
      }
    }
  }

  private reportScopedGitStatus(originLocalId: string, originThreadId: string, message: string): void {
    const key = originLocalId + ':' + originThreadId;
    if (this.selectedLocalId + ':' + this.threadId !== key) return;
    this.gitBannerThreadKey = key;
    this.gitBannerText = message;
    this.status = message;
  }

  private async sendMcpAppMessage(textValue: string): Promise<void> {
    const body = textValue.trim();
    if (!body || this.draftMode || !client.ready || this.busy || this.unknown) {
      throw new Error('当前无法发送消息');
    }
    const running = !!client.thread?.runs.some((run: Record<string, Object>) =>
      ['preparing', 'starting', 'running', 'waiting'].includes(String(run.status)));
    await client.send(body, followUpDelivery('auto', running, workspacePrefs.followUpBehavior), []);
  }

  private async startPrAgentTask(localId: string, projectId: string, prompt: string): Promise<void> {
    if (this.busy || this.unknown) {
      this.status = '请先等待当前操作完成';
      return;
    }
    const registry = this.registry();
    const targetLocal = localId || this.selectedLocalId;
    try {
      if (targetLocal && targetLocal !== this.selectedLocalId && registry.clients.has(targetLocal)) {
        await registry.select(targetLocal);
      }
      const targetProject = projectId || this.projectId || (this.projects.length > 0 ? this.projects[0].id : '');
      if (!targetProject) {
        this.status = '未找到关联项目，请先选择一个项目';
        this.openProjectPicker();
        return;
      }
      this.homeTabDetailOpen = false;
      await this.beginDraft(targetProject);
      this.prompt = prompt;
      this.page = 'chat';
    } catch (reason) {
      this.status = (reason as Error).message || '无法发起 PR Agent 任务';
    }
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
  attachmentActionsMenu() {
    Menu() {
      if (this.selectedAttachment && canSaveToPhotoGallery(
        this.selectedAttachment.name,
        this.selectedAttachment.mimeType,
        this.attachmentMediaKind(this.selectedAttachment)
      )) {
        MenuItem({ content: '保存到相册' }).onClick(() => { void this.saveAttachmentToGallery(false); })
      }
      MenuItem({ content: '保存到文件' }).onClick(() => { void this.saveAttachment(); })
      MenuItem({ content: '分享' }).onClick(() => { void this.shareAttachment(); })
      if (this.attachmentPreviewUrl && /^https?:\/\//i.test(this.attachmentPreviewUrl)) {
        MenuItem({ content: '复制预览链接' }).onClick(() => { void this.copy(this.attachmentPreviewUrl); })
      }
    }
  }

  @Builder
  markdownMediaActionsMenu() {
    Menu() {
      if (this.markdownPreviewCanSaveGallery()) {
        MenuItem({ content: '保存到相册' }).onClick(() => { void this.saveMarkdownMediaToGallery(false); })
      }
      MenuItem({ content: '保存到文件' }).onClick(() => { void this.saveMarkdownMediaToFile(); })
      MenuItem({ content: '分享' }).onClick(() => { void this.shareMarkdownMedia(); })
      if (mediaCopyValue(this.markdownImagePath, this.markdownImageUrl)) {
        MenuItem({ content: mediaCopyLabel(this.markdownImagePath, this.markdownImageUrl) })
          .onClick(() => {
            const target = mediaCopyValue(this.markdownImagePath, this.markdownImageUrl);
            if (target) void this.copy(target);
          })
      }
    }
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
        }) {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            Image($r('app.media.ui_more'))
              .width(Sizes.icon)
              .height(Sizes.icon)
              .objectFit(ImageFit.Contain)
              .draggable(false)
              .accessibilityLevel('no')
          }
          .width(Sizes.iconHit)
          .height(Sizes.iconHit)
          .backgroundColor(Color.Transparent)
          .accessibilityText('附件操作')
          .bindMenu(this.attachmentActionsMenu())
        }
        if (this.attachmentPreviewUrl && (this.selectedAttachment.mimeType === 'text/html' || isHtml(this.selectedAttachment.name))) {
          Column({ space: Space.sm }) {
            Column() {
              HtmlRenderWebView({
                uri: this.attachmentPreviewUrl,
                title: this.selectedAttachment.name,
                nested: false,
                isHtmlRender: false,
                onOpenExternalLink: (url: string) => { void this.openExternalUrl(url); }
              })
            }
            .width('100%')
            .layoutWeight(1)
            .backgroundColor($r('app.color.card'))
            .borderRadius(Radius.card)
            .clip(true)
            Row({ space: Space.xs }) {
              Column() {
                AppButton({
                  label: this.busy ? '保存中…' : '保存到文件',
                  kind: 'primary',
                  fill: true,
                  disabled: this.busy,
                  onTap: () => { void this.saveAttachment(); }
                })
              }.layoutWeight(1)
              Column() {
                AppButton({
                  label: '分享',
                  kind: 'secondary',
                  fill: true,
                  disabled: this.busy,
                  onTap: () => { void this.shareAttachment(); }
                })
              }.layoutWeight(1)
            }.width('100%')
            if (this.attachmentStatus) {
              Text(this.attachmentStatus).fontSize(FontSize.caption).fontColor($r('app.color.muted')).width('100%')
            }
          }.layoutWeight(1).width('100%').padding({ left: Space.page, right: Space.page, top: Space.xs, bottom: Space.md }).alignItems(HorizontalAlign.Start)
        } else {
          Scroll() {
            Column({ space: Space.sm }) {
              if ((this.selectedAttachment.type === 'image' || this.attachmentMediaKind(this.selectedAttachment) === 'image') && this.attachmentPreviewUrl) {
                Image(this.attachmentPreviewUrl).width('100%').constraintSize({ maxHeight: 420 })
                  .objectFit(ImageFit.Contain).backgroundColor($r('app.color.card')).borderRadius(Radius.card)
                  .onError(() => {
                    const failedUrl = this.attachmentPreviewUrl;
                    const att = this.selectedAttachment;
                    if (att && /^https?:\/\//i.test(failedUrl)) {
                      void this.downloadMediaToLocalCache(client, failedUrl, 'image', att.name).then((localUri: string) => {
                        if (this.attachmentPreviewUrl === failedUrl && localUri) this.attachmentPreviewUrl = localUri;
                      }).catch((err: Error) => { this.attachmentStatus = err.message || '图片加载失败'; });
                    }
                  })
              }
              if ((this.selectedAttachment.mimeType.startsWith('video/') || this.attachmentMediaKind(this.selectedAttachment) === 'video') && this.attachmentPreviewUrl) {
                Video({ src: this.attachmentPreviewUrl }).width('100%').height(320).objectFit(ImageFit.Contain).controls(true)
                  .backgroundColor(Color.Black).borderRadius(Radius.card)
                  .onError(() => {
                    const failedUrl = this.attachmentPreviewUrl;
                    const att = this.selectedAttachment;
                    if (att && /^https?:\/\//i.test(failedUrl)) {
                      void this.downloadMediaToLocalCache(client, failedUrl, 'video', att.name).then((localUri: string) => {
                        if (this.attachmentPreviewUrl === failedUrl && localUri) this.attachmentPreviewUrl = localUri;
                      }).catch((err: Error) => { this.attachmentStatus = err.message || '视频加载失败'; });
                    }
                  })
              }
              if (canSaveToPhotoGallery(
                this.selectedAttachment.name,
                this.selectedAttachment.mimeType,
                this.attachmentMediaKind(this.selectedAttachment)
              )) {
                Column({ space: Space.xs }) {
                  Row({ space: Space.xs }) {
                    Column() {
                      SaveButton({
                        icon: SaveIconStyle.FULL_FILLED,
                        text: SaveDescription.SAVE_TO_GALLERY,
                        buttonType: ButtonType.Normal
                      })
                        .width('100%')
                        .height(Sizes.buttonHeight)
                        .borderRadius(Radius.button)
                        .backgroundColor($r('app.color.prominent'))
                        .fontColor($r('app.color.on_prominent'))
                        .iconColor($r('app.color.on_prominent'))
                        .fontSize(FontSize.body)
                        .iconSize(16)
                        .onClick((event: ClickEvent, result: SaveButtonOnClickResult) => {
                          if (this.busy) return;
                          if (result === SaveButtonOnClickResult.SUCCESS) {
                            void this.saveAttachmentToGallery(true);
                          } else if (result === SaveButtonOnClickResult.CANCELED_BY_USER) {
                            this.attachmentStatus = '已取消保存';
                          } else {
                            void this.saveAttachmentToGallery(false);
                          }
                        })
                    }.layoutWeight(1)
                    Column() {
                      AppButton({
                        label: '分享',
                        kind: 'secondary',
                        fill: true,
                        disabled: this.busy,
                        onTap: () => { void this.shareAttachment(); }
                      })
                    }.layoutWeight(1)
                  }.width('100%')
                  Row({ space: Space.xs }) {
                    Column() {
                      AppButton({
                        label: this.busy ? '保存中…' : '保存到文件',
                        kind: 'secondary',
                        compact: true,
                        fill: true,
                        disabled: this.busy,
                        onTap: () => { void this.saveAttachment(); }
                      })
                    }.layoutWeight(1)
                    if (this.attachmentPreviewUrl && /^https?:\/\//i.test(this.attachmentPreviewUrl)) {
                      Column() {
                        AppButton({
                          label: '复制链接',
                          kind: 'secondary',
                          compact: true,
                          fill: true,
                          onTap: () => { void this.copy(this.attachmentPreviewUrl); }
                        })
                      }.layoutWeight(1)
                    }
                  }.width('100%')
                }
                .width('100%')
                .padding(Space.sm)
                .backgroundColor($r('app.color.card'))
                .borderRadius(Radius.card)
              } else {
                Column({ space: Space.xs }) {
                  if (this.attachmentPreviewUrl && /^https?:\/\//i.test(this.attachmentPreviewUrl)) {
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
                }
                .width('100%')
                .padding(Space.sm)
                .backgroundColor($r('app.color.card'))
                .borderRadius(Radius.card)
              }
              if (this.attachmentStatus) {
                Text(this.attachmentStatus).fontSize(FontSize.caption).fontColor($r('app.color.muted')).width('100%')
              }
            }.width('100%').padding({ left: Space.page, right: Space.page, top: Space.xs, bottom: Space.md }).alignItems(HorizontalAlign.Start)
          }.layoutWeight(1).width('100%').align(Alignment.TopStart)
        }
      }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
    } else if (this.panel === 'markdown-image') {
      Column() {
        TopBar({
          title: this.markdownPreviewFileName(),
          subtitle: this.markdownImageKind === 'video' ? '视频预览' : '图片预览',
          showBack: true,
          closeStyle: true,
          onBack: () => { this.panelOpen = false; }
        }) {
          if (this.markdownImageUrl || this.markdownImageSource) {
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              Image($r('app.media.ui_more'))
                .width(Sizes.icon)
                .height(Sizes.icon)
                .objectFit(ImageFit.Contain)
                .draggable(false)
                .accessibilityLevel('no')
            }
            .width(Sizes.iconHit)
            .height(Sizes.iconHit)
            .backgroundColor(Color.Transparent)
            .accessibilityText('媒体操作')
            .bindMenu(this.markdownMediaActionsMenu())
          }
        }
        Scroll() {
          Column({ space: Space.sm }) {
            Column({ space: Space.sm }) {
              if (this.markdownImageUrl && this.markdownImageKind === 'video') {
                Video({ src: this.markdownImageUrl }).width('100%').height(320).objectFit(ImageFit.Contain).controls(true)
                  .backgroundColor(Color.Black).borderRadius(Radius.tool)
                  .onError(() => {
                    const failedUrl = this.markdownImageUrl;
                    const owner = this.markdownImageOwner || client;
                    if (/^https?:\/\//i.test(failedUrl)) {
                      void this.downloadMediaToLocalCache(owner, failedUrl, 'video', this.markdownImagePath).then((localUri: string) => {
                        if (this.markdownImageUrl === failedUrl && localUri) this.markdownImageUrl = localUri;
                      }).catch((err: Error) => { this.markdownImageStatus = err.message || '视频加载失败'; });
                    }
                  })
              } else if (this.markdownImageUrl) {
                Image(this.markdownImageUrl).width('100%').constraintSize({ maxHeight: 460 })
                  .objectFit(ImageFit.Contain).borderRadius(Radius.tool)
                  .onError(() => {
                    const failedUrl = this.markdownImageUrl;
                    const owner = this.markdownImageOwner || client;
                    if (/^https?:\/\//i.test(failedUrl)) {
                      void this.downloadMediaToLocalCache(owner, failedUrl, 'image', this.markdownImagePath).then((localUri: string) => {
                        if (this.markdownImageUrl === failedUrl && localUri) this.markdownImageUrl = localUri;
                      }).catch((err: Error) => { this.markdownImageStatus = err.message || '图片加载失败'; });
                    }
                  })
              } else {
                Text(this.markdownImageKind === 'video' ? '没有可播放的视频' : '没有可显示的图片').fontSize(FontSize.callout).fontColor($r('app.color.muted')).width('100%')
              }
              if (this.markdownImagePath) {
                Text(this.markdownImagePath)
                  .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted'))
                  .width('100%').maxLines(2).wordBreak(WordBreak.BREAK_ALL)
              }
            }.padding(Space.md).width('100%').backgroundColor($r('app.color.card')).borderRadius(Radius.card).alignItems(HorizontalAlign.Start)

            if (this.markdownImageUrl || this.markdownImageSource) {
              Column({ space: Space.xs }) {
                Row({ space: Space.xs }) {
                  if (this.markdownPreviewCanSaveGallery()) {
                    Column() {
                      SaveButton({
                        icon: SaveIconStyle.FULL_FILLED,
                        text: SaveDescription.SAVE_TO_GALLERY,
                        buttonType: ButtonType.Normal
                      })
                        .width('100%')
                        .height(Sizes.buttonHeight)
                        .borderRadius(Radius.button)
                        .backgroundColor($r('app.color.prominent'))
                        .fontColor($r('app.color.on_prominent'))
                        .iconColor($r('app.color.on_prominent'))
                        .fontSize(FontSize.body)
                        .iconSize(16)
                        .onClick((event: ClickEvent, result: SaveButtonOnClickResult) => {
                          if (this.markdownImageBusy) return;
                          if (result === SaveButtonOnClickResult.SUCCESS) {
                            void this.saveMarkdownMediaToGallery(true);
                          } else if (result === SaveButtonOnClickResult.CANCELED_BY_USER) {
                            this.markdownImageStatus = '已取消保存';
                          } else {
                            void this.saveMarkdownMediaToGallery(false);
                          }
                        })
                    }.layoutWeight(1)
                  } else {
                    Column() {
                      AppButton({
                        label: this.markdownImageBusy ? '保存中…' : '保存到文件',
                        kind: 'primary',
                        fill: true,
                        disabled: this.markdownImageBusy,
                        onTap: () => { void this.saveMarkdownMediaToFile(); }
                      })
                    }.layoutWeight(1)
                  }
                  Column() {
                    AppButton({
                      label: '分享',
                      kind: 'secondary',
                      fill: true,
                      disabled: this.markdownImageBusy,
                      onTap: () => { void this.shareMarkdownMedia(); }
                    })
                  }.layoutWeight(1)
                }.width('100%')

                Row({ space: Space.xs }) {
                  if (this.markdownPreviewCanSaveGallery()) {
                    Column() {
                      AppButton({
                        label: this.markdownImageBusy ? '处理中…' : '保存到文件',
                        kind: 'secondary',
                        compact: true,
                        fill: true,
                        disabled: this.markdownImageBusy,
                        onTap: () => { void this.saveMarkdownMediaToFile(); }
                      })
                    }.layoutWeight(1)
                  }
                  if (mediaCopyValue(this.markdownImagePath, this.markdownImageUrl)) {
                    Column() {
                      AppButton({
                        label: mediaCopyLabel(this.markdownImagePath, this.markdownImageUrl),
                        kind: 'secondary',
                        compact: true,
                        fill: true,
                        onTap: () => {
                          const target = mediaCopyValue(this.markdownImagePath, this.markdownImageUrl);
                          if (target) void this.copy(target);
                        }
                      })
                    }.layoutWeight(1)
                  }
                }.width('100%')
              }
              .width('100%')
              .padding(Space.sm)
              .backgroundColor($r('app.color.card'))
              .borderRadius(Radius.card)
            }

            if (this.markdownImageStatus) {
              Text(this.markdownImageStatus)
                .fontSize(FontSize.caption)
                .lineHeight(LineHeight.caption)
                .fontColor($r('app.color.muted'))
                .width('100%')
            }
          }.width('100%').padding({ left: Space.page, right: Space.page, top: Space.xs, bottom: Space.md }).alignItems(HorizontalAlign.Start)
        }.layoutWeight(1).width('100%').align(Alignment.TopStart)
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
            Text('使用系统粘贴按钮读取剪贴板中的结构化上下文片段；不会读取密码或任意页面。')
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
        mentionThreads: this.commandPanel === 'mention' ? this.sheetMentionGroups().threads : [],
        mentionEnvironments: this.commandPanel === 'mention' ? this.sheetMentionGroups().environments : [],
        mentionModels: this.commandPanel === 'mention' ? this.sheetMentionGroups().models : [],
        mentionFileItems: this.commandPanel === 'mention' ? this.sheetMentionGroups().files : [],
        mentionLoading: this.commandPanel === 'mention' ? this.mentionLoading : false,
        branches: this.branches, environments: this.environmentLabels(),
        repoChoices: this.draftRepoChoices,
        repoChoicesLoaded: this.draftRepoChoicesLoaded,
        selectedRepos: this.draftWorkspace.repositories,
        worktree: this.draftWorkspace.mode === 'worktree',
        startFromOrigin: this.draftWorkspace.startFromOrigin,
        onClose: () => this.panelOpen = false,
        onQuery: (value: string) => {
          if (this.commandPanel === 'mention') this.triggerSheetMentionSearch(value, false);
          else this.commandQuery = value;
        },
        onCommand: (value: string) => this.insertCommand(value),
        onSkill: (name: string) => { this.addSkillContext(name); this.panelOpen = false; },
        onFile: (path: string) => { this.addFileContext(path); this.panelOpen = false; },
        onMentionSelect: (item: MentionItem) => { this.applyMentionItem(item); },
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
        onSwitchCheckout: () => { void this.applyCurrentCheckoutBranch().catch((error: Error) => this.status = error.message); },
        onRepositoriesChange: (paths: string[]) => this.updateDraftRepositories(paths),
        onOpenRepositories: () => { this.commandPanel = 'repositories'; this.commandQuery = ''; }
      })
    } else if (this.panel === 'extras') {
      ThreadExtrasPanel({ busy: this.busy, plans: this.extraPlans, subagents: this.extraSubagents,
        sideChats: sideChatsForThread(this.threads, this.threadId),
        backgroundTasks: this.extraBackground,
        usage: this.extraUsage, guest: this.extraGuest, connected: this.ready,
        onClose: () => this.panelOpen = false,
        onCopy: (value: string) => { void this.copy(value); },
        onOpenThread: (threadId: string, remoteEnvironmentId: string, remoteLabel: string) => {
          void this.openSideThread('subagent', threadId, remoteEnvironmentId, remoteLabel);
        },
        onOpenSideChat: (threadId: string) => {
          void this.openSideThread('side-chat', threadId, '', '');
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
        onOpenThread: (threadId: string, remoteEnvironmentId: string, remoteLabel: string) => {
          void this.openRemoteOrLocalThread(threadId, remoteEnvironmentId, remoteLabel);
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
        onOpenThread: (threadId: string) => { void this.openSideThread('subagent', threadId, '', ''); },
        onStopAll: () => { this.stopBackgroundWork(); }
      })
    } else if (this.panelOpen && this.panel === 'task-settings') {
      TaskSettingsPanel({ models: this.models, config: client.config, localFavorites: this.localFavorites,
        settings: this.taskSettings, busy: this.busy || this.unknown, status: this.status,
        onSave: (settings: TaskSettings) => { void this.saveTaskSettings(settings); }, onClose: () => this.panelOpen = false,
        onInstall: (id: string) => { void this.installProvider(id); },
        onAuth: (id: string) => { void this.startProviderAuth(id); },
        onRefreshProviders: (id: string) => { void this.refreshProvider(id); },
        onToggleFavorite: (provider: string, model: string, favorite: boolean) =>
          this.toggleModelFavorite(provider, model, favorite) })
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
        }.width('100%').layoutWeight(1).align(Alignment.TopStart).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
    } else if (this.panel === 'cloud') {
      CloudAccountPanel({
        configured: this.cloudConfigured,
        signInReady: this.cloudSignInReady,
        signedIn: this.cloudSignedIn,
        accountId: this.cloudAccountId,
        accountEmail: this.cloudAccountEmail,
        accountDisplayName: this.cloudAccountDisplayName,
        deviceCode: this.cloudDeviceCode,
        relayUrl: this.cloudRelayUrl,
        publishableKey: this.cloudPublishableKey,
        jwtTemplate: this.cloudJwtTemplate,
        isCustomConfig: this.cloudCustomConfig,
        showOnboarding: this.cloudShowOnboarding,
        status: this.cloudStatus,
        error: this.cloudError,
        busy: this.cloudBusy,
        refreshing: this.cloudRefreshing,
        environments: this.cloudEnvironments,
        entries: this.environmentEntries,
        approvalCodes: this.environmentApprovalCodes,
        ssoProviders: this.cloudSsoProviders,
        emailCodeEnabled: this.cloudEmailCodeEnabled,
        passwordEnabled: this.cloudPasswordEnabled,
        pendingSsoStrategy: this.cloudPendingSsoStrategy,
        signInStep: this.cloudSignInStep,
        signInEmail: this.cloudSignInEmail,
        canUseEmailCode: this.cloudCanUseEmailCode,
        canUsePassword: this.cloudCanUsePassword,
        secondFactors: this.cloudSecondFactors,
        backLabel: this.cloudReturnPanel ? '返回' : '关闭',
        onClose: () => this.closeCloudPanel(),
        onCopy: (value: string) => { void this.copy(value); },
        onBeginSso: (strategy: string) => this.cloudBeginSso(strategy),
        onStartEmail: (email: string) => this.cloudStartEmail(email),
        onSendEmailCode: () => this.cloudSendEmailCode(),
        onVerifyEmailCode: (code: string) => this.cloudVerifyEmailCode(code),
        onVerifyPassword: (password: string) => this.cloudVerifyPassword(password),
        onPrepareSecondFactor: (strategy: string) => this.cloudPrepareSecondFactor(strategy),
        onVerifySecondFactor: (strategy: string, code: string) => this.cloudVerifySecondFactor(strategy, code),
        onCancelSignIn: () => this.cloudCancelSignIn(),
        onSignOut: () => this.cloudSignOut(),
        onRefresh: () => this.cloudRefresh(),
        onConnect: (id: string) => this.cloudConnect(id),
        onLink: (id: string) => this.cloudLink(id),
        onUnlink: (id: string) => this.cloudUnlink(id),
        onResetDeviceKey: () => this.cloudResetDeviceKey(),
        onDismissOnboarding: (dontShowAgain: boolean) => { this.cloudManager().dismissOnboarding(dontShowAgain); this.syncCloudState(); },
        onSaveCustomConfig: (pk: string, tpl: string, relayUrl: string) => this.cloudSaveCustomConfig(pk, tpl, relayUrl),
        onResetCustomConfig: () => this.cloudResetCustomConfig()
      })
    } else if (this.panel === 'side-thread' && this.sideThreadTarget) {
      SideThreadPanel({
        target: this.sideThreadTarget,
        ownerClient: this.registry().clients.get(this.sideThreadTarget.localId) || client,
        ownerReady: this.environmentReady[this.sideThreadTarget.localId] === true ||
          (this.sideThreadTarget.localId === this.selectedLocalId && this.ready),
        onClose: () => {
          this.panelOpen = false;
          this.sideThreadTarget = undefined;
        },
        onOpenInMain: () => {
          const current = this.sideThreadTarget;
          if (!current) return;
          this.panelOpen = false;
          this.sideThreadTarget = undefined;
          void this.openSideThread(current.kind, current.threadId, current.environmentId, current.environmentLabel, 'main');
        },
        onCopy: (value: string) => { void this.copy(value); },
        onOpenLink: (url: string) => { void this.openLink(url); },
        onOpenImage: (source: string) => {
          const target = this.sideThreadTarget;
          const owner = target ? (this.registry().clients.get(target.localId) || client) : client;
          void this.openMarkdownImageFor(owner, target ? target.threadId : '', owner.threadCwd(), source, target ? target.localId : this.selectedLocalId);
        },
        onShareMedia: (source: string, alt: string, kind: string, resolvedUrl: string, displayPath: string) => {
          const target = this.sideThreadTarget;
          const owner = target ? (this.registry().clients.get(target.localId) || client) : client;
          void this.shareInlineMediaFor(owner, target ? target.localId : this.selectedLocalId, target ? target.threadId : '', owner.threadCwd(), source, alt, kind, resolvedUrl, displayPath);
        },
        onSaveMediaToGallery: (source: string, alt: string, kind: string, resolvedUrl: string, displayPath: string) => {
          const target = this.sideThreadTarget;
          const owner = target ? (this.registry().clients.get(target.localId) || client) : client;
          void this.saveInlineMediaToGalleryFor(owner, target ? target.threadId : '', owner.threadCwd(), source, alt, kind, resolvedUrl, displayPath);
        },
        onSaveMediaToFile: (source: string, alt: string, kind: string, resolvedUrl: string, displayPath: string) => {
          const target = this.sideThreadTarget;
          const owner = target ? (this.registry().clients.get(target.localId) || client) : client;
          void this.saveInlineMediaToFileFor(owner, target ? target.threadId : '', owner.threadCwd(), source, alt, kind, resolvedUrl, displayPath);
        },
        downloadLocalMedia: (url: string, kind: string, displayPath: string): Promise<string> => {
          const target = this.sideThreadTarget;
          const owner = target ? (this.registry().clients.get(target.localId) || client) : client;
          return this.downloadMediaToLocalCache(owner, url, kind, displayPath);
        }
      })
    } else if (this.panel === 'linked-thread' && this.linkedThreadTarget) {
      LinkedThreadPanel({
        target: this.linkedThreadTarget,
        viaClient: this.registry().clients.get(this.linkedThreadTarget.viaLocalId) || client,
        viaReady: this.environmentReady[this.linkedThreadTarget.viaLocalId] === true ||
          (this.linkedThreadTarget.viaLocalId === this.selectedLocalId && this.ready),
        showOpenInMain: true,
        connecting: this.linkedConnecting,
        connectNotice: this.linkedConnectNotice,
        connectError: this.linkedConnectError,
        onOpenInMain: () => {
          const current = this.linkedThreadTarget;
          if (!current) return;
          this.panelOpen = false;
          const parentPos = this.captureCurrentChatPosition();
          if (parentPos) {
            this.sideThreadReturnStack = pushSideThreadReturn(this.sideThreadReturnStack, parentPos);
          }
          this.page = 'linked-thread';
        },
        onConnect: (target: LinkedThreadTarget) => this.connectLinkedThreadEnvironment(target),
        onClose: () => {
          this.panelOpen = false;
          this.linkedThreadTarget = undefined;
          this.linkedConnectNotice = '';
          this.linkedConnectError = false;
        },
        onCopy: (value: string) => { void this.copy(value); },
        onOpenLink: (url: string) => { void this.openLink(url); },
        onOpenImage: (source: string) => { void this.openMarkdownImage(source); },
        onShareMedia: (source: string, alt: string, kind: string, resolvedUrl: string, displayPath: string) => {
          const tid = !this.draftMode && client.thread ? client.thread.threadId : '';
          void this.shareInlineMediaFor(client, this.selectedLocalId, tid, this.currentWorkspace(), source, alt, kind, resolvedUrl, displayPath);
        },
        onSaveMediaToGallery: (source: string, alt: string, kind: string, resolvedUrl: string, displayPath: string) => {
          const tid = !this.draftMode && client.thread ? client.thread.threadId : '';
          void this.saveInlineMediaToGalleryFor(client, tid, this.currentWorkspace(), source, alt, kind, resolvedUrl, displayPath);
        },
        onSaveMediaToFile: (source: string, alt: string, kind: string, resolvedUrl: string, displayPath: string) => {
          const tid = !this.draftMode && client.thread ? client.thread.threadId : '';
          void this.saveInlineMediaToFileFor(client, tid, this.currentWorkspace(), source, alt, kind, resolvedUrl, displayPath);
        },
        downloadLocalMedia: (url: string, kind: string, displayPath: string): Promise<string> =>
          this.downloadMediaToLocalCache(client, url, kind, displayPath)
      })
    } else if (this.panel === 'peer-link' && this.activeLink && this.linkOwner) {
      PeerLinkForm({ request: this.activeLink, machines: this.linkMachines, connection: this.linkOwner,
        onClose: () => { this.panelOpen = false; },
        onBusy: (busy: boolean) => { this.busy = busy; if (!busy) { this.peerCanAnswer = this.linkOwner === client && !!this.linkOwner?.canManagePeerAccess(); this.incomingPairing(); } } })
    } else if (this.panel === 'link-batch' && this.linkBatchSourceLocalId) {
      LinkSeveralEnvironmentsPanel({
        sourceLocalId: this.linkBatchSourceLocalId,
        sourceLabel: this.environmentEntries.find((e: EnvironmentEntry) => e.localId === this.linkBatchSourceLocalId)?.label || '当前环境',
        entries: this.environmentEntries,
        connectionFor: (localId: string) => this.registry().clients.get(localId),
        onClose: () => { this.panel = 'server'; this.linkBatchSourceLocalId = ''; },
        onLinked: () => { void this.loadLinkedEnvironments(); }
      })
    } else if (this.panel === 'server') {
          ConnectionsPanel({ entries: this.environmentEntries, linkedGroups: this.linkedGroups, statuses: this.environmentStatuses, readyMap: this.environmentReady, approvalCodes: this.environmentApprovalCodes, canLinkBatchMap: this.canLinkBatchMap(), initialized: this.loaded,
            cloudConfigured: this.cloudConfigured, cloudSignedIn: this.cloudSignedIn, cloudAccountLabel: this.cloudAccountSummary(), cloudStatus: this.cloudStatus, cloudEnvironments: this.cloudEnvironments,
            deviceEnvironmentLabel: this.deviceEnvironmentLabel, pendingDevices: this.pendingDevices,
            approvedDevices: this.approvedDevices,
            onClose: () => { this.panelOpen = false; this.credential = ''; },
            onAdd: () => { this.routeFor = ''; this.linkedConnectTarget = undefined; this.address = ''; this.credential = ''; this.pairingError = false; this.pairingStatus = '填写地址与配对码后确认'; this.panel = 'connection-new'; },
            onAddRoute: (id: string) => { this.routeFor = id; this.linkedConnectTarget = undefined; this.address = ''; this.credential = ''; this.pairingError = false; this.pairingStatus = '为当前环境添加连接路径'; this.panel = 'connection-new'; },
            onLinkBatch: (localId: string) => { this.linkBatchSourceLocalId = localId; this.panel = 'link-batch'; },
            onRemoveLink: (sourceLocalId: string, targetEnvironmentId: string, targetLabel: string) =>
              this.removePeerLinkFromConnections(sourceLocalId, targetEnvironmentId, targetLabel),
            onInitialize: () => this.restoreAddress(),
            onRetry: (id: string) => this.registry().reconnect(id),
            onEnabled: (id: string, enabled: boolean) => this.registry().setEnabled(id, enabled),
            onEdit: (id: string, label: string, address: string) => this.registry().edit(id, label, address),
            onRemove: (id: string) => this.forget(id),
            onReorderRoutes: (id: string, references: string[]) => this.registry().reorderRoutes(id, references),
            onRemoveRoute: (id: string, reference: string) => this.registry().removeRoute(id, reference),
            onRouting: (id: string, permission: string) => this.registry().setPullRequestRouting(id, permission),
            onCloudAccount: () => this.openCloudPanel('server'),
            onConnectCloud: (id: string) => this.cloudConnect(id),
            onLinkCloud: (id: string) => this.cloudLink(id),
            onApproveDevice: (id: string) => this.approveDevice(id),
            onDenyDevice: (id: string) => this.denyDevice(id),
            onRevokeDevice: (id: string) => this.revokeDevice(id),
            onCopy: (value: string) => { void this.copy(value); } })
    } else if (this.panel === 'connection-new') {
      Column({ space: 0 }) {
        TopBar({
          title: this.routeFor ? '添加路径' : (this.linkedConnectTarget ? '连接 ' + (this.linkedConnectTarget.label || '环境') : '添加环境'),
          showBack: true,
          backLabel: this.linkedConnectTarget ? '返回只读会话' : '返回环境',
          onBack: () => {
            const backToLinked = this.linkedConnectTarget !== undefined && this.linkedThreadTarget !== undefined;
            this.panel = backToLinked ? 'linked-thread' : 'server';
            this.credential = '';
            this.routeFor = '';
            this.linkedConnectTarget = undefined;
            this.pairingError = false;
          }
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
                  subtitle: this.cloudSignedIn ? (this.cloudAccountSummary() || this.cloudStatus || '使用托管中继') : '通过上游托管中继访问已链接的机器（可切换自建中继）',
                  value: '',
                  disabled: this.busy,
                  isFirst: true,
                  onTap: () => this.openCloudPanel('connection-new')
                })
              }
            }
          }.width('100%').padding({ left: Space.sm, right: Space.sm, top: Space.xs, bottom: Space.lg }).alignItems(HorizontalAlign.Start)
        }.width('100%').layoutWeight(1).align(Alignment.TopStart).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
    } else if (this.panel === 'mcp-sign-in' && this.activeMcpSignIn) {
      McpSignInPanel({
        connection: client,
        target: this.activeMcpSignIn,
        onOpenExternalUrl: (url: string) => this.openExternalUrl(url),
        onSignedIn: (server: string) => {
          this.panelOpen = false;
          this.activeMcpSignIn = undefined;
          this.status = '已完成 MCP 服务「' + server + '」登录';
        },
        onClose: () => {
          this.panelOpen = false;
          this.activeMcpSignIn = undefined;
        }
      })
    } else if (this.panel === 'mcp-app' && this.fullscreenMcpApp) {
      Column({ space: 0 }) {
        TopBar({
          title: this.fullscreenMcpApp.app.title,
          subtitle: this.fullscreenMcpApp.app.server + ' · ' + this.fullscreenMcpApp.app.tool,
          showBack: true,
          closeStyle: true,
          backLabel: '关闭应用',
          onBack: () => {
            this.panelOpen = false;
            this.fullscreenMcpApp = undefined;
          }
        })
        McpAppView({
          connection: client,
          entry: this.fullscreenMcpApp,
          threadId: this.threadId,
          fullscreen: true,
          onExitFullscreen: () => {
            this.panelOpen = false;
            this.fullscreenMcpApp = undefined;
          },
          onOpenExternalLink: (url: string) => { void this.openExternalUrl(url); },
          onSendMessage: (body: string) => this.sendMcpAppMessage(body)
        }).layoutWeight(1)
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
                subtitle: this.floatingCapsule.browserPreview
                  ? this.floatingCapsule.browserPreview.label + ' · 查看与控制远端页面'
                  : '查看与控制本地开发页面',
                disabled: !(this.ready && !this.draftMode &&
                  (client.canScope('preview:operate') !== false || this.floatingCapsule.browserPreview !== undefined)),
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
        }.width('100%').layoutWeight(1).align(Alignment.TopStart).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
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
          this.emptyState('添加你的工作环境', '连接你的远程工作环境（兼容 T3 Code 服务端），在手机上继续工作。')
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
        onSelect: (thread: ScopedThread) => { this.sideThreadReturnStack = []; this.pendingScrollRestore = undefined; void this.openScopedThread(thread); },
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
  messageAttachmentsView(message: ChatMessage, userStyle: boolean) {
    if (message.attachments && message.attachments.length > 0) {
      ForEach(message.attachments, (att: ChatAttachment) => {
        if (this.attachmentMediaKind(att) !== '') {
          Column() {
            MarkdownMediaBlock({
              source: 't3-attachment://' + att.id,
              alt: att.name,
              initialKind: this.attachmentMediaKind(att),
              scopeKey: this.markdownMediaScopeKey(),
              mediaReady: this.ready,
              resolveMedia: (source: string, refresh: boolean): Promise<ResolvedMarkdownMedia> =>
                this.resolveMarkdownMedia(source, refresh),
              downloadLocalMedia: (url: string, kind: string, displayPath: string): Promise<string> =>
                this.downloadMediaToLocalCache(client, url, kind, displayPath),
              onOpenImage: () => { void this.openAttachment(att.name); },
              onCopy: (value: string) => { void this.copy(value); },
              onShareMedia: (source: string, alt: string, kind: string, resolvedUrl: string, displayPath: string) => {
                const tid = !this.draftMode && client.thread ? client.thread.threadId : '';
                void this.shareInlineMediaFor(client, this.selectedLocalId, tid, this.currentWorkspace(), source, alt, kind, resolvedUrl, displayPath);
              },
              onSaveMediaToGallery: (source: string, alt: string, kind: string, resolvedUrl: string, displayPath: string) => {
                const tid = !this.draftMode && client.thread ? client.thread.threadId : '';
                void this.saveInlineMediaToGalleryFor(client, tid, this.currentWorkspace(), source, alt, kind, resolvedUrl, displayPath);
              },
              onSaveMediaToFile: (source: string, alt: string, kind: string, resolvedUrl: string, displayPath: string) => {
                const tid = !this.draftMode && client.thread ? client.thread.threadId : '';
                void this.saveInlineMediaToFileFor(client, tid, this.currentWorkspace(), source, alt, kind, resolvedUrl, displayPath);
              }
            })
          }.width(userStyle ? '84%' : '100%')
        } else {
          Button('附件 · ' + att.name, { type: ButtonType.Normal })
            .constraintSize({ minHeight: 36, minWidth: userStyle ? 0 : '100%' })
            .fontSize(FontSize.callout).fontColor($r('app.color.ink'))
            .backgroundColor($r('app.color.card')).border({ width: Sizes.hairline, color: $r('app.color.border') })
            .borderRadius(Radius.tool).padding({ left: Space.sm, right: Space.sm })
            .onClick(() => { void this.openAttachment(att.name); })
        }
      }, (att: ChatAttachment) => att.id + ':' + att.name)
    } else if (message.attachmentNames && message.attachmentNames.length > 0) {
      ForEach(message.attachmentNames, (name: string) => {
        Button('附件 · ' + name, { type: ButtonType.Normal })
          .constraintSize({ minHeight: 36, minWidth: userStyle ? 0 : '100%' })
          .fontSize(FontSize.callout).fontColor($r('app.color.ink'))
          .backgroundColor($r('app.color.card')).border({ width: Sizes.hairline, color: $r('app.color.border') })
          .borderRadius(Radius.tool).padding({ left: Space.sm, right: Space.sm })
          .onClick(() => { void this.openAttachment(name); })
      })
    }
  }

  @Builder
  userBubble(message: ChatMessage) {
    Row() {
      Column({ space: Space.xs }) {
        this.messageAttachmentsView(message, true)
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
            .constraintSize({ maxWidth: '84%' }).clip(true)
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
                onShareMedia: (source: string, alt: string, kind: string, resolvedUrl: string, displayPath: string) => {
                  const tid = !this.draftMode && client.thread ? client.thread.threadId : '';
                  void this.shareInlineMediaFor(client, this.selectedLocalId, tid, this.currentWorkspace(), source, alt, kind, resolvedUrl, displayPath);
                },
                onSaveMediaToGallery: (source: string, alt: string, kind: string, resolvedUrl: string, displayPath: string) => {
                  const tid = !this.draftMode && client.thread ? client.thread.threadId : '';
                  void this.saveInlineMediaToGalleryFor(client, tid, this.currentWorkspace(), source, alt, kind, resolvedUrl, displayPath);
                },
                onSaveMediaToFile: (source: string, alt: string, kind: string, resolvedUrl: string, displayPath: string) => {
                  const tid = !this.draftMode && client.thread ? client.thread.threadId : '';
                  void this.saveInlineMediaToFileFor(client, tid, this.currentWorkspace(), source, alt, kind, resolvedUrl, displayPath);
                },
                resolveMedia: (source: string, refresh: boolean): Promise<ResolvedMarkdownMedia> =>
                  this.resolveMarkdownMedia(source, refresh),
                downloadLocalMedia: (url: string, kind: string, displayPath: string): Promise<string> =>
                  this.downloadMediaToLocalCache(client, url, kind, displayPath) })
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
      this.messageAttachmentsView(message, false)
      MarkdownView({ markdown: message.text, selectable: true,
        mediaScopeKey: this.markdownMediaScopeKey(),
        mediaReady: this.ready,
        onCopy: (value: string) => { void this.copy(value); },
        onOpenLink: (url: string) => { void this.openLink(url); },
        onOpenImage: (url: string) => { void this.openMarkdownImage(url); },
        onShareMedia: (source: string, alt: string, kind: string, resolvedUrl: string, displayPath: string) => {
          const tid = !this.draftMode && client.thread ? client.thread.threadId : '';
          void this.shareInlineMediaFor(client, this.selectedLocalId, tid, this.currentWorkspace(), source, alt, kind, resolvedUrl, displayPath);
        },
        onSaveMediaToGallery: (source: string, alt: string, kind: string, resolvedUrl: string, displayPath: string) => {
          const tid = !this.draftMode && client.thread ? client.thread.threadId : '';
          void this.saveInlineMediaToGalleryFor(client, tid, this.currentWorkspace(), source, alt, kind, resolvedUrl, displayPath);
        },
        onSaveMediaToFile: (source: string, alt: string, kind: string, resolvedUrl: string, displayPath: string) => {
          const tid = !this.draftMode && client.thread ? client.thread.threadId : '';
          void this.saveInlineMediaToFileFor(client, tid, this.currentWorkspace(), source, alt, kind, resolvedUrl, displayPath);
        },
        resolveMedia: (source: string, refresh: boolean): Promise<ResolvedMarkdownMedia> =>
          this.resolveMarkdownMedia(source, refresh),
        downloadLocalMedia: (url: string, kind: string, displayPath: string): Promise<string> =>
          this.downloadMediaToLocalCache(client, url, kind, displayPath) })
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
      htmlRenders: group.htmlRenders,
      htmlRenderScopeKey: this.markdownMediaScopeKey(),
      headerLabel: group.runMeta ? group.runMeta.headerLabel : '',
      summaryLabel: group.summary.label,
      summaryIcon: group.summary.summaryIcon,
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
      onOpenDiff: () => this.openReview(),
      onOpenHtmlFullscreen: (entry: HtmlRenderEntry, uri: string) => this.openHtmlFullscreen(entry, uri),
      onOpenExternalLink: (url: string) => { void this.openExternalUrl(url); }
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
              (this.draftWorkspace.branch || (this.draftWorkspace.mode === 'worktree' && !this.draftIsGitRepo && this.draftRepoChoices.length > 0 ? '各仓库默认分支' : '未选分支')) +
              (this.draftWorkspace.mode === 'local' && this.draftRepoChoices.length > 0 ? (' · ' + this.draftRepoChoices.length + ' 个仓库') : ''))
              .fontSize(FontSize.callout).fontColor($r('app.color.ink')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            Image($r('app.media.ui_chevron_right')).width(12).height(12).accessibilityLevel('no')
          }.width('100%').alignItems(VerticalAlign.Center)
        }.width('100%').constraintSize({ minHeight: 36 }).padding({ left: Space.sm, right: Space.xs })
          .backgroundColor($r('app.color.group')).borderRadius(Radius.button).enabled(!this.busy)
          .accessibilityDescription('选择分支与工作区').onClick(() => this.openComposerCommand('branch'))
        if (this.draftWorkspace.mode === 'worktree' && (this.draftRepoChoices.length > 0 || !this.draftRepoChoicesLoaded)) {
          Button({ type: ButtonType.Normal }) {
            Row({ space: 4 }) {
              Text('关联仓库 · ' + resolveWorktreeRepositorySelection(
                this.draftRepoChoicesLoaded ? this.draftRepoChoices : null,
                this.draftWorkspace.repositories
              ).label)
                .fontSize(FontSize.callout)
                .fontColor(resolveWorktreeRepositorySelection(
                  this.draftRepoChoicesLoaded ? this.draftRepoChoices : null,
                  this.draftWorkspace.repositories
                ).needsChoice ? $r('app.color.warning') : $r('app.color.ink'))
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
              Image($r('app.media.ui_chevron_right')).width(12).height(12).accessibilityLevel('no')
            }.width('100%').alignItems(VerticalAlign.Center)
          }.width('100%').constraintSize({ minHeight: 36 }).padding({ left: Space.sm, right: Space.xs })
            .backgroundColor($r('app.color.group')).borderRadius(Radius.button).enabled(!this.busy)
            .accessibilityDescription('选择新工作树包含的关联仓库')
            .onClick(() => this.openComposerCommand('repositories'))
        }
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
                htmlRenderScopeKey: this.markdownMediaScopeKey(),
                onToggleGroup: (group: TurnWorkGroup) => this.toggleWorkGroup(group),
                onCopy: (value: string) => { void this.copy(value); },
                onReference: (line: ActivityLine) => this.addTerminalContext(line),
                onOpenDiff: () => this.openReview(),
                onOpenHtmlFullscreen: (entry: HtmlRenderEntry, uri: string) => this.openHtmlFullscreen(entry, uri),
                onOpenExternalLink: (url: string) => { void this.openExternalUrl(url); }
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
                htmlRenderScopeKey: this.markdownMediaScopeKey(),
                onToggleGroup: (group: TurnWorkGroup) => this.toggleWorkGroup(group),
                onCopy: (value: string) => { void this.copy(value); },
                onReference: (line: ActivityLine) => this.addTerminalContext(line),
                onOpenDiff: () => this.openReview(),
                onOpenHtmlFullscreen: (entry: HtmlRenderEntry, uri: string) => this.openHtmlFullscreen(entry, uri),
                onOpenExternalLink: (url: string) => { void this.openExternalUrl(url); }
              })
            } else if (message.role !== 'user' && !this.draftMode) {
              MessageWorkSlot({
                connection: client,
                messageId: message.id,
                slotKind: 'afterAssistant',
                htmlRenderScopeKey: this.markdownMediaScopeKey(),
                onToggleGroup: (group: TurnWorkGroup) => this.toggleWorkGroup(group),
                onCopy: (value: string) => { void this.copy(value); },
                onReference: (line: ActivityLine) => this.addTerminalContext(line),
                onOpenDiff: () => this.openReview(),
                onOpenHtmlFullscreen: (entry: HtmlRenderEntry, uri: string) => this.openHtmlFullscreen(entry, uri),
                onOpenExternalLink: (url: string) => { void this.openExternalUrl(url); }
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
      if (!this.draftMode && this.gitBannerText && this.gitBannerThreadKey === this.selectedLocalId + ':' + this.threadId) {
        ListItem() {
          Row({ space: Space.xs }) {
            Text(this.gitBannerText)
              .fontSize(FontSize.caption)
              .lineHeight(LineHeight.caption)
              .fontColor($r('app.color.ink'))
              .layoutWeight(1)
            Button('关闭', { type: ButtonType.Normal })
              .height(28)
              .fontSize(FontSize.badge)
              .fontColor($r('app.color.muted'))
              .backgroundColor(Color.Transparent)
              .onClick(() => { this.gitBannerText = ''; this.gitBannerThreadKey = ''; })
          }
          .width('100%')
          .padding({ left: Space.sm, right: Space.xs, top: Space.xs, bottom: Space.xs })
          .backgroundColor($r('app.color.card'))
          .borderRadius(Radius.tool)
          .alignItems(VerticalAlign.Center)
        }
      }
      ForEach(this.actions, (card: ActionCard) => { ListItem() { RequestCard({ card, connection: client }) } }, (card: ActionCard) => this.selectedLocalId + ':' + card.id)
      ForEach(this.feedbackItems, (item: AgentFeedbackRequestView) => {
        ListItem() {
          FeedbackRequestCard({
            item,
            canOperate: this.canOperateChat,
            busy: this.busy || this.unknown,
            onAnswer: (turnItemId: string, answer: AgentFeedbackAnswer, includeConversation: boolean) =>
              this.answerAgentFeedbackItem(turnItemId, answer, includeConversation)
          })
        }
      }, (item: AgentFeedbackRequestView) => this.selectedLocalId + ':' + item.id + ':' + item.status)
      ForEach(this.mcpSignInNotices, (notice: McpSignInNoticeView) => {
        ListItem() {
          Column({ space: Space.xs }) {
            Text('MCP 服务需要登录：' + notice.server)
              .fontSize(FontSize.body).fontWeight(Weight.semibold).fontColor($r('app.color.ink')).width('100%')
            if (notice.message) {
              Text(notice.message).fontSize(FontSize.callout).lineHeight(LineHeight.callout)
                .fontColor($r('app.color.muted')).width('100%')
            }
            AppButton({
              label: '登录到 ' + notice.server + '…',
              kind: 'primary',
              compact: true,
              fill: true,
              disabled: !this.ready || this.busy || this.unknown || client.canScope('providers:manage') === false,
              onTap: () => {
                this.activeMcpSignIn = notice;
                this.panel = 'mcp-sign-in';
                this.panelOpen = true;
              }
            })
          }
          .padding(Space.md).width('100%')
          .backgroundColor($r('app.color.card'))
          .border({ width: 1, color: $r('app.color.border') })
          .borderRadius(Radius.card)
          .alignItems(HorizontalAlign.Start)
        }
      }, (notice: McpSignInNoticeView) => this.selectedLocalId + ':mcpsignin:' + notice.id + ':' + notice.server)
      ForEach(this.mcpAppEntries, (entry: McpAppEntry) => {
        ListItem() {
          McpAppView({
            connection: client,
            entry,
            threadId: this.threadId,
            fullscreen: false,
            onExpand: (target: McpAppEntry) => {
              this.fullscreenMcpApp = target;
              this.panel = 'mcp-app';
              this.panelOpen = true;
            },
            onOpenExternalLink: (url: string) => { void this.openExternalUrl(url); },
            onSendMessage: (body: string) => this.sendMcpAppMessage(body)
          })
        }
      }, (entry: McpAppEntry) => this.selectedLocalId + ':mcpapp:' + entry.id + ':' + entry.revision)
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
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .onScrollIndex((start: number): void => {
          this.chatScrollIndex = start;
        })
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
        onOpenBrowserPreview: () => { void this.openPreview(); },
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
    if (this.inlineMentionTrigger !== undefined && !this.busy && !this.unknown && !this.panelOpen) {
      Column() {
        ComposerMentionPopover({
          items: this.inlineMentionItems,
          query: this.inlineMentionTrigger.query,
          loading: this.inlineMentionLoading,
          onSelect: (item: MentionItem) => {
            if (this.inlineMentionTrigger) {
              this.applyMentionItem(item, this.inlineMentionTrigger);
            }
          },
          onDismiss: () => this.dismissInlineMention()
        })
      }.width('100%').padding({ left: Space.sm, right: Space.sm, top: Space.xxs, bottom: Space.xxs })
    }
    Column({ space: 0 }) {
      if (this.draftContext.length || this.attachments.length || this.uploadingAttachment) {
        ComposerAttachmentStrip({
          attachments: this.attachments,
          contexts: this.draftContext,
          uploading: this.uploadingAttachment,
          previewUris: this.attachmentPreviewMap,
          scopeKey: this.markdownMediaScopeKey(),
          mediaReady: this.ready,
          lookupLocalPreview: (item: DraftAttachment): string => this.lookupLocalAttachmentPreview(item),
          resolvePreview: (item: DraftAttachment): Promise<string> => this.resolveComposerAttachmentPreview(item),
          downloadLocalPreview: (url: string, item: DraftAttachment): Promise<string> =>
            this.downloadComposerAttachmentPreview(url, item),
          onOpenAttachment: (item: DraftAttachment) => { void this.openAttachmentItem(item); },
          onRemoveAttachment: (id: string) => {
            client.removeAttachment(id);
            this.refreshAttachments();
            this.scheduleDraftSave();
          },
          onRemoveContext: (contextId: string) => this.removeContext(contextId),
          onCancelUpload: () => this.cancelAttachmentUpload()
        })
      }
      Stack({ alignContent: Alignment.BottomStart }) {
        Row({ space: 4 }) {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            Image($r('app.media.ui_plus'))
              .width(20).height(20)
              .opacity(this.busy || this.unknown ? Opacity.disabled : 0.9)
              .accessibilityLevel('no')
          }.width(38).height(38).flexShrink(0)
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
            }.height(28).padding({ left: 10, right: 10 }).flexShrink(0)
              .backgroundColor($r('app.color.info_bg'))
              .accessibilityText('消息发送方式，' + (this.sendMode === 'queue' ? '排队' : '引导'))
              .bindMenu(this.composerSendModeMenu())
          }
          if (!this.composerExpanded) {
            Row()
              .layoutWeight(1)
              .height(38)
              .constraintSize({ minWidth: 60 })
              .hitTestBehavior(HitTestMode.None)
              .onAreaChange((_, area: Area) => {
                const x = Number(area.position.x);
                const w = Number(area.width);
                if (Number.isFinite(x) && Number.isFinite(w) && w > 0) {
                  if (Math.abs(x - this.compactSlotLeft) > 0.5 || Math.abs(w - this.compactSlotWidth) > 0.5) {
                    this.compactSlotLeft = x;
                    this.compactSlotWidth = w;
                    this.syncComposerExpanded();
                  }
                }
              })
            Button({ type: ButtonType.Normal, stateEffect: true }) {
              Row({ space: 3 }) {
                if (this.hasCurrentModelLogo()) {
                  Row() {
                    ProviderLogo({ driver: this.currentModelDriver(), model: this.currentModelSlug(), logoSize: 18 })
                  }.width(18).height(18).justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center).flexShrink(0)
                } else {
                  Image($r('app.media.ui_settings')).width(17).height(17).opacity(0.75).flexShrink(0).accessibilityLevel('no')
                }
                Image($r('app.media.ui_chevron_down')).width(11).height(11).opacity(0.65).flexShrink(0).accessibilityLevel('no')
              }.alignItems(VerticalAlign.Center)
            }.height(36).padding({ left: 8, right: 6 }).flexShrink(0)
              .backgroundColor(Color.Transparent)
              .borderRadius(Radius.button)
              .enabled(!this.busy && !this.unknown)
              .opacity(!this.busy && !this.unknown ? 1 : Opacity.disabled)
              .accessibilityText('模型与选项，' + (this.currentModelDisplayLabel() || '模型') +
                (this.currentModelSummary() ? ' ' + this.currentModelSummary() : ''))
              .onClick(() => this.openTaskSettings())
          } else {
            Row() {
              Button({ type: ButtonType.Normal, stateEffect: true }) {
                Row({ space: this.expandedModelIconOnly() ? 3 : 5 }) {
                  if (this.hasCurrentModelLogo()) {
                    Row() {
                      ProviderLogo({ driver: this.currentModelDriver(), model: this.currentModelSlug(), logoSize: 17 })
                    }.width(17).height(17).justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center).flexShrink(0)
                  } else {
                    Image($r('app.media.ui_settings')).width(16).height(16).opacity(0.75).flexShrink(0).accessibilityLevel('no')
                  }
                  if (!this.expandedModelIconOnly()) {
                    Text(this.currentModelDisplayLabel() || '模型')
                      .fontSize(FontSize.callout).lineHeight(LineHeight.callout)
                      .fontWeight(Weight.medium)
                      .fontColor($r('app.color.ink'))
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      .wordBreak(WordBreak.BREAK_ALL)
                      .constraintSize({ minWidth: 0, maxWidth: this.expandedModelMaxLabelWidth() })
                      .flexShrink(1)
                    if (this.expandedModelShowSummary()) {
                      Text(this.currentModelSummary())
                        .fontSize(FontSize.caption).lineHeight(LineHeight.caption)
                        .fontColor($r('app.color.muted'))
                        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                        .wordBreak(WordBreak.BREAK_ALL)
                        .constraintSize({ minWidth: 0, maxWidth: this.expandedModelMaxSummaryWidth() })
                        .flexShrink(1)
                    }
                  }
                  Image($r('app.media.ui_chevron_down')).width(12).height(12).opacity(0.7).flexShrink(0).accessibilityLevel('no')
                }
                .alignItems(VerticalAlign.Center)
                .constraintSize({ minWidth: 0, maxWidth: this.expandedModelMaxButtonWidth() })
                .clip(true)
              }.height(36).padding({ left: 8, right: 6 })
                .backgroundColor(Color.Transparent)
                .borderRadius(Radius.button)
                .constraintSize({ minWidth: 0, maxWidth: this.expandedModelMaxButtonWidth() })
                .clip(true)
                .enabled(!this.busy && !this.unknown)
                .opacity(!this.busy && !this.unknown ? 1 : Opacity.disabled)
                .accessibilityText('模型与选项，' + (this.currentModelDisplayLabel() || '模型') +
                  (this.currentModelSummary() ? ' ' + this.currentModelSummary() : ''))
                .onClick(() => this.openTaskSettings())
            }.layoutWeight(1).constraintSize({ minWidth: 0 }).justifyContent(FlexAlign.End).alignItems(VerticalAlign.Center).clip(true)
              .onAreaChange((_, area: Area) => {
                const w = Number(area.width);
                if (Number.isFinite(w) && w > 0 && Math.abs(w - this.expandedModelSlotWidth) > 0.5) {
                  this.expandedModelSlotWidth = w;
                }
              })
          }
          if (!this.draftMode && this.threadRunning && !this.busy && !this.unknown &&
            this.prompt.trim().length === 0 && this.attachments.length === 0 && this.draftContext.length === 0) {
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              Rect().width(11).height(11).radius(2.5).fill($r('app.color.danger'))
            }.width(36).height(36).flexShrink(0)
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
            }.width(36).height(36).flexShrink(0).backgroundColor($r('app.color.prominent'))
              .opacity(this.busy || (this.ready && !this.unknown && (this.prompt.trim().length > 0 || this.attachments.length > 0 || this.draftContext.length > 0)) ? 1 : 0.28)
              .accessibilityText(this.busy ? '正在提交' : '发送消息')
              .enabled(this.ready && !this.busy && !this.unknown && (this.prompt.trim().length > 0 || this.attachments.length > 0 || this.draftContext.length > 0))
              .onClick(() => this.send())
          } else {
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              if (this.busy) {
                LoadingProgress().width(16).height(16).color($r('app.color.on_prominent')).accessibilityLevel('no')
              } else {
                Image($r('app.media.ui_send')).width(17).height(17).accessibilityLevel('no')
              }
            }.width(36).height(36).flexShrink(0).backgroundColor($r('app.color.prominent'))
              .opacity(this.busy || (this.ready && !this.unknown && (this.prompt.trim().length > 0 || this.attachments.length > 0 || this.draftContext.length > 0)) ? 1 : 0.28)
              .accessibilityText(this.busy ? '正在提交' : '发送消息')
              .enabled(this.ready && !this.busy && !this.unknown && (this.prompt.trim().length > 0 || this.attachments.length > 0 || this.draftContext.length > 0))
              .bindContextMenu(this.sendModeContextMenu(), ResponseType.LongPress)
              .onClick(() => this.send())
          }
        }.width('100%').height(this.composerExpanded ? 46 : 48)
          .padding({ left: 6, right: 8, top: 0, bottom: this.composerExpanded ? 2 : 0 })
          .alignItems(VerticalAlign.Center)
        TextArea({
          placeholder: this.draftMode ? '描述要完成的任务…' : '继续追问…',
          text: this.prompt,
          controller: this.composerController
        })
          .id('composer-input')
          .width(this.composerExpanded ? '100%' : this.compactEditorGeometry().widthVp)
          .fontSize(FontSize.body).lineHeight(LineHeight.body)
          .fontColor($r('app.color.ink')).placeholderColor($r('app.color.placeholder'))
          .onChange((value: string, preview: PreviewText) => {
            const previewValue = preview?.value || '';
            this.composerPreviewText = previewValue;
            this.composingText = !!previewValue;
            const prevPrompt = this.prompt;
            const unchanged = prevPrompt === value;
            this.prompt = value;
            if (unchanged) this.syncComposerExpanded(value, previewValue);
            this.scheduleDraftSave();
            if (!previewValue) {
              const delta = value.length - prevPrompt.length;
              const baseCursor = this.composerCursor === this.composerSelectionEnd &&
                this.composerSelectionEnd <= prevPrompt.length
                ? this.composerSelectionEnd
                : prevPrompt.length;
              const estimated = Math.max(0, Math.min(value.length, baseCursor + delta));
              this.composerCursor = estimated;
              this.composerSelectionEnd = estimated;
              this.syncInlineMention(value, estimated, estimated);
            }
          })
          .onTextSelectionChange((selectionStart: number, selectionEnd: number) => {
            this.composerCursor = selectionStart;
            this.composerSelectionEnd = selectionEnd;
            if (!this.composingText) {
              this.syncInlineMention(this.prompt, selectionStart, selectionEnd);
            }
          })
          .onFocus(() => { this.composerFocused = true; this.keyboard.reset(); })
          .onBlur(() => { this.composerFocused = false; this.composingText = false; this.composerPreviewText = ''; this.keyboard.reset(); })
          .onKeyPreIme((event: KeyEvent): boolean => this.keyboardEvent(event, true))
          .onAreaChange((_, area: Area) => {
            const h = Number(area.height);
            if (Number.isFinite(h) && h > 0 && Math.abs(h - this.lastComposerEditorHeight) > 1) {
              this.lastComposerEditorHeight = h;
              this.syncComposerExpanded();
            }
          })
          .enterKeyType(EnterKeyType.NEW_LINE)
          .constraintSize({ minHeight: this.composerExpanded ? 46 : 38, maxHeight: 156 })
          .barState(BarState.Auto)
          .padding(this.composerExpanded
            ? { left: 14, right: 14, top: (this.draftContext.length || this.attachments.length || this.uploadingAttachment) ? 6 : 12, bottom: 4 }
            : { left: 4, right: 4, top: 8, bottom: 8 })
          .margin(this.composerExpanded
            ? { left: 0, bottom: 46 }
            : { left: this.compactEditorGeometry().leftVp, top: 5, bottom: 5 })
          .align(this.composerExpanded ? Alignment.TopStart : Alignment.Center)
          .backgroundColor(Color.Transparent).accessibilityText('消息输入框')
      }
      .width('100%')
      .onAreaChange((_, area: Area) => {
        const w = Number(area.width);
        if (Number.isFinite(w) && w > 0 && Math.abs(w - this.composerRowWidth) > 0.5) {
          const widthChanged = this.composerRowWidth > 0 && Math.abs(w - this.composerRowWidth) > 2;
          this.composerRowWidth = w;
          if (widthChanged && this.composerExpanded) {
            this.compactSlotWidth = 0;
          }
          this.syncComposerExpanded();
        }
      })
    }.margin({ left: Space.sm, right: Space.sm, top: Space.xxs, bottom: this.composerFocused ? Space.xs : Space.sm })
      .backgroundColor($r('app.color.group')).borderRadius(Radius.composer)
      .border({ width: 1, color: $r('app.color.border') })
      .clip(true)
  }

  private measureTextVp(value: string, fontSize: number, fontWeight: number = Weight.regular): number {
    if (!value) return 0;
    try {
      const ui = this.getUIContext();
      const px = ui.getMeasureUtils().measureText({ textContent: value, fontSize, fontWeight });
      const vp = ui.px2vp(px);
      return Number.isFinite(vp) && vp > 0 ? vp : 0;
    } catch (_) {
      return 0;
    }
  }

  private composerLineCount(): number {
    try {
      const count = this.composerController.getTextContentLineCount();
      return Number.isFinite(count) && count > 0 ? count : 0;
    } catch (_) {
      return 0;
    }
  }

  private compactEditorGeometry(): CompactEditorGeometry {
    return resolveCompactEditorGeometry({
      rowWidthVp: this.composerRowWidth,
      measuredSlotLeftVp: this.compactSlotLeft,
      measuredSlotWidthVp: this.compactSlotWidth,
      hasSendModeBadge: !this.draftMode && this.sendMode !== 'auto'
    });
  }

  private syncComposerExpanded(text: string = this.prompt, previewText: string = this.composerPreviewText): void {
    const effective = (text || '') + (previewText || '');
    const geom = this.compactEditorGeometry();
    const needsWidthMeasure = effective.length > 0 && !effective.includes('\n') && !effective.includes('\r');
    const singleLineTextWidthVp = needsWidthMeasure ? this.measureTextVp(effective, FontSize.body, Weight.regular) : 0;
    const next = shouldExpandComposer({
      text,
      previewText,
      compactTextWidthVp: geom.textWidthVp,
      singleLineTextWidthVp,
      measuredLineCount: effective.length > 0 ? this.composerLineCount() : 0,
      currentlyExpanded: this.composerExpanded
    });
    if (next !== this.composerExpanded) {
      this.composerExpanded = next;
    }
  }

  private onPromptStateChanged(): void {
    if (!this.prompt) this.composerPreviewText = '';
    this.syncComposerExpanded(this.prompt, this.composerPreviewText);
  }

  private onComposerChromeChanged(): void {
    if (this.composerExpanded) {
      this.compactSlotWidth = 0;
      this.expandedModelSlotWidth = 0;
    }
    this.syncComposerExpanded();
  }

  private expandedModelSlotWidthVp(): number {
    if (this.expandedModelSlotWidth > 0) return this.expandedModelSlotWidth;
    if (this.composerRowWidth > 0) {
      const reserved = (!this.draftMode && this.sendMode !== 'auto') ? 154 : 100;
      return Math.max(0, this.composerRowWidth - reserved);
    }
    return 0;
  }

  private expandedModelLayout(measureText: boolean): ExpandedModelLayout {
    const summary = this.currentModelSummary();
    const hasSummary = summary.length > 0;
    const label = this.currentModelDisplayLabel() || '模型';
    const labelWidth = measureText ? this.measureTextVp(label, FontSize.callout, Weight.medium) : 0;
    const summaryWidth = measureText && hasSummary ? this.measureTextVp(summary, FontSize.caption, Weight.regular) : 0;
    return layoutExpandedModelControl(this.expandedModelSlotWidthVp(), labelWidth, summaryWidth, hasSummary);
  }

  private expandedModelIconOnly(): boolean {
    return this.expandedModelLayout(false).iconOnly;
  }

  private expandedModelShowSummary(): boolean {
    return this.expandedModelLayout(false).showSummary && this.currentModelSummary().length > 0;
  }

  private expandedModelMaxButtonWidth(): number {
    return this.expandedModelLayout(false).maxButtonWidthVp;
  }

  private expandedModelMaxLabelWidth(): number {
    return this.expandedModelLayout(true).maxLabelWidthVp;
  }

  private expandedModelMaxSummaryWidth(): number {
    return this.expandedModelLayout(true).maxSummaryWidthVp;
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

  private isChatSubpage(): boolean {
    if (this.page === 'files' || this.page === 'review' || this.page === 'git' ||
      this.page === 'pull-requests' || this.page === 'terminal' || this.page === 'preview' ||
      this.page === 'device-picker' || this.page === 'voice') {
      return true;
    }
    if (this.page === 'html-viewer') return this.htmlViewerEntry !== undefined;
    if (this.page === 'android-device' || this.page === 'device-preview') return this.deviceChoice !== undefined;
    if (this.page === 'linked-thread') return this.linkedThreadTarget !== undefined;
    return false;
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
        if (this.page === 'share') {
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
            cloudConfigured: this.cloudConfigured, cloudSignedIn: this.cloudSignedIn,
            cloudAccountLabel: this.cloudAccountSummary(), cloudCustomConfig: this.cloudCustomConfig,
            onBack: () => this.page = 'sessions', onEnvironments: () => this.openPanel('server'),
            onCloudAccount: () => this.openCloudPanel(''),
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
            onCopy: (value: string) => { void this.copy(value); },
            onStartAgentTask: (localId: string, projectId: string, prompt: string) => {
              void this.startPrAgentTask(localId, projectId, prompt);
            } })
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
          connectionFor: (localId: string) => this.registry().clients.get(localId),
          onBack: () => this.page = 'settings',
          onSelectGroup: (key: string) => this.overviewGroupKey = key,
          onRename: (group: ProjectGroup, title: string) => this.renameGroup(group, title),
          onPin: (group: ProjectGroup, pinned: boolean) => this.pinGroup(group, pinned),
          onArchive: (group: ProjectGroup, archived: boolean) => this.archiveGroup(group, archived),
          onTrackFolder: async (project: ScopedProject, folderPath: string, name: string): Promise<void> => {
            await this.workspace().trackProjectFolder(project, folderPath, name);
            this.rebuildWorkspace();
          },
          onUntrackFolder: async (project: ScopedProject, folderPath: string): Promise<void> => {
            await this.workspace().untrackProjectFolder(project, folderPath);
            this.rebuildWorkspace();
          },
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
      } else if (this.page === 'chat' || this.isChatSubpage()) {
        Stack() {
          Column() {
            Row({ space: Space.xxs }) {
              IconButton({
                icon: $r('app.media.ui_back'),
                label: this.sideThreadReturnStack.length > 0 ? '返回父会话' : '返回会话列表',
                onTap: () => { void this.leaveChatOrReturnParent(); }
              })
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
          }
          .width('100%')
          .height('100%')
          .visibility(this.page === 'chat' ? Visibility.Visible : Visibility.Hidden)
          .enabled(this.page === 'chat')
          .hitTestBehavior(this.page === 'chat' ? HitTestMode.Default : HitTestMode.Block)
          .accessibilityLevel(this.page === 'chat' ? 'auto' : 'no-hide-descendants')

          if (this.page !== 'chat') {
            Column() {
              if (this.page === 'voice') {
                VoiceInputPanel({ onBack: () => this.page = 'chat', onInsert: (value: string) => this.insertVoice(value) })
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
                  autoConnect: this.previewAutoConnect,
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
              } else if (this.page === 'html-viewer' && this.htmlViewerEntry) {
                Column({ space: 0 }) {
                  TopBar({
                    title: this.htmlViewerEntry.render.title || 'HTML 视图',
                    subtitle: htmlRenderFileName(this.htmlViewerEntry.render.title),
                    showBack: true,
                    closeStyle: true,
                    backLabel: '返回会话',
                    onBack: () => { this.returnToChatWithScrollRestore(); }
                  }) {
                    IconButton({
                      icon: $r('app.media.ui_more'),
                      label: '页面操作',
                      onTap: () => {}
                    })
                      .bindMenu([
                        { value: '重新加载', action: () => { void this.reloadHtmlFullscreen(); } },
                        { value: '保存到文件', action: () => { void this.saveHtmlRender(); } },
                        { value: '分享文件', action: () => { void this.shareHtmlRender(); } }
                      ])
                  }
                  if (this.htmlViewerError) {
                    Column({ space: Space.sm }) {
                      Text(this.htmlViewerError).fontSize(FontSize.callout).fontColor($r('app.color.danger'))
                      AppButton({
                        label: '重新加载',
                        kind: 'secondary',
                        compact: true,
                        onTap: () => { void this.reloadHtmlFullscreen(); }
                      })
                    }
                    .width('100%')
                    .layoutWeight(1)
                    .justifyContent(FlexAlign.Center)
                    .alignItems(HorizontalAlign.Center)
                    .padding(Space.lg)
                  } else if (this.htmlViewerUri) {
                    Column() {
                      ForEach([this.htmlViewerUri + ':' + this.htmlViewerAttempt], (_key: string) => {
                        HtmlRenderWebView({
                          uri: this.htmlViewerUri,
                          title: this.htmlViewerEntry!.render.title,
                          nested: false,
                          isHtmlRender: true,
                          onOpenExternalLink: (url: string) => { void this.openExternalUrl(url); },
                          onLoadError: () => { this.htmlViewerError = '页面加载失败，请重试'; }
                        })
                      }, (key: string) => key)
                    }
                    .width('100%')
                    .layoutWeight(1)
                  } else {
                    Column() {
                      LoadingProgress().width(24).height(24).color($r('app.color.muted'))
                    }
                    .width('100%')
                    .layoutWeight(1)
                    .justifyContent(FlexAlign.Center)
                    .alignItems(HorizontalAlign.Center)
                  }
                }.width('100%').height('100%').backgroundColor($r('app.color.screen')).foregroundColor($r('app.color.ink'))
              } else if (this.page === 'files') {
                FilesPanel({ cacheScope: this.selectedLocalId, connection: client, cwd: this.filesOverrideCwd || this.currentWorkspace(),
                  threadId: this.draftMode ? '' : this.threadId,
                  title: this.draftMode ? '草稿文件' : '文件与源码',
                  initialPath: this.filesInitialPath,
                  initialDir: this.filesInitialDir,
                  initialLine: this.filesInitialLine,
                  directFileOnly: this.filesDirectFileOnly,
                  onBack: () => { this.returnToChatWithScrollRestore(); },
                  onCompose: (value: Object, label: string) => this.addExternalContext(value, label),
                  onCopy: (value: string) => { void this.copy(value); },
                  onStatus: (value: string) => this.status = value,
                  onOpenExternalLink: (url: string) => { void this.openExternalUrl(url); },
                  onOpenLink: (url: string) => { void this.openLink(url); } })
              } else if (this.page === 'review') {
                ReviewPanel({ connection: client, cwd: this.currentWorkspace(), threadId: this.threadId,
                  projectId: this.projectId,
                  worktreePath: this.draftMode ? this.draftWorkspace.worktreePath : client.threadWorktreePath(),
                  project: this.draftMode ? this.draftProject() : client.threadProject(),
                  checkpointScopes: this.draftMode ? [] : client.threadCheckpointScopes(),
                  checkpoints: this.draftMode ? [] : client.threadCheckpoints(),
                  onBack: () => this.page = 'chat',
                  onCompose: (value: Object, label: string) => this.addExternalContext(value, label),
                  onCopy: (value: string) => { void this.copy(value); },
                  onStatus: (value: string) => this.status = value })
              } else if (this.page === 'git') {
                GitPanel({ connection: client, cwd: this.currentWorkspace(), threadId: this.threadId,
                  projectId: this.projectId,
                  worktreePath: this.draftMode ? this.draftWorkspace.worktreePath : client.threadWorktreePath(),
                  project: this.draftMode ? this.draftProject() : client.threadProject(),
                  checkpointScopes: this.draftMode ? [] : client.threadCheckpointScopes(),
                  checkpoints: this.draftMode ? [] : client.threadCheckpoints(),
                  onBack: () => this.page = 'chat',
                  onStatus: (value: string) => this.reportScopedGitStatus(this.selectedLocalId, this.threadId, value) })
              } else if (this.page === 'pull-requests') {
                PullRequestsPanel({ connection: client, projectId: this.projectId,
                  projectLabel: this.projects.find((project: ProjectView) => project.id === this.projectId)?.label || '',
                  onBack: () => this.page = 'chat', onStatus: (value: string) => this.status = value,
                  onCopy: (value: string) => { void this.copy(value); },
                  onStartAgentTask: (localId: string, projectId: string, prompt: string) => {
                    void this.startPrAgentTask(localId, projectId, prompt);
                  } })
              } else if (this.page === 'linked-thread' && this.linkedThreadTarget) {
                LinkedThreadPanel({
                  target: this.linkedThreadTarget,
                  viaClient: this.registry().clients.get(this.linkedThreadTarget.viaLocalId) || client,
                  viaReady: this.environmentReady[this.linkedThreadTarget.viaLocalId] === true ||
                    (this.linkedThreadTarget.viaLocalId === this.selectedLocalId && this.ready),
                  showOpenInMain: false,
                  connecting: this.linkedConnecting,
                  connectNotice: this.linkedConnectNotice,
                  connectError: this.linkedConnectError,
                  onConnect: (target: LinkedThreadTarget) => this.connectLinkedThreadEnvironment(target),
                  onClose: () => { void this.leaveLinkedThreadPage(); },
                  onCopy: (value: string) => { void this.copy(value); },
                  onOpenLink: (url: string) => { void this.openLink(url); },
                  onOpenImage: (source: string) => { void this.openMarkdownImage(source); },
                  onShareMedia: (source: string, alt: string, kind: string, resolvedUrl: string, displayPath: string) => {
                    const tid = !this.draftMode && client.thread ? client.thread.threadId : '';
                    void this.shareInlineMediaFor(client, this.selectedLocalId, tid, this.currentWorkspace(), source, alt, kind, resolvedUrl, displayPath);
                  },
                  onSaveMediaToGallery: (source: string, alt: string, kind: string, resolvedUrl: string, displayPath: string) => {
                    const tid = !this.draftMode && client.thread ? client.thread.threadId : '';
                    void this.saveInlineMediaToGalleryFor(client, tid, this.currentWorkspace(), source, alt, kind, resolvedUrl, displayPath);
                  },
                  onSaveMediaToFile: (source: string, alt: string, kind: string, resolvedUrl: string, displayPath: string) => {
                    const tid = !this.draftMode && client.thread ? client.thread.threadId : '';
                    void this.saveInlineMediaToFileFor(client, tid, this.currentWorkspace(), source, alt, kind, resolvedUrl, displayPath);
                  },
                  downloadLocalMedia: (url: string, kind: string, displayPath: string): Promise<string> =>
                    this.downloadMediaToLocalCache(client, url, kind, displayPath)
                })
              }
            }
            .width('100%')
            .height('100%')
            .backgroundColor($r('app.color.group'))
            .hitTestBehavior(HitTestMode.Default)
          }
        }
        .width('100%')
        .layoutWeight(1)
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
                Row({ space: 0 }) {
                  Text('Less').fontSize(FontSize.title).fontWeight(Weight.bold).fontColor($r('app.color.ink'))
                  Text('Agent').fontSize(FontSize.title).fontWeight(Weight.regular).fontColor($r('app.color.muted'))
                }.alignItems(VerticalAlign.Center)
              }
            }.constraintSize({ minHeight: Sizes.iconHit }).padding({ left: Space.xxs, right: Space.xs })
              .backgroundColor(Color.Transparent)
              .accessibilityText((this.homeShowReconnectingHeader() || this.homeShowOfflineHeader())
                ? (this.homeConnectionLabel() + '，管理环境') : 'LessAgent，管理环境')
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
      if (!this.privacyAccepted) {
        Column() {
          Column({ space: Space.sm }) {
            Text('隐私政策与用户协议')
              .fontSize(FontSize.headline)
              .lineHeight(LineHeight.headline)
              .fontWeight(Weight.semibold)
              .fontColor($r('app.color.ink'))
              .width('100%')
            Text(PRIVACY_POLICY_SUMMARY)
              .fontSize(FontSize.callout)
              .lineHeight(LineHeight.callout)
              .fontColor($r('app.color.muted'))
              .width('100%')
            Button({ type: ButtonType.Normal }) {
              Text(this.privacyDetailExpanded ? '收起完整隐私声明' : '查看完整隐私声明')
                .fontSize(FontSize.callout)
                .lineHeight(LineHeight.callout)
                .fontWeight(Weight.medium)
                .fontColor($r('app.color.primary_text'))
            }
            .backgroundColor(Color.Transparent)
            .padding({ top: 4, bottom: 4 })
            .alignSelf(ItemAlign.Start)
            .onClick(() => { this.privacyDetailExpanded = !this.privacyDetailExpanded; })
            if (this.privacyDetailExpanded) {
              Scroll() {
                Text(PRIVACY_POLICY_DETAIL)
                  .fontSize(FontSize.caption)
                  .lineHeight(LineHeight.caption)
                  .fontColor($r('app.color.ink'))
                  .width('100%')
              }
              .width('100%')
              .constraintSize({ maxHeight: 220 })
              .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
              .padding(Space.sm)
              .backgroundColor($r('app.color.group'))
              .borderRadius(Radius.tool)
            }
            Row({ space: Space.sm }) {
              Column() {
                AppButton({
                  label: '不同意并退出',
                  kind: 'secondary',
                  fill: true,
                  onTap: () => { this.declinePrivacy(); }
                })
              }.layoutWeight(1)
              Column() {
                AppButton({
                  label: '同意并继续',
                  kind: 'primary',
                  fill: true,
                  onTap: () => { this.acceptPrivacy(); }
                })
              }.layoutWeight(1)
            }.width('100%').padding({ top: Space.xs })
          }
          .width('100%')
          .constraintSize({ maxWidth: 420 })
          .padding(Space.lg)
          .backgroundColor($r('app.color.card'))
          .borderRadius(Radius.card)
          .border({ width: Sizes.hairline, color: $r('app.color.border') })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .height('100%')
        .padding(Space.md)
        .backgroundColor($r('app.color.backdrop'))
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .onClick(() => {})
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
        this.panel === 'linked-thread' || this.panel === 'side-thread' || this.panel === 'link-batch' || this.panel === 'mcp-app' ? '88%' :
        this.panel === 'mcp-sign-in' ? '72%' :
        this.panel === 'cloud' || this.panel === 'snooze' ? '85%' : '70%',
        showClose: false,
        onWillDismiss: (action: DismissSheetAction) => { if (this.panel !== 'peer-link' || !this.busy) action.dismiss(); },
        backgroundColor: $r('app.color.group') })
  }
}
