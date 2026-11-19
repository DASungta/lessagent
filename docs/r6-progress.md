# R6 终端与远程预览

## 真机进度

| 路径 | 已验证 | 仍待验收 |
|---|---|---|
| 终端 | 多会话、选字复制、调字号后的行列数、交互式 less、两轮持续输出。[分页](evidence/r8/batch27/README.md) · [持续输出](evidence/r8/batch28/README.md) | 更多全屏程序、外接键盘、长时间负载与重连 |
| 浏览器 | 多标签、导航、固定尺寸和逐标签缩放，真实网页点击与复位。[尺寸](evidence/r8/batch20/README.md) · [缩放](evidence/r8/batch29/README.md) · [双查看者控制交接](evidence/r8/batch30/README.md) | 只读授权、Agent 接管、完整 profile、剪贴板、音频与 PiP |
| 设备预览 | Android 竖屏画面及点按、拖动、输入、导航。[设备记录](evidence/r8/batch6/README.md) | Android 横屏投影与触控、iOS 宿主 |

当前安装包和全量测试数见[整体开发进度](development-status.md)，逐项退出条件见[R6–R8 清单](r6-r8-acceptance.md)。

## 历史交付记录

2026-11-18。首批为**原生基础终端实现，未验收**。尚未达到完整交互终端或 R6 退出标准。父会话负责最终公共入口接入、构建和设备验证，本记录不预先声明通过。

## 本批交付

- `protocol/Terminal.ts`：原生有界 VT 网格，按字符与颜色保存屏幕；支持 CR/LF/BS/Tab、换行滚屏、CSI 光标移动/定位/保存恢复、清屏/清行、基础 ANSI 8 色及跨消息控制序列。支持常见中文宽字与拆包代理对；不支持的控制序列明确标记，不声称完整 Ghostty 等价。
- `components/TerminalPanel.ets`：ArkUI Canvas 网格，不是日志列表/WebView。连接按钮接真实 `terminal.attach`；显式命令发送、Ctrl C、Tab、上箭头、共享 PTY resize；结束 shell 需确认，普通返回只取消订阅。输入失败不自动重发，要求重连核对；订阅按线程/终端身份校验、序列去重与缺口保护，重连用服务器快照重建。
- 默认 40 × 24 提高手机可读性，支持按宽度适配。协议尺寸仍按上游 1000 × 500 校验，但当前渲染器限制 240 × 100，遇到过大共享网格明确报错，防止大网格阻塞 UI。
- 组件不自行选择环境或创建会话，由父级绑定现有环境的 T3Client 与 threadId/cwd。没有本地持久化命令或终端输出，没有向真实工作 shell 发送测试命令。

## 固定上游依据

直接从 `docs/baselines/t3code-ad1b136.tar.gz` 读取：

- `packages/contracts/src/terminal.ts`：attach/observe/write/resize/close、snapshot/events、UTF-16 写入上限 65536、序列及尺寸约束。
- `apps/mobile/src/features/terminal/NativeTerminalSurface.tsx`：真实原生 surface、输入、resize、渲染器桥接接口。
- `packages/contracts/src/preview.ts`、`device.ts`：远程 preview session 与设备服务契约。

## 接入契约

`TerminalPanel` 需要 `threadId`、`terminalId`（默认 `term-1`）、`onBack`，以及以下回调：

- `attach(size, resume, receive, failed)` 返回取消订阅闭包。调用 `terminal.attach`，传入 threadId/terminalId/cwd/cols/rows/resume/maxHistoryBytes。必须回传流失败/完成状态；旧 `watchRpcStream` 吞异常的默认行为不能直接作为终端断线处理。
- `write(data)`：用 `terminalInput` 校验后调用 `terminal.write`，不重试。
- `resize(size)`：校验后调用 `terminal.resize`。
- `closeTerminal()`：`terminal.close` 必须包含 terminalId 和 `deleteHistory:false`，不能因省略 terminalId 误关整组会话终端。

连接与操作须遵循 terminal:read/terminal:operate 权限及连接代际检查；不允许旧页面把输入发到新环境连接。

## 本次验证

`node --experimental-strip-types --test tests/terminal.test.mjs`：3/3 通过。覆盖拆分 ANSI/UTF-16、覆盖写/颜色/中文宽字/清屏、OSC 不泄漏正文、滚屏/resize、异常控制参数和尺寸/输入边界。此结果只是宿主算法测试。

未单独构建、安装或操作共享设备，避免与父会话竞争。最终构建及真机结果应由父会话追加。

## 首批未完成项（历史；第二批更新见文末）

1. 基础 shell 命令真实双向收发、中文输入、resize、断线快照恢复、结束回读、键盘遮挡和深色/大字体必须在隔离服务与专用机验证，当前不标通过。
2. 原生 Ghostty 尚无鸿蒙库/ABI/渲染校准产物。当前 VT 子集没有 alternate screen、scroll regions、完整 SGR/true color、复杂字素与完整键盘模式，不适合宣称 vim/top 等全屏程序可用。Canvas 读屏、选区复制、回滚历史、多终端管理和逐键 IME 还需完成。
3. 浏览器/设备远程预览尚未实现：已有 contracts 不能替代流解码。需对上游 `preview-stream.browser.ts` 与 `device-stream.browser.ts` 的鉴权、帧头、H.264/MJPEG、输入坐标/旋转和回压逐项移植并实测；不能用静态截图或打开远端 localhost 链接冒充远程交互。
4. 基础终端先帮助完成小命令操作，不以本批替代 R6 全量迁移，后续仍按完整计划补齐。


## 第二批：常用 shell / TUI 控制序列与有界渲染

本批只修改 `Terminal.ts`、`TerminalPanel.ets`、`tests/terminal.test.mjs` 与本文。父会话已报告首批真机 attach/echo 通过；本子任务未重新操作设备。

### 已实现

