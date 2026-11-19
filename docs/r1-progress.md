# R1 首批实现与边界

> 当前结论见文末真机与 B01 补验收记录；下文首批“单例/未激活”描述为历史实现，不能作为当前代码状态。统一摘要见 [整体进度](development-status.md)。

2026-11-16。已开始 R1，**未完成 R1 全量，也未解除 R0 原版真实取证阻塞**。首批记录未操作设备；后续按用户要求补真机验证，最新状态见文末。未迁移设备真实数据、未发送服务请求、未重启服务、未创建子代理或初始化 Git。

## 本批代码

- **R1.1 已实现未真机验收**：`protocol/Pairing.ets` 依据固定 ad1b136 的 mobile pairing/shared remote 规则，用鸿蒙 URL/URLParams 实现纯解析；现有手动连接按钮调用此解析。覆盖无 scheme IP→HTTP、域名/tailnet→HTTPS、IPv6、显式 HTTP/HTTPS、WS/WSS→对应 HTTP、hash 优先 query token、托管 host+token、`t3code://pair?pairingUrl=`。坏输入、用户信息、非网络协议、无效端口、控制字符、冲突配对码拒绝；不记录输入、不自动连接、不打开扫描地址。包装链接限 pair 目标，拒绝递归包装，属于明确校验边界。
- `Wire.serverBase` 允许上游直连所需的 HTTP，包括 LAN/tailnet；端口范围检查新增。**HTTP 会明文传输配对及 Bearer，只适用于用户信任的网络，公网优先 HTTPS**。TLS 校验未关闭，NetworkKit `maxRedirects: 0` 未变。鸿蒙 LAN/IPv6 真实网络兼容仍待验证。
- **R1.2 仅基础模块，未激活/未完成**：`protocol/Environment.ts` 提供 v2 目录严格 schema、每环境凭据引用、每线程恢复引用和 v1 迁移函数。拒绝多余字段、重复身份/引用、越范围引用、非法选中项、损坏身份。该版本目录只接受已实现的 bearer kind，T3 Connect/relay 仍在 R2 范围。
- `storage/EnvironmentStore.ets` 将无 token 的目录写入应用私有文件：临时写入→fsync→回读/校验→rename；缺文件与损坏/不可读分开处理。独立 session/recovery alias 复用 `SessionStore` 的 DEVICE_UNLOCKED、1024 字节限制，无明文回退。
- `migrateLegacy` 读取并验证旧 session/recovery；过期 session 仍迁入，未知提交类型/标记不做宽松丢弃。先写独立 Asset 并精确回读，最后提交目录；旧 alias 保留。固定迁移引用使提交前崩溃重试不重复添加目录条目；失败可留下未引用的新 Asset，后续重试覆盖同引用，不清理旧记录。已有目录也检查全部凭据/恢复身份和可读性，锁屏不当成空数据。
- **启动仍使用 v1 单例**，没有调用迁移；不允许 v1/v2 两组 writer 同时写。目录的 clear 仅是底层空目录提交，不是已实现的用户移除环境流程，调用层还必须处理未知提交、删除中状态和旧 alias。

## 本地检查

- 本轮开始时实际执行原有测试为 47 项；新增后 **65/65 通过**，以归档日志为准。
- 新增 18 项：配对向量/拒绝；迁移各步读写失败、回读丢标记、过期、不匹配、孤立/坏数据、两个环境同 threadId 引用、目录防复活、已有引用不可读；实际文件适配器用宿主临时目录检查中断写/坏回读/rename 失败后旧目录保持完整。所有数据为合成数据。
- `./scripts/build.sh` 签名 HAP 构建通过；迁移/文件模块曾通过 ArkTS 编译，未接入最终启动。SDK 文件异常提示保留；页面已有 AlertDialog deprecated 提示不是本轮新增流程。
- 上游 schema / Effect serialized RPC conformance 重新执行通过。未改变 Wire 消息契约，未用这些检查替代鸿蒙 URL、Asset、真实网络或原版 UI 验收。
- 证据：`docs/evidence/r1/` 保存本轮开始前源码/测试/README 备份、测试/构建日志和摘要；HAP 见 `entry/build/default/outputs/default/entry-default-signed.hap`。

## 尚需继续的工作

1. R1.2 完整目录写入协调、添加/删除中状态与旧 alias 防复活、独立恢复 store 的运行绑定及升级/回退测试；与 R1.3 一起切换启动写入者。**当前不允许把该模块单独激活后仍运行旧单例写入**。
2. R1.3 按环境持有 T3Client，选择绑定、旧回包 generation、防跨环境草稿/附件/请求卡；两个环境相同 ID 的客户端并发测试。现有 UI/AttachmentPicker/RequestCard 的单例依赖未改。
3. R1.4 Connections/ConnectionsNew/SettingsEnvironmentNew 原生页面翻译、启停/编辑/重试/移除；R1.5 扫码和 Want 冷启动暂存、权限与生命周期。当前只是原有手动表单获得解析能力，**没有新增扫码/深链注册入口**。
4. R1.6 两个独立合法环境、专用 Mate60Pro 复核与升级安装、原版 B01 真实对照。ADB/simctl/匹配 Dev Client 缺口仍按 R0 记录，本轮未重新尝试解除，不以宿主测试代替。

新任务仍为选择项目/模型后创建空会话，完整原版草稿流程留 R4；云/DPoP/终端/预览/推送本轮均未真验。

## 回退

`evidence/r1/pre-r1-source.tar.gz` 是本批之前的 entry/src/main/ets、tests、README；仅在核对本批变更清单后取回具体文件，避免覆盖后续修改。新增 Environment/Pairing/测试文件不在旧备份中，回退时另行移除。未激活 v2，没有设备数据迁移需回退。未来激活后若 v2 凭据/恢复发生变更，不得直接退包继续使用陈旧 v1。


## 真机作为每环节完成门槛（2026-11-16 追加）

用户明确要求每个环节都在真机验证。后续每个 R1 子项必须同时记录设备实际操作、正常/异常路径、持久化/重启适用路径和结果证据；本地检查不替代设备检查。遇到设备/账号/原版条件阻塞时标记未验收，不能跳过后宣布完成。

本次补验准备与实际结果：

