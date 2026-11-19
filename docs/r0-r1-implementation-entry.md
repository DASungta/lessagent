# R0 → R1 实施入口与存储迁移设计

本轮只设计到可执行拆分，没有修改应用业务代码。以 [能力矩阵](r0-mobile-capability-matrix.md) 的 C01–C05 和 [完整迁移计划](full-mobile-migration-plan.md) 为边界；R2 仍是完整连接目标。原版页面取证阻塞未解除前，不把 UI 流程自行补成产品设计。

## 现有代码约束与必须触达的位置

- `protocol/Core.ts`：SavedSession={base,environmentId,token,expiresAt}，RecoveryState={base,environmentId,threadId,pendingId,pendingKind}，有效 pendingKind 为 message/create/stop/response/secret。未知标记是业务事实，迁移不能清空。
- `storage/SessionStore.ets`：Asset alias `t3-harmony-session-v1`，恢复 alias 在 `entryability/EntryAbility.ets` 设为 `t3-harmony-recovery-v1`。每条序列化后最多 1024 字节，仅解锁可读，无明文回退；存储 query JSON 目前没有目录级 schema 验证。
- `services/T3Client.ets`：网络/授权/恢复及状态现在是单例；需要环境实例隔离，不能覆盖一个 base 假装切环境。保留每次修改前持久 pending、防双击、无 ACK 不重发。
- `pages/Index.ets`、`EntryAbility.ets`：当前单例状态、生命周期绑定和 sheet 入口需统一改；`components/MessageSource.ets/RequestCard.ets` 需要明确来自哪个实例；`AttachmentPicker.ets` 已有 base/environment/thread 检查，不得移除。
- 测试触达 `core/native-client/storage/attachment-picker/ui-state`；fixtures 需要两个环境相同 projectId/threadId 的碰撞数据、过期会话及损坏/锁屏存储。Wire 编解码尽量不改；相关导出/构造调用需全局 rg 后一起调整，不增加通用连接插件框架。

## 数据作用域（拟议 v2，非已写入格式）

| 数据 | 键/内容 | 存储与边界 |
|---|---|---|
| EnvironmentDirectory | schemaVersion=2、generation、entries[{localId,environmentId,base,label,enabled,kind,accountId?,credentialRef}]、selectedLocalId | 应用私有文件，临时文件写完校验后同文件系统 rename；不含 token/code/ticket/签名 URL。label/base 可能含私有拓扑，不导出到普通日志 |
| 身份 | localId 为安装内稳定随机 ID；environmentId 是服务返回身份；cloud 另含 accountId | 去重按已验证 environmentId+transport/account 语义；添加相同服务不无声覆盖凭据；地址变化重新验证身份 |
| 凭据 | 每 localId 独立 Asset alias、base/env/expiresAt/token；云 key/token 独立账号/安装范围 | 目录只留 alias 引用；每条 ≤1024；超限明确失败并保留旧数据，不随意切明文或分片丢原子性 |
| 恢复与未知提交 | localId+threadId 下原 RecoveryState；包括 pending create 的 thread 未定状态 | 每环境独立受保护记录；同环境存在多线程未知提交时每线程独立，不能只留 selectedThread 一条 |
| 会话/项目/列表/订阅/请求 ID | localId+environmentId+entityId；请求归连接实例 | 回包必须匹配实例 generation，切换后旧回包不能写到新页面；读订阅取消不取消服务端任务 |
| 草稿/队列 | localId+projectId+draftId 或 threadId，cloud 再绑定 accountId | R1 先保证现有进程草稿不串；完整持久草稿/队列 R4，不能把 R1 宣称其已完成 |
| 附件/签名链接 | localId+threadId/draftId+selection generation | URI/上传能力仅进程内，环境切换不复用；pending 服务文件依上游过期机制，删除本地引用不删除已发送附件 |
| 全局偏好 | theme/locale/导航/键盘等 | 仅原版本地作用域可共享；provider/project/managed settings 均环境或项目范围，禁止全局覆盖 |

不把整个目录塞入单 Asset。目录持久化不能包含待发送正文/秘密，不引入数据库只是为了两条环境；后续草稿需求再按现有持久层扩展。

## 旧数据迁移与回退

