# R0 页面与交互基线

2026-11-16，固定源码见 [基线清单](evidence/r0/baseline.json)。B01 已于 2026-11-17 在 Android 模拟器取得原版真实截图/操作记录（`evidence/r1/b01-original/`）；B02–B10 仍为 S（源码推断），原版真实运行证据尚未取得。历史 `evidence/ui-translation/` 是 H（鸿蒙离线样例），不能当 R；上游 `docs/internals/images/mobile-*.png` 是架构示意，也不是核心页面运行记录。

## 可复核的原版操作顺序

| 用例 | 入口、操作及返回 | 结构/交互基准（S） | 必须取得的真实证据 | ArkUI 对应/当前偏差 |
|---|---|---|---|---|
| B01 | Home 无环境→标题/添加→Connections→+→ConnectionsNew→返回 | Home 工作区标题和列表；环境管理是 sheet；添加页扫描区、Or enter it 地址/Code、顶栏 check；云配置齐全才出现 T3 Connect | 2026-11-17 已取得：无环境、添加页、空字段禁用、相机授权/拒绝/永久拒绝设置入口、提交中/失败、真实配对成功回 opener、已连接无项目、深色、Manage/Edit、服务停止后 retrying；原版二维码识别成功/无效码因 AVD 合成相机不可用未执行 | Navigation+bindSheet；入口位置/扫描文案/底栏差异见 `ui-refresh.md` |
| B02 | 添加页→T3 Connect→SettingsAuth→账号/Profile→onboarding→发现/添加环境→关闭 | 原版 Clerk AuthView/UserProfileView；签出后返回；onboarding 0.6 detent，Android max 0.95；配置缺失 drops auth deep link | 同合法账号、回调/取消/拒绝、环境 offline/授权中/完成 | ArkUI 壳+经批准的认证机制；不能直接复用 RN 原生账号 UI，回调注册仍缺 |
| B03 | Home 列表→新任务→项目（或 last project）→Thread draft→模型/选项→环境/分支/上下文→发送 | 新任务选择项目支持搜索/No project；选项目进入草稿而非立即创建空会话；模型 sheet 无 header、full detent；返回保留 draft 语义 | 空项目/搜索无结果、草稿返回恢复、模型/上下文选择、第一次发送及失败，服务端会话创建时点 | R3 已在专用机验证项目搜索/选择、No project 入口、添加项目、返回和选中项目不被旧会话覆盖；完整 draft/首次发送状态机仍属 R4，不能把当前空会话创建称为原版等价 |
| B04 | Thread→输入→运行→审批/问题/敏感请求→完成→追问 | 单一 composer、队列/steer/stop 状态、工具工作记录；PendingApproval/UserInput/SecretRequest 的不同可恢复态；输入焦点与键盘不遮卡片 | 真实工具/允许与拒绝、多问题自定义、敏感来源/另端 pending、完成与停止；密码期间不抓值/UI dump | 原生 List+请求卡；历史部分闭环 H 仍有效，不能作为新版原版对比 |
| B05 | Thread→Files→File→返回；Thread→Review→选行→评论 sheet→返回/发送 | 文件路由为 page；Review 为 page，comment sheet 0.55/Android fullScreen；草稿文件浏览也有独立路由 | 相同测试仓库文件/增删改 Diff、长行/折叠/选择与取消、加入上下文后的内容 | 原生文件树/源码/Diff；当前只有基础代码文本，缺文件审阅 |
| B06 | Thread→Terminal→session 菜单→输入/复制/粘贴→返回 | header solid；原生终端自测量 cols/rows，read-only 与可输入分开；键盘修饰条和多 session | 测试 PTY 的 ANSI/宽字/软键盘/外接键盘/resize/断线恢复，不执行真实业务命令 | XComponent+桥接候选；文本日志不能作为交互终端证据 |
| B07 | Thread→Browser/Devices→选 tab/设备→操作→返回 | Browser modal gestureEnabled=false；Device immersive 隐藏 system bars；菜单包含缩放/viewport/theme/站点数据/设备操作 | 非业务测试页面/设备帧和触摸回传、断线/无权/无设备，键盘及方向改变 | ArkUI 原生外壳/解码显示+输入映射；客户端导航不可改成 WebView |
| B08 | Home→Settings/搜索→子页→环境筛选→返回 | 分组跟原版 SettingsRouteScreen，server pages 无目标 disabled；手机/宽屏工作区返回由 settings-navigation 决定；旧链接 alias 保留 | 所有设置入口与隐藏条件，回读本地/服务/项目范围、managed disabled | Navigation/NavDestination+原分组 rows；当前没有完整设置页 |
| B09 | 列表行长按/侧滑→固定/暂缓/settle/归档/删除/撤销 | 状态/能力决定菜单与可撤销动作；行排序与读状态 | 展开每个动态菜单、无权限、部分失败/撤销/取消，顺序和状态回读 | 专用机已验证长按菜单、settle/撤销、归档/恢复、暂缓、上移 orderKey、自动 Settle 与删除确认的 DB 回读；拖拽、运行中限制和无权限矩阵仍未验收 |
| B10 | PR 列表→详情→文件/讨论→inline comment/review→确认；关联线程/评审向导 | 保留 Stack 中 12 个 PR 注册页及 ThreadPullRequests sheet；子弹层 detent 见 route ledger | 有权限/只读/草稿 review/冲突/不同 merge method、返回保持列表位置 | 原生详情/选择器/Diff；缺失 |

