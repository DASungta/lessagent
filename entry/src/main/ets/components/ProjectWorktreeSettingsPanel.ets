import { FontSize, LineHeight, Radius, Sizes, Space, Weight } from '../common/Theme';
import { AppButton } from './ui/AppButton';
import { GroupCard } from './ui/GroupCard';
import { TopBar } from './ui/TopBar';
import { EnvironmentEntry } from '../protocol/Environment';
import { ScopedProject } from '../protocol/Projects';
import { ProjectWorktreeSettings, ProjectWorktreeField, projectWorktreeField,
  readProjectWorktreeSettings, writeProjectWorktreeSettings, clearProjectWorktreeSettings } from '../protocol/ProjectWorktreeSettings';
import { T3Client } from '../services/T3Client';

@Component
export struct ProjectWorktreeSettingsPanel {
  @Prop environments: EnvironmentEntry[] = [];
  @Prop projects: ScopedProject[] = [];
  connectionFor: (localId: string) => T3Client | undefined = () => undefined;
  onBack: () => void = () => {};
  @StorageLink('t3Foreground') @Watch('foregroundChanged') foreground: boolean = true;
  @State localId: string = '';
  @State projectId: string = '';
  @State snapshot: ProjectWorktreeSettings | undefined = undefined;
  @State busy: boolean = false;
  @State notice: string = '';
  @State editingKey: string = '';
  @State draft: string = '';
  private epoch: number = 0;
  private snapshotConnection: T3Client | undefined = undefined;

  aboutToDisappear(): void { this.reset(); }

