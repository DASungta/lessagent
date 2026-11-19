# R7 S18 用量主路径（2026-11-19）

状态：已实现，未构建/未真机验收；不能标记 S18 完成。

固定上游 `ad1b1365999c92c3fc7a054e7f3af84623f74fee`，读取 `/tmp/t3-upstream-r5/t3code-ad1b136`：
- `apps/mobile/src/features/usage/UsageRouteScreen.tsx`、`UsageLimitsPooled.tsx`、`UsageLimitsSection.tsx`、`state/usage.ts`。
- `Stack.tsx` 的 `SettingsUsageAccount` 使用 `UsageLimitAccountScreen`，禁止以深链持久化池快照参数。
- `packages/contracts/src/usage.ts`、`providerUsageLimits.ts`、`server.ts`、`rpc.ts`；`packages/shared/src/usageLimits.ts` 的剩余比例舍入口径。

## 父组件接入

新增 `components/UsagePanel.ets`，入口：`UsagePanel({ connection: 当前T3Client, onBack: 返回设置回调 })`。连接切换时应销毁并重新创建该页面；组件内部也检查连接代际，丢弃旧请求，清除旧数据。未修改 Index、SettingsPanel、T3Client 或公共资源。

实现当前环境今日/7日/30日真实 `server.getUsageSummary`，设备 IANA 时区、提供商和模型筛选、逐日模型明细、USD 和 token 汇总、读取时间、缺定价/部分来源/扫描中提示。金额直接使用服务端 costUsd；输入含缓存读写，reasoning 已计入输出，不再相加。请求保留 settings.usageModelFilter，旧服务未确认过滤规则会提示。请求非 fatal 超时，不断开会话或重发写入。

`server.getConfig` 回读 provider 与 hub/source 账号限额；显示剩余百分比、原重置时间、检查时间、查询失败历史快照和 $0 cap。详情仅保存账号 ID，并从最新 config 快照读取，账号消失明确反馈；不持久化限额路由参数。每 3 秒检查现有配置的账号部分是否更新，不增加轮询 RPC。卡片和列表使用已有主题资源、无固定内容高度、可滚动布局。

## 验证与边界

`node --experimental-strip-types --test tests/usage.test.mjs`：5/5 通过，覆盖金额与 token 口径、筛选、日期、账号来源身份、剩余舍入、重置时间、非法输入、权限、连接代际和服务器过滤规则。

未执行 HAP 构建、设备操作、实际业务 RPC、服务重启；由父任务统一构建和真机回读。账号刷新读取服务端最近快照，不额外强制 provider probe（无探测授权副作用）。未迁移跨环境来源去重/池聚合、完整交互图表、用量来源与价格覆写/模型别名设置、信用额度兑换动作、原版全筛选和实时池估算；页面明确仅当前环境/分账号。最大字体、深浅色、读屏及源账号动态变更仍需真机验收。

## 日趋势补充

核对固定版本 `usageChartData.ts` / `UsageDailyChart.tsx`：原版对同日各 provider 的服务端 costUsd / totalTokens 求和，并按所选指标峰值缩放。已添加 ArkUI 原生行条趋势，可切换费用和 tokens，与当前 provider/model 筛选共享数据。按 day 合并模型与来源记录，只显示实际返回日期，不为缺失日期补零。未定价记录按日提示“金额不完整”，0 金额仍保留未知标记，不等同已知零消费。

限额契约实际限定 usedPercent 为 0–100，因此 >100 不是合法契约值；但原版 `remainingPercent` 会钳位。鸿蒙展示改为相同钳位，并提示“服务端比例超出契约范围”，不会因一项有限越界数值让整个账号页失败；NaN/Infinity 仍拒绝。新增测试覆盖日聚合、筛选一致性、缺日、未定价零金额、峰值和超限显示。补充阶段未构建/未操作设备。

## 显示打磨

总 token 数使用万/亿紧凑显示，明细、趋势和总数读屏标签保留精确值；金额仍直接显示服务端汇总。重复来源提示合并为一次，并将无记录、读取失败、记录不完整/尚未更新与价格状态转为可读中文。短内容和加载态滚动区固定顶部对齐。新增格式化与提示测试后 7/7 通过。未记录真实金额或 token 数，未截图、构建或操作设备。
