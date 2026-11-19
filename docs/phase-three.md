# 第三阶段：恢复与原生体验

> 历史记录：下文状态属于当时批次，不代表当前进度。当前以 [整体进度](development-status.md) 和 [完整迁移计划](full-mobile-migration-plan.md) 为准。

日期：2026-11-16。状态：**已实施恢复、防重发、列表及原生适配、单文件上传；专项验收仍进行中，M2 尚未宣布完成**。真机与自动检查的边界见 [脱敏证据](evidence/phase-three-mate60pro.json)。没有初始化 Git、发布、增加依赖、修改签名配置或重启现有 T3 服务。

## 恢复和防重发

- 复用 Asset Store，同一存储实现使用独立 alias 保存恢复元数据；与 Bearer 会话分开，均仅解锁可读、最大 1024 字节、无明文回退。恢复记录只含 base、environmentId、threadId、pendingKind、pendingId，不含指令正文、普通回答、敏感值、附件路径或签名 URL。
- 先持久保存当前会话，才开始订阅。新建、发送、停止、审批/回答及敏感输入在出站前先保存未知结果标记；写入失败不会发送。提交中及未知状态禁止新的修改请求，双击只有一次出站。收到确认后清除标记；清除失败保留保护。
- 进程启动使用有效安全会话恢复选中的 thread；前后台释放连接和重新订阅。仅前台对读取连接按 1–30 秒退避重试，用户主动断开取消重连。到期/鉴权/身份失败需人工处理，不交换旧配对凭据。
- 每次重连采用完整服务端快照作为补齐和回退路径，不复用丢失的内存投影，也不猜测全局 sequence 的跳号是本会话事件丢失。事件以 sequence 忽略重复/旧事件，消息以 messageId 合并，活跃订阅拒绝更旧快照；新订阅允许服务重启后的新游标。
- 快照对照 messageId，找到则提示已接收；未找到仍不能推断未执行。保留未知标记，需用户打开原会话核对并点击“已核对上次提交结果”，才允许手动新提交。未核实 commandId 幂等，不自动重发任何修改请求。
- 后台清空卡片普通/敏感回答。草稿仍仅保留于页面进程；杀进程不保存草稿。连接删除清理凭据、恢复记录、页面草稿、附件选择与显示缓存。

## 列表和原生行为

- 原 Scroll/整列 ForEach 改为 List + LazyForEach，缓存两行，MessageSource 只通知增加/变化行；消息内容键确保最终文字重建，避免阶段一发现的 ID 键旧文字问题。
- 50 ms 合并流式 UI 通知；输入区独立固定在列表外。消息变化不主动滚动，提供“查看最新”；断线保留当前已显示正文，连接状态标明离线，完整快照更新后继续显示。滚动位置仅进程内，不持久化到重启后。
- 键盘使用 SDK 的 RESIZE 避让，原生文本选择/复制保留，系统主题色替代硬编码卡片背景；字体保持系统缩放，附件按钮可换行，状态有无障碍文字。
- 历史展示附件文件名，不缓存本地路径/签名 URL。附件预览、下载及代码/Diff 审阅不在本轮扩大。
- 当前懒加载覆盖原生 UI；服务端仍获取完整快照，未启用 bounded snapshot、opaque historyCursor 或服务端分页。2000 条数据通知有自动测试，不能据此宣称真机千条历史性能通过。超长单消息仍按原块 Markdown 构建，其分段优化留待性能专项。

## 附件契约及边界

先核对固定上游 contracts/assets.ts、chatAttachment.ts、client-runtime/state/attachments.ts、服务端 AttachmentUpload.ts、http.ts 和 RpcAuthorization.ts，再使用本轮独立凭据验证真实响应。

- `attachments.createUploadUrl` 需要 orchestration:operate；本轮只读观察凭据调用被拒绝。申请参数：type=file、name、mimeType=application/octet-stream、sizeBytes。
- 服务返回 attachmentId、relativeUrl、expiresAt；严格限制签名地址为当前 base 下 `/api/attachments/upload/<token>`，拒绝外站、查询串、路径穿越、过期和无效 ID。不向上传地址发送 Bearer，不跟随重定向，保留系统 TLS 校验。
- POST 精确文件字节；实际成功是 **HTTP 204、空正文**，不能按 JSON 响应猜协议。消息显式发送时引用 `{type,id,name,mimeType,sizeBytes}`。
- 使用系统 DocumentViewPicker，应用只获得所选文件权限；读后总会关闭 fd，短读循环补齐。客户端首版单文件、1 字节至 10 MiB；上游 file 上限 50 MiB，本轮主动收窄以限制内存峰值。文件按普通文档处理，未提供图片专用预览。
- 失败保留当前进程中的选择 URI，供用户手动重试；按 base/environmentId/threadId 隔离，切服/切会话禁止复用。进程退出需重选，不在磁盘保存文件副本或上传能力。成功上传不代表消息已发送。
- 未发送或失败上传形成的 pending 文件由上游过期清扫处理；不自动重传或重发消息。“移除附件”清除本机引用，不删除已经归属服务端消息的附件。

