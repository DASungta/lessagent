<div align="center">

<p>
  <img src="docs/assets/logo.png" width="112" alt="T3 Code Harmony Logo" />
</p>

<h1>T3 Code Harmony</h1>

<p>
  基于 <strong>ArkTS + ArkUI</strong> 打造的 <strong>T3 Code</strong> 鸿蒙原生客户端 ——<br />
  在手机上直连电脑或服务器端的 T3 Code，随时操控远端 Coding Agent、审阅变更与驱动研发工具。
</p>

<p>
  <img src="https://img.shields.io/badge/HarmonyOS_NEXT-API_24%2B-0A59F7?style=flat-square" alt="HarmonyOS API 24+" />
  <img src="https://img.shields.io/badge/ArkTS_%2B_ArkUI-Native-18181B?style=flat-square" alt="ArkTS + ArkUI Native" />
  <a href="https://github.com/DASungta/t3code-harmony/releases/tag/v0.1.1-preview"><img src="https://img.shields.io/badge/Preview-v0.1.1--preview-2563EB?style=flat-square" alt="Preview v0.1.1-preview" /></a>
  <img src="https://img.shields.io/badge/Tests-562_passing-16A34A?style=flat-square" alt="562 Tests Passing" />
  <img src="https://img.shields.io/badge/License-MIT-52525B?style=flat-square" alt="MIT License" />
</p>

<p>
  <strong>简体中文</strong> · <a href="README.en.md">English</a>
</p>

<p>
  <a href="#界面预览">界面预览</a> ·
  <a href="#核心特性">核心特性</a> ·
  <a href="#日常使用">日常使用</a> ·
  <a href="#本地开发与构建">本地开发与构建</a> ·
  <a href="#项目结构">项目结构</a> ·
  <a href="#工程文档">工程文档</a>
</p>

</div>

---

