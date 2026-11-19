# R0 移动能力迁移矩阵

> 本文保留 R0 初始差距。R6–R8 当前实现、证据和剩余范围见 [收口清单](r6-r8-acceptance.md)，不能将初始“缺失”直接当作当前状态。

基线：DASungta/t3code `ad1b1365999c92c3fc7a054e7f3af84623f74fee`。2026-11-16。

本表是实施索引；89 个注册路由逐个展开在 [路由台账](r0-route-ledger.md)，精确动作、条件、调用和设置行在 [证据目录](evidence/r0/README.md)。源码路径均相对归档根目录；`features/` 指 `apps/mobile/src/features/`，`contracts/` 指 `packages/contracts/src/`，`runtime/` 指 `packages/client-runtime/src/`。每条证据有 file/line/source，可按固定 SHA 在归档内复核，不能随 main 漂移。

状态：下表未迁移项目均为**待实施**；已有部分实现记为**已实现未验收（完整原版范围）**，不抹去阶段一至三的局部真实验收。云及原生关键依赖详见阻塞清单。S=源码，O=离线检查，R=真实原版，H=历史鸿蒙证据。本轮没有 R 画面。每行验收编号就是首列 ID；正常、拒绝权限/缺能力、离线/重连、重复操作及取消返回均要执行，服务写入必须回读。

R2 更新（2026-11-17）：C06–C10 的客户端实现已落地并有本地契约测试/签名构建，但因公开云配置、合法鸿蒙 OAuth client、真实账号/中继和设备 DPoP 执行缺失，统一保持**已实现未验收**。详见 [R2 进展](r2-progress.md)。

R3 更新（2026-11-17）：P01–P06 的客户端实现已落地，173 项宿主测试和最终签名构建通过；专用 Mate60Pro 与隔离 T3 0.1.9 服务已完成一轮列表、项目来源/概览、归档、会话状态与撤销的真实写回读。原版逐页视觉、拖拽排序、运行中归档限制、严格权限矩阵和 provider 真实副作用仍未验收。详见 [R3 进展](r3-progress.md) 和 [R3 证据](evidence/r3/README.md)。

R4 第三批更新（2026-11-17）：在第二批设备/隔离服务基础上补齐队列 edit/reorder/promote/cancel/start/resume/steer 真实回读、force stop/resume、secret 直接/文件/拒绝、12 MiB 多附件与 exact-byte 下载，并修复首次提交 marker、草稿清理、继承 secret、50 MiB 上限和部分设置同步；208/208 测试和签名构建通过。原版 Pixel 6 已补发送菜单、队列胶囊/sheet、审批和 secret 视觉。第三批 HAP 已覆盖安装，但设备安全锁屏导致启动/UI 未验收。M04 结构化 user input、secret reference provider、Guest 隧道、用量恢复、history paging 和原版最大字体/深色/读屏仍未验收，不能标 R4 完成。逐项见 [R4 进展](r4-progress.md)，下表原 R0 基线保留。

R5 更新（2026-11-18）：M02/F01/F02/G01–G05 的客户端主路径已实现，219/219 宿主测试、签名构建和专用 Mate60Pro 隔离服务回读通过。文件树/源码/图片/4 MB 大文件、原生 Markdown（表格/代码着色/折叠/Unicode 数学）、Diff 选行与 review-comment 上下文、Git 提交/推送/拉取/分支、PR 列表/详情/审阅入口均已真机操作；真实 PR provider/账号写入仍因测试环境无 provider 阻塞，Mermaid/KaTeX、最大字体/读屏/逐像素和超大 Diff 未验收。逐项见 [R5 进展](r5-progress.md)。

## 连接、云与环境

