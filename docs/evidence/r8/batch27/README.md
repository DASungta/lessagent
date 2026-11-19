# 项目工作树设置与交互式分页终端

签名 HAP 已安装 Mate60Pro，最终 SHA-256 为 `1dd8e081eb1ad7142d27cd8641dbbf5c6b843913fc6c4bfeb1c3ddeaa23c027d`。隔离服务为 T3 0.1.10。功能集成后全量测试 453/453 通过，随后精简重复值与恢复按钮样式，最终包重跑项目专项 7/7 通过。

## 项目工作树设置

从「设置 → 工作树 → 项目级覆盖」选择环境与具体 checkout，可以修改远程起点、子模块、分支命名模式、固定前缀、命名说明。页面显示每项生效值的来源，支持逐项或整页恢复继承。服务缺少能力、写权限或组织锁住字段时，页面限制对应操作。多端同时写同一项目仍受服务缺少原子条件写入的限制。

真机选择 r5-round2，原先继承开启，改为关闭后，服务持久化该项目的 `newWorktreesStartFromOrigin=false`。新建该项目的本机草稿、切到新工作树，开关读回 checked=false。[修改后的页面](project-final.jpeg) · [草稿消费](project-draft.jpeg)

切到另一个 pr-read 项目仍显示开启、继承环境默认值。回到 r5-round2 逐项恢复，值变回开启，服务持久化的该项目覆盖条目消失。其他项目和全局设置摘要均与操作前相同。[修改前](project-before.json) · [保存后](project-edited.json) · [恢复后](project-restored.json)

此轮真机主路径验证远程起点。分支和子模块在实际新 checkout 中的效果、多环境同名 checkout，以及组织锁的真机矩阵仍待验收。

## 终端

手机「按键」菜单提供 Tab、左右方向键、Page Up 和 Page Down。真实 shell 中运行 `less -N` 阅读 80 行测试文件。搜索 TARGET 命中第 64 行，覆盖安装并重新连接后，Page Down 到第 80 行文件末尾，Page Up 回到 55–67 行。关闭附带回车并发送 q，画面恢复到原 shell 提示符。结束测试终端后刷新列表为空。

[文件开头](pager-start.jpeg) · [搜索命中](pager-search.jpeg) · [向下翻页](pager-page-down.jpeg) · [向上翻页](pager-page-up.jpeg) · [退出分页器](pager-exit.jpeg)

搜索图来自 B26，翻页和退出图来自 B27 功能包。手机已返回会话首页。
