# R5：文件、Markdown、Diff、Git 与 PR

日期：2026-11-18。状态：**R5 客户端主链路已实现，235/235 宿主测试、签名构建和专用 Mate60Pro 真机主路径通过；Git 真实提交/推送、远端不可用、拉取冲突与文件权限错误均完成真机回读；Mermaid 四类图表子集已原生绘制；PR 已用真实 GitHub provider 只读验证列表/详情/文件 Diff/讨论评论/checks，并接入评审向导。PR 写入、KaTeX 视觉等价、其他图表类型（gantt 等）和逐像素/读屏仍未验收。R5 未完整关闭，R4 的未验收状态保持不动。**

固定上游：`DASungta/t3code` `ad1b1365999c92c3fc7a054e7f3af84623f74fee`。项目归档 `docs/baselines/t3code-ad1b136.tar.gz` SHA256 已复核为 `595b64affe9ae78510bbfdcd1cb4f282cade542aa4f8f7c704ea02998321e30a`；本轮没有使用或伪造 Git HEAD。

没有初始化本工程 Git、提交、推送、发布或改动真实业务项目/会话。真机使用专用 `ALN-AL80 / 23E0224122000135`。当前隔离服务为 T3 `0.1.10`：环境 1 在 `127.0.0.1:47895`（base `/tmp/t3-r5-accept-00fcea`），环境 2 在 `127.0.0.1:47896`（base `/tmp/t3-r5-iso2-09506a`）；另有只读项目 `pr-read` 指向 `https://github.com/cli/cli.git`，仅拉取列表/详情/Diff/评论/checks，从未写入。未接触 `3773`/`47831` 的真实服务。

## 当前进度快照（2026-11-18 20:30）

| 维度 | 当前状态 |
|---|---|
| 目标状态 | `blocked`：等授权测试仓库/写权限令牌；服务端向导配置 |
| 宿主测试 | `235/235`；日志 `evidence/r5/r5-local-tests.log` |
| 签名包 | `evidence/r5/r5-candidate-signed.hap`，SHA256 `6bb938588df22d2dc8cb26b3618b706b0537c616048758a28a32d98756b04c36`；设备 updateTime `2026-11-18 20:22:53` |
| 文件/源码 | 文件树、搜索、源码行选/复制/上下文、图片预览、分享/保存、大文件截断、权限错误重试；真机通过 |
| Markdown | GFM 表格/代码/details/数学；Mermaid flowchart/sequence/class/state 原生；gantt 等回退代码块 |
| Diff/审阅 | 工作区/分支 Diff、行选、review-comment 上下文、上一/下一文件；真机 1/3→2/3→1/3 通过 |
| Git | 状态/分支/提交/推送/拉取；远端不可用、冲突/非快进不自动重试；真实提交与 remote 回读通过 |
| PR 只读 | `pr-read` 真实 GitHub #15068：列表/详情/文件 Diff/讨论评论/checks/向导空态与错误态均真机通过 |
| PR 写入 | 未执行；没有授权测试仓库/测试 PR，未向 cli/cli 或任何真实仓库写入 |
| 双环境 | 文件与草稿隔离通过；真实 provider 下跨环境 PR 隔离未测 |
| 视觉/无障碍 | 深色与最大字体抽查通过；Mermaid 标签固定字号；读屏/逐像素未做 |

机器可读快照：[status.json](evidence/r5/status.json)。

## 已实现

### 文件树、源码与媒体

- 新增 `protocol/Files.ts`：工作区条目/目录直系子项、路径拒绝 `..`/绝对路径、读取结果、内容搜索、MIME/二进制判定、文本行拆分上限、工作区资产资源。
- 新增 `components/FilesPanel.ets`，从会话“更多 → 文件与源码”进入；草稿复用同一入口和草稿 cwd。
- 目录逐级浏览、返回上一级、文件名搜索、内容搜索（行号与匹配片段）；目录/图片/视频/音频/PDF/文本分类图标。
- 源码按行显示行号，超长行省略并可横向查看，点行选取、复制选区、加入输入上下文；图片通过 `assets.createUrl` 使用工作区资源直接预览；文件支持系统分享与保存（文件选择器）。
- 文件头支持复制工作区路径、对整个文件添加评论（生成文件级 `review_comment` 上下文）、分享与保存。
- Markdown 文件使用原生 Markdown 预览；视频使用 ArkUI Video；PDF/未知类型保留打开/分享路径，不伪装成内置阅读器。
- 大文件不一次渲染全部行：最多 5000 行并显示截断提示；4,080,000 字节、120,000 行文件在真机打开和滚动不再崩溃。
- 权限拒绝、服务端读取失败显示错误与“重试”，不自动重发修改。

