# R0 证据索引

所有源码证据固定在 `ad1b1365999c92c3fc7a054e7f3af84623f74fee`。S=源码；O=宿主离线自检；本目录没有原版真实页面/云/鸿蒙 native 原型验收证据。

| 文件 | 用途/边界 |
|---|---|
| [baseline.json](baseline.json) | 归档 SHA256、上游 SHA、32,347 个普通文件的路径/字节/SHA256；不包含工作区未跟踪文件、.env、node_modules 或 Git 历史。归档只含 Git 已跟踪提交内容，可能含 `.env.example` 等模板 |
| [routes.json](routes.json) | 89 个注册名、Stack 行号、页面文件、完整 options/linking/alias；源码自动核对数量/唯一性/目标存在 |
| [actions.json](actions.json) | 6,929 条菜单 title/label/id、操作绑定或 case 候选；含类型/内部 ID，不能据条数宣称全量人工审阅 |
| [conditions.json](conditions.json) | 1,948 条权限/能力/云/平台/开发/禁用/managed 条件候选 |
| [calls.json](calls.json) | 946 条环境 API/WS_METHODS/Rpc/HTTP 调用线索；结合 contracts/rpc.ts 的 payload/success/error/stream 与 scopes 阅读 |
| [settings.json](settings.json) | 506 条设置/偏好/字段读写线索；动态 provider/model 仍需真实 config |
| [native.json](native.json) | 940 条系统包/原生模块 import/桥接线索，覆盖移动端目录外共享代码 |
| [rpc-methods.json](rpc-methods.json) | 完整 WS_METHODS wire 名、声明行、Schema 绑定和额外客户端权限引用；共享契约含非 mobile 方法，不能据此扩迁桌面能力 |
| [capabilities.json](capabilities.json) | 环境 capability 字段及 mobile 直接引用位置，空引用仍保留声明，不视为必迁 mobile 入口 |
| [settings-controls.json](settings-controls.json) | 设置页面和子 sections 的 label/title/setting/value/change/disabled 控件线索，补充动态字段与 UI 标签 |
| [native-modules.json](native-modules.json) | 10 个本地原生模块名 |
| [runtime-probes.json](runtime-probes.json) | 本机原版运行条件与指定 HDC 设备只读发现记录，无应用操作 |
| [sdk-probes.json](sdk-probes.json) | 本机 SDK 路径/文件 hash/签名、通知、视频解码符号；仅声明检查，无设备运行 |
| [dpop-host-selfcheck.json](dpop-host-selfcheck.json) | Node crypto 表示方式自检，不是鸿蒙或 relay 验证 |
| [local-tests.txt](local-tests.txt) | 47 项已有本地测试本轮通过；不能替代 UI/原版/云验收 |
| [upstream-conformance.txt](upstream-conformance.txt) | 已有上游 command/OAuth Schema、Effect 4.1.3 内存 RPC 检查通过；不等于所有新增范围协议已覆盖 |
| [pre-index-docs.tar.gz](pre-index-docs.tar.gz) | 本轮更新索引前 README/权威计划/旧计划/UI 文档备份，保留历史事实 |

## 复现

```sh
python3 scripts/r0-inventory.py
node scripts/r0-dpop-selfcheck.mjs
node --experimental-strip-types --test tests/*.test.mjs
```

归档在 `docs/baselines/t3code-ad1b136.tar.gz`（约 128 MiB），SHA256 `595b64affe9ae78510bbfdcd1cb4f282cade542aa4f8f7c704ea02998321e30a`。脚本直接读取归档，不依赖 `/tmp`、Git 仓库或安装第三方依赖。需要浏览源码时解压到独立目录，顶层 `t3code-ad1b136/`，不要覆盖当前鸿蒙工程。Git archive 不包含 Git 历史及两个 gitlink 的子仓库内容：`.repos/alchemy-effect/submodules/distilled@e02e9d405b8848909f4f746b61b12a663f631c7c`、`floci@493909133db04153348eabc503f4e30cf0033d96`；它们不在 mobile 依赖闭环，本轮不声称归档可离线重建所有 monorepo 目标。原生二进制/补丁/锁文件以归档内跟踪内容为准，构建仍需相应工具链/包缓存。

源码在线定位模板：`https://github.com/DASungta/t3code/blob/ad1b1365999c92c3fc7a054e7f3af84623f74fee/<file>#L<line>`。JSON 每条 file/line 可直接套用，不使用可能漂移的 main。

动作/条件扫描跳过 `.test.`、`__tests__`、nitrogen/generated；测试仍完整保存在源码归档用于查看预期。正则不能证明运行可达性：没有匹配的文件不代表没有功能，动态注册、render props、翻译标签和 provider 数据须结合原版运行与矩阵人工补核。见 [防漏与限制](../../r0-mobile-capability-matrix.md#防漏核对与限制)。
