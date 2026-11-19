# 定时任务的会话目标

Mate60Pro 的「设置 → 定时任务 → 新建任务」可选择每次新建会话、继续同一会话，或同一会话内每次使用新上下文。后两种方式可选当前项目已有会话，也可在首次运行时创建会话。绑定时显示目标会话当前模型。切换项目后清除旧绑定。缺少任务模式能力的服务按 threadId 推导兼容行为。

隔离 T3 0.1.10 声明支持 scheduledTaskThreadModes，测试前任务表为空。选择 r5-round2 的 Unclear Subject 后切到 pr-read，原会话选择被清除。真机创建并核对了以下两种配置。

| 手机选择 | 服务端回读 |
|---|---|
| 继续同一会话，绑定 Unclear Subject | thread_mode=continue，thread_id 指向同一项目的目标会话 |
| 同一会话内每次使用新上下文，首次运行创建会话 | thread_mode=fresh_session，thread_id 为空 |

两条任务的模型均为 gpt-6.2-sol，enabled=0、run_count=0。绑定后的运行由服务按目标会话处理；保存的启动备用字段沿用 root、approval-required、default。[绑定确认](boundConfirm.jpeg) · [首次运行创建的确认](firstRunConfirm.jpeg) · [数据库回读](both.json)

目标选择功能包在系统特大字号下读回两条配置，列表和详情可分辨项目、目标会话及复用方式。[列表](listLarge.jpeg) · [详情](boundDetailLarge.jpeg)。选择器使用稳定候选列表，点选后按 ID 重新检查，提交前重新核对项目、会话与模型；候选排序翻转和目标失效由宿主回归覆盖。

最终签名 HAP SHA-256 为 `0edfa0eef24243b4b8a431586f573506b2033dce346850f81169acc42c18c8fe`，全量宿主测试 508/508 通过，最后按钮响应式修正后定时任务专项 17/17 通过，失败、取消、跳过均为 0。本批覆盖配置与回读。真实定时触发后的上下文重建、已有任务改绑、分支工作区及 Webhook 仍待验收。


## 返回前台

旧包返回前台后，列表看似已恢复，但新建按钮一直禁用。检查发现就绪状态没有传递给列表，且禁用分支曾先读取普通连接对象，导致 ArkUI 未订阅按钮可用状态。最终包按连接代次和权限刷新列表，按钮优先订阅可观察的读取状态。Home 后立即返回，新建按钮自动恢复 enabled=true；未手动刷新。编辑或确认中的未保存表单保留，连接变化时显示重新核对提示。[修复前](reconnectBefore.jpeg) · [恢复后](reconnectAfter.jpeg)

从恢复后的新建入口再次创建「已有会话 + 每次新上下文」，最终包回读 thread_mode=fresh_session、目标属于同一项目且运行次数为 0。删除本轮测试任务后，隔离任务表与基线均为 0 条。手机已恢复系统标准字号并留在会话首页。[最终确认](finalConfirm.jpeg) · [保存回读](finalBound.json) · [清理回读](cleaned.json)
