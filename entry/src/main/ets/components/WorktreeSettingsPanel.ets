import { T3Client } from '../services/T3Client';
import { record } from '../protocol/Wire';
import { WorktreeDefaults, readWorktreeDefaults, worktreeSettingLocked, worktreeValue, writeWorktreeDefault } from '../protocol/WorktreeSettings';

@Component
export struct WorktreeSettingsPanel {
  connection: T3Client | undefined = undefined;
  @Prop settingsWriteAllowed: boolean | undefined = undefined;
  onBack: () => void = () => {};
  onProjects: () => void = () => {};
  @State snapshot: WorktreeDefaults | undefined = undefined;
  @State busy: boolean = false;
  @State error: string = '';
  @State notice: string = '';
  @State needsRefresh: boolean = false;
  @State branchDraft: string = '';
  private environmentId: string = '';
  private alive: boolean = true;

  aboutToAppear(): void {
    this.alive = true;
    if (this.connection) {
      const id = record(this.connection.config.environment).environmentId;
      this.environmentId = typeof id === 'string' ? id : '';
    }
    void this.refresh();
  }
  aboutToDisappear(): void { this.alive = false; }

  private accept(result: WorktreeDefaults): void {
    this.snapshot = result;
    this.branchDraft = result.branchNamingMode === 'static' ? result.branchNamePrefix ?? '' :
      result.branchNamingMode === 'custom' ? result.branchNameInstructions ?? '' : '';
  }
  private canWriteBranch(key: string): boolean {
    return this.settingsWriteAllowed === true && this.canWrite() && this.connection?.canScope('settings:write') === true &&
      !!this.snapshot && worktreeValue(this.snapshot, key) !== undefined &&
      !worktreeSettingLocked(this.snapshot.lockedPaths, key);
  }

