# 上游同步至 `620cf4770d` — P0-2 RPC 响应前向兼容审计

- 上游参考提交：`e452042db8`（`fix(contracts): older clients drop unknown values in RPC responses (#40490)`，`packages/contracts/src/baseSchemas.ts` 中的 `ForwardCompatibleArray`）
- 审计基线：HarmonyOS 客户端 `entry/src/main/ets/protocol/` 全目录（共 39 个文件）
- 核心原则：
  1. 服务端 RPC 响应和流推送中的数组元素若遇到未知 `type`/`kind`、新字段或单条校验失败，仅丢弃该元素，不让整个响应失败，也不清空整个列表。
  2. 额外的新增对象属性（如项目 `repositories`、`trackedFolders`、checkpoint scope `kind: 'manual'` 与 `repositoryPath`、设置项 `sideThreadOpenTarget`、服务端 `featureFlags`、secret 的 `fields` 等）应被安全忽略或按已知能力解析。
  3. **严格边界绝不放宽**：配对、鉴权、DPoP、Cloud 令牌、本地环境目录与凭据资产校验、路径穿越防护、写操作前置校验和媒体帧边界继续保持 fail-closed。

## 全目录审计结论（按文件）

| 文件 | 结论 | 审计与改动说明 |
|---|---|---|
| `Wire.ts` | **已修复** | 新增 `compactObjects` 与 `compactArray` 通用前向兼容工具。`ThreadState.apply` 的快照数组（`runs`、`messages`、`plans`、`subagents`、`providerTurns`、`providerThreads`、`providerSessions`、`nodes`、`visibleTurnItems`、`runtimeRequests`、`checkpoints`、`turnItems`）、`thread.pull-request-link-updated` 和 `prependHistory` 改为逐项容错丢弃非法元素；`turn-item.updated` 忽略缺少合法 `id` 的未知项。`serverBase`、`bootstrapForm`、`validateDescriptor`、`RpcClient` 帧解析及 `threadId`/负序列号校验**有意保持严格**。 |
| `Core.ts` | **已修复** | `models()`、`ShellState.apply` 快照（`projects`/`threads`/`archivedThreads` 与 `resolvedRepositoryIdentityRoots`）、`cachedShellEntry` 列表及 `cards()`（含 `secretFields`、`questions`、`options`、审批选项）改为逐项容错，非法条目单条丢弃。`peerAccessGranted`、`peerLinkViews`、`linkRequests`、`linkAnswerPayload`、`uploadTarget`、`recoveryState`、单事件 `project.updated` 及 secret 回答校验**有意保持严格**。 |
| `Projects.ts` | **已修复** | `snoozeSettingsFrom()` 遇到未知预设 `kind` 或非法项时仅丢弃该项，全部无效时才回退默认值；`projectView()` 将未知 `defaultThreadEnvMode` 归一化为 `undefined`，容忍非法 `repositoryIdentity` 与新增字段（如 `repositories`/`trackedFolders`）；`threadView()` 对 `pendingBackgroundTasks` 与 `goal` 逐项容错；`buildArchiveGroups()` 对归档快照项目/会话逐项容错。`sessionAllows()` 权限校验**有意保持严格**。 |
| `ThreadItems.ts` | **已修复** | `activityLines()` 改为容错遍历，忽略缺失 `type`/`id` 的条目，并对 `file_search.results`、`web_search.patterns`/`results`、`todo_list.steps`、`checkpoint.files` 与可空 `error.failure` 逐项容错；未知 `type` 继续走通用回退展示；`deriveCheckpointBadges()`、`isHiddenWorkItem()`、`groupWorkByMessage()` 等改用安全字段读取与 `compactObjects`，完整兼容 `kind: 'manual'` 与 `repositoryPath` 等新字段。 |
| `ScheduledTasks.ts` | **已修复** | `scheduleSnapshot()` 对应上游 `ForwardCompatibleArray(ScheduledTask)`，对 `root.tasks` 逐项解析并丢弃非法/重复条目，不再因单条新格式任务使整个列表失败；`verifyScheduleDestination()` 对项目和会话数组改用 `compactObjects`。写操作前置检查与回读校验**有意保持严格**。 |
| `Usage.ts` | **已修复** | 对应上游 `providerUsageLimits.ts` 的 4 处 `ForwardCompatibleArray`，对 `usageAccounts()`、`parseResetCredits()`、`parseLimitWindows()` 与 `collectPooledLimitAccounts()` 中的 `providers`、`usageLimitSources`、`accounts`、`windows` 和 `resetCredits.options` 逐项容错丢弃非法元素；`parseUsageSummary()` 对 `sources` 逐项容错，保留 `contractVersion` 区间检查与 `buckets` 指标合法性校验（防止负数/NaN 污染汇总），未知 `provider`/`status` 枚举安全透传或静默处理。 |
| `R4.ts` | **已修复** | 服务端响应解析 `branches()`、`proposedPlans()`、`subagents()`、`backgroundTasks()`、`guestShare()`（含消息及附件列表）改用 `compactArray` 逐项丢弃非法元素，`latestExecutedRun()` 安全读取 `status`。草稿、上传目标和上下文写校验（`composerDraft`、`attachmentRecord`、`uploadAttachmentTarget`、`contextRecord`、`contextPayload` 等）**有意保持严格**。 |
| `R5.ts` | **已修复** | 对应上游 `pullRequest.ts` 的 `ForwardCompatibleArray`，对 `reviewPreview()`、`mergeVcs()`、`refs()`、`pullRequestRows()`、`pullRequestChecks()`、`pullRequestGuide()`、`pullRequestDetail()`、`pullRequestActivity()`、`linkedPullRequests()` 中的全部响应数组改用 `compactArray`/`compactObjects` 并处理 `undefined`/`null` 可选字段；`textList()` 改为过滤非字符串项。写操作入参（`gitActionInput`、`pullRequestListInput`、`pullRequestRef`、`reviewSubmitInput` 等）**有意保持严格**。 |
| `Composer.ts` | **已修复** | `optionControls()` 遇到未知模型选项 `type`（如未来新增 `number`/`text`）或非法选项条目时单条丢弃，不再抛错阻断任务发送；`modelOptionsSummary()`、`supportedModes()`、`interactionModes()`、`validateTaskSettings()` 和 `queuedRuns()` 中的数组遍历改用 `compactObjects`/`compactArray`。写路径策略校验（`validateTaskSettings`、`launchTask`、`queueCommand`）**有意保持严格**。 |
| `ProviderSettings.ts` | **已修复** | `providerCatalog()` 对 `provider.models` 改用 `compactArray` 丢弃单条非法模型，未知 `driver`/`status`/`authStatus` 枚举已通过 `safeText` 安全降级；环境身份一致性、Provider 重复/非法 `instanceId`、以及 `providerAuthView()`/`providerSignInUrl()` 鉴权流校验**有意保持严格**。 |
| `DraftDefaults.ts` | **已修复** | `normalizeModelOptions()`、`isUsageWindowExhausted()`、`usableModelSelection()`、`catalogFallbackModelSelection()` 和 `resolveDefaultModelSelection()` 中读取 `providers`/`models`/`optionDescriptors`/`options`/`usageLimits.windows` 改用 `compactObjects`，容忍单条非法元素及未知配置键（如 `sideThreadOpenTarget`、`featureFlags`）。未知写入模式/策略上限仍保持 fail-closed。 |
| `Files.ts` | **已修复** | `workspaceEntries()` 与 `contentMatches()` 改用 `compactArray` 逐项容错，单个未知条目 `kind`（如未来新增类型）或异常行仅丢弃该项而不使整个文件树/搜索结果失败，且仍对保留条目的路径穿越（`..`、绝对路径）严格拒绝。 |
| `FloatingStatus.ts` | **已修复** | `pullRequestWatchTasks()` 与 `derivePendingBackgroundWork()` 对 `details.pullRequests`、`pendingBackgroundTasks` 及可空子对象改为 `compactObjects` 容错读取，单个非法条目不再导致悬浮状态崩溃。 |
| `SourceControlSettings.ts` | **已兼容** | 仅读取白名单 `SETTINGS_KEYS`，自动忽略 `sideThreadOpenTarget`、`featureFlags` 等未知键，对 `lockedSettings` 过滤非字符串项；环境身份、写权限与回读校验保持严格。 |
| `LabsSettings.ts` | **已兼容** | 仅读取已知实验开关，忽略未知 capabilities/settings/`featureFlags`，对 `lockedSettings` 过滤非字符串项；写路径权限与回读保持严格。 |
| `WorktreeSettings.ts` | **已兼容** | 忽略未知设置键与 `featureFlags`，`lockedSettings` 过滤非字符串，`branchNamingMode` 未知值安全降级为 `undefined`；写路径枚举与组织锁校验保持严格。 |
| `ProjectWorktreeSettings.ts` | **已兼容** | 仅解析已知项目覆盖键并保留未知存储字段，未知枚举安全降级为 `undefined`，`lockedSettings` 过滤非字符串；项目身份防原型污染与回读校验保持严格。 |
| `WorktreeStorage.ts` | **已兼容** | 忽略未知设置键，未知 `worktreeCleanup.mode` 映射为 `'unknown'` 禁用不安全写入，未知 `worktreeKeepWhen` 降级为 `undefined`；写路径目录安全与二次确认保持严格。 |
| `AutoSettle.ts` | **已兼容** | 仅读取 3 个已知字段，忽略未知配置键与 `featureFlags`，`lockedSettings` 过滤非字符串；写路径权限与回读保持严格。 |
| `ThreadDefaults.ts` | **已兼容** | 仅读取 4 个已知默认项，未知枚举值将 `supported` 置为 `false` 而非整页抛错，未知 `maxRuntimeMode` 降级为 `'unknown'` 阻止越权修改。 |
| `ServiceMaintenance.ts` | **已兼容** | 未知 `serverInstallation.kind` / `serverSelfUpdate` 安全降级为空字符串，忽略未知 capabilities/`featureFlags`；数据库存储响应与版本校验保持严格。 |
| `Environment.ts` | **有意保持严格** | 本地环境目录（`environmentDirectory`）、安全会话凭据（`savedSession`）与旧数据迁移（`migrateLegacy`）属于安全边界，任何非法/篡改字段必须 fail-closed。 |
| `Cloud.ts` | **有意保持严格** | Clerk OAuth 配置与回调、DPoP 证明生成与公钥校验、Relay 令牌与端点、Cloud 账号会话及设备批准事件（`authAccess`/`applyAuthAccessEvent`）属于鉴权与令牌安全边界，严禁放宽。 |
| `Pairing.ets` | **有意保持严格** | 直连与扫码配对地址/配对码解析，防止凭据注入与非法 scheme，保持严格。 |
| `LinkTarget.ets` | **有意保持严格** | 环境互链目标解析，防止 Agent 伪造或劫持环境地址，保持严格。 |
| `Preview.ts` | **有意保持严格** | 远端浏览器预览视口、JPEG 帧限额、控制权状态、缩放/尺寸回读与服务端会话列表去重校验，保持严格。 |
| `DevicePreview.ts` | **有意保持严格** | MJPEG 二进制边界与大小上限、HID 输入白名单、安全 Hub 路径与设备清单去重，保持严格。 |
| `Terminal.ts` | **有意保持严格** | 终端快照、渲染工作量上限与会话流状态机（含重复 ID/未知状态拒绝），保持严格。 |
| `AndroidVideo.ts` | **有意保持严格** | SEMU 视频帧头、H.264 Annex-B 与 SPS 参数集边界解析，防止恶意视频包，保持严格。 |
| `Hosts.ts` | **已兼容** | 纯本地主机分类与系统代理旁路判断，不解析服务端 RPC 列表。 |
| `IncomingShare.ts` | **有意保持严格** | 系统跨应用分享内容与文件 URI 白名单校验，防越权访问本地路径。 |
| `Keyboard.ts` | **已兼容** | 纯本地快捷键状态与帮助清单，不解析服务端响应。 |
| `LocalNotifications.ts` | **有意保持严格** | 本地通知跳转目标字段校验与运行状态去重，不涉及服务端数组放宽。 |
| `Markdown.ts` | **已兼容** | 纯客户端 Markdown/数学公式/相对路径解析，安全路径校验（`workspacePath`、`safeAssetUrl`）保持严格。 |
| `Mermaid.ts` | **已兼容** | 纯客户端 Mermaid 图表语法解析，解析失败安全返回 `undefined`。 |
| `Monogram.ts` | **已兼容** | 纯客户端项目首字母、颜色与图标 slug 解析，未知图标/颜色自动回退默认值。 |
| `Settings.ts` | **已兼容** | 本地外观/跟进模式校验与诊断摘要构建，不解析服务端 RPC 数组。 |
| `ThreadRow.ts` | **已兼容** | 纯客户端会话行展示与 Provider 图标/名称映射，未知 provider/状态安全回退默认样式。 |
| `Voice.ts` | **已兼容** | 纯客户端 PCM 语音帧分片与转写文本状态，不解析服务端响应。 |

