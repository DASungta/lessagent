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

  @Builder
  row(title: string, detail: string, value: string, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 10 }) {
        Column({ space: 3 }) {
          Text(title).fontSize(15).fontWeight(FontWeight.Medium).width('100%')
          Text(detail).fontSize(11).fontColor($r('app.color.muted')).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Text(value).fontSize(12).fontColor($r('app.color.muted'))
        Image($r('app.media.ui_back')).width(16).height(16).rotate({ angle: 180 }).opacity(0.5)
      }.width('100%').padding(14)
    }.width('100%').backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).borderRadius(12).onClick(action)
  }
  @Builder
  appearanceChoice(title: string, detail: string, mode: string) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 10 }) {
        Column({ space: 3 }) {
          Text(title).fontSize(15).fontWeight(FontWeight.Medium).width('100%')
          Text(detail).fontSize(11).fontColor($r('app.color.muted')).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Text(this.appearance === mode ? '✓' : '').fontSize(16).fontColor($r('app.color.primary')).width(24)
      }.width('100%').padding(14)
    }.width('100%').backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).borderRadius(12)
      .enabled(!this.savingAppearance).accessibilityText(title + (this.appearance === mode ? '，已选择' : ''))
      .onClick(() => { void this.changeAppearance(mode); })
  }
  @Builder
  choice(title: string, detail: string, value: string) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 8 }) {
        Radio({ value: value, group: 'project-grouping' }).checked(this.groupingMode === value)
          .width(20).height(20).hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
        Column({ space: 2 }) {
          Text(title).fontSize(14).fontWeight(FontWeight.Medium).width('100%')
          Text(detail).fontSize(11).fontColor($r('app.color.muted')).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%').padding({ left: 14, right: 14, top: 12, bottom: 12 })
    }.width('100%').backgroundColor(Color.Transparent).fontColor($r('app.color.ink')).accessibilityText(title + (this.groupingMode === value ? '，已选中' : '')).onClick(() => this.onGrouping(value))
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
      Row({ space: 6 }) {
        Button({ type: ButtonType.Normal }) {
          Image($r('app.media.ui_back')).width(22).height(22)
        }.width(44).height(44).backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
          .accessibilityText(this.section ? '返回设置' : '返回会话').onClick(() => { if (this.section) { this.section = ''; this.notice = ''; } else this.onBack(); })
        Text(this.section === 'diagnostics' ? '诊断' : this.section === 'about' ? '关于' : this.section === 'license' ? '开源许可' : '设置').fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
      }.width('100%').padding({ left: 8, right: 12, top: 8, bottom: 6 })
      Scroll() {
        Column({ space: 14 }) {
          if (this.notice) {
            Text(this.notice).fontSize(13).fontColor($r('app.color.muted')).width('100%')
          }
          if (this.section === 'diagnostics') {
            Text(this.summary()).fontSize(15).lineHeight('24fp').copyOption(CopyOptions.LocalDevice)
              .width('100%').padding(18).backgroundColor($r('app.color.surface')).borderRadius(16)
            this.row('复制诊断摘要', '仅复制本页所列信息', '', () => { void this.copyDiagnostics(); })
            Button('分享诊断摘要').constraintSize({ minHeight: 44 }).width('100%')
              .backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink'))
              .enabled(!this.sharingDiagnostics).onClick(() => { void this.shareDiagnostics(); })
          } else if (this.section === 'about') {
            Text('T3 Code Harmony').fontSize(26).fontWeight(FontWeight.Bold).margin({ top: 20 })
            Text('鸿蒙原生客户端 · ' + this.version).fontSize(14).fontColor($r('app.color.muted'))
            Text('在手机上连接你的工作环境，继续项目与会话。').fontSize(15).lineHeight('24fp').margin({ bottom: 16 })
            this.row('T3 Code 开源许可', 'MIT · T3 Tools Inc.', '', () => { void this.openLicense(); })
            Text('此版本为独立鸿蒙客户端。客户端版本与所连接的服务端版本分别管理。')
              .fontSize(13).lineHeight('20fp').fontColor($r('app.color.muted'))
          } else if (this.section === 'license') {
            Text(this.license).fontSize(14).lineHeight('22fp').width('100%').copyOption(CopyOptions.LocalDevice)
          } else {
          TextInput({ placeholder: '搜索设置', text: this.query }).height(44).fontSize(15)
            .backgroundColor($r('app.color.surface')).borderRadius(12).onChange(value => this.query = value)
            .accessibilityText('搜索设置')
          if (settingsMatch(this.query, '连接与项目 环境 连接 路径 T3 Connect 项目 归档 恢复 删除')) {
            Text('连接与项目').fontSize(12).fontColor($r('app.color.muted')).width('100%')
            Button({ type: ButtonType.Normal }) {
              Row({ space: 10 }) {
                Column({ space: 3 }) {
                  Text('环境').fontSize(15).fontWeight(FontWeight.Medium).width('100%')
                  Text('连接、路径与 T3 Connect').fontSize(11).fontColor($r('app.color.muted')).width('100%')
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Text(String(this.environmentCount)).fontSize(12).fontColor($r('app.color.muted'))
                Image($r('app.media.ui_back')).width(16).height(16).rotate({ angle: 180 }).opacity(0.5)
              }.width('100%').padding(14)
            }.width('100%').backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).borderRadius(12)
              .onClick(() => this.onEnvironments())
            Button({ type: ButtonType.Normal }) {
              Row({ space: 10 }) {
                Column({ space: 3 }) {
                  Text('项目').fontSize(15).fontWeight(FontWeight.Medium).width('100%')
                  Text('管理工作区与项目').fontSize(11).fontColor($r('app.color.muted')).width('100%')
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Text(String(this.projectCount)).fontSize(12).fontColor($r('app.color.muted'))
                Image($r('app.media.ui_back')).width(16).height(16).rotate({ angle: 180 }).opacity(0.5)
              }.width('100%').padding(14)
            }.width('100%').backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).borderRadius(12)
              .onClick(() => this.onProjects())
            Button({ type: ButtonType.Normal }) {
              Row({ space: 10 }) {
                Column({ space: 3 }) {
                  Text('归档会话').fontSize(15).fontWeight(FontWeight.Medium).width('100%')
                  Text('恢复或删除已归档会话').fontSize(11).fontColor($r('app.color.muted')).width('100%')
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Text(String(this.archivedCount)).fontSize(12).fontColor($r('app.color.muted'))
                Image($r('app.media.ui_back')).width(16).height(16).rotate({ angle: 180 }).opacity(0.5)
              }.width('100%').padding(14)
            }.width('100%').backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).borderRadius(12)
              .onClick(() => this.onArchive())
          }
          if (settingsMatch(this.query, '项目分组 仓库 路径 独立')) {
          Text('项目分组').fontSize(12).fontColor($r('app.color.muted')).width('100%')
          Column({ space: 0 }) {
            this.choice('按仓库分组', '同一仓库的多个工作区合并显示。', 'repository')
            Divider().color($r('app.color.border')).margin({ left: 14, right: 14 })
            this.choice('按仓库路径分组', '同一仓库的不同路径保持分开。', 'repository_path')
            Divider().color($r('app.color.border')).margin({ left: 14, right: 14 })
            this.choice('保持独立', '每个工作区单独显示。', 'separate')
          }.width('100%').backgroundColor($r('app.color.surface')).borderRadius(12)
          Text('项目分组使用本机偏好；会话固定/活跃顺序由服务端保存。')
            .fontSize(11).lineHeight('16fp').fontColor($r('app.color.muted')).width('100%').padding({ left: 4 })
          }
          if (settingsMatch(this.query, '工作中 Working 会话 分组 排序')) {
            Button({ type: ButtonType.Normal }) {
              Row({ space: 10 }) {
                Column({ space: 3 }) {
                  Text('工作中分组').fontSize(15).fontWeight(FontWeight.Medium).width('100%')
                  Text('开启后将运行中的会话单独分组，活跃会话按返回时间排序。')
                    .fontSize(11).fontColor($r('app.color.muted')).width('100%')
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Text(this.workingShelfEnabled ? '已开启' : '已关闭')
                  .fontSize(12).fontColor($r('app.color.muted'))
              }.width('100%').padding(14)
            }.width('100%').backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).borderRadius(12)
              .enabled(!this.savingWorkingShelf)
              .accessibilityText(this.workingShelfEnabled ? '工作中分组，已开启' : '工作中分组，已关闭')
              .onClick(() => { void this.changeWorkingShelf(); })
          }
          if (settingsMatch(this.query, WORKTREE_STORAGE_SEARCH)) {
            this.row('工作树存储', '目录位置与自动清理规则', '', () => this.section = 'worktree-storage')
          }
          if (settingsMatch(this.query, SOURCE_CONTROL_SEARCH)) {
            this.row('源码管理', '克隆布局、项目目录、自动拉取与合并署名', '', () => this.section = 'source-control')
          }
          if (settingsMatch(this.query, '服务维护 更新 版本 数据库 存储 maintenance')) {
            this.row('服务维护', '版本、数据库与更新状态', '', () => this.section = 'maintenance')
          }
          if (settingsMatch(this.query, '实验功能 Labs Beta 工作树')) {
            this.row('实验功能', '按环境管理实验选项', '', () => this.section = 'labs')
          }
          if (settingsMatch(this.query, '自动归整 Settle 闲置 合并 会话')) {
            this.row('自动归整会话', '合并与闲置会话的自动整理规则', '', () => this.section = 'auto-settle')
          }
          if (settingsMatch(this.query, '新任务 默认 权限 工作区 流式 浏览器')) {
            this.row('新任务默认设置', '当前环境的权限、工作区与响应行为', '', () => this.section = 'thread-defaults')
          }
          if (settingsMatch(this.query, '最近项目 上次 使用项目 新任务 默认 last project')) {
            Button({ type: ButtonType.Normal }) {
              Row({ space: 10 }) {
                Column({ space: 3 }) {
                  Text('使用最近项目').fontSize(15).fontWeight(FontWeight.Medium).width('100%')
                  Text('开启后优先使用当前或筛选的项目，其次使用最近项目。')
                    .fontSize(11).fontColor($r('app.color.muted')).width('100%')
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Text(this.useLastProject ? '已开启' : '已关闭').fontSize(12).fontColor($r('app.color.muted'))
              }.width('100%').padding(14)
            }.width('100%').backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).borderRadius(12)
              .enabled(!this.savingLastProject)
              .accessibilityText(this.useLastProject ? '使用最近项目，已开启' : '使用最近项目，已关闭')
              .onClick(() => { void this.changeUseLastProject(); })
          }
          if (settingsMatch(this.query, WORKTREE_SEARCH)) {
            Text('环境设置').fontSize(12).fontColor($r('app.color.muted')).width('100%')
            this.row('工作树', '远程起点、子模块与分支命名', '', () => this.section = 'worktrees')
          }
          if (settingsMatch(this.query, 'Provider 模型 账号 登录')) {
            this.row('Provider 与模型', '模型目录、状态与登录', '', () => this.section = 'providers')
          }
          if (settingsMatch(this.query, '会话 后续消息 排队 引导')) {
            this.row('后续消息', '运行中消息的处理方式', '', () => this.section = 'followup')
          }
          if (settingsMatch(this.query, '键盘 快捷键')) {
            this.row('键盘快捷键', '查看可用的键盘操作', '', () => this.section = 'keyboard')
          }
          if (settingsMatch(this.query, '通知 提醒 完成 任务 在线')) {
            Text('通知').fontSize(12).fontColor($r('app.color.muted')).width('100%')
            this.row('任务通知', '在线任务完成提醒与会话定位', '', () => this.section = 'notifications')
          }
          if (settingsMatch(this.query, '用量 限额 费用 usage')) {
            this.row('用量与限额', '当前环境的历史用量与账号限额', '', () => this.section = 'usage')
          }
          if (settingsMatch(this.query, '定时任务 计划 scheduled')) {
            this.row('定时任务', '查看与管理当前环境的计划', '', () => this.section = 'schedules')
          }
          if (settingsMatch(this.query, '存储 缓存 清理 临时 文件')) {
            this.row('客户端存储', '按环境清理旧临时分享文件', '', () => this.section = 'storage')
          }
          if (settingsMatch(this.query, '外观 主题 浅色 深色 系统')) {
            Text('外观').fontSize(12).fontColor($r('app.color.muted')).width('100%')
            Column({ space: 6 }) {
              this.appearanceChoice('跟随系统', '随设备外观自动切换', 'system')
              this.appearanceChoice('浅色', '明亮背景', 'light')
              this.appearanceChoice('深色', '低亮度背景', 'dark')
            }.width('100%').enabled(!this.savingAppearance)
          }
          if (settingsMatch(this.query, CODE_APPEARANCE_SEARCH)) {
            Column({ space: 8 }) {
              Text('代码与差异字号 · ' + this.visibleCodeFontSize() + (this.codeFontSize === null ? '（默认）' : ''))
                .fontSize(15).fontWeight(FontWeight.Medium).width('100%')
              Row({ space: 6 }) {
                Button('A−').backgroundColor($r('app.color.canvas')).fontColor($r('app.color.ink')).layoutWeight(1).constraintSize({ minHeight: 44 }).padding({ left: 4, right: 4 })
                  .enabled(!this.savingCodeAppearance && this.visibleCodeFontSize() > MIN_CODE_FONT_SIZE)
                  .accessibilityText('减小代码字号').onClick(() => { void this.changeCodeFontSize(this.visibleCodeFontSize() - 1); })
                Button('A+').backgroundColor($r('app.color.canvas')).fontColor($r('app.color.ink')).layoutWeight(1).constraintSize({ minHeight: 44 }).padding({ left: 4, right: 4 })
                  .enabled(!this.savingCodeAppearance && this.visibleCodeFontSize() < MAX_CODE_FONT_SIZE)
                  .accessibilityText('放大代码字号').onClick(() => { void this.changeCodeFontSize(this.visibleCodeFontSize() + 1); })
                Button('恢复默认').backgroundColor($r('app.color.canvas')).fontColor($r('app.color.ink')).layoutWeight(2).constraintSize({ minHeight: 44 }).padding({ left: 4, right: 4 })
                  .enabled(!this.savingCodeAppearance && this.codeFontSize !== null)
                  .onClick(() => { void this.changeCodeFontSize(null); })
              }.width('100%')
              Row({ space: 8 }) {
                Text('代码自动换行').fontSize(14).layoutWeight(1)
                Button(this.codeWordBreak ? '已开启' : '已关闭')
                  .backgroundColor(this.codeWordBreak ? $r('app.color.primary') : $r('app.color.canvas'))
                  .fontColor(this.codeWordBreak ? $r('app.color.on_primary') : $r('app.color.ink')).constraintSize({ minHeight: 44 })
                  .enabled(!this.savingCodeAppearance)
                  .accessibilityText(this.codeWordBreak ? '代码自动换行，已开启' : '代码自动换行，已关闭')
                  .onClick(() => { void this.changeCodeWordBreak(); })
              }.width('100%')
              if (this.codeFontNotice) Text(this.codeFontNotice).fontSize(13).fontColor($r('app.color.danger')).width('100%')
            }.width('100%').padding(12).backgroundColor($r('app.color.surface')).borderRadius(12)
          }
          if (settingsMatch(this.query, '帮助 诊断 复制 版本 关于 许可 开源')) {
            Text('帮助与信息').fontSize(12).fontColor($r('app.color.muted')).width('100%')
            this.row('诊断', '查看并复制安全摘要', '', () => this.section = 'diagnostics')
            this.row('关于', '版本与开源许可', this.version, () => this.section = 'about')
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
            Text('没有匹配的设置').fontSize(15).fontColor($r('app.color.muted')).padding(24)
          }
          }

        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 16, right: 16, bottom: 20 })
      }.width('100%').layoutWeight(1).align(Alignment.TopStart)
    }.width('100%').height('100%').foregroundColor($r('app.color.ink')).backgroundColor($r('app.color.canvas'))
    }
  }
}
