# Step 4 真机验收：设置与表单面板视觉重构

日期：2026-11-20  
设备：Mate60Pro（`ALN-AL80` / `23E0224122000135`）  
连接环境：隔离服务 `127.0.0.1:47895`（`/tmp/t3-r5-accept-00fcea`，仅只读浏览界面与配置状态，未发送或保存服务端修改）  
宿主测试：`node --experimental-strip-types --test tests/*.test.mjs` — **559/559 通过**（含 `tests/native-client.test.mjs` 新增的过时非挂起恢复会话保护单测）  
签名构建：`./scripts/build.sh` — `BUILD SUCCESSFUL`  
HAP SHA-256：`5712eb6809d8f98085b73e41d11a35c2f10e701929c750d8a458a781be4c76e5`

## 真机验收视图

| 视图 | 截图 | 验证结论 |
|---|---|---|
| 设置主页（浅色） | [after-settings-light.jpeg](after-settings-light.jpeg) | 顶部圆角搜索栏与分组镶边卡片（`group` 底、`card` 白卡 + `1vp` 分割线），`环境 5` / `项目 3` / `归档会话 0` 实时计数与勾选态对号一致 |
| 设置主页（深色） | [after-settings-dark.jpeg](after-settings-dark.jpeg) | 深色分组卡片、次级标题与蓝色勾选/状态值对比清晰，无白框或截断 |
| 环境面板（浅色） | [after-connections-light.jpeg](after-connections-light.jpeg) | `TopBar` 切换为 `ui_close` 关窗图标；`奋斗的iMac Pro`（`127.0.0.1:47895`）展示绿色 `已连接` 角标，离线条目展示精简红色 `连接失败` 角标且标题不被挤压，下方多行副标题完整显示错误详情 |
| 会话默认设置子页（浅色） | [after-subpage-light.jpeg](after-subpage-light.jpeg) | 返回箭头与顶部 `刷新` 动作对齐；权限单选与响应方式采用规范 `FormRow` 勾选行，不支持项柔和置灰 |
| 新建定时任务编辑器（浅色） | [after-scheduled-editor-light.jpeg](after-scheduled-editor-light.jpeg) | 分组表单展示 `运行位置`、`调度` 三段式选择器（`固定时间` / `间隔` / `单次`）、`本地时间 09:00` 与 `周一`–`周日` 圆角标签按钮，底部单一 `#18181b` 主确认按钮 `检查并保存` |
| 筛选与排序表单（浅色） | [after-filter-light.jpeg](after-filter-light.jpeg) | `筛选范围` 下拉行、`会话排序` 勾选卡片与底部 `清除环境与项目筛选` 操作分布自然、无裁切 |

## 实测发现并修复的问题

1. **`ConnectionsPanel.ets` 状态角标宽度挤压标题与上移图标不可见**：首轮真机检查 `环境` 面板时，较长的连接失败错误信息直接传入右上角 `StatusBadge` 导致环境标题被挤没，且上移按钮引用了白色图标 `ui_up`；已为角标提取精简短文案映射（`已连接` / `连接中` / `需解锁` / `连接失败` / `未连接`），保留多行详细说明在地址下方展示，并改用主题墨色 `ui_down` 旋转 `180°` 绘制上移箭头。
2. **`T3Client.ets` 过时非挂起恢复会话重连死循环**：设备本地持久化着前序步骤留下的 `thread-worklog-demo-001` 恢复标记；连接到不含该会话的隔离库时，`orchestration.subscribeThread` 返回已知拒绝错误后 `watch()` 直接断开整个连接导致 5 秒死循环重试。已在 `T3Client.watch()` 增加保护：当且仅当不存在未决发送 `pendingId` 且未收到过快照（`state.cursor < 0`）收到已知拒绝时，清理过时本地状态并保持环境已连接，同时保留未核对挂起请求的严格重连保护；并在 `tests/native-client.test.mjs` 补充单测覆盖。
3. **验证与还原**：真机全量截屏后已切回「浅色」外观并二次截屏核验，同时停止 `127.0.0.1:47895` 隔离服务进程、确认 `lsof -i :47895` 清空，并删除 `/tmp/t3_step4_*` 与设备 `/data/local/tmp/t3_*` 临时文件；`/tmp/t3-r5-accept-00fcea` 保持只读未改。