## 回归验证覆盖

新增 `tests/forward-compat.test.mjs`，覆盖：
- 项目新增 `repositories`/`trackedFolders` 与未知 `defaultThreadEnvMode`，以及 checkpoint scope `kind: 'manual'` + `repositoryPath`
- Secret 卡片 `fields`（含非法项丢弃）及 `cards()` 单个非法项丢弃
- `server.getConfig` 含 `sideThreadOpenTarget` 与 `featureFlags` 在全部设置解析模块中无报错通过
- 未知 turn item `type` 与非法元素在 `ThreadState`、`ThreadItems`、`FloatingStatus` 中的容错
- 未知 provider/usage 枚举及非法限额项在 `Usage`、`ProviderSettings`、`Composer`、`DraftDefaults` 中的容错
- `ScheduledTasks`、`R4`、`R5`、`Files` 响应数组中单条非法/未知元素仅丢弃该项
- `Environment`、`Cloud`、`Pairing`、`Wire`（协议版本/会话身份）、`Core`（peerLinks/uploadTarget）安全边界继续严格拒绝非法输入

---

## 第 1+2 批上游同步完成记录（C1–C5、U1–U4）

基线：`6085c0f`（宿主单测 651/651）→ 同步后全量宿主单测 672/672。

### 第 1 批：连接与发送稳定性（C1–C5）

