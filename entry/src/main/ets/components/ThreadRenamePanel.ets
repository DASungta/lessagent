import { ScopedThread } from '../protocol/Projects';

@Component
export struct ThreadRenamePanel {
  thread: ScopedThread | undefined = undefined;
  @State title: string = '';
  @State error: string = '';
  @State busy: boolean = false;
  onClose: () => void = () => {};
  onRename: (thread: ScopedThread, title: string) => Promise<void> = async () => {};

  aboutToAppear(): void { this.title = this.thread?.label || ''; }
  private async submit(): Promise<void> {
    if (!this.thread || this.busy) return;
    const value = this.title.trim();
    if (!value) { this.error = '会话名称不能为空'; return; }
    this.busy = true; this.error = '';
    try { await this.onRename(this.thread, value); }
    catch (error) { this.error = (error as Error).message; }
    finally { this.busy = false; }
  }
  build() {
    Column({ space: 14 }) {
      Row() {
        Button('×').width(44).height(44).backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
          .accessibilityText('关闭重命名').onClick(this.onClose)
        Text('重命名会话').fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
      }.width('100%')
      TextInput({ text: this.title, placeholder: '会话名称' }).height(48).fontSize(15)
        .onChange((value: string) => this.title = value).accessibilityText('会话名称')
      if (this.error) { Text(this.error).fontSize(13).fontColor($r('app.color.danger')).width('100%') }
      Button(this.busy ? '保存中…' : '保存').height(44).width('100%')
        .backgroundColor($r('app.color.primary')).fontColor($r('app.color.on_primary'))
        .enabled(!this.busy && !!this.title.trim()).onClick(() => void this.submit())
    }.width('100%').padding(20).foregroundColor($r('app.color.ink'))
  }
}
