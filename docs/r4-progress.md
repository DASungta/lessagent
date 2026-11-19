# R4：草稿、环境、模型、队列、请求与附件

> 最新结论（2026-11-18 汇总）：已推进至文末第三批，208/208 测试、签名构建及专用机部分 UI 回读通过。第二批及首批边界是历史状态；当前剩余项以文末“仍未验收”为准。R4 未完整关闭，整体见 [进度总览](development-status.md)。

2026-11-17。状态：**R4 第二批已实现并通过 195 项本地测试、签名构建和专用 Mate60Pro + 隔离 T3 0.1.9 主链路回读；仍缺完整队列写操作、多附件/媒体 picker、Guest share 隧道、结构化 user input provider 路径、用量恢复及原版逐页视觉。整个 R4 尚未完成。**

本批先解决 R3 遗留的“选项目/模型后创建空会话”主流程，不等待 R2 云链路验收。没有初始化 Git、提交、发布、增加依赖、变更签名、操作设备或重启服务。开始前备份见 `evidence/r4/pre-r4-source.tar.gz`，包含原应用源码、测试和相关索引；不用于覆盖后来其他会话的工作。

## 已实现

### 项目选择 → 本地草稿 → 首次发送

- 选择已有项目、No project 或新建/克隆完成的项目后，进入原生对话页的本地草稿态。取消/返回不发送 `thread.create`；不再显示原先的“创建空会话”表单。
- 草稿正文与模型选项按 `localId + projectId` 进程内隔离；切项目时保留，切环境后同 projectId 不串。已有会话正文仍按 `localId + threadId` 保存。发送期间输入的新文字不会被旧回包清掉。
- 首次发送复用固定上游 `startThreadTurn` 的实际网络语义：一个 `orchestration.launchThread`，包含自分配的 threadId、initialMessage.messageId、modelSelection、runtimeMode、interactionMode、root workspaceStrategy 和首条消息。没有先建空会话再发第二个写请求的窗口。
- 发起前写入原有受保护的 recovery marker；相同连接内阻止双击、另一次 launch、重连和其他修改。存储失败不出站；回包身份不匹配/连接变化不清除 marker；失败不自动换 ID 重发。
- 首发结果未知时，把草稿转到已经分配的 threadId 供核对，不让同一正文残留在“新建任务”草稿中再次出现。重连仍靠原完整快照和人工核对门槛，不据超时推断服务没有执行。
- 首批单文件能力已在第二批扩展为最多 100 个 file/image、file ≤50 MiB、image ≤10 MiB、图片合计 ≤80 MiB；上传只申请/消费文件能力，不创建会话。草稿附件与旧会话附件以不同 scope 隔离，逐项失败保留待重试 URI，支持取消当前上传。

### 模型与会话设置

- 原生模型/选项 sheet 同时用于新草稿和已有会话；根据模型 capability 的 optionDescriptors 展示 select/boolean 控件，选项可恢复为 provider 默认值。
- 提交前核对模型存在、provider 安装/启用、项目 provider override、组织 allowedDrivers/maxRuntimeMode、provider supportedRuntimeModes 和 plan 支持；重复/失效/类型错误选项不发送。
- 新草稿设置只修改本地状态；已有会话分别使用原版 `thread.model-selection.set`、`thread.runtime-mode.set` 和 `thread.interaction-mode.set`。三个设置是独立请求，某一步失败后停止；**不保证三项事务原子性**，必须回读核对已生效部分。每个请求仍保留未知结果保护。
- 通过服务端快照/线程配置事件保留当前 model/runtime/interaction；已确认的设置同步到当前投影，避免保存下一项时仍用旧模型验证。

### 服务端消息队列

- ThreadState 保留 projection 的 runs、原始 message records 和 thread details；run/message 事件更新这些事实，旧 sequence 不覆盖新队列。没有用本地 timer 自动启动任务。
- 输入区支持自动发送、排队发送和引导运行；分别沿用 upstream dispatchMode/deliveryIntent。新增队列 sheet 显示排队消息、held 状态，提供编辑、移除确认、上移、立即开始和恢复队列。
- 编辑使用 `queued-run.edit`，本批只替换文本，**不传 attachments**，保留服务端已有附件。reorder 使用 beforeRunId，队尾是 null；resume 使用 queue.resume。
- 操作前重新检查目标仍为 queued；若任务已经运行，不提交旧的取消/编辑。服务端返回确认后等待投影更新；失败不本地假装成功，不自动重试。

### 请求卡片修复

- 卡片显式绑定所属 T3Client。
- 多问题的必填校验失败时保留其他已填答案，允许修正；空白字符串/仅空白多选自定义值不算必填完成。秘密值仍在提交前清空，不因此持久化或回填。

