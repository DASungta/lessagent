# 全站文字按钮中性化收紧真机验收证据

- **验证设备**：Mate60Pro（`23E0224122000135`，`1260x2720`，浅色模式）
- **数据源**：只读隔离服务端样本（`/tmp/t3-r5-accept-00fcea`）
- **单元测试**：`node --experimental-strip-types --test tests/*.test.mjs` → `tests 562`、`pass 562`、`fail 0`
- **签名 HAP（SHA-256）**：`5b1b75460de5e91b0ef75837c245b2dd91d293cf25e9dca3281964b24e58f574`

## 变更摘要

- [AppButton.ets](../../../../entry/src/main/ets/components/ui/AppButton.ets)：将 `kind: 'text'` 的字色从 `primary_text` 收紧为中性 `ink`，统一收敛全站 43 处文字按钮（「搜索」「刷新」「分支」「保存」「默认」「添加项目」「检测代码托管来源」等）。
- [ThreadList.ets](../../../../entry/src/main/ets/components/ThreadList.ets)：将首页搜索框右侧「取消 / 清除」与筛选条「清除」改为 `Weight.medium` + `ink`。
- [Index.ets](../../../../entry/src/main/ets/pages/Index.ets)：将底部撤销提示条的「撤销」改为 `Weight.medium` + `ink`。
- [docs/design/README.md](../../../design/README.md)：更新 `primary_text` 与 `AppButton` `text` 规范说明，蓝色仅保留给开关、多选选中态、运行中状态、Markdown 链接及审批 `confirm` 确认操作。

## 真机验收截图

| 截图 | 页面 | 验证点 |
|---|---|---|
| [after-pulls-light.jpeg](./after-pulls-light.jpeg) | 拉取请求 | 搜索框右侧「搜索」改为中性 `ink`（无输入禁用态清晰自然） |
| [after-usage-light.jpeg](./after-usage-light.jpeg) | 用量 | 顶栏右上角「刷新」改为中性 `ink` |
| [after-git-light.jpeg](./after-git-light.jpeg) | Git 状态与提交 | 顶栏右上角「刷新」「分支」改为中性 `ink`，主操作「提交」近黑突出 |
| [after-files-light.jpeg](./after-files-light.jpeg) | 文件与源码 | 搜索框右侧「搜索」改为中性 `ink` |
