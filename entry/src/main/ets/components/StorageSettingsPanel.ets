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
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Normal }) { Image($r('app.media.ui_back')).width(22).height(22) }
          .width(44).height(44).backgroundColor(Color.Transparent).accessibilityText('返回设置').onClick(this.onBack)
        Text('客户端存储').fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button('刷新').backgroundColor(Color.Transparent).fontColor($r('app.color.primary')).onClick(() => { this.notice = ''; this.refresh(); })
      }.width('100%')
      Scroll() {
        Column({ space: 16 }) {
          Select(this.options()).selected(this.selected).value(this.options()[this.selected]?.value || '所有环境').onSelect((index: number) => { this.selected = index; this.notice = ''; })
          Text('临时分享文件').fontSize(18).fontWeight(FontWeight.Medium).width('100%')
          Text(this.rows().length + ' 个文件 · ' + cacheSizeLabel(this.rows().reduce((sum: number, entry: ShareCacheEntry) => sum + entry.bytes, 0))).fontSize(16).width('100%')
          Text('可清理 ' + this.removable().length + ' 个文件').fontSize(14).fontColor($r('app.color.muted')).width('100%')
          Text('保留最近一小时的分享文件。清理不会删除凭据、草稿、未知提交记录、服务端文件或你另存的文件。')
            .fontSize(14).lineHeight('22fp').fontColor($r('app.color.muted')).width('100%')
          Button('清理旧临时文件').width('100%').constraintSize({ minHeight: 48 })
            .backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).enabled(!this.busy && !this.error && this.removable().length > 0)
            .onClick(() => AlertDialog.show({ title: '清理临时分享文件？', message: '将删除所选范围内一小时前生成的临时副本。请先完成正在进行的分享。',
              primaryButton: { value: '取消', action: () => {} }, secondaryButton: { value: '清理', action: () => this.clear() } }))
          if (this.notice) { Text(this.notice).fontSize(14).width('100%') }
          if (this.error) { Text(this.error).fontSize(14).fontColor($r('app.color.danger')).width('100%') }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1).align(Alignment.TopStart)
    }.padding(16).width('100%').height('100%').backgroundColor($r('app.color.canvas')).foregroundColor($r('app.color.ink'))
  }
}