## 源码与检查

新增协议：`protocol/Composer.ts`；新增 UI：`components/TaskSettingsPanel.ets`、`QueuePanel.ets`。接入修改 `pages/Index.ets`、`services/T3Client.ets`、`AttachmentPicker.ets`、`protocol/Wire.ts` 与 `RequestCard.ets`。测试执行真实适配层，并用假 NetworkKit/文件选择器注入网络、存储和回包异常；这些是宿主测试，不能当作真实服务证据。

```sh
node --experimental-strip-types --test tests/*.test.mjs
./scripts/build.sh
```

- 本轮 188/188 通过；原 R3 173 项保留，新增 15 项覆盖 launch、草稿、模型/策略、队列及回答校验。日志：[r4-local-tests.log](evidence/r4/r4-local-tests.log)。
- 最终签名构建通过，见 [构建日志](evidence/r4/r4-final-build.log)；候选包和 hash 在 [证据索引](evidence/r4/README.md)。没有覆盖安装专用机上的 R3 产品包。
- 原 `/tmp/t3code-harmony-upstream` 的 Git HEAD 当前不可用；本轮没有修它或初始化 Git。直接验证项目内归档 SHA256 后把固定源码解到独立 `/tmp/t3-harmony-r4-upstream`，逐文件 SHA 与 R0 manifest 对齐。实际引用文件和声明行见 [固定源码核对](evidence/r4/pinned-source-audit.json)。
- **未执行上游 Effect Schema/RPC conformance**：原有工具要求可用 Git checkout 和 Effect 安装，当前临时环境不满足；本轮没有为了测试再安装依赖或伪造 Git SHA。source audit 只证明声明/来源，不等同上游 Schema 执行。

## 本批边界和 R4 下一步

| 矩阵项 | 当前状态 | 还需完成 |
|---|---|---|
| D01 草稿 | 首发/进程内正文与模型隔离已实现未验收 | 多草稿管理、持久恢复、账号切换/删除联动、分享预留目标、孤立项目草稿重定向；当前每环境/项目只有一份进程草稿 |
| D02 环境/分支/worktree/bootstrap | 待实施 | 原环境与分支 picker、checkout 占用、root/existing_worktree/worktree 准备及失败/重试；本批 launch 只用 root |
| D03 provider/模型/选项 | 基础设置已实现未验收 | 原版搜索/分组、cwd catalog、账号/managed 状态反馈的完整入口及运行中变更真验 |
| D04 输入命令/上下文 | 待实施 | slash/skills/@文件、完整 context records、终端/审阅/剪贴板上下文，不用纯文本占位冒充结构化上下文 |
| D05 队列 | 服务端队列基础操作已实现未验收 | 真实运行时 queue/steer、promote-to-steer、完整附件编辑/本地 outbox、崩溃与丢 ACK 真验 |
| D06–D08 | 保留已有停止能力，其余待实施 | fork/resume/guest share、子 Agent/side chat/后台任务、计划确认/用量恢复等原版状态与动作 |
| M01/M03/M04/M05 | 保留原能力并修复必填校验；完整范围未完成 | 完整消息/工具类型与输出流、审批可恢复/继承态、多问题附件/取消、秘密 provider/reference/来源与另端请求状态 |
| A01–A03 | 原单 file 能用于首发，其余待实施 | 多附件、图片/视频、上传取消/逐项重试、预览/保存/分享；内存与格式/服务限额；进程退出需重选 |

验收先在独立测试服务/仓库执行：项目选择/取消无新会话→首发只有一条初始消息→流式/审批→运行中队列与设置→重连快照→已有会话继续发送；核对同 ID 两环境不串、存储拒绝、已过期模型/权限和未知提交。首发明确拒绝/不存在会话的核对退出分支也要专项验证；当前保守保留保护，不能假定失败一定没创建。

随后按原版 B03/B04 页面在相同内容/尺寸/字体下比对，再对授权 Mate60Pro 复核软键盘、sheet、返回、最大字体、读屏与深浅色。**本轮均未执行，不将协议/构建通过算作视觉验收。**

## 第二批：真实隔离服务与设备主链路

第二批使用专用 `ALN-AL80 / 23E0224122000135` 和隔离 T3 0.1.9
`127.0.0.1:47893`（临时 base dir、临时 Git 仓库、临时 worktree）。未操作真实
工作仓库，未重启 `3773`/`47831`，未使用真实业务任务。最终候选
`docs/evidence/r4/batch2-device/r4-batch2-candidate.hap` SHA256
`bfb1d6cb688ae4e6a54eaacc07fab50d63a0c6f2585e5d536038645f28a727d3`。

### 新增实现