### 完整 Markdown（原版支持项的子集与边界）

- 新增 `protocol/Markdown.ts` 与 `components/MarkdownView.ets`，替换会话中按行解析的基础文本。
- 支持标题（ATX/Setext）、段落、引用、无序/有序/嵌套/任务列表、GFM 表格与对齐、围栏代码、分隔线、链接、行内代码、粗体/斜体/删除线、行内与块级数学、`<details>/<summary>` 折叠、图片/视频块。
- 代码围栏保留语言、复制、换行切换、水平滚动；增加轻量语法着色（关键字/字符串/注释/数字），未引入新依赖。
- 裸 HTML 不直接进入 UI；只保留安全的少量实体解码。链接点击只允许 `http(s)`/`mailto`，图片只允许 `http(s)`/`data:image` 或工作区路径。
- Mermaid：新增 `protocol/Mermaid.ts` + `components/MermaidView.ets` + `components/SequenceView.ets` + `components/ClassDiagramView.ets` + `components/StateDiagramView.ets`。`flowchart/graph TD/TB/LR` 支持简单节点（`[]`/`()`/`{}`/`(())`）、有向边和 `|label|` 标签（BFS 层级，回边不抬层）；`sequenceDiagram` 支持 `participant ... as`、`->>`/`-->>`/`->`/`-->`；`classDiagram` 支持 `class X { members }`、关系与 `: label`；`stateDiagram-v2` 支持 `[*]` 起止点、状态与 `: label` 迁移。真机 `MERMAID.md` 依次显示流程图、序列图、类图、状态图（起止圆点、Idle/Running、start），`gantt` 回退代码块；不支持的语法不猜结构。截图 [流程图](evidence/r5/device/round2/r5-mermaid-dark4.jpeg)、[序列图](evidence/r5/device/round2/r5-mermaid-seq.jpeg)、[类图](evidence/r5/device/round2/r5-mermaid-class.jpeg)、[状态图/回退](evidence/r5/device/round2/r5-mermaid-state.jpeg)。
- 数学使用 Unicode 排版（分数、根号、上下标、常用希腊字母/运算符），不是 KaTeX 级排版；已补 `\dfrac/\tfrac`、`\sqrt[n]{}`、`^\circ`、常用函数名与 `\mathbb{R/N/Z/Q/C}`，并修复单行 `$$...$$` 被解析为空且吞掉后续段落的问题。真机 `MATH.md` 显示 `(a+b)/(c) + ³√(x) + 45° + log₂ n ∈ ℝ`。Mermaid 仅覆盖已列出的四类子集。截图 [数学](evidence/r5/device/round2/r5-math3.jpeg)。

### Diff 与审阅

- 新增 `protocol/R5.ts` 的 unified diff 解析：`diff --git`、新增/删除/修改/重命名、hunk、旧/新行号、二进制标记、长行。
- 新增 `components/ReviewPanel.ets`，从“更多 → 审阅 Diff”进入；支持工作区、分支范围（需输入 baseRef），刷新、文件统计、重命名原路径、长行水平滚动。
- 行选取：点代码行或行号，选中范围高亮；复制选区；评论输入后生成与原版一致的 `<review_comment ...>` 结构化上下文并返回会话输入区。
- 文件详情增加“上一文件/下一文件”和当前位置；二进制/仅元数据文件显示无文本 Diff 提示。
- 服务端 `review.getDiffPreview` 的 `truncated`/`incomplete` 保留为提示；没有用本地假 diff 补全。

### Git

- 新增 `components/GitPanel.ets`：仓库/分支、工作区文件统计、刷新、提交信息、创建功能分支、提交、提交并推送、提交推送并创建 PR、推送、拉取、分支列表与切换。
- 默认分支推送前弹出确认；分支被其他工作树占用显示占位提示，当前 checkout 不再误标“占用”。
- 操作使用 `git.runStackedAction` 的流式进度。真实验收发现成功结果在 `action_finished.result` 而不是 Exit，已修复读取逻辑并增加宿主测试；失败不自动重试。
- `vcs.refreshStatus` 结果直接用于刷新状态，不再依赖订阅推送才能看到工作区变化。
- 上游移动端没有 stage/unstage 独立入口；本轮跟随源码，不为 R5 自创。

