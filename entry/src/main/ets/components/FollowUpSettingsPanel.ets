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
  option(value: string, title: string, detail: string) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        Radio({ value, group: 'follow-up' }).checked(this.selected === value)
          .width(20).height(20).hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
        Column({ space: 6 }) {
          Text(title).fontSize(16).fontWeight(FontWeight.Medium).width('100%')
          Text(detail).fontSize(14).fontColor($r('app.color.muted')).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.padding(16).width('100%')
    }.width('100%').backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).borderRadius(12)
      .enabled(!this.busy).accessibilityText(title + (this.selected === value ? '，已选中' : ''))
      .onClick(() => { void this.save(value); })
  }
  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Normal }) { Image($r('app.media.ui_back')).width(22).height(22) }
          .width(44).height(44).backgroundColor(Color.Transparent).accessibilityText('返回设置').onClick(this.onBack)
        Text('后续消息').fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
      }.width('100%')
      Scroll() {
        Column({ space: 12 }) {
          Text('任务运行时，自动发送采用以下方式。').fontSize(15).width('100%')
          this.option('queue', '排队', '等待当前任务结束后，再处理这条消息。')
          this.option('steer', '立即引导', '让 Agent 立即看到新消息，调整当前工作方向。')
          Text('仅影响本机后续发送。输入栏选择的排队或引导可覆盖此默认值；已经提交的消息不会改变。')
            .fontSize(13).lineHeight('20fp').fontColor($r('app.color.muted')).width('100%')
          if (this.error) { Text(this.error).fontSize(14).fontColor($r('app.color.danger')).width('100%') }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1).align(Alignment.TopStart)
    }.padding(16).width('100%').height('100%').backgroundColor($r('app.color.canvas')).foregroundColor($r('app.color.ink'))
  }
}
