# R3 项目、会话与归档进展

日期：2026-11-17。状态：**R3 客户端实现已落地；173 项宿主测试、最终签名构建、专用 Mate60Pro 与隔离真实 T3 0.1.9 服务的一轮功能验收通过。原版 R3 逐页视觉、拖拽手势、运行中归档限制、完整新任务草稿和 provider 实际调用仍未验收，因此 R3 未宣布完整关闭。**

固定上游：`DASungta/t3code` `ad1b1365999c92c3fc7a054e7f3af84623f74fee`。长期归档 `docs/baselines/t3code-ad1b136.tar.gz`，SHA256 `595b64affe9ae78510bbfdcd1cb4f282cade542aa4f8f7c704ea02998321e30a`。本轮未初始化 Git、未提交/发布、未重启现有 `3773`/`47831` 服务；已覆盖安装并操作专用 `23E0224122000135`。

本批开始前备份：

- `docs/evidence/r3/pre-r3-source.tar.gz`，SHA256 `d558b294073e856109ed081b77194c7d7403c6d5645a5c4af9749cf2e7c17ff6`
- `docs/evidence/r3/pre-r3-docs.tar.gz`，SHA256 `dd558fd79d6dd72d6ecba3fb5517171f1963cb1904846517665541a52282ad8c`

最终候选 HAP：`docs/evidence/r3/r3-candidate-signed.hap`，SHA256 `bf9937b56c35c44ed38c0d6112634bc395e59549548a86969d4ef17ea28c6137`。该 HAP 已覆盖安装到 `ALN-AL80 / 23E0224122000135`。证据索引见 [r3 evidence](evidence/r3/README.md)，脱敏设备/服务回读见 `docs/evidence/r3/device/r3-device-verification.json`。

## 已完成

### 协议与本地状态

- 新增 `entry/src/main/ets/protocol/Projects.ts`：项目/会话 shell 严格解析、仓库身份、跨环境 `projectId/threadId` 隔离、项目分组、会话固定/活跃/暂缓/Settled 排序、搜索匹配、Snooze 预设/自定义时间、路径与克隆目标、原版命令构造、session scope 回退和 capability 判定。
- `protocol/Core.ts` 的 `ShellState` 改为保存完整项目/会话 shell 与归档列表；保留旧项目/会话流序列去重和仓库身份 enrichment 不覆盖列表的行为。
- 新增 `services/Workspace.ets`：把项目创建/更新/删除、线程归档/恢复/Settle/暂缓/固定/顺序/重命名/重生成/删除/未读/转项目、克隆/发布、搜索、归档快照收敛到独立 R3 服务，避免继续堆在 `Index.ets`。
- 新增 `services/WorkspacePrefs.ets`：项目分组、环境/项目过滤、会话排序、Working/Snoozed/Settled shelf 展开状态的本机偏好；原子写入与回读校验。
- `services/T3Client.ets` 增加 R3 RPC 与配置投影：`projects.*`、`projectClone.*`、`filesystem.browse`、`server.discoverSourceControl`、`sourceControl.*`、归档快照、会话搜索、线程命令 dispatch、连接代际检查、scope 能力读取和克隆流取消句柄。

### 会话列表与行动作

- 新增 `components/ThreadList.ets`：头部搜索、环境/项目过滤入口、设置入口、固定/活跃/Working/Snoozed/Settled 分区、Settled 分页、搜索摘要、长按/更多菜单、左滑动作。
- 行动作覆盖：Settle/取消 Settle、暂缓/取消暂缓、固定/取消固定、菜单上移/下移（持久化 `pinOrderKey`/`activeOrderKey`）、重命名、受 `threadTitleRegeneration` 门控的重生成、标记未读、受 `threadAutoSettleOptOut` 门控的自动 Settle、归档（运行中按 `threadCanArchive` 限制）、删除确认。
- Settle、暂缓、取消固定提供 5 秒撤销；撤销按原版步骤恢复 unsettle、pin/reorderActive 和未过期 snooze。
- 修改类请求失败不自动重试；连接/超时/服务端拒绝统一提示“结果未确认，请刷新列表核对，不会自动重试”。同一目标同一动作在未完成时拒绝第二次点击。
- 打开会话前执行 `thread.visit`（仅在 `threadVisitedTracking` 可用时），搜索时携带查询用于访问记录。

### 新任务项目选择

- 新增 `components/ProjectPicker.ets`：按仓库/仓库路径/独立分组，环境筛选、项目搜索、固定项目优先、No project、添加项目、返回原会话列表。
- 选择项目后进入现有模型/创建面板；“更换项目”返回同一项目选择器。完整草稿、上下文、模型选项、消息队列仍属 R4，本轮只完成 R3 项目选择/接口衔接，不把“选择项目/模型后立即创建空会话”称为原版完整流程。
- `No project` 通过 `projects.ensureScratch` 创建/打开 scratch 项目，仅在环境的 `scratchWorkspaceRoot` 可用且连接 ready 时显示；跨环境同 ID 通过 `localId` 区分。