- zsh 常见模式：`?2004` bracketed paste 状态、`?25` 光标显隐、`?1` application cursor（箭头使用对应 CSI/SS3）、`?6` origin 与 `?7` 自动换行；`ESC(B` 字符集恢复和常见 prompt SGR 不再产生错误的 unsupported 提示。Bracketed paste 只追踪模式，本批没有冒充系统粘贴协议完成。
- `?1049h/l` 真正切换正常/备用屏幕，恢复正常屏幕内容、光标及样式；两屏 resize 均限制在 240 × 100。备用屏退出不把 TUI 输出残留到 shell 屏幕。
- 上下滚动区域、反向索引、origin-relative 光标移动、插入/删除行及字符、擦除字符、延迟自动换行。宽字覆盖会清除相邻占位格；基础组合重音能附着前一格。
- SGR 基础/高亮 16 色、256 色、RGB truecolor、粗体/暗色/下划线/反色/隐藏及 reset。Canvas 先绘制全部背景再绘制字形，避免中文宽字右半被下一格背景覆盖。**保留真机校准 `vp2px(14)` 字号与 8.4 × 20 网格**。
- DEC 线框字符集；OSC 标题读取，工作目录/超链接/提示符 metadata 安全消费，不执行剪贴板或文件操作。未知 DCS/APC 等字符串吞至 ST 且标记不支持，不把其载荷泄露为可见文字。
- DSR 光标/状态、主 DA、文本网格尺寸查询应答。`feed(history, false)` 禁用历史应答，只对 live output 回答。父级通过 `terminal.write` 的 `reply:true` 接入服务端多查看器去重；失败不自动重试。
- 输入区保留回车命令发送，增加 Esc、下箭头、Enter 与“仅发文字”模式，方便显式发送 TUI 命令；输入仍是用户确认发送，未自动执行输入框中的内容。

### 安全与回归

- 每次 feed 最多 1 Mi UTF-16 字符，显示缓冲仅两屏、不无限累计历史；CSI 缓冲 128 字符、OSC 等字符串缓冲 256 字符。
- 实时查询队列最多 16 项；控制序列与清屏等累计渲染工作量有上限，异常时停止订阅并提示重连。批量 clear-screen 测试证明不会以短控制序列触发无界全屏重绘。
- 15/15 宿主测试通过：保留首批输入/scope/可选快照回归；新增常见 zsh、备用屏恢复与 resize、滚动区/固定标题、颜色属性、宽字与线框、拆包 OSC/ST、有界历史、查询与历史应答禁用、插删与自动换行、恶意清屏工作量保护。
- 协议依据仍为固定上游 `contracts/terminal.ts`；控制序列语义对照 [XTerm Control Sequences](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html)。测试检查屏幕内容和状态变化，而不是仅断言警告消失。

### 最新剩余边界

- 本批仍须真机复验 zsh 正常 prompt、中文/样式、备用屏进入退出、resize/重连、查询应答、键盘遮挡和 TUI 输入；不把 15 项宿主测试当作 vim/less/top 真机验收。
- 尚非完整 Ghostty 等价：没有文本 reflow/scrollback、鼠标报告、复杂 emoji/ZWJ、全部 SGR/OSC 查询、图片协议与所有私有模式（例如旧 `47/1047` 备用屏形式）。未知控制序列仍显示限制提示。光标形状/闪烁请求以当前静态光标呈现。
- Canvas 读屏、选区复制、多终端管理、逐键 IME、系统粘贴包装与完整硬件快捷键仍待实现/验收。resize 为裁剪/扩展屏幕，不把历史自动重排称为实现。
- 浏览器/设备远程 H.264/MJPEG 流尚未实现，完整 R6 继续保持未关闭。

## 第二批联合真机结果

258/258 测试、签名构建与最终包安装通过，详见 [第二批证据](evidence/r8/batch2/README.md)。本记录区分已真机路径与仅宿主测试路径，不代表阶段全量完成。


## 第三批：浏览器连续 JPEG 画面与双向输入

### 实现范围

- `protocol/Preview.ts`：帧/尺寸/控制消息限额，远端 viewport 与本机 contain 布局坐标转换、鼠标/按键/导航协议构造、服务端控制权校验。
- `services/PreviewStream.ets`：Harmony NetworkKit WebSocket 接 `/api/preview-stream/ws`，每个二进制消息是一张 JPEG。使用 ImageKit `ImageSource → getImageInfo → createPixelMap` 连续解码、更新画面与 ACK；不是静态截图轮询，也不使用 WebView。
- `components/PreviewPanel.ets`：远端 URL、连接、连续帧计数、原生 Image 画面、控制权取得/释放、点击、手势滚动、文字/Enter 输入、后退/刷新。远端网页在服务器 Chromium 运行，localhost 指远端主机。
- 用户返回只停止本机流和释放解码资源，不擅自关闭远端标签页。`initialTabId/onTab` 让父级保存同线程已创建标签，重连不重复创建；连接失败后由用户手动重连取得新票据，不自动重放页面写操作。

### 鉴权与资源边界

- 固定上游 `state/deviceHubAccess.ts` 要求每次建立流获取新的 media ticket；父级已实现 `T3Client.previewStreamUrl`，路径 `/api/auth/websocket-ticket/media`，沿用当前 Bearer 或云 DPoP，校验环境/连接代际，不使用 RPC ticket 替代。
- ticket 仅用于 WebSocket 连接，不写入持久化、日志或错误文字。旧 socket 的消息/关闭回调、环境切换后的输入、迟到的解码帧全部被连接代际/isCurrent 阻断。
- 每帧 ≤2 MiB，解码前读取尺寸，单边 ≤1920、面积 ≤2073600；父级请求 720 × 1280 帧。解码最多一张进行中、一张最新等待，替换等待帧时 ACK 旧帧，成功显示后 ACK 当前帧；不堆积所有历史画面。
- 界面最多保留当前和上一张 PixelMap，停止时释放；解码结束后若连接失效，立即释放结果。JSON 控制消息 ≤65536 字符，输入 ≤16384 序列化字符，文字输入 UI ≤4096 字符。
- 只有服务端 `control.canOperate=true` 才能请求控制权；普通输入还必须 `controller=you`。切换控制者不保留待发送的输入。当前不自动处理系统剪贴板、下载或文件上传。

