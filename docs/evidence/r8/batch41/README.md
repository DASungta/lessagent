# 上游同步第 3 批（M1、L1–L4）真机验收 · batch41

2026-11-23。在专用 Mate60Pro（`23E0224122000135`，`com.dasungta.t3code.harmony`）上以 `hdc install -r` 覆盖安装，未卸载应用、未清数据，未触碰宿主机用户正在运行的主 T3 Code 服务（`http://192.168.10.75:3773`），全程未启用定时任务、未触发真实模型调用。

## 构建与单测

- 宿主单测（在干净临时 `git worktree` 的 `HEAD` 上执行 `node --test tests/*.test.mjs`）：`672/672` → **`698/698`** 全量通过（+26 项新测）。
- 签名 debug HAP 构建通过（干净 `HEAD` `798d373`，`> hvigor BUILD SUCCESSFUL in 37 s 133 ms`）：
  - 最终交付包 SHA-256：**`f51313e0026b92398be4bb870739ecf84ed0c7be4c38cdd718cba81edea146e3`**（含真机验收中发现并修复的 `46bea01` `ProjectOverviewPanel`/`ReviewPanel` 多仓库参数透传与 `798d373` `GitPanel.statusCard` ArkUI 按值传参刷新修复）。
  - 过程构建记录：`abcd8b4` (`1ef54fd609b2f3de11de231e04de6be598be40ecdf037f8bcc8ab897629c0708`) → `46bea01` (`31fe59097109007ebbbe452cd6ff66fe3867e9c2eb7bc22cf2bc96a930b7a654`) → `798d373` (`f51313e0026b92398be4bb870739ecf84ed0c7be4c38cdd718cba81edea146e3`)。
  - 详细命令输出见 [检验日志](checks.txt)。

## 隔离服务端与跨环境链接拓扑

使用本机已安装的 `t3` CLI（`0.1.12-nightly.20261122.5098`，对应上游 `620cf4770d`）启动 3 个完全隔离的服务端（外加单仓库复测用临时 `:14884`）：

- **Server A**（`:14881`，`--base-dir /tmp/t3-b41-a`，`envId=307deb0c-8540-4e18-8a3f-1b93432612df`）：
  - 多仓库项目 `t3-b41-multi`（`/tmp/t3-b41-multi`，含自动发现的 `repo-api`、`repo-docs`、`repo-web`，其中 `repo-api/server/api.ts` 与 `repo-web/src/index.ts` 有工作区改动；另准备项目外仓库 `/tmp/t3-b41-extra` 用于手动添加/移除）。
  - 单仓库对照项目 `t3-b41-single`（`/tmp/t3-b41-single`，含 `app.ts` 改动）。
  - 预置会话：`多仓库联调主会话`（14 条消息，含 `MARKER-1`–`MARKER-6`、行内 `t3-thread://v2/...` 链接、本地子智能体 `本地子智能体：API 校验`、远端委派 `远端委派：Server B 审阅`）、侧聊 `侧聊：仓库分组方案讨论`（`lineage.sideChat=true`）、以及 `单仓库对照会话`。
- **Server B**（`:14882`，`--base-dir /tmp/t3-b41-b`，`envId=0578616a-4579-49de-b7f5-710d01a88928`）：
  - 预置 `Server B 远端审阅会话`（含 `B41-REMOTE-MARKER` 标记）。
  - 通过 `t3 environment link` 与 Server A 建立双向 peer link（因上游禁止明文 HTTP 局域网地址、允许 loopback，Server A 以 `http://127.0.0.1:14882` 链接 Server B，配合 `hdc rport tcp:14882 tcp:14882` 使手机可直连探测并完成 E3 DPoP 配对）。
- **Server C**（`:14883`，`--base-dir /tmp/t3-b41-c`，`envId=60399c1f-0055-4eac-ae24-f89eb9a79b12`）：用于 E6 批量链接界面与协议验证。

验收完成后已停止全部隔离实例、删除全部 `/tmp/t3-b41-*` 目录与 `hdc` 端口转发规则，并从手机移除 batch40/batch41 全部测试环境。

## 真机验收记录（E1–E6）

