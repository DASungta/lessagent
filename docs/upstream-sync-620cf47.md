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
