# R8 可用性与视觉改进

## 视觉验收入口

| 页面 | 建议先查看的真机证据 | 覆盖范围 |
|---|---|---|
| 会话首页 | [新版首页](evidence/r8/batch24/sessions-after.jpeg) · [深色特大字号](evidence/r8/batch24/sessions-dark-large.jpeg) | 搜索、筛选、新任务和设置入口 |
| 聊天与输入 | [改动前](evidence/r8/batch26/chat-before.jpeg) · [改动后](evidence/r8/batch26/chat-after.jpeg) · [键盘展开](evidence/r8/batch26/composer-large-ime.jpeg) | 消息操作、正文密度、发送和工具栏可达性 |
| 文件搜索 | [定位前](evidence/r8/batch33/before.jpeg) · [系统特大字号下的命中行](evidence/r8/batch33/largeFont.jpeg) | 命中行可见性、四位行号以及文件已变更时的反馈 |
| 工作树与源码管理 | [项目覆盖](evidence/r8/batch27/project-final.jpeg) · [源码管理特大字号](evidence/r8/batch28/source-control-large.jpeg) | 字段来源、开关状态、长文本和滚动 |
| 浏览器预览 | [缩放菜单](evidence/r8/batch29/largeMenu.jpeg) · [实际点击](evidence/r8/batch29/desktopRestoredHit.jpeg) | 系统字号、远端画面、点击位置及复位 |

平板、折叠屏、读屏、长时间性能及升级矩阵仍待覆盖。

当前安装包和全量测试数见[整体开发进度](development-status.md)，逐项退出条件见[R6–R8 清单](r6-r8-acceptance.md)。

## 历史交付记录

2026-11-18。状态：首批组件改进已实现；宿主请求卡回归通过，等待统一签名构建和真机视觉验收。尚未完成 R8 全量回归或发布验收。

## 本批范围

用户反馈现有 UI 难看，优先收口日常会话列表、项目选择和请求卡片；功能和服务端动作不删减。

已读取现有真实截图 `evidence/r4/batch3-device/r4b3-secret-card.jpeg` 与 `evidence/r5/device/round2/r5-maxfont-home.jpeg`。注意后一个文件名含 home，实际内容为 Mermaid 文件页，不能作为会话列表前后对照。原版对照读取固定归档解压出的 `PendingApprovalCard.tsx`（细边框、次要说明、分层操作），不声称已逐像素等价。

- `ThreadList.ets`：搜索框和操作区统一 44vp 触达尺寸，明确输入/标题前景色；标题 16sp、项目副标题 13sp；分组箭头使用既有线形 SVG，固定组移除误导的折叠箭头；分组提供数量/展开状态朗读；更多菜单包含会话名称；已完成分组使用中文；空项目筛选显示“所有项目”。
- `ProjectPicker.ets`：移除重复左右 padding，环境筛选和搜索分行避免长环境名挤压输入框；返回/添加/文件夹/草稿复用线形图标；统一 12vp 圆角和显式前景色，避免 Button 默认颜色污染项目标题；草稿删除增加触达尺寸和朗读名称。
- `RequestCard.ets`：标题/说明字号和颜色层级明确，卡内间距 10vp；次要动作和附件删除达到 44vp；秘密来源支持自动换行，避免横向溢出；保留密码模式、前后台清空、提交保护及全部拒绝动作。

调用入口均保留：Index 的 ThreadList、ProjectPicker、RequestCard 无需变更接口；未增加资源或依赖。首页与 composer 由主代理独立整合。

## 已执行检查

`node --experimental-strip-types --test tests/request-card.test.mjs`：2/2 通过，验证必填失败保留其他答案、修正后提交和自定义回答优先级。随后对共享工作树执行全部宿主测试：240/240 通过（包含其他并行代理已落盘测试，不作为本代理新增数量）。这些结果不证明 ArkUI 构建或视觉效果。

## 本批真机验收门槛

由主代理统一构建和使用专用机，避免并行覆盖安装。至少保存同一数据下的浅色/深色对照：

1. 会话列表：长标题、多环境/项目名、固定/进行中/已完成，检查截断、分组展开、搜索、更多菜单与返回。
2. 项目选择：长路径、草稿、临时任务、搜索空态，检查外层 16vp 对齐及最大字体下搜索可用。
3. 请求卡：审批长文、多问题/选项、秘密直接输入和来源，检查主次按钮、键盘遮挡、必填/拒绝/错误状态。
4. 默认与系统最大字体，深浅色切换；读屏顺序、按钮命名与触达；真实聊天发送→审批→回复回归。