- 指定 HDC `23E0224122000135` 复核为 `ALN-AL80`；前台进程仅确认是 `com.dasungta.t3code.harmony`。
- 新增 `scripts/build-device-check.py` 和 `scripts/device-checks/DeviceCheck.ets`：临时构建隔离诊断页，finally 恢复普通入口与页面注册。诊断页不加载 T3Client，不发网络请求；仅使用 `r1-check-` 前缀 Asset 与私有 `r1-device-check` 目录中的合成数据。计划覆盖真实 URL 解析、Asset 大小边界、身份不匹配保护、真实 Asset+文件迁移、目录损坏保护，以及第二次启动回读并清理。
- 诊断签名构建通过并成功覆盖安装。启动返回 `10106102`（锁屏限制），**没有运行任何设备测试断言**，不计通过。已通过用户输入卡请求手动解锁，不索取密码、不关闭开发者模式。
- 等待期间重新构建普通入口并成功覆盖安装，**设备最终恢复普通构建**，诊断入口未留在普通源码/普通 HAP。没有清除本机应用数据、没有运行 v1→v2 迁移；诊断没有成功启动，因此也未写入合成 Asset/目录。
- 本地回归仍为 65/65；恢复包构建成功。等待解锁后需要重新安装已归档诊断包、执行两次启动，记录实际断言，再恢复普通包并补验手动连接 UI。当前配对与迁移设备验收仍未通过，真实连接、锁屏 Asset 和升级迁移不由本次安装成功证明。

临时诊断包仅用于这台授权设备，位于 `docs/evidence/r1/device-check-signed.hap`；不得作为普通交付包安装。运行命令的目标必须始终显式指定，测试过程中不能触及其他设备。


## 解锁后真机补验结果（2026-11-16 17:24–17:27）

用户明确回复已解锁后，重新复核同一 ALN-AL80，只操作授权目标 `23E0224122000135` 的测试应用。

- 隔离诊断包覆盖安装、启动成功；进程 28009 执行 **9/9 通过**：IPv4/IPv6/tailnet 解析、托管链接/query/hash/Unicode、t3code 包装/wss、坏输入拒绝、实际 Asset 读写与 1024 字节限制、迁移身份不匹配保留旧记录、真实 Asset+私有文件目录迁移、跨环境引用拒绝、损坏目录拒绝覆盖。
- 仅 force-stop 本测试应用后重新启动，进程改为 28539，**2/2 通过**：真实进程重启后目录/未知提交标记及旧合成凭据完整读回；清理全部测试 Asset/目录成功。没有重启 T3 服务或操作其他设备。
- 恢复普通签名 HAP 并成功启动，普通客户端显示空环境首页。实际操作添加环境表单，输入 `ftp://test` 点击连接，显示通用无效地址错误；系统返回键关闭 sheet 并保留首页；再次停止并启动测试应用后，普通首页正常、测试输入消失。三项原生 UI 检查通过，错误状态截图已人工查看。
- 最终设备是普通构建，诊断页未留在应用入口中；合成数据已清理，没有读取生产 alias、没有激活生产 v2 迁移、没有提交服务端业务任务。普通页面空环境恢复路径没有触发服务连接。

证据：`evidence/r1/device-check-runtime.log`、`device-check-result.json`、`device-invalid-pairing.json`、`device-invalid-pairing.jpeg`、`device-native-back.json`。结果摘要含诊断/恢复 HAP SHA256。上述结果取代上一节的等待解锁状态，但不扩大验收范围。

**仍未验收**：实际 LAN/IPv6/HTTPS 配对传输、锁屏时 Asset 行为、真实旧版升级/回退、多环境连接绑定和原版视觉对照。诊断证明的是基础 API 与合成迁移事实，不能把 11 项通过记作 R1 全量完成。后续每环节继续先列设备用例，完成设备检查后才推进其验收状态。


## R1 持续推进：实际网络与目录协调器（2026-11-16 追加）

目标继续保持 active，尚未完成 R1。最新设备状态取代前面的“最终普通构建”：当前为了锁屏存储检查安装了临时 NetworkCheck 诊断构建，设备锁屏且等待用户手动解锁；读取/清理锁屏记录后再恢复普通构建，不把临时入口当产品交付。

- 通过桌面自带 T3 CLI 启动两个独立 **真实 0.1.9 / protocol 2** 服务，独立 base-dir/端口 47831、47832，现有 3773 服务未重启/改配置。私有目录和环境 ID 见 `evidence/r1/lab-state.json`，该文件不含凭据；测试凭据仅一次性、只读 orchestration 权限，不调用 Agent。
- 真机经 **Wi-Fi 和实际局域网路由**（非 USB reverse）完成 4 项检查：A/B 各自 OAuth→WebSocket→getConfig；两实例同时 ready、env/token 不相同；暂停/恢复 A 时 B 保持 ready；坏配对码拒绝且 B 凭据保持原值、再用保存凭据恢复。观察记录见 `network-observations.json`。不外推为 HTTPS、IPv6 实网或完整多环境产品验收。
- 构建工具支持 `--source/--output`，可以用不同隔离诊断页构建到 /tmp，finally 恢复普通 Ability/页面注册。配对数据通过 HDC debug 文件通道放入应用私有文件，不包含在 HAP/证据中；应用读完即删除，不在命令或日志输出凭据。
- NetworkCheck 使用独立 `r1-net-*` Asset；锁屏前保存合成记录并启动受控探针。系统 WindowManager 确认锁屏窗口 foreground；**尚未拿到 Asset 在锁屏时拒绝/解锁后读回证据**。不能把按键成功或日志暂不可读当测试通过。已发手动解锁输入卡。
- 新增 `EnvironmentRegistry.ets`，尚未接正式启动/页面：串行目录变更、每环境客户端及独立 Asset、每线程恢复索引、重复身份配对前拒绝、启停/选择、未知提交拒绝移除、删除 tombstone 与中断清理。v2 schema 增加可选 deleting 字段，仍兼容旧 v2 严格格式。
- `T3Client` 增加预期 environmentId/配对前校验及只读 mutationPending，地址指向其他环境或重复添加时不交换配对码。删除路径先阻断新提交，再读所有恢复引用；旧迁入环境删除会清理对应 v1 alias，空目录防复活。
- 本地回归 **72/72**，包含两个实例相同 thread/message ID 的流、旧回包/独立重连、提交/未知拦截、目录提交失败和中断删除重启清理。RegistryCheck 真实 ArkTS 编译与签名构建通过（最初 constructor property/隐式对象类型错误已修复）；**专项真机尚未执行**。

