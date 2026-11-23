import { TopBar } from './ui/TopBar';
import { GroupCard } from './ui/GroupCard';
import { FormRow } from './ui/FormRow';
import { AppButton } from './ui/AppButton';
import { FontSize, LineHeight, Sizes, Space } from '../common/Theme';
import { T3Client } from '../services/T3Client';
import { configEnvironmentId } from '../protocol/Wire';
import {
  AutoSettleKey, AutoSettleSettings, AutoSettleValue, DEFAULT_AUTO_SETTLE_DAYS,
  autoSettleField, readAutoSettleSettings, validAutoSettleDays, writeAutoSettleSetting
} from '../protocol/AutoSettle';

@Component
export struct AutoSettlePanel {
  connection: T3Client | undefined = undefined;
  onBack: () => void = () => {};
  @State snapshot: AutoSettleSettings | undefined = undefined;
  @State busy: boolean = false;
  @State needsRefresh: boolean = false;
  @State message: string = '';
  @State days: string = '';
  private environmentId: string = '';
  private epoch: number = 0;

  aboutToAppear(): void {
    this.environmentId = this.connection ? configEnvironmentId(this.connection.config) : '';
    this.busy = false;
    void this.refresh();
  }
  aboutToDisappear(): void { this.epoch++; }

  private current(connection: T3Client, epoch: number): boolean {
    return this.epoch === epoch && this.connection === connection && connection.ready && !!this.environmentId &&
      configEnvironmentId(connection.config) === this.environmentId;
  }
  private accept(snapshot: AutoSettleSettings): void {
    this.snapshot = snapshot;
    const value = this.value('sidebarAutoSettleAfterDays');
    this.days = typeof value === 'number' ? String(value) : '';
    this.needsRefresh = false;
  }
  private async refresh(): Promise<void> {
    const connection = this.connection;
    if (!connection || this.busy) return;
    const id = this.environmentId || configEnvironmentId(connection.config);
    if (!connection.ready || !id) { this.message = '请先连接一个环境'; return; }
    this.environmentId = id;
    const epoch = ++this.epoch;
    this.busy = true;
    try {
      const result = await readAutoSettleSettings(connection, this.environmentId);
      if (this.current(connection, epoch)) { this.accept(result); this.message = ''; }
    } catch (_) {
      if (this.epoch === epoch) { this.needsRefresh = true; this.message = '读取失败，请检查连接后刷新'; }
    } finally {
      if (this.epoch === epoch) this.busy = false;
    }
  }
  private value(key: AutoSettleKey): AutoSettleValue | undefined {
    return this.snapshot ? autoSettleField(this.snapshot, key).value : undefined;
  }
  private canEdit(key: AutoSettleKey): boolean {
    return !!this.snapshot && !!this.connection && this.current(this.connection, this.epoch) &&
      !this.busy && !this.needsRefresh && this.connection.canScope('settings:write') !== false &&
      this.value(key) !== undefined && !autoSettleField(this.snapshot, key).locked;
  }
  private async save(key: AutoSettleKey, value: AutoSettleValue): Promise<void> {
    const connection = this.connection;
    if (!connection || !this.canEdit(key) || this.value(key) === value) return;
    const epoch = ++this.epoch;
    this.busy = true;
    this.message = '';
    try {
      const result = await writeAutoSettleSetting(connection, this.environmentId, key, value);
      if (this.current(connection, epoch)) {
        this.accept(result);
        this.message = '已保存并核对服务端结果';
      }
    } catch (_) {
      if (this.epoch === epoch) {
        this.needsRefresh = true;
        this.message = '修改未确认，请刷新核对。不会自动重试。';
      }
    } finally {
      if (this.epoch === epoch) this.busy = false;
    }
  }

