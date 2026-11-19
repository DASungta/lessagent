# 原版 B01 真机取证（Android 模拟器）

2026-11-17。固定基线 `ad1b1365999c92c3fc7a054e7f3af84623f74fee` 的原版 `apps/mobile`，运行于 T3 Device 管理的 Android 11 模拟器 `Pixel_6_API_30`（`emulator-5554`，1080×2400），包名 `com.t3tools.t3code.dev`。这是原版 Dev Client 的真实 Android 渲染与真实网络请求，不是源码推断、Replay、Harmony 页面或 browser preview。

基线核对：把 `docs/baselines/t3code-ad1b136.tar.gz` 的 `apps/mobile` 与运行目录 `/tmp/t3code-harmony-upstream/apps/mobile` 做 `rsync -rcn`（排除 `node_modules`、`.cxx`、`build`）比较，无差异；`app.config.ts` SHA256 两端一致，版本 2.3.0。

## B01 操作记录

| # | 操作 | 结果 | 截图 |
|---|---|---|---|
| 1 | 冷启动 Home，无环境 | “No environments connected”、添加按钮、四栏底部导航 | `01-home-empty-light.png` |
| 2 | 点击标题 | 无变化；与 01 字节相同，证明零连接时标题不是入口 | `02-title-tap-no-op-empty-light.png` |
| 3 | 点击 Add environment | 全屏添加页：扫描卡、地址/配对码、顶栏 check 空态禁用 | `03-add-environment-empty-light.png` |
| 4 | 填 `127.0.0.1:1` / `000000` 并提交 | 真实传输失败，红色错误与红色卡片边框，停留在页面 | `04-add-environment-failure-light.png` |
| 5 | 点击扫描 | 系统相机权限对话框 | `05-camera-permission-light.png` |
| 6 | 拒绝相机 | 返回表单，无错误条，已填字段保留 | `06-camera-denied-light.png` |
| 7 | 再次扫描 | 同一会话第二次请求仍弹系统对话框 | `07-camera-permission-second-request-light.png` |
| 8 | 返回 | 回到 Settings 根页（该入口的 opener），不是 Home | `08-settings-root-after-back-light.png` |
| 9 | 第二次拒绝后再次扫描 | 应用对话框“Camera access needed”，Cancel / Open Settings | `09-camera-after-second-deny-light.png` |
| 10 | 填写隔离服务地址与一次性码并提交 | 真实 OAuth 配对成功，返回 opener（Settings 根页） | `11-add-environment-success-opener-light.png` |
| 11 | 进入 Environments | 一个环境：Desktop、`http://10.0.2.2:47861/`、Connected；PR routing 为 Off | `12-environments-connected-light.png` |
| 12 | 回到 Chats | 已连接但服务无项目：“No projects found”与 New thread | `13-home-connected-empty-threads-light.png` |
| 13 | 已连接时点击标题 | 同样无变化；与 13 字节相同 | `14-title-tap-no-op-connected-light.png` |
| 14 | 切换深色 | Home、Environments、Add environment 三张深色页面 | `15`–`17` |
| 15 | 提交到黑洞地址 | 顶栏 check 变 spinner（提交中），随后真实传输失败 | `18`、`19` |
| 16 | 授予相机后扫描 | 扫描卡变为黑色实时预览，扫描控件禁用；模拟器合成相机没有可读二维码 | `20-scan-screen-camera-allowed-light.png` |
| 17 | Manage / Edit | 连接详情、路由列表、权限、编辑模式的路由删除与排序 | `21`、`22` |
| 18 | 停止隔离服务 47861 | 环境行变为 “did not answer, Retrying”，地址保留；现有 3773 仍在监听 | `23-environment-disconnected-light.png` |

一次性配对码没有写入截图、日志或本目录；`11` 是成功返回后的 opener，不含配对材料。`10.0.2.2` 是 Android 模拟器到宿主的固定别名，本次配对只连到临时隔离服务 47861，现有 3773 未重启或改配置。

## 未执行

- **二维码识别成功/无效码**：headless AVD 的 `hw.camera.back=emulated`，合成相机无法呈现可读二维码。实际尝试到“相机已授权、扫描页激活”，没有用源码、Replay、Harmony 截图或浏览器预览替代。
- 原版没有对“相机拒绝”显示错误条；应用只在第二次拒绝后提供系统设置入口。这一点是原版行为，不是验收遗漏。

## 与当前 Harmony 实现的差异

对照现有 `docs/evidence/visual-parity/harmony-*.jpeg`：

- 原版 Home 已连接时显示 No projects 空态和右下 New thread；Harmony 仍以标题/列表为主，底部四栏导航与搜索入口未迁移（已在 `ui-refresh.md` 记录）。
- 原版添加页是全屏页，扫描卡有 “Tap to scan” 和说明文案；Harmony 是底部 sheet，扫描区为黑色预览且没有这两行文案。Harmony 额外的配对码显隐按钮是本地安全增强。
- 原版空态主按钮、添加页主色、卡片层级与当前 Harmony 已对齐；本次没有发现需要立即回退的颜色偏差。
- 原版标题在空闲且已连接时也不打开 Connections（`WorkspaceConnectionTitle` 只有状态非空时才渲染 Pressable）；Harmony 用标题进入环境管理，属于交互差异，需在 R1.4 视觉/交互收口时决定是否保留。

截图哈希见 `screenshots.sha256`，结构化观察见 `observations.json`。
