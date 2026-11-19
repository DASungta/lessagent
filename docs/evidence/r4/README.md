# R4 证据

首批是草稿首发/模型设置/服务端队列的代码与本地检查；第二批补充持久草稿、分支/worktree、队列计数、审批、Side chat、安全输入和附件关联的真实隔离服务/设备证据；第三批修复提交保护/附件/继承请求并用隔离服务补队列、secret、steer、force stop、resume 和多附件回读。**仍不是完整 R4。** 进展见 [R4 记录](../../r4-progress.md)。

- [测试日志](r4-local-tests.log)：188/188，包括原 R3 173 项；新增项执行纯协议或真实适配层/方法，网络与系统 API 使用宿主注入，不是真机。
- [最终构建日志](r4-final-build.log)：普通签名 HAP 构建通过，仍有 SDK API 可抛异常/AlertDialog deprecated 提示，不影响构建结果。
- [候选 HAP](r4-candidate-signed.hap)：SHA256 `2913e49fee913d1a912a3f7cc1157ce7ae2d8eb81bb69575e073b5f322b2e6e2`；[校验文件](r4-hap.sha256)。未安装。
- [固定源码核对](pinned-source-audit.json)：归档文件 SHA 对齐 R0 manifest，列出 launch/queue/model/policy 声明行。只有源码核对，**未执行上游 Effect Schema 或内存 RPC conformance**。
- [变更清单](changes.json)：本批源码/测试/索引路径及修改前后 hash，不包含 build 中间产物。
- [实施前备份](pre-r4-source.tar.gz)：修改前源码、测试及相关索引；不要用整体解压覆盖后续其他会话工作。
- [汇总](summary.json)：机器可读的检查与未验收边界。
- [第二批设备/真实服务证据](batch2-device/README.md)：Mate60Pro + 隔离 T3 0.1.9；195/195 测试、最终签名包 SHA256 `bfb1d6cb688ae4e6a54eaacc07fab50d63a0c6f2585e5d536038645f28a727d3`。
- [第二批变更清单](batch2-device/changes.json)：追加源码/测试/文档路径与 SHA256；根 `changes.json` 保留首批历史，不回写覆盖。
- [第三批真实服务证据](batch3-service/README.md)：208/208 测试、签名候选 SHA256 `86b950e13afb6ac3b7a48226f8d6d570abf93706b8c4e84148e323f4d003092c`；已覆盖安装并完成模型、消息、队列、secret、附件预览/分享的专用机 UI 回读，剩余边界见该目录。
- [第三批专用机 UI 证据](batch3-device/README.md)：模型分组、消息复制/空续接隐藏、队列编辑/移除、secret 提交、附件预览与系统分享。

复现本地检查：在工程根目录运行 `node --experimental-strip-types --test tests/*.test.mjs` 和 `./scripts/build.sh`。构建使用已有 DevEco 工具链，无新增依赖；上游源码来自项目内固定归档，运行测试不依赖临时上游目录。没有运行设备/浏览器 UI 自动化，没有修改服务、真实仓库或服务端会话。