**T3 Code Harmony** 是 [T3 Code](https://github.com/pingdotgg/t3code) 的独立 HarmonyOS 原生客户端（架构上作为瘦客户端运行，所有 Coding Agent 执行与仓库操作均在桌面端或远端服务端完成）。全套页面、会话流、Markdown、代码高亮、Mermaid 图表与 Diff 审阅均以原生 ArkUI 实现，并在 HUAWEI Mate 60 Pro / Mate 70 Pro 上完成真机联调与视觉对齐。

## 界面预览

| 首页工作台 | 会话与代码高亮 | 文件浏览与原生 Mermaid | Git 变更与提交 |
| :---: | :---: | :---: | :---: |
| <img src="docs/screenshots/promo-v0.1.1/01-home-light.jpeg" width="200" alt="首页工作台（浅色）" /> | <img src="docs/screenshots/promo-v0.1.1/02-chat-light.jpeg" width="200" alt="会话与代码高亮（浅色）" /> | <img src="docs/screenshots/promo-v0.1.1/03-files-mermaid-light.jpeg" width="200" alt="文件浏览与原生 Mermaid（浅色）" /> | <img src="docs/screenshots/promo-v0.1.1/04-git-light.jpeg" width="200" alt="Git 变更与提交（浅色）" /> |

| 分组设置中心 | 关于与版本 v0.1.1 | 深色首页工作台 | 深色会话详情 |
| :---: | :---: | :---: | :---: |
| <img src="docs/screenshots/promo-v0.1.1/05-settings-light.jpeg" width="200" alt="分组设置中心（浅色）" /> | <img src="docs/screenshots/promo-v0.1.1/06-about-version-light.jpeg" width="200" alt="关于与版本 v0.1.1" /> | <img src="docs/screenshots/promo-v0.1.1/07-home-dark.jpeg" width="200" alt="深色首页工作台" /> | <img src="docs/screenshots/promo-v0.1.1/08-chat-dark.jpeg" width="200" alt="深色会话详情" /> |

> 以上截图均采集自 HUAWEI Mate 60 Pro 真机（演示仓库测试数据）。

## 核心特性

- **多环境工作台与会话管理**
  - 支持局域网 / SSH / 回环地址直连配对（手动输入、扫码、深链）以及 T3 Connect / Cloud Relay（OAuth + PKCE + DPoP）。
  - 底部悬浮四栏（`会话 / 拉取请求 / 用量 / 设置`）与新建任务快捷入口；支持仓库、路径与平铺分组、全文搜索、环境与项目筛选、置顶、稍后提醒（Snooze）、Settle、归档与多草稿恢复。
- **原生会话与富媒体渲染**
  - 纯 ArkUI 对话消息流、按轮次分组的可折叠工作日志与检查点、子 Agent 线程查看、工具审批与密钥请求卡片。
  - 原生支持 Markdown、代码语法高亮（支持 8–18 号字号与长行自动换行）、LaTeX 数学公式，以及原生 ArkUI Mermaid 图表（流程图、时序图、类图、状态图）；内置中文离线语音口述草稿。
- **移动端研发工具箱**
  - 随时浏览工作区文件与全文检索、查看支持选行与行级评论的 Diff、执行 Git 状态检查 / 暂存 / 提交 / 分支切换 / 推送拉取。
  - 支持 GitHub Pull Requests 阅读 / 评审 / Guide 导览、会话顶栏直达的远端 ANSI 终端（含回滚与复制）、远端浏览器预览与 iOS Simulator / Android Emulator 设备预览。
- **设计系统与鸿蒙原生集成**
  - 内置 58 组深浅色对称语义颜色令牌（`base/element/color.json` 与 `dark/element/color.json`），WCAG AA（≥ 4.5:1）对比度由自动化测试守门。
  - 支持通过鸿蒙系统分享面板「T3 Harmony」将相册图片或文件直接导入为任务草稿，并提供 2×2 桌面快捷卡片与图标长按快捷入口。

## 日常使用

| 要做的事 | 从哪里进入 |
|---|---|
| **新建任务或继续会话** | 点击底部悬浮栏右下角「新建任务」按钮，或点选已有会话；输入区下方可切换环境、项目、模型与模式。 |
| **管理连接环境** | 点击首页左上角 `T3 Code` 字标，支持手动配对、扫码、深链导入与多连接路径管理。 |
| **搜索与筛选会话** | 点击首页右上角搜索图标检索会话，或点击筛选图标按环境与项目过滤。 |
| **文件、Diff、Git、PR、终端与预览** | 进入会话后，顶栏可直接打开「终端」，或点击右上角「更多」进入文件、Diff、Git、拉取请求、浏览器预览与设备预览。 |
| **从系统分享导入附件** | 在相册或文件管理中选择文件 → 分享 →「T3 Harmony」，核对预览并选择目标项目后存为草稿。 |
| **中文语音口述草稿** | 在会话输入区打开「工具 → 语音输入」，语音识别完成后自动写入输入框。 |
| **代码阅读、项目、工作树与定时任务** | 切换到底部「设置」标签页，按分组配置代码字号（8–18）/ 自动换行、添加项目、源码管理、工作树项目级覆盖、定时任务与深浅色主题。 |

## 本地开发与构建

### 下载预览侧载包

当前项目处于 **Preview** 阶段，可在 [GitHub Releases (`v0.1.1-preview`)](https://github.com/DASungta/t3code-harmony/releases/tag/v0.1.1-preview) 下载预编译的**未签名调试模式 HAP**（`t3code-harmony-v0.1.1-preview-unsigned.hap`，附 SHA-256 校验文件）。

> **HarmonyOS NEXT 侧载说明**：出于系统安全机制，鸿蒙真机拒绝直接安装未签名包，而调试签名又强绑定单台设备 UDID 与个人证书。下载 `unsigned.hap` 后，请使用你自己的华为开发者账号通过社区侧载签名工具（如 AutoInstaller / 鸿蒙侧载助手）或 `hap-sign-tool` + `hdc` 注入调试签名后安装，也可直接克隆源码在 DevEco Studio 中开启自动签名编译安装。

### 环境要求

- **DevEco Studio 6.1.1+** 与 HarmonyOS SDK `6.1.1(24)`（`API 24+`）
- **Node.js 22+**（用于运行 `--experimental-strip-types` 宿主单元测试）
- 电脑或服务器上运行中的 [T3 Code](https://github.com/pingdotgg/t3code) 服务端

### 运行测试与构建 HAP

```bash
git clone https://github.com/DASungta/t3code-harmony.git
cd t3code-harmony

# 运行全部宿主单元测试与主题对比度校验（562/562）
node --experimental-strip-types --test tests/*.test.mjs

# 构建 Debug HAP（可通过 DEVECO_HOME 指定 DevEco Studio 安装路径）
./scripts/build.sh
```

> **签名提示**：如需打包安装到真机，请在 DevEco Studio 中为 `build-profile.json5` 配置你自己的 HarmonyOS 调试签名证书，切勿向公开仓库提交个人签名文件与密钥。

## 项目结构

```text
t3code-harmony/
├── AppScope/                         # 应用元信息 (app.json5)、分层图标与名称
├── entry/src/main/
│   ├── ets/
│   │   ├── common/                   # Theme.ets（字号、行高、间距、圆角与尺寸令牌）
│   │   ├── components/               # 业务面板与 ui/ 基础设计系统组件
│   │   ├── pages/                    # 主入口页面 Index.ets
│   │   ├── protocol/                 # 服务端协议、状态派生、Markdown/Diff/Mermaid 解析
│   │   ├── services/                 # 网络通信、配对认证、远端终端与系统能力桥接
│   │   ├── storage/                  # 本地偏好设置、连接档案与草稿持久化
│   │   ├── entryability/             # 主 Ability 与系统分享 / 深链接入
│   │   └── formextension/            # 2×2 桌面快捷卡片扩展
│   └── resources/
│       ├── base/element/color.json   # 浅色主题 58 组语义颜色令牌
│       ├── dark/element/color.json   # 深色主题 58 组语义颜色令牌
│       └── rawfile/                  # 内置开源许可证与连接预设
├── scripts/                          # 构建脚本与联调 / 真机常亮工具
├── tests/                            # 宿主单元测试与深浅色对比度校验
└── docs/                             # Brand Logo (assets/)、设计规范、迁移计划、宣传截图与证据
```

## 工程文档

- **设计与视觉**：[设计规范与令牌文档](docs/design/README.md) · [可视化风格指南](docs/design/style-guide.html) · [视觉重构真机证据（Step 2–6b）](docs/evidence/visual-refresh)
- **项目进度与计划**：[整体开发状态与真机记录](docs/development-status.md) · [完整移动端迁移计划（R0–R8）](docs/full-mobile-migration-plan.md)
- **对照台账与验收**：[移动端能力矩阵](docs/r0-mobile-capability-matrix.md) · [路由台账](docs/r0-route-ledger.md) · [R6–R8 验收记录](docs/r6-r8-acceptance.md)
- **调试与交接**：[真机调试常亮指南](docs/device-keep-awake.md) · [开发交接说明](docs/开发交接.md)

## 当前边界

当前 `v0.1.1` 已在 HUAWEI Mate 60 Pro / Mate 70 Pro 上完成主链路能力与全站视觉重构收口，但部分依赖外部运行环境的边缘场景（例如外接 iOS Simulator 宿主机、实体蓝牙键盘快捷键全覆盖、独立生产级云中继服务部署以及平板 / 折叠屏多形态响应式矩阵）仍在文档中持续跟踪；宿主单元测试通过亦不能替代完整真机与端到端联调验收。

## 上游与开源协议

- 上游项目：[pingdotgg/t3code](https://github.com/pingdotgg/t3code) · [DASungta/t3code](https://github.com/DASungta/t3code)
- 开源协议：遵循 [MIT License](entry/src/main/resources/rawfile/t3code-license.txt)（应用内置许可证副本）。