下一步：解锁后读回 NetworkCheck 锁屏结果并清理；重新发两份仅测试配对码，执行 `/tmp/r1-registry-diagnostic.hap` 的真实目录/客户端检查；然后才把 Registry 绑定到正式启动和原版连接管理入口，做真实升级及页面回归。源码与单测不得替代此门槛。两个隔离服务暂供后续验收，结束时仅停止它们、撤销其测试授权并删除私有临时数据。


## 目录真机、锁屏修复与正式入口接入（2026-11-16 18:08 追加）

- RegistryCheck 在两个真实隔离服务上 **6/6 通过**：同时存在、重复身份在交换凭据前拒绝、独立启停与重连、相同 threadId 的恢复 alias 隔离、未知提交阻止移除、单目标清理与空目录防 v1 复活。日志 `registry-device-runtime.log`。
- 锁屏发现了不能忽略的平台时序：设备 secureMode=true，系统发出 SCREEN_LOCKED 后，最初一段时间原封装仍能读到测试 Asset，随后才出现原生 24000005。因此不能仅靠 Asset DEVICE_UNLOCKED 判断即时保护。原始观察 `lock-native-observation.json`、`lock-native-after-unlock.json` 保留这个事实；不将其泛化为所有鸿蒙设备缺陷。
- SessionStore 新增显式 screenLock.isScreenLocked 检查，读/写/删除入口均拒绝锁屏操作；query 后再次检查，避免查询期间锁定后把记录返回。API 状态查询失败也拒绝访问。锁屏失败不会用空记录覆盖目录，也不清未知标记。
- 修复真机检查已闭合：`lock-guard-locked.json` 记录 secureMode=true、系统锁屏事件、screenApiLocked=true、wrapperDenied=true、lockedReadable=false；`lock-guard-recovered.json` 记录解锁事件、恢复完整 unknown/message 标记、清理合成 Asset 成功（recovered=true）。旧的临时 r1-net-lock 也由诊断清理。
- 生产源码已接环境目录启动和生命周期，页面绑定当前实例；附件 picker 绑定实例并在文件读完后再次校验会话，卡片捕获所属连接，草稿按 localId+threadId 分区。新页面为标题→环境管理 sheet→添加页，保留返回/顶栏确认；首页环境过滤与跨环境线程键已接。**尚未在正式 UI 完成升级/多环境验收**。
- 已接原生 ScanKit XComponent、相机权限、停扫/释放、重复识别防护与本地取消 generation；已注册 t3code://pair Want 冷/热启动暂存，只填表、不联网、不落配对码。仅源码/宿主状态机测试和构建，**扫码/深链真机仍未验收**。T3 Connect 仍留 R2，未因默认关闭删除。
- 地址编辑先验证 environmentId，无凭据发送；pendingBase 作为崩溃续做状态，将凭据与每线程恢复记录切到新 base 后提交目录。已有启用/删除标记保留。该新增路径待真机验证。
- 当前本地回归 **83/83**；正式源码签名构建通过。AppScope versionCode 从 1 增至 2、versionName 为 0.1.1，以便执行真正带版本递增的覆盖升级。
- 从首批备份源码在私有临时工程构建旧 v1 writer/UI（versionCode 1，旧 session/recovery alias），不替换工作树源码；仅为用户要求附加前台 keep-screen-on 测试标记。现已在授权手机覆盖安装并启动此旧版，准备通过真实配对写 v1，再安装 v2 检查迁移，**升级尚未执行**。构建来源/hash 见 `legacy-build.json`。
- 按用户要求临时保持测试应用亮屏，系统 API 读回 `legacyWindowKeepScreenOn=true`（18:07:54，进程56627，日志 `keep-awake-device.log`）。普通新构建以 Want `--pb r1KeepAwake true` 显式启用；后台释放、前台恢复，默认关闭，不修改全局自动锁屏设置，不绕过安全锁屏。诊断/旧版测试包只在自己的可见窗口保持亮屏，退出后系统释放。

最新设备状态是旧 v1 验证构建、已解锁/保持前台亮屏；不是已完成升级的产品包。两个测试服务仍供验收使用，现有3773服务未改动。下一步为真实旧版配对→v2覆盖升级→原生多环境/扫码/深链；C05 环境关系与 PR routing、原版 B01 真实取证门槛也仍需核对，不能漏掉后宣布 R1 完成。


## 真实升级与原生入口回归（2026-11-16 18:43 追加）

- 原 v1 源码构建在真机经真实配对连接隔离 A，确认地址为 `http://127.0.0.1:47831`、配对字段清空；第一次 UI 等待超时，但后续原生读回及实际连接确认成功，未把超时当作失败后盲目重发。证据 `legacy-ui-pairing.json`。
- 两个真实服务创建同一个 `r1-collision-project` / `r1-collision-thread`，读回各自 project/thread 身份。**两边 messages、providerTurns、runs、providerSessions 全为 0**，没有消息/Agent 任务。fresh 服务无可用 provider metadata，空会话只保存明确的未配置模型元数据，不宣称模型可运行。证据 `real-collision-fixtures.json`。
- 旧 UI 实际打开该线程并写入 v1 恢复记录。v1 格式隔离准备页只在预期 A 身份/线程、无 v2 目录、原 pending 为空的边界内，注入 `r1-synthetic-unconfirmed/message`；保留旧 UI 的真实凭据不变。该标记为受控故障样本，**不是注入真实服务丢 ACK**。结果 `upgrade-v1-seed.json`。
- 覆盖安装 versionCode **1→2** / 0.1.0→0.1.1 后，普通产品入口自动完成迁移并用原凭据恢复真实连接，没有重填配对码。受保护记录在设备内比较：新旧 session/recovery JSON 完全一致、已选环境保留、目录无 token。证据 `upgrade-directory-after-install.json`、`upgrade-protected-audit.json`、`upgrade-installed-version.json`。
- 普通 v2 重启后依然显示原线程的未知提交提示；从实际环境管理点击移除被阻止。初次跨页选择曾只改变 generation，未改变条目/凭据；修正同一环境选择不再写目录后，重新实际操作得到 **移除前后目录完全相同**。精确证据为 `upgrade-unknown-remove-exact.json`，不能用更早两份不同 generation 的目录声称字节相同。
- 默认降级安装旧 v1 被系统拒绝：`9568263 install version downgrade`，安装版本仍为 2。仅证明默认安装路径拒绝，不宣称强制绕过平台版本检查后的旧包安全。日志与读回 `upgrade-downgrade-attempt.log` / `upgrade-downgrade-result.json`。
- 在服务端确认样本从未有消息/运行后，实际点击“已核对提交结果”清除本地受控标记，输入未发送的 `R1_A_UNSENT_ONLY` 作为之后切环境的草稿样本；没有点发送。证据 `upgrade-ack-and-draft.json`。
- 真机发现并修复两个 UI 问题：当前聊天项目误作首页过滤器，导致同 ID 的另一环境可能被隐藏；系统 sheet 关闭控件遮住自绘 +。已分离环境/项目筛选身份，环境页改为独立的左侧关闭/右侧添加、滚动内容与固定工具栏。修复后真实点击 + 已进入添加页，确认/返回均可见；不自创其他导航。
- 相机权限首次拒绝后手动输入保留；后续系统不弹请求时，正确提供原生权限设置入口。请求/设置/取消均不会自动新增环境。已在真机到达系统的“相机权限”恢复页；**尚未完成允许后实际摄像头扫描**。拒绝证据 `camera-denied-no-popup.json`。
- 已为旧/新扫码视图交替加上 ScanKit 全进程串行硬件租用，旧视图回调/清理不能停掉新视图；本地测试覆盖，真正相机生命周期仍随下一步扫码专项检查。当前本地 **87/87** 与最新签名构建通过。
- 原生 CoreImage 生成独立 B 的一次性测试 QR，宿主 Vision 回读一致；只放在私有 lab 目录并在本机 Preview 打开，配对材料不进入 HAP/证据/日志。此宿主检查不代替手机扫码。已发输入卡，请用户在手机允许相机、对准实际 QR，识别后回复且先不确认添加。

