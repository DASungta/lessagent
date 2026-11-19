import { FontSize, LineHeight, Opacity, Radius, Sizes, Space, Weight } from '../../common/Theme';

/**
 * primary   ink 实心（原版 prominent-action），一屏最多一个
 * secondary group 底 + ink 字
 * text      无底色，primary_text 字
 * danger    danger_bg 底 + danger 字
 * confirm   蓝色实心，只用于审批「允许」这类明确确认
 */
export type AppButtonKind = 'primary' | 'secondary' | 'text' | 'danger' | 'confirm';

/**
 * AppButton({ label: '保存', kind: 'primary', fill: true, loading: this.saving, onTap: () => this.save() })
 */
@Component
export struct AppButton {
  @Prop label: string = '';
  @Prop kind: AppButtonKind = 'primary';
  @Prop disabled: boolean = false;
  @Prop loading: boolean = false;
  /** 铺满父容器宽度 */
  @Prop fill: boolean = false;
  /** 紧凑高度 38，用于卡片和对话框里的按钮组 */
  @Prop compact: boolean = false;
  /** 读屏文本，默认等于 label */
  @Prop a11yLabel: string = '';
  onTap: () => void = () => {};

  private fillColorOf(): ResourceColor {
    if (this.kind === 'primary') return $r('app.color.prominent');
    if (this.kind === 'secondary') return $r('app.color.group');
    if (this.kind === 'danger') return $r('app.color.danger_bg');
    if (this.kind === 'confirm') return $r('app.color.primary');
    return Color.Transparent;
  }

  private textColorOf(): ResourceColor {
    if (this.kind === 'primary') return $r('app.color.on_prominent');
    if (this.kind === 'secondary') return $r('app.color.ink');
    if (this.kind === 'danger') return $r('app.color.danger');
    if (this.kind === 'confirm') return $r('app.color.on_primary_fill');
    return $r('app.color.primary_text');
  }

  private minHeightOf(): number {
    if (this.kind === 'text') return Sizes.iconHit;
    return this.compact ? Sizes.buttonHeightCompact : Sizes.buttonHeight;
  }

  build() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: Space.xs }) {
        if (this.loading) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color(this.textColorOf())
        }
        Text(this.label)
          .fontSize(FontSize.body)
          .lineHeight(LineHeight.body)
          .fontWeight(this.kind === 'primary' || this.kind === 'confirm' ? Weight.semibold : Weight.medium)
          .fontColor(this.textColorOf())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
    }
    .width(this.fill ? '100%' : 'auto')
    .constraintSize({ minHeight: this.minHeightOf() })
    .padding({ left: this.kind === 'text' ? Space.sm : Space.md, right: this.kind === 'text' ? Space.sm : Space.md })
    .borderRadius(Radius.button)
    .backgroundColor(this.fillColorOf())
    .enabled(!this.disabled && !this.loading)
    .opacity(this.disabled ? Opacity.disabled : 1)
    .accessibilityText(this.a11yLabel.length > 0 ? this.a11yLabel : this.label)
    .onClick(() => {
      if (!this.disabled && !this.loading) this.onTap();
    })
  }
}
