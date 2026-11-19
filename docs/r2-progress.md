# R2 T3 Connect 进展

日期：2026-11-17。状态：**R2 客户端实现已落地，真实云中继/账号验收未完成。**

固定上游：`ad1b1365999c92c3fc7a054e7f3af84623f74fee`。长期归档 `docs/baselines/t3code-ad1b136.tar.gz`，SHA256 `595b64affe9ae78510bbfdcd1cb4f282cade542aa4f8f7c704ea02998321e30a`。本轮未初始化 Git、未提交/发布、未重启现有 T3 服务。

## 已实现

### 公开配置与 Clerk 账号

- 新增 `entry/src/main/resources/rawfile/t3-connect.json`，全部字段为空，不包含任何凭据。只有 Clerk publishable key、JWT template、HTTPS relay URL 三项齐全时才显示 T3 Connect 入口；缺少合法鸿蒙 OAuth client 或回调配置时登录明确禁用。
- 新增 `protocol/Cloud.ts`、`services/CloudAuth.ets`、`storage/CloudStores.ets`：Clerk OAuth authorization-code + PKCE、系统浏览器登录、精确回调 `t3code://auth/callback`、state/PKCE/一次性回调消费、账号 JWT `sub` 提取、登录过期/配置变化时 fail closed。
- 账号会话使用分片 Asset（manifest 最后提交、逐片回读），避免 Clerk token 超过单条 Asset 限制；未截断或退回明文。账号清理/切换先停掉旧实例，再删除旧云环境、令牌缓存和会话。
- 原版 `AuthView/UserProfileView` 是 Clerk Expo 原生组件，未伪造复用。当前实现是标准 OAuth PKCE 路线；`jwtTemplate` 已纳入配置校验，但实际 subject token 是 OAuth 返回的 access token。若真实部署要求 Clerk `session.getToken({ template })` 的定制 JWT claims，仍需合法鸿蒙客户端/适配器，**真实登录与 relay 接受性未验收**。

### DPoP

- `services/Dpop.ets` 使用 CryptoFramework `ECC256|SHA256` 生成/导入 P-256 密钥，私钥/公钥 DER 存于 Asset `DEVICE_UNLOCKED`；加载时校验公私匹配并自签自验。
- `protocol/Cloud.ts` 生成 `typ=dpop+jwt`、`alg=ES256`、public JWK；`htm` 大写、`htu` 去 query/hash、UUID `jti`、秒级 `iat`、可选 `ath`；RFC 7638 thumbprint 固定 `crv/kty/x/y` 顺序。
- Harmony ECDSA DER 签名转换为固定 64 字节 `r‖s`；未加 nonce 字段，未臆造上游不存在的协议。
- 新增隔离诊断页 `scripts/device-checks/CloudDpopCheck.ets`，检查密钥持久化、thumbprint、proof 验签、篡改拒绝、64 字节签名和 htu/ath。签名诊断 HAP 已构建，**尚未在设备运行**；没有把宿主 Node 自检当鸿蒙结果。HUKS 未使用，Asset 锁屏边界本轮未重新执行。

### 中继、环境与令牌

- `services/CloudRelay.ets` 对齐固定上游：`POST /v1/client/dpop-token`、`GET /v1/environments`、环境 link challenge/link/unlink、status/connect、mobile device unregister。
- relay DPoP access token 缓存绑定 account/client/relay/thumbprint/scopes/expiry；`invalid_bearer` 只失效当前 token 并重试一次，不循环重放。缓存按账号校验并在退出/切号时清理。
- `services/CloudConnection.ets` 处理 relay bootstrap credential → 环境 `/oauth/token` DPoP exchange、环境 DPoP token 缓存、RPC ticket、404 回退到裸 ticket、WebSocket `dpop` proof 和 `connectionMethod=relay`；令牌临近过期时重取并保留同一密钥绑定。
- `services/CloudManager.ets` 实现环境发现/状态、link challenge 与 host link-proof/relay-config、账号环境列表、连接、unlink、前台刷新、环境端点轮换。目录中直连与云记录可同时存在同一 `environmentId`，但 localId、凭据、恢复记录独立；云端点变化保留原恢复锚点。
- 环境目录扩展 `kind=bearer|cloud` 与 `cloudAccountId`；云条目不读 Bearer session asset，仍校验恢复记录。R1 的未知提交、环境移除阻断、凭据/路径隔离逻辑未移除。

### 设备批准与 UI