| ID/批次 | 原版入口与动作；源码 | 条件与契约 | ArkUI 对应及当前差距 | 验收结果要求 |
|---|---|---|---|---|
| C01/R1 | Home 标题→Connections；connection/ConnectionsRouteScreen.tsx、LocalEnvironmentList.tsx：展开、重试、启停、编辑、移除 | runtime/connection；环境身份、启用状态、连接状态独立 | 真机 A/B/C 独立启停/移除、A/B 同 ID 草稿/附件/恢复隔离、已知地址重配对、路径添加/排序/移除/重启恢复通过；C 环境改名保持凭据与恢复引用，带未知标记的 A/B 改名被阻止并显示安全提示；B01 原版视觉/交互已在 Android 模拟器取证（空态/添加/失败/相机拒绝/真实配对成功/深色/Manage），原版二维码识别与底部导航、扫描文案差异另记 | 两环境独立启停/切换/删除，失败不污染另一环境 |
| C02/R1 | ConnectionsNew/SettingsEnvironmentNew；ConnectionsNewRouteScreen.tsx：扫码、重新扫描、系统设置、地址/Code、顶栏确认 | camera 授权/焦点；connecting/host 空禁用；成功返回 opener | 权限拒绝/设置恢复、后台释放/前台重开、冷/热深链、恶意 URL 拒绝、物理对准、确认前码未消费、一次确认后消费及连接 B 均真机通过；重扫细分场景保留后续视觉回归 | 拒绝/永久拒绝、连续扫描只填一次，确认前不连接，取消不新增 |
| C03/R1 | connection/pairing.ts：IP/域名、token hash/query、托管链接、t3code 包装 | shared/remote；IP 默认 http，域名默认 https；扫码解析和传输校验分离 | LAN HTTP 与有效公开证书 HTTPS 均完成真机配对；302/307、自签名证书、协议错、明文公网拒绝均在鉴权前失败；Tailnet 与 IPv6 实网组合仍无可用地址证据 | IPv4/IPv6/tailnet、无 Code、坏 URL、跨源重定向，凭据不外泄 |
| C04/R1 | connection/platform.ts、storage.ts、environment-owned-data-cleanup.ts | connectivity、network path、前后台 wakeup；runtime/authorization/remote.ts、rpc/session.ts | 真实 v1→v2 升级、锁屏 Asset 拒绝/解锁恢复、未知提交保留、凭据过期重配、写后读回、路径增删/排序/删除、进程重启恢复均真机通过 | 过期/身份错/协议错、切网、前后台，不自动重发修改 |
| C05/R1 | Connections LinkedEnvironmentsSection、PullRequestRoutingSettings；thread LinkRequestCard；撤销归属 Settings Sharing & access/Authorized clients | peerLinks 能力、linkedEnvironmentsEnabled、当前连接 access:read 查询/access:write 回答；PR 共享双方授权 | 真机批准只读 B、拒绝、目标端 session 撤销和源端 unlink 均回读；PR 三档设置双方授权/路线变更清信任通过。上游移动页只展示 linked environments，撤销使用原版 Authorized clients HTTP 契约，不自创移动入口 | 连接请求批准/拒绝/撤销、选 PR 目标，无权隐藏/禁用 |
| C06/R2 | 添加页 T3 Connect 段；cloud/publicConfig.ts、CloudAuthProvider.tsx、settings/SettingsAuthRouteScreen.tsx | 三项 Clerk key/JWT template/relay URL 齐全才显示；账号 ready/签入 | **已实现未验收**：公开配置门控、系统浏览器 OAuth/PKCE、精确回调校验与账号会话；真实 Clerk 配置/鸿蒙 OAuth client 未验收 | 登录取消、失败、回调伪造/重复、冷启动、账号恢复与注销 |
| C07/R2 | cloud/T3ConnectProfilePage.tsx、cloudAccountService.ts、cloud-drafts.ts | Clerk 会话→relay session；切账号先清理缓存/环境/通知注册 | **已实现未验收**：原生账号面板、会话恢复/注销/切号清理、云环境与令牌隔离；云草稿持久化留 R4 | A→B 不出现 A 环境/草稿/密钥引用，清理失败不能激活 B |
| C08/R2 | CloudEnvironmentRows、cloud/linkEnvironment.ts、ConnectOnboardingRouteScreen.tsx | runtime/relay/discovery.ts；relay.ts list/link/challenge/unlink/device revoke | **已实现未验收**：发现/状态/连接、link challenge/link/unlink、设备批准/拒绝/撤销和本机链接 UI；真实 relay/host 未验证 | 发现/链接/拒绝/设备撤销/离线/重名，不因默认云关闭而删除范围 |
| C09/R2 | cloud/dpop.ts、runtime/relay/dpopProof.ts、managedRelay.ts | P-256 ES256 r‖s、htu/htm/jti/iat/ath、thumbprint；密钥绑定令牌/缓存 | **已实现未验收**：CryptoFramework ECC256+Asset DPoP、DER→64 字节、ath/htu/thumbprint；HUKS/专用机/relay 未验证 | 64 字节格式、错误 key/ath/时间、令牌失效重取、撤销不可继续 |
| C10/R2 | cloud/managedRelayLayer.ts、managedRelayTokenStore.ts、runtime/connection/resolver.ts | 状态/连接 DPoP 接口、中继 endpoint/ticket、账号与 scopes 缓存键 | **已实现未验收**：relay/environment DPoP transport、token/ticket/续期/撤销适配；真实跨网络中继未验证 | 跨网络经中继发送/审批/续期/撤销；直连与中继并存不任意降级 |
| C11/排除 | connection/platform.ts | SSH 明确 unsupported，桌面限定 | 不增加移动 SSH 入口 | 确认 unsupported 提示，不把它当待迁移功能 |

