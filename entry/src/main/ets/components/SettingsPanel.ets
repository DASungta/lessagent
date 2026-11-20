import { TopBar } from './ui/TopBar';
import { GroupCard } from './ui/GroupCard';
import { FormRow } from './ui/FormRow';
import { AppButton } from './ui/AppButton';
import { FontSize, LineHeight, Radius, Sizes, Space, Weight } from '../common/Theme';
import { WorktreeStoragePanel } from './WorktreeStoragePanel';
import { SourceControlSettingsPanel } from './SourceControlSettingsPanel';
import { systemShare } from '@kit.ShareKit';
import { ServiceMaintenancePanel } from './ServiceMaintenancePanel';
import { LabsSettingsPanel } from './LabsSettingsPanel';
import { AutoSettlePanel } from './AutoSettlePanel';
import { ThreadDefaultsPanel } from './ThreadDefaultsPanel';
import { StorageSettingsPanel } from './StorageSettingsPanel';
import { UsagePanel } from './UsagePanel';
import { ScheduledTasksPanel } from './ScheduledTasksPanel';
import { EnvironmentEntry } from '../protocol/Environment';
import { ProviderSettingsPanel } from './ProviderSettingsPanel';
import { FollowUpSettingsPanel } from './FollowUpSettingsPanel';
import { KeyboardHelpPanel } from './KeyboardHelpPanel';
import { NotificationSettingsPanel } from './NotificationSettingsPanel';
import { T3Client } from '../services/T3Client';
import { WorktreeSettingsPanel } from './WorktreeSettingsPanel';
import { ProjectWorktreeSettingsPanel } from './ProjectWorktreeSettingsPanel';
import { ScopedProject } from '../protocol/Projects';
import { bundleManager, common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { currentAppearance, saveAppearance } from '../services/Appearance';
import { diagnosticSummary, settingsMatch } from '../protocol/Settings';
import { setUseLastProjectForNewThreads, workspacePrefs, setCodeFontSize, setCodeWordBreak, DEFAULT_CODE_FONT_SIZE,
  MIN_CODE_FONT_SIZE, MAX_CODE_FONT_SIZE } from '../services/WorkspacePrefs';

const CODE_APPEARANCE_SEARCH = '外观 代码 字号 字体 差异 自动换行 diff code font size word break wrap';

const WORKTREE_SEARCH = '工作树 worktree 远程起点 远程分支 子模块 分支命名 前缀';
const WORKTREE_STORAGE_SEARCH = '工作树存储 目录位置 自动清理规则 本地文件保护 worktree storage';
const SOURCE_CONTROL_SEARCH = '源码管理 Git 克隆目录 布局 ghq 默认添加项目目录 自动拉取 Agent 署名 合并';

@Component
export struct SettingsPanel {
  @Prop environments: EnvironmentEntry[] = [];
  @Prop projects: ScopedProject[] = [];
  @Prop activeLocalId: string = '';
  connection: T3Client | undefined = undefined;
  @Prop connectionReady: boolean = false;
  @Prop scheduledConnectionKey: string = '';
  @Prop settingsWriteAllowed: boolean | undefined = undefined;
  connectionFor: (localId: string) => T3Client | undefined = () => undefined;
  @State query: string = '';
  @Link section: string;
  @State version: string = 'unknown';
  @State notice: string = '';
  @State sharingDiagnostics: boolean = false;
  @State license: string = '';
  @State appearance: string = currentAppearance;
  @State savingAppearance: boolean = false;
  @State codeFontSize: number | null = workspacePrefs.codeFontSize;
  @State codeWordBreak: boolean = workspacePrefs.codeWordBreak;
  @State savingCodeAppearance: boolean = false;
  @State codeFontNotice: string = '';
  @State savingWorkingShelf: boolean = false;
  @State useLastProject: boolean = workspacePrefs.useLastProjectForNewThreads;
  @State savingLastProject: boolean = false;
  @Prop workingShelfEnabled: boolean = true;
  @Prop embedded: boolean = false;
  @Prop bottomInset: number = 0;
  onWorkingShelf: (enabled: boolean) => Promise<void> = async () => {};

  aboutToAppear(): void {
    try { this.version = bundleManager.getBundleInfoForSelfSync(0).versionName; }
    catch (_) { this.notice = '无法读取客户端版本'; }
  }

  private async changeAppearance(mode: string): Promise<void> {
    if (this.savingAppearance) return;
    this.savingAppearance = true;
    try {
      await saveAppearance(this.getUIContext().getHostContext() as common.Context, mode);
      this.appearance = mode;
      this.notice = '';
    } catch (_) { this.notice = '外观保存失败，请重试'; }
    finally { this.savingAppearance = false; }
  }

  private visibleCodeFontSize(): number { return this.codeFontSize ?? DEFAULT_CODE_FONT_SIZE; }

  private async changeCodeFontSize(value: number | null): Promise<void> {
    if (this.savingCodeAppearance || this.codeFontSize === value) return;
    this.savingCodeAppearance = true;
    this.codeFontNotice = '';
    try {
      await setCodeFontSize(value);
      this.codeFontSize = workspacePrefs.codeFontSize;
    } catch (_) {
      this.codeFontNotice = '代码字号保存失败，请重试';
    } finally { this.savingCodeAppearance = false; }
  }

  private async changeCodeWordBreak(): Promise<void> {
    if (this.savingCodeAppearance) return;
    this.savingCodeAppearance = true;
    this.codeFontNotice = '';
    try {
      await setCodeWordBreak(!this.codeWordBreak);
      this.codeWordBreak = workspacePrefs.codeWordBreak;
    } catch (_) {
      this.codeFontNotice = '代码换行设置保存失败，请重试';
    } finally { this.savingCodeAppearance = false; }
  }

  private async changeWorkingShelf(): Promise<void> {
    if (this.savingWorkingShelf) return;
    this.savingWorkingShelf = true;
    try { await this.onWorkingShelf(!this.workingShelfEnabled); this.notice = ''; }
    catch (_) { this.notice = '工作中分组保存失败，请重试'; }
    finally { this.savingWorkingShelf = false; }
  }

  private async changeUseLastProject(): Promise<void> {
    if (this.savingLastProject) return;
    this.savingLastProject = true;
    try {
      await setUseLastProjectForNewThreads(!this.useLastProject);
      this.useLastProject = workspacePrefs.useLastProjectForNewThreads;
      this.notice = '';
    } catch (_) { this.notice = '最近项目设置保存失败，请重试'; }
    finally { this.savingLastProject = false; }
  }

  private async openLicense(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.Context;
      const bytes = await context.resourceManager.getRawFileContent('t3code-license.txt');
      this.license = util.TextDecoder.create('utf-8').decodeToString(bytes);
      this.section = 'license';
    } catch (_) { this.notice = '许可文件读取失败，请重试'; }
  }

  private summary(): string {
    return diagnosticSummary(this.version, this.environmentCount, this.projectCount, this.archivedCount);
  }

  private async copyDiagnostics(): Promise<void> {
    try {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.summary()));
      this.notice = '诊断摘要已复制';
    } catch (_) { this.notice = '复制失败，请重试'; }
  }

  private async shareDiagnostics(): Promise<void> {
    if (this.sharingDiagnostics) return;
    this.sharingDiagnostics = true; this.notice = '';
    try {
      const summary = this.summary();
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const data = new systemShare.SharedData({ utd: 'general.plain-text', content: summary });
      await new systemShare.ShareController(data).show(context, {});
      this.notice = '已打开系统分享，请选择接收应用或取消';
    } catch (_) { this.notice = '无法打开系统分享，可改用复制诊断摘要'; }
    finally { this.sharingDiagnostics = false; }
  }

  @Prop groupingMode: string = 'repository';
  @Prop projectCount: number = 0;
  @Prop archivedCount: number = 0;
  @Prop environmentCount: number = 0;
  onBack: () => void = () => {};
  onEnvironments: () => void = () => {};
  onProjects: () => void = () => {};
  onArchive: () => void = () => {};
  onGrouping: (mode: string) => void = () => {};

  private isFirstVisible(keywords: string[], index: number): boolean {
    for (let i = 0; i < index; i++) {
      if (settingsMatch(this.query, keywords[i])) return false;
    }
    return true;
  }

  private anyVisible(keywords: string[]): boolean {
    return keywords.some((item: string) => settingsMatch(this.query, item));
  }

  private workspaceSectionKeywords(): string[] {
    return [
      '工作中 Working 会话 分组 排序',
      WORKTREE_STORAGE_SEARCH,
      SOURCE_CONTROL_SEARCH,
      '服务维护 更新 版本 数据库 存储 maintenance',
      '实验功能 Labs Beta 工作树',
      '自动归整 Settle 闲置 合并 会话',
      '新任务 默认 权限 工作区 流式 浏览器',
      '最近项目 上次 使用项目 新任务 默认 last project'
    ];
  }

  private envSectionKeywords(): string[] {
    return [
      WORKTREE_SEARCH,
      'Provider 模型 账号 登录',
      '会话 后续消息 排队 引导',
      '键盘 快捷键'
    ];
  }

  private notifyToolsKeywords(): string[] {
    return [
      '通知 提醒 完成 任务 在线',
      '用量 限额 费用 usage',
      '定时任务 计划 scheduled',
      '存储 缓存 清理 临时 文件'
    ];
  }

  @Builder
  row(title: string, detail: string, value: string, isFirst: boolean, action: () => void) {
    FormRow({
      kind: 'value',
      label: title,
      subtitle: detail,
      value,
      valueMuted: true,
      isFirst,
      onTap: action
    })
  }

  @Builder
  appearanceChoice(title: string, detail: string, mode: string, isFirst: boolean) {
    FormRow({
      kind: 'choice',
      label: title,
      subtitle: detail,
      checked: this.appearance === mode,
      disabled: this.savingAppearance,
      isFirst,
      onTap: () => { void this.changeAppearance(mode); }
    })
  }

  @Builder
  choice(title: string, detail: string, value: string, isFirst: boolean) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: Space.sm }) {
        Column({ space: 2 }) {
          Text(title).fontSize(FontSize.body).lineHeight(LineHeight.body).fontWeight(Weight.regular)
            .fontColor($r('app.color.ink')).width('100%')
          Text(detail).fontSize(FontSize.caption).lineHeight(LineHeight.caption)
            .fontColor($r('app.color.muted')).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Text(this.groupingMode === value ? '✓' : '')
          .fontSize(FontSize.headline).fontWeight(Weight.semibold).fontColor($r('app.color.primary'))
          .width(20).textAlign(TextAlign.End).accessibilityLevel('no')
      }.width('100%').padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs }).constraintSize({ minHeight: Sizes.formRowMin })
    }
    .width('100%').backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
    .border({ width: { top: isFirst ? 0 : Sizes.hairline }, color: { top: $r('app.color.separator') } })
    .accessibilityText(title + (this.groupingMode === value ? '，已选中' : ''))
    .onClick(() => this.onGrouping(value))
  }

  @Builder
  sectionLabel(title: string) {
    Text(title)
      .fontSize(FontSize.caption)
      .lineHeight(LineHeight.caption)
      .fontColor($r('app.color.muted'))
      .padding({ left: Space.xxs, right: Space.xxs, top: Space.sm, bottom: 5 })
      .width('100%')
  }

  build() {
    if (this.section === 'source-control') {
      SourceControlSettingsPanel({ connection: this.connection, connectionReady: this.connectionReady, settingsWriteAllowed: this.settingsWriteAllowed,
        environmentLabel: this.connection ?
          this.environments.find((entry: EnvironmentEntry) => this.connectionFor(entry.localId) === this.connection)?.label || '' : '',
        onBack: () => this.section = '' })
    } else if (this.section === 'worktree-storage') {
      WorktreeStoragePanel({ connection: this.connection, settingsWriteAllowed: this.settingsWriteAllowed, onBack: () => this.section = '' })
    } else if (this.section === 'maintenance') {
      ServiceMaintenancePanel({ connection: this.connection, onBack: () => this.section = '' })
    } else if (this.section === 'labs') {
      LabsSettingsPanel({ environments: this.environments, connectionFor: this.connectionFor, onBack: () => this.section = '' })
    } else if (this.section === 'auto-settle') {
      AutoSettlePanel({ connection: this.connection, onBack: () => this.section = '' })
    } else if (this.section === 'thread-defaults') {
      ThreadDefaultsPanel({ connection: this.connection, onBack: () => this.section = '' })
    } else if (this.section === 'storage') {
      StorageSettingsPanel({ environments: this.environments, onBack: () => this.section = '' })
    } else if (this.section === 'usage') {
      UsagePanel({ connection: this.connection, onBack: () => this.section = '' })
    } else if (this.section === 'schedules') {
      ScheduledTasksPanel({ connection: this.connection, connectionKey: this.scheduledConnectionKey,
        scopedProjects: this.projects, activeLocalId: this.activeLocalId, onBack: () => this.section = '' })
    } else if (this.section === 'providers') {
      ProviderSettingsPanel({ connection: this.connection, onBack: () => this.section = '' })
    } else if (this.section === 'followup') {
      FollowUpSettingsPanel({ onBack: () => this.section = '' })
    } else if (this.section === 'keyboard') {
      KeyboardHelpPanel({ onBack: () => this.section = '' })
    } else if (this.section === 'notifications') {
      NotificationSettingsPanel({ onBack: () => this.section = '' })
    } else if (this.section === 'worktree-project') {
      ProjectWorktreeSettingsPanel({ environments: this.environments, projects: this.projects,
        connectionFor: this.connectionFor, onBack: () => this.section = 'worktrees' })
    } else if (this.section === 'worktrees') {
      WorktreeSettingsPanel({ connection: this.connection, settingsWriteAllowed: this.settingsWriteAllowed,
        onBack: () => this.section = '', onProjects: () => this.section = 'worktree-project' })
    } else {
    Column({ space: 0 }) {
      if (!this.embedded || this.section.length > 0) {
        TopBar({
          title: this.section === 'diagnostics' ? '诊断' : this.section === 'about' ? '关于' : this.section === 'license' ? '开源许可' : '设置',
          showBack: true,
          backLabel: this.section ? '返回设置' : '返回会话',
          onBack: () => { if (this.section) { this.section = ''; this.notice = ''; } else this.onBack(); }
        })
      } else {
        Row() {
          Text('设置')
            .fontSize(FontSize.title)
            .lineHeight(LineHeight.title)
            .fontWeight(Weight.bold)
            .fontColor($r('app.color.ink'))
            .layoutWeight(1)
        }
        .width('100%')
        .constraintSize({ minHeight: Sizes.topBar })
        .padding({ left: Space.md, right: Space.md, top: Space.xxs, bottom: Space.xxs })
        .alignItems(VerticalAlign.Center)
      }
      Scroll() {
        Column({ space: 0 }) {
          if (this.notice) {
            Text(this.notice)
              .fontSize(FontSize.callout)
              .lineHeight(LineHeight.callout)
              .fontColor($r('app.color.primary_text'))
              .padding({ left: Space.xxs, right: Space.xxs, bottom: Space.xs })
              .width('100%')
          }
          if (this.section === 'diagnostics') {
            GroupCard({ title: '安全摘要', footnote: '不包含密钥、Token 或消息正文。' }) {
              Text(this.summary())
                .fontSize(FontSize.body)
                .lineHeight(LineHeight.body)
                .fontFamily('monospace')
                .fontColor($r('app.color.ink'))
                .copyOption(CopyOptions.LocalDevice)
                .padding({ left: 14, right: 14, top: Space.sm, bottom: Space.sm })
                .width('100%')
            }
            GroupCard() {
              this.row('复制诊断摘要', '仅复制本页所列信息', '', true, () => { void this.copyDiagnostics(); })
            }
            Column() {
              AppButton({
                label: '分享诊断摘要',
                kind: 'primary',
                fill: true,
                loading: this.sharingDiagnostics,
                onTap: () => { void this.shareDiagnostics(); }
              })
            }.width('100%').padding({ top: Space.md })
          } else if (this.section === 'about') {
            Column({ space: 6 }) {
              Text('T3 Code Harmony')
                .fontSize(FontSize.title)
                .lineHeight(LineHeight.title)
                .fontWeight(Weight.bold)
                .fontColor($r('app.color.ink'))
              Text('鸿蒙原生客户端 · ' + this.version)
                .fontSize(FontSize.callout)
                .lineHeight(LineHeight.callout)
                .fontColor($r('app.color.muted'))
              Text('在手机上连接你的工作环境，继续项目与会话。')
                .fontSize(FontSize.body)
                .lineHeight(LineHeight.body)
                .fontColor($r('app.color.ink'))
                .padding({ top: Space.xs })
            }
            .width('100%')
            .padding({ left: Space.xxs, right: Space.xxs, top: Space.sm, bottom: Space.xs })
            .alignItems(HorizontalAlign.Start)
            GroupCard({ footnote: '此版本为独立鸿蒙客户端。客户端版本与所连接的服务端版本分别管理。' }) {
              this.row('T3 Code 开源许可', 'MIT · T3 Tools Inc.', '', true, () => { void this.openLicense(); })
            }
          } else if (this.section === 'license') {
            GroupCard() {
              Text(this.license)
                .fontSize(FontSize.callout)
                .lineHeight(LineHeight.callout)
                .fontColor($r('app.color.ink'))
                .padding({ left: 14, right: 14, top: Space.sm, bottom: Space.sm })
                .width('100%')
                .copyOption(CopyOptions.LocalDevice)
            }
          } else {
            Row({ space: Space.xs }) {
              Image($r('app.media.ui_search'))
                .width(16)
                .height(16)
                .opacity(0.6)
                .accessibilityLevel('no')
              TextInput({ placeholder: '搜索设置', text: this.query })
                .layoutWeight(1)
                .height(40)
                .fontSize(FontSize.body)
                .fontColor($r('app.color.ink'))
                .placeholderColor($r('app.color.placeholder'))
                .backgroundColor(Color.Transparent)
                .padding(0)
                .accessibilityText('搜索设置')
                .onChange(value => this.query = value)
            }
            .width('100%')
            .padding({ left: Space.sm, right: Space.sm })
            .backgroundColor($r('app.color.card'))
            .borderRadius(Radius.button)
            .margin({ top: Space.xxs, bottom: Space.xs })
            .alignItems(VerticalAlign.Center)

            if (settingsMatch(this.query, '连接与项目 环境 连接 路径 T3 Connect 项目 归档 恢复 删除')) {
              Text('连接与项目')
                .fontSize(FontSize.caption)
                .lineHeight(LineHeight.caption)
                .fontColor($r('app.color.muted'))
                .padding({ left: Space.xxs, right: Space.xxs, top: Space.sm, bottom: 5 })
                .width('100%')
              Column() {
                Button({ type: ButtonType.Normal }) {
                  Row({ space: 10 }) {
                    Column({ space: 2 }) {
                      Text('环境').fontSize(FontSize.body).lineHeight(LineHeight.body).fontWeight(Weight.regular).width('100%')
                      Text('连接、路径与 T3 Connect').fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted')).width('100%')
                    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                    Text(String(this.environmentCount)).fontSize(FontSize.callout).fontColor($r('app.color.muted'))
                    Image($r('app.media.ui_chevron_right')).width(Sizes.chevron).height(Sizes.chevron).opacity(0.6).accessibilityLevel('no')
                  }.width('100%').padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs }).constraintSize({ minHeight: Sizes.formRowMin })
                }.width('100%').backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
                  .onClick(() => this.onEnvironments())
                Button({ type: ButtonType.Normal }) {
                  Row({ space: 10 }) {
                    Column({ space: 2 }) {
                      Text('项目').fontSize(FontSize.body).lineHeight(LineHeight.body).fontWeight(Weight.regular).width('100%')
                      Text('管理工作区与项目').fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted')).width('100%')
                    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                    Text(String(this.projectCount)).fontSize(FontSize.callout).fontColor($r('app.color.muted'))
                    Image($r('app.media.ui_chevron_right')).width(Sizes.chevron).height(Sizes.chevron).opacity(0.6).accessibilityLevel('no')
                  }.width('100%').padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs }).constraintSize({ minHeight: Sizes.formRowMin })
                }.width('100%').backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
                  .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
                  .onClick(() => this.onProjects())
                Button({ type: ButtonType.Normal }) {
                  Row({ space: 10 }) {
                    Column({ space: 2 }) {
                      Text('归档会话').fontSize(FontSize.body).lineHeight(LineHeight.body).fontWeight(Weight.regular).width('100%')
                      Text('恢复或删除已归档会话').fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted')).width('100%')
                    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                    Text(String(this.archivedCount)).fontSize(FontSize.callout).fontColor($r('app.color.muted'))
                    Image($r('app.media.ui_chevron_right')).width(Sizes.chevron).height(Sizes.chevron).opacity(0.6).accessibilityLevel('no')
                  }.width('100%').padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs }).constraintSize({ minHeight: Sizes.formRowMin })
                }.width('100%').backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
                  .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
                  .onClick(() => this.onArchive())
              }.width('100%').backgroundColor($r('app.color.card')).borderRadius(Radius.card).clip(true)
            }

            if (settingsMatch(this.query, '项目分组 仓库 路径 独立')) {
              Text('项目分组')
                .fontSize(FontSize.caption)
                .lineHeight(LineHeight.caption)
                .fontColor($r('app.color.muted'))
                .padding({ left: Space.xxs, right: Space.xxs, top: Space.sm, bottom: 5 })
                .width('100%')
              Column() {
                this.choice('按仓库分组', '同一仓库的多个工作区合并显示。', 'repository', true)
                this.choice('按仓库路径分组', '同一仓库的不同路径保持分开。', 'repository_path', false)
                this.choice('保持独立', '每个工作区单独显示。', 'separate', false)
              }.width('100%').backgroundColor($r('app.color.card')).borderRadius(Radius.card).clip(true)
              Text('项目分组使用本机偏好；会话固定/活跃顺序由服务端保存。')
                .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted'))
                .width('100%').padding({ left: 6, right: 6, top: 6 })
            }

            if (this.anyVisible(this.workspaceSectionKeywords())) {
              this.sectionLabel('会话与工作区')
              Column() {
                if (settingsMatch(this.query, '工作中 Working 会话 分组 排序')) {
                  Button({ type: ButtonType.Normal }) {
                    Row({ space: 10 }) {
                      Column({ space: 2 }) {
                        Text('工作中分组').fontSize(FontSize.body).lineHeight(LineHeight.body).fontWeight(Weight.regular).width('100%')
                        Text('开启后将运行中的会话单独分组，活跃会话按返回时间排序。')
                          .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted')).width('100%')
                      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                      Text(this.workingShelfEnabled ? '已开启' : '已关闭')
                        .fontSize(FontSize.callout)
                        .fontWeight(Weight.medium)
                        .fontColor(this.workingShelfEnabled ? $r('app.color.primary_text') : $r('app.color.muted'))
                    }.width('100%').padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs }).constraintSize({ minHeight: Sizes.formRowMin })
                  }.width('100%').backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
                    .border({ width: { top: this.isFirstVisible(this.workspaceSectionKeywords(), 0) ? 0 : Sizes.hairline }, color: { top: $r('app.color.separator') } })
                    .enabled(!this.savingWorkingShelf)
                    .accessibilityText(this.workingShelfEnabled ? '工作中分组，已开启' : '工作中分组，已关闭')
                    .onClick(() => { void this.changeWorkingShelf(); })
                }
                if (settingsMatch(this.query, WORKTREE_STORAGE_SEARCH)) {
                  this.row('工作树存储', '目录位置与自动清理规则', '', this.isFirstVisible(this.workspaceSectionKeywords(), 1), () => this.section = 'worktree-storage')
                }
                if (settingsMatch(this.query, SOURCE_CONTROL_SEARCH)) {
                  this.row('源码管理', '克隆布局、项目目录、自动拉取与合并署名', '', this.isFirstVisible(this.workspaceSectionKeywords(), 2), () => this.section = 'source-control')
                }
                if (settingsMatch(this.query, '服务维护 更新 版本 数据库 存储 maintenance')) {
                  this.row('服务维护', '版本、数据库与更新状态', '', this.isFirstVisible(this.workspaceSectionKeywords(), 3), () => this.section = 'maintenance')
                }
                if (settingsMatch(this.query, '实验功能 Labs Beta 工作树')) {
                  this.row('实验功能', '按环境管理实验选项', '', this.isFirstVisible(this.workspaceSectionKeywords(), 4), () => this.section = 'labs')
                }
                if (settingsMatch(this.query, '自动归整 Settle 闲置 合并 会话')) {
                  this.row('自动归整会话', '合并与闲置会话的自动整理规则', '', this.isFirstVisible(this.workspaceSectionKeywords(), 5), () => this.section = 'auto-settle')
                }
                if (settingsMatch(this.query, '新任务 默认 权限 工作区 流式 浏览器')) {
                  this.row('新任务默认设置', '当前环境的权限、工作区与响应行为', '', this.isFirstVisible(this.workspaceSectionKeywords(), 6), () => this.section = 'thread-defaults')
                }
                if (settingsMatch(this.query, '最近项目 上次 使用项目 新任务 默认 last project')) {
                  Button({ type: ButtonType.Normal }) {
                    Row({ space: 10 }) {
                      Column({ space: 2 }) {
                        Text('使用最近项目').fontSize(FontSize.body).lineHeight(LineHeight.body).fontWeight(Weight.regular).width('100%')
                        Text('开启后优先使用当前或筛选的项目，其次使用最近项目。')
                          .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted')).width('100%')
                      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                      Text(this.useLastProject ? '已开启' : '已关闭')
                        .fontSize(FontSize.callout)
                        .fontWeight(Weight.medium)
                        .fontColor(this.useLastProject ? $r('app.color.primary_text') : $r('app.color.muted'))
                    }.width('100%').padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs }).constraintSize({ minHeight: Sizes.formRowMin })
                  }.width('100%').backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
                    .border({ width: { top: this.isFirstVisible(this.workspaceSectionKeywords(), 7) ? 0 : Sizes.hairline }, color: { top: $r('app.color.separator') } })
                    .enabled(!this.savingLastProject)
                    .accessibilityText(this.useLastProject ? '使用最近项目，已开启' : '使用最近项目，已关闭')
                    .onClick(() => { void this.changeUseLastProject(); })
                }
              }.width('100%').backgroundColor($r('app.color.card')).borderRadius(Radius.card).clip(true)
            }

            if (this.anyVisible(this.envSectionKeywords())) {
              this.sectionLabel('环境设置')
              Column() {
                if (settingsMatch(this.query, WORKTREE_SEARCH)) {
                  this.row('工作树', '远程起点、子模块与分支命名', '', this.isFirstVisible(this.envSectionKeywords(), 0), () => this.section = 'worktrees')
                }
                if (settingsMatch(this.query, 'Provider 模型 账号 登录')) {
                  this.row('Provider 与模型', '模型目录、状态与登录', '', this.isFirstVisible(this.envSectionKeywords(), 1), () => this.section = 'providers')
                }
                if (settingsMatch(this.query, '会话 后续消息 排队 引导')) {
                  this.row('后续消息', '运行中消息的处理方式', '', this.isFirstVisible(this.envSectionKeywords(), 2), () => this.section = 'followup')
                }
                if (settingsMatch(this.query, '键盘 快捷键')) {
                  this.row('键盘快捷键', '查看可用的键盘操作', '', this.isFirstVisible(this.envSectionKeywords(), 3), () => this.section = 'keyboard')
                }
              }.width('100%').backgroundColor($r('app.color.card')).borderRadius(Radius.card).clip(true)
            }

            if (this.anyVisible(this.notifyToolsKeywords())) {
              this.sectionLabel('通知与记录')
              Column() {
                if (settingsMatch(this.query, '通知 提醒 完成 任务 在线')) {
                  this.row('任务通知', '在线任务完成提醒与会话定位', '', this.isFirstVisible(this.notifyToolsKeywords(), 0), () => this.section = 'notifications')
                }
                if (settingsMatch(this.query, '用量 限额 费用 usage')) {
                  this.row('用量与限额', '当前环境的历史用量与账号限额', '', this.isFirstVisible(this.notifyToolsKeywords(), 1), () => this.section = 'usage')
                }
                if (settingsMatch(this.query, '定时任务 计划 scheduled')) {
                  this.row('定时任务', '查看与管理当前环境的计划', '', this.isFirstVisible(this.notifyToolsKeywords(), 2), () => this.section = 'schedules')
                }
                if (settingsMatch(this.query, '存储 缓存 清理 临时 文件')) {
                  this.row('客户端存储', '按环境清理旧临时分享文件', '', this.isFirstVisible(this.notifyToolsKeywords(), 3), () => this.section = 'storage')
                }
              }.width('100%').backgroundColor($r('app.color.card')).borderRadius(Radius.card).clip(true)
            }

            if (settingsMatch(this.query, '外观 主题 浅色 深色 系统')) {
              this.sectionLabel('外观')
              Column() {
                this.appearanceChoice('跟随系统', '随设备外观自动切换', 'system', true)
                this.appearanceChoice('浅色', '明亮背景', 'light', false)
                this.appearanceChoice('深色', '低亮度背景', 'dark', false)
              }.width('100%').backgroundColor($r('app.color.card')).borderRadius(Radius.card).clip(true)
                .enabled(!this.savingAppearance)
            }

            if (settingsMatch(this.query, CODE_APPEARANCE_SEARCH)) {
              Column() {
                Column({ space: Space.xs }) {
                  Text('代码与差异字号 · ' + this.visibleCodeFontSize() + (this.codeFontSize === null ? '（默认）' : ''))
                    .fontSize(FontSize.body).lineHeight(LineHeight.body).fontWeight(Weight.regular).fontColor($r('app.color.ink')).width('100%')
                  Row({ space: 4 }) {
                    Button('A−').backgroundColor($r('app.color.card')).fontColor($r('app.color.ink')).fontSize(FontSize.callout).fontWeight(Weight.medium)
                      .borderRadius(7).layoutWeight(1).constraintSize({ minHeight: 34 }).padding({ left: 4, right: 4 })
                      .enabled(!this.savingCodeAppearance && this.visibleCodeFontSize() > MIN_CODE_FONT_SIZE)
                      .accessibilityText('减小代码字号').onClick(() => { void this.changeCodeFontSize(this.visibleCodeFontSize() - 1); })
                    Button('A+').backgroundColor($r('app.color.card')).fontColor($r('app.color.ink')).fontSize(FontSize.callout).fontWeight(Weight.medium)
                      .borderRadius(7).layoutWeight(1).constraintSize({ minHeight: 34 }).padding({ left: 4, right: 4 })
                      .enabled(!this.savingCodeAppearance && this.visibleCodeFontSize() < MAX_CODE_FONT_SIZE)
                      .accessibilityText('放大代码字号').onClick(() => { void this.changeCodeFontSize(this.visibleCodeFontSize() + 1); })
                    Button('恢复默认').backgroundColor($r('app.color.card')).fontColor($r('app.color.ink')).fontSize(FontSize.callout).fontWeight(Weight.medium)
                      .borderRadius(7).layoutWeight(2).constraintSize({ minHeight: 34 }).padding({ left: 4, right: 4 })
                      .enabled(!this.savingCodeAppearance && this.codeFontSize !== null)
                      .onClick(() => { void this.changeCodeFontSize(null); })
                  }.width('100%').padding(2).backgroundColor($r('app.color.group')).borderRadius(9)
                  if (this.codeFontNotice) {
                    Text(this.codeFontNotice).fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.danger')).width('100%')
                  }
                }.width('100%').padding({ left: 14, right: 14, top: Space.sm, bottom: Space.sm }).alignItems(HorizontalAlign.Start)

                Row({ space: 10 }) {
                  Text('代码自动换行').fontSize(FontSize.body).lineHeight(LineHeight.body).fontColor($r('app.color.ink')).layoutWeight(1)
                  Button(this.codeWordBreak ? '已开启' : '已关闭')
                    .backgroundColor(this.codeWordBreak ? $r('app.color.primary') : $r('app.color.group'))
                    .fontColor(this.codeWordBreak ? $r('app.color.on_primary_fill') : $r('app.color.ink'))
                    .fontSize(FontSize.callout).fontWeight(Weight.medium).borderRadius(Radius.badge)
                    .constraintSize({ minHeight: 34 }).padding({ left: Space.sm, right: Space.sm })
                    .enabled(!this.savingCodeAppearance)
                    .accessibilityText(this.codeWordBreak ? '代码自动换行，已开启' : '代码自动换行，已关闭')
                    .onClick(() => { void this.changeCodeWordBreak(); })
                }
                .width('100%')
                .constraintSize({ minHeight: Sizes.formRowMin })
                .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
                .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
                .alignItems(VerticalAlign.Center)
              }
              .width('100%')
              .backgroundColor($r('app.color.card'))
              .borderRadius(Radius.card)
              .clip(true)
              .margin({ top: Space.sm })
            }

            if (settingsMatch(this.query, '帮助 诊断 复制 版本 关于 许可 开源')) {
              this.sectionLabel('帮助与信息')
              Column() {
                this.row('诊断', '查看并复制安全摘要', '', true, () => this.section = 'diagnostics')
                this.row('关于', '版本与开源许可', this.version, false, () => this.section = 'about')
              }.width('100%').backgroundColor($r('app.color.card')).borderRadius(Radius.card).clip(true)
            }

            if (this.query.trim() && !settingsMatch(this.query, '连接与项目 环境 连接 路径 T3 Connect 项目 归档 恢复 删除') &&
              !settingsMatch(this.query, '项目分组 仓库 路径 独立') && !settingsMatch(this.query, '外观 主题 浅色 深色 系统') &&
              !settingsMatch(this.query, CODE_APPEARANCE_SEARCH) &&
              !settingsMatch(this.query, '帮助 诊断 复制 版本 关于 许可 开源') &&
              !settingsMatch(this.query, '工作中 Working 会话 分组 排序') &&
              !settingsMatch(this.query, WORKTREE_STORAGE_SEARCH) &&
              !settingsMatch(this.query, SOURCE_CONTROL_SEARCH) &&
              !settingsMatch(this.query, '服务维护 更新 版本 数据库 存储 maintenance') &&
              !settingsMatch(this.query, '实验功能 Labs Beta 工作树') &&
              !settingsMatch(this.query, '自动归整 Settle 闲置 合并 会话') &&
              !settingsMatch(this.query, '新任务 默认 权限 工作区 流式 浏览器') &&
              !settingsMatch(this.query, '最近项目 上次 使用项目 新任务 默认 last project') &&
              !settingsMatch(this.query, WORKTREE_SEARCH) && !settingsMatch(this.query, '通知 提醒 完成 任务 在线') &&
              !settingsMatch(this.query, 'Provider 模型 账号 登录') && !settingsMatch(this.query, '会话 后续消息 排队 引导') &&
              !settingsMatch(this.query, '键盘 快捷键') && !settingsMatch(this.query, '用量 限额 费用 usage') &&
              !settingsMatch(this.query, '定时任务 计划 scheduled') && !settingsMatch(this.query, '存储 缓存 清理 临时 文件')) {
              GroupCard() {
                Text('没有匹配的设置')
                  .fontSize(FontSize.body)
                  .fontColor($r('app.color.muted'))
                  .textAlign(TextAlign.Center)
                  .width('100%')
                  .padding({ left: 14, right: 14, top: Space.md, bottom: Space.md })
              }
            }
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
          .padding({ left: Space.sm, right: Space.sm, top: Space.xxs, bottom: 20 + (this.embedded && !this.section ? this.bottomInset : 0) })
      }.width('100%').layoutWeight(1).align(Alignment.TopStart)
    }.width('100%').height('100%').foregroundColor($r('app.color.ink')).backgroundColor($r('app.color.group'))
    }
  }
}
