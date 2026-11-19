# R0 实施交付记录

2026-11-16。范围：整个原版移动客户端完整迁移的第 0 阶段。**静态产物与离线检查已交付；R0 完整验收未闭合。** 本轮未改 ArkTS/ArkUI 业务代码、依赖或签名，未安装/操作测试应用、未初始化 Git/提交/发布、未创建子代理、未重启 T3 服务或提交业务任务。

## 从这里继续

| 交付物 | 内容 |
|---|---|
| [能力迁移矩阵](r0-mobile-capability-matrix.md) | 连接/云、多环境、项目/会话/草稿/队列、消息/工具/输入/秘密来源、多媒体、文件/Diff/Git/PR、终端/预览、系统集成和设置；每项有源文件、条件/契约、鸿蒙差距、验收 ID |
| [89 路由台账](r0-route-ledger.md) | 注册名/页面源文件/精确 Stack 行号/options/linking/aliases，包含无 URL 的 sheet、开发页和旧链接 |
| [页面与交互基线](r0-interaction-baseline.md) | B01–B10 核心路径、返回/键盘/菜单/状态/ArkUI 对应、真实取证要求与当前空缺 |
| [依赖验证与阻塞](r0-dependency-validation.md) | Clerk 账号/回调、DPoP/中继、Ghostty、H.264/MJPEG、通知/推送；10 个本地原生模块及外部系统依赖 |
| [R1 实施入口](r0-r1-implementation-entry.md) | 触达调用点、环境范围键、目录/Asset 分离、旧数据迁移/崩溃/删除/回退设计、R1.1–R1.6 顺序和门槛 |
| [R2 进展](r2-progress.md) | 2026-11-17 T3 Connect 客户端实现、153 项本地测试、签名 HAP、固定上游契约审计、真实 Clerk/relay/设备 DPoP 阻塞 |
| [证据与复现索引](evidence/r0/README.md) | 完整上游归档及 hash、逐文件清单、动作/条件/调用/设置/原生行证据、本轮测试结果 |

## 本轮真实做过的检查

- 只读复核上游 HEAD=`ad1b1365999c92c3fc7a054e7f3af84623f74fee`、无工作区修改；保存 Git tracked 源码归档到项目内 `docs/baselines/t3code-ad1b136.tar.gz`，SHA256 已固定，约 128 MiB。原始 `/tmp` 目录删除后仍可重建索引/解压浏览；两个无关 gitlink 不在归档内容，详见复现索引。
- `python3 scripts/r0-inventory.py` 从归档重建：32,347 文件、89 个注册路由和 10 个本地模块；断言归档 hash、注册数量/唯一性/目标存在/嵌套注册块边界。6,929 条动作、1,948 条条件、946 条调用、506 条设置、940 条原生候选均带源码行；另展开 198 个 wire 方法、78 个 capability 字段及 739 条设置控件线索。**候选条数不是已人工运行验收的功能数量。**
- `node scripts/r0-dpop-selfcheck.mjs` 通过宿主 Node crypto 的表示方式/签名篡改拒绝检查；不写私钥，不联网，不能证明鸿蒙或 relay。
- `node --experimental-strip-types --test tests/*.test.mjs`：47/47 通过。已有上游 conformance：固定 command/OAuth schemas、Effect 4.1.3 serialized RPC 通过。它们不覆盖新矩阵所有协议，不代替原版/视觉验收。
- 本机 SDK 声明检查已保存 hash/符号；HDC 仅复核授权目标 ALN-AL80 和已安装包列表，没有启动/修改应用，没有碰其他设备。
- 原版运行条件检查：ADB 无设备、Xcode simctl 不可用、未找到本地 native-client cache；桌面 T3 安装不是移动端。原版需要匹配 native fingerprint 的 Dev Client，不能用 Expo Go/鸿蒙离线样例充数。

本轮只有文档、源码索引工具和隔离自检变更，没有重建/覆盖安装 HAP；上一轮签名构建与真机局部验收仍是历史事实，本轮不将其标为新验收。自动索引脚本会覆写其列明的生成 JSON 和路由台账；人工维护的能力矩阵/基线记录不被覆写。

## 未完成与解除条件

| 阻塞 | 现有证据/需要的具体条件 | 关闭条件 |
|---|---|---|
| 原版真实视觉/交互 | R0 本轮只有 S 源码推断；2026-11-17 已补 B01 的 Android 模拟器真实截图/操作（`evidence/r1/b01-original/`），B02–B10 仍缺 | 继续取得原版 B02–B10 的设备/隔离构建条件，记录截图/操作/服务状态；动态菜单逐入口核对 |
| 云账号与鸿蒙登录 | 缺已核实的 Clerk/relay 公开配置、合法鸿蒙身份/回调和测试账号 | 注册/回调、登录/注销/切号、token 读取与续期真实闭环 |
| 鸿蒙 DPoP | SDK 有候选 API，宿主 raw/JWS 自检通过；没有 D | 鸿蒙 key/sign/存取/锁屏/格式检查，通过真实上游 verifier/relay 验签 |
| 原生终端 | Ghostty 固定版本已定位；没有鸿蒙二进制/渲染/输入证据 | 隔离 native prototype 构建及真机 ANSI/UTF-8/resize/双向 PTY/重连 |
| 远程预览 | 协议/解码候选已定位；没有合法独立帧源与鸿蒙原型 | H.264/MJPEG、鉴权/输入坐标/背压/音频适用项、生命周期真实验证 |
| 通知/推送 | SDK 本地通知 API 存在，鸿蒙云注册/服务发送支持未核实 | 合法推送项目/relay 适配、设备注册/注销、后台与冷启动点击正确定位 |

静态扫描无法证明“每个条件隐藏入口已运行核对”，因此本轮不将完整 R0 标为已验收，也不擅自开始 R1 全量实现。接续先解除上述原版/关键依赖条件，再按 R1 实施入口推进；缺外部条件不能删掉功能或用 mock 关闭验收。

## 变更与回退

新增：`docs/r0-*.md` 六份文档、`docs/evidence/r0/`、固定源码归档、`scripts/r0-inventory.py`、`scripts/r0-dpop-selfcheck.mjs`。更新 README、完整迁移计划、历史开发计划和 UI 索引；原文备份在 `evidence/r0/pre-index-docs.tar.gz`。没有修改阶段一至三历史证据。

回退文档索引可从备份取回对应四文件；新产物独立，无应用数据迁移或运行服务变更需要回退。归档较大，后续若接入 Git 应先决定二进制基线存放方式，不能自动把 128 MiB 文件提交到远端。
