# 第一阶段实施与验收记录

> 历史记录：下文状态属于当时批次，不代表当前进度。当前以 [整体进度](development-status.md) 和 [完整迁移计划](full-mobile-migration-plan.md) 为准。

日期：2026-11-16。状态：**M1 已通过真机验收**。已完成工程、协议原型、签名安装、真实对话、流式状态及最终文本更新、原会话断线恢复验证。

脱敏结果：[首轮 Mate 70 Pro](evidence/phase-one-device.json)、[专用测试机 Mate 60 Pro 复验](evidence/phase-one-mate60pro.json)。该文件记录测试结果和签名包 SHA-256，不包含凭据或完整会话内容。

## 环境与兼容基线

| 项目 | 实际验证结果 |
| --- | --- |
| 首轮验收手机 | HUAWEI Mate 70 Pro，型号 `PLR-AL30` |
| 当前专用测试机 | HUAWEI Mate 60 Pro，型号 `ALN-AL80`；系统 7.0.0.111，API 26，已独立重跑验收 |
| 系统 | 设备返回 `OpenHarmony-7.0.0.111`，API 26；DevEco 识别为 7.0.0 |
| 开发环境 | DevEco Studio 6.1.1.300；HarmonyOS 6.1.1.125 SDK，API 24 |
| 工程兼容/目标版本 | `6.1.1(24)`；已在上述 API 26 真机安装运行，不代表验证了所有 API 24 及以上设备 |
| 应用 | `com.dasungta.t3code.harmony`，0.1.0，单 entry 模块 |
| 上游调研源码 | DASungta/t3code `ad1b1365999c92c3fc7a054e7f3af84623f74fee` |
| 实际联调服务 | 电脑上现有 T3 0.1.9，端口 3773，协议版本 2；服务端运行构建的 Git SHA 未核实 |
| 通信基线 | OAuth Bearer、RPC 专用 ticket、Effect 4.1.3 JSON RPC；只声明协议版本 2 |
| 手机到电脑路径 | HDC reverse：手机 `127.0.0.1:3773` → 电脑 `127.0.0.1:3773` |
| 签名 | 用户完成华为授权；DevEco 管理调试签名，本机 product 已关联 `default` signingConfig |

本次没有修改现有 T3 服务的协议、监听配置或 Agent 配置。应用未引入第三方运行时或额外包。当前目录尚未初始化 Git 仓库。

## 已实现范围

- ArkUI 原生原型页：服务地址、密码型凭据输入、项目/Provider 实例/模型输入、创建会话、按 ID 同步会话、发送指令、文本回复和流式状态。
- HTTP：读取 `/.well-known/t3/environment` 并检查协议；表单编码调用 `/oauth/token`；POST `/api/auth/websocket-ticket/rpc`，仅在 404 时回退到无 audience 的路径。
- WebSocket：使用 `/ws` 的专用 ticket 和协议参数；通过 `server.getConfig` 再次核对环境身份。
- RPC：请求编号、响应匹配、批量帧、Chunk/Ack、Exit、Ping/Pong、超时、分片重组和大小限制。断开会结束订阅；停止 Agent 任务属于第二阶段。
- 会话：`thread.create`、`message.dispatch`、`orchestration.subscribeThread`；处理快照及序列号去重。实时 `turn-item.updated/assistant_message` 和最终 `message.updated` 按 message ID 合并。
- 安全：只接受 HTTPS 根地址，回环 HTTP 用于 USB/本机调试；保持系统证书校验，禁止 HTTP 自动跳转；凭据不写缓存或日志，错误不回显带 ticket 的地址。
- 生命周期：进入后台主动断开；前台手动重新配对并按原会话 ID 恢复。修改类请求断线或超时后不自动重发。

## 首轮 Mate 70 Pro 真机验收结果

