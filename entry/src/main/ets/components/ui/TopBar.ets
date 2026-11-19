import { FontSize, LineHeight, Sizes, Space, Weight } from '../../common/Theme';
import { IconButton } from './IconButton';

/**
 * 标题栏：可选返回按钮 + 标题 / 副标题 + 右侧动作区。最低高度 52，系统字号很大时随内容长高。
 * 右侧动作区只放 IconButton 或 AppButton({ kind: 'text' })。
 *
 * TopBar({ title: '会话', subtitle: 'r5-round2 · iMac', showBack: true, onBack: () => this.back() }) {
 *   IconButton({ icon: $r('app.media.ui_more'), label: '更多', onTap: () => this.openMore() })
 * }
 */
@Component
export struct TopBar {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop showBack: boolean = false;
  @Prop backLabel: string = '返回';
  onBack: () => void = () => {};
  @BuilderParam actions: () => void = this.noActions;

  @Builder noActions() {}

  build() {
    Row({ space: Space.xxs }) {
      if (this.showBack) {
        IconButton({ icon: $r('app.media.ui_back'), label: this.backLabel, onTap: () => this.onBack() })
      }
      Column() {
        Text(this.title)
          .fontSize(FontSize.headline)
          .lineHeight(LineHeight.headline)
          .fontWeight(Weight.semibold)
          .fontColor($r('app.color.ink'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.subtitle.length > 0) {
          Text(this.subtitle)
            .fontSize(FontSize.caption)
            .lineHeight(LineHeight.caption)
            .fontColor($r('app.color.muted'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
      .padding({ left: this.showBack ? Space.xxs : Space.xs })
      .accessibilityGroup(true)
      Row() {
        this.actions()
      }
      .flexShrink(0)
    }
    .width('100%')
    .constraintSize({ minHeight: Sizes.topBar })
    .padding({ left: Space.xs, right: Space.xs })
    .alignItems(VerticalAlign.Center)
  }
}