### PR

- 新增 `components/PullRequestsPanel.ets`：列表状态筛选、搜索、分页游标、provider 错误保留；空列表明确说明未配置账号/provider，不删除入口。
- 详情：概览、标题/正文 Markdown、状态/分支/增删/文件数、checks、labels、reviewers、编辑标题/正文、评论、审阅 verdict、行内评论草稿、merge/close/reopen/ready/draft、标签与评审人候选请求。
- 讨论评论增加 reaction，讨论线程可标记解决/重新打开；接口按 `pullRequests.setReaction`/`setThreadResolution` 发送。
- 合并方式来自 `mergeMethods`，动作来自 viewer permissions；只读/无权/不可合并时按钮禁用或返回错误，不伪造成功。
- 评审向导/Agent 入口：详情新增“向导”页，读取 `pullRequests.reviewGuide`，显示 stop 标题/摘要、attention（tradeoff/contract/product/risk/accessibility）、文件、摘录行段、行级笔记与待确认问题；`pullRequests.generateReviewGuide` 触发 Agent 生成，“刷新”回读结果，running/stale/failed/empty 都有独立提示。解析与失败态有宿主测试；真实生成尝试被服务端拒绝（见下），未算通过。
- 真实 GitHub provider 只读验证：新建只读项目 `pr-read`（remote `https://github.com/cli/cli.git`，不写入），真机拉取请求页返回真实数据（#15068 等，含 checks/draft 状态）；详情显示标题、分支、`+14 -9`、2 文件与正文，`向导` 页正常渲染空态。截图 [列表](evidence/r5/device/round2/r5-pr-real.jpeg)、[详情](evidence/r5/device/round2/r5-pr-detail.jpeg)、[向导](evidence/r5/device/round2/r5-pr-guide.jpeg)。
- 评审向导真实生成尝试：在 #15068 的“向导”页点“生成”，服务端返回拒绝/任务失败，页面显示“服务端拒绝请求或任务失败…”且不伪造向导内容。截图为 [向导错误态](evidence/r5/device/round2/r5-guide-run.jpeg)。同时修正了空结果时显示“向导基于 ”的文案，改为“还没有保存的评审向导”（代码已构建安装，未在最终包再次逐屏复核）。该能力仍需服务端 `reviewGuidesEnabled`/模型配置和受控测试条件，未算通过。
- 只读验证暴露并修复的真实缺陷：`文件` 页原调用不存在的 `pullRequests.diff` WS 方法，现改为按契约 POST `/api/pull-requests/diff`（Bearer、60s 超时）；真机 #15068 文件页已显示两个文件与 `+9 -9`、`+5 -0`。`讨论` 页的 activity 解析遇到 null 字段会抛“需要字符串”，改为容错取值后，真机已显示 `copilot-pull-request-reviewer` 的完整评论、Details 折叠与 reaction 按钮。截图 [文件](evidence/r5/device/round2/r5-pr-files.jpeg)、[讨论](evidence/r5/device/round2/r5-pr-discussion4.jpeg)。
- Checks：契约字段是 `status`，且需单独调用 `pullRequests.checks`；已补该 RPC 并按 `status` 解析。真机 #15068 概览已显示 CodeQL/build/integration 等 success/skipped 条目及“打开”链接。截图 [Checks](evidence/r5/device/round2/r5-pr-checks.jpeg)。
- 真实 PR 写入未验收：当前只有 `DASungta` 的 `gh` 只读账号与公开仓库 `cli/cli` 的只读项目，没有明确授权的专用测试仓库/测试 PR。未向任何真实仓库创建 PR/评论/合并，也未用 mock 冒充成功。

## 本地检查

```sh
node --experimental-strip-types --test tests/*.test.mjs
./scripts/build.sh
```