## 自动检查

```sh
./scripts/build.sh
node --experimental-strip-types --test tests/*.test.mjs
T3_SOURCE=/tmp/t3code-harmony-upstream node --experimental-strip-types tests/upstream-conformance.mjs
node /Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/bin/tsc --strict --noEmit --target ES2022 --module ES2022 --lib ES2022,DOM entry/src/main/ets/protocol/Wire.ts entry/src/main/ets/protocol/Core.ts
```

43 项本地测试通过；Wire/Core 严格检查、固定上游 Schema/Effect 4.1.3 序列化 RPC、签名 HAP 构建通过。新增覆盖持久未知状态与新客户端实例、写入失败不发送、双击、后台恢复、身份隔离、独立 Asset alias、2000 行局部通知、附件能力校验/失败/精确字节、短读关闭和文件选择隔离。上游校验增加文件消息和上传入参。SDK 对文件 API 报告可抛异常提示，调用在 try/finally 与页面 catch 内处理。

## 真机实际路径

专用 HDC 目标重新核实为 Mate 60 Pro / ALN-AL80 / OpenHarmony-7.0.0.111 / API 26；仅自动操作本应用、其系统文件选择器和本轮下载测试文件。客户端仍为 0.1.0 / compatible-target API 24，服务仍为原 T3 0.1.9 / 协议 2 / 3773，运行 Git SHA 未核实。

- 本轮新标签、最小权限配对及只读观察凭据；原生选择项目新建独立会话，所有 Agent 测试都在该会话，未委派子代理。
- 覆盖安装和 force-stop 后留空配对凭据，自动恢复原会话；未手填 threadId。
- 生成 120 行回复时移除本机指定设备的 USB reverse，手机断线，服务端继续并完成；恢复 reverse 后自动完整快照同步。逐次滚动，120 行及结束标记共 121 行与服务端一致。
- 锁屏期间提交的任务继续完成；真实启动遭 10106102 拒绝。用户明确回复已经手动解锁后重新启动应用，自动回原会话；100 行及结束标记共 101 行逐行一致。期间未关闭开发者模式或绕过系统保护。
- 系统选择器明确选中本轮创建的 harmony-phase3.txt，上传后由手机发送；服务端确认一个 29 字节 file 附件。指令要求不调用工具，Agent 未读取文件内容，因此只计附件传输，不计模型读取内容验收。
- 第二次选同一测试文件，在完成选择前移除 reverse；连接恢复后手动“重试上传”成功，再移除本机附件。失败及重试均没有自动新增用户消息。
- 最终包再次覆盖安装，附件历史名称可见。最后一轮提交后立即输入未发送草稿并滚动，输入保持启用；160 行及结束标记共 161 行最终回复逐行可见比对一致。服务端为 6 条用户指令、6 个唯一 messageId，草稿不在服务端。观察器未捕获本轮 streaming 中间帧，所以只计提交后输入/滚动与最终文本，不计快速流式性能通过。

## 未测和交付限制

公网 HTTPS、真实蜂窝/Wi-Fi 切换、隔离服务重启、千条历史真机延迟、系统最大字体及屏幕朗读/深浅色专项、快速流式输入性能尚未验收。锁屏结果仅覆盖 USB 回环路径，不能外推为蜂窝或公网锁屏恢复。进程退出时丢 ACK 的恢复由实际客户端适配层模拟存储/网络测试覆盖，未注入真实服务 ACK 丢失故障。安全条件不足，不重启现有服务来补验。

服务端分页、进程退出后滚动位置/草稿/附件续传、多附件及图片专用体验均未实现；不因此提前进入阶段四/五。M2 需要上述影响日常使用的性能与原生专项验证后再判断。

## 清理

最终签名包已覆盖安装。手机删除本机连接并 force-stop/重启后确认地址为空、会话不再显示；本轮 3 个临时会话凭据撤销，活跃会话及配对回读均为 0（配对已交换消耗）。本轮下载测试文件已删除，原始凭据、投影、UI 布局和辅助脚本目录已移除。已发送测试附件归属本轮服务端测试会话，保留该会话作为联调记录；未发送 pending 上传按服务端过期清扫处理。USB reverse 恢复到原有 3773→3773，未动其他设备或会话。
