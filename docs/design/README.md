# 设计基础层：令牌与公共组件

依据：[style-guide.html](style-guide.html)（已确认的设计稿）。颜色来源：原版 `apps/mobile/generated-uniwind-default-theme-variables.json`（上游提交 `ad1b136`，副本见 `docs/baselines/upstream-mobile/`）。

这一层只新增令牌和组件，**不改变任何现有页面的外观**。现有页面按「会话 → 首页 → 设置 / 表单 → 终端 / 文件 / Git」的顺序逐页迁移。

## 1. 颜色令牌

定义在 `entry/src/main/resources/base/element/color.json`（浅色）和 `dark/element/color.json`（深色），两份同名。组件里只能写 `$r('app.color.xxx')`，不要写十六进制色值。ArkUI 颜色带透明度时写成 `#AARRGGBB`。

| 令牌 | 浅色 | 深色 | 原版变量 | 用途 |
|---|---|---|---|---|
| `screen` | `#fcfcfc` | `#0a0a0a` | `--color-screen` | 页面底色 |
| `group` | `#f4f4f5` | `#1a1b1b` | `--color-grouped-card` | 分组页底色、输入区、次要按钮、搜索框 |
| `card` | `#ffffff` | `#111111` | `--color-card` | 分组卡片、列表组 |
| `ink` ⚠ | `#27272a` | `#f4f4f5` | `--color-foreground`（深色应为 `#f5f5f5`） | 正文 |
| `muted` ⚠ | `#6f6f79` | `#a1a1aa` | `--color-foreground-muted`（深色应为 `#838383`） | 次要文字 |
| `muted_tertiary` | `#71717b` | `#818181` | `--color-foreground-tertiary` | 中性角标文字、更弱的说明 |
| `placeholder` | `#6f6f79` | `#838383` | `--color-placeholder` | 占位文字 |
| `icon` / `icon_muted` | `#27272a` / `#71717b` | `#f5f5f5` / `#818181` | `--color-icon(-muted)` | 图标（SVG 目前直接写色值，见下文） |
| `border` ⚠ | `#e4e4e7` | `#2e2e33` | `--color-border`（深色应为 `#191919`） | 描边 |
| `border_subtle` | `#B3E4E4E7` | `#B3191919` | `--color-border-subtle` | 弱描边 |
| `separator` | `#B3E4E4E7` | `#B3191919` | `--color-border-subtle` | 列表 / 分组行之间的分隔线（与设计稿一致取 0.7 透明度；原版 `--color-separator` 为 0.55） |
| `chevron` | `#6B71717B` | `#6B818181` | `--color-chevron` | › 箭头 |
| `dot_separator` | `#5971717B` | `#59818181` | `--color-dot-separator` | 副标题里的 · 分隔点 |
| `primary` ⚠ | `#1b4ed8` | `#6f9bff` | `--color-primary`（深色应为 `#346bf1`） | 开关、选中态、审批「允许」底色 |
| `primary_text` | `#1b4ed8` | `#4b7cf3` | `--color-primary-text` | 链接、文字按钮 |
| `on_primary_fill` | `#ffffff` | `#ffffff` | `--color-primary-foreground` | 蓝色实心按钮上的文字（现有 `on_primary` 深色是 `#0b0b0d`，不能用于蓝底） |
| `prominent` | `#27272a` | `#f5f5f5` | `--color-prominent-action` | 主按钮底色（ink 近黑 / 深色近白） |
| `on_prominent` | `#fcfcfc` | `#0a0a0a` | `--color-prominent-action-foreground` | 主按钮文字 |
| `bubble` / `bubble_ink` | `#efeff1` / `#27272a` | `#161616` / `#f5f5f5` | `--color-user-bubble(-foreground)` | 用户消息气泡 |
| `danger` ⚠ | `#c10007` | `#ff8a8a` | `--color-danger-foreground`（深色应为 `#ff6467`） | 危险文字 |
| `danger_bg` | `#fcebec` | `#301214` | `--color-danger` | 危险按钮 / 角标底 |
| `danger_border` | `#52FB2C36` | `#52FB414A` | `--color-danger-border` | 危险卡片描边 |
| `warning` | `#bb4d00` | `#ffb900` | `--color-warning-foreground` | 警告文字 |
| `warning_bg` | `#fcf4e8` | `#312108` | `--color-warning` | 审批卡片、警告角标底 |
| `warning_border` | `#52FE9A00` | `#52FE9A00` | `--color-warning-border` | 审批卡片描边 |
| `success` | `#146c2e` | `#4ade80` | 原版无，取设计稿（浅色 = 现有 `diff_add_ink`，深色 = 设计稿 `#4ade80`） | 成功文字 |
| `success_bg` | `#e7f6ec` | `#12351f` | 原版无，取现有 `diff_add` | 成功角标底 |
| `info` | `#1b4ed8` | `#51a2ff` | `--color-update-foreground` | 信息文字 |
| `info_bg` | `#e0e6f7` | `#121b34` | `--color-update` | 信息角标底 |
| `input_bg` | `#ffffff` | `#111111` | `--color-input` | 输入框底 |
| `input_border` | `#d4d4d8` | `#1e1e1e` | `--color-input-border` | 输入框描边 |
| `switch_track_off` | `#e4e4e7` | `#262626` | 取设计稿（原版深色 `#111111` 与 card 同色，看不见） | 自绘开关关闭态轨道（系统 Toggle 暂未用） |
| `backdrop` | `#38000000` | `#7A000000` | `--color-backdrop` | 弹层遮罩 |
| `monogram_1..8_fg/_bg` | 见 color.json | 见 color.json | 原版无，取设计稿首页色块 | ProjectMonogram 的 8 组配色 |