1. 启动先读 v2 目录并严格校验版本、URL/ID/引用；不存在才检查 v1。Asset 锁屏/不可读不是“无记录”，不以空目录覆盖。
2. v1 session 校验 base/env/expiresAt，过期也保留为需重新配对的环境，不能丢其恢复/未知状态。v1 recovery 必须匹配 base/env；不匹配或损坏时隔离为待人工核对，不附给新环境、不删除、不发请求。
3. 生成 localId 和迁移 generation，先分别写 v2 Asset 凭据及恢复记录，再回读精确比较（只记布尔结果，不记录内容）；任何一步失败撤销本批新引用并保留 v1。
4. 写临时目录，校验引用均可读后原子替换目录；目录 commit 是迁移生效点。崩溃在之前只留下不可见新记录，重试必须按迁移标识幂等处理，不能重复迁入目录。
5. 重启确认 v2 完整；迁移收据只含版本/状态/generation，**首批不自动删除 v1**。回退构建只在尚未发生 v2 凭据/恢复变更时可安全读 v1；一旦 v2 有新提交/撤销/换号，旧版会看到陈旧事实，不允许直接退包继续操作。
6. 删除/撤销任一迁入环境时，清理对应 v1 alias 或记录兼容墓碑防止重新迁入。目录先标记 deleting 并停止网络/禁止提交，清理凭据/恢复/缓存后提交删除；中断可继续清理，不能复活旧凭据。存在未知提交时需用户先核对服务结果，删除本地不表示取消任务。
7. 后续明确清理旧 alias 的版本须在升级/崩溃/删除/回退测试全通过后单独交付；不以“迁移成功”掩盖回退限制。

## R1 可直接执行的顺序

| 子项 | 最小交付 | 检查与完成门槛 |
|---|---|---|
| R1.1 | URL/配对纯解析与目录 schema，先搬上游规则及测试向量 | IP/IPv6/域名/tailnet/hash/query/托管/t3code 包装、坏输入；解析不触发连接；明确 LAN HTTP 策略且保持 TLS 校验/禁重定向 |
| R1.2 | 目录+独立凭据/恢复 store+v1 迁移（无新 UI） | 写失败/回读失败/各步 crash、锁屏、过期、不匹配、删除/升级回退，全程无未知标记丢失 |
| R1.3 | 每环境连接实例和页面选择绑定，复用已有 T3Client 防重发 | A/B 同 entity ID、订阅 generation、同时存在/独立重连/禁用一个，旧回包和附件不串 |
| R1.4 | 按原版 Connections/ConnectionsNew/SettingsEnvironmentNew 翻译入口 | B01 真实对照；启停/编辑/重试/移除、空/错误/权限/禁用完整；先修连接，不顺带改新任务完整业务 |
| R1.5 | 鸿蒙扫码/深链与冷启动暂存；原生权限/扫码生命周期 | 独立测试码、相机拒绝/永久拒绝、focus/background 停止扫描、成功只填一次；恶意链接不自动授权 |
| R1.6 | 两环境真实验收+升级安装验证+证据归档 | 专用设备复核、独立服务/凭据、手动/扫码各一套，切换/断网/重启/移除/过期；读回服务状态且不提交真实任务 |

每子项先完成本地和隔离检查再上专用 Mate 60 Pro；任何需要用户独有秘密通过 request_secret。签名/安装/服务变更只在具体测试条件和授权范围内执行，不增加当前真实服务权限。原 R0 会话未授权 R1 全量实施的边界已由本会话用户明确更新：继续完成 R1，每个环节均须真机验收；不扩展为 R2 云功能或 R3/R4 业务改造。

## 风险与批次门槛

- R0 退出：89 注册路由可追溯、动态隐藏入口人工运行核对、B01–B10 原版真实记录、四项关键依赖至少有可运行原型或明确可解除阻塞；当前后三项尚未全满足。
- R1 退出：C01–C05 与迁移/多环境隔离真验；C06–C10 留 R2 不得删除。没有合法第二环境时只能记已实现未验收。
- R2 退出：真云身份/DPoP/中继/续期/撤销闭环；鸿蒙客户端注册或服务端推送通道缺失是外部阻塞，不由 UI mock 关闭。
- 后续严格 R3→R4→R5→R6→R7→R8；原版新任务流程在 R4 校正，不能继续把当前空会话创建当完整原版流程。终端/预览可行性若需协议或 native 库移植，单独估算，不虚报整项目工期。
