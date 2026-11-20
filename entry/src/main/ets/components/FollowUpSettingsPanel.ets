import { TopBar } from './ui/TopBar';
import { GroupCard } from './ui/GroupCard';
import { FormRow } from './ui/FormRow';
import { FontSize, LineHeight, Space } from '../common/Theme';
import { workspacePrefs, setFollowUpBehavior } from '../services/WorkspacePrefs';

@Component
export struct FollowUpSettingsPanel {
  onBack: () => void = () => {};
  @State selected: string = workspacePrefs.followUpBehavior;
  @State busy: boolean = false;
  @State error: string = '';
  private async save(value: string): Promise<void> {
    if (this.busy) return;
    this.busy = true; this.error = '';
    try { await setFollowUpBehavior(value); this.selected = workspacePrefs.followUpBehavior; }
    catch (_) { this.error = '设置未保存，请重试'; }
    finally { this.busy = false; }
  }
  @Builder
  option(value: string, title: string, detail: string, isFirst: boolean = false) {
    FormRow({
      kind: 'choice',
      label: title,
      subtitle: detail,
      checked: this.selected === value,
      disabled: this.busy,
      isFirst,
      onTap: () => { void this.save(value); }
    })
  }
  build() {
    Column({ space: 0 }) {
      TopBar({ title: '后续消息', showBack: true, backLabel: '返回设置', onBack: () => this.onBack() })
      Scroll() {
        Column({ space: 0 }) {
          GroupCard({
            title: '任务运行时，自动发送采用以下方式',
            footnote: '仅影响本机后续发送。输入栏选择的排队或引导可覆盖此默认值；已经提交的消息不会改变。'
          }) {
            this.option('queue', '排队', '等待当前任务结束后，再处理这条消息。', true)
            this.option('steer', '立即引导', '让 Agent 立即看到新消息，调整当前工作方向。', false)
          }
          if (this.error) {
            Text(this.error)
              .fontSize(FontSize.callout).lineHeight(LineHeight.callout).fontColor($r('app.color.danger'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.sm }).width('100%')
          }
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: Space.sm, right: Space.sm, bottom: Space.lg })
      }.width('100%').layoutWeight(1).align(Alignment.TopStart)
    }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
  }
}