- 持久草稿：`DraftStore` 原子 JSON；每草稿独立 UUID，保存文本、模型/模式、
  workspace、附件元数据、结构化 context 和 updatedAt。ProjectPicker 列出草稿，
  可恢复/删除；项目被移除时先回到项目选择并重新绑定；force-stop/relaunch 后
  原文恢复已在专用机验证。账号/环境按 `localId + environmentId` 隔离。
- 环境/分支/worktree：草稿头显示环境与 checkout；读取 `vcs.listRefs`，本地分支
  切换前校验 `source-control:write`；worktree 可选择 base branch 与
  `startFromOrigin`，通过 launch workspaceStrategy 创建。`subscribeWorktreeSetup`
  显示 phase/branch/path/error，并保留 retry/cancel。
- 模型/provider：模型搜索与 provider 分组；provider 状态、安装/刷新/登录入口；
  仍沿用 project override、managed allowedDrivers/maxRuntimeMode、
  supportedRuntimeModes、option descriptor 与 interaction mode 校验。
- 输入上下文：原生 `/` 命令、skill、`@` 文件搜索和结构化 context chips；
  文件引用使用 `mention` record，skill 使用 `skill` record，剪贴板可导入
  `version:1` context fragment。未用纯文本冒充结构化上下文。
- 队列：处理 `run.created`，新排队 run 在首次状态更新前即计数；queue sheet
  显示内容和附件名，提供 edit/cancel/reorder/start/resume/promote 入口。
- 线程投影：读取 `visibleTurnItems`，分叉/Side chat 可显示继承项；工具活动改为
  类型化折叠行，命令输出可展开并拉取完整输出，支持空输出/退出码/文件变更/搜索/
  todo/error/checkpoint/compaction。
- 请求与安全输入：审批使用服务端 options，默认提供允许本次/本会话/拒绝；输入
  支持多问题、多选、custom、required、附件、dismiss；secret 卡支持 URL、file
  delivery、直接值、provider/reference 入口。所有 response marker 改用独立
  command UUID，避免 runtime request ID 超过恢复记录长度。
- 附件/预览：精选多个 file/image，逐项上限与聚合图片上限、取消上传、保留重试
  URI；附件 ID 关联到消息；附件面板使用 `assets.createUrl` 预览图片/视频、
  保存到系统文件、复制预览链接。
- D06–D08：从最新 run fork、Side chat、stop/force stop/resume、plan 渲染/复制/
  保存、token usage、subagents/background tasks、guest share 创建/停止入口。

### 真实回读

- 首发只发送一个 `orchestration.launchThread`；Codex 流式回复、工具活动、
  `CODEX-DONE` 与未在错误分支重发均完成。
- 草稿 force-stop/relaunch 后出现在 Drafts，重新打开保留正文。
- `main` 新 worktree 创建成功，服务端线程回读 branch `t3/a6d686db` 与 worktree
  path；UI phase 为 done。
- 运行时排队成功，composer 显示 `队列 · 1`；队列 sheet 展示等待项和操作。
- Codex 审批卡允许后命令执行、请求状态 `resolved` 且助手返回 `CODEX-DONE`；
  拒绝后服务端 `decision=decline`，命令未执行。
- Side chat 回读 `lineage.sideChat=true`、relationship `fork`。
- 附件 exact-byte 上传返回 HTTP 204；消息投影回读 `r4-test.txt` / 19 bytes /
  `text/plain`，Codex 会话能读取该文件。
- Secret request 卡真实渲染，MCP 工具审批后 secret prompt 出现；但完整提交值
  与 reference 来源仍未完成。

本地 `node --experimental-strip-types --test tests/*.test.mjs`：195/195；
`./scripts/build.sh` 成功。证据索引：
[batch2-device](evidence/r4/batch2-device/README.md)。

### 仍未验收/阻塞

- 队列 edit/cancel/reorder/promote 只有宿主测试和 sheet 渲染；未在真实 queued
  状态下完成服务端编辑/取消回读。
- Codex Default 模式不提供结构化 `request_user_input`；当前 provider 走了纯文本
  回退，M04 的完整真实卡未取得。
- Secret 的 provider/reference 来源和最终提交回读未完成；隔离环境没有配置
  secret provider。
- Guest share 需要真实 T3 Connect 隧道，当前 R2 云配置缺失，只保留入口和错误路径。
- 多附件/图片/视频 picker 和上传进度逐项 UI 未完成；已有消息的图片预览与系统分享已验证，保存到文件路径仍未单独取证；
  exact-byte 关联是通过隔离服务 API 验证。
- 用量限制恢复、历史分页、子 Agent/background 的真实 provider 触发未完成。
- 原版 Android 移动端视觉/交互对照未取得：Pixel 6 模拟器仍被另一设备会话占用，
  未抢占。最大字体、深/浅色和读屏亦未完成。