- `T3Client` 保留原直连 Bearer 路径，额外支持 relay transport；新增 `subscribeAuthAccess`、approve/deny/revoke 的 host HTTP 契约和 DPoP/Bearer 自适应。
- 设备代码按固定上游 thumbprint 转换；UI 对等待设备显示系统确认框，并在环境面板提供待批准/已批准设备的批准、拒绝、撤销入口。
- UI 复用原环境 sheet：添加页仅在配置齐全时出现 T3 Connect 入口；Connections 增加 T3 Connect 行；云环境行不显示直连路径编辑；新增账号面板包含服务器、连接、解除账号链接、本机直连环境链接和退出登录。未用 WebView 替代客户端页面，未新增顶层导航。

## 本地验证

- `node --experimental-strip-types --test tests/*.test.mjs`：**153/153 通过**（其中原 R1 119 项全部保留通过）。日志 `docs/evidence/r2/r2-local-tests.log`。
- `./scripts/build.sh`：成功。普通签名 HAP `docs/evidence/r2/r2-candidate-signed.hap`，SHA256 `75fb05fdc3463b3c709cb884cf5e331a0180170a67215ce8f9b36df4f523755b`。日志 `r2-build.log`。
- 固定上游契约审计：14/14 通过，覆盖公开配置、relay URL、DPoP 字段/thumbprint/htu、relay token cache、invalid_bearer、relay/environment link 和设备批准路径。`docs/evidence/r2/upstream-contract.json`、`r2-upstream-contract.log`。
- 新增测试覆盖：配置/回调/状态、DPoP raw 签名与篡改、relay 状态/连接/ticket/token 重取、账号/scope/key 缓存隔离、设备审批流、云存储分片/回读/锁屏、云目录与恢复锚点、直连云共存及注册表账号隔离。
- 宿主自检不等同于真实 relay 或鸿蒙 DPoP；未使用 mock 宣称中继验收通过。

## 外部阻塞

| 阻塞 | 当前事实 | 解除条件 |
|---|---|---|
| Clerk 公开配置 | rawfile 三项均为空 | 用户/构建提供真实 publishable key、JWT template、HTTPS relay URL，并确认可公开 |
| 鸿蒙 OAuth 客户端/回调 | 代码要求 `oauthClientId` 且回调固定 `t3code://auth/callback`；没有真实注册 | Clerk 侧注册合法鸿蒙 OAuth client/redirect，真实验证登录、取消、过期和账号切换 |
| Clerk token 契约 | 当前用 OAuth access token；上游移动组件用 template token | 真实 relay 验证 token claims/audience；若需要 template，补合法适配器 |
| 鸿蒙 DPoP | CryptoFramework+Asset 代码和诊断 HAP 已构建 | 专用机空闲时运行 `cloud-dpop-check-signed.hap`，读回实际结果，再恢复普通 HAP；补锁屏/HUKS 结论 |
| 真实 relay/环境 | 无合法账号、已 link 环境或可测试 relay | 独立账号/环境执行 list→link→connect→ticket→会话→审批/回答→续期→撤销，并验证跨网络 |
| 设备批准/拒绝/撤销 | 客户端入口/HTTP 契约已实现 | 真实 host 发起待批准设备；另一受信任设备完成批准/拒绝/撤销并回读 |

## 未完成/边界

- 未执行真实 Clerk 登录、回调、账号切换或真实 relay；不能据本地 153 项测试宣布 R2 完成。
- 未运行鸿蒙 DPoP 诊断包；未验证 HUKS、真实 Asset 锁屏行为或真实 relay 验签速。诊断 HAP `docs/evidence/r2/cloud-dpop-check-signed.hap`，SHA256 `fd0329ccd57342471a3092210a87b89a864eb0f4d67e34687a66f7d95802b586`，执行状态 `not-run`。
- 原版 Clerk 视觉/交互、云草稿持久化、通知/推送注册、Live Activity、R3–R8 业务未在本轮扩展。
- 普通 HAP 未覆盖安装到专用机；设备上仍是 R1 普通构建。这样避免打断 R1 协作和当前前台应用。恢复/安装验证留给设备空闲后的串行步骤。

## 下一步

1. 提供并注册真实 Clerk/relay 公开配置；不在聊天或证据中记录秘密。
2. 设备空闲后运行 DPoP 诊断 HAP，读回 `r2-dpop-result.json`，恢复普通 HAP；补锁屏/HUKS 结论。
3. 用隔离测试账号与已 link 环境完成真实 relay 闭环、令牌过期重取、撤销、账号切换和直连/云并存。
4. 真实 host/受信任设备完成设备批准、拒绝、撤销，并保留脱敏 trace。
5. 保留 R1 unknown-submit、防重发、环境删除阻断和原 R1 证据不变。