验收后记录包 hash、设备、服务版本及截图路径，不用宿主测试或旧图替代。R8 性能、安全、平板/折叠布局、升级迁移与全能力回归仍待后续推进。

## 第二批：消息内容与工具输出

依据新真机截图 `evidence/r8/chat-dark.jpeg` 检查：工具记录居中且使用文本箭头，不像可展开的辅助记录。代码另发现未换行模式固定 20vp 行高/高度、工具详情最多 12 行静默截断，以及表格强制填满视口宽度。固定原版 `native/EnrichedMarkdownText.tsx` 与 `lib/wideMarkdownBlocks.ts` 将宽代码/表格与普通正文区别处理，当前沿用原生滚动方向处理，不引入 WebView。

已修改：

- `ThreadActivity.ets`：左对齐线形箭头和可多行标题，最小 44vp 触达，不再固定高度；完整工具输出在独立横向滚动容器中展示并可选择复制；错误/详情移除 12 行限制；复制和引用按钮统一 44vp。
- `MarkdownView.ets`：代码行去掉固定高度，保留空行最小高度，行高使用 fp 跟随系统字号；正文行高同样随字体缩放；代码/图表工具操作 44vp；表格以一致 160vp 列宽排布，内容可超过视口横向滚动，长单元格可换行；details 使用线形箭头和展开状态朗读。
- 保留原有代码换行开关、语法色、复制原文、链接/媒体、安全与解析逻辑。未更改 Index 消息气泡或复制行。

`node --experimental-strip-types --test tests/r4.test.mjs tests/r5.test.mjs`：24/24 通过。尚未运行构建/真机；须补长代码、空行、四列长表格、超过 12 行工具错误、最大字体及深浅色截图。超长输出渲染性能仍待专项，不把横滚修复当成性能验收。

## 第二批联合真机结果

258/258 测试、签名构建与最终包安装通过，详见 [第二批证据](evidence/r8/batch2/README.md)。本记录区分已真机路径与仅宿主测试路径，不代表阶段全量完成。


## 第三批：文件、Diff 与 Git

实际查看 `evidence/r8/batch2/markdown-light.jpeg`，文件顶栏在标题之外排列“更多/分享/保存”，挤压长文件名，且标题和副标题重复文件名。结合源码检查发现源码行固定 20vp 并用省略号丢掉长行，Diff 固定 22vp，Git 的两行文件名被 40vp 行高限制。

本批只修改 `FilesPanel.ets`、`ReviewPanel.ets`、`GitPanel.ets`：

- 三页返回复用 `ui_back`，44vp 触达、明确朗读名称，前景色跟随主题。
- 文件顶栏仅保留标题/目录与更多菜单，复制路径/文件评论/分享/保存全部保留在菜单中；目录使用已有线形文件夹与方向图标，文件使用可读类型标签替代 `¶/▸/·` 等符号；目录行自适应最小高度。源码行横向滚动，去掉省略号和固定 20vp，高度跟随字体。
- Diff 分支输入移到独立整行，不与模式按钮争宽；上下文件导航去除文字假箭头，统一次要操作底色；Diff 行使用 fp 最小高度与行高，仍保留选区/复制/评论。
- Git 提交采用主操作色，推送/拉取及组合提交采用次要底色，统一圆角与最小触达尺寸；改动行可自适应双行长路径；概览和提交页整体可滚动，避免最大字体或键盘挤掉错误/动作；分支用“当前/分支”状态文字。

`node --experimental-strip-types --test tests/r5.test.mjs`：16/16 通过。未改业务 RPC、写操作确认或自动重试规则。构建与真机仍由主代理执行；需验证文件菜单保存/分享、长文件名、源码横滚、Diff 选行、Git 键盘及深浅色/最大字体。

## 第三批联合真机结果

276/276 测试、最终签名包构建和安装通过。连续预览/点击/输入/重启恢复/关闭，以及系统分享→独立草稿→重启恢复已实际验证；范围与清理见 [第三批联合证据](evidence/r8/batch3/README.md)。阶段整体仍未关闭。

## 第四批配套：R7 原生语音草稿

父代理指定本代理实现独立语音输入，接口为 `VoiceInputPanel({ onInsert: (text) => ..., onBack: () => ... })`。调用方必须绑定打开时的环境/会话/草稿，切换目标关闭面板；onInsert 只进入可编辑草稿，不能自动发送。