### 父级接入与真实服务条件

`PreviewPanel` 接入：

- `createTab(url)` → `preview.open({threadId,url,runtime:'server'})`，返回 `PreviewSessionSnapshot.tabId`；按 `preview:operate` 权限门控，失败结果未知时不自动重试创建。
- `streamUrl(tabId)` → 当前连接 `previewStreamUrl(threadId,tabId)`；每次重连重新申请票据。
- `isCurrent()` → 环境实例/线程仍与打开页面时一致；`initialTabId`/`onTab` 保存该线程标签页；`onBack` 关闭面板。

固定归档源码核对了 `contracts/preview.ts`、`contracts/rpc.ts`、`client-runtime/preview/serverBrowserStream.ts`、`state/deviceHubAccess.ts`、mobile `preview-stream.browser.ts`、server `PreviewBrowserHost.ts`。

真实验收需隔离 T3 服务能够启动 `runtime:'server'` 浏览器、可用的 headless Chromium 与宿主依赖；Linux sandbox/libraries 条件不足可能以 4503 关闭流，需由运维配置正常浏览器运行条件，不通过客户端关闭沙箱绕过。测试页面应包含持续变化的计数/动画、输入框和点击按钮，从手机回读浏览器 DOM/计数验证动态帧与输入，而非只留一张截图。

### 本批检查与未完成

`node --experimental-strip-types --test tests/preview.test.mjs`：7/7 通过。测试包含纯协议/坐标及**实际 PreviewStream 适配器代码**，注入 NetworkKit/ImageKit 替身验证多帧解码/ACK、仅最新待解码帧、迟到帧释放、解码异常/尺寸超限、权限撤销和旧 socket 不重放输入。替身结果不是鸿蒙真实解码或服务联调验收。

本子任务未构建、安装或操作设备；需父会话补真实动态页、点击/滚动/输入、控制权变化、断线与重新取票、最大字体/深浅色/键盘的设备证据。

尚未实现：浏览器完整标签管理/关闭、网页对话框、文件上传/下载、系统剪贴板、音频/PiP、按键组合/拖拽/选择；设备 H.264/MJPEG 远程预览与设备操作仍未实现。不能以本批浏览器 JPEG 路径声明整个 R6 完成。


### 第三批真机与关闭操作补充

父会话已完成专用机连续 52 帧、点击后 `Clicked 1` 与文字输入 `PREVIEW-INPUT-OK` 的真实页面回读；本子任务未独立复验该设备路径，具体截图/服务证据由父会话归档。

新增“关闭远端页面”按钮，确认后调用父级 `closeTab(tabId)` → `preview.close({threadId,tabId})`。只有成功且环境/线程/标签仍一致才停止流、清空 tabId 并通知 `onTab('')`；超时/失败不重试、不假装关闭，保留标签供核对。返回仍只断流保留页面。父级可通过 `preview.list` 恢复同线程标签，并传 `initialTabId/initialUrl`。

预览测试更新为 9/9：新增执行实际面板关闭方法的成功/失败、不重试、旧标签与迟到回包隔离回归。此关闭按钮的最终构建/真机确认由父会话执行。

## 第三批联合真机结果

276/276 测试、最终签名包构建和安装通过。连续预览/点击/输入/重启恢复/关闭，以及系统分享→独立草稿→重启恢复已实际验证；范围与清理见 [第三批联合证据](evidence/r8/batch3/README.md)。阶段整体仍未关闭。


## 第四批：普通 iOS Simulator MJPEG 与输入

### 实际实现

- `protocol/DevicePreview.ts`：独立设备协议，不与浏览器帧协议混用。multipart/x-mixed-replace 边界解析，支持任意网络分片、多帧、可选 Content-Length、结束边界；每帧 ≤4 MiB、帧头 ≤8 KiB、单批 ≤32 帧。
- `services/DevicePreviewStream.ets`：NetworkKit `HttpRequest.requestInStream` 持续接收 HTTP multipart JPEG，ImageKit 连续解码；最新等待帧覆盖旧帧，最多一张正在解码。解码前检查单边 ≤4096、面积 ≤1000 万像素，并将解码结果最长边缩至 ≤1920。不是截图轮询。
- 独立 helper WebSocket：收到 `0x82 + JSON` 更新屏幕配置；只有 `0x83` 准入且屏幕配置未声明 inputUnavailable 才发送操作。HID touch `0x03`、home/app_switcher `0x04`、Enter/Esc/Tab/Backspace 等按键 `0x06`、orientation `0x07`。
- `components/DevicePreviewPanel.ets`：原生动态画面与帧计数、单指触控/拖动、主屏幕/应用切换、旋转、基础按键。按原版 orientation 映射显示旋转与归一化输入坐标，屏幕尺寸/方向更新时中止旧手势，等待新帧。没有虚构 iOS 任意文字输入（原版也只支持 HID）。
- 输入队列最多 32 项，仅合并相邻 move，不重放 begin/end/按键；失败明确提示。环境/目标失效、旧 HTTP/WS 回调与迟到解码结果均受代际保护。返回只断开本机流，不调用 shutdown/结束远端设备。

### 父级接入

`DevicePreviewPanel`：`deviceName`、`hostLabel`、`platform`、`getAccess():Promise<DeviceStreamAccess>`、`isCurrent()`、`onBack()`。`DeviceStreamAccess` 包含 `mjpegUrl` 和 `inputUrl`。

父级先用 `device.list` 选择设备并以 `device.open({threadId,hostId,deviceId,platform})` 创建/恢复该线程设备会话，再进入面板；每次连接仅获取新 media ticket，不重复 boot/修改会话。父级须按目标身份与访问权限门控。

