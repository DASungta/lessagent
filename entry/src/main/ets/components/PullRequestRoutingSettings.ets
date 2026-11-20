import { GroupCard } from './ui/GroupCard';
import { FormRow } from './ui/FormRow';
import { FontSize, LineHeight, Sizes, Space, Weight } from '../common/Theme';
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
      GroupCard({
        title: 'PR 路由',
        footnote: this.error ? this.error : '选择信任的环境以共享 PR 数据和使用彼此的源码控制权限。双方都需启用，此设置仅影响本客户端。'
      }) {
        ForEach(this.entries.filter((entry: EnvironmentEntry) => !entry.deleting), (entry: EnvironmentEntry, index: number) => {
          Column({ space: 0 }) {
            Row({ space: Space.sm }) {
              Column({ space: 2 }) {
                Text(entry.label).fontSize(FontSize.body).lineHeight(LineHeight.body).fontWeight(Weight.regular)
                  .fontColor($r('app.color.ink')).width('100%')
                Text(entry.base).fontSize(FontSize.caption).lineHeight(LineHeight.caption)
                  .fontColor($r('app.color.muted')).width('100%')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Row({ space: 6 }) {
                Text(this.options.find((option: RoutingOption) => option.value === (entry.prRouting || 'off'))?.label || '关闭')
                  .fontSize(FontSize.callout).fontColor($r('app.color.muted'))
                Image($r('app.media.ui_chevron_down')).width(Sizes.chevron).height(Sizes.chevron)
                  .opacity(0.6).rotate({ angle: this.expanded === entry.localId ? 180 : 0 }).accessibilityLevel('no')
              }
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
            .constraintSize({ minHeight: Sizes.formRowMin })
            .alignItems(VerticalAlign.Center)
            .border({ width: { top: index === 0 ? 0 : Sizes.hairline }, color: { top: $r('app.color.separator') } })
            .onClick(() => { this.expanded = this.expanded === entry.localId ? '' : entry.localId; })
            if (this.expanded === entry.localId) {
              Column() {
                ForEach(this.options, (option: RoutingOption) => {
                  FormRow({
                    kind: 'choice',
                    label: option.label,
                    subtitle: option.description,
                    checked: (entry.prRouting || 'off') === option.value,
                    disabled: !(this.initialized && !this.saving && !entry.pendingBase),
                    isFirst: false,
                    onTap: () => { void this.select(entry.localId, option.value); }
                  })
                }, (option: RoutingOption) => option.value)
              }.width('100%').backgroundColor($r('app.color.group')).padding({ left: Space.xs })
            }
          }.width('100%')
        }, (entry: EnvironmentEntry) => entry.localId)
      }
    }
  }
}