| 编号 | 上游参考提交 | 实现要点 | 关键文件 |
|---|---|---|---|
| **C1** | `11224f63d2` | `T3Client.mutate()` 增加断线重放（`resendOnSocketLoss`，最多 2 次、单次 60s 超时），复用于首条消息 `orchestration.launchThread`、`message.dispatch`、队列 `start`/`resume`、`queued-message.promote-to-steer` 与 `resumeLatestRun`；断线重连后使用同一 `commandId` 重放以依赖服务端幂等回执，显式服务端拒绝（`RpcFailure.known`）绝不重放。 | `T3Client.ets`、`tests/native-client.test.mjs` |
| **C2** | `b479ce21ed` | `Wire.ts` 新增 `validateServerConfig()`；初始配置快照解码失败时抛出 `ServerConfigIncompatibleError`，终止会话、不回退 `server.getConfig`、停止自动重连风暴，并在 `ConnectionsPanel.ets` 显示红色「版本不兼容」标签与手动「重试」；已建立连接后的后续不可读更新或流结束转为瞬态断线重连。 | `Wire.ts`、`T3Client.ets`、`EnvironmentRegistry.ets`、`ConnectionsPanel.ets`、`tests/native-client.test.mjs` |
| **C3** | `38bac7091a`、`003d53ace1` | 保护 `T3Client` 重连循环、心跳、前后台恢复、网络事件及回调（`emitUpdate`、`handleReconnectFailure`），`NetworkMonitor` 在启动/注册失败或观察者抛错后自动重启并核对默认网络，`EnvironmentRegistry` 隔离单环境异常避免阻塞其余环境。 | `T3Client.ets`、`NetworkMonitor.ets`、`EnvironmentRegistry.ets`、`tests/native-client.test.mjs`、`tests/network-monitor.test.mjs` |
| **C4** | `73e6472545` | `T3Client.watch()` 在带 `afterSequence` 恢复订阅遇到解码异常、流中断或服务端拒绝时，保留已缓存 `ThreadState` 与消息列表不闪空，立即丢弃 `afterSequence` 回退完整快照；若完整快照仍失败则设置 `threadSyncError = '无法同步消息'` 并指数退避重试，直至快照应用后清除强制标记。 | `T3Client.ets`、`Index.ets`、`tests/native-client.test.mjs` |
| **C5** | `245a1ead92` | `R4.ts` 新增 `MANUAL_CONTINUATION_FALLBACK_TEXT = 'Continue where you left off.'` 与 `manualContinuationText()`；`T3Client.resumeLatestRun()` 在空文本且无附件的手动继续命令上发送该回退文本（新服务端自动清空，旧服务端原样派发避免发送空消息），与上游实现完全一致。 | `R4.ts`、`T3Client.ets`、`tests/r4.test.mjs`、`tests/native-client.test.mjs` |

