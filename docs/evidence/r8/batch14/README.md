# 第十四批：Labs设置

399/399回归通过，ArkTS可空字段检查修正后签名构建与Mate60Pro安装启动成功，见build.json。

固定上游移动Labs两字段：linkedEnvironmentsEnabled（peerLinks能力）、fastWorktreeCheckout（fastWorktreeCheckout能力）。页面按环境独立读取，过滤禁用/删除/换址中目标，组织锁和settings:write门控；写前重读、单字段patch、写后核对，失败不重放。不自动配对或连接其他机器，既有peer link入口保留。

真机从设置搜索Labs进入，当前已连接环境两项均显示关闭，文案和按钮完整（labs.jpeg已视觉检查）。本批只读，未切换开关、未清除检出缓存。实际跨环境写入/回读、快速工作树性能和组织托管真机仍待验，不能标S13全量完成。

## 快速检出开关真机写回

08:56在原隔离环境点击快速检出开关，页面显示已开启及保存回读成功，服务settings.json确为fastWorktreeCheckout:true（labs-enabled.json）。再次关闭后字段恢复默认省略，与labs-before.json完全一致（labs-restored.json）。关联环境未开启，未建立连接、未创建工作树。此结果证明单环境设置写回，不证明实际检出加速或跨环境写隔离。

## 特大字号视觉补验

系统字体标准2→常规最高特大5，字重1/显示缩放1不变。Labs标题、环境选择器、两项说明和开关完整，布局无重叠/裁切，见labs-large.jpeg。检查后恢复字体2，见large-font.json。未开启关怀模式；其他新增页及全部状态仍需逐项大字体验收。