  @Builder
  setting(title: string, key: AutoSettleKey, enabled: boolean, next: AutoSettleValue, isFirst: boolean = false) {
    if (this.value(key) === undefined) {
      FormRow({
        kind: 'value',
        label: title,
        subtitle: '当前服务不支持此设置',
        value: '不支持',
        valueMuted: true,
        chevron: false,
        isFirst
      })
    } else {
      FormRow({
        kind: 'switch',
        label: title,
        subtitle: this.snapshot && autoSettleField(this.snapshot, key).locked ? (this.snapshot.managedBy + ' 管理此设置') : '',
        checked: enabled,
        disabled: !this.canEdit(key),
        isFirst,
        onToggle: () => { void this.save(key, next); }
      })
    }
  }

  build() {
    Column({ space: 0 }) {
      TopBar({
        title: '自动归整会话',
        showBack: true,
        backLabel: '返回设置',
        onBack: () => this.onBack()
      }) {
        AppButton({
          label: '刷新',
          kind: 'text',
          disabled: this.busy || !this.connection,
          onTap: () => { void this.refresh(); }
        })
      }
      Scroll() {
        Column({ space: 0 }) {
          Text('由当前环境的服务自动执行。项目单独设置优先。')
            .fontSize(FontSize.callout).lineHeight(LineHeight.callout).fontColor($r('app.color.muted'))
            .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs, bottom: Space.xxs }).width('100%')
          if (!this.connection) {
            GroupCard() {
              FormRow({ kind: 'value', label: '请先连接一个环境', value: '', valueMuted: true, chevron: false, isFirst: true })
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
            if (this.connection?.canScope('settings:write') === false) {
              Text('当前连接仅可查看').fontSize(FontSize.callout).fontColor($r('app.color.muted'))
                .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs }).width('100%')
            }
            GroupCard({ title: '自动规则' }) {
              this.setting('合并 PR 后自动归整', 'sidebarAutoSettleOnMerge',
                this.value('sidebarAutoSettleOnMerge') === true, this.value('sidebarAutoSettleOnMerge') !== true, true)
              this.setting('闲置后自动归整', 'sidebarAutoSettleAfterDays',
                typeof this.value('sidebarAutoSettleAfterDays') === 'number',
                this.value('sidebarAutoSettleAfterDays') === null ? DEFAULT_AUTO_SETTLE_DAYS : null, false)
              if (typeof this.value('sidebarAutoSettleAfterDays') === 'number') {
                Column() {
                  Row({ space: Space.xs }) {
                    Text('闲置天数').fontSize(FontSize.body).fontColor($r('app.color.ink')).flexShrink(0)
                    TextInput({ text: this.days, placeholder: '1–90 天，可输入小数' })
                      .layoutWeight(1).height(40).fontSize(FontSize.body).textAlign(TextAlign.End)
                      .fontColor($r('app.color.ink')).placeholderColor($r('app.color.placeholder'))
                      .backgroundColor(Color.Transparent).padding(0)
                      .accessibilityText('闲置天数').enabled(this.canEdit('sidebarAutoSettleAfterDays'))
                      .onChange((value: string) => { this.days = value; })
                    AppButton({
                      label: '保存',
                      kind: 'primary',
                      compact: true,
                      disabled: !(this.canEdit('sidebarAutoSettleAfterDays') && validAutoSettleDays(Number(this.days)) &&
                        Number(this.days) !== this.value('sidebarAutoSettleAfterDays')),
                      onTap: () => { void this.save('sidebarAutoSettleAfterDays', Number(this.days)); }
                    })
                  }.width('100%').alignItems(VerticalAlign.Center)
                }
                .width('100%')
                .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
                .constraintSize({ minHeight: Sizes.formRowMin })
                .justifyContent(FlexAlign.Center)
                .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
                this.setting('闲置规则保留含 PR 的会话', 'sidebarAutoSettleKeepPullRequests',
                  this.value('sidebarAutoSettleKeepPullRequests') === true,
                  this.value('sidebarAutoSettleKeepPullRequests') !== true, false)
              }
            }
          }
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: Space.sm, right: Space.sm, bottom: Space.lg })
      }.width('100%').layoutWeight(1).align(Alignment.TopStart).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
  }
}
