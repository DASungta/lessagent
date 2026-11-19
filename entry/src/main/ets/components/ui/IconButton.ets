import { Opacity, Sizes } from '../../common/Theme';

/**
 * 40×40 圆形热区的图标按钮。图标用线形 SVG（base/media 与 dark/media 同名两份，深浅色自动切换）。
 * label 必填：没有可见文字时，它就是读屏文本。
 *
 * IconButton({ icon: $r('app.media.ui_search'), label: '搜索', onTap: () => this.openSearch() })
 */
@Component
export struct IconButton {
  /** 图标资源，通常是 $r('app.media.ui_xxx')。非响应式，需要换图标时请用 if/else 切换组件。 */
  icon: ResourceStr = '';
  @Prop label: string = '';
  @Prop disabled: boolean = false;
  @Prop iconSize: number = Sizes.icon;
  onTap: () => void = () => {};

  build() {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      Image(this.icon)
        .width(this.iconSize)
        .height(this.iconSize)
        .objectFit(ImageFit.Contain)
        .draggable(false)
        .accessibilityLevel('no')
    }
    .width(Sizes.iconHit)
    .height(Sizes.iconHit)
    .backgroundColor(Color.Transparent)
    .enabled(!this.disabled)
    .opacity(this.disabled ? Opacity.disabled : 1)
    .accessibilityText(this.label)
    .onClick(() => this.onTap())
  }
}