  private foregroundChanged(): void {
    if (this.foreground) void this.refresh();
    else this.reset();
  }
  private reset(): void {
    this.epoch++;
    this.snapshot = undefined; this.busy = false;
    this.snapshotConnection = undefined;
    this.editingKey = ''; this.draft = ''; this.notice = '';
  }
  private connectedEnvironments(): EnvironmentEntry[] {
    return this.environments.filter((entry: EnvironmentEntry) =>
      entry.enabled && !entry.deleting && this.connectionFor(entry.localId)?.ready === true);
  }
  private projectChoices(): ScopedProject[] {
    if (!this.connectedEnvironments().some((entry: EnvironmentEntry) => entry.localId === this.localId)) return [];
    return this.projects.filter((project: ScopedProject) =>
      project.localId === this.localId && !!project.environmentId && !project.archivedAt && !project.isScratch);
  }
  private selectedProject(): ScopedProject | undefined {
    return this.projectChoices().find((project: ScopedProject) => project.id === this.projectId);
  }
  private selectEnvironment(index: number): void {
    const environment = this.connectedEnvironments()[index];
    if (!environment || environment.localId === this.localId) return;
    this.reset();
    this.localId = environment.localId; this.projectId = '';
  }
  private selectProject(index: number): void {
    const project = this.projectChoices()[index];
    if (!project || project.id === this.projectId) return;
    this.reset();
    this.projectId = project.id;
    void this.refresh();
  }
  private isCurrent(epoch: number, connection: T3Client, generation: number, project: ScopedProject): boolean {
    const current = this.selectedProject();
    return this.foreground && epoch === this.epoch && current?.localId === project.localId &&
      current?.id === project.id && current?.environmentId === project.environmentId &&
      this.connectionFor(project.localId) === connection && connection.ready && connection.generationValue() === generation;
  }
  private async refresh(): Promise<void> {
    const project = this.selectedProject();
    const connection = project ? this.connectionFor(project.localId) : undefined;
    if (!this.foreground || this.busy || !project || !connection) return;
    this.reset();
    const epoch = this.epoch; const generation = connection.generationValue();
    this.busy = true;
    try {
      await connection.refreshSessionAccess();
      if (!this.isCurrent(epoch, connection, generation, project)) return;
      const snapshot = await readProjectWorktreeSettings(connection, project.environmentId, project.id);
      if (this.isCurrent(epoch, connection, generation, project)) {
        this.snapshotConnection = connection;
        this.snapshot = snapshot;
      }
    } catch (_) {
      if (this.isCurrent(epoch, connection, generation, project)) this.notice = '读取失败，请刷新核对';
    } finally {
      if (epoch === this.epoch) this.busy = false;
    }
  }
  private field(key: string): ProjectWorktreeField | undefined {
    return this.snapshot ? projectWorktreeField(this.snapshot, key) : undefined;
  }
  private canWrite(): boolean {
    const project = this.selectedProject();
    const connection = project ? this.connectionFor(project.localId) : undefined;
    return this.foreground && !this.busy && this.snapshot?.supported === true &&
      !!project && this.snapshot.environmentId === project.environmentId && this.snapshot.projectId === project.id &&
      !!connection && connection === this.snapshotConnection && this.snapshot.generation === connection.generationValue() &&
      connection.canScope('settings:write') === true;
  }
  private canEdit(key: string): boolean {
    const field = this.field(key);
    return this.canWrite() && field?.value !== undefined && !field.locked;
  }
  private canRestoreAll(): boolean {
    return this.canWrite() && !!this.snapshot?.fields.some((field: ProjectWorktreeField) => field.source === 'project') &&
      !this.snapshot?.fields.some((field: ProjectWorktreeField) => field.source === 'project' && field.locked);
  }
  private async save(key: string, value: string | null): Promise<void> {
    const project = this.selectedProject();
    const connection = project ? this.connectionFor(project.localId) : undefined;
    const snapshot = this.snapshot;
    if (!project || !connection || !snapshot || (key ? !this.canEdit(key) : !this.canRestoreAll())) return;
    const epoch = ++this.epoch; const generation = connection.generationValue();
    const stillSelected = (): boolean => this.isCurrent(epoch, connection, generation, project);
    this.busy = true; this.notice = '';
    try {
      const result = key ? await writeProjectWorktreeSettings(connection, snapshot, key, value, stillSelected) :
        await clearProjectWorktreeSettings(connection, snapshot, stillSelected);
      if (stillSelected()) {
        this.snapshot = result; this.editingKey = ''; this.draft = ''; this.notice = '已保存并核对';
      }
    } catch (_) {
      if (stillSelected()) {
        this.snapshot = undefined; this.editingKey = ''; this.draft = '';
        this.notice = '修改未确认，请刷新核对。';
      }
    } finally {
      if (epoch === this.epoch) this.busy = false;
    }
  }
  private confirmRestoreAll(): void {
    if (!this.canRestoreAll()) return;
    const snapshot = this.snapshot;
    AlertDialog.show({ title: '恢复此项目的环境默认值？', message: '移除此项目在此页的覆盖，之后新建工作树将使用环境默认值。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '恢复继承', action: () => {
        if (snapshot === this.snapshot) void this.save('', null);
      } } });
  }

  private displayValue(key: string, values: string[], labels: string[]): string {
    const value = this.field(key)?.value;
    if (value === undefined) return '当前服务未提供';
    if (value === 'inherit' && key === 'worktreeSubmodules') return '由仓库配置决定';
    return labels[values.indexOf(value)] || (value === '' ? '空值' : value);
  }

  @Builder
  setting(title: string, key: string, values: string[], labels: string[], isFirst: boolean = false) {
    Column({ space: 6 }) {
      Text(title).fontSize(FontSize.body).lineHeight(LineHeight.body).fontColor($r('app.color.ink')).width('100%')
      if (!this.canEdit(key) || (!values.length && this.editingKey !== key)) {
        Text(this.displayValue(key, values, labels)).fontSize(FontSize.callout).lineHeight(LineHeight.callout)
          .fontColor($r('app.color.muted')).width('100%').wordBreak(WordBreak.BREAK_ALL)
      }
      if (this.field(key)?.value !== undefined) {
        Text(this.field(key)?.source === 'project' ? '项目覆盖' : '继承环境默认值')
          .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted')).width('100%')
      }
      if (this.field(key)?.locked) {
        Text((this.snapshot?.managedBy || '组织策略') + '管理此设置')
          .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted')).width('100%')
      }
      if (this.canEdit(key)) {
        if (values.length) {
          Select(labels.map((label: string): SelectOption => ({ value: label })))
            .value(this.displayValue(key, values, labels)).accessibilityDescription(title)
            .width('100%').constraintSize({ minHeight: Sizes.buttonHeightCompact })
            .backgroundColor($r('app.color.group')).fontColor($r('app.color.ink'))
            .onSelect((index: number) => { if (values[index] !== undefined) void this.save(key, values[index]); })
        } else if (this.editingKey === key) {
          TextArea({ text: this.draft, placeholder: title }).width('100%')
            .enterKeyType(EnterKeyType.NEW_LINE)
            .constraintSize({ minHeight: 44, maxHeight: 120 })
            .barState(BarState.Auto)
            .fontSize(FontSize.body).fontColor($r('app.color.ink')).placeholderColor($r('app.color.placeholder'))
            .backgroundColor($r('app.color.group')).borderRadius(Radius.tool).padding(10)
            .accessibilityText(title).onChange((value: string) => { this.draft = value; })
          Row({ space: Space.xs }) {
            AppButton({
              label: '取消',
              kind: 'secondary',
              compact: true,
              onTap: () => { this.editingKey = ''; this.draft = ''; }
            })
            AppButton({
              label: '保存覆盖',
              kind: 'primary',
              compact: true,
              onTap: () => { void this.save(key, this.draft); }
            })
          }.width('100%')
        } else {
          Row({ space: Space.xs }) {
            AppButton({
              label: '编辑',
              kind: 'secondary',
              compact: true,
              a11yLabel: '编辑' + title,
              onTap: () => { this.draft = this.field(key)?.value || ''; this.editingKey = key; }
            })
            if (this.field(key)?.source === 'project') {
              AppButton({
                label: '恢复继承',
                kind: 'text',
                compact: true,
                a11yLabel: title + '恢复继承',
                onTap: () => { void this.save(key, null); }
              })
            }
          }.width('100%')
        }
        if (values.length && this.field(key)?.source === 'project') {
          AppButton({
            label: '恢复继承',
            kind: 'text',
            compact: true,
            a11yLabel: title + '恢复继承',
            onTap: () => { void this.save(key, null); }
          })
        }
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .border({ width: { top: isFirst ? 0 : Sizes.hairline }, color: { top: $r('app.color.separator') } })
  }

  build() {
    Column({ space: 0 }) {
      TopBar({
        title: '项目工作树设置',
        showBack: true,
        backLabel: '返回工作树默认设置',
        onBack: this.onBack
      }) {
        AppButton({
          label: '刷新',
          kind: 'text',
          compact: true,
          disabled: this.busy || !this.selectedProject(),
          onTap: () => { void this.refresh(); }
        })
      }
      Scroll() {
        Column({ space: Space.xs }) {
          GroupCard({
            title: '选择工作区',
            footnote: this.selectedProject() ? (this.selectedProject()?.workspaceRoot || '') :
              this.localId ? '请选择已连接环境中的项目工作区' : ''
          }) {
            if (!this.connectedEnvironments().length) {
              Row() {
                Text('请先连接一个工作环境').fontSize(FontSize.body).fontColor($r('app.color.muted'))
              }.width('100%').constraintSize({ minHeight: Sizes.formRowMin }).padding({ left: 14, right: 14 })
            } else {
              Row({ space: 10 }) {
                Text('环境').fontSize(FontSize.body).fontColor($r('app.color.ink')).flexShrink(0)
                Select(this.connectedEnvironments().map((entry: EnvironmentEntry): SelectOption => ({ value: entry.label })))
                  .value(this.connectedEnvironments().find((entry: EnvironmentEntry) => entry.localId === this.localId)?.label || '选择已连接环境')
                  .layoutWeight(1).constraintSize({ minHeight: Sizes.buttonHeightCompact }).accessibilityDescription('选择已连接环境')
                  .backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
                  .onSelect((index: number) => this.selectEnvironment(index))
              }.width('100%').constraintSize({ minHeight: Sizes.formRowMin }).padding({ left: 14, right: 14 })
              if (this.localId) {
                Row({ space: 10 }) {
                  Text('项目').fontSize(FontSize.body).fontColor($r('app.color.ink')).flexShrink(0)
                  Select(this.projectChoices().map((project: ScopedProject): SelectOption =>
                    ({ value: project.label + ' · ' + project.workspaceRoot })))
                    .value(this.selectedProject()?.label || '选择项目工作区')
                    .layoutWeight(1).constraintSize({ minHeight: Sizes.buttonHeightCompact }).accessibilityDescription('选择项目工作区')
                    .backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
                    .enabled(this.projectChoices().length > 0).onSelect((index: number) => this.selectProject(index))
                }.width('100%').constraintSize({ minHeight: Sizes.formRowMin }).padding({ left: 14, right: 14 })
                  .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
              }
            }
          }

          if (this.busy) {
            Text('正在同步…').fontSize(FontSize.callout).fontColor($r('app.color.muted'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs }).width('100%')
          }
          if (this.notice) {
            Text(this.notice).fontSize(FontSize.callout).fontColor($r('app.color.primary_text'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs }).width('100%')
          }
          if (this.snapshot && this.selectedProject()) {
            if (!this.snapshot.supported) {
              Text('当前服务暂不支持项目级覆盖，可查看环境默认值。').fontSize(FontSize.callout).fontColor($r('app.color.muted'))
                .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs }).width('100%')
            } else if (!this.busy && !this.canWrite()) {
              Text('当前连接仅可查看。').fontSize(FontSize.callout).fontColor($r('app.color.muted'))
                .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs }).width('100%')
            }
            GroupCard({ title: '项目覆盖项' }) {
              this.setting('从远程分支开始', 'newWorktreesStartFromOrigin', ['true', 'false'], ['开启', '关闭'], true)
              this.setting('子模块', 'worktreeSubmodules', ['recursive', 'top-level', 'none'], ['递归初始化', '仅顶层', '跳过'])
              this.setting('分支命名模式', 'branchNamingMode', ['static', 'semantic', 'custom'], ['固定前缀', '语义前缀', '自定义说明'])
              this.setting('固定分支前缀', 'branchNamePrefix', [], [])
              this.setting('分支命名说明', 'branchNameInstructions', [], [])
            }

            if (this.canRestoreAll()) {
              Button('全部恢复继承').width('100%').constraintSize({ minHeight: Sizes.buttonHeight }).margin({ top: Space.sm })
                .fontSize(FontSize.body).fontWeight(Weight.medium)
                .borderRadius(Radius.button).backgroundColor($r('app.color.card')).fontColor($r('app.color.ink'))
                .onClick(() => this.confirmRestoreAll())
            }
          }
        }.width('100%').padding({ left: Space.page, right: Space.page, bottom: Space.lg })
      }.width('100%').layoutWeight(1).align(Alignment.TopStart)
    }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
  }
}