- 宿主测试：**235/235**，日志 [r5-local-tests.log](evidence/r5/r5-local-tests.log)。
- 签名构建成功，日志 [r5-final-build.log](evidence/r5/r5-final-build.log)。
- 最终候选 [r5-candidate-signed.hap](evidence/r5/r5-candidate-signed.hap)，SHA256 `6bb938588df22d2dc8cb26b3618b706b0537c616048758a28a32d98756b04c36`（与 `entry/build` 最新产物一致；`bm dump` 的 updateTime 2026-11-18 20:22:53 与安装相符）。已 `hdc install -r` 到专用 Mate60Pro。最终包包含文件路径复制/文件级评论/Diff 文件间导航、深色资源、PR reaction/讨论入口、Mermaid 四种图表子集、PR 评审向导、数学降级修复、HTTP Diff、讨论容错解析、checks 独立读取与向导空态文案修正；文件菜单、文件级评论、深色首页/文件树/Markdown/Diff、`nav-a.txt → nav-b.txt` 显示 `NAV-B` 已通过。
- 新增测试覆盖 Markdown 块/内联/数学/代码着色、文件路径与行上限、diff 解析/选区/审阅上下文、VCS 快照合并、Git/PR 输入校验、PR 权限与列表解析；并增加 Git 流式成功结果和 VCS 直连结果的回归测试。

## 隔离服务回读

证据：[service-readback.json](evidence/r5/service-readback.json)、[service-files-readback.json](evidence/r5/service-files-readback.json)。

- 新项目在隔离 `newProjectsRoot` 创建；根目录、嵌套文件、README 表格、文本读取、条目搜索和内容搜索均回读。
- 工作区 Diff 返回 4 个文件，含新增、修改、重命名、删除二进制；120,000 字节截断场景保留 `truncated=true`。
- 另一个小型改动集返回 3 个文件，包含 2,000 字符长行与 `src/new.ts → src/newer.ts` 重命名，`truncated=false`。
- `projects.readFile` 对 PNG 返回失败；`assets.createUrl` 对工作区 PNG 返回 HTTP 200、70 字节、`image/png`。
- `subscribeVcsStatus` 返回 `isRepo=true`、`main`、5 个改动文件；`git.runStackedAction(commit_push)` 回读提交/推送成功；远程侧提交后 `vcs.pull` 返回 `pulled`；`vcs.createRef`/`switchRef` 到 `r5-branch` 并回切 `main`。
- 该组旧回读所在环境当时没有 provider，`pullRequests.list` 返回 0 个 provider；后续已在只读项目 `pr-read` 上验证真实 GitHub provider（列表/详情/文件 Diff/讨论/checks），见下方 PR 与真机章节。写入仍未验证。

## 专用机真机验收

设备：`HUAWEI Mate 60 Pro / ALN-AL80 / 23E0224122000135`。截图见 [device](evidence/r5/device/)。