  private async refresh(): Promise<void> {
    if (!this.connection || this.busy) return;
    const connection = this.connection;
    this.busy = true;
    try {
      const result = await readWorktreeDefaults(connection, this.environmentId);
      if (this.alive && this.connection === connection) { this.accept(result); this.error = ''; this.needsRefresh = false; }
    } catch (_) { if (this.alive) { this.error = '读取失败，请检查连接后刷新'; this.needsRefresh = true; } }
    finally { if (this.alive) this.busy = false; }
  }
  private canWrite(): boolean {
    return this.settingsWriteAllowed !== false && !!this.connection && this.connection.ready && this.connection.canScope('settings:write') !== false &&
      !!this.snapshot && !this.busy && !this.needsRefresh;
  }
  private async save(key: string, value: string): Promise<void> {
    if (!this.connection || !this.canWrite()) return;
    const connection = this.connection;
    this.busy = true; this.notice = ''; this.error = '';
    const stillSelected = (): boolean => this.alive && this.connection === connection;
    try {
      const result = await writeWorktreeDefault(connection, this.environmentId, key, value, stillSelected);
      if (stillSelected()) { this.accept(result); this.notice = '已保存并核对服务端结果'; }
    } catch (_) {
      if (this.alive) {
        this.needsRefresh = true;
        this.error = '修改未确认，请刷新核对。不会自动重试。';
      }
    } finally { if (this.alive) this.busy = false; }
  }
  @Builder
  option(title: string, description: string, value: string) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        Radio({ value: value, group: 'worktree-submodules' }).checked(this.snapshot?.submodules === value)
          .width(20).height(20).hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
        Column({ space: 4 }) {
          Text(title).fontSize(15).width('100%')
          Text(description).fontSize(13).fontColor($r('app.color.muted')).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%').padding(14)
    }.width('100%').backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).borderRadius(12)
      .enabled(this.canWrite() && this.snapshot?.submodulesLocked !== true)
      .accessibilityText(title + (this.snapshot?.submodules === value ? '，已选择' : ''))
      .onClick(() => { void this.save('worktreeSubmodules', value); })
  }
  @Builder
  namingMode(title: string, detail: string, value: string) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        Radio({ value, group: 'worktree-branch-naming' }).checked(this.snapshot?.branchNamingMode === value)
          .width(20).height(20).hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
        Column({ space: 4 }) {
          Text(title).fontSize(15).width('100%')
          Text(detail).fontSize(13).fontColor($r('app.color.muted')).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%').padding(14)
    }.width('100%').backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).borderRadius(12)
      .enabled(this.canWriteBranch('branchNamingMode'))
      .accessibilityText(title + (this.snapshot?.branchNamingMode === value ? '，已选择' : ''))
      .onClick(() => {
        if (this.snapshot?.branchNamingMode !== value) void this.save('branchNamingMode', value);
      })
  }
  @Builder
  branchFieldNotice(key: string) {
    if (this.snapshot && worktreeSettingLocked(this.snapshot.lockedPaths, key)) {
      Text(this.snapshot.managedBy + ' 管理此设置').fontSize(13).fontColor($r('app.color.muted')).width('100%')
    } else if (this.snapshot && worktreeValue(this.snapshot, key) === undefined) {
      Text('当前服务未提供此设置').fontSize(13).fontColor($r('app.color.muted')).width('100%')
    }
  }
  build() {
    Column({ space: 0 }) {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Normal }) { Image($r('app.media.ui_back')).width(22).height(22) }
          .width(44).height(44).backgroundColor(Color.Transparent).accessibilityText('返回设置').onClick(this.onBack)
        Text('工作树默认设置').fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button('刷新').constraintSize({ minWidth: 44, minHeight: 44 })
          .fontSize(14).backgroundColor(Color.Transparent).fontColor($r('app.color.primary'))
          .enabled(!this.busy).onClick(() => { void this.refresh(); })
      }.width('100%').padding(8)
      Scroll() {
        Column({ space: 14 }) {
          Text('对当前环境中新建的工作树生效；项目单独设置和创建时的选择可以覆盖默认值。')
            .fontSize(13).fontColor($r('app.color.muted')).width('100%')
          Button('项目级覆盖', { type: ButtonType.Normal }).width('100%').constraintSize({ minHeight: 44 })
            .backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).borderRadius(12)
            .onClick(this.onProjects)
          if (!this.connection) { Text('请先连接一个环境').fontSize(15) }
          if (this.busy) { Text('正在同步…').fontSize(13).fontColor($r('app.color.muted')) }
          if (this.error) { Text(this.error).fontSize(14).fontColor($r('app.color.ink')).width('100%') }
          if (this.notice) { Text(this.notice).fontSize(13).fontColor($r('app.color.muted')).width('100%') }
          if (this.snapshot) {
            if (this.settingsWriteAllowed === false) {
              Text('当前连接仅可查看，无法修改设置').fontSize(13).fontColor($r('app.color.muted'))
            }
            Row({ space: 12 }) {
              Column({ space: 4 }) {
                Text('从远程分支开始').fontSize(15).width('100%')
                Text('优先使用基准分支跟踪的远程最新提交；没有对应远程时使用本地分支。')
                  .fontSize(13).fontColor($r('app.color.muted')).width('100%')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Toggle({ type: ToggleType.Switch, isOn: this.snapshot.remote })
                .enabled(this.canWrite() && !this.snapshot.remoteLocked)
                .accessibilityText('从远程分支开始')
                .onChange((value: boolean) => { void this.save('newWorktreesStartFromOrigin', String(value)); })
            }.width('100%').padding(14).backgroundColor($r('app.color.surface')).borderRadius(12)
            if (this.snapshot.remoteLocked) {
              Text(this.snapshot.managedBy + ' 管理工作树起点').fontSize(13).fontColor($r('app.color.muted'))
            }
            Text('子模块').fontSize(13).fontColor($r('app.color.muted')).width('100%')
            this.option('继承仓库设置', '使用 t3.json；未设置时递归初始化。', 'inherit')
            this.option('递归初始化', '包括嵌套子模块。', 'recursive')
            this.option('仅顶层', '不初始化子模块中的嵌套子模块。', 'top-level')
            this.option('跳过', '保持子模块为空，由安装脚本处理。', 'none')
            if (this.snapshot.submodulesLocked) {
              Text(this.snapshot.managedBy + ' 管理子模块设置').fontSize(13).fontColor($r('app.color.muted'))
            }
            Text('工作树分支命名').fontSize(13).fontColor($r('app.color.muted')).width('100%')
            this.branchFieldNotice('branchNamingMode')
            if (this.snapshot.branchNamingMode !== undefined) {
              this.namingMode('固定前缀', '为生成的分支名使用固定前缀。', 'static')
              this.namingMode('语义前缀', '让模型选择 feat/、fix/ 等前缀。', 'semantic')
              this.namingMode('自定义说明', '根据命名说明生成完整分支名。', 'custom')
            }
            if (this.snapshot.branchNamingMode === 'static') {
              this.branchFieldNotice('branchNamePrefix')
              if (this.snapshot.branchNamePrefix !== undefined) {
                TextInput({ text: this.branchDraft, placeholder: '留空不加前缀' }).constraintSize({ minHeight: 44 })
                  .accessibilityText('分支前缀').enabled(this.canWriteBranch('branchNamePrefix'))
                  .onChange((value: string) => { this.branchDraft = value; })
                Button('保存分支前缀').constraintSize({ minHeight: 44 })
                  .enabled(this.canWriteBranch('branchNamePrefix') && this.branchDraft.trim() !== this.snapshot?.branchNamePrefix)
                  .onClick(() => { void this.save('branchNamePrefix', this.branchDraft); })
              }
            } else if (this.snapshot.branchNamingMode === 'custom') {
              this.branchFieldNotice('branchNameInstructions')
              if (this.snapshot.branchNameInstructions !== undefined) {
                TextArea({ text: this.branchDraft, placeholder: '分支命名说明' }).constraintSize({ minHeight: 96 })
                  .accessibilityText('分支命名说明').enabled(this.canWriteBranch('branchNameInstructions'))
                  .onChange((value: string) => { this.branchDraft = value; })
                Button('保存命名说明').constraintSize({ minHeight: 44 })
                  .enabled(this.canWriteBranch('branchNameInstructions') && this.branchDraft.trim() !== this.snapshot?.branchNameInstructions)
                  .onClick(() => { void this.save('branchNameInstructions', this.branchDraft); })
              }
            }
          }
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 16, right: 16, bottom: 28 })
      }.width('100%').layoutWeight(1).align(Alignment.TopStart)
    }.width('100%').height('100%').backgroundColor($r('app.color.canvas')).foregroundColor($r('app.color.ink'))
  }
}