| 验收项 | 证据与结果 |
| --- | --- |
| 签名安装及启动 | 签名 HAP 覆盖安装成功，`aa start` 成功，原生页面实际可操作 |
| 错误凭据 | 真机明确显示鉴权失败，未建立连接 |
| 合法鉴权与身份校验 | 真机读取版本、交换 token、获取 ticket，界面进入“已连接” |
| 创建与同步会话 | 手机在当前项目中创建审批模式测试会话，使用 `codex` / `gpt-6.1-sol`；真实服务记录可核对 |
| 真实回复 | 手机显示 `HARMONY_PHASE1_OK` 及中文第二行，与服务端一致 |
| 断线后任务继续 | 长回复生成期间移除本次 USB 转发；手机显示中断，服务端继续完成 |
| 原会话恢复 | 恢复转发、使用新凭据重连并同步原 ID，手机恢复的 2,244 字回复与服务端全文一致 |
| 实时更新与最终状态 | 真实服务记录到 streaming 事件；最新版手机出现“assistant · 回复中”，最终 2,302 字回复逐字匹配，界面仅一条对应最终消息 |
| 不重复提交 | 四条人工测试指令对应四个唯一用户消息 ID，内容也各不相同；断线后没有自动重发 |
| 凭据清理 | 仅撤销本次专用标签下的临时会话/配对，回读确认剩余有效测试凭据为 0，临时凭据文件已删除 |

测试指令要求 Agent 只生成验收文字，不调用工具或读写文件。未执行服务端重启或影响其他会话的网络配置变更。

## Mate 60 Pro 专用测试机复验

日期：2026-11-16。结果：**通过**。后续真机调试以此设备为主，保留首轮 Mate 70 Pro 的结果。

| 检查 | 本次结果 |
| --- | --- |
| 设备与授权 | DevEco 识别为 Mate 60 Pro，`ALN-AL80`，`OpenHarmony-7.0.0.111` / API 26，HDC 已授权 |
| 签名安装 | 原签名因新设备未在 Profile 内而返回 9568423；通过 DevEco 更新设备 Profile 后，重新签名、安装和启动成功 |
| 鉴权 | 错误凭据在真机被明确拒绝；新临时凭据完成交换、ticket 和服务器身份校验 |
| 创建会话 | 手机在当前项目下新建独立测试会话，`codex` / `gpt-6.1-sol`、审批模式 |
| 真实流式回复 | 服务端记录 streaming 事件，手机出现“assistant · 回复中”；707 字最终文本逐字匹配，只有一条对应最终消息 |
| 生成中断线 | 第二条指令提交后移除该设备的 USB 反向转发，手机明确提示中断与结果未知；服务端在断开后约 20.413 秒继续完成 |
| 重连恢复 | 恢复转发并使用新凭据同步原会话，987 字回复与服务端全文一致，界面只有一条对应消息 |
| 防重复提交 | 两条测试指令对应两个唯一消息 ID 和两份不同内容，没有自动重发 |
| 自动检查 | 16 项测试、严格类型检查、固定上游 Schema/Effect RPC 检查和签名构建均通过 |
| 清理 | 本次专用标签下的临时会话/配对已撤销并回读确认，临时凭据文件已删除 |

本次未修改应用逻辑，仅更新本机调试签名 Profile，并在新设备重跑验证。测试同样使用 USB 回环直连；公网 HTTPS、蜂窝切网、锁屏任务恢复、服务端重启和长历史性能仍未验证。

## 真机发现并修复的问题

1. NetworkKit 对显式传入的空 POST `extraData` 返回参数错误 401，导致 ticket 请求失败；改为无正文时省略字段。适配层回归先复现失败，修复后通过，真机鉴权连接也通过。
2. 实时文本由 `turn-item.updated/assistant_message` 提供，原型最初只处理最终 `message.updated`；已补齐并按 message ID 合并，回归测试覆盖实时片段到最终消息不重复。
3. ForEach 仅以消息 ID 为键时，替换消息对象未使已创建的文字组件更新，真机停留在“回复中”；改用平台默认的内容键，真机重新验证最终全文精确匹配。当前会重建变化的消息项，长会话应在第三阶段改为可观察行模型并优化列表。

锁屏曾使启动返回 10106102，解锁后启动成功。没有通过关闭开发者模式或绕过锁屏解决。临时 HDC 输入脚本曾重复插入地址，也已修正；此问题未涉及应用协议代码。