⚠ 标记的是**现有颜色名，深色取值与原版不一致**，本步骤没有改（改了会改变现有页面外观）。新组件在深色模式下用到它们时，会暂时沿用旧值，见第 5 节。

ProjectMonogram 配色：浅色是 Tailwind 600/700 字 + 100 底（设计稿首页的 blue / fuchsia / lime / cyan / teal 五组，另补 orange / violet / rose）。为保证可读，lime、cyan、teal、orange 的字色从 600 加深到 700（对比度 ≥ 4.5:1）。深色是 300 字 + 950 底。

## 2. 字号、间距、圆角、尺寸

`entry/src/main/ets/common/Theme.ets`：

```ts
import { FontSize, LineHeight, Weight, Space, Radius, Sizes, Opacity } from '../common/Theme';

Text('会话标题').fontSize(FontSize.headline).lineHeight(LineHeight.headline).fontWeight(Weight.semibold)
```

| 字号（fp） | 行高 | 用途 |
|---|---|---|
| `title` 22 | 28 | 首页字标、空态标题（bold） |
| `headline` 17 | 22 | 标题栏、弹层标题（semibold） |
| `body` 15 | 22 | 消息、列表主行、表单 |
| `callout` 13 | 18 | 列表副行、工具行 |
| `caption` 12 | 16 | 分组标题、时间、提示 |
| `mono` 13 | 19 | 代码、终端、Diff |
| `badge` 11 | 14 | 只用于角标 |

- 字重：`Weight.regular` 400 / `medium` 500 / `semibold` 600；`bold` 700 只给首页字标与空态标题。
- 行高写成 `'NNfp'` 字符串，随系统字号一起放大。
- 间距 `Space`：`xxs` 4 · `xs` 8 · `sm` 12 · `md` 16 · `lg` 24 · `xl` 32 · `page` 16（页面左右边距）。
- 圆角 `Radius`：`badge` 6 · `tool` 10 · `button` 12 · `card` 14 · `bubble` 18 · `composer` 22 · `full` 999。
- 尺寸 `Sizes`：`topBar` 52 · `iconHit` 40 · `icon` 22 · `listRowMin` 56 · `formRowMin` 50 · `buttonHeight` 46 · `buttonHeightCompact` 38 · `monogram` 22 · `chevron` 16 · `hairline` 1。
- `Opacity.disabled` 0.38。

## 3. 公共组件（`entry/src/main/ets/components/ui/`）

所有组件颜色只用 `$r('app.color.xxx')`。回调统一叫 `onTap` / `onBack` / `onToggle`（避开 ArkUI 通用事件名 `onClick`）。

### TopBar

| 属性 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `title` | string | `''` | 17fp semibold，单行省略 |
| `subtitle` | string | `''` | 12fp muted，空则不显示 |
| `showBack` | boolean | false | 显示返回图标按钮（`ui_back`） |
| `backLabel` | string | `'返回'` | 返回按钮读屏文本 |
| `onBack` | () => void | | |
| `actions` | @BuilderParam | 空 | 右侧动作区，可用尾随闭包 |

最低高度 52；系统字号很大时随内容长高，不裁切。

```ts
TopBar({ title: this.thread.title, subtitle: 'r5-round2 · iMac', showBack: true, onBack: () => this.back() }) {
  IconButton({ icon: $r('app.media.ui_more'), label: '更多', onTap: () => this.openMore() })
}
```

### IconButton

`icon: ResourceStr`（非响应式）、`label`（读屏文本，必填）、`disabled`、`iconSize`（默认 22）、`onTap`。40×40 圆形热区，透明底，按下有系统态效果。图标用线形 SVG，`base/media` 和 `dark/media` 各放一份同名文件（浅色描边 `#27272a`，深色 `#f4f4f5`），由系统按深浅色切换。

