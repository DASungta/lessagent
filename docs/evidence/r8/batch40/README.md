# 上游同步第 1+2 批（C1–C5、U1–U4）与 P0 真机验收 · batch40

2026-11-23。在专用 Mate60Pro（`23E0224122000135`，`com.dasungta.t3code.harmony`）上以 `hdc install -r` 覆盖安装，未卸载应用、未清数据，未触碰宿主机用户正在运行的主 T3 Code 服务（`http://192.168.10.75:3773`）。

## 构建与单测

- 宿主单测：`651/651` → **`672/672`** 全量通过（`node --test tests/*.test.mjs`）。
- 签名 debug HAP 构建通过（`> hvigor BUILD SUCCESSFUL in 19 s 108 ms`），最终交付包 SHA-256 为 `7f48b6efb929d83a14ef9ccf32e909e783d3ab91fc3fbc5664e16d4643647939`（对应 commit `1d22911`，含真机验收期间发现并修复的 U2 折叠遮罩灰带与展开按钮宽度溢出修复；首轮全量构建 `f010d5e` SHA-256 为 `96666b3a2898708a8943e37d05fe38d52be038b0b63ca6c9f6e2af4cd318b126`）。[检验日志](checks.txt)

## 隔离服务端

使用本机已安装的 `t3` CLI（`0.1.12-nightly.20261122.5098`，对应上游 `620cf4770d`，具备 `accessTokenRenewal`、`scheduledTaskThreadModes`、`threadRestartContinuation` 等全部能力），搭配独立数据目录 `/tmp/t3-harmony-b40-home`、独立测试仓库 `/tmp/t3-harmony-b40-repo`（默认分支 `develop`，当前检出 `feature-demo`，含 5 个工作区改动文件）及独立端口 `14873`（D2 续期与 D4 断线重放阶段由本机透明代理 `0.0.0.0:14873 -> 127.0.0.1:14874` 做一次性 401/断链注入与帧记录）。验收结束后已按任务 ID/PID 停止隔离服务端与代理，并删除全部临时目录。

## 真机验收记录（D1–D9）