## 列表、项目、草稿和会话

| ID/批次 | 原版入口与动作；源码 | 条件/契约 | ArkUI 对应及差距 | 验收结果要求 |
|---|---|---|---|---|
| P01/R3 | home/HomeScreen.tsx、layout/workspace：列表/搜索/过滤、项目分组、Working/待办/归档、排序 | threadSearch.ts、shell state、跨环境 scoped refs | **已实现，部分真机验收**：固定/活跃/暂缓/Settled 分区、搜索命中、项目过滤标签、仓库/路径分组偏好和主要导航已真机回读；原版视觉/底部工具栏、空/离线/加载全组合未闭合 | 多环境同 ID、搜索定位、空/离线/加载状态与原版一致 |
| P02/R3 | home/useThreadListActions.ts、thread-swipe-actions.tsx：归档/还原、settle/unsettle、删除、撤销 | threadCanArchive、threadSettlement、operate 权限；orchestrationV2 | **已实现，部分真机验收**：长按/更多、左滑动作、Settle/撤销、归档/恢复、删除确认与失败不自动重试已落地；运行中归档限制、撤销失败组合与草稿清理未验收，拖拽未实现 | 运行中限制、撤销失败、删除确认回读，草稿清理正确 |
| P03/R3 | 同上：固定/取消、拖序、活跃排序、暂缓/取消/自定日期、重命名/重生成 | threadPinning/PinReorder/ActiveReorder/Snooze/TitleRegeneration | **已实现，部分真机验收**：固定/取消、菜单上移 orderKey、暂缓预设、重命名、自动 Settle 暂停/恢复已回读；下移边界、自定义时间 UI、重生成实际 provider、拖拽手势未验收 | 无能力不显示、顺序持久、时区正确、重名/空名处理 |
| P04/R3 | projects/AddProjectSourceRoute.tsx→Repository/Destination/Local/New | project.ts/projectClone.ts/filesystem.ts/sourceControl.ts；ready environment/仓库账号 | **已实现，部分真机验收**：新项目、本地目录、Git URL 克隆成功/失败/重试/取消、目标页与项目选择衔接已回读；provider lookup/登录、私有发布、真实远端认证未验收 | 本地/克隆/新建、目录校验/冲突/取消/进度失败重试 |
| P05/R3 | projects 与 settings/SettingsProjectOverviewRouteScreen.tsx | project.update/归档/固定、身份分组、项目 overrides 能力 | **已实现，部分真机验收**：名称更新、固定/取消、归档/恢复、删除确认/取消/确认和 checkout 列表已回读；同仓库多 checkout、项目 overrides/managed 继承未验收 | 同仓库多环境显示、覆盖与继承、权限回读 |
| P06/R3 | threads/NewTaskRouteScreen.tsx：项目搜索、No project、恢复被移除项目草稿 | scratch 能力/ready env；projectEnvironment.openScratch；保留 draftId/share reservation | **已实现，部分真机验收**：项目搜索/选择、No project、添加项目、返回和选择后显示正确项目已验证；完整 Thread draft、被移除项目草稿恢复和首次发送状态机属 R4 | 返回不创建会话/不改草稿；选择后保留上下文，无项目任务真实启动 |
| D01/R4 | NewTaskDraftRouteScreen/NewTaskDraftScreen/new-task-flow-provider | new-task-flow-state/use-composer-drafts；environment/project/draftId | 同 Thread 里的草稿编辑态；未实现完整持久草稿 | 首次发送才按原状态机创建/启动；失败保留、双击不重复 |
| D02/R4 | NewTaskEnvironment/NewTaskBranch/checkout-new-task-branch/use-worktree-setup | 环境/分支/worktree/bootstrap、分支占用与清理能力 | 原 picker 页/启动状态卡；缺失 | 远端/本地起点、已有 worktree、冲突/失败不误发 |
| D03/R4 | ThreadSettingsSheet/ThreadSettingsRows/thread-settings-options | modelSelection/providerInstance/providerPolicy；provider 安装/认证/managed policy | 模型 sheet、搜索、provider 账号、模型选项/权限/运行模式；现仅创建前模型 | 新草稿与已有会话分别生效，禁用模型、账号失效、选项边界 |
| D04/R4 | ThreadComposer/use-composer-command-menu/ComposerCommandPopover | composerContext、serverResolvedCommandContext；slash/skill、@ 文件/命令上下文、clipboard | 原输入工具栏+弹出选项/上下文 chips；缺失 | 查询/选择/移除、目录/终端/代码上下文正确，取消不残留 |
| D05/R4 | ThreadQueueControl/ComposerQueuedEdit/ThreadQueueSheet | queued messages、queue/steer、编辑/删除/恢复；orchestrationV2 | 原队列 badge+sheet；缺失 | 运行时发送、调序/编辑取消、重启恢复，未知结果不重发 |
| D06/R4 | ThreadHeader/ThreadDetailScreen/ThreadGuestShareBar | thread.stop/forceStop capability、resume-thread、fork、guestShare/access scopes | 原更多菜单/运行控制/共享；目前基本 stop | 普通停止/强停差别、恢复/分叉/访客分享/撤销实际回读 |
| D07/R4 | ThreadAgentsSheet/ThreadBackgroundWorkSheet/ThreadSideChatsRow/ChildThreadApprovals | lineage/sideChats/provider subagent/background、runtime 关联 | agents/background sheet、子会话跳转；缺失 | 关联定位/子任务停止及审批、返回原线程、无权限路径 |
| D08/R4 | ProposedPlanCard/UsageLimitRecoveryCard/ManagedRuntimeModeNotice/FreshSessionNotice | projected item、计划确认、用量恢复/取消 auto-resume、provider runtime | 原状态卡和操作；缺失 | 同状态显示同可执行动作、确认只发一次、过期不能操作 |

