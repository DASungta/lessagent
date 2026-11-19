# R6–R8 真机验收索引

[全部阶段测试图库](../../handoff/index.html) · [B39 终端选字与中断位置](batch39/README.md)

[当前安装包和整体进度](../../development-status.md) · [尚待验收的项目](../../r6-r8-acceptance.md)

| 想核对的功能 | 真机记录 |
|---|---|
| 会话首页、筛选、聊天输入 | [首页与深色特大字号](batch24/README.md) · [筛选恢复](batch25/README.md) · [聊天改动前后](batch26/README.md) · [源码阅读与会话操作](batch31/README.md) · [真实 PR Diff](batch32/README.md) · [文件搜索命中定位](batch33/README.md) |
| 终端与远程设备 | [Android 操作](batch6/README.md) · [多终端](batch9/README.md) · [滚回](batch10/README.md) · [选字](batch21/README.md) · [终端分页](batch27/README.md) · [持续输出](batch28/README.md) |
| 远程浏览器 | [多标签和导航](batch7/README.md) · [画面尺寸和点击](batch20/README.md) · [缩放与复位](batch29/README.md) · [双查看者交接](batch30/README.md) |
| 项目和源码管理 | [工作树分支命名](batch22/README.md) · [存储与权限恢复](batch23/README.md) · [单项目覆盖](batch27/README.md) · [默认克隆目录](batch28/README.md) |
| 系统集成 | [文字分享](batch3/README.md) · [多文件分享导入](batch37/README.md) · [图库 PNG 分享与首页环境导航](batch38/README.md) · [通知](batch4/README.md) · [语音输入](batch5/README.md) · [桌面快捷入口](batch15/README.md) · [静态卡片](batch16/README.md) |
| 设置与维护 | [新任务默认值](batch8/README.md) · [自动归整](batch11/README.md) · [工作中分组](batch12/README.md) · [最近项目](batch13/README.md) · [Labs](batch14/README.md) · [维护信息](batch17/README.md) · [数据库整理](batch18/README.md) · [诊断分享](batch19/README.md) · [定时任务模型编辑](batch34/README.md) · [定时任务目标会话](batch35/README.md) · [工作区选择](batch36/README.md) |

## 第一批联合验证（历史记录）

2026-11-18，专用 Mate60Pro `23E0224122000135`，原有隔离 r5-round2 环境，T3 0.1.10。没有初始化 Git、提交或发布。

- 当前树宿主测试 243/243 通过；见 tests.log。
- 最终签名构建成功，候选包 r678-candidate-signed.hap，SHA256 `5fbaf63d24e992a8688a417a4f2ed691dce5f2ebd80570b4162e1d1f357b5b78`；已覆盖安装并启动，保留原环境/会话。
- 真机列表、会话和输入工具条：home-dark.jpeg、chat-dark.jpeg；工具入口保留命令/技能/文件引用，队列和发送模式仍可达。
- 外观：settings-light.jpeg 为切换过程截图；home-light-restored.jpeg 证明强制停止并重启后浅色恢复（连接加载中，不作为列表完成证据）。
- 终端：terminal.jpeg 保留首次发现的可选 error 字段解析错误；已修复并加入回归。terminal-final.jpeg 为修复后真实 echo R6-DEVICE-OK 回显；之后继续校准字体/行距，最终截图另存 terminal-calibrated.jpeg。

仅完成上述路径抽查。请求卡新布局、读屏、系统最大字体全页面、折叠/平板、完整终端与远程视频预览、通知/语音及全量设置仍未验收。截图中的既有字体档位不等于本次跑完最大字体专项。
