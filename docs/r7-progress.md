# R7 系统集成与设置

## 真机进度

| 路径 | 已验证 | 仍待验收 |
|---|---|---|
| 系统入口 | 中文离线口述、文字分享草稿、在线通知、桌面快捷操作及静态卡片。[语音](evidence/r8/batch5/README.md) · [桌面卡片](evidence/r8/batch16/README.md) | 图片授权与离线附件、离线推送、硬件键盘 |
| 项目与会话 | 新任务默认值、工作树项目覆盖与恢复继承、源码管理目录在添加项目时生效。[工作树](evidence/r8/batch27/README.md) · [源码管理](evidence/r8/batch28/README.md) | 实际 checkout 的子模块及命名、自动拉取、组织策略 |
| 设置与维护 | 主题、用量、定时任务、分享缓存清理、服务版本和数据库状态。[定时任务](evidence/r8/batch6/README.md) · [服务维护](evidence/r8/batch18/README.md) | 真实 provider 认证、适格数据库整理、安装更新与续跑 |

当前安装包和全量测试数见[整体开发进度](development-status.md)，逐项退出条件见[R6–R8 清单](r6-r8-acceptance.md)。

## 历史交付记录

2026-11-18。首批实现设置可用性与外观入口，**R7 未完整完成**。本批不占用设备、不单独构建，统一交由主代理整合与验收。

## 已实现

- 设置搜索按分组匹配，支持多词、忽略英文大小写及无结果状态；保留环境、项目、归档与原有分组回调。
- 跟随系统/浅色/深色调用 HarmonyOS `ApplicationContext.setColorMode`，偏好保存至独立 `appearance` Preferences；保存失败回滚原选项，不假成功。启动需调用 `prepareAppearance(context)` 恢复。
- 设置行显式使用正文颜色，返回/展开用已有线形图标，项目分组选中状态使用原生 Radio；行高随内容伸展，保留大字体空间。
- 诊断页仅显示包版本、环境/项目/归档数量及平台，支持用户明确点击后复制；构造器只接受限定版本字符串和非负整数，不序列化任何环境对象、地址、凭据、日志或正文。
- 关于页从 BundleManager 读取实际安装包版本；离线上游 MIT 许可来自固定 `ad1b136` 归档根 LICENSE，完整保留版权文本。没有伪装远程更新检查或完整依赖许可证清单。

## 触达文件与依据

- `components/SettingsPanel.ets`：现有设置入口直接使用新增功能，无需增添虚假导航。
- `protocol/Settings.ts`：搜索、外观值校验、诊断允许字段。
- `services/Appearance.ets`：应用级主题切换及持久化；主代理接入 EntryAbility 启动。
- `resources/rawfile/t3code-license.txt`：固定上游原始 MIT 文本。
- `tests/settings.test.mjs`：搜索、诊断输入限制、主题保存/恢复/失败回滚。
- 对照固定上游 `SettingsAboutRouteScreen.tsx`、`SettingsDiagnosticsRouteScreen.tsx`，沿用版本/诊断/复制行为的职责；不把 Expo 日志与更新机制移植成无效鸿蒙入口。

## 检查与待验收

新增宿主测试 **3/3 通过**。本机 SDK 核实颜色枚举、getPreferences、setColorMode、BundleManager 与 TextDecoder API。构建及真机结果由整合阶段补充，不能把宿主模拟 Preferences 当作设备持久化证明。

需真机验证：设置行颜色、搜索/无结果、深浅/系统切换、杀进程恢复、诊断复制、离线许可、大字体/读屏与系统返回。子页状态通过 `@Link section` 交由父页面管理；父页面传入 `settingsSection`，系统返回先清空子页再退出设置，待统一真机核对。

尚未覆盖：通知/推送及冷启动定位、语音、快捷方式/卡片、外接键盘、系统分享导入、全部 provider/Agent/worktree/用量等服务端设置、完整三方许可清单。不得据本批宣布 S01–S21 全部完成。

## 第二批：环境级工作树默认设置