- SDK 依据：本机 `@hms.ai.speechRecognizer.d.ts` 明确 `online: 1` 离线、`online: 0` 在线，`writeAudio` 接收 640/1280 字节。实现固定离线 `zh-CN`，设备引擎不可用即报错，不降级云端。AudioKit 16kHz/单声道/PCM16 从麦克风取得流，在内存按 640 字节分帧；不创建音频文件、不上传第三方。
- 原版依据：固定上游 `native/voiceTranscription.android.ts` 的本地转写与取消语义。Harmony 仅实现中文端侧输入，不代表原版环境转写器或全部语言等价。
- [华为官方识别指南](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/speechrecognizer-guide/) 与本机 SDK 核对了引擎监听、PCM 参数与音频写入方式。
- 只有用户点击开始才申请麦克风并启动；提供结束、取消、编辑和加入草稿。60 秒自动结束、引擎/最终结果超时；拒绝权限给出键盘与系统设置路径。后台/关闭撤销会话代际、停止并释放麦克风、丢弃迟到回调与录入文本，不恢复录音。
- 新文件：`protocol/Voice.ts`、`services/VoiceInput.ets`、`components/VoiceInputPanel.ets`、`tests/voice.test.mjs`。module 仅新增 MICROPHONE inuse 权限，string 仅新增理由。未改 Index、EntryAbility 或 T3Client。
- 测试 7/7：权限拒绝不录音、权限待决时后台取消且不自动恢复、PCM 边界拼接/末帧补零、分句部分结果替换、强制离线、取消后回调隔离/资源释放、初始化途中取消、重复完成回调。测试注入引擎/麦克风替身，未录真实音频。

待父代理统一构建与用户点击验证：设备是否提供离线中文模型、麦克风首次允许/拒绝、真实识别、取消和后台麦克风指示消失、编辑后插入正确草稿、无自动发送。未宣布语音真机验收完成。

## 第四批联合真机结果

296/296 测试、最终签名构建与安装通过。本地通知完成与点击定位、常规特大字号/深色抽查、语音权限拒绝已实际验证。设备流和语音口述仍待所需条件；详情见 [第四批联合证据](evidence/r8/batch4/README.md)。


## 第五批配套：S04 外接键盘

新增 `protocol/Keyboard.ts`、`components/KeyboardHelpPanel.ets` 和 `tests/keyboard.test.mjs`，不修改 Index/设置/EntryAbility；父代理负责接入。

最小命令：Ctrl/Cmd+F 搜索会话，Ctrl/Cmd+N 新任务，Esc 返回，Ctrl/Cmd+Enter 在消息输入框发送。普通 Enter 和 Shift+Enter 不派发命令，保留输入框换行。搜索/新任务/返回在编辑文字时不派发；所有命令在组合输入、后台、受限页面、忙碌或未知提交时禁用。发送仍必须通过既有发送函数检查，不能绕开状态/模型/队列规则。

固定上游核对 `HardwareKeyboardCommandProvider.tsx`、`SettingsKeyboardRouteScreen.tsx` 和 Android `T3KeyboardCommandsModule.kt`：原版有作用域命令和 Enter 行为配置；本批固定安全的 newline 行为，不新增发送偏好，也不宣称所有原版命令已迁移。

本机 ArkUI SDK 实际 API：

- `KeyEvent` 有 type/keyCode/keySource/deviceId，`getModifierKeyState` 只明确支持 ctrl/alt/shift。`metaKey` 表示按键状态，不是 Cmd 布尔值；没有 DOM 的 repeat/isComposing。
- `KeyboardCommands` 接收规范化输入，追踪左右 Meta 的 Down/Up（2076/2077）及重复按下。切后台、窗口失焦、断开键盘时 `reset()`，不同 deviceId 不共享组合键。
- TextArea `onChange(value, previewText?: PreviewText)` 或 `onWillChange` 的 `previewText.value` 用于组合输入状态；预编辑未完成时禁用命令，不能用空字符串正文猜测 composition。
- `onKeyPreIme`（API12）用于输入法前拦截，`onKeyEvent` 布尔回调与 `onKeyEventDispatch`（API15）可用于派发；只在实际处理命令时返回 true/停止冒泡，未匹配不能吞普通按键。同一事件不可同时在两个阶段重复调用 controller；必须收到释放事件。
- 搜索框/密码框/终端/其他弹层的焦点若无法可靠追踪，应将该作用域 `blocked=true`，不能默认按“无文本焦点”处理。失焦后须同步清除 composition。

父接入参数：`handle({keyCode, down, keyboard, deviceId, ctrl, alt, shift}, {foreground, composing, textFocused, composerFocused, blocked, busy, unknownSubmission, canSend, canSearch, canNewTask, canBack})` 返回空字符串或 `search/new-task/back/send`。帮助页只展示用户操作与适用条件。

