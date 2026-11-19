# 第九批：终端多会话

最新：08:13 第二轮双终端关闭隔离验收通过，本次测试终端已清理。以下保留第一轮中断记录。

2026-11-19。371/371测试、签名构建、Mate60Pro安装启动通过。HAP SHA256：`1da0bea4fecd374d2d43b961c372c6462c153083babd1fb29fd6d6e8f2ca2823`。

新增metadata列表、唯一ID新建、显式连接、切换、单目标结束、退出终端清理。只读走observe；后台释放订阅，迟到回包隔离。首帧nonfatal超时现在Interrupt订阅，不关闭shell。列表活动更新保持顺序。

真机证据：原有Terminal 1保留；新建Terminal 2输出R9-TERMINAL-A（terminal-a.jpeg），新建Terminal 3输出测试命令，列表显示三个终端（terminal-b-list.jpeg）。切回Terminal 2重新连接，A历史保持且不含B，见terminal-a-restored.jpeg。确认结束Terminal 2后，列表仅余Terminal 1与Terminal 3。

最后验证被环境中断：08:10再次操作时提示“请先连接服务器”；127.0.0.1:47895无监听，curl返回连接失败。`terminal-b-after-close-a.jpeg`是失败证据，不能当作B继续运行通过。R9-B-STILL-ALIVE未发送。应用重新启动不能恢复已退出服务。

待继续：恢复原隔离服务（不要更换环境身份），核对Terminal 3状态，验证关闭A后B可继续输入，然后仅清理本次Terminal 3。不能删除原Terminal 1。只读真机、显式重启、大字体/读屏、完整TUI/滚回仍未验。当前未宣布本批真机闭环全部通过。

## 08:11 恢复进展

原base-dir及原端口服务已重新启动，descriptor环境ID与原environment-id一致，版本0.1.10。手机重启应用后重新显示原会话，终端metadata成功返回空列表，见service-recovery.json。没有通过猜测旧ID重新attach启动shell，也未删除原终端历史。空列表表示服务重启后无活动终端，不能证明此前B存活；需重新进行A/B关闭隔离验收。

## 08:13 第二轮通过

从空metadata新建两个唯一ID终端（显示Terminal 1/2，均为本轮新建，不是第一轮旧shell）。关闭A后，B连接恢复原R9-SECOND-B历史，并实际执行echo R9-B-AFTER-A-CLOSED，画面出现对应输出，见 [通过截图](terminal-isolation-passed.jpeg) 和 [回读](isolation-readback.json)。随后确认关闭B，更新metadata为空；仅清理本轮终端，保留历史。多会话主路径关闭，完整TUI、滚回、硬件键盘、只读真机与长时性能仍未完成。

## 08:14 存储清理补验

第六批创建的80字节分享缓存已超过一小时。真机选择其所属环境，清理确认后从1个80B变为0个0B；切回所有环境及旧文件未知范围，仍有1个70B，未清理其他范围。见cache-cleanup.json及cache-unknown-preserved.jpeg。近期文件保护沿用B6证据；本次无源码修改，未重复全量测试。

## 存储提示修正

真机发现切换范围后仍保留上一范围的“已清理”反馈。已改为选择范围或手动刷新时清空该提示；签名构建、安装和启动通过，见storage-feedback-fix.json。本次仅反馈状态两处赋值，不改变清理范围/文件规则，未重复全量测试，也未再次删除旧未知文件。