## 构建与自动验证

项目根目录执行：

```sh
./scripts/build.sh
node --experimental-strip-types --test tests/*.test.mjs
```

构建默认使用 `/Applications/DevEco-Studio.app/Contents`，其他位置通过 `DEVECO_HOME` 指定。测试使用支持 `--experimental-strip-types` 的 Node，本次为 22.22.3；适配层测试使用 DevEco SDK 自带 TypeScript 编译器。

签名产物：`entry/build/default/outputs/default/entry-default-signed.hap`。调试证书与密钥保留在本机 DevEco 管理目录；含本机签名参数的配置不应直接提交到共享仓库。

| 检查 | 结果 |
| --- | --- |
| HAP | ArkTS、资源、打包及签名构建通过，已安装到目标手机 |
| 本地测试 | 16 项通过，覆盖协议、流式合并、网络适配、超时防重发、诊断脱敏等 |
| 严格类型检查 | SDK 自带 TypeScript，以 `--strict --noEmit --target ES2022 --module ES2022 --lib ES2022,DOM` 检查 `entry/src/main/ets/protocol/Wire.ts`，通过 |
| 上游 Schema | 固定提交的 OAuth 参数、创建会话和发送指令 Schema 校验通过 |
| Effect RPC | 真实 Effect 4.1.3 序列化 RPC 服务端的请求、流式 Ack、命令和拒绝测试通过；此自动测试使用内存传输 |
| 样例 | `tests/fixtures/thread-stream.json` 为按契约构造的合成样例；额外真机结果见设备验收数据 |

重复上游校验时，在独立调研目录准备固定源码及 Effect，无需安装整个 monorepo：

```sh
git clone https://github.com/DASungta/t3code.git /tmp/t3-harmony-contract-source
git -C /tmp/t3-harmony-contract-source checkout ad1b1365999c92c3fc7a054e7f3af84623f74fee
mkdir -p /tmp/t3-harmony-contract-deps
npm install --prefix /tmp/t3-harmony-contract-deps --ignore-scripts --no-audit --no-fund effect@4.1.3
ln -s /tmp/t3-harmony-contract-deps/node_modules /tmp/t3-harmony-contract-source/node_modules
T3_SOURCE=/tmp/t3-harmony-contract-source node --experimental-strip-types tests/upstream-conformance.mjs
```

## 使用方式与验证边界

本轮以 USB 转发完成真实服务联调。转发失效后，需要重新执行：

```sh
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc rport tcp:3773 tcp:3773
```

手机原型中使用 `http://127.0.0.1:3773`，通过现有 T3 的配对入口生成新的一次性凭据。凭据只在应用内输入，勿写入文档或聊天。当前断开即丢弃 access token，所以每次重连需要新凭据；联调临时凭据已撤销，不能继续复用。

公网 HTTPS 及真机证书失败路径、蜂窝/Wi-Fi 切换、锁屏期间任务恢复、服务端重启恢复和长历史性能尚未实测。协议不兼容、环境身份不一致等拒绝路径已通过本地测试，不为验证而改动正在使用的真实服务。

项目/会话列表、系统安全存储、令牌续期、应用内审批和停止任务、Markdown 属于第二阶段；附件、完整生命周期恢复和长会话优化属于后续阶段。当前未知事件会显示事件类型，未支持的交互由现有客户端处理；单条重组消息上限为 16 Mi 个 UTF-16 代码单元。

## 协议来源

- [鉴权与 ticket](https://github.com/DASungta/t3code/blob/ad1b1365999c92c3fc7a054e7f3af84623f74fee/packages/client-runtime/src/authorization/remote.ts)
- [HTTP 契约](https://github.com/DASungta/t3code/blob/ad1b1365999c92c3fc7a054e7f3af84623f74fee/packages/contracts/src/environmentHttp.ts)
- [会话命令与流契约](https://github.com/DASungta/t3code/blob/ad1b1365999c92c3fc7a054e7f3af84623f74fee/packages/contracts/src/orchestrationV2.ts)
- [ArkUI ForEach](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-rendering-control-foreach)
