# Step 3 真机验收：会话页重构

日期：2026-11-19  
设备：Mate60Pro（`ALN-AL80` / `23E0224122000135`）  
连接环境：隔离服务 `127.0.0.1:47895`（`/tmp/t3-r5-accept-00fcea`，仅只读拉取会话快照与输出，未发送任务或改动服务端数据）  
宿主测试：`node --experimental-strip-types --test tests/*.test.mjs` — **551/551 通过**（含新增 `tests/thread-activity.test.mjs`）  
签名构建：`./scripts/build.sh` — `BUILD SUCCESSFUL`  
HAP SHA-256：`4689c68e9bb05d63426d7a8124b22c33a68787e6dde8626d8684e16e0ce0f0bb`

## 前后对照

| 视图 | 截图 | 验证结论 |
|---|---|---|
| 改造前（浅色会话） | [before-chat-light.jpeg](before-chat-light.jpeg) | 顶栏右上角显示文字「状态」；每条消息右侧常驻 `···` 按钮；短消息气泡拉满宽且两侧留有较大余白；活动行仅为 `↓ 命令 · completed · exit 0` 纯文字；底栏为矩形蓝灰大发送按钮且顶部工具条直接暴露 `模型与选项` |
| 改造前（深色会话） | [before-chat-dark.jpeg](before-chat-dark.jpeg) | 深色旧版对照（常驻 `···`、宽气泡、`状态` 文字按钮与旧输入区） |
| 改造后（浅色会话） | [after-chat-light.jpeg](after-chat-light.jpeg) | 顶栏显示返回图标、会话标题与 `r5-round2 · 奋斗的iMac Pro` 副标题、可点击 `>_` 终端图标按钮（启用态不置灰）与 `···` 菜单图标；去除每条消息常驻 `···`（长按触发 Copy/Share 菜单）；短用户气泡 `1` 右侧紧凑贴合内容；单行描边工具行清晰呈现 `Preparing workspace` 与绿色 `exit 0`；圆角输入区底部胶囊左对齐显示 `+` / `模型 ⌄` / `工具` / `自动` / `队列`（不展示具体模型名） |
| 工具行展开态 | [after-chat-tool-expanded.jpeg](after-chat-tool-expanded.jpeg) | 点击 `Preparing workspace` 展开输出卡片，等宽输出 `Workspace preparation completed.` 左对齐展示，下方紧凑横排提供 `复制输出` 与 `引用为上下文` 按钮 |
| 新任务草稿页 | [after-chat-draft.jpeg](after-chat-draft.jpeg) | 顶栏为 `新任务`（草稿态不展示终端图标）；工作区选择器展示 `奋斗的iMac Pro >` 与 `当前 checkout · main >`；空状态居中引导与新版圆角输入区正常，`模型 ⌄` 不暴露具体模型名称 |
| 改造后（深色会话） | [after-chat-dark.jpeg](after-chat-dark.jpeg) | `#0a0a0a` 深色背景下顶栏、用户气泡、描边工具行、绿色 `exit 0`、深色输入框与胶囊按钮均对比清晰、无遮挡 |

## 实测中发现并修复的问题

1. 首轮真机检查发现底部 `ButtonType.Normal` 胶囊与 `Scroll` 默认居中对齐导致输入区按钮偏方且未贴左：已统一改为 `ButtonType.Circle` / `ButtonType.Capsule` + `Scroll().align(Alignment.Start)`。
2. 首轮重装后顶栏终端按钮 `>_` 在异步会话快照到达后仍呈半透明禁用态（`@BuilderParam` 与非响应式 `client.threadCwd()` 读取未触发刷新）：已改回内联渲染并在 `Index.ets` 新增响应式 `@State threadTerminalEnabled`，在 `watch()` 与 `update()` 同步更新后终端按钮正常点亮。
3. 首轮工具行展开输出文本与 Markdown 横向滚动块在短文本时居中对齐：已在 `ThreadActivity.ets`、`MarkdownView.ets` 及 `Index.ets` 上下文/附件横向 `Scroll` 补全 `.align(Alignment.Start)`。
4. 验收结束后已通过真机设置页恢复浅色外观并截屏核验，同时停止临时隔离服务进程并清理设备端/本机临时文件。

## 范围说明

- `RequestCard`（审批卡使用 `warning_bg`/`warning_border` 底纹、并排「拒绝本次」与蓝色「允许本次」主确认按钮，密钥/问答卡使用规范卡片令牌）已完成重构并通过 `./scripts/build.sh` 编译及 `tests/request-card.test.mjs` 全部用例校验；当前只读隔离测试会话中无挂起的实时审批请求，未产生真实拦截态抓图。