- 文件树能区分目录和文件，折叠后只显示当前目录直系子项；源码/图片/Markdown/大文件/权限失败路径均已实际打开。
- 源码选行后出现“已选行 2 / 复制选区 / 加入上下文”；加入后会话输入区出现 `review-comment: src/app.ts · 行 2`。
- Diff 选行后出现“已选 4-4 行 / 复制 / 评论”，提交评论后回到会话并出现第二条 review-comment 上下文。
- Git 页面显示 5 个改动文件；从 UI 输入 `R5 UI commit`，默认分支确认后提交并推送成功，服务端仓库回读提交 `cf3d3d8`。分支页显示 `main`/`r5-branch`，当前分支不再显示“工作树占用”。
- 让 Agent 返回表格、ts 代码块、details 和数学后，真机按原生 Markdown 渲染：表格、代码着色、折叠、Unicode 数学均显示，未回退为纯文本。
- 4 MB 大文件显示“仅显示前 5000 行”并正常滚动；`chmod 000` 文件显示错误和重试，不崩溃。
- PR 页在无 provider 时显示空态说明，并保留筛选、搜索与入口。
- 系统深色模式下首页、文件树、Markdown 预览和 Diff 页面均使用深色背景/文字/图标；浅色已在此之前通过。
- 文件“更多 → 文件评论”可输入并生成 `review-comment: README.md · 文件评论` 上下文；Diff 上一/下一文件切换后修复了相同 hunk 头导致的列表复用，`nav-b.txt` 显示 `NAV-B`。
- 续调轮（16:31–16:35，深色系统 + 最终包）在同一个 `r5-round2` 真机路径复测：文件“复制路径”后输入区出现“来自剪贴板 / README.md”；文件评论生成 `review-comment: README.md · 文件评论`，Diff 选行评论生成 `review-comment: README.md · 行 7`，两条上下文可同时存在。
- Diff 详情显示 `‹ 上一文件`（首文件禁用）/`下一文件 ›`/`1 / 3`，下一文件切到 `src/app.ts` 后为 `2 / 3` 且清空选区；返回后回到 `1 / 3`。Git 页显示 `main` + 3 个改动文件（`README.md +2`、`src/app.ts +1`、`src/new.ts +0`），刷新后提交/推送/拉取可用，分支页只列 `main`。PR 页保留状态筛选与无 provider 空态说明。
- 截图：[composer 双上下文](evidence/r5/device/round2/r5-composer-chips.jpeg)、[Diff 上一/下一文件](evidence/r5/device/round2/r5-diff-dark.jpeg)、[Git 深色](evidence/r5/device/round2/r5-git2-dark.jpeg)、[PR 空态](evidence/r5/device/round2/r5-pr-dark.jpeg)。
- Git 写路径在新隔离服务复测：从 UI 输入 `R5 round2 UI commit` → 默认分支确认 → 结果 `提交 created · 推送 pushed · PR skipped_not_requested`；本地 `22e223b` 与 bare remote `main` 回读一致，随后显示“工作区干净”，`提交` 禁用而推送/拉取仍可用。截图 [Git 提交结果](evidence/r5/device/round2/r5-git-commit-dark.jpeg)。
- Git 异常路径：把测试仓 `origin` 指到不存在的 bare 路径并构造 `领先 1` 后从 UI 推送，界面显示“Git 操作失败：服务端拒绝请求或任务失败…不会自动重试，请核对仓库状态”，状态仍为“领先 1”，没有重复推送；恢复 `origin` 后同一操作成功，remote `main` 回读 `3b1e3c8`，界面变为“工作区干净”。失败态布局回读见 [r5-git-push-failure.layout.json](evidence/r5/device/round2/r5-git-push-failure.layout.json)。
- 文件异常路径：对测试文件 `chmod 000` 后打开，显示“服务端拒绝请求或任务失败…”与“重试”；连续重试不崩溃且不显示伪内容，恢复 `644` 后同一“重试”加载出文件内容。截图 [权限失败](evidence/r5/device/round2/r5-perm-dark.jpeg)、[恢复后](evidence/r5/device/round2/r5-perm-recovered-dark.jpeg)。
- Git 冲突/非快进路径：本地 `main` 与远端 `main` 各自修改 `README.md` 首行形成 `领先 1 / 落后 1`，从 UI 拉取显示“拉取失败：服务端拒绝请求或任务失败…不会自动重试。”；本地未生成 `MERGE_HEAD`、未留下未合并文件，状态保持 `领先 1 / 落后 1`。测试仓随后 `reset --hard origin/main` 复原并刷新为“工作区干净”。截图 [拉取冲突](evidence/r5/device/round2/r5-git-pull-conflict-dark.jpeg)。
- 双环境隔离：另起独立 T3 `0.1.10`（`127.0.0.1:47896`，base `/tmp/t3-r5-iso2-09506a`，项目 `r5-iso2`）并配对为第二个环境。环境 2 的文件树只有 `src`/`README.md`，README 为 `ISO-TWO ONLY / unique-env-two`；切回环境 1 的 `r5-round2` 后文件树为 `assets`/`src`/`README.md`，README 为 `R5 Remote Side` + 原表格，未出现环境 2 内容。截图 [环境 2](evidence/r5/device/round2/r5-iso2-readme.jpeg)、[环境 1](evidence/r5/device/round2/r5-env1-readme.jpeg)。
- 大文件/长行（最终包复测）：`big.txt` 1.33 MB、120,000 行、首行 2,000 字符，打开显示“文件较大，仅显示前 5000 行或服务端预览片段”，首行可横向查看；连续上滑后行号从 32 推进到 93，无崩溃。截图 [大文件深色](evidence/r5/device/round2/r5-bigfile-dark.jpeg)。
- 最大字体：系统“字体大小”调到 **特大（5/5）** 后，会话输入区、文件列表、Markdown 页面标题/正文均放大且未发现裁切或重叠；Mermaid 节点标签仍按图内固定字号绘制（不随系统字体放大），这是当前图表子集的已知无障碍差距。检查后已把系统字体恢复为“标准（2/5）”。截图 [特大-输入区](evidence/r5/device/round2/r5-maxfont-composer.jpeg)、[特大-文件列表](evidence/r5/device/round2/r5-maxfont-files.jpeg)、[特大-Markdown](evidence/r5/device/round2/r5-maxfont-home.jpeg)。
- 一次大文件渲染曾导致应用窗口黑屏/被系统结束；限制预览行数后复测通过。另一次输入过程中窗口黑屏，`aa force-stop` + 重新启动后恢复，具体属于应用生命周期/渲染稳定性风险，不能当成已修复。

