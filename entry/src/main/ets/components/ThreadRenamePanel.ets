import { TopBar } from './ui/TopBar';
import { GroupCard } from './ui/GroupCard';
import { AppButton } from './ui/AppButton';
import { FontSize, Sizes, Space } from '../common/Theme';
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
    Column({ space: 0 }) {
      TopBar({
        title: '重命名会话',
        showBack: true,
        closeStyle: true,
        backLabel: '关闭重命名',
        onBack: () => this.onClose()
      })
      Column({ space: 0 }) {
        GroupCard() {
          Column() {
            TextInput({ text: this.title, placeholder: '会话名称' })
              .height(42).fontSize(FontSize.body).fontColor($r('app.color.ink'))
              .placeholderColor($r('app.color.placeholder')).backgroundColor(Color.Transparent).padding(0)
              .width('100%').accessibilityText('会话名称')
              .onChange((value: string) => this.title = value)
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
          .constraintSize({ minHeight: Sizes.formRowMin })
          .justifyContent(FlexAlign.Center)
        }
        if (this.error) {
          Text(this.error).fontSize(FontSize.caption).fontColor($r('app.color.danger'))
            .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs }).width('100%')
        }
        Column() {
          AppButton({
            label: this.busy ? '保存中…' : '保存',
            kind: 'primary',
            fill: true,
            loading: this.busy,
            disabled: !this.title.trim(),
            onTap: () => { void this.submit(); }
          })
        }.width('100%').padding({ top: Space.md })
      }.width('100%').padding({ left: Space.sm, right: Space.sm, bottom: Space.md })
    }.width('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
  }
}