## 消息、输入及附件

| ID/批次 | 入口/源码 | 条件/契约 | ArkUI 对应及差距 | 验收结果要求 |
|---|---|---|---|---|
| M01/R4 | ThreadFeed/thread-work-log/thread-command-output | orchestrationV2 快照/增量/historyCursor；message/tool/turn item | List+局部更新；已有部分，缺完整消息类型与分页 | 中断/最终/错误去重、历史分页不跳位，长历史真机性能 |
| M02/R5 | ThreadMarkdownImage/Video、lib/markdown*、components 原生 Markdown | 链接/引用/表格/折叠/数学/代码高亮/媒体/宽内容 | 原生富文本/代码/横滚/选取与跳转；现基础按行解析 | 原文复制/代码语言、恶意链接、大表格、读屏/字体 |
| M03/R4 | PendingApprovalCard、ChildThreadApprovals | runtime-request.respond、请求可恢复性/权限 | 原审批卡；已有局部真实验收 H | 允许/拒绝/批量或子任务适用入口、重复/已过期/离线 |
| M04/R4 | PendingUserInputCard/QuestionAttachments/QuestionAnswerHistory | 单/多选、多问题、自定义、required、附件、历史/不可恢复 | 原问题布局+焦点；已有基础，变体未全验收 | 完整多问题回读、自由输入与选项互斥、取消/校验 |
| M05/R4 | SecretRequestCard、runtime/secret-request | secrets.answerRequest；secretProviders、reference/source/link/display pending elsewhere | 安全字段/来源 picker/外部授权；现仅直接值 | 来源引用与直接值、不可恢复/另端 pending、拒绝/失败，正文/日志无秘密 |
| A01/R4 | ComposerAttachmentButton、state/use-composer-attachment-actions、lib/composerAttachmentUploadQueue | assets/chatAttachment；图片/视频/file、多附件；服务能力及大小 | 相机/相册/文档 picker+队列/移除/重试；现单 file≤10MiB | 逐项失败/取消/重试、精确字节、不自动发送；支持上游限额 |
| A02/R4 | AttachmentFileScreen/ZoomableImagePressable/messageImageGallery/fileChipMenu | attachment ID/签名 URL、图片/视频/PDF/文件；save/share | 原生图库/媒体/PDF 路线及分享；现仅历史名称 | 授权/过期/下载/保存/复制/分享、无权读取、清理临时文件 |
| A03/R7 | sharing/IncomingShareProvider、threads/incomingShareImport | share extension、MIME/保留目标 draft、冷启动导入 | 鸿蒙分享目标+暂存 draft；缺失 | 文本/URL/多文件、取消和重复导入、缺项目重新选择 |

