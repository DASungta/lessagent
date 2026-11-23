import { FontSize, LineHeight, Radius, Sizes, Space } from '../common/Theme';
import { AppButton } from './ui/AppButton';
import { GroupCard } from './ui/GroupCard';
import { TopBar } from './ui/TopBar';
import { configEnvironmentId } from '../protocol/Wire';
import { SourceControlSettings, SourceControlField, readSourceControlSettings,
  sourceControlField, writeSourceControlSetting } from '../protocol/SourceControlSettings';
import { T3Client } from '../services/T3Client';

const DIRECTORY = 'addProjectBaseDirectory';

@Component
export struct SourceControlSettingsPanel {
  connection: T3Client | undefined = undefined;
  @Prop @Watch('foregroundChanged') connectionReady: boolean = false;
  @Prop settingsWriteAllowed: boolean | undefined = undefined;
  @Prop environmentLabel: string = '';
  onBack: () => void = () => {};
  @StorageLink('t3Foreground') @Watch('foregroundChanged') foreground: boolean = true;
  @State snapshot: SourceControlSettings | undefined = undefined;
  @State busy: boolean = false;
  @State notice: string = '';
  @State editing: boolean = false;
  @State directoryDraft: string = '';
  private owner: T3Client | undefined = undefined;
  private alive: boolean = false;
  private epoch: number = 0;

  aboutToAppear(): void { this.alive = true; void this.refresh(); }
  aboutToDisappear(): void { this.alive = false; this.reset(); }

  private foregroundChanged(): void {
    if (this.foreground && this.connectionReady) void this.refresh();
    else this.reset();
  }
  private reset(): void {
    this.epoch++;
    this.owner = undefined; this.snapshot = undefined; this.busy = false;
    this.editing = false; this.directoryDraft = ''; this.notice = '';
  }
  private environmentId(connection: T3Client): string {
    if (!connection.ready) return '';
    return configEnvironmentId(connection.config);
  }
  private isCurrent(connection: T3Client, id: string, generation: number, epoch: number): boolean {
    return this.alive && this.foreground && this.epoch === epoch && this.connection === connection &&
      connection.generationValue() === generation && this.environmentId(connection) === id;
  }
  private async refresh(): Promise<void> {
    if (!this.alive || !this.foreground || this.busy) return;
    this.reset();
    const connection = this.connection;
    const id = connection ? this.environmentId(connection) : '';
    if (!connection || !id) { this.notice = '请先连接当前环境'; return; }
    const epoch = this.epoch; const generation = connection.generationValue();
    this.busy = true;
    try {
      await connection.refreshSessionAccess();
      if (!this.isCurrent(connection, id, generation, epoch)) return;
      const snapshot = await readSourceControlSettings(connection, id);
      if (this.isCurrent(connection, id, generation, epoch)) {
        this.owner = connection; this.snapshot = snapshot;
      }
    } catch (_) {
      if (this.isCurrent(connection, id, generation, epoch)) this.notice = '读取失败，请刷新核对。';
    } finally {
      if (epoch === this.epoch) this.busy = false;
    }
  }
  private field(key: string): SourceControlField | undefined {
    return this.snapshot ? sourceControlField(this.snapshot, key) : undefined;
  }
  private hasCurrentSnapshot(): boolean {
    const connection = this.connection; const snapshot = this.snapshot;
    return !!connection && !!snapshot && this.owner === connection &&
      this.environmentId(connection) === snapshot.environmentId && connection.generationValue() === snapshot.generation;
  }
  private canEdit(key: string): boolean {
    const field = this.field(key);
    return this.alive && this.foreground && !this.busy && this.settingsWriteAllowed === true && this.hasCurrentSnapshot() &&
      this.connection?.canScope('settings:write') === true && field?.value !== undefined && !field.locked;
  }
  private async save(key: string, value: string | boolean): Promise<void> {
    const snapshot = this.snapshot; const connection = this.connection;
    if (!snapshot || !connection || !this.canEdit(key) || this.field(key)?.value === value) return;
    const epoch = ++this.epoch; const generation = connection.generationValue();
    const stillSelected = (): boolean => this.isCurrent(connection, snapshot.environmentId, generation, epoch);
    this.busy = true; this.notice = '';
    try {
      const result = await writeSourceControlSetting(connection, snapshot, key, value, stillSelected);
      if (stillSelected()) {
        this.snapshot = result; this.editing = false; this.directoryDraft = ''; this.notice = '已保存并核对。';
      }
    } catch (_) {
      if (stillSelected()) {
        this.owner = undefined; this.snapshot = undefined;
        this.notice = '修改未确认，请刷新核对。';
      }
    } finally {
      if (this.epoch === epoch) this.busy = false;
    }
  }

  @Builder
  fieldNotice(key: string) {
    if (this.field(key)?.value === undefined) {
      Text('当前服务未提供此设置').fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted')).width('100%')
    }
    if (this.field(key)?.locked) {
      Text((this.snapshot?.managedBy || '组织') + '管理此设置').fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted')).width('100%')
    }
  }