| 项 | 验证目标 | 结果 | 关键证据 |
| --- | --- | --- | --- |
| **E1** | M1 多仓库项目（项目设置增删仓库、新任务仓库多选、Git 分组与提交目标确认、审阅分组、单仓库对照） | **通过** | - 项目设置自动展示 `repo-api`/`repo-docs`/`repo-web`（`自动发现` + `Git 仓库`）；手动添加 `/tmp/t3-b41-extra` 成功并出现 `移除` 按钮；点击 `移除` 经确认弹窗移除成功，磁盘 `/tmp/t3-b41-extra/.git` 完整保留。[初始列表](e1-project-repos-initial.jpeg) · [已添加外置仓库](e1-project-repos-added.jpeg) · [已移除](e1-project-repos-removed.jpeg)<br>- 新建任务选 `t3-b41-multi` 切换至「新工作树」后可打开「选择关联仓库」多选清单，默认 `全部仓库（3）`，取消勾选 `repo-docs` 后实时更新为 `关联仓库 · 2 个仓库`。[新任务仓库选择](e1-new-task-repo-picker.jpeg)<br>- 多仓库 Git 面板分组列出 3 个仓库分支与改动统计；进入 `repo-web` 提交页显示「目标仓库：repo-web · main」，点「提交」弹出「确认目标仓库」确认对话框后取消未提交。[多仓库 Git](e1-multi-git.jpeg) · [提交目标确认](e1-multi-git-confirm.jpeg)<br>- 多仓库审阅面板显示「4 个仓库」、仓库筛选胶囊与 `repo-api/server/api.ts`、`repo-web/src/index.ts` 分组 Diff。[多仓库审阅](e1-multi-review.jpeg)<br>- 单仓库对照无多仓库分组元素；真机视觉复核捕获并修复 `GitPanel.statusCard` 按值传参刷新缺陷（`798d373`），复测确认单仓库 Git 正常显示 `1 个文件已改动`、`+1 -1` 与可点击「提交」。[单仓库 Git（修复复测）](e1-single-git.jpeg) · [单仓库审阅](e1-single-review.jpeg) |
| **E2** | L1 只读查看链接环境会话 | **通过** | 手机仅连接 Server A（未配对 Server B）时，点击 `多仓库联调主会话` 中的行内 `t3-thread://v2/...` 链接，经 Server A 实时流式读取并渲染 Server B 的 `Server B 远端审阅会话` 与 `B41-REMOTE-MARKER` 内容；底部呈现「只读模式」「此视图不可发送消息」与「连接此环境」按钮，无输入框与发送按钮。[Server A 已链接 B](e2-server-a-linked-b.jpeg) · [只读链接会话](e2-linked-readonly.jpeg) |
| **E3** | L2 从只读会话直接连接链接环境 | **通过** | 在只读链接会话点击「连接此环境」，通过 `peerLinks.pairClient` 自动换取 12 位一次性凭据并探测可达地址 `http://127.0.0.1:14882`，预填「连接 B41-Server-B」确认页；点击「确认」完成 P0-3 DPoP 配对（Server B `auth_sessions` 写入 `dpop-access-token\|one-time-token`），并自动切入交互态 `Server B 远端审阅会话`（出现正常输入框「继续追问…」）；返回父会话后再次点击同一链接直接进入已连接的交互会话，不再触发只读或重配。[预填配对页](e3-prefilled-pair.jpeg) · [连接后交互会话](e3-connected-interactive.jpeg) |
| **E4** | L3 统一打开方式（`panel` / `main`）与返回父会话滚动位置恢复 | **通过** | - 默认 `panel` 模式下，从滚动至中段（`MARKER-2`–`MARKER-4`）的父会话分别打开远端链接会话（[e2-linked-readonly.jpeg](e2-linked-readonly.jpeg)）、本地子智能体（`B41-SUBAGENT-MARKER`，[面板打开子智能体](e4-panel-subagent.jpeg)）与侧聊（`B41-SIDECHAT-MARKER`，[面板打开侧聊](e4-panel-sidechat.jpeg)），三者均以面板覆盖展示且关闭后父会话位置不漂移。[父会话中段基准](e4-parent-mid.jpeg)<br>- 在「设置 → 子会话打开方式」切换为「主视图打开」后（[主视图设置](e4-setting-main.jpeg)），三类入口全部在主页面全屏打开（[主视图子智能体](e4-main-subagent.jpeg) · [主视图侧聊](e4-main-sidechat.jpeg) · [主视图链接会话](e4-main-linked.jpeg)），且点击返回后父会话每次均像素级恢复到原中段位置（`REPLY-MARKER-3` y=676 / `MARKER-4` y=1042 / `REPLY-MARKER-4` y=1583，[返回恢复滚动位置](e4-parent-restored.jpeg)）。验收后已恢复默认「面板打开」。 |
| **E5** | 既有连接与主实例回归（D1、D5） | **通过** | - D1：`hdc install -r` 覆盖安装冷启动后自动重连主实例 `http://192.168.10.75:3773`（`已连接 · 会话已同步`），无需重新配对。[冷启动首页](e5-d1-home-reconnect.jpeg) · [环境列表](e5-d1-connections.jpeg)<br>- D5：停止 Server A（`:14881`）后 `:14881` 转为「连接失败」而 `:3773` 保持 `已连接` 不受影响；重启 Server A 后无人工干预自动恢复 `已连接`。[断线状态](e5-d5-disconnected.jpeg) · [自动恢复](e5-d5-recovered.jpeg) · [清理后最终环境状态](e5-cleanup-verified.jpeg) |
| **E6** | L4 一次链接多个环境（可选） | **部分受限（UI 与协议链路已全验证）** | 在「环境 → Server A → 批量链接其他环境…」中完整验证：离线环境标「不可选」、已链接的 Server B 标「已链接」排除、可勾选目标环境（手动取消勾选 `:3773` 仅保留隔离实例 `:14883`）与权限单选（[批量链接选择](e6-link-batch.jpeg)）。点击「批量链接 (1)」后客户端在 Server C 现场签发一次性配对码并向 Server A 调用 `peerLinks.link`，Server A 按上游安全策略拒绝明文 HTTP 局域网地址（`http://192.168.10.75:14883 is plain http ... Use its https address, or its Tailscale address`），客户端按结构化错误逐项展示「目标不可达」失败原因与「已链接 0 个，失败 1 个（可重试失败项）」状态（[批量链接结果](e6-link-batch-result.jpeg)）。因测试宿主机无 HTTPS 证书与 Tailscale 地址且 `linkReachableAddresses()` 按上游策略过滤 loopback，未在纯明文局域网下强行放宽安全校验；全量并发成功/部分失败/重试逻辑已在宿主单测 `tests/link-batch.test.mjs` 与 `tests/native-client.test.mjs` 完整覆盖。 |