使用 `device.list` 返回的 `hubBasePath`；以选定 hostId 的票据构造：

- HTTP：`{httpBase}{hubBasePath}/vendor/serve-sim/helper/{encodedDeviceId}/stream.mjpeg?hostId=…&wsTicket=…`
- WS：`{wsBase}{hubBasePath}/vendor/serve-sim/helper/ws?device={encodedDeviceId}&hostId=…&wsTicket=…`

`DeviceHubProxy.ts` 明确读取 hostId 并在转发前移除；不能把远程 host 当本机。票据仅留内存，不打印完整 URL；媒体/输入连接分别取得新 media ticket，不以 RPC ticket 代替。真实请求保留 TLS 校验且禁用重定向，不关闭安全校验来绕过服务配置。

### 支持条件与当前阻塞

固定原版 `client-runtime/device/stream.ts` 的 MJPEG fallback 只适用于普通 iOS `serve-sim`；普通 Android `serve-emu` 是 H.264，不能套 JPEG 路径。Simlock、Expo 等宿主可能仅允许 WebRTC，HTTP 409 / 非 multipart 时明确显示不支持，不冒充帧流成功。

本批父会话实际发现仅有 local Pixel_6_API_30 Android 11；iOS 探测报 `xcrun unable to find utility simctl`，没有可用 iOS Simulator。未安装大型 Xcode，未创建假设备。因此 iOS 画面/HID/旋转为**已实现未真验**，不是验收完成。

### Android H.264 最小原生路径核查

固定上游 `device/stream.ts` 使用 `/vendor/serve-emu/ws?device=…&frame-meta=1`。二进制 SEMU 包可带 16 字节头（magic/version/key flag/PTS），负载为 Annex-B access unit；首次需 SPS/PPS 与 IDR，收到 JSON `video-session` 后销毁旧 decoder、请求关键帧并按新尺寸配置。原版无 Android MJPEG fallback。

本机 SDK `native/sysroot/usr/include/multimedia/player_framework/` 已确认：

- `native_avcodec_videodecoder.h`：`OH_VideoDecoder_CreateByMime`、`RegisterCallback`、`SetSurface`、`Configure`、`Start`、`PushInputBuffer`、`RenderOutputBuffer`、`FreeOutputBuffer`。
- `native_avbuffer.h`：`OH_AVBuffer_GetAddr/GetCapacity/SetBufferAttr`。

工程当前没有 `entry/src/main/cpp`、CMake 或 NAPI 视频桥。最小下一步是建立 decoder 生命周期与缓冲队列的 NAPI 模块，把 Annex-B 数据/PTS 放入可用 AVBuffer，渲染到 XComponent/NativeWindow；验证关键帧恢复、旋转尺寸变化、丢帧与背压、切后台释放、宿主重连、物理像素/触控坐标。上述只是已核查的 SDK 条件，**尚无 native 库产物或真实 H.264 解码结果**，不能声称 Android 设备预览已可用。不得以 Android 周期截图替代此视频路径。

### 检查与剩余验收

`node --experimental-strip-types --test tests/device-preview.test.mjs`：5/5 通过，包含实际服务适配器代码注入 NetworkKit/ImageKit 替身：连续两帧与旋转调用、二进制 HID 准入与载荷、旧连接/环境隔离、multipart 分包/限额/错误。未执行本轮构建/安装或设备操作，统一交父会话。

待真实 iOS host 补：连续动态帧、单指拖动、home/app switcher、键盘、四方向坐标、断网/票据过期/准入拒绝、旋转中断与资源释放。H.264/WebRTC、折叠多屏/hinge、真实设备与所有原版设备动作仍未完成；完整 R6 保持未关闭。

### 第四批设备选择与票据路径校验

`DevicePickerPanel.ets` 已接独立只读 `device.list({inspectOnly:true})`，显示主机平台可用性/原因、设备名称/版本/启动状态。只有 host kind 为 local/ssh、platform=ios 且明确 physical=false 的模拟器启用“打开”；Android 显示 H.264/WebRTC 尚未接入，其他云宿主/真机/未知主机均不进入假的画面。

组件参数：`connection:T3Client`、`threadId`、`onOpen(device:DevicePreviewChoice,hubBasePath,hostKind)` 与 `onBack`。真正的 `device.open` 和两个新媒体票据由父级处理。

`safeDeviceHubBase` 只接受 `/api/` 下由字母、数字、下划线和连字符构成的相对路径，拒绝绝对 URL、协议相对 URL、编码路径、双斜线、点段、反斜线、query/hash 和控制字符；在票据 URL 构造点必须再次校验，避免服务端返回路径将票据导向其他源。固定 `DeviceService.ts` 的路径为 `/api/device-hub`。

设备测试更新为 7/7，新增路径逃逸/外源注入、同 ID 跨主机隔离、平台/宿主/真机门控。选择页尚待父级统一构建与实际清单 UI 验证，iOS 实机路径仍缺宿主。

## 第四批联合真机结果

296/296 测试、最终签名构建与安装通过。本地通知完成与点击定位、常规特大字号/深色抽查、语音权限拒绝已实际验证。设备流和语音口述仍待所需条件；详情见 [第四批联合证据](evidence/r8/batch4/README.md)。


## 第五批：Android 原生 H.264 显示链路

### 已落地代码与配置

