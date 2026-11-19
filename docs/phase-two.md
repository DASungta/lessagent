# 第二阶段：核心客户端

> 历史记录：下文状态属于当时批次，不代表当前进度。当前以 [整体进度](development-status.md) 和 [完整迁移计划](full-mobile-migration-plan.md) 为准。

日期：2026-11-16。状态：核心功能已实现，阶段二主业务闭环真机验收通过。拒绝审批、多选/多问题等交互变体仍待专项覆盖。脱敏结果见 [Mate 60 Pro 证据](evidence/phase-two-mate60pro.json)。阶段三未开始。

## 本轮实现

- 沿用单模块 ArkTS/ArkUI，没有新增运行依赖。`Wire.ts` 管理 RPC、历史、流式消息与请求状态，`Core.ts` 管理 shell 列表、模型、交互卡片和基础 Markdown。
- 服务地址及有效 Bearer 会话保存到系统 Asset Store，绑定根地址、environmentId 和 expiresAt。仅解锁时可读取；无明文凭据回退、无配对凭据/ticket 持久化，密码框禁用自动填充。支持删除本机连接。
- 已核实上游 token 交换结果无 refresh token。有效期内重新获取 ticket 并复核服务器身份，过期/失效需重新配对。首版保存一个服务器；一条 Asset 的 JSON 超过 1024 字节明确拒绝保存，不降级明文。
- `server.getConfig.providers` 提供 Provider/模型选择，排除明确禁用或未安装 Provider；`subscribeShell` 提供项目和活动会话列表；支持在选择的项目和模型下创建审批模式会话。
- 切换会话通过 RPC Interrupt 取消旧订阅，再加载完整快照；没有修改类请求自动重发。草稿按服务地址/会话隔离，仅本次应用内保留，杀进程后不保留。
- 历史与实时/最终消息按 messageId 合并；工具区显示类型、状态、命令和随流提供的输出。仍用内容键重建变化行，长历史和局部渲染留待阶段三。
- 审批卡片提供允许本次/拒绝本次；输入卡片支持多问题、选项、自定义值、必填、多选和不可恢复状态，使用 `runtime-request.respond`；不提供永久授权。
- `secret_request` 使用密码输入及专用 `secrets.answerRequest`，不进入普通消息、草稿、剪贴板或应用日志。提交前清除界面值，离开卡片清除输入。敏感值不在失败时恢复；需重新同步再决定是否提交。卡片提交后禁用，等待服务端更新。
- 停止任务使用 `thread.stop`。未知提交保留本次进程内的 messageId；先同步快照，已接收则清除对应草稿，未找到则提示核对后手动重试。进程退出后的未知结果跟踪属于阶段三。
- 基础 Markdown 支持按行段落、标题、保留列表文本、引用和 fenced code；原生代码块及复制。内联强调、可点击链接、表格、语法高亮和完整 CommonMark 未实现，内容仍以文本展示。

## 契约、环境与验证

- 固定调研上游仍为 `ad1b1365999c92c3fc7a054e7f3af84623f74fee`；运行服务为原有 T3 0.1.9 / 协议 2 / 3773，未核实其运行构建 Git SHA。
- 已核对 `subscribeShell`、`subscribeThread`、`getThreadProjection`、`dispatchCommand`、`runtime-request.respond`、`thread.stop`、`secrets.answerRequest` 和权限映射。客户端只申请 orchestration:read / orchestration:operate；只读观察凭据仅 orchestration:read。
- 自动验证：30 项测试通过；Wire/Core 严格类型检查通过；固定上游 Schema（新增审批、回答、停止、敏感输入、shell 参数）及真实 Effect 4.1.3 内存 RPC 检查通过；签名 HAP 构建通过。
- 专用目标重新核实为 Mate 60 Pro / ALN-AL80 / API 26。最初安装成功但锁屏禁止启动，用户手动解锁后继续，无系统保护绕过。复用现有 HDC reverse；未修改 T3 服务监听、协议、其他会话或签名配置。