最新设备是普通 v2 产品构建（保持亮屏测试参数开启），不是诊断页；A 保持连接。当前为相机权限恢复页，等待实际物理对准，B 尚未添加；A 草稿是进程内测试样本，后续升级重启若重建则明确重输，不把它算 R4 跨进程草稿持久化。继续做 B 扫码确认、两环境同 ID 的 UI/草稿/附件/重连/删除、深链、TLS/IPv6/重定向和 C05。原版 B01 取证门槛仍未解除，R1 未完成。


## C05 源码与负向传输探针准备（2026-11-16 追加）

上一轮是实质进展（真实升级/原生入口故障修复），本轮继续准备未完成能力；**R1 仍 active，未完成**。手机保持 87 项时代的普通产品构建，未在等待用户实际扫码时覆盖安装。

- PR 路由设置按固定上游 `PullRequestRoutingSettings.tsx` 翻译：关闭/读取/读取与操作，默认关闭、双方启用且都授权才允许共享；写操作双方都须 read-write。值随目录持久化，端点变化先撤销该权限；移除时与条目一起清理。严格 schema 拒绝未知值。仍只支持当前单一 Bearer 端点；R2 alternate/relay routes 引入时须按上游完整 connectionKey 保持信任边界。
- 已链接环境段按固定 `LinkedEnvironmentsSection.tsx` 翻译，为只读展示；能力 peerLinks、服务 beta `linkedEnvironmentsEnabled` 和当前连接的 access:read 都满足才查询 `peerLinks.list`。权限来自 `/api/auth/session`，明确 permissions=[] 优先于旧 scopes，未认证/异常列表/查询失败不授权；旧连接迟到响应不能写入新视图。过期/不可达/错误与五天过期提示按上游顺序处理，窗口离开/后台释放计时。
- 管理页打开、前后台和已连接环境变更会重新读取；两环境权限按各自连接隔离，不落 token、配对码或权限快照。地址编辑成功后补上启用环境的自动重连，避免多一个手动重试动作。
- 当前 **91/91 本地检查、普通签名构建通过**，但 **C05 候选未覆盖安装、未真机验收**。只证明已实现的只读段和本地 PR 策略；实际跨环境 PR 请求、link_request 批准/拒绝/撤销相关入口仍须按原版真实归属继续核对/实现，不能把设置保存称为全部 C05 完成。
- 启动了仅合成数据的独立负向传输 fixture：HTTP 302 跨源、独立捕获端口、自签名 HTTPS、协议 3 描述符。宿主自检通过，不接收真实配对码、不改两个 T3 服务或现有3773。基线 `network-negative-host-baseline.json`；原生 `TransportCheck.ets` 签名构建已准备，**尚未安装/执行**，不能把宿主自检称为鸿蒙 TLS/重定向/协议验收。自签名拒绝即使通过，也不代替有效公网证书的 HTTPS 配对。
- 原来的 B QR 在等待期间到期，已在本机 Preview 换为新的隔离 B 只读测试码；材料仍仅在私有 lab 目录，未进入源码/HAP/证据。仍等待用户在手机允许相机并实际对准；二维码只填表，不应自动连接。
- 为解除原版运行阻塞，重新核实本机已有 Android36/NDK/Java，但无 emulator/镜像。精确 Node26.13.1 和任务私有 pnpm12.14.0 已准备，默认 Node22 未改。按上游 AGENTS 的 `vp i` 在固定源码 checkout 准备依赖，当前安装会话仍运行；不启动上游 CI、不上传产物、不改 Git 身份。包管理器 bootstrap 曾只添加25行工具元数据，已精确恢复，检查时固定上游 tracked 源码干净，安装结束还需复核。
- 原版 **Device panel 工具返回 Agent device access 关闭，且需后续会话才生效**。已读取 `/tmp/t3code-harmony-upstream/.agents/skills/test-t3-mobile/SKILL.md`；原文要求：`If T3 device tools or the selected device are unavailable, report the blocker and stop verification. Do not install or switch to another automation system.` 因此没有绕到另一套原版自动化，原版取证未执行；专用 Mate60Pro 的用户显式 HDC 授权保持有效。
- 上游 AGENTS/开发文档提供 free Replay(dev)，后续 C05 需要活动请求时优先用自建隔离 Replay 后端，不用真实付费模型或真实业务任务。这里只完成前置依赖，尚未启动 Replay，也未产生审批请求。

后续：用户实际扫码→确认前核对 B 配对未消费→确认添加与同 ID/草稿/附件/断网/删除验收；之后执行并比对原生负向传输结果和宿主计数、深链、C05 真验。原版 B01 仍受上述访问设置阻塞，不由宿主/源码/Harmony 离线样例代替。最新句柄、临时服务 PID 与候选包路径见 `lab-state.json`；持续任务开始前先复核实际存活和手机状态，不凭文件重启任何服务。