- `entry/src/main/cpp/decoder.cpp` / `CMakeLists.txt`：真实 NAPI 模块 `libt3device.so`，使用已安装 NDK 的 `OH_VideoDecoder`、`OH_AVBuffer`、`OHNativeWindow`，不是截图或软件假帧。
- `entry/src/main/cpp/types/libt3device`：本地类型声明与包描述。`entry/build-profile.json5` 添加 externalNativeOptions 指向该 CMake；`entry/oh-package.json5` 只添加本地 file 依赖，无新增外部下载依赖，未改签名或根工程配置。
- `protocol/AndroidVideo.ts`：SEMU 16 字节头/版本/时间戳、Annex-B NAL 扫描、SPS/PPS/IDR 提取、baseline/high profile SPS 分辨率和裁剪解析、关键帧附带参数集。
- `services/AndroidDeviceStream.ets`：独立 serve-emu WebSocket，首次等待 SPS/PPS/IDR，`video-session` 或 SPS 变化时销毁旧 decoder 并重建；按原版发送 `reset-video` 请求新关键帧，失败不自动重连。
- `components/AndroidDevicePanel.ets`：XComponent Surface，按视频尺寸 contain 布局；显示 native render 回调统计的真实渲染帧数、丢帧和错误。当前仅只读视频，不伪装完整触控已完成。
- DevicePicker 对普通 local/ssh Android Emulator 启用“原生 H.264 只读（待真机验证）”，iOS 仍走独立 MJPEG 组件；WebRTC-only/真机/未知宿主继续禁用。

### 原生执行与资源边界

NAPI `start(surfaceId,width,height)` 返回 session epoch，独立工作线程建立 NativeWindow、配置/启动系统 AVC decoder。`push(epoch,ArrayBuffer,pts,key)` 仅验证并拷贝到有界队列；缓冲填充与 PushInputBuffer 在 worker 上，RenderOutputBuffer 在 codec 回调上，不在 ArkUI 线程执行解码。UI 每 250 ms 读取统计。

每包 ≤4 MiB、队列最多 8 帧且 ≤12 MiB、输入 slot 最多 64。背压时清队列并等待下一 IDR，不继续喂丢依赖后的 P 帧。`stop(epoch)` 和旧连接消息均有代际限制，先使旧回调失效，再由工作线程 Stop/Destroy codec 和释放 NativeWindow；不会无限保留旧 Surface 或压缩帧。

屏幕最大单边 4096/面积 1000 万像素；时间戳要求安全整数。NAPI 错误给出阶段错误/错误码，不包含票据或帧内容。Native 生命周期、硬件 profile 支持、输入 buffer 容量、Surface 比例及旋转仍必须在真机校准。

### 父级接入与构建

`AndroidDevicePanel` 参数：`deviceName`、`hostLabel`、`getStreamUrl():Promise<string>`、`isCurrent()`、`onBack()`。父级先选择设备并完成 `device.open`，按 platform 路由，取新媒体票据构造：

`{wsBase}{safeHubBase}/vendor/serve-emu/ws?device={encodedDeviceId}&hostId={encodedHostId}&frame-meta=1&wsTicket={freshMediaTicket}`

依旧在票据构造前验证 `safeDeviceHubBase`。父级先使用现有 ohpm 解析本地 `file:./src/main/cpp/types/libt3device`，再执行现有 `scripts/build.sh`。NDK/CMake 均使用本机 DevEco 所带工具，不需要下载新第三方 SDK。子任务未执行 native 或 HAP 构建，也未操作共享设备，避免竞争。

### 本次测试与验收边界

`tests/android-video.test.mjs` 4/4 通过：本机已安装 ffmpeg 生成无内容黑帧的 baseline 320×240 / high 640×360 Annex-B fixture（合计约 1.7 KiB，无真实设备/用户数据）；验证真实参数集与裁剪尺寸、SEMU 时间戳/边界、实际 AndroidDeviceStream 代码等待参数/IDR、重建、背压恢复及环境/旧 socket 隔离。测试执行时不需要 ffmpeg。

这四项测试使用 native API 替身，**不代表硬件解码或 native 线程生命周期已验收**。下一步由父会话完成本地依赖解析/原生编译、Harmony 安装与 Android Emulator 动态帧显示、视频尺寸变化、返回/重进/断连/销毁和长时间资源回读。触控、按键、旋转控制与 WebRTC 路径仍未在本批接入。

### 第五批首连修复：配置与 Surface 调用顺序