### 项目来源与项目概览

- 新增 `components/AddProjectPanel.ets`：
  - 来源页：环境选择、新项目（仅 `newProjectsRoot` 可用）、本地文件夹、Git URL、source-control discovery 发现且 offered 的 provider 行。
  - 新项目：名称、路径预览、可选私有远程仓库发布；`projects.createNew`，等待项目 shell 到达。
  - 本地文件夹：`filesystem.browse` 目录浏览、`~/` 主机 home 解析、已存在路径打开/取消归档、`project.create`。
  - Git URL/provider：`sourceControl.lookupRepository`、克隆目标路径、ghq clone layout、`projectClone.start`、克隆进度订阅、失败/取消/重试。
  - 所有路径先按环境平台和完整路径规则校验；失败不自动重发克隆/创建。
- 新增 `components/ProjectOverviewPanel.ets`：项目分组选择、名称批量更新、固定/归档（受 `projectOrganization` 与所有 checkout 已连接/可操作限制）、checkout 列表、单 checkout/全项目删除确认。
- 新增 `components/ArchivePanel.ets`：`orchestration.getArchivedShellSnapshot` 跨环境归档、环境过滤、项目/标题搜索、最新/最早排序、取消归档、删除确认、左滑恢复/删除。
- 新增 `components/SettingsPanel.ets`：设置入口中的环境、项目、归档会话和项目分组；未添加 R7 全量设置的空行。

### 能力、权限与环境隔离

- 线程动作按服务端 capability 显示/隐藏：`threadSettlement`、`threadSnooze`、`threadPinning`、`threadPinReorder`、`threadActiveReorder`、`threadAutoSettleOptOut`、`threadTitleRegeneration`、`threadProjectFromScratch`、`threadVisitedTracking`。
- 项目固定/归档按 `projectOrganization`；项目/克隆/浏览入口按连接 ready 与 `orchestration:operate`/`filesystem:read`/`source-control:write` 的显式拒绝门控。scope 未知时不删除入口，由服务端最终授权并回显失败，避免因当前账号无权直接删掉原版范围。
- 每个动作使用 `thread.localId`/`project.localId` 取连接；列表状态与动作不共用裸 `projectId/threadId`。打开项目/会话/归档时先切换环境。
- 环境/项目过滤只改变列表范围，不改变当前连接、草稿或附件；打开具体会话/项目选择才切换环境。

## 本地检查

- `node --experimental-strip-types --test tests/*.test.mjs`：**173/173 通过**。最终日志 `docs/evidence/r3/r3-final-tests.log`；保留首轮 `r3-local-tests.log`。
- `./scripts/build.sh`：成功。最终普通签名 HAP `docs/evidence/r3/r3-candidate-signed.hap`，SHA256 `bf9937b56c35c44ed38c0d6112634bc395e59549548a86969d4ef17ea28c6137`。最终日志 `docs/evidence/r3/r3-final-build.log`。
- 新增 R3 测试覆盖：项目跨环境仓库分组/路径分组/独立分组/归档组、scratch 排除、活跃/固定/暂缓/Settled 排序、搜索命中、Snooze 本地时间/重复/过期自定义时间、项目/线程/克隆命令字段、session scope 回退、归档快照分组/过滤/排序、R3 偏好校验、命令失败不自动重试、并发双击拦截、T3Client R3 配置投影、旧连接项目写隔离和自动 Settle 即时可见状态。

## 专用机与真实服务验收

使用专用 `ALN-AL80 / HUAWEI Mate 60 Pro / 23E0224122000135` 和隔离 T3 0.1.9 服务 `127.0.0.1:47891`；仅操作 `$LAB` 下临时项目/仓库，未使用真实工作项目，未停止或重启 `3773`/`47831` 服务，未提交业务任务。

### 已通过