新增 `WorktreeSettingsPanel.ets`、`protocol/WorktreeSettings.ts` 与 `tests/worktree-settings.test.mjs`。设置页通过 `connection` 接收当前环境的 T3Client，新增真实“工作树”入口，不需要改动 T3Client 的公共 API。

覆盖设置：

- `newWorktreesStartFromOrigin`：新工作树优先远程起点。
- `worktreeSubmodules`：继承（发送 `null`）、递归、仅顶层、跳过。不会把继承转换为显式 recursive。

固定上游依据：`SettingsServerControlsRouteScreen.tsx` 的 Worktrees 分组；`contracts/settings.ts` 中字段与 ServerSettingsPatch；`contracts/rpc.ts` 的 `server.updateSettings` payload `{ patch }`；`managedPolicy.ts` 的 `lockedSettings`。

行为与边界：

- 进入读取 `server.getConfig`，严格校验环境身份、已返回的字段与支持值。字段缺失/未来未知值显示读取失败，不推测默认值。
- 写前重新读取组织策略与身份；只发选中的一个字段。`settings:write` 明确拒绝时只读，组织锁字段禁用并显示管理者。
- 修改后再读取配置比对结果，只有一致才显示已保存。超时/拒绝/回读不一致均不自动重试，必须先刷新核对才允许再次编辑。
- 当前为**单环境默认值**，不是项目覆盖编辑；界面明确项目覆盖与创建时选择可以覆盖默认值。没有修改已有工作树、删除/清理目录或提升运行权限。
- SettingsPanel 与新页面 Scroll 顶对齐，修复短搜索结果垂直居中。

新增 4 项宿主测试通过，R7 累计 7/7：字段/身份校验、null 继承、组织锁、单字段 patch、读写读顺序、权限拒绝、失败/不一致不重试。真实服务与真机读写仍由主代理统一验收；本批没有自行修改任何服务端环境设置。

## 第二批联合真机结果

258/258 测试、签名构建与最终包安装通过，详见 [第二批证据](evidence/r8/batch2/README.md)。本记录区分已真机路径与仅宿主测试路径，不代表阶段全量完成。

## 第三批：系统分享文字接收

新增 `protocol/IncomingShare.ts`、`services/ShareInbox.ets`、`components/ShareImportPanel.ets` 和 `tests/incoming-share.test.mjs`。`module.json5` 为 EntryAbility 增加 `ohos.want.action.sendData` skill，仅声明 `general.plain-text` 与 `general.hyperlink`；没有新增权限。