## 负向传输 307 与依赖准备补充

- 新增独立 307 探针（47846），覆盖 POST body 会被保留的重定向情形；原探针未重启，生产与两个真实测试 T3 服务未改动。宿主 manual-redirect 自检通过，捕获端无请求。Native TransportCheck 现在共四项：302、307、自签名 TLS、协议不兼容；**仍未安装/执行**。
- 引用仓库要求的 Node26.13.1 已实际安装，任务专用 pnpm12.14.0 运行正常，用户默认 Node22 未切换。第一次 `pnpm dlx vite-plus ...` 因包内多个可执行文件终止，改用明确 `--package=vite-plus@1.4.0 dlx vp i --frozen-lockfile` 后正在正常下载；当前确认为存活会话23710，不因等待重新启动。tracked lock 的25行工具 bootstrap 变更已检查归因并恢复，原版源码尚未修改；安装结束还需读回状态。
- 已将过期 QR 换为有效期2小时的隔离 B 只读测试 QR并在Preview打开，不含其他权限；手机仍未被重装或代替用户完成物理对准。源包/原生诊断候选已准备，权限恢复/扫码需用户实际操作后继续。

## 临时防自动熄屏（用户授权）

- 2026-11-16 20:29，专用目标23E0224122000135使用系统`power-shell timeout -o 7200000`临时将自动熄屏等待覆盖为2小时；PowerManagerService实际回读AWAKE、原值600000ms、覆盖值7200000ms。无需后台循环程序，不重装或切换正在等待相机权限的应用，不取消安全锁屏。
- 进入下一次主动锁屏验证前及结束设备验收时执行`power-shell timeout -r`恢复，并再次回读；当前尚未恢复。此证据仅证明超时覆盖已生效，不声称已连续运行2小时。证据：`docs/evidence/r1/temporary-screen-timeout.json`。

## 相机恢复、真实链接请求与恢复检查（2026-11-16 20:40）

- 专用 ALN-AL80 目标再次复核。系统相机权限页已通过“允许”单选读回及“确定”恢复；返回普通产品页后实际出现 ScanKit XComponent，未截取相机像素、未重装或切换应用。隔离 B 的当前 QR grant 数据库只读核对仍为未消费/未撤销；相机恢复不等于实际识别成功。证据 `camera-permission-recovered.json`。已请求用户物理对准 QR，识别后先不确认添加。
- 固定上游依赖安装已成功结束（会话1687），tracked 源码仍干净；之前记录的23710为已被修正的失败启动，不再是运行中。默认 Node22 未改，源服务使用独立 Node26.13.1 与 private home，在47847启动。未改动实际3773和隔离A/B配置。
- 独立源服务 C 已用免费 Replay question 场景和实际 ACP/MCP 通道生成一张待处理 link_request，并由真实 orchestration snapshot 读回。初次调用被服务端正确拒绝：审批模式不能修改环境关系；随后只对自己的测试 Replay 线程明确选择 full-access，形成新卡，没有重发旧消息。前四个测试 run 已明确停止，只有第五个为当前待验卡；没有付费模型和真实业务任务。`replay-link-request.json` 仅导出白名单字段，标注 nativeVerified=false；它证明后端真实请求存在，不证明原版或 Harmony UI 已批准/拒绝。
- 链接请求原生卡与表单已接入候选源码：当前线程及本地来源校验、当前连接权限、5种原版访问级别、已知地址 origin 匹配、未知地址提示、手动码或具备权限的目标自动 mint、提交单次与失败不回显秘密。撤销真实归属为 Sharing & access/Authorized clients，不能在只读 LinkedEnvironmentsSection 自创撤销入口；该路径仍未闭合。
- 修复环境重试吞掉失败的问题：T3Client.connect 记录失败后，Registry.reconnect 在未 ready 时向调用者报告状态。新增错误码重新配对保留旧凭据/目录/未知恢复、有效换码保留同一恢复记录且不发 dispatch 的实际适配器回归；捕获的真实链接卡也加入跨线程来源回归。**106/106 本地测试、普通签名构建成功**。当前候选 `/tmp/r1-c05-current-candidate.hap` 未安装，手机仍是87项时代的普通产品构建；新增逻辑未计真机通过。
- 已同步 README、权威计划顶部状态、C01–C05矩阵及本轮R1授权边界；不修改历史验收结论。临时2小时熄屏覆盖仍启用，锁屏验证前及设备验收结束须恢复并回读。

仍需：实际扫码且确认前无网络授权、双环境产品级同ID/草稿/附件/启停/重启/删除、原生深链和传输负例、有效HTTPS/IPv6实网、过期重新配对的原版入口、C05批准/拒绝/撤销及PR目标请求。原版B01依旧受 Device access 关闭和 test-t3-mobile 明确停止规则约束，不由源码/Replay/Harmony样例代替。R1继续 active，未完成。

## 已有地址重新配对与摄像头生命周期（2026-11-16 20:48）

- 核对固定上游 `connection/onboarding.ts` 的 preparePairingRegistration/registry.assertKnownAddress：普通添加允许已有地址刷新凭据，拒绝“新地址冒认已有环境”；显式 Add route 才允许添加新路径。此前一律拒绝重复身份过严，阻塞过期会话更新。
- 当前候选的 `EnvironmentRegistry.add` 对已有规范化地址复用原 T3Client、credentialRef、全部 recovery alias 和未知提交事实；仍按已固定 environmentId 在 OAuth 前校验。正确配对后才重新启用/选择；坏码不改目录/存储，新地址冒认仍拒绝。沿用添加页，无新增导航。多条直连 route 的完整列表/增删/排序尚未实现，不把当前单端点替换视作上游完整 route 管理。
- `T3Client.connect` 在真实修改提交期间拒绝重连，防止重连切断尚在落盘的提交；仅有恢复中的未知标记不阻断鉴权/只读同步。新增测试覆盖更新已停用/过期环境时恢复引用不变、另一个客户端不受影响、身份变化和坏码保留原数据；RegistryCheck 的已知地址用例也同步改为复用，避免把“过期旧码被拒绝”误当“未交换凭据”的证据。既有6组真机日志为旧行为历史记录，不能证明新语义。
- Asset save 改为序列化一次、写入后通过同一锁屏保护入口回读并精确比较，再让调用方继续。掉写但返回成功时，旧凭据不被视作更新，新的未知恢复引用也不能提交。写后查询失败仍报告失败，不伪造空记录。原有1024字节限制及锁屏前/后检查保留。
- `CredentialRefreshCheck.ets` 独立诊断包构建成功，准备实际 A/B 配对→控制过期A/合成未知→坏码保留→同地址新码更新→B不变/超限拒绝→清理的5组检查。它仅使用 r1-refresh 前缀 Asset/目录，尚未安装运行，不能计作真机通过。
- 新增真机证据 `camera-lifecycle-native.json`：系统 CameraService 读回同一产品进程前台 Started/1 session→Home 后0 session→显式返回 Started/1 session；环境目录前后字节一致。未截取相机像素。这证明实际后台释放和前台恢复，不证明物理 QR 已识别。
- 最新本地108/108通过，普通签名构建成功，诊断构建后恢复产品源码并重新构建普通候选。`known-address-candidate.json`记录hash及candidateInstalled=false。手机仍是原普通产品包且停在扫码页，等待真实对准；不将新候选检查算作已安装代码的真机证据。