- 项目来源：新建项目写入 `projects.createNew` 并回读项目记录/目录；本地文件夹加入 `project-c`；Git URL 使用 `$LAB` 本地裸仓库克隆成功，HEAD `3fb8c4bf...` 和 `clone-ok` 标记一致；失败后显示“重试克隆”，显式重试发出 `projectClone.retry`；慢连接显示取消控件，取消发出 `projectClone.cancel` 并返回“已请求取消”。
- 项目选择衔接：从项目选择器选择克隆项目后，新任务面板显示对应项目；修复后即使客户端仍保留上一个会话的 `thread`，也不会把新任务项目覆盖成旧 Project A。完整新任务草稿、上下文和首次发送状态机仍按 R4 边界保留。
- 项目概览：Project B 改名后数据库标题回读；Project C 固定/取消固定、归档/取消归档均回读 `pinned_at`/`archived_at`；删除确认先取消保留记录，再确认写入 `deleted_at`。
- 会话管理：Settle 后点击“撤销”回读 `settledOverride=active`/`unsettledAt`；归档 Delta 后归档页出现，取消归档后 `archived_at` 为空；活跃顺序上移写入 `activeOrderKey=n` 且 UI 顺序变化；暂缓 1 小时回读 `snoozedUntil`；自动 Settle 暂停写入 `autoSettleDisabledAt`，恢复后清空。
- 列表与导航：固定/活跃/暂缓/Settled 分区、搜索“Gamma”命中、项目过滤标签显示当前项目、仓库/路径分组切换及本机偏好回读；设置、项目概览、归档页和删除确认的原生返回/关闭流程可用。
- 证据：11 张设备截图、最终测试/构建日志和脱敏服务回读在 `docs/evidence/r3/device/` 与 `docs/evidence/r3/`；截图未包含配对码、token 或消息正文。
- 期间设备触发一次系统“协同升级”重启；恢复并解锁后继续完成最终 HAP 的自动 Settle 即时刷新复核和清理，未操作真实 T3 服务。

### 验收中修复

- `AddProjectPanel` 的项目写操作改由环境注册表按 `localId` 取当前 `T3Client`，避免页面持有重连前的旧 socket。
- source-control discovery 改为显式按钮，切换环境不再自动请求。
- 克隆完成前先观察 `subscribeProjectClones` 的终态；失败/取消停在目标页并显示重试或取消，不再因项目壳先到达而误开新会话。
- 全局 shell 更新不再用残留 `client.thread` 改写新任务 `projectId`；打开已有会话时才同步对应项目。

## 未验收与边界

| 项目 | 状态 | 需要 |
|---|---|---|
| 专用 Mate60Pro 上的 R3 页面与手势 | 部分通过 | 已验收列表/搜索/过滤/分组/长按/左滑/确认/返回与主要深色页面；最大字体、系统深浅色切换、离线/重连全组合未验收 |
| 真实服务写操作 | 部分通过 | 新建、本地目录、克隆成功/失败/重试/取消、项目改名/固定/归档/删除、会话 settle/撤销/归档/恢复/暂缓/排序/自动 Settle 已回读；运行中归档限制、权限拒绝矩阵和真实业务项目未验收 |
| 原版视觉对照 | 未完成 | 按固定 SHA 取得 Settings/Projects/Archive/Add Project/Home 菜单真实运行证据；当前只有源码契约和 ArkUI 实现 |
| 拖拽排序 | 未实现 | 当前提供原版菜单“上移/下移”和服务端 orderKey 持久化；拖拽手势需单独原型和真机视觉验收 |
| 导航位置 | 有差异 | 当前从会话列表搜索行更多入口进入 R3 设置，原版为底部 Settings 导航；全量底部导航/搜索/Settings 属后续导航与 R7 收口 |
| 分支/worktree 写操作 | 未加入 | 新任务分支/worktree 属 R4（D02），文件/Git 操作属 R5（G01）；本轮只显示 branch/worktree 相关信息，不伪造管理入口 |
| 新任务完整草稿 | 未完成 | 当前只完成 R3 项目选择后进入现有模型/创建面板；首次发送才创建草稿、上下文、模型选项和消息队列属 R4 |
| 原版 provider 登录 | 未迁移 | Add Project 只读取 discovery 的可用/未登录提示；账号登录/凭据管理属 R7 |
| provider 发布/重生成 | 未验收 | 私有远程发布与 title regeneration 会触发真实 provider/账号副作用，本轮未执行；保留入口与契约，不宣称成功 |

## 回退

- 代码和文档回退只取 `docs/evidence/r3/pre-r3-source.tar.gz` / `pre-r3-docs.tar.gz` 中对应文件，避免覆盖本批之后其他会话的修改。
- 不删除 `environments-v2.json`、本机 `r3-preferences.json` 或任何服务端项目/会话数据；本轮写测试只存在于 `/tmp/t3-r3-accept-WuIFKn` 隔离服务。
- 最终普通 HAP 已覆盖安装。验收后撤销隔离服务 8 个测试会话、最后 1 个配对码、删除 8 个临时凭据文件、移除设备上的 47891 环境并停止 47891；`tcp:3773`、`tcp:47831` reverse 和 R1 的两个环境保留。见 `docs/evidence/r3/device/r3-cleanup.json`。