## 文件、Git、PR 与远程操作

| ID/批次 | 入口/源码 | 条件/契约 | ArkUI 对应及差距 | 验收结果要求 |
|---|---|---|---|---|
| F01/R5 | ThreadFilesTreeScreen/ThreadFileScreen、草稿对应路由 | filesystem.ts、路径/环境/工作区权限 | 文件树/搜索/原生源码选取/分享；缺失 | 目录/二进制/大文件/删除路径/无权限、返回保留位置 |
| F02/R5 | ReviewSheet/ReviewCommentComposerSheet/review-section-menu | checkpointDiff/review；diff 范围、行选择、评论上下文 | 原生 Diff/行号/折叠/评论 sheet；缺失 | 增删/重命名/长行、选择精确行、加入上下文/发送前检查 |
| G01/R5 | ThreadGitControls/GitOverview/GitCommit/GitBranches/GitConfirm | git/vcs；sourceControl scopes、worktree occupancy | 原 Git sheet/确认/进度；缺失 | stage/unstage/commit/push/pull/checkout、冲突/失败/取消，不误改其他目录 |
| G02/R5 | ThreadPullRequests/LinkedPullRequestList/useLinkedPullRequestActions | threadPullRequests/Linking/Watch、pullRequestStackActions | PR 链接/解除/栈/监控行；缺失 | 同仓库跨环境路由、链接/栈顺序及 watch 状态回读 |
| G03/R5 | pull-requests 列表/筛选、PullRequestRoute/File/Files/Discussion | pullRequest.ts/sourceControl；仓库账号、checks 能力 | 原 PR 列表/详情/文件/讨论；缺失 | 搜索/过滤/分页、checks/冲突、差异文件及讨论定位 |
| G04/R5 | PullRequestReview/InlineComment/Reactions/Reviewers/Labels/Edit | draft review、submit/comment/approve/request changes、编辑权限 | 原 sheet/行评论/选择器；缺失 | 草稿/提交/失败保留、回复/reaction、reviewer/label/标题正文回读 |
| G05/R5 | pullRequestActions/PullRequestGuideStop/usePullRequestAgentActions | merge method、close/reopen、review guide/Agent 任务、stack actions | 原确认与导览/Agent 入口；缺失 | squash/merge/rebase/ff 按仓库能力、无权禁用、Agent 使用独立测试任务 |
| T01/R6 | ThreadTerminalRouteScreen/NativeTerminalSurface/TerminalContextSheet | terminal.ts：open/attach/observe/write/resize/clear/close/events；read/write 权限分离 | NAPI+Ghostty VT+XComponent 候选；未实现 | 真双向 ANSI/UTF-8/宽字符/IME/快捷键/resize、断线序列与缓冲恢复 |
| T02/R6 | terminalMenu/ThreadTerminalRouteScreen | 多 session、项目脚本、字体、复制/粘贴/控制修饰键、终端上下文 | 原 session 菜单/快捷键条；缺失 | 新建/切换/退出回退、粘贴确认、选行加入上下文 |
| V01/R6 | BrowserPreviewRouteScreen/BrowserTabMenu/preview-stream.browser | preview.ts/previewCapture；tabs/权限、帧/输入/音频/PiP | 原生视频/画面+输入；未实现，WebView 不可作客户端 UI 替代 | tabs/后退前进/reload、触摸/键盘/剪贴板、缩放/viewport/主题/清 cookies/cache、PiP 能力 |
| V02/R6 | DevicePreviewRouteScreen/device-stream.browser | device.ts；host/tool versions、H.264 支持否则 MJPEG、设备状态 | 解码+Surface+坐标映射；未实现 | 设备选择、重试/重载、back/app switcher/rotate/shutdown 依原权限，输入与画面一致 |
| V03/R4 | McpAppFullscreenScreen/McpAppWebView、HtmlRenderWebView | mcpApps/工具内容、安全 origin/桥接、HTML 内容 | 客户端壳保持 ArkUI；交互网页内容承载边界须专项设计，未定不删功能 | MCP app 通信/resize/权限/断线与不可信内容隔离；不把网页内容变客户端导航 |

