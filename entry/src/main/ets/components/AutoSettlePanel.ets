import { T3Client } from '../services/T3Client';
import { record } from '../protocol/Wire';
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
    const id = this.connection ? record(this.connection.config.environment).environmentId : '';
    this.environmentId = typeof id === 'string' ? id : '';
    this.busy = false;
    void this.refresh();
  }
  aboutToDisappear(): void { this.epoch++; }

  private current(connection: T3Client, epoch: number): boolean {
    return this.epoch === epoch && this.connection === connection && connection.ready &&
      record(connection.config.environment).environmentId === this.environmentId;
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
  setting(title: string, key: AutoSettleKey, enabled: boolean, next: AutoSettleValue) {
    Row({ space: 8 }) {
      Column({ space: 4 }) {
        Text(title).fontSize(15)
        if (this.value(key) === undefined) {
          Text('当前服务不支持此设置').fontSize(13).fontColor($r('app.color.muted'))
        } else if (this.snapshot && autoSettleField(this.snapshot, key).locked) {
          Text(this.snapshot.managedBy + ' 管理此设置').fontSize(13).fontColor($r('app.color.muted'))
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (this.value(key) !== undefined) {
        Button(enabled ? '已开启' : '已关闭').fontSize(14).borderRadius(8).constraintSize({ minHeight: 44 })
          .backgroundColor(enabled ? $r('app.color.primary') : $r('app.color.canvas'))
          .fontColor(enabled ? $r('app.color.on_primary') : $r('app.color.muted'))
          .enabled(this.canEdit(key)).accessibilityText(title + (enabled ? '，已开启' : '，已关闭'))
          .onClick(() => { void this.save(key, next); })
      }
    }.width('100%').padding(12).borderRadius(12).backgroundColor($r('app.color.surface'))
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Normal }) { Image($r('app.media.ui_back')).width(22).height(22) }
          .width(44).height(44).backgroundColor(Color.Transparent).accessibilityText('返回设置').onClick(this.onBack)
        Text('自动归整会话').fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button('刷新').fontSize(14).backgroundColor(Color.Transparent).fontColor($r('app.color.primary'))
          .enabled(!this.busy && !!this.connection).onClick(() => { void this.refresh(); })
      }.width('100%').padding(8)
      Scroll() {
        Column({ space: 10 }) {
          Text('由当前环境的服务自动执行。项目单独设置优先。')
            .fontSize(13).fontColor($r('app.color.muted')).width('100%')
          if (!this.connection) { Text('请先连接一个环境').fontSize(15) }
          if (this.busy) { Text('正在同步…').fontSize(13).fontColor($r('app.color.muted')) }
          if (this.message) { Text(this.message).fontSize(14).width('100%') }
          if (this.snapshot) {
            if (this.connection?.canScope('settings:write') === false) {
              Text('当前连接仅可查看').fontSize(13).fontColor($r('app.color.muted'))
            }
            this.setting('合并 PR 后自动归整', 'sidebarAutoSettleOnMerge',
              this.value('sidebarAutoSettleOnMerge') === true, this.value('sidebarAutoSettleOnMerge') !== true)
            this.setting('闲置后自动归整', 'sidebarAutoSettleAfterDays',
              typeof this.value('sidebarAutoSettleAfterDays') === 'number',
              this.value('sidebarAutoSettleAfterDays') === null ? DEFAULT_AUTO_SETTLE_DAYS : null)
            if (typeof this.value('sidebarAutoSettleAfterDays') === 'number') {
              Row({ space: 8 }) {
                Text('闲置天数').fontSize(15)
                TextInput({ text: this.days, placeholder: '1–90 天，可输入小数' }).layoutWeight(1)
                  .accessibilityText('闲置天数').enabled(this.canEdit('sidebarAutoSettleAfterDays'))
                  .onChange((value: string) => { this.days = value; })
                Button('保存').fontSize(14)
                  .enabled(this.canEdit('sidebarAutoSettleAfterDays') && validAutoSettleDays(Number(this.days)) &&
                    Number(this.days) !== this.value('sidebarAutoSettleAfterDays'))
                  .onClick(() => { void this.save('sidebarAutoSettleAfterDays', Number(this.days)); })
              }.width('100%').padding(12)
              this.setting('闲置规则保留含 PR 的会话', 'sidebarAutoSettleKeepPullRequests',
                this.value('sidebarAutoSettleKeepPullRequests') === true,
                this.value('sidebarAutoSettleKeepPullRequests') !== true)
            }
          }
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 16, right: 16, bottom: 28 })
      }.width('100%').layoutWeight(1).align(Alignment.TopStart)
    }.width('100%').height('100%').backgroundColor($r('app.color.canvas')).foregroundColor($r('app.color.ink'))
  }
}
