# R0 关键依赖验证与阻塞

2026-11-16。证据等级：S=固定上游/本机 SDK 声明，O=宿主离线原型，D=鸿蒙设备真实能力，R=原版业务。**S/O 不能证明 D/R。** 现有业务应用、签名、服务、设备数据均未修改。

## 云登录、DPoP 与中继

源码：mobile `features/cloud/publicConfig.ts/CloudAuthProvider.tsx/cloudAccountService.ts/managedRelayTokenStore.ts/dpop.ts/linkEnvironment.ts`；runtime `relay/dpopProof.ts/managedRelay.ts/discovery.ts/cloudAccountService.ts`；contracts `relay.ts/relayClient.ts/auth.ts`；shared `dpopCommon.ts/dpop.ts/relayAuth.ts`。

- 云配置要求 Clerk publishable key、JWT template、HTTPS relay URL 齐全；源码构建默认关闭。仅核对了字段与 gating，未读取本机 `.env` 的值，未借用其他客户端凭据。
- 原版账号 UI 实际使用 `@clerk/expo/native-components` 的 AuthView/UserProfileView；登录方式由 Clerk 配置决定，不能仅凭源码假定 Google/Apple/PKCE 全部已可用。鸿蒙需要合法客户端/redirect URI、Clerk 支持的认证路线、会话 token 读取/刷新、回调校验及账号切换清理。未发现本工程已有适配，**阻塞**：公开配置、鸿蒙身份与合法测试账号/回调许可尚未核实。
- `relay.ts` 明确分 list environments/devices（v1/v2）、link challenge/link/unlink、revoke client device、DPoP token exchange、environment status/connect、mobile register/unregister/live activity；链接批准与连接票据是不同阶段。不要把 list 成功当作 relay 已通。
- DPoP header typ=dpop+jwt/alg=ES256/public JWK，payload method 大写、htu 去 query/hash、UUID jti、秒 iat，可选 SHA256 ath。RFC7638 thumbprint 对 crv/kty/x/y 固定顺序。原版 native module 输出 raw 64 字节 r‖s，密钥存 SecureStore 并检查公私匹配；不是任意 JWT 签名。
- 当前 `dpopProof.ts` createProof **没有 nonce 字段**；不能无依据加 nonce 重试状态机。若未来部署返回 nonce challenge，需记录实际契约再适配。续期按 managedRelay 令牌有效期/缓存/scopes/账号/key 绑定及 invalid_bearer 分支重取，不假设存在 refresh_token。
- 本机 SDK 的 `@ohos.security.cryptoFramework.d.ts` 存在 ECC key/sign/convert 和 ECC 签名格式转换接口；[华为 ECDSA 指南](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/crypto-ecdsa-sign-sig-verify/) 指定 ECC256|SHA256。仅说明有候选 API，输出格式、JWK 坐标/导入、安全密钥和锁屏可用性仍须设备测试。
- 最小隔离原型 `node scripts/r0-dpop-selfcheck.mjs` 已通过：与上游测试相同 URL/时间/token 输入，Node crypto 检查坐标长度、htu、ath、thumbprint 顺序、raw 签名验签及篡改拒绝/DER 与 raw 区别。不持久化私钥/令牌，不联网，不导入应用。**没有执行上游 Effect 测试/relay verifier，也没有在鸿蒙签名**；结果见 `evidence/r0/dpop-host-selfcheck.json`。
- R2 门槛：鸿蒙 key→真实 relay 验签、绑定 token、发现/设备批准/拒绝/撤销、跨网络连接与审批、有效期边界/注销/换号；缺任一项保留阻塞，R1 完成不能称整个连接模块完成。

## 原生终端

上游 `modules/t3-terminal/README.md`：iOS GhosttyKit 自定义 I/O revision `cf8edc23f3a6a87a96e41a90013e89e987d34980`；Android libghostty-vt revision `3ff6d08fad56f2d6b81420a27bdc56ee707b453e`（`native/libghostty-vt/VERSION`）。上游 Android JNI/Canvas 不可直接链接为鸿蒙模块。

最小候选是保留 VT 引擎，使用鸿蒙 NAPI/XComponent 实现测量、渲染和输入桥接；需先独立交叉编译并验证头文件/ABI、依赖/许可、reflow/scrollback/颜色/宽字符。R0 未引入 Ghostty 新依赖或实现第二套终端。**可行性未闭合**：没有鸿蒙库产物及运行证明；不可承诺零移植成本。

协议 contracts/terminal.ts 区分 open/attach/observe/write/resize/clear/close、snapshot/event/sequence；UI 需分 terminal:read 和 terminal:operate。后续隔离原型验收：内存 VT 注入固定 ANSI/UTF-8/宽字序列→真机渲染/resize→独立 PTY 双向输入与重连；禁止向真实工作 shell 注入测试键。当前只有 S，无 D/R。

