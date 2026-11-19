# T3 Code Harmony

基于 ArkTS + ArkUI 的 T3 Code 鸿蒙原生客户端，连接电脑或服务器上的 T3 Code，Agent 在服务端运行。目标为整个原版移动端迁移。

专用 Mate60Pro 已可直连服务、管理会话、发送任务、审阅文件与 Git 变更，并使用远端终端和浏览器。项目当前在补齐 R6–R8 的功能和逐页真机验收。

**开发已暂停并进入移交。** [开发交接](docs/开发交接.md) · [全部测试过程图库](docs/handoff/index.html)

## 手机上怎么用

| 要做的事 | 从哪里进入 |
|---|---|
| 开始任务或继续会话 | 首页右上角「新任务」，或点已有会话。输入框下方可选模型和发送方式。 |
| 管理连接环境 | 点首页左上角「T3 Code」打开环境管理。 |
| 从系统分享导入附件 | 在文件管理器或相册选择文件 → 分享 →「T3 Harmony」。在「导入分享」中审阅，图片可点「查看图片」，确认目标后存为草稿。已真机验证图库单张 PNG 的分享、预览和草稿恢复。[图片分享实测](docs/evidence/r8/batch38/README.md) |
| 用中文口述草稿 | 聊天输入区「工具 → 语音输入」，结束识别后加入输入框。 |
| 操作远端终端或浏览器 | 进入已有会话，点右上角「更多」，选择「终端」或「浏览器预览」。 |
| 调整源码和 Diff 阅读字号 | 首页齿轮，搜索「代码」。支持 8–18 号和长行自动换行。 |
| 添加项目或设置克隆目录 | 首页搜索框旁的齿轮 →「项目 → 添加项目」或「源码管理」。 |
| 为某个项目单独设置工作树 | 齿轮 →「工作树 → 项目级覆盖」，选择环境和具体项目。 |
| 创建停用的定时任务 | 首页齿轮 →「定时任务 → 新建任务」。选择项目后可指定目标会话。 |

## 开发文档

- [整体进度与下一步](docs/development-status.md)：统一状态入口，2026-11-19 第三十九批宿主测试 537/537 通过。
- [完整迁移计划](docs/full-mobile-migration-plan.md)：R0–R8 范围与验收标准。
- 阶段记录：[R0](docs/r0-delivery.md) · [R1](docs/r1-progress.md) · [R2](docs/r2-progress.md) · [R3](docs/r3-progress.md) · [R4](docs/r4-progress.md) · [R5](docs/r5-progress.md) · [R6](docs/r6-progress.md) · [R7](docs/r7-progress.md) · [R8](docs/r8-progress.md)。
- 对照索引：[能力矩阵](docs/r0-mobile-capability-matrix.md) · [路由台账](docs/r0-route-ledger.md) · [UI 记录](docs/ui-refresh.md)。
- 历史资料：[旧开发规划](docs/development-plan.md) · [阶段一](docs/phase-one.md) · [阶段二](docs/phase-two.md) · [阶段三](docs/phase-three.md)。

- [设备调试常亮](docs/device-keep-awake.md)：系统级开关，应用重装期间仍保持亮屏。

## 开发与验证

独立 HarmonyOS Stage 工程，当前目录尚未初始化 Git。既有构建记录使用 DevEco Studio 6.1.1 / API 24，真机记录含 Mate 70 Pro 与专用 Mate 60 Pro（系统 7 / API 26）。

```sh
node --experimental-strip-types --test tests/*.test.mjs
./scripts/build.sh
```

页面、聊天、Markdown 与 Diff 使用原生 ArkUI。终端、云连接及远程预览按完整计划独立验证。临时配对与服务状态须在续调前重核；测试通过不能替代真机及完整功能验收。

上游：[官方仓库](https://github.com/pingdotgg/t3code) · [用户 fork](https://github.com/DASungta/t3code)。固定参考提交及实际联调版本见阶段记录。
