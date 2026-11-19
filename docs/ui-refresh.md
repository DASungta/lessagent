# 按原版 T3 移动端翻译原生界面

R0 校对补充见 [原版交互基线](r0-interaction-baseline.md) 和 [能力矩阵](r0-mobile-capability-matrix.md)。本文截图是鸿蒙离线样例，不是原版真实页面证据；本轮未复写历史结果。

2026-11-16。用户否定首轮自创三页导航和大卡片后，按本机上游 `apps/mobile` 重新实现。首轮 `evidence/ui-refresh/` 为旧方案记录，不代表当前界面。阶段三专项仍进行中，M2 未完成。

## 原版到 ArkUI 的对应

| 原版源码（`/tmp/t3code-harmony-upstream/apps/mobile/`） | 当前原生实现 |
| --- | --- |
| `features/home/HomeScreen.tsx`、`features/threads/thread-list-v2-items.tsx` | 紧凑会话行、项目副标题、项目过滤；点击进入对话 |
| `features/layout/workspace/WorkspaceListHeader.android.tsx` | 单行 T3 Code 标题，标题进入环境管理，右侧新会话入口 |
| `features/threads/ThreadHeader.tsx` | 返回列表、会话标题/项目副标题、更多操作；系统返回优先关闭弹层 |
| `features/threads/ThreadComposer.tsx`、`components/ComposerToolbar.tsx` | 单一圆角输入区域、空文本紧凑单行、多行扩展；附件原生菜单、圆形发送控件 |
| `features/threads/PendingApprovalCard.tsx`、`SecretRequestCard.tsx` | 细边框请求卡片、正文和次要说明分层，安全字段保持密码模式 |
| `generated-uniwind-default-theme-variables.json` | 直接使用原版默认深浅色的 screen、foreground、muted、user-bubble、border、prominent-action；输入区域取原版不透明底色 |

不再使用“会话 / 对话 / 连接”选项卡、蓝色大按钮、重复角色标题及首页宣传大卡片。助手正文无额外卡片，用户消息靠右使用原版灰底；代码块提供轻量复制入口。图标为深浅色线形 SVG，ArkUI 原生渲染。

## 保留的能力与适配边界

连接/安全续用/断开/删除、项目/模型选择、新建/打开会话、完整历史与流式回复、工具输出、代码复制、审批/普通回答/敏感输入、停止、附件、未知提交核对均保留。发送回包保护新草稿的修复保留。

环境管理、新会话选择和会话操作用 ArkUI `bindSheet`；附件用 `bindMenu`。新会话仍先选择项目/模型再创建，沿用现有服务流程；没有移植上游完整草稿任务创建器、会话内模型切换或多环境能力。停止任务在会话更多操作中，不根据不完整的运行状态猜测停止/发送按钮切换。未实现功能没有放置空入口。

## 本轮验证

- `./scripts/build.sh`：签名构建通过；没有修改协议、依赖、签名配置或安全存储。
- `node --experimental-strip-types --test tests/*.test.mjs`：47 项通过，包括新草稿保护、失败保留草稿、深浅色正文对比度和系统返回顺序。
- 授权 Mate 60 Pro / ALN-AL80：用临时离线样例实际检查列表、进入对话、单行输入栏、线形图标、新会话原生弹层。修复真机发现的 SVG 填充和弹层内容垂直居中问题。
- 样例仅用于视觉检查，没有连接服务器或提交业务请求。样例代码已移除，最终重新构建、覆盖安装并启动正式包。

真机样例截图：[列表](evidence/ui-translation/list-sample.png)、[对话](evidence/ui-translation/chat-sample.png)、[新会话弹层](evidence/ui-translation/new-session-sample.png)。这些是设备上的原生界面，不是 WebView 或网页预览。

## 未验收

本轮未复验在线发送/审批/附件闭环。新版键盘弹出、深色真机切换、最大字体、屏幕朗读和快速流式/大历史性能未完成专项；不将协议测试或离线样例计作这些验收结果。

无 Git 仓库；上一版页面和请求卡片备份在 `/tmp/t3-harmony-ui-v1-backup/`，临时路径不是持久备份。

## 2026-11-17 原版 Android 实机对照（B01）

按固定基线 `ad1b136` 在本机构建 Expo Dev Client，运行于 Android 11 模拟器（Pixel_6_API_30，1080×2400），取得原版空环境 Home、Environments、Add environment 的浅色/深色真实截图，存于 [visual-parity](evidence/visual-parity/)。截图带 Dev Client 的浮动齿轮和 DEV 标记，属于开发构建附加 UI，不是产品界面。

据此完成一轮视觉迁移：

- 主操作色改为原版 `primary`（浅色 `#1b4ed8`、深色 `#346bf1`），用于 Home 空态按钮、发送按钮和审批/回答按钮；移除未再使用的 `accent`。
- 空态标题/说明字号与层级贴近原版（24 粗体 / 15 次要色）。
- 环境面板空态改为原版同类的整块 `surface` 圆角卡，含圆形图标底与两行说明。
- 添加环境页把地址和配对码合并为单个圆角卡，左侧标签、行间分隔，并补原版说明文案；返回改为线形箭头。

未迁移：原版底部 Chats/Pulls/Usage/Settings 标签栏（后三项目前没有功能，不放空入口）、搜索入口、会话列表的状态/时间/置顶等行内信息，以及扫码成功/失败、相机拒绝等 B01 交互取证。上述截图只证明空态与添加页的静态视觉，不代表交互验收通过。

## 2026-11-17 B01 交互取证补全

固定基线 `ad1b136` 的 Dev Client 仍在 `Pixel_6_API_30` 上运行。本次通过 T3 Device 实际操作补齐了 B01 的原版交互，证据在 `evidence/r1/b01-original/`：

- 已覆盖：无环境 Home、添加页、空字段禁用、真实连接失败、系统相机授权、首次拒绝、第二次拒绝后的设置入口、隔离服务真实配对成功并返回 opener、已连接无项目 Home、深色三页、提交中 spinner、超时失败、Manage/Edit。
- 原版没有在相机拒绝时显示错误条；只有第二次拒绝后再扫描才出现 “Camera access needed”，提供 Cancel / Open Settings。
- 原版零连接和已连接空闲时点击标题都不打开 Connections；从 Home 空态进入的添加页，返回落到 Settings 根部。因此不能把“标题→Connections”当成本构建的可复现入口。
- 仍未取得原版二维码识别成功/无效码：AVD 后摄为合成 `emulated`，只能得到黑色预览，无法呈现可读二维码。

对照结论（详情见 `evidence/r1/b01-original/README.md`）：

- 颜色、空态主按钮、添加页卡片层级与已迁移版本基本一致，本轮没有回退颜色。
- Harmony 添加页仍是底部 sheet，扫描卡缺少原版 “Tap to scan” 与扫描说明两行文案；配对码显隐是本地安全增强。
- Harmony 用标题进入环境管理，而原版空闲态标题不可点；底部四栏导航/搜索仍未迁移。前者需要在 R1.4 决定是否保留，后者继续按“没有功能不放空入口”处理。