| 项 | 验证目标 | 结果 | 关键证据 |
| --- | --- | --- | --- |
| D1 | P0-3 旧直连 Bearer 环境覆盖安装后无缝重连 | 通过 | 覆盖安装后冷启动自动恢复 `http://192.168.10.75:3773`（`已连接 · 会话已同步`，40 条会话），无需重新配对。[首页](d1-home-reconnect.jpeg) · [环境页](d1-connections.jpeg) |
| D2 | P0-3 直连 DPoP 配对与滚动续期 | 通过 | 使用 `t3 pair` 签发的一次性配对码（`subject=one-time-token`）完成局域网配对，`auth_sessions` 写入 `method=dpop-access-token` 与 `proof_key_thumbprint`（30 天续期窗口）；在重连获取 ws-ticket 阶段注入单次 401 后，客户端自动携带 ES256 DPoP 证明调用 `POST /oauth/token` 完成续期，令牌指纹由 `103cc188b786` 轮换为 `624a9d73e5fd`，`auth_sessions.expires_at` 由 `2026-12-22T17:32:03.675Z` 顺延至 `2026-12-22T17:34:44.189Z`，重连保持 `已连接` 无需重配。[配对后](d2-dpop-paired.jpeg) · [续期后](d2-dpop-renewed.jpeg) |
| D3 | P0-1 多字段敏感输入卡片（明文/掩码、显隐、校验、退后台清空、提交） | 通过 | 邮箱字段明文无显隐图标、密码字段默认掩码带眼睛图标；仅填邮箱时「安全提交」禁用，两项填全后启用；点击眼睛图标明文展示 `B40Secret99`；切到桌面再返回前台后两项输入全部清空且按钮恢复禁用；重新填写提交后服务端落盘 2 个 `0600` 秘密文件，投影 `secretStatus` 转为 `saved`，聊天消息与 turn_items 零明文泄漏。[初始卡片](d3-secret-card.jpeg) · [掩码已填](d3-secret-filled.jpeg) · [明文显隐](d3-secret-revealed.jpeg) · [退后台清空](d3-secret-bg-cleared.jpeg) · [提交完成](d3-secret-saved.jpeg) |
| D4 | C1 断线重连同 `commandId` 重放且服务端不重复入库 | 通过 | 在无本机 `claude` CLI 的隔离 `claudeAgent` 会话（零真实模型调用）中发送消息，代理在转发 `message.dispatch`（`commandId=25726315-e5a1-4955-aaf9-b5db2123d631`）并待服务端落库后于返回 ack 前切断 TCP 连接；客户端自动重连 `WS#2` 并以完全相同的 `commandId` 重放 `message.dispatch`，服务端凭回执幂等去重，SQLite 与手机 UI 均仅保留 1 条用户消息。[去重画面](d4-c1-dedup.jpeg) |
| D5 | C2/C3 断线退避重连与前后台切换恢复 | 通过 | 停止隔离服务后 `:14873` 进入连接失败与退避重连（主实例 `:3773` 保持 `已连接` 不受影响）；重启服务后无人工操作自动恢复 `已连接`；切到系统桌面 3 秒再返回前台连接保持健康且 `/api/auth/session` 正常返回 200。[断线状态](d5-reconnecting.jpeg) · [恢复连接](d5-recovered.jpeg) |
| D6 | U2 长用户消息默认折叠、展开全文与收起 | 通过 | 真机首测捕获到自适应气泡内 `.width('100%')` 导致「展开全文」右溢出及 `Color.Transparent` 渐变灰带，已在 `1d22911` 修复（改用实测 `contentWidth` 与对称 `bubble_transparent` 色板）；复测 26 行长消息默认折叠、渐变柔和、`展开全文` 贴合气泡内右对齐，短消息不折叠；点击展开可见末尾 `END-MARKER-26` 与 `收起`，点击 `收起` 恢复折叠。[默认折叠](d6-long-collapsed.jpeg) · [展开顶部](d6-long-expanded.jpeg) · [展开末尾与收起](d6-long-expanded-bottom.jpeg) |
| D7 | U3 审阅 Diff 排序对齐 Web 与「隐藏测试文件」开关及持久化 | 通过 | 工作区改动按依赖与分类排序为 `src/core.ts` → `src/app.ts` → `src/core.test.ts` → `src/app.test.ts` → `pnpm-lock.yaml`（非字典序）；勾选「隐藏测试文件」后显示「已隐藏 2 个测试文件」并仅保留非测试文件，关闭重开面板后状态保持持久化（验收后已恢复关闭）。[审阅排序](d7-review-order.jpeg) · [隐藏测试文件](d7-review-hide-tests.jpeg) |
| D8 | U4 定时任务默认工作树基准分支与清除已绑定目标会话 | 通过 | 新建任务选项目 `b40-demo` 并切换工作区为「新工作树」时，「基准分支」自动解析为项目默认分支 `develop`（非当前分支 `feature-demo` 或硬编码 `main`）；对停用状态的已绑定任务点「编辑」→「清除目标会话」→「检查并保存」→「保存修改」后，UI 回读确认且隔离库确认 `enabled=0`、`thread_id IS NULL`（全程未启用定时任务）。[默认分支](d8-schedule-default-branch.jpeg) · [编辑清除目标会话](d8-schedule-unbind-edit.jpeg) · [保存回读确认](d8-schedule-unbind-saved.jpeg) |
| D9 | U1 Provider 不支持原生恢复时隐藏「恢复最近的运行」 | 通过 | A/B 对照两个 `interrupted` 会话：`supportsNativeResume=false` 时「会话操作 → 任务与连接」隐藏「恢复最近的运行」；`supportsNativeResume=true` 对照会话正常显示该入口。[隐藏恢复入口](d9-resume-hidden.jpeg) · [支持时显示](d9-resume-shown.jpeg) |
