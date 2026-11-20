import { TopBar } from './ui/TopBar';
import { GroupCard } from './ui/GroupCard';
import { FormRow } from './ui/FormRow';
import { AppButton } from './ui/AppButton';
import { FontSize, LineHeight, Sizes, Space } from '../common/Theme';
import { EnvironmentEntry } from '../protocol/Environment';
import { LabsField, LabsSettingKey, LabsSettings, readLabsSettings, writeLabsSetting } from '../protocol/LabsSettings';
import { T3Client } from '../services/T3Client';

@Component
export struct LabsSettingsPanel {
  @Prop environments: EnvironmentEntry[] = [];
  connectionFor: (localId: string) => T3Client | undefined = () => undefined;
  onBack: () => void = () => {};
  @State selectedLocalId: string = '';
  @State snapshot: LabsSettings | undefined = undefined;
  @State busy: boolean = false;
  @State message: string = '';
  @State needsRefresh: boolean = false;
  private epoch: number = 0;

  aboutToAppear(): void {
    this.selectedLocalId = this.machines().find((entry: EnvironmentEntry) =>
      this.connectionFor(entry.localId)?.ready)?.localId || this.machines()[0]?.localId || '';
    this.busy = false;
    void this.refresh();
  }
  aboutToDisappear(): void { this.epoch++; }

  private machines(): EnvironmentEntry[] {
    return this.environments.filter((entry: EnvironmentEntry) => entry.enabled && !entry.deleting && !entry.pendingBase && !!entry.environmentId);
  }
  private options(): SelectOption[] {
    return this.machines().map((entry: EnvironmentEntry): SelectOption => ({ value: entry.label }));
  }
  private target(): EnvironmentEntry | undefined {
    return this.machines().find((entry: EnvironmentEntry) => entry.localId === this.selectedLocalId);
  }
  private current(entry: EnvironmentEntry, connection: T3Client, epoch: number): boolean {
    const target = this.target();
    return this.epoch === epoch && connection.ready && target?.localId === entry.localId &&
      target.environmentId === entry.environmentId && this.connectionFor(entry.localId) === connection;
  }
  private chooseMachine(index: number): void {
    const entry = this.machines()[index];
    if (!entry || this.busy || entry.localId === this.selectedLocalId) return;
    this.selectedLocalId = entry.localId;
    this.snapshot = undefined;
    void this.refresh();
  }
  private async refresh(): Promise<void> {
    if (this.busy) return;
    const entry = this.target();
    const connection = entry ? this.connectionFor(entry.localId) : undefined;
    if (!entry || !connection?.ready) {
      this.snapshot = undefined;
      this.message = this.machines().length > 0 ? '请连接选中的环境后刷新' : '请先连接一个环境';
      return;
    }
    const epoch = ++this.epoch;
    this.busy = true;
    this.message = '';
    try {
      const result = await readLabsSettings(connection, entry.environmentId);
      if (this.current(entry, connection, epoch)) {
        this.snapshot = result;
        this.needsRefresh = false;
      }
    } catch (_) {
      if (this.epoch === epoch) {
        this.needsRefresh = true;
        this.message = '读取失败，请检查连接后刷新';
      }
    } finally {
      if (this.epoch === epoch) this.busy = false;
    }
  }
  private field(key: LabsSettingKey): LabsField | undefined {
    return key === 'linkedEnvironmentsEnabled'
      ? this.snapshot?.linkedEnvironmentsEnabled : this.snapshot?.fastWorktreeCheckout;
  }
  private canEdit(key: LabsSettingKey): boolean {
    const entry = this.target();
    const connection = entry ? this.connectionFor(entry.localId) : undefined;
    const field = this.field(key);
    return !this.busy && !this.needsRefresh && !!entry && !!connection?.ready &&
      entry.environmentId === this.snapshot?.environmentId &&
      connection.canScope('settings:write') !== false && field?.value !== undefined && !field.locked;
  }
  private async toggleSetting(key: LabsSettingKey): Promise<void> {
    const entry = this.target();
    const connection = entry ? this.connectionFor(entry.localId) : undefined;
    if (!entry || !connection || !this.canEdit(key)) return;
    const value = this.field(key)?.value !== true;
    const epoch = ++this.epoch;
    this.busy = true;
    this.message = '';
    try {
      const result = await writeLabsSetting(connection, entry.environmentId, key, value);
      if (this.current(entry, connection, epoch)) {
        this.snapshot = result;
        this.message = '已保存并核对服务端结果';
      }
    } catch (_) {
      if (this.epoch === epoch) {
        this.needsRefresh = true;
        this.message = '修改未确认，请刷新核对';
      }
    } finally {
      if (this.epoch === epoch) this.busy = false;
    }
  }

