# 第十八批：数据库整理操作

412/412测试与签名构建安装通过，见build.json。已实现真实server.reclaimDatabaseSpace：维护权限、能力、可回收空间、canReclaim及未启用增量回收共同门控；确认明确服务会重启/中断运行任务，执行前fresh身份/状态校验，单次请求，重连后读回，未知结果不重放。

原隔离数据库已通过SQLite backup私有备份（仅保存在隔离base-dir的acceptance-backups，权限600，quick_check=ok），未复制入仓库。当前库增量回收已开启且空闲页0，真机明确显示无需手动整理，没有可点击回收按钮。未改pragma、未制造业务数据、未请求整理或重启。会话和消息行数保持1/6，见database-before.json、readback.json。

本轮只关闭实现与不可用门控验收；适格数据库真实重启/回收成功、断网恢复、维护权限撤销及运行任务影响仍待专用条件验证，不宣称S10全部完成。