R1继续 active；实际QR、双环境产品页面、深链/传输边界、过期重新配对真验、多路径管理及C05仍需完成。原版B01访问设置阻塞未解除；未扩展云、移动SSH或R3/R4业务。

## 网络负例、凭据更新、深链与双环境产品真机闭环（2026-11-16 21:08）

- 暂存实际物理扫码，先完成无需用户对准的独立真机检查，再恢复普通构建；未把深链或文件解码称为摄像头识别。普通目录在诊断覆盖前备份，恢复产品后逐字节一致，A无需新码自动鉴权。进程内旧测试草稿因主动重启丢失，明确重新录入，不计跨进程草稿持久化。
- `TransportCheck` 原生4项及宿主计数已通过：302/307各发生一次OAuth请求、捕获端无任何请求；自签名HTTPS没有收到HTTP请求且新增unknown_ca握手告警；协议3描述符后OAuth请求为零。首轮只有2/4断言通过，因为诊断误期望302/307而SDK实际报告2300047；保留首轮结果，核对已装SDK及华为官方API（maxRedirects=0禁止重定向、超过返回2300047）后修正断言、重新构建安装复验。证据 `transport-negative-first-attempt.json`、`transport-negative-accepted.json`。有效公开证书HTTPS配对仍未证明。
- `CredentialRefreshCheck` 独立 r1-refresh Asset/目录、真实A/B只读新码，5组真机通过：控制A过期和合成未知→坏码保留目录/过期凭据/未知事实→已有地址更新且复用原client/引用→B仍ready且凭据不变、1024字节超限不覆盖→仅清理测试记录。首轮诊断清理直接写空Asset但内存unknown仍保留，产品正确阻止移除；修正为等待实际线程快照后走acknowledgeUnknown，第二轮通过。旧轮仅专用前缀的已知合成标记在显式cleanupPrevious fixture下清理，不碰产品记录；不发送业务消息。证据 `credential-refresh-native.json`。
- 普通产品108通过已有A地址+新只读码的实际UI重新配对，服务端确认该码消费；返回Connections、目录字节完全相同、原进程测试草稿仍在。证据 `known-address-product-native.json`。这证明产品入口，和控制过期/未知的独立诊断分别记录。
- 深链检查发现确认提示和连接状态共用status，已有连接更新可覆盖表单提示；拆出pairingStatus，坏链接清除暂存码，连接错误留在表单。修复后109/109本地测试及普通签名构建通过、已覆盖安装109产品；不是未安装候选。
- 系统隐式Want（没有指定bundle/ability绕过filter）冷/热启动t3code://pair均在真实产品预填目标，确认提示可见、目录字节不变、独立B grant仍未消费；冷启动PID实际变化。javascript内层URL拒绝，无自动配对。证据 `deeplink-native.json`。后续单独点击明确确认按钮添加B，记为URI预填+显式确认配对，**仍不计QR识别**。
- `r1-dual-ui-check.py` 在普通109产品验证：两个真实环境同时连接，首页两条同projectId/threadId会话且按环境/项目区分；A→B→A→B未发送草稿保留各自内容；credentialRef和recovery alias独立；关闭A仍可打开B并保留B草稿；重启A连接无需新码并恢复A草稿。等待异步shell列表出现后才操作，不重发业务请求。A/B实际数据库回读messages/runs/providerSessions均为0。证据 `dual-product-ui-native.json`。
- IPv6准备只读检查：宿主没有非链路本地IPv6；设备`ip -6 addr`受权限限制，不能把空输出当作没有IPv6。`ipv6-readiness.json`明确该查询未证明地址可用性。没有改网络配置，不计IPv6实网通过。
- 真机当前为普通109，首页A选中、A/B测试草稿仍在同一进程。下一步先附件/删除隔离，再恢复实际相机扫码；不要为读取源码而重装打断这两个样本。临时2小时熄屏覆盖仍有效，后续锁屏检查前及验收结束须恢复。

R1仍active：实际摄像头识别、附件/移除及进程恢复产品回归、同环境多路径、有效HTTPS/tailnet/IPv6实网、C05批准/拒绝/撤销及PR请求、原版B01对照均未全部闭合。原版Device access关闭，继续遵守已引用test-t3-mobile的停止规则；不会用上述Harmony/Replay证据代替原版视觉或真实业务验收。T3 Connect保留R2，未增加移动SSH或扩展R3/R4。

## 原生文档附件、移除隔离与真实摄像头识别（2026-11-16 21:45）

