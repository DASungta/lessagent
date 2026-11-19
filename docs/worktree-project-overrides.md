# S09 项目级工作树覆盖

依据固定上游 `ad1b136` 和 [R7 验收清单](r6-r8-acceptance.md)。此页记录源码契约，真机结果见各批验收记录。

## 已支持

- B27 已接入下表前五项的项目读取、写入和恢复继承；远程起点覆盖、隔离、草稿消费和恢复已通过真机服务回读。[B27](evidence/r8/batch27/README.md)

- 鸿蒙「设置 → 工作树」支持环境级远程起点、子模块和分支命名。B2 验证子模块写入并恢复，B22 验证命名模式和前缀写入并恢复。 [B2](evidence/r8/batch2/README.md) · [B22](evidence/r8/batch22/README.md)
- 「工作树存储」支持环境级目录和六项自动清理规则。B23 验证目录写入及恢复、权限重连和大字确认框的取消分支。B23 没有执行实际清理或创建工作树。 [B23](evidence/r8/batch23/README.md)
- `resolveDraftDefaults` 已读取服务端预存的项目级远程起点，为新草稿填充 `startFromOrigin`。恢复的草稿仍用已保存参数。草稿显式切换本地与新工作树时保留解析值或用户选择。选择具体远端分支会使用远端起点。 [DraftDefaults.ts](../entry/src/main/ets/protocol/DraftDefaults.ts) · [Index.ets](../entry/src/main/ets/pages/Index.ets)

## 入口和优先级

上游移动端从「Settings → Worktrees」进入，通过环境和项目筛选选择已连接的 checkout，展示生效值和项目覆盖状态，并可清除此页覆盖。移动端该页只管理下表前五项。项目清理由桌面 Storage 的项目或 checkout 视图管理。鸿蒙现已提供移动端五项配置的项目入口，选定一个精确的 `(environmentId, projectId)`；同名仓库或聚合分组不能代替项目 ID。多 checkout 广播属于后续范围。

| 字段 | 项目值及生效顺序 |
| --- | --- |
| `newWorktreesStartFromOrigin` | 布尔值。新草稿读取项目覆盖，再读取环境默认。用户在创建时明确选择的工作区起点优先。服务端 launch 根据请求的 `startFromOrigin` 执行。 |
| `worktreeSubmodules` | `recursive`、`top-level`、`none`。单次创建选项优先，其次是项目覆盖、环境配置。环境值为 `null` 时读新检出的 `t3.json`，缺失时递归初始化。项目字段省略即继承；项目页的「继承」应移除该键。 |
| `branchNamingMode` | `static`、`semantic`、`custom`。项目覆盖优先于环境模式。用户明确指定的分支走单独的分支启动路径。 |
| `branchNamePrefix`、`branchNameInstructions` | 各自独立继承；分别由固定前缀和自定义模式消费。两项只去除首尾空白。隐藏字段保留值；空前缀是显式值，移除键才恢复继承。 |
| `worktreeCleanup` | 项目字段省略时继承环境有效清理策略。项目 `off` 关闭五项删除触发；`custom` 是完整规则快照，覆盖环境规则。进入 `custom` 时先从当前有效规则补齐整个对象，然后改目标字段。 |
| `worktreesDirectory` | 仅环境级；Git 服务直接读取环境的根目录。创建时仍由宿主机验证目录。 |

清理自定义快照包含 `worktreeKeepWhen`、`worktreeAfterDays`、`worktreeSettledAfterDays`、`worktreeOnMerge`、`worktreeOnDelete`、`worktreeUnchanged`。闲置天数是整数 1–3650 或 `null`，归整天数是整数 0–3650 或 `null`，0 表示下次清理时检查。项目清理需 `projectWorktreeCleanup` 和 `storageCleanup`，归整天数和本地文件保护分别按 `settledWorktreeCleanup`、`storageCleanupRun` 门控。

上游可核对 `apps/mobile/src/features/settings/SettingsRouteScreen.tsx:311`、`SettingsServerControlsRouteScreen.tsx:58–77,177–225,287–315,467–527`、`apps/web/src/components/settings/StorageSettings.tsx:548–649`、`scopedSettings.ts:315–334`、`packages/contracts/src/settings.ts:1135–1169,1172–1246,1253–1268`、`packages/shared/src/projectSettings.ts:95–119,165–167,218–256`、`apps/server/src/orchestration-v2/ThreadLaunchService.ts:402,547–621`、`apps/server/src/git/GitManager.ts:826–853` 及 `apps/server/src/vcs/GitVcsDriverCore.ts:5280–5304`。

