import { EnvironmentEntry } from '../protocol/Environment';
interface RoutingOption { value: string; label: string; description: string; }

@Component
export struct PullRequestRoutingSettings {
  @Prop entries: EnvironmentEntry[] = [];
  @Prop initialized: boolean = false;
  @State expanded: string = '';
  @State saving: boolean = false;
  @State error: string = '';
  onChange: (localId: string, permission: string) => Promise<void> = async () => {};
  private options: RoutingOption[] = [
    { value: 'off', label: '关闭', description: '源码控制请求保留在当前环境。' },
    { value: 'read', label: '读取 PR', description: '与其他已启用环境共享 PR 数据。' },
    { value: 'read-write', label: '读取和操作', description: '操作可能使用其他环境更广的源码控制权限。' }
  ];
  private async select(localId: string, permission: string): Promise<void> {
    if (this.saving) return;
    this.saving = true; this.error = '';
    try { await this.onChange(localId, permission); }
    catch (error) { this.error = (error as Error).message; }
    finally { this.saving = false; }
  }
  build() {
    if (this.entries.length) {
      Column({ space: 12 }) {
        Text('PR 路由').fontSize(14).fontWeight(FontWeight.Medium).width('100%')
        ForEach(this.entries.filter((entry: EnvironmentEntry) => !entry.deleting), (entry: EnvironmentEntry) => {
          Column({ space: 0 }) {
            Button({ type: ButtonType.Normal }) {
              Row({ space: 8 }) {
                Column({ space: 4 }) {
                  Text(entry.label).fontSize(16).fontWeight(FontWeight.Medium).maxLines(1).width('100%')
                  Text(entry.base).fontSize(12).fontColor($r('app.color.muted')).maxLines(1).width('100%')
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Text(this.options.find((option: RoutingOption) => option.value === (entry.prRouting || 'off'))?.label || '关闭')
                  .fontSize(13).fontColor($r('app.color.muted'))
                Text(this.expanded === entry.localId ? '⌃' : '⌄').fontSize(14)
              }.padding(16).width('100%')
            }.width('100%').backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
              .accessibilityText(entry.label + ' PR 路由').onClick(() => this.expanded = this.expanded === entry.localId ? '' : entry.localId)
            if (this.expanded === entry.localId) {
              ForEach(this.options, (option: RoutingOption) => {
                Button({ type: ButtonType.Normal }) {
                  Row({ space: 12 }) {
                    Column({ space: 4 }) {
                      Text(option.label).fontSize(15).width('100%')
                      Text(option.description).fontSize(13).fontColor($r('app.color.muted')).width('100%')
                    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                    if ((entry.prRouting || 'off') === option.value) { Text('✓').accessibilityText('已选择') }
                  }.padding(16).width('100%')
                }.width('100%').backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
                  .enabled(this.initialized && !this.saving && !entry.pendingBase)
                  .accessibilityText(option.label + ((entry.prRouting || 'off') === option.value ? '，已选择' : ''))
                  .onClick(() => this.select(entry.localId, option.value))
              }, (option: RoutingOption) => option.value)
            }
          }.width('100%').backgroundColor($r('app.color.surface')).borderRadius(12)
        }, (entry: EnvironmentEntry) => entry.localId)
        Text('选择信任的环境以共享 PR 数据和使用彼此的源码控制权限。双方都需启用，此设置仅影响本客户端。')
          .fontSize(13).fontColor($r('app.color.muted')).width('100%')
        if (this.error) { Text(this.error).fontSize(13).fontColor($r('app.color.danger')).width('100%') }
      }.width('100%').alignItems(HorizontalAlign.Start)
    }
  }
}