  @Builder
  switchSetting(key: string, title: string, description: string, isFirst: boolean = false) {
    Column({ space: Space.xxs }) {
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text(title).fontSize(FontSize.body).lineHeight(LineHeight.body).fontColor($r('app.color.ink')).width('100%')
          Text(description).fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted')).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (this.field(key)?.value !== undefined) {
          Toggle({ type: ToggleType.Switch, isOn: this.field(key)?.value === true })
            .selectedColor($r('app.color.primary')).switchPointColor(Color.White)
            .enabled(this.canEdit(key))
            .accessibilityText(title).onChange((value: boolean) => {
              if (this.canEdit(key) && value !== this.field(key)?.value) void this.save(key, value);
            })
        }
      }.width('100%').alignItems(VerticalAlign.Center)
      this.fieldNotice(key)
    }.width('100%').alignItems(HorizontalAlign.Start).constraintSize({ minHeight: Sizes.formRowMin })
      .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
      .border({ width: { top: isFirst ? 0 : Sizes.hairline }, color: { top: $r('app.color.separator') } })
  }

  build() {
    Column({ space: 0 }) {
      TopBar({
        title: '源码管理',
        subtitle: this.environmentLabel,
        showBack: true,
        backLabel: '返回设置',
        onBack: this.onBack
      }) {
        AppButton({
          label: '刷新',
          kind: 'text',
          compact: true,
          disabled: this.busy,
          onTap: () => { void this.refresh(); }
        })
      }
      Scroll() {
        Column({ space: Space.xs }) {
          if (this.busy) {
            Text('正在同步…').fontSize(FontSize.callout).fontColor($r('app.color.muted'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs }).width('100%')
          }
          if (this.notice) {
            Text(this.notice).fontSize(FontSize.callout).fontColor($r('app.color.primary_text'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs }).width('100%')
          }
          if (this.snapshot && !this.hasCurrentSnapshot()) {
            Text('环境连接已变化，请刷新。').fontSize(FontSize.callout).fontColor($r('app.color.muted'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs }).width('100%')
          }
          if (this.snapshot && this.hasCurrentSnapshot()) {
            if (this.settingsWriteAllowed !== true) {
              Text('当前连接仅可查看。').fontSize(FontSize.callout).fontColor($r('app.color.muted'))
                .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs }).width('100%')
            }
            GroupCard({ title: '克隆与拉取' }) {
              this.switchSetting('ghqCloneLayout', '按主机和组织分层克隆',
                '新克隆使用「主机／所有者／仓库」布局，例如 github.com/org/repo。关闭时使用仓库名称作为目录。', true)
              Column({ space: 6 }) {
                Text('默认添加项目目录').fontSize(FontSize.body).lineHeight(LineHeight.body).fontColor($r('app.color.ink')).width('100%')
                Text('添加项目时，文件浏览器从宿主机上的这个目录开始。').fontSize(FontSize.caption).lineHeight(LineHeight.caption)
                  .fontColor($r('app.color.muted')).width('100%')
                if (this.field(DIRECTORY)?.value !== undefined) {
                  Text(String(this.field(DIRECTORY)?.value || '~/（默认）')).fontSize(FontSize.callout).fontColor($r('app.color.ink'))
                    .width('100%').wordBreak(WordBreak.BREAK_ALL)
                  if (this.canEdit(DIRECTORY)) {
                    if (this.editing) {
                      TextInput({ text: this.directoryDraft, placeholder: '留空恢复默认' }).constraintSize({ minHeight: 40 })
                        .fontSize(FontSize.body).fontColor($r('app.color.ink')).placeholderColor($r('app.color.placeholder'))
                        .backgroundColor($r('app.color.group')).borderRadius(Radius.tool).padding({ left: 10, right: 10 })
                        .accessibilityText('默认添加项目目录').onChange((value: string) => { this.directoryDraft = value; })
                      Row({ space: Space.xs }) {
                        AppButton({
                          label: '取消',
                          kind: 'secondary',
                          compact: true,
                          onTap: () => { this.editing = false; }
                        })
                        AppButton({
                          label: '保存',
                          kind: 'primary',
                          compact: true,
                          onTap: () => { void this.save(DIRECTORY, this.directoryDraft.trim()); }
                        })
                      }.width('100%').padding({ top: Space.xxs })
                    } else {
                      Row({ space: Space.xs }) {
                        AppButton({
                          label: '编辑目录',
                          kind: 'secondary',
                          compact: true,
                          onTap: () => {
                            this.directoryDraft = String(this.field(DIRECTORY)?.value || ''); this.editing = true;
                          }
                        })
                        if (this.field(DIRECTORY)?.value) {
                          AppButton({
                            label: '恢复默认目录',
                            kind: 'text',
                            compact: true,
                            onTap: () => { void this.save(DIRECTORY, ''); }
                          })
                        }
                      }.width('100%').padding({ top: Space.xxs })
                    }
                  }
                }
                this.fieldNotice(DIRECTORY)
              }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 14, right: 14, top: 10, bottom: 10 })
                .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
              this.switchSetting('defaultAutoPull', '默认启用自动拉取',
                '服务会定期检查默认分支，在没有本地改动时尝试拉取。项目单独设置优先。')
              this.switchSetting('removeAgentCreditsOnMerge', '合并时移除 Agent 署名',
                '受支持的宿主会从合并或压缩提交的消息中移除识别到的 Agent 署名，保留人类共同作者。')
            }
          }
        }.width('100%').padding({ left: Space.page, right: Space.page, bottom: Space.lg })
      }.width('100%').layoutWeight(1).align(Alignment.TopStart).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
  }
}