父会话首连收到视频包并调用 native.start，但真机日志报 `OH_VideoDecoder_SetSurface: Video decoder set output surface failed`。原顺序在 Configure 前设置 Surface，已改为 RegisterCallback → Configure → SetSurface → Prepare → Start，与[华为视频解码指南](https://developer.huawei.com/consumer/en/doc/HarmonyOS-Guides/video-decoding/) 的 Surface 初始化顺序一致。

同时保留首个 native 根因及 API 阶段/返回码；push 拒绝时优先显示 `nativeVideo.stats().error`，不再被“会话已失效”覆盖。新增实际服务适配器错误传播回归，Android 视频测试更新为 5/5。该修复未由本子任务构建/运行，等待父会话复验。

### 第五批真机结果与后台释放补验收

父会话已验证 Configure → SetSurface 修复后，Mate 60 Pro 显示 Android Settings 真实动态画面：渲染计数 12 → 129、0 丢帧；Pixel 6 切换搜索页时鸿蒙画面同步；返回再进入显示 48 帧、0 丢帧。证据：[首帧修复](evidence/r8/batch5/android-native-fixed.jpeg)、[远端页面变化](evidence/r8/batch5/android-native-changed.jpeg)、[重新进入](evidence/r8/batch5/android-native-reopen.jpeg)。当前只读，触控/HID 不包含在此结论内。

2026-11-19 生命周期补丁：AndroidDevicePanel、PreviewPanel、DevicePreviewPanel 均监听 `t3Foreground`，进入后台立即断流、停止 native decoder/计时器、释放 PixelMap 与输入队列；返回前台只提示手动连接，不自动恢复媒体连接或重发操作。新连接闭包同时检查 foreground 与目标身份，旧异步回调不得改写当前画面。

AndroidDeviceStream.current 当前实现已在 owner 失效时主动 fail/stop；补充实际适配器回归确认：已有 native session、owner 失效且无任何新帧时，250 ms watchdog 仍关闭 socket、清 timer 并调用 native stop。另执行三个实际 Panel 的后台处理方法，验证资源释放与不自动恢复。Android 视频测试更新为 7/7，与浏览器 9 项合计 16/16；此后台补丁的最终安装/设备回归仍由父会话完成。


## 第六批：Android 触控、按键、文字与旋转

### 固定协议与准入

核对固定 `client-runtime/device/stream.ts`、`contracts/device.ts`、server `DeviceHubProxy.ts`、`RpcAuthorization.ts` 与 `DeviceActions.ts`：

- 普通 serve-emu 复用视频 WS。触控为 `{type:'touch',action:'down'|'move'|'up',x,y}`，坐标归一化至 0..1；Back/Home/最近任务为 `{type:'back'|'home'|'recents'}`；Enter 为 `{type:'key',keycode:66}`；文字为 `{type:'text',text}`，单包最多 300 UTF-8 字节、最多 64 包。
- Android 在经过鉴权的 WS upgrade 成功后即输入准入，没有浏览器的 takeControl/控制者协议，也没有 iOS 0x83 包。服务端设备流 upgrade 和 `device.action` 都要求 `orchestration:operate`。客户端每次出站还校验 owner、前台状态、scope 与 decoder epoch。
- UI“开启控制”是本机显式操作开关，不声称取得服务端独占锁。原版此路径未提供浏览器式多查看器仲裁，其他已授权查看器仍可能操作同一设备。
- Android 旋转不走猜测的 WS rotate 包，走 `device.action({hostId,deviceId,type:'setOrientation',value})`；固定服务实现确实支持 Android 并设置模拟器加速度传感器方向。

### 已实现与接口

`AndroidDevicePanel` 新增 `canOperate():boolean` 和 `setOrientation(value:string):Promise<void>`，父级分别绑定当前 owner/权限和真实 device.action RPC。保留原 `prepareConnection/getStreamUrl/isCurrent`。

首帧由 native render 回调确认后，用户可显式开启控制。屏幕点击/拖动经过 contain/letterbox 映射，黑边不产生 down；拖动出界时夹紧到 0..1，取消/多指/抬起均结束当前单指。远端编码器已按旋转后的尺寸发送画面，Android 不再次套 iOS 的方向变换。

输入序列由服务层串行发送，最多 64 项，仅合并相邻 move；绑定视频 epoch，尺寸变化时取消旧队列并在原 socket 尽力发送 up。后台/返回关闭也先释放原连接已按下的触点，再关闭 WS（最多等待 250 ms），不在替换连接上重放 down/move/up。失败只提示结果未知，不自动重试。

文字完整按 Unicode code point 拆为 ≤300 字节，超过 64 包整批拒绝，不静默截断；部分已发送后失败明确要求核对，不自动补发。UI 文字最多 4096 UTF-16 字符。Back/Home/最近任务/Enter 都使用原版明确字段。

旋转前结束触控并关闭本地控制开关；RPC 成功仅表示请求完成，要求观察新画面后重新开启控制。`video-session` 与新 SPS 触发原 decoder 重建和坐标更新，避免旧尺寸手势继续发送。

### 本次检查与边界

Android 视频/控制测试更新为 11/11，涵盖实际适配器输入准入、原版 JSON 包、scope 撤销、后台原 socket 抬手、move 合并/取消与旧 decoder epoch 隔离，以及纯坐标映射、300 字节 UTF-8 拆包和过限拒绝。保留已有硬解协议、后台无帧 watchdog 和 native 错误传播测试。

未改 native C++，未构建或操作设备；父会话统一构建与 Harmony 验证，真实 Android 动态显示的既有结论保持，新增触控/按键/文字/旋转不得在真验前标完成。多指、硬件组合键、输入法差异、跨查看器并发及各种应用锁定方向仍待专项验收；WebRTC 和 iOS 宿主阻塞不因此解除。

### 第六批触摸校准与文字真验

父会话发现按钮控制有效而画面点击未到达目标，已把 onTouch 从 Stack 父层移到实际 hitTestBlock overlay，自身 onAreaChange 测量触摸区域；归一化不再混用父层坐标。实际 Panel 的 Down/Up 映射和黑边拒绝回归已补，Android 测试 12/12。

父会话真机复验：normalized≈(0.485, 0.069) 点击进入 Android 搜索，鸿蒙输入 `battery` 后远端搜索框/结果出现相同文本，148 帧、0 丢帧。证据：[Android 点击与文字](evidence/r8/batch6/android-input.jpeg)。临时数值 hilog/import 已全部移除，保留 overlay 修复与测试；拖动、旋转等剩余路径由父会话继续验收。


## 第七批：浏览器多标签与前进（待真机验收）

`PreviewPanel` 新增当前会话标签选择、更新、新建和前进按钮。列表来自 `preview.list`，仅接受当前 thread 的 server runtime；标签 ID 为空、过长、控制字符或重复时拒绝整份结果。切换只释放旧媒体连接并清空待输入文字，保持远端页面打开，显式点击连接后由服务端报告控制权状态。新建先显示空地址，点击连接才调用原有 `preview.open`，不会因点“新建”立即创建空页面。

沿用固定上游 `packages/contracts/src/preview.ts` 的 `sessions/navStatus` 与 `packages/client-runtime/src/preview/serverBrowserStream.ts` 的 `{type:'history',delta:-1|1}`；前进仍受服务端控制权和当前作用域约束。列表刷新晚到、后台或环境变化时丢弃，失败保留当前标签；确认当前标签已在远端关闭才断开并清除选择。列表标题是最近一次列表快照，可用“更新”读回，尚未订阅导航元数据。

父级接入新增 `listTabs:()=>Promise<PreviewTab[]>`，用 `previewTabs(result,threadId)` 解析 RPC 结果并在请求前后验证原连接/线程。无需改流服务或媒体票据格式。

验证：`node --experimental-strip-types --test tests/preview.test.mjs` 12/12，包括线程/runtime隔离、无效/重复ID、前后历史线格式、切换断流且不关闭/接管、后台拒绝选择、刷新迟到隔离与失败保留。尚未运行整包构建或多标签手机视觉/前进真实页面验收，由父会话统一完成。


### 第七批导航地址与标题读回修复

父会话真机已验证前进/后退画面及双标签切换，发现地址仍停留在手输 URL。固定上游媒体 WS 没有导航状态包；`ServerBrowser.report` 写入 PreviewManager，通过主 RPC `subscribePreviewEvents` 发布 `navigated/opened/resized/failed/closed`，因此没有向 `PreviewStream` 编造新协议。

Panel 新增 `watchTabs(changed):stop`，由父级限定连接与线程后订阅真实事件。事件触发串行 `preview.list` 回读标题/URL；读回中再次收到事件，只排队一次新读并丢弃旧快照，不阻塞媒体输入、不重发任何导航命令。后台、切换标签、返回和重新连接取消旧订阅，旧回调不能修改新界面。当前地址只有未聚焦且没有未提交编辑时跟随服务端；导航提交或新建成功后恢复同步，创建期间新输入的地址仍保留。

预览专项测试现为 14/14，新增地址编辑保护、标题随真实读回更新、事件突发合并、迟到事件取消。整包构建和修复后的地址真机验收仍由父会话完成。

第七批父级最终验收：344/344 全量测试与安装通过，多标签/历史导航/地址同步和编辑保护已真机复验；标题、地址、画面一致的证据见 B7。地址保护按实际改值而非仅聚焦判断。测试页面已清理，初始空白页元信息边界仍保留。

## 下一批终端多会话契约核对（未实现）

没有 terminal.list。订阅 subscribeTerminalMetadata 的 snapshot.terminals / upsert.terminal / remove(threadId,terminalId)，按当前线程隔离；列表未知不当作空列表。新建使用客户端唯一终端 ID（不超过 128 字符），避免多客户端 term-N 冲突。Index 当前五处 term-1 必须一起改为捕获的目标 ID，切换只取消 attach 订阅、清旧画面及应答队列，不关闭 shell。

terminal.attach 的 resume:true 保留退出状态；但未知 ID 加 cwd 仍可能启动 shell，不是纯只读恢复。只观察应使用 terminal.observe（terminal:read）；创建/写/resize/close 需要 terminal:operate。terminal.close 必须传 terminalId，省略会操作整个线程；deleteHistory:false 保留历史但 metadata 移除，不能宣称关闭后仍能从列表恢复。显式重启使用 resume:false、restartIfNotRunning:true 和 cwd。验收需 A/B 各自输出、切换重进、结束 A 不影响 B、失败不重放，以及共享 PTY 尺寸边界。

### 终端多会话实现（下一批，待整包与真机验收）

已按上述固定契约实现 TerminalPanel 的会话列表、唯一 ID 新建、选择、恢复连接、明确确认重启和单目标结束。列表用 snapshot/upsert/remove reducer；只接受当前线程，状态/ID/重复项校验，upsert 原位替换避免活动更新导致选项顺序抖动。列表未加载或订阅失败保留旧信息但禁用新建/连接，明确提示更新；不猜测存在 term-1。

新建只准备 `term-N-UUID`，用户点击连接才启动 shell。切换取消旧 attach、清画面、草稿和查询应答队列，不关闭远端任务；attach/write/reply/resize/close 全部显式传入捕获的 terminalId，迟到回调不会更新另一会话。结束确认只关闭确认时选中的 ID，已退出的终端也可结束并移除列表；失败不重试。后台取消输出及 metadata，回来手动更新/连接。

只读入口依赖父级按权限选择 terminal.observe；Panel 的 canOperate 阻止新建、重启、写入、调整、结束，并且解析查询序列后不发送 DSR/DA 应答。父级负责 T3Client 中 metadata 失败传播、owner/线程隔离与 RPC 权限校验。

专项验证：`node --experimental-strip-types --test tests/terminal-sessions.test.mjs tests/terminal.test.mjs` 25/25 通过。新增实际 Panel 状态测试覆盖双会话切换隔离、列表未知/失败、新建显式启动、输入与应答目标、迟到失败、单目标关闭/退出后关闭、只读无写入、后台取消，以及 reducer 更新顺序。保留所有原 VT 测试。

本段仅记录实现与单测；未由本子任务构建 HAP、操作设备或确认真机视觉。普通 attach 恢复未知 ID 仍可能启动 shell；关闭后历史保留但 metadata 移除、共享 PTY 尺寸、完整 VT/TUI、滚回/选区/实体键盘仍保持原有边界。

第九批父级结果：371/371与安装通过，选择/历史恢复/结束单目标已部分真验。47895退出中断最后B续输及清理，详见 [B9](evidence/r8/batch9/README.md)，不能标全项通过。

## 下一批：终端滚回与复制计划（尚未实现）

已只读检查当前 TerminalPanel/TerminalGrid 及 B9 terminal-b-list、terminal-a-restored 真机截图。当前 Canvas 仅绘制 grid.cells；内容移出主屏后即丢弃，没有滚回或复制入口。下一批最小完整路径如下：

- 在 TerminalGrid.scroll() 的正常主屏、全屏区域、向上滚动时保留移出的渲染行；不把备用屏、局部滚动区、反向滚动和插删行混入普通 shell 历史。保留历史行时固定其文本和样式，避免后续网格修改污染已保存内容。完整 VT 的更复杂滚动区语义另行补齐，不声称该范围等价所有终端。
- Panel.draw() 读取“有界历史 + 当前屏幕”的可见窗口，Canvas 垂直手势只滚动本地查看窗口，不发远端方向键。增加“回到底部”入口；阅读旧行时新输出不强制跳底。使用累计行位置/淘汰计数维持阅读锚点，不能仅用当前数组长度差判断新增行（满容量后长度不变）。历史已淘汰时夹紧位置并提示，光标只在包含当前屏幕的位置绘制。
- 复制从解析后的可见文本导出，不能 regex 去除原始 ANSI 或复制 snapshot.history。宽字符占位不重复、hidden 单元格输出空白，保留中间空格；记录软换行与显式换行区别，避免长命令被复制出伪换行。复制入口可打开固定文本快照，使用原生可选文本/复制能力，避免另写 Canvas 选区手柄；在显示该快照期间输出继续进入网格但不改变用户正在选择的文本。父级增加 onCopy(text):Promise<void>，复用现有 pasteboard 写入，失败由本页显示。
- alternateScreen(true) 不清主屏历史，也不向历史追加全屏应用重绘；alternateScreen(false) 恢复主屏查看语义。reset() 在切换/新快照/重启时清历史，receive(snapshot) 维持“reset → resize → feed(history,false)”且不回答历史查询，不能再额外追加 raw history。ED2(clearScreen) 保留滚回；ED3 当前是无操作，需要改成只清历史。resize 不承诺旧行重排，历史保留原始行宽及换行标志。

建议首批预算：历史最多 500 行，同时最多 64,000 单元格和 256 Ki UTF-16 文本单元；任一超限按整行淘汰，超限状态可见。当前/备用屏仍受 240×100 上限约束。复制快照另设 256 Ki UTF-16 上限，超过时明确提示或要求缩小范围，不静默截断；避免同时保留完整 raw ANSI、历史单元格和无上限的第二份文本日志。上述计数是数据结构上限，不是假定 ArkTS 对象固定字节数，实际堆占用需真机观察。

另外发现现有 put() 对 U+0300–U+036F 会反复 `cell.char += char`；攻击性组合字符跨多次 feed 可无限累积，单次 1 MiB feed 上限及每批 2,000,000 工作量不能约束这个生命周期内存。实现有界滚回前应给单元格文本设置明确上限（例如 128 UTF-16 单元），超过后停止追加并标记不支持/受限；覆盖跨批输入测试，不把截断伪装为完整字形支持。

原重连请求 maxHistoryBytes=524288 只约束服务快照，不是无限历史或分页接口；旧服务可能忽略它，现客户端 feed 上限继续保留。新滚回只能恢复收到的快照窗口，不能把重新连接当成读取所有旧行。历史 replay 与实时输出共用容量预算，保持 sequence 去重/断档断开及旧终端 generation 隔离。

验收：单测覆盖超屏顺序、软/硬换行复制、宽字符/hidden、备用屏不污染、ED2/ED3、resize、快照重放不重复/不回查询、行/字符双重淘汰、跨批组合字符限制及阅读锚点。真机用编号输出超出一屏，上滚读取并复制核对；持续输出时停留旧行、返回底部；进入/退出备用屏、切换A/B和重连后无串行；常规特大字体下滚动/选择/复制入口可用，长时输出观察堆内存趋于稳定。此节仅方案，未新增代码、未执行设备测试。

组合字符内存边界已修复：单元格最多128个UTF-16单元，超限标记unsupported且继续处理后续输入。26项终端专项通过，含跨批1万组合字符、宽字符和备用屏；构建安装通过，长时真机堆观测尚未执行。滚回/复制仍待实现。证据见 [单元格边界](evidence/r8/batch9/terminal-cell-bound.json)。

## 第十批：有界滚回与可见页复制

已实现主屏历史500行/64000单元格/256Ki文本三重预算，备用屏隔离、ED2/ED3及reset重放；复制从渲染单元格导出，处理软换行/宽字符/隐藏文本且超限拒绝。Panel新增上页、下页、回到底部、复制本页，持续输出维护阅读锚点，切换/重连清阅读位置；通过父级显式剪贴板回调显示成功/失败。终端三组38/38通过，签名构建成功。旧行不重排，完整VT与真机长输出/剪贴板验收尚待完成。

B10后续视觉检查（gpt-6.2-sol）：模式按钮“发送并回车”应改成清楚的附带回车开关文案；复制反馈应与历史位置同时展示；运行中重连按钮降低主视觉权重。均为下一批待修改，不称已修复。

B20联合结果：417项测试和构建安装通过，手机viewport/点击通过；平板首帧成功但后续解码保护失败，桌面未验。标签与临时服务已清理，下一步测量真实帧尺寸/失败阶段。见 [B20](evidence/r8/batch20/README.md)。

B20补帧修复完成：实测同流高分辨率静态JPEG，采用独立源上限与有界降采样、实际输出核对。420项回归通过，平板和桌面尺寸及点击计数真机复验通过，测试资源已清理。见B20最终段。

B21部分文字选择已完成真机主路径：原生长按BETA复制并粘贴精确BETA，未发送；测试终端清理。40项相关测试及构建通过，跨行/大字/读屏等待验。见 [B21](evidence/r8/batch21/README.md)。


B24 已交付会话首页操作调整和终端字号。字号 14→15 的远端尺寸、设置保留，以及浅色标准字号和深色特大字号首页已通过 Mate60Pro 验收。全量测试 436/436。[本批证据及剩余范围](evidence/r8/batch24/README.md)


B26 验证了终端局部双向滚动、同尺寸适配后的边界保持，以及新版聊天的消息操作、深色特大字号输入区。446/446 全量测试通过。[B26 记录与真机截图](evidence/r8/batch26/README.md)


B27 已接入五项项目工作树覆盖，以及终端翻页和左右方向键。Mate60Pro 验证项目远程起点保存、草稿消费、另一个项目继承、恢复，以及真实 less 搜索/翻页/退出。[本批证据与范围](evidence/r8/batch27/README.md)


B28 上线全局源码管理设置、项目管理中的添加入口，已验默认目录及分层克隆目标的实际表单消费。终端补验两轮持续输出、冻结快照和历史上限。462/462 全量测试通过。[本批证据](evidence/r8/batch28/README.md)


B29 加入每标签缩放、首次无画面时的单次媒体重接与超限补帧处理。0.1.10 复位原比例需明确确认，已用真实网页尺寸与点击计数验收。最终全量 479/479。[真机记录](evidence/r8/batch29/README.md)
