# Step 6 深色主题令牌对齐、对比度修复与旧颜色清理真机验收证据

- **验证设备**：Mate60Pro（`23E0224122000135`，`1260x2720`）
- **数据源**：只读隔离服务端样本（`/tmp/t3-r5-accept-00fcea`）
- **静态扫描**：`rg -n "app\.color\.(surface|selected|canvas|composer|on_primary)\b|quietButton" entry/src/main/ets/ entry/src/main/module.json5` → 0 处残留（`LEGACY_EXIT:1`）
- **单元测试**：`node --experimental-strip-types --test tests/*.test.mjs` → `tests 562`、`pass 562`、`fail 0`（含新增 [tests/theme-tokens.test.mjs](../../../../tests/theme-tokens.test.mjs)）
- **签名 HAP（SHA-256）**：`2b5d311778477db636abcf28ecbf94d7831f866c83206ae9a6e54bdff2d3f475`

## 变更摘要

1. **删除 5 个未用旧令牌**（浅/深色 `color.json` 对称保留 58 个令牌）：`canvas`、`surface`、`selected`、`composer`、`on_primary`。
2. **对齐 9 个深色令牌值**：
   - `start_window_background` `#121214` → `#0a0a0a`
   - `ink` `#f4f4f5` → `#f5f5f5`
   - `muted` `#a1a1aa` → `#838383`（`card` 上 `4.98:1`，`group` 上 `4.55:1`）
   - `border` `#2e2e33` → `#262626`（对齐 `docs/design/style-guide.html`，保证 `#1a1b1b` 分组底描边可见）
   - `border_subtle` & `separator` `#B3191919` → `#B3262626`（70% `border`）
   - `primary` `#6f9bff` → `#346bf1`（修复 `on_primary_fill` `#ffffff` 在 `primary` 上的对比度从 `2.69:1` 提升至 `4.65:1`）
   - `primary_text` `#4b7cf3` → `#5585f5`（修复 `primary_text` 在 `info_bg` `#121b34` 上的对比度从 `4.44:1` 提升至 `4.92:1`）
   - `danger` `#ff8a8a` → `#ff6467`（`card` 上 `6.54:1`，`danger_bg` 上 `5.95:1`）
3. **SVG 与深色文本对比度回归修复**：
   - `dark/media/status_run.svg` 描边 `#6f9bff` → `#5585f5`；`dark/media/status_danger.svg` `#ff8a8a` → `#ff6467`。
   - `ThreadList.ets`、`DiffLineNumber.ets`、`SettingsPanel.ets`、`FormRow.ets`、`MarkdownView.ets`（2 处）共 6 处文本/高亮改用 `primary_text`。
   - `ArchivePanel.ets` 左滑删除按钮改为 `danger` 文字 + `danger_bg` 底（`5.95:1`）。
4. **文档与防回归测试**：
   - 更新 `docs/design/README.md` §1、§3、§5，并与 `tests/ui-state.test.mjs`、`tests/theme-tokens.test.mjs` 联动校验全部关键配色组合满足 WCAG AA（≥ 4.5:1）。

## 真机深色验收截图（共 7 张）

| 截图 | 页面 | 验收要点 |
|---|---|---|
| [after-dark-settings.jpeg](./after-dark-settings.jpeg) | 设置 | `separator` `#B3262626` 清晰、`深色 ✓`（`#5585f5`）、字号按钮 `#262626` 边框 |
| [after-dark-scheduled.jpeg](./after-dark-scheduled.jpeg) | 新建定时任务 | 星期按钮 `8vp` 圆角 + `#5585f5` 字 + `#346bf1` 边框、高对比白色主按钮 |
| [after-dark-home.jpeg](./after-dark-home.jpeg) | 首页对话 | `#0a0a0a` 页面底、`#111111` 卡片与 `#262626` 描边、`#f5f5f5`/`#838383` 层次 |
| [after-dark-usage.jpeg](./after-dark-usage.jpeg) | 用量 | `刷新`（`#5585f5`）、`Progress` 进度条（`#346bf1`）、`#262626` 描边 |
| [after-dark-chat.jpeg](./after-dark-chat.jpeg) | 会话详情 | `#161616` 用户气泡、工作记录分割线、滚底浮钮与输入框 `#262626` 描边 |
| [after-dark-files.jpeg](./after-dark-files.jpeg) | 文件与源码 | 分段边框 `#262626`、`#B3262626` 行分割线与 `42vp` 徽章列对齐 |
| [after-dark-git.jpeg](./after-dark-git.jpeg) | Git 状态与提交 | `刷新` / `分支` `#5585f5`、次级按钮与 `#838383` 副标题清晰 |