- 未通过 HDC 绕过系统公共目录权限，也未修改系统权限。临时 DocumentFixture 用系统 DocumentSavePicker 创建唯一命名的两份文档并逐字节回读。首轮诊断未在部分失败前记下URI，另留下两份自有测试文件；现四个准确名称已列白名单并通过系统选择器重新选中、校验内容。业务客户端未加入测试文档创建入口。
- 普通产品109实际调用 DocumentViewPicker 选择本轮A文档；只给自建A发放新的 read+operate 授权，B保持read-only。A真实服务收到一个pending附件，读回39字节与原文相同，SHA256见 `attachment-a-native-upload-bytes.json`。未点击发送；A/B的消息、run、provider session均为0。
- 切到B时无A附件；B的“重试上传”没有复用A的选择。再明确选择B测试文档，真实RPC被拒绝，B无pending文件，B草稿保留。当前错误呈现为通用RPC失败，未将其称为已显示具体权限说明。只读权限由真实B会话scope与拒绝结果共同核对；回到A，原文件chip和草稿仍在。
- 普通产品页明确确认移除B后，A目录条目逐字段/引用不变，A附件和未发送草稿仍在；独立native Asset审计实际读到A有效凭据/恢复完整、旧B凭据及1条恢复记录均缺失。证据 `attachment-and-B-removal-native.json`、`product-removal-asset-native.json`。随后扫码重新添加的是新的B本机记录，不把旧B别名缺失等同于新B也不存在。
- 用户实际将后摄对准电脑Preview二维码。第一枚物理二维码曾在核对前被消费且新B已出现，因未捕获确认时刻，不计该轮“确认前无授权”门槛。已使用另一枚新只读码复验，用户明确回复“已识别并保持不动”。设备实际显示识别完成、地址为预期B、CameraService会话数0；服务端该枚新码仍未消费/未撤销，目录已有两环境。证据 `camera-physical-before-confirm-native.json`。此后代理只点击一次原生确认，实际读到该枚码被消费、A/B均连接、已知B目录字节不变，证据 `camera-physical-pairing-native.json`。没有截取相机画面，不以桌面Vision自检或深链替代物理识别。
- 实际扫码后重新跑普通产品A→B→A→B同ID草稿/恢复范围、停用A保留B、重新启用A保留A草稿的回归，通过。最新 `dual-product-ui-native.json`已关联真实摄像头证据。之后普通包再次恢复并等待真实启动过程结束，读到两环境无需新码鉴权、同ID空线程都回到列表，见 `ordinary-after-camera-and-document-fixture.json`。未声称进程内草稿或附件跨进程持久化；重装诊断是主动中止这些测试样本进程。
- **测试文档清理未通过**：4份文档有准确名称及内容记录；清理时重开URI返回13900001，另一次未能证明删除后不可再打开。文件清单仍在原生选择器中可见，清理journal保留，未记作已删除；`document-cleanup-observed-partial.json`只作未完成证据。没有操作其他文件。后续需通过受支持的系统文件操作完成这四个准确目标的清理，或继续核实临时URI授权/路径语义，不能删除journal掩盖失败。
- 普通产品109现已恢复、A/B实际连接；不是诊断入口。当前源码的109项宿主测试/普通构建已通过；独立诊断页也能构建，但不计为原版视觉或真实业务验收。临时2小时屏幕超时覆盖仍启用，验收结束/锁屏测试前须恢复。

仍需：多条直连路径（R1，不能借R2延期）、C05真实批准/拒绝/撤销与PR目标请求、编辑/扫描重试等余下原生细项、有效HTTPS/tailnet/IPv6实网及原版B01对照。当前宿主无可用非链路本地IPv6；设备地址查询报权限错误，不能把查询失败写为设备没有IPv6。R1保持active，未完成；T3 Connect留R2，未扩移动SSH或R3/R4业务。

## 最终产品回归、C05 与多路径闭合（2026-11-16 23:40）

R1 的客户端功能范围已完成专用 Mate60Pro / ALN-AL80 (`23E0224122000135`) 实机回归。普通签名产品最终为 versionCode 2 / 0.1.1，119 项宿主测试和构建通过；原版 B01 视觉对照、IPv6/Tailnet 实网组合仍保持外部阻塞，不能据此宣称完整原版视觉或所有网络组合验收通过。

- 多路径：普通产品真实添加同一 B 环境的独立 HTTPS 凭据；路径列表、凭据引用、优先级、环境改名和路径移除均回读。有效公开 HTTPS 证书路径完成 descriptor、OAuth、WebSocket ticket 和 `server.getConfig`；临时隧道轮换/明文转发失败被正确拒绝，修正自 `X-Forwarded-Proto` 后才完成。A/B 最终只保留既有主路径，三个临时 HTTPS 路径全部在 UI 删除并清理凭据，重启后无测试路径残留。多路由隔离、首路径失败回退、活动路径移除重连和未知恢复保留见 `multi-route-native.json`、`multi-route-product-native.json`。
- C05 成功：C 的免费 Replay `r1-c05-replay-source-9` 在原生卡中只读选择 B；确认前 B 无 `T3 Code link` 凭据、C 无 peer row，确认一次后卡片变为 `linked`，目标 B、`read-only`，一次性码消费一次，B 的授权 session 仅含 `orchestration:read`，peer row 指向 HTTPS、状态 `reachable`，到期时间约 30 天。B 的消息/run/provider session 仍为 0，未自动发送业务消息。证据 `c05-link-before-confirm-native.json`、`c05-link-approved-native.json` 和 `c05-link-approved-native.jpeg`。
- C05 拒绝：新卡点击“拒绝”一次后为 `declined`，通知为 `cancelled`，未新建配对码或源端链接。证据 `c05-decline-native.json`、`c05-link-declined-native.jpeg`。
- C05 撤销：固定上游移动 `LinkedEnvironmentsSection` 只读展示，没有虚构源端撤销按钮；目标端通过原版 `/api/auth/clients/revoke` 契约撤销 B 的授权 session，原 C peer token 从 MCP 200 变为 401；源端随后使用协议支持的 `peerLinks.unlink` 忘记链接，row 和 secret 均删除。`peerLinks.list` 在目标 session 撤销但源 row 尚存时仍会因只检查 peer 描述符而报告 reachable，这一上游语义被原样记录，没有误称即时吊销探测。证据 `c05-revoke-ownership-native.json`。
- PR 路由：真机在 A/B 分别设置 `read`、`read-write` 和最终 `off`，目录回读正确；双方 `read-write` 可写授权，单路身份变化会撤销该环境信任，排序不撤销。实际 PR 数据页/写操作仍属 R5，R1 不伪造 PR 路由结果。证据 `pr-routing-settings-native.json`、`pr-routing-settings-native.jpeg`。
- 产品恢复：最终 HAP SHA256 `9a3d43f81743682b321a7dfcb31274bb36b8233ed2123bd5091470be0f3e672f`，`install -r` 成功，final restart 后 A/B 均无需新码连接，目录无 token、无临时路径、PR 设置关闭，两环境未知提交提示仍完整；C 测试环境通过 UI 移除，A/B 引用未变。证据 `final-product-directory.json`、`final-product-manager-native.jpeg`。
- 文档清理：通过系统 File Manager 原生多选四个准确 `r1-native-*.txt` 测试文件并移入删除流程；主目录不再显示，最近删除也没有这四个测试文档。原失败 journal 保留，另记录成功清理，不触碰其他文件。证据 `document-cleanup-resolved.json`；原先的 URI 重开失败记录继续保留。
- 本地最终检查：`node --experimental-strip-types --test tests/*.test.mjs` 为 **119/119 通过**；`./scripts/build.sh` 成功；固定上游 conformance 为命令/OAuth schema 与 Effect 4.1.3 serialized RPC 均 PASS；宿主 DPoP 自检仍明确为 host-only，不替代鸿蒙 DPoP/relay。日志为 `r1-final-tests.log`、`r1-final-build.log`、`r1-final-upstream-conformance.log`、`r1-final-dpop-selfcheck.log`。
- 收尾清理：专用设备系统熄屏覆盖已恢复并读回原值 600000ms；A/B/C 隔离服务的 48 个测试 session 已按标签撤销、无剩余测试配对码，三个服务只按其监听 PID 停止，现有 3773 未重启或修改。私有临时目录、上游临时 checkout 和隧道辅助文件已删除；最终普通 HAP 与脱敏证据保存在项目内。证据 `final-timeout-readback.log`、`final-grant-revocation.json`、`final-service-stop.json`。
- 仍未闭合：原版 B01/全部路由真实视觉与操作，以及 Tailnet/IPv6 实网组合。固定上游 `test-t3-mobile` 规定 T3 Device 不可用时停止原版验证，未用 Replay、源码或 Harmony 截图代替。公开 HTTPS 已真验；公网蜂窝切换、Tailnet、IPv6 不因本次临时隧道结果自动通过。R2 云/DPoP/中继、R3–R8 业务未展开；移动 SSH 仍明确 unsupported。