### 隔离环境变化

旧隔离目录 `/tmp/t3-r4-accept-gHC0QI` 在 2026-11-18 15:32 左右被 `/tmp` 清理。随后本会话以 `openssl rand` 生成并自建 `/tmp/t3-r5-accept-00fcea`（见下方“续调”节），项目 `r5-round2` 与 bare remote 都在该目录内；不是其他会话的目录。`47893` 上该服务重建后服务器身份变化，客户端按安全规则拒绝发送旧地址的配对凭据，因此续调改用同一 base dir 的 `47895`，未删除旧环境条目，也未触碰 `3773`/`47831`。

## 未验收与边界

| 项目 | 状态 | 需要 |
|---|---|---|
| PR 真实读取（列表/详情/文件 Diff/讨论/checks） | 只读通过 | 真实 GitHub PR #15068 已在专用机回读 |
| PR 写操作（评论/review/reaction/标签/评审人/edit/merge/close/reopen） | 未验收 | 需明确授权的专用测试仓库/测试 PR 与写权限令牌 |
| PR 向导生成 | 未通过 | 服务端拒绝；需开启 `reviewGuidesEnabled` 并配置模型/账号 |
| Mermaid 流程图/序列图/类图/状态图、KaTeX 级数学排版 | 部分实现 | `flowchart TD/LR`、`sequenceDiagram`、简单 `classDiagram`、`stateDiagram-v2` 已原生绘制；gantt 等仍回退代码块，数学仍为 Unicode 降级；不能加 WebView 替代客户端 UI |
| 与原版 Shiki 级代码高亮/宽度/折叠完全一致 | 未验收 | 原版真实页面逐项对照；当前为轻量高亮 |
| 最大字体、深色/浅色、读屏/逐像素 | 部分 | 特大字体下输入区/文件列表/Markdown 无裁切已验证，Mermaid 标签不随字体缩放；读屏与逐像素仍未验收 |
| 深色资源 | 已实现并真机抽查 | 首页/文件树/Markdown/Diff/Git/PR 已通过；settings、深浅切换动画与最大字体/读屏仍需补 |
| 超大 Diff（数百文件）、跨文件选区 | 未实现 | 分页清理、懒渲染；上一/下一文件已实现并修复列表复用 |
| Git 冲突/非快进/认证/worktree 占用错误恢复 | 部分 | 远端不可用、`领先 1/落后 1` 拉取失败与不自动重试、恢复后成功均已真机验证；认证失败与 worktree 占用仍未验收 |
| 视频/PDF/音频内置播放与缩放 | 部分 | 当前图片直接预览；其余走保存/分享/系统路线，未宣称等价 |
| 文件复制路径、文件级评论、Diff 上一/下一文件 | 最终包真机复测通过 | 截图与上下文回读见 `device/round2`；大文件/超大 Diff 仍按上面边界 |
| 双环境同 ID/账号切换下的文件与 PR 隔离 | 文件/草稿已回归，PR 未验收 | 两个独立服务各自项目文件内容与草稿绑定未串；真实 provider 下跨环境 PR 未测 |

## 回退

本轮只修改客户端源码、测试、文档、颜色资源和证据目录；没有服务端迁移、没有真实项目/会话写入。隔离服务 `47895`/`47896` 仍在运行，可停止并删除本轮临时项目/远程仓库；HDC 转发依赖当前交互 shell。设备上仅覆盖安装本应用，保留原有环境与 R4 数据。

本批开始前没有建立 pre-R5 源码归档（工程无 Git）；这是流程缺口。回退按
[changes.json](evidence/r5/changes.json) 的文件清单和当前 hash 逐文件处理，不能整体覆盖其他会话的后续修改。

## 续调：隔离环境重建（2026-11-18 下午）