复查命令：

```sh
./scripts/build.sh
node --experimental-strip-types --test tests/*.test.mjs
T3_SOURCE=/tmp/t3code-harmony-upstream node --experimental-strip-types tests/upstream-conformance.mjs
```

## 真机记录

- 从原生项目/模型列表在当前项目中新建独立 `Harmony 新会话`，没有手工填 ID。
- 手机提出修改 `/tmp/t3-harmony-phase2-task.cjs` 的指令；分别批准读取、修改、Node assert 三次命令请求。服务端三条请求均为 resolved / accept，三条命令均退出 0，实际文件由减法修为加法。
- 最终 `HARMONY_PHASE2_EDIT_OK` 及代码块在手机逐行与服务端记录匹配，标记只显示一次。
- 覆盖安装、进程重启后留空配对凭据，成功使用系统 Asset Store 会话重新连接，打开原会话恢复历史。
- 修复身份补充 snapshot 后原生列表保持完整，重新选择原测试会话成功。
- 原会话继续追问，服务端观察到 streaming，手机出现“assistant · 回复中”，最终 624 字回复已生成；逐行比对结果见证据。
- 复制代码块并粘贴到输入框，内容一致。
- `request_secret` 工具本身的 MCP 调用授权也由手机审批。第二次由自动化填写随机测试占位值，通过 `secrets.answerRequest` 提交后状态 saved；从服务端完整会话投影中确认占位值不存在。填写期间没有执行 UI dump，也没有把占位值写到辅助文件。首次卡片也记录为 saved，不读取其值。
- 手机停止本次专用会话的长回复，服务端运行状态 interrupted。初次闭环共五条测试用户消息，后加两次普通输入检查，最终七条消息与七个唯一 messageId；没有自动重发。
- 仅将专用测试会话临时设为 plan 以触发真实 request_user_input，再恢复 default。自动化在手机选择 Blue 并点击提交，服务端收到 `auto_color: Blue`，最终回复与手机比对见证据。多问题、多选、自定义回答和拒绝审批仍仅有自动检查或未作真机专项。
- 首轮颜色请求与首轮敏感卡片在自动化提交前已完成，用户确认不是其手动操作；不推断完成来源，也不把它们算作手机人工操作证据。后续两项验收采用明确的自动化点击/提交与服务端回读。
- 草稿断开/重连保留通过。相同根地址的表单重建不再清空草稿；新建会话前先保存旧会话草稿，避免分配新 ID 时串会话。

## 真机发现的修复

重连后会话列表一度消失。真实服务除完整 shell snapshot 外，还发送带 `resolvedRepositoryIdentityRoots` 的仓库身份补充 snapshot，其中 threads 为空。上游 `ShellStream.ts` 与 `shellReducer.ts` 确认这种 snapshot 只补充身份信息，不能替换列表。当前列表不展示仓库身份，故忽略这类补充帧；补了回归测试，并保留完整 snapshot 的替换语义。归档集合的 removed 事件也不再删除活动集合的会话。

## 清理与交付

本次只在专用测试会话修改临时文件、切换交互模式和停止其运行；未重启 T3 服务、改变监听/协议或操作其他会话。验收后删除本机测试连接，撤销本轮唯一标签下的配对和会话，并回读活跃列表；结果见脱敏证据。临时凭据和原始投影文件删除，测试文件删除。最终签名包已覆盖安装。

## 尚未验证的范围

单选输入、敏感输入、停止及代码复制均按上述真实操作记录验收；拒绝审批、多问题、多选、自定义回答、不可恢复请求和凭据过期等边界的真机专项未全部覆盖。本地模拟测试不能替代这些证据。

公网 HTTPS、蜂窝切网、锁屏任务恢复、服务端重启、大历史性能、进程退出后的未知结果恢复均未验证；本轮没有扩展到阶段三。
