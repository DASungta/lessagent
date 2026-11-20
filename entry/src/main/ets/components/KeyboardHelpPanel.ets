import { TopBar } from './ui/TopBar';
import { GroupCard } from './ui/GroupCard';
import { FontSize, LineHeight, Sizes, Space, Weight } from '../common/Theme';
import { KEYBOARD_HELP, KeyboardHelpItem } from '../protocol/Keyboard';

@Component
export struct KeyboardHelpPanel {
  onBack: () => void = () => {};

  build() {
    Column({ space: 0 }) {
      TopBar({ title: '外接键盘', showBack: true, backLabel: '返回设置', onBack: () => this.onBack() })
      Scroll() {
        Column({ space: 0 }) {
          GroupCard({
            title: 'USB 或蓝牙键盘快捷键',
            footnote: '输入法候选尚未确认、正在提交或提交结果未知时，不触发快捷动作。Cmd 依赖系统传递左右 Meta 键事件，部分布局可改用 Ctrl。'
          }) {
            ForEach(KEYBOARD_HELP, (item: KeyboardHelpItem, index: number) => {
              Column({ space: Space.xxs }) {
                Row({ space: Space.xs }) {
                  Text(item.action)
                    .fontSize(FontSize.body).lineHeight(LineHeight.body).fontWeight(Weight.medium)
                    .fontColor($r('app.color.ink')).layoutWeight(1)
                  Text(item.keys)
                    .fontSize(FontSize.mono).lineHeight(LineHeight.mono).fontFamily('monospace')
                    .fontColor($r('app.color.primary_text'))
                }.width('100%').alignItems(VerticalAlign.Center)
                Text(item.detail)
                  .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted')).width('100%')
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
              .constraintSize({ minHeight: Sizes.formRowMin })
              .justifyContent(FlexAlign.Center)
              .border({ width: { top: index === 0 ? 0 : Sizes.hairline }, color: { top: $r('app.color.separator') } })
            }, (item: KeyboardHelpItem) => item.action)
          }
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: Space.sm, right: Space.sm, bottom: Space.lg })
      }.width('100%').layoutWeight(1).align(Alignment.TopStart)
    }.width('100%').height('100%').foregroundColor($r('app.color.ink')).backgroundColor($r('app.color.group'))
  }
}