### 第 2 批：交互与审阅体验（U1–U4）

| 编号 | 上游参考提交 | 实现要点 | 关键文件 |
|---|---|---|---|
| **U1** | `78d74598d4` | `ThreadState` 同步快照 `attempts` 及 `run-attempt.created`/`run-attempt.updated` 事件；`R4.ts` 移植 `unsentManualContinuationSource()` 与 `deriveResumableRunId()`；当 `supportsNativeResume === false` 且消息已送达 Provider 时隐藏 `Index.ets` 中的「恢复最近的运行」入口并在 `resumeLatestRun()` 拦截，兼容缺少该字段的旧服务端。 | `Wire.ts`、`R4.ts`、`T3Client.ets`、`Index.ets`、`tests/r4.test.mjs`、`tests/native-client.test.mjs` |
| **U2** | `910c1a8df9` | 新增 `CollapsibleUserMessageBody.ets` 及 `ThreadItems.ts` 阈值工具（`USER_MESSAGE_FOLDED_HEIGHT = 176`，仅在内容高度 `>= 352` 时折叠）；折叠态屏蔽裁切高度回调防止闪烁循环，带底部气泡色渐变遮罩与「展开全文」/「收起」按钮，展开态通过 `@Provide('t3ExpandedUserMessages')` 按 `message.id` 在 `LazyForEach` 中稳定保持。 | `ThreadItems.ts`、`CollapsibleUserMessageBody.ets`、`Index.ets`、`tests/thread-activity.test.mjs` |
| **U3** | `71ff113795`、`210996207d` | `R5.ts` 完整移植 `classifyChangedFile()`、`isTestChangedFile()`、`filterDiffTestFiles()`、`diffFileTreePositions()` 与 `orderDiffFilesForReview()`（依赖先于被依赖、源码→测试→生成物、目录连续、保留同名符号链接双条目）；`WorkspacePrefs.ets` 新增 `pullRequestHideTestFiles`（`AppStorage` `t3HideTestFiles`），`ReviewPanel.ets` 与 `PullRequestsPanel.ets` 共享「隐藏测试文件」筛选与全隐藏空态。 | `R5.ts`、`WorkspacePrefs.ets`、`ReviewPanel.ets`、`PullRequestsPanel.ets`、`tests/r5.test.mjs`、`tests/workspace-prefs.test.mjs`、`tests/pull-request-reads.test.mjs` |
| **U4** | `b5481adcd8`、`898c22f990` | `ScheduledTasks.ts` 新增 `scheduledTaskWorktreeBaseRef()`（优先 `isDefault`，其次 `main`/`master` 及 `origin/*`），`ScheduledTasksPanel.ets` 新建工作树自动等待并选取项目默认分支；支持在编辑已绑定会话的任务时清除目标会话，显式发送 `threadId: null` 与 `unbindThread: true` 并保留原 `threadMode`，回读确认 `saved.threadId === null`。 | `ScheduledTasks.ts`、`ScheduledTasksPanel.ets`、`tests/scheduled-tasks.test.mjs`、`tests/scheduled-tasks-ui.test.mjs` |

