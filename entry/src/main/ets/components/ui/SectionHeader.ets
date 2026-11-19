import { FontSize, LineHeight, Sizes, Space, Weight } from '../../common/Theme';

/**
 * 首页分栏标题：caption 字号 + 右侧细线，可选折叠箭头（整行可点）。
 * SectionHeader({ title: '置顶' })
 * SectionHeader({ title: 't3code-harmony', collapsible: true, collapsed: this.folded, onToggle: () => this.folded = !this.folded })
 */
@Component
export struct SectionHeader {
  @Prop title: string = '';
  @Prop showRule: boolean = true;
  @Prop collapsible: boolean = false;
  @Prop collapsed: boolean = false;
  onToggle: () => void = () => {};

  private a11yText(): string {
    if (!this.collapsible) return this.title;
    return this.title + (this.collapsed ? '，已折叠' : '，已展开');
  }

  build() {
    Row({ space: Space.xs }) {
      Text(this.title)
        .fontSize(FontSize.caption)
        .lineHeight(LineHeight.caption)
        .fontWeight(Weight.semibold)
        .fontColor($r('app.color.muted'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .flexShrink(1)
      if (this.showRule) {
        Divider()
          .strokeWidth(Sizes.hairline)
          .color($r('app.color.separator'))
          .layoutWeight(1)
      } else {
        Blank()
      }
      if (this.collapsible) {
        Image($r('app.media.ui_chevron_down'))
          .width(Sizes.chevron)
          .height(Sizes.chevron)
          .opacity(0.7)
          .rotate({ angle: this.collapsed ? -90 : 0 })
          .accessibilityLevel('no')
      }
    }
    .width('100%')
    .constraintSize({ minHeight: this.collapsible ? Sizes.iconHit : 0 })
    .padding({ left: Space.xxs, right: Space.xxs, top: Space.sm, bottom: Space.xxs })
    .alignItems(VerticalAlign.Center)
    .accessibilityGroup(true)
    .accessibilityText(this.a11yText())
    .onClick(() => {
      if (this.collapsible) this.onToggle();
    })
  }
}