### AppButton

| 属性 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `label` | string | | |
| `kind` | `'primary' \| 'secondary' \| 'text' \| 'danger' \| 'confirm'` | `'primary'` | 见下 |
| `disabled` | boolean | false | 透明度 0.38，不响应 |
| `loading` | boolean | false | 左侧转圈，不响应 |
| `fill` | boolean | false | 铺满宽度 |
| `compact` | boolean | false | 高 38（卡片 / 对话框按钮组） |
| `a11yLabel` | string | `''` | 读屏文本，默认用 label |
| `onTap` | () => void | | |

- `primary`：`prominent` 底 + `on_prominent` 字，高 46，一屏最多一个。
- `secondary`：`group` 底 + `ink` 字。
- `text`：无底色，`primary_text` 字，高 40，用于标题栏右侧文字动作。
- `danger`：`danger_bg` 底 + `danger` 字。
- `confirm`：`primary` 底 + `on_primary_fill` 字，**只用于审批「允许」**。

```ts
Column() { /* 表单 */ }
AppButton({ label: '保存', fill: true, loading: this.saving, disabled: !this.valid, onTap: () => this.save() })
```

### StatusBadge

ArkUI 内置组件已占用 `Badge`，所以叫 `StatusBadge`。`text`、`tone: 'success' | 'warning' | 'danger' | 'neutral' | 'info'`（默认 neutral：`group` 底 + `muted_tertiary` 字）。11fp medium，圆角 6，内边距 8×2。

```ts
StatusBadge({ text: '等待审批', tone: 'warning' })
```

### SectionHeader

`title`、`showRule`（默认 true，右侧细线）、`collapsible`、`collapsed`、`onToggle`。可折叠时整行可点（最低 40 高），箭头 `ui_chevron_down` 折叠时转 -90°，读屏追加「已折叠 / 已展开」。

### GroupCard + FormRow

`GroupCard`：`title`（组标题，caption muted）、`footnote`（脚注）、`content`（@BuilderParam，可用尾随闭包）。卡片 `card` 底、圆角 14。页面底色用 `group`，父容器左右留 12。

`FormRow`：

| 属性 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `kind` | `'value' \| 'switch' \| 'custom' \| 'multiline' \| 'content'` | `'value'` | |
| `label` | string | | |
| `value` / `placeholder` | string | | value 为空时显示 placeholder（`placeholder` 色） |
| `valueMuted` | boolean | false | 只读信息行的取值用 muted |
| `chevron` | boolean | true | value 行显示 › |
| `checked` | boolean | false | switch 行状态 |
| `disabled` | boolean | false | |
| `destructive` | boolean | false | 标签用 danger 色 |
| `isFirst` | boolean | false | 第一行不画顶部分隔线 |
| `labelWidth` | number | 0 | 0 表示按内容；最多占 60% |
| `onTap` | () => void | | value / multiline 行点击 |
| `onToggle` | (on: boolean) => void | | switch 行切换（点开关或整行都会触发） |
| `trailing` | @BuilderParam | | custom 行的尾部 |
| `body` | @BuilderParam | | content 行的整行内容 |

最低高度 50，左右内边距 14；multiline / content 最低 72。

```ts
GroupCard({ title: '运行位置', footnote: '每次新建线程，使用项目根工作区。' }) {
  FormRow({ label: '项目', value: this.projectName, isFirst: true, onTap: () => this.pickProject() })
  FormRow({ label: '模型', placeholder: '请选择', onTap: () => this.pickModel() })
}
GroupCard({ title: '调度' }) {
  FormRow({ label: '方式', kind: 'custom', isFirst: true, trailing: () => { this.ModeSegments() } })
  FormRow({ label: '启用', kind: 'switch', checked: this.enabled, onToggle: (on: boolean) => { this.enabled = on; } })
}
```

### ProjectMonogram

`projectId`（决定配色，空时用 name）、`name`（提取首字母）、`boxSize`（默认 22）。圆角 6，字号按 vp 固定（不随系统字号放大）。纯装饰，读屏忽略——旁边的项目名负责朗读。

纯逻辑在 `protocol/Monogram.ts`：

- `projectInitials(name)`：取前两个词的首字母（`t3code-harmony` → `TH`），只有一个词时取前两个字符（`T3Code` → `T3`）；camelCase 在小写→大写处拆词（`myProject` → `MP`）；CJK / 符号开头只取一个字符（`拉文克劳` → `拉`）；空名 `?`。
- `monogramTone(id, count = 8)`：FNV-1a 32 位哈希取模，同一 id 永远同色。
- 测试：`tests/monogram.test.mjs`。