---

## 第 3 批上游同步盘点清单（M1、L1–L4）

基线：`b52ffdb`（宿主单测 672/672），对照上游 `620cf4770d`。

| 模块 / 同步项 | 已有实现 | 缺失部分 | 需改造文件 |
| --- | --- | --- | --- |
| **M1 多仓库项目**<br>（上游 `60863edc41`） | - `Projects.ts`/`Core.ts`：单仓库 `ProjectView` 与壳缓存，P0-2 已容忍未知 `repositories`/`trackedFolders` 字段。<br>- `ProjectOverviewPanel.ets`/`Workspace.ets`：重命名、固定、归档、checkout 列表与删除（`projects.mutate`）。<br>- `R4.ts`/`ComposerCommandPanel.ets`：新任务 `DraftWorkspace`（`local`/`worktree`、`branch`、`startFromOrigin`）。<br>- `GitPanel.ets`/`ReviewPanel.ets`/`R5.ts`：单 `cwd` 的 VCS 订阅、刷新、提交/推送/拉取、切分支与审阅 Diff 排序/测试文件过滤；`ThreadItems.ts` 已兼容 checkpoint `kind: 'manual'` 与 `repositoryPath`。 | - 项目 `trackedFolders` 解析、缓存及 `projects.mutate` 更新（添加/移除仓库）。<br>- `workspace.listFolders`、`workspace.scanFolders`、`workspace.taskFolder`、`workspace.addTaskFolderRepository` RPC 与状态推导（`threadRepositories`）。<br>- 项目设置页「仓库」管理区（展示自动发现与手动关联仓库、扫描/添加/移除）。<br>- 新建任务在多仓库项目下的工作树仓库选择（默认 `<= 8` 全选、`> 8` 不默认全选）及 `launchWorkspace` 的 `repositories` 字段。<br>- Git 面板与 Review 面板按仓库分组展示、切换目标仓库、提交/推送确认目标仓库及向 taskFolder 追加仓库。 | `Projects.ts`、`Core.ts`、`R4.ts`、`R5.ts`、`T3Client.ets`、`Workspace.ets`、`ProjectOverviewPanel.ets`、`ComposerCommandPanel.ets`、`GitPanel.ets`、`ReviewPanel.ets`、`Index.ets`、新增 `ThreadRepositories.ts` |
| **L1 只读查看链接环境会话**<br>（上游 `1cb3a8c753`） | - `Core.ts`/`LinkTarget.ets`/`PeerLinkForm.ets`/`LinkedEnvironmentsSection.ets`：`peerLinks.list`、`peerLinks.answerRequest`、`mintPeerPairingCode`、`peerLinkViews`。<br>- `Wire.ts`：`ThreadState` 完整支持 snapshot/event/historyCursor/prependHistory。<br>- `R4.ts`/`ThreadAgentsPanel.ets`/`ThreadExtrasPanel.ets`：`SubagentView` 已提取 `remoteChild.threadId` 与 `remoteChild.environmentId`。 | - `peerLinks.names`、`peerLinks.subscribeThread`、`peerLinks.threadHistoryPage`、`peerLinks.threadItem` RPC 封装。<br>- `LinkedThreadTarget`、`resolveLinkedThreadOpen()` 与 `linkedThreadFailure()`（区分 `disabled`/`unknown_link`/`expired`/`rejected`/`unreachable`/`thread_not_found`/`incompatible` 与权限拒绝，非瞬态失败禁止重试刷屏）。<br>- `RpcFailure` 保留服务端结构化错误字段（`message`/`label`/`answeredAs`）。<br>- 会话 Markdown 链接中 T3 会话链接识别与跳转分发。<br>- 只读链接会话视图（消息流、状态、历史翻页、步骤展开、底部只读栏禁发）。 | `Wire.ts`、`Core.ts`、新增 `LinkedThread.ts`、`T3Client.ets`、新增 `LinkedThreadPanel.ets`、`MarkdownView.ets`、`ThreadAgentsPanel.ets`、`ThreadExtrasPanel.ets`、`Index.ets` |
| **L2 从只读会话直接连接链接环境**<br>（上游 `d7f6b3efca`） | - `EnvironmentRegistry.ets`/`T3Client.ets`/`Dpop.ets`：完整 DPoP 直连配对（`add()`）、`probeRoute()` 身份校验与 `connection-new` 表单。 | - `peerLinks.pairClient` RPC 与 `PeerLinkClientPairingResult`（`credential`/`unsupported`）解码。<br>- `connectLinkedEnvironment()` 流程：换取一次性配对码 → 探测本机可达地址并校验 `environmentId` → 预填新连接页由用户确认走 DPoP 配对；不支持/拒绝时仅预填地址转手动配对。<br>- 已连接环境检测：目标环境已在本机配置并连接时直接切换打开，不重复配对。<br>- 只读底栏「连接此环境」操作与反馈。 | `LinkedThread.ts`、`T3Client.ets`、`EnvironmentRegistry.ets`、`LinkedThreadPanel.ets`、`Index.ets` |
| **L3 子智能体、侧聊、链接会话统一打开方式**<br>（上游 `7c6e889ddb`） | - `Projects.ts`：`ThreadView` 已有 `lineageRelationship`、`lineageParentThreadId`、`lineageSideChat`、`creationSource`、`delegatedFrom*`。<br>- `ThreadExtrasPanel.ets` 已有开启 Side chat（`runFork(true)`）与子智能体打开入口。<br>- `SettingsPanel.ets`/`WorkspacePrefs.ets` 已有本地偏好与 `server.updateSettings` 设置同步。 | - `sideThreadOpenTarget`（`panel`/`main`，默认 `panel`）解析、设置页修改与服务端/本地持久化。<br>- `SideThread.ts`：`sideThreadKind()`、`sideThreadComposer()`、`resolveSideThreadOpenTarget()`。<br>- 三类入口（子智能体、侧聊、链接会话）统一打开逻辑：按 `sideThreadOpenTarget` 决定以侧会话面板或主会话页打开，支持面板切主视图，关闭/返回后精准回到父会话及原滚动位置。<br>- 父会话中的侧聊列表/入口展示。 | 新增 `SideThread.ts`、`WorkspacePrefs.ets`、`SettingsPanel.ets`、`T3Client.ets`、`ThreadAgentsPanel.ets`、`ThreadExtrasPanel.ets`、`ThreadBackgroundWorkPanel.ets`、`LinkedThreadPanel.ets`、`Index.ets` |
| **L4 一次链接多个环境（可选）**<br>（上游 `8e8ff9b243`） | - `T3Client.ets` 已有 `mintPeerPairingCode()`、`linkedEnvironments()`、`directAddresses`；`ConnectionsPanel.ets` 已有环境列表与 `LinkedEnvironmentsSection.ets`。 | - `peerLinks.link` RPC 与 `PeerLinkError.answeredAs` 错误归类。<br>- `LinkBatch.ts`（候选过滤 `linkBatchCandidates`、并发 4 路 `runLinkBatch`、失败汇总与重试）。<br>- 环境页「批量链接环境」多选界面。 | `Wire.ts`、`Core.ts`、新增 `LinkBatch.ts`、`T3Client.ets`、`ConnectionsPanel.ets`、`LinkedEnvironmentsSection.ets`、`Index.ets` |