真实接收使用 ShareKit `systemShare.getSharedData(want).getRecords()`，不是从临时自定义参数拼装业务内容。固定上游 `incoming-share-model.ts`/`incoming-share-inbox.ts` 的核心语义是先收件、选择目的地、保存草稿、消费收件；本批保留这一顺序，暂不移植媒体持久化。SDK 与官方依据：[ShareKit 接收 API](https://developer.huawei.com/consumer/en/doc/harmonyos-references/share-system-share)、[分享接收配置](https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/share-kit-faq-0001/)。

### 接入合同

1. EntryAbility `onCreate/onNewWant` 调用 `void acceptIncomingShare(want)`。非 sendData Want 忽略，冷启动与热启动解码串行，避免后到的内容越过先到的内容。
2. Index 观察 `t3IncomingShareRevision`，读取 `peekIncomingShare()`，错误提示来自 `t3IncomingShareError`。待处理队列仅存内存；不会记录日志或自动写入磁盘。
3. `ShareImportPanel` 展示可编辑文字和目标，回调 `onChooseDestination` 选择环境/项目；`onConfirm(text)` 必须创建**独立新草稿**并通过现有 DraftStore 保存，成功后 `removeIncomingShare(id)`。不得覆盖原有草稿、自动创建远程会话或发送消息。
4. 保存失败保留原分享；取消明确删除指定收件。没有目标时禁用保存按钮；进程退出前未确认的分享会丢失，确认后的草稿按 DraftStore 恢复。

### 输入边界与验证

- 纯文字及 HTTP(S) 链接只作为文字，不解析/执行 HTML、不自动打开链接或下载资源。
- 最多 32 个文本记录、合并后最多 R4 输入上限 120000 字符、最多 8 条待处理分享；超限整体拒绝，不静默截断。混合图片/文件也整体拒绝，避免假装已导入附件。
- 同一待处理文字重复投递去重；消费按 id，复制返回对象防止界面改写收件。错误消息不泄露平台原始异常或私有 URI。
- 新增宿主测试 **4/4 通过**：文字合并、安全链接、空/异常/超长/媒体拒绝、队列去重与上限、串行 Want、错误保留及不泄漏异常。

真实分享面板是否列出本应用、第三方文字/网页来源、冷/热启动、目标选择、确认后新草稿持久化及不自动发送，均待主代理统一接入与真机验收。本批没有实现后台云推送，也未把本地在线通知冒充推送。

### API24 分享 skill schema 修正

首次整合构建在 PreBuild 拒绝只有 `utd` 的 URI。核对安装 SDK 的 `toolchains/modulecheck/module.json` 后确认：`utd` 是有效字段，但所在分支同时要求 `scheme`；不是 SDK 不支持 UTD。按[官方目标应用接收配置](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V13/share-interface-description-V13/)补充 `scheme: "file"` 和 `maxFileSupported: 32`，仍只接收声明的纯文字/链接类型。

使用 Hvigor/SDK 自带 Ajv 对实际 URI schema 验证通过，并将此校验加入测试（旧的仅 UTD 配置应失败、新配置应通过）。分享专项现为 **5/5 通过**；最终 HAP 构建与系统分享匹配仍由主代理验证，未改为手工伪造 Want。

## 第三批联合真机结果

276/276 测试、最终签名包构建和安装通过。连续预览/点击/输入/重启恢复/关闭，以及系统分享→独立草稿→重启恢复已实际验证；范围与清理见 [第三批联合证据](evidence/r8/batch3/README.md)。阶段整体仍未关闭。

## 第四批：在线任务本地通知与点击目标

新增 `protocol/LocalNotifications.ts`、`services/LocalNotifications.ets`、`components/NotificationSettingsPanel.ets`、`tests/local-notifications.test.mjs`，未新增 module 权限。SDK 使用 NotificationKit `requestEnableNotification(context)`/`isNotificationEnabled`/`publish`，点击使用显式 WantAgent 启动本应用 EntryAbility。

这是**在线收到状态变化时的本地提醒**，不是离线云推送，也没有承诺后台常驻。现有后台 suspend 会断开连接，未收到的变化不能通知；没有补发历史队列。固定上游参考 `foregroundNotificationBehavior.ts` 的当前会话抑制与 `notificationNavigation.ts` 的冷/热启动点击路由。

### 接入合同

- 启动调用 `prepareLocalNotifications(UIAbilityContext)`，仅加载默认关闭的独立 Preferences，不弹系统授权。父设置入口打开 `NotificationSettingsPanel({ onBack })`，只有用户点击启用才请求系统授权。
- 父设置 `configureNotificationTargets(validate)`，按 localId/environmentId 在当前目录核对启用/未删除/当前账号；默认校验器拒绝全部通知，漏接不会误通知。
- 每次 registry 更新遍历实际 client，调用 `observeThreadNotifications(target, connectionGeneration, threadStateObject, runs)`；target 为 `{localId,environmentId,threadId}`，runs 仅 `{id,status}`。
- 初次、新 ThreadState 对象或连接代际变化只建立基线。基线清除该目标旧 run 状态，包括初次空状态，防止重连补发历史完成。后续仅 preparing/starting/running/waiting → completed/failed/interrupted 转换可提醒，重复终态与 cancelled 不提醒。
- `setVisibleNotificationThread(target | undefined)` 同步当前实际显示的会话；前台同一会话不提醒。全链路键包含本地目录 ID + 环境 ID + 会话 ID，不用裸 threadId。
- EntryAbility `onCreate/onNewWant` 调用 `acceptNotificationWant(want)`。父观察 `t3NotificationTargetRevision`，通过 `peekNotificationTarget()` 获得待定位目标，必须重新核对环境/账号和真实会话存在后再打开，最后 `clearNotificationTarget()`。目标无效仅提示，不连接到 Want 提供的新地址、不自动发送指令。

通知标题与正文固定为通用完成/结束状态，不包含项目名、消息、模型输出或秘密；只有三个范围 ID 进入点击参数。关闭通知保存偏好、清除本应用通知和跟踪状态；异步发布前后检查设置代际与目标有效性，防止关闭后悬挂通知。设置保存失败尝试恢复旧偏好，错误提示不拼接底层异常内容。

新增宿主测试 **3/3 通过**：目标校验/多环境隔离、首次与重连空快照不补发、状态去重、默认关闭/授权仅显式触发、前台当前会话抑制、固定通知内容、点击解析、权限拒绝与关闭。尚需主代理真机验证授权弹框、真实新事件通知、通知中心点击与冷启动路由、系统撤销权限；不以 SDK mock 作为真机验收。

### 通知真机续调诊断

只读复核父接入：registry 的 client.onUpdate 会通知 Index，watch 创建新 ThreadState、增量 apply 保持同对象；代际变化/新对象只建基线。validTarget 要求当前目录环境可见且 shell 包含目标会话。WantAgent 创建不会主动启动会话，通知点击目标由 EntryAbility 接收后才交父路由，不能仅依据界面回到聊天判断点击验收成功。

发现应保留的边界：T3Client 的 onUpdate 有 50ms 合并；若 running 与 completed 在同一合并窗口内且未事先观察到 active，客户端不能据终态猜测新任务完成，当前不发通知。切换订阅/重连同样不补发首次快照历史状态。此轮未修改父事件链路。

为区分未观察到事件、主动抑制、权限拒绝与系统接受，通知设置新增只读状态卡：系统通知权限、最近判定、最近系统接受时间、有效点击接收时间；失败只显示调用阶段与 SDK 数字错误码。全部为内存诊断，不包含任务正文/目标标识，不添加伪造通知测试按钮。“系统已接受”也不等于通知中心已展示或点击导航已验收。相关宿主测试仍 3/3 通过。

## 第四批联合真机结果

296/296 测试、最终签名构建与安装通过。本地通知完成与点击定位、常规特大字号/深色抽查、语音权限拒绝已实际验证。设备流和语音口述仍待所需条件；详情见 [第四批联合证据](evidence/r8/batch4/README.md)。

## 第五批：Provider 与模型目录

新增 `components/ProviderSettingsPanel.ets`、`protocol/ProviderSettings.ts`、`tests/provider-settings.test.mjs`；SettingsPanel 接入真实 Provider 入口，并按主代理约定接入后续消息设置与键盘帮助组件。

已实现：

- 从当前连接 `server.getConfig` 读取并核对 environmentId，展示 Provider 名称、enabled/installed/组织 allowedDrivers、实际 auth 状态与模型目录；搜索 Provider 或模型。未知 auth 不显示成已登录，未安装/停用/组织禁用明确区分。
- 用户点击刷新调用既有 `refreshProviders(instanceId)` 后重新读取配置；首次进入只读取配置，不自动安装、不自动开始认证。
- 选中支持认证的 Provider 后订阅 `provider.auth.subscribe`，校验 instanceId/phase/flowId/interactionId；切换对象、离开页面取消订阅，旧连接和旧 Provider 回包不改新页面。15 秒未收到状态显示可重试说明。
- 登录按钮有产品确认框，随后调用既有 `startProviderAuth`。browser/deviceCode 挑战展示真实状态/验证码，HTTP(S) 登录页仅用户点击后打开；requiresConsent 通过明确同意按钮调用 `provider.auth.respond`。不输出授权 URL、验证码或原始异常到日志。
- 显式取消发送 `{instanceId,flowId}` 到 `provider.auth.cancel`，用返回/订阅真实 phase 显示取消结果。未知结果不自动重试并锁修改，需刷新核对；晚到 RPC 响应不能覆盖更新的订阅状态。
- 已完成/失败/取消/过期状态分别显示，succeeded 不继续给出重复登录入口。认证状态未知或权限不足时不能伪造成功。模型选择仍复用原会话模型面板，不在目录重复建设置机制。

固定上游依据：`SettingsProviderAccountsRouteScreen.tsx`；`contracts/server.ts` 的 ServerProvider 与 auth；`providerSetup.ts` 的挑战与流程状态；`rpc.ts` 的 provider.auth.start/subscribe/respond/cancel。权限沿用 `providers:manage`，服务端最终授权。

新增宿主测试 **3/3 通过**，覆盖环境/Provider 身份、组织限制、未知账号状态、安全登录 URL、浏览器/设备验证码/不支持挑战、不泄漏终端内容、过期和终态。未在真实账号发起登录或注销，构建与隔离真机只读列表验证交由主代理。

未覆盖：terminal/credentials 输入、client callback 粘贴、多认证方法选择、账号新增/删除/注销、Provider 安装卸载、模型自定义与默认模型修改；unsupported 挑战明确提示在服务端/桌面继续，并保留取消与真实状态订阅。完整 provider 设置范围仍未关闭。没有卸载、清理、登出或操作真实账号。

## 下一批 S07/S12 契约核对（尚未实现）

固定上游 ServerControls/projectSettings 已核对。优先默认权限 `defaultRuntimeMode`、默认工作区 `defaultThreadEnvMode`、流式 `responseStreamingMode`、Agent 浏览器 `enableAgentBrowserAccess`。使用 getConfig 读取身份与策略，updateSettings 只 patch 单字段，写后 getConfig 回读，不重放未知结果。

不能只做设置页面：Index.beginDraft 与 confirmShare 当前仍写死新草稿默认值，必须同时消费环境默认和项目覆盖，已有草稿保持保存值。工作区 null 表示遵循 t3.json，并非直接 local；组织 lockedSettings 按父子路径相交，权限受 maxRuntimeMode 上限。未知字段/旧服务应不可编辑，不回退成放权默认值。

S12 可继续对接 sidebarAutoSettleOnMerge、sidebarAutoSettleAfterDays（null 或 1–90，契约不限定整数）、autoResumeLimitedThreads、snoozeLimitedThreads；保留未修改字段。workingShelfEnabled 与 useLastProjectForNewThreads 是设备偏好，须连同列表分区或跨环境项目身份校验实现。相关链路尚无交付/真机证据。

## 第七批开发中：会话默认设置 S07

新增 `protocol/ThreadDefaults.ts`、`components/ThreadDefaultsPanel.ets`、`tests/thread-defaults.test.mjs`。页面接口 `ThreadDefaultsPanel({ connection, onBack })`，只修改当前连接环境，不广播其他环境或改写项目覆盖。

- 真实字段：`defaultRuntimeMode` 四种权限、`defaultThreadEnvMode` 的 null/local/worktree、`responseStreamingMode` 的 turn/paragraph、`enableAgentBrowserAccess` boolean。缺失或未来值保持不可编辑，不伪造服务默认值。
- `server.getConfig` 检查 environmentId；修改前重新读取政策/权限，`server.updateSettings {patch}` 仅携带一个字段，再 getConfig 验证。失败或不一致要求显式刷新，不自动重放。组织锁按父子 dot-path 匹配；权限模式遵循 `managedPolicy.limits.maxRuntimeMode`，未知上限拒绝修改权限模式。
- 页面使用现有原生卡片/字号/主题，当前值只来自服务回读。离开页面撤销代际，异步结果检查原连接及环境身份；只读范围禁用修改。
- 5 项宿主测试覆盖身份/字段类型/null继承/未知值、锁与上限、单字段写与回读、超时不重试、读期间断开或撤销权限。

固定上游依据：`SettingsServerControlsRouteScreen.tsx`、`contracts/settings.ts`、`contracts/managedPolicy.ts`、`shared/projectSettings.ts`。尚需父代理连接 SettingsPanel 入口、让新草稿（含分享草稿）消费项目覆盖/环境默认/t3.json 的有效值；已有草稿保持原保存值。只加设置页面不代表默认行为闭环。未构建全包或在真机修改设置；联合构建、逐页视觉与隔离服务写后恢复由父代理验证。

下一批S12核对（gpt-6.2-sol）：全局sidebarAutoSettleOnMerge、sidebarAutoSettleAfterDays（null关闭或1–90）、sidebarAutoSettleKeepPullRequests通过getConfig/updateSettings单字段patch。分别结合threadAutoSettlement/threadAutoSettlementScope能力和组织锁，写前读及写后核对。服务端ThreadSettlementServiceV2已负责定时/事件消费，客户端不新增自动dispatch。OnMerge只控制merged，closed行为需单独遵循服务端；不要文案合并。workingShelfEnabled/useLastProjectForNewThreads为本地偏好，须接列表及新任务路由消费，不只是开关。尚未实现。

## 第十一批：全局自动归整设置

AutoSettle协议和原生页已接入设置搜索，388项回归通过，构建安装成功。真机闲置7→90→7天修改及服务端回读通过，原配置恢复。能力与组织限制已测试；真实归整事件、项目覆盖编辑及本地working/last-project仍待完成。见 [B11](evidence/r8/batch11/README.md)。

## 第十二批：工作中分组

本地偏好已接设置与列表分组/排序消费，保留展开状态和搜索/置顶/暂缓/归整优先级。390项回归及构建通过；修复Builder行反馈缓存后，真机关闭、重启仍关闭及恢复开启通过。运行态分组变化与完整多行重排仍待验/实现。见 [B12](evidence/r8/batch12/README.md)。

## 第十三批：使用最近项目

默认开启的本地偏好及普通新任务入口已接入，环境+项目身份过滤，分享保留独立目标选择。394项测试通过；真机开启直达原项目、关闭回选择器、测试草稿删除及未发送回读通过。更多环境/重启矩阵待补。见 [B13](evidence/r8/batch13/README.md)。

## 第十四批：实验功能

按环境Labs两开关已实现，399项回归、构建安装及真机只读显示通过。能力/策略/单字段写回读有专项测试，实际写入及快速检出仍待真验。见 [B14](evidence/r8/batch14/README.md)。

## 第十五批：桌面快捷入口

新任务/会话列表静态快捷菜单已配置，受控单次导航已接冷/热生命周期。403项全量通过，重连保护修正后20项专项及构建通过。真机实际长按菜单、冷启动新任务选择器和冷热会话列表通过；未发送任务。小组件及完整异常矩阵仍待。见 [B15](evidence/r8/batch15/README.md)。

## 第十六批：桌面服务卡片

2×2新任务/会话列表静态卡片已添加真机桌面，405项回归与构建通过。修复系统顶层/嵌套同动作重复传参兼容，保留冲突/分享/URI拒绝与单次TTL。实际卡片冷新任务/热会话列表主路径通过；升级/账号/读屏等待验。见 [B16](evidence/r8/batch16/README.md)。

## 第十七批：服务维护

只读版本/安装方式/数据库状态与显式发布检查已接入，409项回归及真机数据核对通过。缺失值不当零，未知版本不当已最新。更新安装、重启、清理仍待实现/验收。见 [B17](evidence/r8/batch17/README.md)。

## 第十八批：数据库整理

手动回收真实重启契约及单次/未知结果保护已实现，412项回归和构建通过。当前隔离库自动增量回收开启、无空闲页，真机正确不提供手动操作；未改变DB模式或重启。成功回收与重启矩阵待验。见 [B18](evidence/r8/batch18/README.md)。

## 第十九批：诊断分享

复用脱敏摘要的系统分享入口已实现，8项设置测试与构建安装通过，真机面板内容核对后取消，未向外发送。完整tracing/导出矩阵仍待。见 [B19](evidence/r8/batch19/README.md)。

## S20追踪边界核对

固定上游移动追踪是构建配置：app.config.ts:483–487注入Expo extra，features/cloud/publicConfig.ts仅在HTTPS接收地址、数据集和令牌均有值时启用，features/observability/tracing.ts消费该配置。SettingsDiagnosticsRouteScreen的用户开关是Crash Reports，与OTLP追踪独立。当前鸿蒙没有追踪导出或对应崩溃上报，不能声称已经启用，也不把桌面Telemetry Export的OTLP地址设置移到移动端。后续范围是客户端构建门控、隐私说明和实际导出/崩溃上报验收；本次不新增外发端点、不读取或记录令牌、不操作服务。

## 第二十二批：工作树分支命名

三个真实命名字段已接，424项回归通过。真机模式修改/回读/恢复及隐藏前缀保留通过，未创建工作树。目录/清理与完整覆盖矩阵待做。见 [B22](evidence/r8/batch22/README.md)。

## 第二十三批：工作树存储

全局目录与六项清理规则编辑已实现，429项回归通过。目录修改/回读/恢复和增强清理确认取消真机通过，原配置与工作树列表保持一致。实际清理与项目覆盖编辑待验/实现。见 [B23](evidence/r8/batch23/README.md)。


### B23 后续：重连权限与页面恢复

连接成功自动读取权限、丢弃旧代次/旧请求结果，并将权限响应式传到两个工作树设置页。432/432回归及签名构建安装通过；Mate60Pro存储页后台往返自动恢复编辑、打开目录编辑并取消，无手动刷新和配置写入。见[evidence/r8/batch23/README.md](evidence/r8/batch23/README.md)。新增可编辑大字体和分支页独立后台矩阵待验。


B25 已验首页筛选空态、清除、冷启动保留、排序反馈与特大字号滚动。草稿切换工作区后保留关闭的远端起点。全量 441/441。[本批证据](evidence/r8/batch25/README.md) · [项目覆盖范围](worktree-project-overrides.md)


B27 已接入五项项目工作树覆盖，以及终端翻页和左右方向键。Mate60Pro 验证项目远程起点保存、草稿消费、另一个项目继承、恢复，以及真实 less 搜索/翻页/退出。[本批证据与范围](evidence/r8/batch27/README.md)


B28 上线全局源码管理设置、项目管理中的添加入口，已验默认目录及分层克隆目标的实际表单消费。终端补验两轮持续输出、冻结快照和历史上限。462/462 全量测试通过。[本批证据](evidence/r8/batch28/README.md)


B31 文件源码和 Diff 支持独立字号、自动换行与紧凑行号。已实测长行复制、深色特大字号和会话工具入口。[真机记录](evidence/r8/batch31/README.md)


B34 已验证未绑定任务的显式模型编辑、取消与还原。测试任务始终停用。[特大字号截图与数据库回读](evidence/r8/batch34/README.md)


B35 已验证定时任务绑定已有会话、未绑定首次运行创建的配置，以及特大字号的目标显示。[目标会话实测](evidence/r8/batch35/README.md)


B36 未绑定定时任务支持工作区选择；基准分支、本地起点、已有 checkout 的真实保存及失效重选已真机验证。[保存与恢复记录](evidence/r8/batch36/README.md)


B37 已真机验证系统文件管理器双 TXT 审阅、目标确认上传、附件草稿恢复与逐项移除。最终全量 532/532。[系统分享实测](evidence/r8/batch37/README.md)

B38 全量宿主测试 536/536。Mate60Pro 从系统图库分享一张 PNG，在审阅页主动查看本地缩略图。确认前无新增附件，确认后服务端新增 1 个附件，原图 2554 字节且 SHA-256 一致，消息始终为 6 条。杀进程重开后草稿恢复了同名图片，验收草稿已删除。点击首页「T3 Code」可展开环境管理面板。[B38 真机实测](evidence/r8/batch38/README.md)