## 首批回退记录（历史，不适用于后续持久草稿及已安装包）

只恢复本批确实修改的文件，清单见 `evidence/r4/changes.json`；不要整体覆盖其他会话新文件。没有新增磁盘草稿格式或服务端数据写入，无新数据迁移需要回退；R1/R2/R3 原有目录、凭据和恢复记录格式保持不变。候选包尚未安装，不需要设备回退。

## 第三批：提交保护与真实服务补验收

第三批仍使用隔离 T3 0.1.9 `127.0.0.1:47893` 和临时仓库，不操作真实服务或
工作仓库。最终签名候选
`docs/evidence/r4/batch3-service/r4-batch3-candidate.hap` SHA256
`86b950e13afb6ac3b7a48226f8d6d570abf93706b8c4e84148e323f4d003092c`。
该包已用 `hdc install -r` 覆盖安装到专用机。设备物理解锁后已完成模型 sheet、
线程消息、队列 sheet/编辑/移除、secret 卡提交、附件预览/分享和深色的真实
UI 回读；最大字体关怀模式流程、读屏和逐像素对照仍未完成。

### 修复

- 首发保护记录写入失败时在发送前中止并恢复原状态，不再显示“结果未知”；
  明确的首次发送拒绝清除临时线程 marker，保留可重试草稿；成功创建会话后
  先切换线程再做本地草稿清理，清理失败也不会让同一正文再次可发送。
- 附件文件使用 R4 的 50 MiB 上限，图片 10 MiB；取消上传销毁真实 HTTP
  请求；跨会话附件显式拒绝，不再静默丢弃。
- fork 继承项保留 visibility/sourceThreadId；继承的 secret 卡只读，客户端
  拒绝在原线程之外回答；secret URL 仅允许 http(s)，引用需要已配置 provider，
  直接值发送前 trim。
- 运行中隐藏/拒绝 `queued-run.start`，使用立即引导；恢复选择最近一次实际
  执行 run 而非数组末项，只对 interrupted 或 usage-limit failed 提供恢复。
- guest 待处理消息增加发送/忽略入口，发送采用 `queue_after_active`；reasoning
  条目可见；附件面板增加 HarmonyOS 系统分享。
- 已有会话三项设置部分成功时保留已生效项并显示部分结果；草稿恢复校验
  environmentId/localId/projectId，避免跨账号/环境草稿串用。

### 真实服务回读

- 队列：编辑后回读 `QUEUE-EDITED`；重排位置 2/1→1/2；promote 后 queued
  run 结束且消息保留；cancel 移除排队 run/message；start 进入 `starting`；
  held=true 经 `queue.resume` 变为 false；direct steer 的
  `STEER-R4-DIRECT` 已持久化。
- `forceStopThread` 返回 `outcome=released`，无共享线程，run 变
  `interrupted`；interrupted run 的手工 continuation 创建了新 run 并进入
  `starting`。
- secret 直接值保存后助手回复 `SECRET-DIRECT-OK`；文件交付保存后助手读取
  并回复 `SECRET-FILE-OK`；拒绝后回复 `SECRET-DECLINED-ACK`。三例投影/
  证据均不包含 dummy 值。
- 同一消息附带 70 字节 PNG 与 12 MiB file；投影回读精确大小，两个
  `assets.createUrl` 下载均 HTTP 200 且字节数一致。
- 隔离服务开启 beta 后 `guestShare.create` 返回 `connect_unavailable`；
  真实 T3 Connect 隧道缺失，未伪造访客链接。

### 原版视觉

原版 Pixel 6 真机 App 新增发送长按菜单、运行中 `1 queued` 胶囊、`Queued`
sheet、Codex 审批卡和安全输入卡截图，见
[original README](evidence/r4/original/README.md)。这些是同一隔离服务上的
原版真实帧；仍未完成最大字体、深/浅色、读屏和逐像素对齐。

本地测试 208/208，签名构建通过。证据索引：
[batch3-service](evidence/r4/batch3-service/README.md)。
专用机 UI 证据索引：
[batch3-device](evidence/r4/batch3-device/README.md)。

### 仍未验收

- 系统最大字体/关怀模式未完成、读屏、系统 Files 重新选附件、保存到文件和逐像素原版
  对照仍未完成。
- Codex Default 没有结构化 `request_user_input`；M04 完整真实卡仍需具备该
  tool 的 provider。
- isolated 服务的 `secretProviders` 为空，reference 成功路径未执行。
- Guest 链接创建需要真实 T3 Connect；usage-limit 恢复需要真实 provider
  限流；history paging 需要声明 `threadSnapshotPagination` 的版本/长会话。