  @Builder
  setting(title: string, detail: string, key: LabsSettingKey, isFirst: boolean = false) {
    if (this.field(key)?.value !== undefined) {
      FormRow({
        kind: 'switch',
        label: title,
        subtitle: this.field(key)?.locked === true ? (detail + ' · ' + (this.snapshot?.managedBy || '') + ' 管理') : detail,
        checked: this.field(key)?.value === true,
        disabled: !this.canEdit(key),
        isFirst,
        onToggle: () => { void this.toggleSetting(key); }
      })
    }
  }

  build() {
    Column({ space: 0 }) {
      TopBar({ title: '实验室', showBack: true, backLabel: '返回设置', onBack: () => this.onBack() }) {
        AppButton({ label: '刷新', kind: 'text', disabled: this.busy, onTap: () => { void this.refresh(); } })
      }
      Scroll() {
        Column({ space: 0 }) {
          if (this.machines().length > 0) {
            GroupCard({ title: '目标环境' }) {
              Column() {
                Row({ space: 10 }) {
                  Text('环境').fontSize(FontSize.body).fontColor($r('app.color.ink')).flexShrink(0)
                  Select(this.options()).layoutWeight(1).constraintSize({ minHeight: 38 })
                    .selected(this.machines().findIndex((entry: EnvironmentEntry) => entry.localId === this.selectedLocalId))
                    .value(this.target()?.label || '选择环境').enabled(!this.busy).accessibilityText('实验设置环境')
                    .backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
                    .onSelect((index: number) => this.chooseMachine(index))
                }.width('100%').alignItems(VerticalAlign.Center)
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
              .constraintSize({ minHeight: Sizes.formRowMin })
              .justifyContent(FlexAlign.Center)
            }
          }
          if (this.busy) {
            Text('正在同步…').fontSize(FontSize.callout).fontColor($r('app.color.muted'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs }).width('100%')
          }
          if (this.message) {
            Text(this.message).fontSize(FontSize.callout).fontColor($r('app.color.primary_text'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs }).width('100%')
          }
          if (this.snapshot) {
            if (this.connectionFor(this.selectedLocalId)?.canScope('settings:write') === false) {
              Text('当前连接仅可查看').fontSize(FontSize.callout).fontColor($r('app.color.muted'))
                .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs }).width('100%')
            }
            if (this.snapshot.linkedEnvironmentsEnabled.value === undefined && this.snapshot.fastWorktreeCheckout.value === undefined) {
              GroupCard() {
                FormRow({ kind: 'value', label: '当前环境未提供实验功能', value: '', valueMuted: true, chevron: false, isFirst: true })
              }
            } else {
              GroupCard({ title: '实验功能（Beta）' }) {
                this.setting('关联环境（Beta）', '允许代理通过已建立的关联在不同环境工作。关闭后，已运行的任务可继续完成。',
                  'linkedEnvironmentsEnabled', true)
                this.setting('快速检出工作树（Beta）', 'Mac 使用缓存加快工作树检出。关闭后服务端清除检出缓存。',
                  'fastWorktreeCheckout', this.field('linkedEnvironmentsEnabled')?.value === undefined)
              }
            }
          }
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: Space.sm, right: Space.sm, bottom: Space.lg })
      }.width('100%').layoutWeight(1).align(Alignment.TopStart)
    }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
  }
}