## 写入、冲突和确认

1. 在当前连接通过 `server.getConfig` 读取环境身份、`settings.projectSettingsOverrides` 和 `managedPolicy`，要求 `orchestration:read`；项目编辑额外要求 `environment.capabilities.projectSettingsOverrides === true`、明确授予 `settings:write`，且 checkout 仍在同一已连接环境。项目切换、退后台或连接代次变化后拒绝旧请求。
2. 调用 `server.updateSettings`，payload 形如 `{patch:{projectSettingsOverrides:{[projectId]: nextEntry}}}`。项目条目对已知字段是**整条替换**，因此应从写前新读的条目复制未改字段，仅替换或删除目标键。服务器保留同项目既有未知键，并特殊保留省略的 `providerInstances`。其他项目条目保持原样。清除此页只删对应键，整个条目确实为空才发送 `[projectId]: null`；看不全条目时避免整条删除。项目条目标识和其他配置值只留在运行内存，不写进测试日志。
3. 检查 `managedPolicy.lockedSettings` 的父子路径。设置键的锁同样约束对应项目覆盖；还要核对 `projectSettingsOverrides`、项目条目路径及目标字段路径。清理按 `worktreeCleanup` 锁处理。服务端 `vetWrite` 同时检查直接提交及合并变化，整条重发时即使只改一个字段，也可能因携带被锁字段而拒绝；保留原数据并提示刷新，不能为绕过拒绝而丢掉兄弟字段。
4. 客户端按同一环境／项目串行写入，保存前对比用户打开时看到的项目条目和最新条目，发现冲突时刷新后重选。上游 RPC 不含版本号或 compare-and-swap，最后一次读与写之间仍可能发生其他客户端覆盖。写后核对同一项目的原始覆盖、有效值、未改字段与来源；超时或结果不符提示核对，避免自动重发。
5. 加强清理需要明确确认，例如开启触发、缩短天数、降低文件保护，或从 `off` 恢复继承并重新启用环境规则。用最新有效规则计算变化。保存后服务可按规则删除符合条件的工作树以及未受保护的本地文件，包含可能存在的未跟踪文件和 `.env`。清理本身保留 Git 分支与会话历史。禁用项目自动清理不触发删除，恢复继承仍需重新比较有效策略。

写入证据见上游 `apps/mobile/src/features/settings/settings-scoped-server.ts:40–102,115–133`、`packages/contracts/src/settings.ts:1876–1888`、`packages/shared/src/serverSettings.ts:273–294,591–602`、`apps/server/src/auth/RpcAuthorization.ts`（`serverGetConfig`、`serverUpdateSettings`）、`apps/server/src/policy/managedSettings.ts:198–209,413–434`、`apps/server/src/storageCleanup.ts:852–880,1171,1244–1285`。

## 隔离服务最小端到端验证

- 在独立服务用两个临时 checkout。先读回两项目条目与环境默认值，仅留待验收字段。项目 A 写入与全局不同的远程起点及固定分支前缀；项目 B 保持继承。回读 A 的原始覆盖和有效值，确认 B、环境默认与无关字段保持原值。用两个新草稿及一个已有草稿验证默认和保留行为，区分从一开始创建工作树草稿和从本地切换工作区的两条路径。
- 加一份无业务数据的 Git 夹具，包含本地分支和追踪远端的不同提交。仅在 A 发起一次隔离任务，检查实际工作树基准提交与生成分支；要证明子模块实际行为，可用本地测试仓库和嵌套子模块分别验证 `none` 与继承。回读设置本身无法证明已创建工作树的行为。
- 项目清理第一轮使用无候选临时项目，仅验证 `off` 或全关闭的 `custom` 和恢复继承、组织锁与只读连接。只有在另外安排的可丢弃工作树测试中才验证删除效果。回读确认恢复原始项目条目、环境规则和其他项目。该轮不改变已存在的真实工作树或启用删除触发。
- 真机对比上游原版同一入口、项目作用域、回读和继承显示。单 checkout 通过与全环境／多 checkout、实际清理及占用矩阵是不同验收项。
