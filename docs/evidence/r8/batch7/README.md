# 第七批：浏览器多标签与历史导航

2026-11-19。最终 344/344 宿主测试通过，签名构建、Mate60Pro 安装启动通过；隔离 T3 0.1.10。

- 两个独立 server 标签：Beta test 与 Alpha test，实际下拉选择可见。切换先释放画面，显示需连接提示，显式连接后恢复所选 Beta 页面；见 preview-switched.jpeg。
- 第一个标签从 Alpha 导航 Beta，后退画面 Alpha、前进画面 Beta，见 preview-back.jpeg / preview-forward.jpeg。
- 空态工具栏无越界，控件在手机实际画面可见，见 preview-empty.jpeg。
- 本批发现地址框未随历史导航同步；前述历史截图明确保留此问题，最终已修复并复验，旧截图不作为最终地址显示证据。
- 仅本机隔离 fixture 127.0.0.1:47897，无外部网站登录或真实仓库变更。尚未完成大字体、跨环境切换、并发关闭全部矩阵。

## 最终复验

- 最终包见 [构建回读](build-readback.json)，344/344 全部通过，已覆盖安装并成功启动。常亮仍启用。
- 主 RPC subscribePreviewEvents 通知后串行回读列表；媒体 WS 不虚构导航包。最终 Beta→Alpha→后退 Beta→前进 Alpha 的标题与地址同步，见 [最终画面](preview-navigation-final.jpeg)。
- 在地址框输入未提交 unsent.html 后后退，标题更新 Beta test，地址保留 unsent.html；没有请求该路径，编辑保护通过。仅聚焦或相同值回调不再当作编辑。
- 两个本次测试标签均经关闭确认移除，重新更新列表为空；临时 HTTP 服务已退出。未关闭其他用户页面。
- 已知边界：回退到浏览器初始空白页时，当前服务可能仍返回上个导航标题/地址；客户端显示服务实际快照，不宣称此边界已修复。跨环境/并发关闭与更大字号仍需扩展验收。