## 浏览器和设备预览

上游 browser `preview-stream.browser.ts/PreviewStreamWebView.tsx/BrowserTabMenu.tsx`、devices `device-stream.browser.ts/DevicePreviewRouteScreen.tsx`：原客户端用 WebView 运行流查看器；不能照搬成整个鸿蒙客户端网页。需要翻译原生壳和菜单，保留远程帧/控制/安全语义。MCP App/HTML 工具内容是额外安全边界，不能因禁用网页客户端而悄悄删除。

设备流明确 WebCodecs H.264 支持检测/不支持时 MJPEG；包括 host/tool version、触摸/键盘/设备命令。浏览器还涉及 tab、viewport、zoom、主题、音频/PiP、clear site data。候选：AVCodec 解码+XComponent Surface、图像解码 MJPEG、按展示缩放映射输入坐标、原协议鉴权与断线恢复。本机 SDK 有 `native_avcodec_videodecoder.h` 的 create/configure/setSurface；[华为 AVCodec 介绍](https://developer.huawei.com/consumer/cn/blog/topic/03223507219045298) 描述 Surface 输出。**仅接口存在，未测实际编码 profile/延迟/背压/音画/PiP**。

R6 前必须隔离验证同源鉴权帧源、H.264 profile/参数帧/关键帧、MJPEG、旋转/resize/输入回传及切后台释放，不发真实设备 shutdown。缺合法帧源和 native prototype，当前 S，D/R 阻塞。

## 通知、推送与系统入口

上游 `features/agent-awareness`、`settings/SettingsNotificationsRouteScreen.tsx`、modules/t3-agent-notifications 和 widget-expiry。iOS Personal Team 会缺推送/Live Activity，Android 原生支持也有能力门控；云账号与系统通知授权是两层条件。

本机 SDK 有 `notificationManager.requestEnableNotification/isNotificationEnabled/publish`，见 sdk-probes.json；[华为通知说明](https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/notification-kit-faq-0002) 涉及授权及系统设置状态。**本地 publish API 不代表离线推送通道已通**。当前工程 module.json5 仅 INTERNET，无相机/麦克风及分享/云回调 skill。

完整目标需要鸿蒙推送注册、服务端发送通道/账号绑定/撤销、Want 冷启动 env/thread 定位、通知类别/隐私/去重、权限拒绝、卡片/快捷入口等价。不能复用 APNs/Expo token 冒充鸿蒙 token。未核实华为项目/推送凭据与 relay 发送支持，当前阻塞；未弹权限窗、未注册设备、未发布通知。

## 原生模块全清单（固定源码，S）

| 模块 | 原职责/迁移检查 | 当前鸿蒙差距/门槛 |
|---|---|---|
| t3-agent-notifications | Android 原生 Agent 通知及后台投递 | 推送/通知适配、点击定位、注销清理 |
| t3-composer-editor | 原生编辑器、选择/粘贴/上下文与键盘 | TextInput 不能自动证明行为等价；需 IME/附件粘贴验证 |
| t3-highlights | Nitro 高亮桥接 | 不可加载 RN Nitro；原生高亮/语言与大文件性能 |
| t3-native-controls | 控件/菜单/布局/媒体/文件呈现/键盘及 DPoP native crypto | 逐 API 翻译至 ArkUI/Kit，平台分支不直接搬代码 |
| t3-review-diff | 原生 Diff 行选取/渲染 | 行号/选区/评论范围/高亮、原生性能 |
| t3-source-text | 原生源码文本 | 选取/复制/字体/大文件/无障碍 |
| t3-terminal | Ghostty surface/输入/resize | 交叉编译、渲染/IME/协议真验 |
| t3-voice-transcription | 平台语音/录音与路由 | 端侧可用性、远端转写/音频许可和中断 |
| t3-web-socket | 原生 WS/生命周期行为 | 现有 @ohos.net.webSocket 是部分实现，重连/协议/后台边界需对照 |
| t3-widget-expiry | widget/live activity 到期处理 | 系统卡片过期/后台更新/注销清理 |

外部模块同样属于范围：Clerk、Camera、Audio/Video、Image/Document Picker/FileSystem/Sharing、SecureStore/SQLite、Notifications/Widgets/QuickActions、Network/Linking、Clipboard/Haptics、PDF、Markdown/math、高亮、keyboard/gesture/screens、安全区域等；精确 import 与调用位置见 native.json/actions.json。不能只迁完这 10 个目录就算系统能力齐全。