- 原 `/tmp/t3-r4-accept-gHC0QI` 已被系统清理，`47893` 无监听；旧环境 `b18f0e2c` 的配对随服务端状态一起失效。没有触碰 `3773`/`47831` 的真实服务。
- 以本机 T3 `0.1.10` 重建隔离服务：base dir `/tmp/t3-r5-accept-00fcea`，临时项目 `r5-round2`（含 `README.md` 表格、`src/app.ts`、`assets/icon.svg`），bare remote `/tmp/t3-r5-accept-00fcea/remote.git` 已推送 `main`。`hdc rport tcp:47893 tcp:47893` 已恢复。
- 重新跑 `node --experimental-strip-types --test tests/*.test.mjs`：**219/219** 通过（当前树，未改代码）。
- 复核安装包：设备 `bm dump` 的 `updateTime=1794983993296`（2026-11-18 14:38:53）与 `entry/build` 14:38 的 `entry-default-signed.hap` 一致，SHA256 `e3951c67a6a5d82dbbf5ddf53d2265b093ebd48ad971efc4c86c9c9c08770d1c`；已修正先前文档/readback 里的旧包 hash。
- 服务端 `REVIEW_DIFF_PATCH_MAX_OUTPUT_BYTES = 120000`（上游 `GitVcsDriverCore`），Diff 文本在服务端已有上限并标 `truncated`，因此客户端不再额外加渲染截断；数百文件场景仍属服务端截断后的可用子集，不宣称等价原版。
- 设备仍处于锁屏；`aa start` 返回 `10106102`，按系统要求停止，未关闭开发者模式、未尝试绕过。重新配对（`t3code://pair?…`，token 只存在于本机终端输出，不写入证据）和最终包深色/新增入口的 UI 复核等待手动解锁。

## R5 完成审计（2026-11-18）

| 权威计划要求 | 当前证据 | 状态 |
|---|---|---|
| 文件树、目录/内容搜索、源码/复制/分享、大文件与权限失败 | `FilesPanel` + 真机截图；4 MB/120k 行不崩溃；`chmod 000` 错误/重试/恢复；环境 1/2 文件内容不串 | 通过 |
| 完整 Markdown（块/内联/表格/折叠/数学/代码围栏） | `MarkdownView` 真机表格/代码/details/数学；235 单测覆盖；单行 `$$…$$` 修复 | 通过（数学为 Unicode 降级） |
| Mermaid 图 | flowchart/sequence/class/state 原生绘制并通过真机；gantt 等回退代码块 | 部分（非全部图类型） |
| Diff 解析、选行、评论上下文、上下文件导航、长 Diff | `ReviewPanel` 真机 1/3→2/3→1/3、选区评论；服务端 120 KB `truncated` | 通过 |
| Git 状态/分支/提交/推送/拉取 | 真机提交+推送、bare remote 回读；分支切换；工作区干净 | 通过 |
| Git 错误/冲突路径 | 远端不可用不自动重试；`领先 1/落后 1` 拉取失败且无 `MERGE_HEAD`；恢复后成功 | 通过（认证/worktree 占用除外） |
| PR 列表/详情/checks/向导 | 真实 GitHub 只读 PR #15068 列表/详情/checks/向导空态已通过 | 只读通过 |
| PR 文件 Diff | 真实 GitHub PR #15068 文件页显示两文件与增删行 | 只读通过 |
| PR 讨论 | 真实 #15068 评论、Details、reaction 按钮已显示 | 只读通过 |
| PR reaction/标签/评审人/合并/栈 | 需真实写权限或后续操作 | **未验收** |
| PR 真实写入/评审回读 | 列表/详情/Diff/讨论/checks 只读已通过；写操作没有授权测试 PR | **未验收（外部条件）** |
| 真机正常/异常闭环与脱敏证据 | `docs/evidence/r5/device/round2/*`、`service-*.json`；最大字体/深色/错误恢复 | 通过（读屏/逐像素未做） |
| 235/235 宿主测试 + 签名构建 | `r5-local-tests.log`、`r5-hap.sha256`、`bm dump` updateTime | 通过 |

需要的外部条件：一个明确授权的专用测试 GitHub/GitLab 仓库，以及隔离服务可配置的受控账号/令牌。条件到位后还需验证：PR 创建/评论/inline review/reaction/thread resolve/reviewers/labels/edit/merge/close/reopen、review guide 生成与 stale 回读，以及涉及真实写入后的服务端回读。未向任何真实仓库写入，未用 mock 冒充。


B32 已通过真实 PR 文件名、详情路径及大字号换行真机验收。读取完成后按 PR、项目、连接与请求序号检查身份。[实测与截图](evidence/r8/batch32/README.md)


B33 已验证内容搜索实际滚到源码命中行，复制保留整行原文与 Tab，失效命中单独提示。[真机截图与边界](evidence/r8/batch33/README.md)
