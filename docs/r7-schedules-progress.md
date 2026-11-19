# R7 S14 定时任务（2026-11-19）

当前支持停用创建、基本编辑、启停、删除与未绑定任务的显式模型切换。基础管理见[B6](evidence/r8/batch6/README.md)，模型变更与字段保留见[B34](evidence/r8/batch34/README.md)。新建可选择目标会话和运行方式，见[B35](evidence/r8/batch35/README.md)。未绑定任务可选项目根、新工作树与已有 checkout，见[B36](evidence/r8/batch36/README.md)。手动运行、Webhook、既有任务改绑与真实启动效果仍待验收。

## 初版交付记录

- 入口：`ScheduledTasksPanel({ connection, onBack })`，父会话接入设置导航；不需要新增配置。
- 基于固定上游 `ad1b136` 的 `scheduledTask.ts`、`rpc.ts`、`SettingsScheduledTasksRouteScreen`、`ScheduledTaskPickerScreens` 和 `scheduledTaskDraft`。
- 读取为 `scheduledTasks.subscribe` 首快照，不存在虚构的 `scheduledTasks.list`。首帧/超时停止流，身份按打开页面的环境锁定。
- 列表/详情显示启停、计划、下一次、最近状态、项目、线程、模型。新建选择当前环境项目及 provider 模型；默认停用、新线程、项目根工作区、approval-required、default。
- 新建/编辑/启停/删除均二次确认，写前再次读取任务并校验 updatedAt，编辑 `requireExisting:true`，写后重新订阅核对。失败/未知结果禁写直到手动刷新，不重发。
- 调度仅有 interval（至少 60000ms）、fixed_time（服务端 timeZone，星期 0=周日）、once（带偏移 ISO 时间，拒绝非法日期）。上游没有 cron 契约，未添加 cron。
- 编辑保留原项目/线程/threadMode/工作区/分支/模型及 options/权限，不做隐式重绑定。旧服务端未返回时区时禁止保存 fixed_time。
- Webhook/未知调度仅查看及独立启停删除；不暴露 webhook 地址、密钥或 lastRunError 原文。
- 颜色复用系统主题资源，控件使用 fp 字号和滚动布局；深浅色、大字体实际可读性仍需真机验收。

验证：`node --test tests/scheduled-tasks.test.mjs`，4/4 通过，覆盖日期/间隔/时区、默认停用、编辑字段保留、真实 RPC 名称、首帧取消、写前后读取、权限/环境/并发修改阻止、未知结果不重试、Webhook 地址不进入展示模型。

边界：尚无立即运行、Webhook 创建/编辑/轮换/投递记录、目标/分支/高级模型选项编辑、新建绑定已有线程；模型选择来自当前目录，服务端仍执行项目及组织策略校验。本代理没有构建/安装/使用设备，没有向真实服务创建、启动或删除任务。并发修改检测基于读前版本，服务端契约不提供原子 CAS，因此读取与写入之间仍可能发生外部修改。
