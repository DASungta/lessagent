# Step 5b 补漏与旧样式清理真机验收证据

- **验证设备**：Mate60Pro（`23E0224122000135`，`1260x2720`）
- **数据源**：只读隔离服务端样本（`/tmp/t3-r5-accept-00fcea`）
- **静态扫描**：`rg -n "app\.color\.(surface|selected|canvas|on_primary)\b|quietButton" entry/src/main/ets/` → 0 处残留（`LEGACY_EXIT:1`）；`rg -n "body:\s*\(\)|trailing:\s*\(\)"` 仅剩 `FormRow.ets` 组件定义
- **单元测试**：`node --experimental-strip-types --test tests/*.test.mjs` → `tests 559`、`pass 559`、`fail 0`
- **签名 HAP（SHA-256）**：`51fb74b51d728d9aa911144f030c4f07c918c6a0e6db323b0abfb8192e306352`

## 修复清单摘要

1. **P0 修复**：
   - `Index.ets`：移除全屏面板容器外层 `8vp` 左右留白并替换 `$r('app.color.canvas')` 为 `$r('app.color.group')`，消除开发面板两侧白边；移除 `@Extend(Button) function quietButton()` 及 3 处调用。
   - `TerminalPanel.ets`：统一底部第一/二排按钮的 `.enabled(...)`、`.opacity(... ? 1 : Opacity.disabled)` 与 `Sizes.hairline` 禁用态。
2. **P1 迁移与旧令牌清理**：
   - 清理全部 12 处 `app.color.surface`、1 处 `app.color.selected`、1 处 `app.color.canvas` 与 `on_primary`/`quietButton` 引用。
   - 完成 `ShortcutCard.ets`、`PreviewPanel.ets`、`ShareImportPanel.ets`、`AddProjectPanel.ets`、`ProjectWorktreeSettingsPanel.ets`、`SourceControlSettingsPanel.ets` 公共组件与 Theme 令牌迁移；同步更新 `tests/{preview,share-preview-ui,projects}.test.mjs` 导入裁剪规则。
   - `SettingsPanel.ets` 3 处开关（工作中分组、使用最近项目、代码自动换行）统一接入 `FormRow({ kind: 'switch' })`；同步更新 `tests/settings.test.mjs`。
   - `ScheduledTasksPanel.ets` 星期胶囊改为 `ButtonType.Normal`，并将 `.border({ ..., radius: Radius.tool })` 与 `.borderRadius(Radius.tool)` 调整至 `.border(...)` 之后以保留 `8vp` 圆角（同类选中态描边顺延修复：`RequestCard.ets`、`ReviewPanel.ets`、`PullRequestsPanel.ets`）。
3. **P2 视觉打磨**：
   - `FilesPanel.ets`：对齐文件夹图标与文件徽章 `42vp` 左槽位，搜索按钮改为 `AppButton({ kind: 'text' })`。
   - `PullRequestsPanel.ets`：嵌入态标题字重与页边距对齐 `UsagePanel`，搜索按钮改为 `kind: 'text'`。
   - `GitPanel.ets`：仅在 `insertions > 0` / `deletions > 0` 时渲染 diff 计数，去除 `+0`/`-0` 噪音。
   - `UsagePanel.ets`：`resetLabel` 格式化为 `YYYY-MM-DD HH:mm`。

## 真机截图索引（共 11 张）

| 截图 | 主题 | 验收要点 |
|---|---|---|
| [after-files-light.jpeg](./after-files-light.jpeg) | 浅色 | 两侧无白边、文件夹/徽章 `42vp` 对齐、`搜索` 按钮清晰 |
| [after-git-light.jpeg](./after-git-light.jpeg) | 浅色 | 两侧无白边、无 `+0 -0` 噪音 |
| [after-terminal-light.jpeg](./after-terminal-light.jpeg) | 浅色 | 两侧无白边、底部两排按钮禁用态统一 |
| [after-pulls-light.jpeg](./after-pulls-light.jpeg) | 浅色 | 嵌入态头部边距与字重统一、`搜索` 按钮清晰 |
| [after-usage-light.jpeg](./after-usage-light.jpeg) | 浅色 | 重置时间显示为 `YYYY-MM-DD HH:mm` |
| [after-settings-switches-light.jpeg](./after-settings-switches-light.jpeg) | 浅色 | `工作中分组` / `使用最近项目` 统一为 `FormRow` 开关 |
| [after-scheduled-weekdays-light.jpeg](./after-scheduled-weekdays-light.jpeg) | 浅色 | 修复 `.border()` 后重置圆角问题，`8vp` 圆角与描边生效 |
| [after-add-project-light.jpeg](./after-add-project-light.jpeg) | 浅色 | `TopBar` + `GroupCard` 迁移效果（未点创建保存） |
| [after-dark-scheduled.jpeg](./after-dark-scheduled.jpeg) | 深色 | 深色模式下星期 `8vp` 圆角与蓝框选中态清晰 |
| [after-dark-git.jpeg](./after-dark-git.jpeg) | 深色 | 深色下无边缘条带、卡片层次清晰 |
| [after-dark-files.jpeg](./after-dark-files.jpeg) | 深色 | 深色下无边缘条带、文件图标列对齐 |
