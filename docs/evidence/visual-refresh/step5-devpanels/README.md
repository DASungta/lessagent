# 第 5 步与方案 A 真机验收证据（研发 / PR / 用量 / 工具面板）

- **设备**：Huawei Mate 60 Pro（`23E0224122000135`）
- **环境**：隔离测试服务端 `/tmp/t3-r5-accept-00fcea`（`127.0.0.1:47895`，仅只读页面浏览与截图，未执行任何写操作或服务端命令）
- **测试**：`node --experimental-strip-types --test tests/*.test.mjs` — `559/559` 通过，`0` 失败
- **签名 HAP**：`entry/build/default/outputs/default/entry-default-signed.hap`
  - SHA-256：`da21bbe675727c91d01d885ab37a85b1c2425ad501f854f554c11ade32401bd3`
- **默认外观恢复**：验收完成后已在「设置 -> 外观」切回「浅色」模式。

## 改动范围

1. **方案 A（`bf7fcb6`）**：多选 / 选项选中态统一为轻蓝主题色（`info_bg` 底 + `primary_text` 字 + `1vp primary` 描边），保留单屏主提交按钮使用近黑 `prominent`。
   - `ScheduledTasksPanel.ets`（星期多选胶囊）
   - `RequestCard.ets`（Secrets Provider / Ask-user 选项）
   - `SettingsPanel.ets`（代码自动换行状态按钮）
2. **Step 5（研发、PR、用量与工具面板重构）**：
   - `TerminalPanel.ets`、`FilesPanel.ets`、`GitPanel.ets`、`ReviewPanel.ets`、`PullRequestsPanel.ets`
   - `UsagePanel.ets`、`QueuePanel.ets`、`ThreadExtrasPanel.ets`、`ComposerCommandPanel.ets`、`VoiceInputPanel.ets`
   - `PreviewPanel.ets`、`DevicePreviewPanel.ets`、`DevicePickerPanel.ets`、`AndroidDevicePanel.ets`、`ShareImportPanel.ets`
   - `Index.ets`（清理未使用的旧蓝色 `@Extend(Button) primaryButton`，将 `会话操作`、`附件预览`、`图片预览`、`粘贴结构化上下文` 弹层升级为 `TopBar` + `group`/`card` 分组卡片，并统一 `bindSheet` 背景与关闭栏）

## 截图索引

| 文件 | 页面 | 主题 |
| --- | --- | --- |
| `after-scheduled-weekdays-light.jpeg` | 新建定时任务（方案 A 轻蓝星期胶囊 + 单一黑底主按钮） | 浅色 |
| `after-usage-light.jpeg` | 用量页（分段时间窗 + 费用/Tokens 趋势与概览卡片） | 浅色 |
| `after-pulls-light.jpeg` | PR 列表页（分段筛选、内嵌搜索栏与收口加载态卡片） | 浅色 |
| `after-chat-tools-light.jpeg` | 会话页 `···`「会话操作」分组面板 | 浅色 |
| `after-files-light.jpeg` | 文件与源码（`r5-round2` 工作区目录与文件角标） | 浅色 |
| `after-git-light.jpeg` | Git 状态与提交（工作区状态卡内嵌操作按钮 + 改动文件列表） | 浅色 |
| `after-terminal-light.jpeg` | 终端（控制卡片、`附带回车：开` 轻蓝选中态与只读终端画布） | 浅色 |
| `after-devpanel-dark.jpeg` | Git 状态与提交（卡片对比度与按钮层次验证） | 深色 |
