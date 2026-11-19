# Step 2 真机验收：首页重构与底部悬浮四栏

日期：2026-11-19  
设备：Mate60Pro（`ALN-AL80` / `23E0224122000135`）  
连接环境：隔离服务 `127.0.0.1:47895`（`/tmp/t3-r5-accept-00fcea`，仅只读拉取列表与记录，未发送任务或改动服务端数据）  
宿主测试：`node --experimental-strip-types --test tests/*.test.mjs` — **547/547 通过**（含新增 `tests/thread-row.test.mjs`）  
签名构建：`./scripts/build.sh` — `BUILD SUCCESSFUL`  
HAP SHA-256：`8d58f5b1100db3058b5bcd93cc69cea707705a85c11d182c763e022c57ef9fb7`

## 前后对照

| 视图 | 截图 | 验证结论 |
|---|---|---|
| 改造前（B39 浅色） | [before-home-light.jpeg](before-home-light.jpeg) | 旧顶栏含下拉箭头与右侧蓝色「新任务」胶囊按钮，无底栏（未连接隔离服务前状态） |
| 改造后（浅色首页） | [after-home-light.jpeg](after-home-light.jpeg) | `#f4f4f5` 灰底顶栏（`T3 Code` 字标 + 搜索/筛选图标）+ 26vp 圆角 `#fcfcfc` 内容面板；会话行展示双字母项目色块（`AT` / `RR`）、标题、紧凑时间（`3分钟` / `19小时`）、桌面图标 + 环境名 + Provider 图标（不显示具体模型名）；底部悬浮四栏激活态在「会话」，右侧为深黑方形圆角「新任务」FAB |
| 首页搜索展开 | [after-home-search.jpeg](after-home-search.jpeg) | 点右上角搜索图标展开搜索框与「取消」；输入聚焦时底部浮栏自动隐藏，列表不被软键盘与浮栏双重挤压 |
| 拉取请求 Tab | [after-tab-pulls.jpeg](after-tab-pulls.jpeg) | 嵌入根页隐藏多余返回箭头，底栏激活胶囊切到第二项「拉取请求」 |
| 用量 Tab | [after-tab-usage.jpeg](after-tab-usage.jpeg) | 嵌入根页隐藏多余返回箭头，底栏激活胶囊切到第三项「用量」 |
| 设置 Tab | [after-tab-settings.jpeg](after-tab-settings.jpeg) | 嵌入根页隐藏多余返回箭头，底栏激活胶囊切到第四项「设置」 |
| 深色首页 | [after-home-dark.jpeg](after-home-dark.jpeg) | `#1a1b1b` 顶栏与 `#0a0a0a` 圆角面板对比清晰，色块/文字/选中态/深色胶囊栏与浅色反相 FAB 均正常 |

## 实测中发现并修复的问题

1. 首次装包切换底栏 Tab 时，激活态灰色胶囊未随 Tab 变化（ArkUI V1 `@Builder` 传入原始 `boolean` 参数不触发刷新）：已拆出独立 `@Component struct HomeTabButton`（`@Prop selected: boolean`）解决，重编重装后四 Tab 激活态切换正常。
2. 首页搜索框聚焦弹出软键盘时，底栏被 `KeyboardAvoidMode.RESIZE` 顶至屏幕中部：改为 `searchFocused` 时隐藏 `HomeBottomBar`，取消或失焦后恢复。
3. 为避免鸿蒙 SVG 解析对 `<defs><linearGradient>` 的兼容风险，将 `provider_gemini.svg` 改为无渐变双路径矢量。
4. 点击顶部 `T3 Code` 字标可正常弹出环境管理面板（`环境` / `+`），系统返回可正常关闭；验收结束后已恢复浅色外观，并停止临时隔离服务进程。
