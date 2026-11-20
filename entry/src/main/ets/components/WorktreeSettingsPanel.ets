import { TopBar } from './ui/TopBar';
import { GroupCard } from './ui/GroupCard';
import { FormRow } from './ui/FormRow';
import { AppButton } from './ui/AppButton';
import { FontSize, LineHeight, Sizes, Space } from '../common/Theme';
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
  option(title: string, description: string, value: string, isFirst: boolean = false) {
    FormRow({
      kind: 'choice',
      label: title,
      subtitle: description,
      checked: this.snapshot?.submodules === value,
      disabled: !(this.canWrite() && this.snapshot?.submodulesLocked !== true),
      isFirst,
      onTap: () => { void this.save('worktreeSubmodules', value); }
    })
  }

  @Builder
  namingMode(title: string, detail: string, value: string, isFirst: boolean = false) {
    FormRow({
      kind: 'choice',
      label: title,
      subtitle: detail,
      checked: this.snapshot?.branchNamingMode === value,
      disabled: !this.canWriteBranch('branchNamingMode'),
      isFirst,
      onTap: () => {
        if (this.snapshot?.branchNamingMode !== value) void this.save('branchNamingMode', value);
      }
    })
  }

  @Builder
  branchFieldNotice(key: string) {
    if (this.snapshot && worktreeSettingLocked(this.snapshot.lockedPaths, key)) {
      Text(this.snapshot.managedBy + ' 管理此设置')
        .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted'))
        .padding({ left: Space.xxs, right: Space.xxs, bottom: 4 }).width('100%')
    } else if (this.snapshot && worktreeValue(this.snapshot, key) === undefined) {
      Text('当前服务未提供此设置')
        .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted'))
        .padding({ left: Space.xxs, right: Space.xxs, bottom: 4 }).width('100%')
    }
  }

  build() {
    Column({ space: 0 }) {
      TopBar({ title: '工作树默认设置', showBack: true, backLabel: '返回设置', onBack: () => this.onBack() }) {
        AppButton({ label: '刷新', kind: 'text', disabled: this.busy, onTap: () => { void this.refresh(); } })
      }
      Scroll() {
        Column({ space: 0 }) {
          Text('对当前环境中新建的工作树生效；项目单独设置和创建时的选择可以覆盖默认值。')
            .fontSize(FontSize.callout).lineHeight(LineHeight.callout).fontColor($r('app.color.muted'))
            .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs, bottom: Space.xxs }).width('100%')

          GroupCard() {
            FormRow({ kind: 'value', label: '项目级覆盖', value: '', isFirst: true, onTap: () => this.onProjects() })
          }

          if (!this.connection) {
            GroupCard() {
              FormRow({ kind: 'value', label: '请先连接一个环境', value: '', valueMuted: true, chevron: false, isFirst: true })
            }
          }
          if (this.busy) {
            Text('正在同步…').fontSize(FontSize.callout).fontColor($r('app.color.muted'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs }).width('100%')
          }
          if (this.error) {
            Text(this.error).fontSize(FontSize.callout).fontColor($r('app.color.danger'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs }).width('100%')
          }
          if (this.notice) {
            Text(this.notice).fontSize(FontSize.callout).fontColor($r('app.color.primary_text'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs }).width('100%')
          }

          if (this.snapshot) {
            if (this.settingsWriteAllowed === false) {
              Text('当前连接仅可查看，无法修改设置')
                .fontSize(FontSize.callout).fontColor($r('app.color.muted'))
                .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs }).width('100%')
            }

            GroupCard({
              title: '分支起点',
              footnote: this.snapshot.remoteLocked ? (this.snapshot.managedBy + ' 管理工作树起点') : ''
            }) {
              FormRow({
                kind: 'switch',
                label: '从远程分支开始',
                subtitle: '优先使用基准分支跟踪的远程最新提交；没有对应远程时使用本地分支。',
                checked: this.snapshot.remote,
                disabled: !(this.canWrite() && !this.snapshot.remoteLocked),
                isFirst: true,
                onToggle: (value: boolean) => { void this.save('newWorktreesStartFromOrigin', String(value)); }
              })
            }

            GroupCard({
              title: '子模块',
              footnote: this.snapshot.submodulesLocked ? (this.snapshot.managedBy + ' 管理子模块设置') : ''
            }) {
              this.option('继承仓库设置', '使用 t3.json；未设置时递归初始化。', 'inherit', true)
              this.option('递归初始化', '包括嵌套子模块。', 'recursive')
              this.option('仅顶层', '不初始化子模块中的嵌套子模块。', 'top-level')
              this.option('跳过', '保持子模块为空，由安装脚本处理。', 'none')
            }

            GroupCard({ title: '工作树分支命名' }) {
              if (worktreeSettingLocked(this.snapshot.lockedPaths, 'branchNamingMode') ||
                worktreeValue(this.snapshot, 'branchNamingMode') === undefined) {
                FormRow({
                  kind: 'value',
                  label: worktreeSettingLocked(this.snapshot.lockedPaths, 'branchNamingMode')
                    ? (this.snapshot.managedBy + ' 管理此设置') : '当前服务未提供此设置',
                  value: '',
                  valueMuted: true,
                  chevron: false,
                  isFirst: true
                })
              }
              if (this.snapshot.branchNamingMode !== undefined) {
                this.namingMode('固定前缀', '为生成的分支名使用固定前缀。', 'static',
                  !worktreeSettingLocked(this.snapshot.lockedPaths, 'branchNamingMode'))
                this.namingMode('语义前缀', '让模型选择 feat/、fix/ 等前缀。', 'semantic')
                this.namingMode('自定义说明', '根据命名说明生成完整分支名。', 'custom')
              }
              if (this.snapshot.branchNamingMode === 'static' && this.snapshot.branchNamePrefix !== undefined) {
                Column() {
                  Row({ space: Space.xs }) {
                    TextInput({ text: this.branchDraft, placeholder: '分支前缀（留空不加前缀）' })
                      .layoutWeight(1).height(40).fontSize(FontSize.body).fontColor($r('app.color.ink'))
                      .placeholderColor($r('app.color.placeholder')).backgroundColor(Color.Transparent).padding(0)
                      .accessibilityText('分支前缀').enabled(this.canWriteBranch('branchNamePrefix'))
                      .onChange((value: string) => { this.branchDraft = value; })
                    AppButton({
                      label: '保存', kind: 'primary', compact: true,
                      disabled: !(this.canWriteBranch('branchNamePrefix') && this.branchDraft.trim() !== this.snapshot?.branchNamePrefix),
                      onTap: () => { void this.save('branchNamePrefix', this.branchDraft); }
                    })
                  }.width('100%').alignItems(VerticalAlign.Center)
                }
                .width('100%')
                .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
                .constraintSize({ minHeight: Sizes.formRowMin })
                .justifyContent(FlexAlign.Center)
                .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
              } else if (this.snapshot.branchNamingMode === 'custom' && this.snapshot.branchNameInstructions !== undefined) {
                Column() {
                  Column({ space: Space.xs }) {
                    TextArea({ text: this.branchDraft, placeholder: '分支命名说明' })
                      .width('100%').constraintSize({ minHeight: 84 }).fontSize(FontSize.body).fontColor($r('app.color.ink'))
                      .placeholderColor($r('app.color.placeholder')).backgroundColor(Color.Transparent).padding(0)
                      .accessibilityText('分支命名说明').enabled(this.canWriteBranch('branchNameInstructions'))
                      .onChange((value: string) => { this.branchDraft = value; })
                    AppButton({
                      label: '保存命名说明', kind: 'primary', fill: true, compact: true,
                      disabled: !(this.canWriteBranch('branchNameInstructions') && this.branchDraft.trim() !== this.snapshot?.branchNameInstructions),
                      onTap: () => { void this.save('branchNameInstructions', this.branchDraft); }
                    })
                  }.width('100%').alignItems(HorizontalAlign.Start)
                }
                .width('100%')
                .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
                .constraintSize({ minHeight: Sizes.formRowMin })
                .justifyContent(FlexAlign.Center)
                .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
              }
            }
          }
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: Space.sm, right: Space.sm, bottom: Space.lg })
      }.width('100%').layoutWeight(1).align(Alignment.TopStart)
    }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
  }
}