## 视觉取证与通过规则

- 每个 B 用例按相同输入内容、窗口逻辑尺寸、系统字体档位、深浅色分别保存原版截图与操作序列；记录平台/设备/系统、app variant、上游 SHA（store 包若不匹配只作辅助）、服务版本/SHA、账号能力和配置**是否存在**，不记录秘密值。
- 记录顶栏、返回/关闭、新任务/环境入口、composer、menu/sheet 的相对位置、间距、圆角、字体、图标与主题变量。数值只能从固定源码或实测读取，不凭空填像素；动画/手势/键盘焦点以录屏和操作步骤验收。
- 每页至少覆盖 loading/empty/error/disabled/offline/content；无适用状态写明原因。返回键先退原页面/弹层，草稿与选择的保留/丢弃严格跟原版；无障碍焦点和最大字号也要比较。
- 使用 `generated-uniwind-default-theme-variables.json` 和原组件角色做 ArkUI 主题翻译，平台 safe area 与系统授权窗允许系统差异；不改产品层级、交互顺序或自创主导航。iOS/Android 原版本身有不同呈现，需先固定对照平台，默认以可获得的 Android 手机原版为首轮参照，并记录 iOS 独有结果的等价要求。
- R0 不把“源码布局已读”记作“像素/交互一致”。B01 已解除“缺可运行原版设备与构建”的阻塞；B02–B10 仍阻塞。B01 的原版二维码识别子项仍受当前 AVD 合成相机限制。本表是具体可执行取证清单，不是已有视觉验收结果。

## 本轮寻找原版运行路径的结果

已读 `apps/mobile/README.md` 和 `package.json/app.config.ts`：Expo Go 不支持；需匹配 fingerprint 的 Dev Client 或 release 原生包，含修改过的 screens/Markdown 包和自定义模块。优先使用上游 `node scripts/mobile-native-client.ts check android <测试设备>` 只读核对，再按 README 安装匹配 dev client、启动独立 Metro；不要在未知设备运行自动安装脚本，也不触发 CI build/publish。

本机 `adb devices -l` 无设备；该命令首次启动了本机 ADB daemon（仅宿主辅助进程，未修改/重启 T3 业务服务）。`xcrun simctl list devices booted` 返回 `unable to find utility simctl`。`~/.cache/t3code/native-clients` 未发现可列出的本地 artifact。`/Applications/T3 Code (Beta).app` 是桌面安装，不能替代 mobile。专用 HDC 目标 `23E0224122000135` 复核为 ALN-AL80，只读包清单发现 `com.dasungta.t3code.harmony`，没有原版移动包；不在 HarmonyOS 上尝试安装 APK。

需要：一台明确授权的 Android 测试机/模拟器或可用 Xcode simulator、与固定基线匹配的原生客户端（或隔离构建条件）、独立测试服务/仓库和按能力所需的合法账号。未索取凭据、未启动登录或安装，不存在等待中的秘密输入；后续若确需用户独有秘密必须经 request_secret。
