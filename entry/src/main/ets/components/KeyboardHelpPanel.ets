import { KEYBOARD_HELP, KeyboardHelpItem } from '../protocol/Keyboard';

@Component
export struct KeyboardHelpPanel {
  onBack: () => void = () => {};

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Circle }) { Image($r('app.media.ui_back')).width(22).height(22) }
          .width(44).height(44).backgroundColor(Color.Transparent).accessibilityText('返回')
          .onClick(this.onBack)
        Text('外接键盘').fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
      }.width('100%')
      Scroll() {
        Column({ space: 16 }) {
          Text('USB 或蓝牙键盘快捷键').fontSize(14).fontColor($r('app.color.muted')).width('100%')
          ForEach(KEYBOARD_HELP, (item: KeyboardHelpItem) => {
            Column({ space: 8 }) {
              Text(item.action).fontSize(16).fontWeight(FontWeight.Medium).width('100%')
              Text(item.keys).fontSize(14).fontFamily('monospace').fontColor($r('app.color.primary')).width('100%')
              Text(item.detail).fontSize(13).fontColor($r('app.color.muted')).width('100%')
            }.width('100%').alignItems(HorizontalAlign.Start).padding(16)
              .backgroundColor($r('app.color.surface')).borderRadius(12)
          }, (item: KeyboardHelpItem) => item.action)
          Text('输入法候选尚未确认、正在提交或提交结果未知时，不触发快捷动作。终端、秘密输入及其他弹层由各自页面处理。')
            .fontSize(13).fontColor($r('app.color.muted')).width('100%')
          Text('Cmd 需要系统向应用传递左右 Meta 键事件；部分键盘布局或系统保留键可能无法使用，可改用 Ctrl。')
            .fontSize(13).fontColor($r('app.color.muted')).width('100%')
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ bottom: 20 })
      }.width('100%').layoutWeight(1)
    }.width('100%').height('100%').padding({ left: 16, right: 16 })
      .foregroundColor($r('app.color.ink')).backgroundColor($r('app.color.canvas'))
  }
}