6/6 宿主测试通过：允许/禁止命令、Enter不发送、composition/后台/忙碌/未知状态、其他修饰键与非键盘来源、重复Down、左右Cmd释放/reset/跨设备隔离。当前没有外接硬件；未验证蓝牙/USB键盘、系统保留Cmd、中文候选确认与实际焦点路由，不能称真机验收通过。

## 终端可见页选字

终端的「文字工具 → 选择文字」打开当前可见页的固定文本快照。长按文字可使用系统选区复制，也可点「复制全部」或「关闭选字」。「文字工具 → 复制本页」仍直接复制可见页。快照使用终端解析后的有界文本，实时输出继续绘制在底层画布；翻页、回到底部、切换终端、重连、后台或终端清屏会关闭选字。

终端相关宿主测试 40 项通过，覆盖实时输出期间快照不变、复制内容和迟到回调隔离。原生长按选区、部分文字复制和真机画布覆盖效果待验证。


### B23 后续：重连权限与页面恢复

连接成功自动读取权限、丢弃旧代次/旧请求结果，并将权限响应式传到两个工作树设置页。432/432回归及签名构建安装通过；Mate60Pro存储页后台往返自动恢复编辑、打开目录编辑并取消，无手动刷新和配置写入。见[evidence/r8/batch23/README.md](evidence/r8/batch23/README.md)。新增可编辑大字体和分支页独立后台矩阵待验。


B24 已交付会话首页操作调整和终端字号。字号 14→15 的远端尺寸、设置保留，以及浅色标准字号和深色特大字号首页已通过 Mate60Pro 验收。全量测试 436/436。[本批证据及剩余范围](evidence/r8/batch24/README.md)


B25 已验首页筛选空态、清除、冷启动保留、排序反馈与特大字号滚动。草稿切换工作区后保留关闭的远端起点。全量 441/441。[本批证据](evidence/r8/batch25/README.md) · [项目覆盖范围](worktree-project-overrides.md)


B26 验证了终端局部双向滚动、同尺寸适配后的边界保持，以及新版聊天的消息操作、深色特大字号输入区。446/446 全量测试通过。[B26 记录与真机截图](evidence/r8/batch26/README.md)


B27 已接入五项项目工作树覆盖，以及终端翻页和左右方向键。Mate60Pro 验证项目远程起点保存、草稿消费、另一个项目继承、恢复，以及真实 less 搜索/翻页/退出。[本批证据与范围](evidence/r8/batch27/README.md)


B28 上线全局源码管理设置、项目管理中的添加入口，已验默认目录及分层克隆目标的实际表单消费。终端补验两轮持续输出、冻结快照和历史上限。462/462 全量测试通过。[本批证据](evidence/r8/batch28/README.md)


B29 加入每标签缩放、首次无画面时的单次媒体重接与超限补帧处理。0.1.10 复位原比例需明确确认，已用真实网页尺寸与点击计数验收。最终全量 479/479。[真机记录](evidence/r8/batch29/README.md)


B31 文件源码和 Diff 支持独立字号、自动换行与紧凑行号。已实测长行复制、深色特大字号和会话工具入口。[真机记录](evidence/r8/batch31/README.md)


B32 已通过真实 PR 文件名、详情路径及大字号换行真机验收。读取完成后按 PR、项目、连接与请求序号检查身份。[实测与截图](evidence/r8/batch32/README.md)


B33 已验证内容搜索实际滚到源码命中行，复制保留整行原文与 Tab，失效命中单独提示。[真机截图与边界](evidence/r8/batch33/README.md)


B34 已验证未绑定任务的显式模型编辑、取消与还原。测试任务始终停用。[特大字号截图与数据库回读](evidence/r8/batch34/README.md)


B35 已验证定时任务绑定已有会话、未绑定首次运行创建的配置，以及特大字号的目标显示。[目标会话实测](evidence/r8/batch35/README.md)


B36 未绑定定时任务支持工作区选择；基准分支、本地起点、已有 checkout 的真实保存及失效重选已真机验证。[保存与恢复记录](evidence/r8/batch36/README.md)


B37 已真机验证系统文件管理器双 TXT 审阅、目标确认上传、附件草稿恢复与逐项移除。最终全量 532/532。[系统分享实测](evidence/r8/batch37/README.md)

B38 全量宿主测试 536/536。Mate60Pro 从系统图库分享一张 PNG，在审阅页主动查看本地缩略图。确认前无新增附件，确认后服务端新增 1 个附件，原图 2554 字节且 SHA-256 一致，消息始终为 6 条。杀进程重开后草稿恢复了同名图片，验收草稿已删除。点击首页「T3 Code」可展开环境管理面板。[B38 真机实测](evidence/r8/batch38/README.md)
