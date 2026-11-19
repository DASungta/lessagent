import { FontSize, LineHeight, Radius, Space, Weight } from '../../common/Theme';

export type BadgeTone = 'success' | 'warning' | 'danger' | 'neutral' | 'info';

/**
 * 状态角标：11fp、圆角 6、浅底同色系字。（ArkUI 内置组件已占用 Badge 这个名字，所以叫 StatusBadge。）
 * StatusBadge({ text: '等待审批', tone: 'warning' })
 */
@Component
export struct StatusBadge {
  @Prop text: string = '';
  @Prop tone: BadgeTone = 'neutral';

  private fillColorOf(): ResourceColor {
    if (this.tone === 'success') return $r('app.color.success_bg');
    if (this.tone === 'warning') return $r('app.color.warning_bg');
    if (this.tone === 'danger') return $r('app.color.danger_bg');
    if (this.tone === 'info') return $r('app.color.info_bg');
    return $r('app.color.group');
  }

  private textColorOf(): ResourceColor {
    if (this.tone === 'success') return $r('app.color.success');
    if (this.tone === 'warning') return $r('app.color.warning');
    if (this.tone === 'danger') return $r('app.color.danger');
    if (this.tone === 'info') return $r('app.color.info');
    return $r('app.color.muted_tertiary');
  }

  build() {
    Text(this.text)
      .fontSize(FontSize.badge)
      .lineHeight(LineHeight.badge)
      .fontWeight(Weight.medium)
      .fontColor(this.textColorOf())
      .backgroundColor(this.fillColorOf())
      .borderRadius(Radius.badge)
      .padding({ left: Space.xs, right: Space.xs, top: 2, bottom: 2 })
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }
}
