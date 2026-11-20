import { TopBar } from './ui/TopBar';
import { GroupCard } from './ui/GroupCard';
import { FormRow } from './ui/FormRow';
import { AppButton } from './ui/AppButton';
import { FontSize, LineHeight, Sizes, Space } from '../common/Theme';
import { common } from '@kit.AbilityKit';
import { EnvironmentEntry } from '../protocol/Environment';
import { ShareCacheEntry, inspectShareCache, clearShareCache, cacheRemovable, cacheSizeLabel } from '../services/ShareCache';

@Component
export struct StorageSettingsPanel {
  @Prop environments: EnvironmentEntry[] = [];
  onBack: () => void = () => {};
  @State entries: ShareCacheEntry[] = [];
  @State scopes: string[] = [];
  @State selected: number = 0;
  @State error: string = '';
  @State notice: string = '';
  @State busy: boolean = false;
  aboutToAppear(): void { this.refresh(); }
  private directory(): string { return (this.getUIContext().getHostContext() as common.Context).cacheDir; }
  private refresh(): void {
    try {
      const scope = this.selected ? this.scopes[this.selected - 1] : undefined;
      this.entries = inspectShareCache(this.directory());
      this.scopes = Array.from(new Set(this.entries.map((entry: ShareCacheEntry) => entry.localId)));
      if (scope !== undefined && !this.scopes.includes(scope)) this.scopes.push(scope);
      this.selected = scope === undefined ? 0 : this.scopes.indexOf(scope) + 1;
      this.error = '';
    } catch (_) { this.error = '无法读取临时分享文件，未执行清理'; this.entries = []; }
  }
  private options(): SelectOption[] {
    const options: SelectOption[] = [{ value: '所有环境' }];
    for (const scope of this.scopes) options.push({ value: !scope ? '旧文件（环境未知）' : this.environments.find((entry: EnvironmentEntry) => entry.localId === scope)?.label || '已移除的环境' });
    return options;
  }
  private rows(): ShareCacheEntry[] { return this.selected === 0 ? this.entries : this.entries.filter((entry: ShareCacheEntry) => entry.localId === this.scopes[this.selected - 1]); }
  private removable(): ShareCacheEntry[] { return this.rows().filter((entry: ShareCacheEntry) => cacheRemovable(entry, Date.now())); }
  private clear(): void {
    if (this.busy || this.error) return;
    this.busy = true;
    try {
      const result = clearShareCache(this.directory(), this.selected ? this.scopes[this.selected - 1] : undefined, Date.now());
      this.notice = '已清理 ' + result.removed + ' 个文件' + (result.failed ? '，' + result.failed + ' 个未能清理' : '');
      this.refresh();
    } catch (_) { this.error = '清理未全部完成，请刷新核对，不会自动重试'; }
    finally { this.busy = false; }
  }
  build() {
    Column({ space: 0 }) {
      TopBar({ title: '客户端存储', showBack: true, backLabel: '返回设置', onBack: () => this.onBack() }) {
        AppButton({ label: '刷新', kind: 'text', onTap: () => { this.notice = ''; this.refresh(); } })
      }
      Scroll() {
        Column({ space: 0 }) {
          GroupCard({
            title: '临时分享文件',
            footnote: '保留最近一小时的分享文件。清理不会删除凭据、草稿、未知提交记录、服务端文件或你另存的文件。'
          }) {
            Column() {
              Row({ space: 10 }) {
                Text('筛选范围').fontSize(FontSize.body).fontColor($r('app.color.ink')).flexShrink(0)
                Select(this.options()).selected(this.selected).layoutWeight(1).constraintSize({ minHeight: 38 })
                  .backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
                  .value(this.options()[this.selected]?.value || '所有环境')
                  .onSelect((index: number) => { this.selected = index; this.notice = ''; })
              }.width('100%').alignItems(VerticalAlign.Center)
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
            .constraintSize({ minHeight: Sizes.formRowMin })
            .justifyContent(FlexAlign.Center)
            FormRow({
              kind: 'value',
              label: '当前占用',
              value: this.rows().length + ' 个文件 · ' + cacheSizeLabel(this.rows().reduce((sum: number, entry: ShareCacheEntry) => sum + entry.bytes, 0)),
              valueMuted: true,
              chevron: false
            })
            FormRow({
              kind: 'value',
              label: '可清理数量',
              value: this.removable().length + ' 个文件',
              valueMuted: true,
              chevron: false
            })
          }
          if (this.notice) {
            Text(this.notice)
              .fontSize(FontSize.callout).lineHeight(LineHeight.callout).fontColor($r('app.color.primary_text'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs }).width('100%')
          }
          if (this.error) {
            Text(this.error)
              .fontSize(FontSize.callout).lineHeight(LineHeight.callout).fontColor($r('app.color.danger'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs }).width('100%')
          }
          Column() {
            AppButton({
              label: '清理旧临时文件',
              kind: 'secondary',
              fill: true,
              disabled: this.busy || !!this.error || this.removable().length === 0,
              onTap: () => {
                AlertDialog.show({
                  title: '清理临时分享文件？',
                  message: '将删除所选范围内一小时前生成的临时副本。请先完成正在进行的分享。',
                  primaryButton: { value: '取消', action: () => {} },
                  secondaryButton: { value: '清理', action: () => { this.clear(); } }
                });
              }
            })
          }.width('100%').padding({ top: Space.md })
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: Space.sm, right: Space.sm, bottom: Space.lg })
      }.width('100%').layoutWeight(1).align(Alignment.TopStart)
    }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
  }
}