## R1 退出条件复核（2026-11-16 23:52）

- 再次只读复核宿主和专用机网络：宿主活动接口 `en0` 仅有 IPv4 `192.168.10.75`，无全局或 ULA IPv6，直接 IPv6 探测为 `No route to host`；未安装 Tailscale CLI/App。专用机 `wlan0` 仅列出 IPv4，未列出 IPv6。该结果说明当前环境无法执行 Tailnet/IPv6 实网验收，不能把解析测试或公开 HTTPS 隧道替代为通过。证据 `network-readiness-recheck.json`、`network-readiness-recheck.log`。
- T3 Device 工具再次实际返回 Agent device access 关闭，并说明设置需在新会话生效。因此原版 B01 的真实视觉/操作验收仍无法执行。解除条件是用户在 `Settings > Integrations > Devices` 打开访问后启动新会话，并提供可运行的原版移动构建；不能用源码、Replay 或鸿蒙界面代替。
- 这两项是 R1 完整退出的外部证据门槛，不是尚可继续猜写的实现项。除此之外，R1.1–R1.3、R1.5 与 R1.6 的客户端范围，以及 R1.4 的功能入口、状态和安全约束，均已按上节真机结果闭合。

## R2 接续（2026-11-17）

R2 在保留上述 R1 结论、设备数据和未知提交/防重发逻辑的前提下，新增 T3 Connect 客户端实现：公开配置门控、Clerk OAuth/PKCE 会话、CryptoFramework DPoP、relay token/ticket、环境发现/link/unlink、设备批准/拒绝/撤销及直连/云同 ID 并存。当前 153 项宿主测试和普通签名构建通过，但真实 Clerk、鸿蒙 OAuth client、relay/账号和专用机 DPoP 执行仍被外部条件阻塞；未将任何 R2 项记作真机验收。详见 [R2 进展](r2-progress.md)。

## 原版 B01 模拟器取证（2026-11-17 09:00）

T3 Device 在新会话实际可用，宿主返回 `Pixel_6_API_30`（Android 11，`emulator-5554`）。设备上已有原版 Expo Dev Client `com.t3tools.t3code.dev`；运行目录 `/tmp/t3code-harmony-upstream/apps/mobile` 与固定基线 `ad1b136` 归档逐文件比较无差异，`app.config.ts` 哈希一致，版本 2.3.0。全部操作经 T3 Device / `agent-device` 完成，未用源码、Replay、Harmony 页面或 browser preview 代替。

- 已取得原版真实 B01 证据：无环境 Home；添加页空态；空字段 check 禁用；真实连接失败的红色错误；系统相机授权；首次拒绝；第二次拒绝后的系统设置入口；真实配对隔离 0.1.9 服务成功后返回 opener；已连接但无项目的 Home；深色 Home/Environments/Add；提交中 spinner；黑洞地址超时失败；Manage/Edit 路由。截图与哈希在 `evidence/r1/b01-original/`。
- 一次真实配对只连到临时隔离服务 47861（模拟器经 `10.0.2.2` 访问），未重启现有 3773；一次性码未写入证据。连接成功后原版 Environments 显示 `Connected`，PR routing `Off`。
- 原版行为记录：零连接与已连接空闲时点击标题都不打开 Connections；从 Home 空态 Add environment 进入的添加页，返回落到 Settings 根部。原版没有在相机拒绝时显示错误条。
- **仍无法执行**：原版二维码识别成功/无效码。headless AVD 的后摄为 `hw.camera.back=emulated`，只得到黑色合成预览，不能呈现可读二维码；没有用其他证据替代。其余 B01 视觉/交互已闭合到上述范围。
- 与当前 Harmony 对照的差异已写入 `evidence/r1/b01-original/README.md` 和 `ui-refresh.md`：底部四栏导航/搜索未迁移、添加页扫描文案缺失、标题进入环境管理的行为不同；这些是 R1.4 的实现收口项，不是原版取证缺失。
- Tailnet/IPv6 再次只读复核：宿主 `en0` 仍只有 IPv4，IPv6 仅 loopback/link-local，无 Tailscale CLI/App；专用机 `wlan0` 仅有 IPv4，`/proc/net/if_inet6` 查询被权限拒绝，不能据此断言设备没有 IPv6。当前没有可用 Tailnet/IPv6 拓扑，组合验收保持未执行。证据 `network-readiness-recheck-2026-11-17.json`、`network-device-recheck-2026-11-17.log`。

R1 的 B01 原版视觉/交互取证门槛已从“Device access 关闭”解除；剩余外部限制只有原版相机二维码识别（AVD 合成相机）与 Tailnet/IPv6 实网拓扑。未把这两项记为通过，未扩展 R2–R4，也未修改现有 3773。