## 4. 图标

新增 `ui_chevron_right`、`ui_chevron_down`（base 描边 `#71717b`，dark 描边 `#818181`）。现有 `ui_*` 图标沿用。工程里没有用 `fillColor` 给 SVG 着色的先例，组件继续采用「base / dark 两份同名 SVG」的方式，不依赖 `fillColor` 对描边的支持。

## 5. 现有颜色名与原版不一致清单（本步未改值）

| 名称 | 模式 | 现值 | 原版对应 | 原版值 |
|---|---|---|---|---|
| `canvas` | 深色 | `#121214` | `--color-screen` | `#0a0a0a` |
| `start_window_background` | 深色 | `#121214` | `--color-screen` | `#0a0a0a` |
| `surface` | 深色 | `#1c1c1f` | `--color-grouped-card` | `#1a1b1b` |
| `composer` | 深色 | `#1c1c1f` | `--color-composer-surface` | `rgba(26,27,27,.9)` |
| `composer` | 浅色 | `#F4F4F5` | `--color-composer-surface` | `rgba(244,244,245,.94)`（仅透明度差异） |
| `ink` | 深色 | `#f4f4f5` | `--color-foreground` | `#f5f5f5` |
| `muted` | 深色 | `#a1a1aa` | `--color-foreground-muted` | `#838383` |
| `muted` | 浅色 | `#6f6f79` | 设计稿写的是 `#71717b`（`--color-foreground-tertiary`）；与原版 `--color-foreground-muted` 一致 | `#6f6f79` |
| `selected` | 深色 | `#2a2a2e` | 无直接对应（`--color-thread-selected` `#1a1b1b`，`--color-user-bubble` `#161616`） | — |
| `selected` | 浅色 | `#efeff1` | 无直接对应（值等于 `--color-user-bubble`；`--color-thread-selected` 为 `#ffffff`） | — |
| `border` | 深色 | `#2e2e33` | `--color-border` | `#191919` |
| `primary` | 深色 | `#6f9bff` | `--color-primary` | `#346bf1` |
| `on_primary` | 深色 | `#0b0b0d` | `--color-primary-foreground` | `#ffffff` |
| `danger` | 深色 | `#ff8a8a` | `--color-danger-foreground` | `#ff6467` |
| `diff_add` / `diff_add_ink` / `diff_del` / `diff_del_ink` | 两种 | — | 原版无同名变量 | — |

浅色下 `canvas`、`surface`、`ink`、`danger`、`border`、`primary`、`on_primary`、`start_window_background` 与原版一致。

建议在逐页迁移时：新页面改用 `screen` / `group` 等新令牌；全部页面迁移完后再把上表的深色值改成原版值，或删除旧名。新组件引用的 `ink`、`muted`、`border`、`primary`、`danger` 在此之前深色下会沿用旧值（差异较小，`border` 和 `primary` 最明显）。

## 6. ArkTS 约束与取舍

- `$r()` 只接受字面量，不能拼接 `'monogram_' + n`。ProjectMonogram 用 switch 列出 8 组资源。
- 组件里有两个 `@BuilderParam` 时不能用尾随闭包（FormRow 的 `trailing` / `body`），要按名字传；传父组件的 `@Builder` 时用箭头函数包一层，保证 `this` 指向父组件。
- `@BuilderParam` 无法判断调用方是否传入，可选区域用空 `@Builder` 作默认值；FormRow 通过 `kind` 决定渲染哪个区域。
- 行间分隔线由 FormRow 自己画（顶部 1vp），第一行传 `isFirst: true`。ArkUI 组件拿不到兄弟节点信息，只有 List 有 divider，而分组卡片通常嵌在外层 Scroll 里，不适合再套 List。
- 资源类型（`icon: ResourceStr`）用普通成员而非 `@Prop`，避免装饰器对 Resource 类型的限制；需要切换图标时在父组件用 if/else。
- 组件私有方法避开 `background` / `height` 等通用属性名，统一叫 `fillColorOf()` / `textColorOf()` / `minHeightOf()`。
- 组件名不能与内置组件同名（`Badge` → `StatusBadge`）；`@Prop` 不能与通用属性方法同名（`size`、`width`、`height`、`padding`、`opacity`、`enabled` 等），所以 ProjectMonogram 用 `boxSize`、IconButton 用 `iconSize`、按钮用 `disabled` 而不是 `enabled`。
- TopBar、AppButton 用 `constraintSize({ minHeight })` 而不是固定高度，系统特大字号时不裁切文字。
- 系统 Toggle 只设 `selectedColor(primary)`；关闭态轨道沿用系统默认，`switch_track_off` 留给以后自绘开关。