## 系统集成及全部设置范围

| ID/批次 | 原入口/源码 | 条件/契约与范围 | ArkUI 对应及差距 | 验收结果要求 |
|---|---|---|---|---|
| S01/R7 | voice-input、settings/SettingsVoiceRouteScreen/Models/CloudVoiceSection | 麦克风/路由、端侧/远端转写、cloudVoiceTranscription、模型下载/删除 | 原语音控制/输入设备/模型页；缺失 | 拒绝、蓝牙/有线/内置、录音中断/取消、远端音频确认、下载失败 |
| S02/R7 | agent-awareness、SettingsNotificationsRouteScreen | OS permission、云账号、APNs/Android 原生注册、Live Activity/设备偏好 | 鸿蒙通知/点击 Want/推送适配；缺失，服务端需支持 | 前台/后台/冷启动定位 env/thread、拒绝/撤销/账号切换、内容隐私 |
| S03/R7 | shortcuts、widgets/*、t3-widget-expiry | 快捷操作、Agent Activity/Subscription Usage、iOS/Android 分支及 Personal Team 限制 | 系统快捷入口/服务卡片等价设计；缺失 | 点击定位/冷启动/无环境、过期清理/账号注销后不留内容 |
| S04/R7 | keyboard/HardwareKeyboardCommandProvider、SettingsKeyboardRouteScreen | 快捷键注册/用户绑定、系统/平台差异 | 原命令 overlay+焦点；缺失 | 外接键盘组合键、IME/冲突、可见命令与焦点返回 |
| S05/R7 | SettingsRouteScreen/settings-search/settings-page-targets | 配置云账号/无环境 serverPage disabled、导航定制 availability | 原设置分组+搜索/环境筛选；当前无完整设置页 | 每条注册设置路由与旧 alias 可达，搜索隐藏条件一致 |
| S06/R7 | SettingsEnvironments/Detail、diagnostics | 连接信息/诊断/更新/维护能力、read/write scopes | 原环境列表/详情；当前单连接表单 | 目标环境正确、只读诊断、危险操作单独确认和回读 |
| S07/R7 | SettingsServerControlsRouteScreen：Threads | default workspace/permissions、response streaming、preview browser access、restart continuation | server settings+managed policy+project overrides；缺失 | current/worktree、权限继承、流式策略、组织锁定及项目覆盖回读 |
| S08/R7 | SettingsServerControlsRouteScreen：Source control | 项目源、merge agent credits、auto pull、clone host folders | sourceControl accounts/settings scopes；缺失 | OAuth/凭据型源、撤销、克隆目录与默认分支行为 |
| S09/R7 | SettingsServerControlsRouteScreen：Worktrees | remote 起点、submodules、目录/清理/分支命名、项目覆盖 | capabilities/worktreeSetup/settings；缺失 | recursive/top-level/none、占用、清理对象和继承正确 |
| S10/R7 | SettingsServerControlsRouteScreen：Maintenance、environment-maintenance | database storage/cleanup、provider update check、continue restart、keep awake、server update | 原维护段；缺失 | 能力与安装方式决定动作；仅独立环境测试，不重启真实服务 |
| S11/R7 | SettingsProviderAccountsRouteScreen、claude-accounts、SourceControlSignInSection | provider auth start/respond/complete/cancel/logout/remove、安装进度、账号/profile | 原 provider 行/认证挑战/密码字段；缺失 | 交互/浏览器/credentials 登录、失败/取消/换号、脱敏与卸载权限 |
| S12/R7 | ThreadSettingsSections（Threads） | resume usage limit、snooze until reset、auto settle merged/inactive/days/scope、working section、last project | server/local 作用域分开；缺失 | 跨环境默认应用、每线程 opt-out、旧 server 缺能力不静默写入 |
| S13/R7 | ThreadSettingsSections（Labs） | linkedEnvironmentsEnabled/peerLinks、fastWorktreeCheckout/能力与 policy | 原 Beta 开关；缺失 | 缺能力/组织托管禁用，切环境不串设置 |
| S14/R7 | SettingsScheduledTasksRouteScreen/ScheduledTaskPickerScreens | scheduledTask：new/edit/model/branch/destination、启停/删除/run now/webhook | 原任务列表+编辑/选择页；缺失 | 时区/调度/目标、prompt/model、运行与删除回读、token 轮换不泄漏 |
| S15/R7 | SettingsFollowUpRouteScreen | 运行中 Queue/Steer，设备本地偏好 | 原 radio rows；缺失 | 设置影响后续发送语义，不修改已有队列事实 |
| S16/R7 | SettingsAppearanceRouteScreen/appearance/sections/* | theme/light/dark/system、text/code font/size、tool calls、terminal、Android navigation | 原预览/滑条/分组；当前仅主题/部分缩放 | 最大字体/深浅色/代码/终端一致，非支持平台设置按条件 |
| S17/R7 | SettingsLanguage/ProjectGrouping/Navigation | system locale/全部 locales、project grouping、tab 排序/启停/可用平台 | 原设置 picker/拖序；缺失 | 重启保存、语言回退、导航仍可回设置，平板折叠布局 |
| S18/R7 | UsageRouteScreen/UsageLimitsPooled/SettingsUsageAccount | pooled accounts、usage source/price overrides/model aliases 能力、筛选快照 params | 原用量图/筛选/账号详情；缺失 | 多账号汇总、reset 时间、无用量/错误、实时池不沿用过期路由参数 |
| S19/R7 | SettingsClientStorageRouteScreen、persistence/mobile-storage | 缓存大小/按环境清理、不可清凭据/未知提交事实 | 原存储明细/确认；缺失 | 清理回读、离线恢复、数据隔离与失败处理 |
| S20/R7 | diagnostics/SettingsDiagnosticsRouteScreen、observability | 诊断数据、tracing config gating、导出脱敏 | 原诊断页+系统分享；缺失 | 只含允许字段，无 token/秘密/正文泄漏，失败反馈 |
| S21/R7 | SettingsAbout/Legal/OpenSourceLicenses/License、updates | 版本/更新/法律/许可证、entryKey 深链、网络与构建条件 | 原 about/list/detail 原生页；缺失 | 有效/失效许可 ID、离线可用、更新不混淆服务端与客户端 |
| S22/R7 | prompt-links、triage、archive、home/usePendingTaskListActions | prompt/repo/pr/provider/model 链接预填、待办批处理/撤销、归档恢复 | 原列表/草稿预填，缺失 | 外部输入校验，返回无提交，批处理部分失败/权限变化 |
| S23/R8 | layout/adaptive/workspace、native 布局投影、development、showcase | 手机/平板/折叠、开发 ComponentCatalog/Showcase、render error fallback | 原导航层级/分栏/错误返回；当前单屏 | 崩溃可返回/设置、旋转/折叠焦点不丢；开发样例不计真实能力 |

## 防漏核对与限制

1. **注册面**：逐个提取 Stack.tsx 的 89 个 createNativeStackScreen（含没有 linking 的弹层、开发条件入口、NotFound、SettingsVoice alias、旧 NewThreads/AgentBehavior 与 Organization 路径），自检数量/唯一性/源文件存在。Home 内嵌 tabs 不会出现在 Stack，另核 layout/workspace 和导航设置。
2. **动作面**：全扫描 mobile src（含 components/lib/state/native/persistence/widgets），以及 shared/runtime/contracts 的动作声明和处理、平台分支、动态菜单/回调。保留 6,929 条动作候选行，和 1,948 条条件、946 条调用行交叉使用；它们含内部 ID/类型与非 mobile 共享代码，**不是 6,929 项已人工验收能力**。真实可达性仍须原版运行逐入口核验，不能以正则或目录数量宣称无遗漏。
3. **设置面**：不是仅记录路由名。506 条 settings 字段/读写候选行涵盖本地偏好、环境/项目覆盖与 managed policy；还需结合 appearance 子 sections、contracts/settings.ts、settingsSecretValue.ts/secretReference.ts，按字段回读。动态 provider/auth/model 选项取决于服务 config，静态枚举不能封顶。
4. **原生面**：10 个本地模块逐个列出；940 条 imports/原生桥接候选同时覆盖 Expo/RN/Clerk 外部依赖。自定义模块清单不代表全部系统能力。
5. **条件面**：environment.ts 的 capabilities、auth scope/RPC permissions、云公开配置、账号、实验开关、provider 发现、平台/构建变体分别保留；默认 false/不支持也要保留目标能力。SSH 是有源码依据的明确排除。
6. **未闭合项**：R 原版实机入口/画面、动态菜单全部展开、合法云账号/授权设备/中继、鸿蒙签名/终端/解码/推送真机。R0 静态产物已落地，R0 的完整验收门槛尚未满足；此时不能宣称整个 R0 已验收或直接启动 R1 全量改造。
