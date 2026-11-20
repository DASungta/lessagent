import { FontSize, LineHeight, Opacity, Sizes, Space, Weight } from '../../common/Theme';

/**
 * value     左标签（可选副标题）+ 右侧取值（空时显示占位）+ ›（chevron 可关）
 * switch    左标签（可选副标题）+ 开关；整行可点
 * choice    左标签（可选副标题）+ 右侧蓝色选中勾选 ✓；整行可点
 * custom    左标签（可选副标题）+ 自定义尾部（trailing），如分段选择器
 * multiline 标签在上，取值 / 占位多行显示在下
 * content   整行自定义内容（body），如 TextArea，最低高度 72
 */
export type FormRowKind = 'value' | 'switch' | 'choice' | 'custom' | 'multiline' | 'content';

/**
 * 分组卡片里的一行。最低高度 50，左右内边距 14。放在 GroupCard 里使用，第一行传 isFirst: true（不画顶部分隔线）。
 *
 * FormRow({ label: '项目', value: 'r5-round2', isFirst: true, onTap: () => this.pick() })
 * FormRow({ label: '启用', kind: 'switch', checked: this.enabled, onToggle: (on: boolean) => this.enabled = on })
 * FormRow({ label: '浅色', subtitle: '明亮背景', kind: 'choice', checked: true, onTap: () => this.pick() })
 * FormRow({ label: '方式', kind: 'custom', trailing: () => { this.ModeSegments() } })
 * FormRow({ kind: 'content', isFirst: true, body: () => { this.PromptInput() } })
 *
 * 两个 @BuilderParam（trailing、body）不能用尾随闭包，需按名字传；传父组件的 @Builder 时用箭头函数包一层，保证 this 指向父组件。
 */
@Component
export struct FormRow {
  @Prop kind: FormRowKind = 'value';
  @Prop label: string = '';
  @Prop subtitle: string = '';
  @Prop value: string = '';
  @Prop placeholder: string = '';
  /** 只读信息行（版本号等）的取值用 muted 色 */
  @Prop valueMuted: boolean = false;
  /** value 行是否显示 ›，默认显示 */
  @Prop chevron: boolean = true;
  @Prop checked: boolean = false;
  @Prop disabled: boolean = false;
  /** 危险操作行（如「删除项目」），标签用 danger 色 */
  @Prop destructive: boolean = false;
  @Prop isFirst: boolean = false;
  /** 标签固定宽度，0 表示按内容 */
  @Prop labelWidth: number = 0;
  onTap: () => void = () => {};
  onToggle: (on: boolean) => void = () => {};
  @BuilderParam trailing: () => void = this.noBuilder;
  @BuilderParam body: () => void = this.noBuilder;

  @Builder noBuilder() {}

  private hasValue(): boolean {
    return this.value.length > 0;
  }

  private shownValue(): string {
    return this.hasValue() ? this.value : this.placeholder;
  }

  private valueColor(): ResourceColor {
    if (!this.hasValue()) return $r('app.color.placeholder');
    return this.valueMuted ? $r('app.color.muted') : $r('app.color.ink');
  }

  private isFlexibleLabel(): boolean {
    return this.kind === 'switch' || this.kind === 'choice' || (this.subtitle.length > 0 && this.kind === 'custom');
  }

  private a11yText(): string {
    if (this.kind === 'switch') return this.label;
    if (this.kind === 'choice') return this.label + (this.checked ? '，已选择' : '');
    const shown = this.shownValue();
    return shown.length > 0 ? this.label + '，' + shown : this.label;
  }

  @Builder
  LabelBlock() {
    if (this.subtitle.length > 0) {
      Column({ space: 2 }) {
        Text(this.label)
          .fontSize(FontSize.body)
          .lineHeight(LineHeight.body)
          .fontWeight(Weight.regular)
          .fontColor(this.destructive ? $r('app.color.danger') : $r('app.color.ink'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.subtitle)
          .fontSize(FontSize.caption)
          .lineHeight(LineHeight.caption)
          .fontColor($r('app.color.muted'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(this.isFlexibleLabel() ? 1 : 0)
      .width(!this.isFlexibleLabel() && this.labelWidth > 0 ? this.labelWidth : 'auto')
      .flexShrink(this.isFlexibleLabel() ? 1 : 0)
      .constraintSize(this.isFlexibleLabel() ? {} : { maxWidth: '60%' })
    } else {
      Text(this.label)
        .fontSize(FontSize.body)
        .lineHeight(LineHeight.body)
        .fontWeight(Weight.regular)
        .fontColor(this.destructive ? $r('app.color.danger') : $r('app.color.ink'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(this.isFlexibleLabel() ? 1 : 0)
        .width(!this.isFlexibleLabel() && this.labelWidth > 0 ? this.labelWidth : 'auto')
        .flexShrink(this.isFlexibleLabel() ? 1 : 0)
        .constraintSize(this.isFlexibleLabel() ? {} : { maxWidth: '60%' })
    }
  }

  @Builder
  Chevron() {
    Image($r('app.media.ui_chevron_right'))
      .width(Sizes.chevron)
      .height(Sizes.chevron)
      .opacity(0.6)
      .flexShrink(0)
      .accessibilityLevel('no')
  }

  build() {
    Column() {
      if (this.kind === 'multiline') {
        Column({ space: Space.xxs }) {
          if (this.label.length > 0) {
            Text(this.label)
              .fontSize(FontSize.callout)
              .lineHeight(LineHeight.callout)
              .fontColor($r('app.color.muted'))
          }
          Text(this.shownValue())
            .fontSize(FontSize.body)
            .lineHeight(LineHeight.body)
            .fontColor(this.valueColor())
            .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 14, right: 14, top: Space.sm, bottom: Space.sm })
        .constraintSize({ minHeight: 72 })
      } else if (this.kind === 'content') {
        Column() {
          this.body()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 14, right: 14, top: Space.sm, bottom: Space.sm })
        .constraintSize({ minHeight: 72 })
      } else {
        Row({ space: 10 }) {
          this.LabelBlock()
          if (this.kind === 'value') {
            Text(this.shownValue())
              .fontSize(FontSize.body)
              .lineHeight(LineHeight.body)
              .fontColor(this.valueColor())
              .textAlign(TextAlign.End)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            if (this.chevron) {
              this.Chevron()
            }
          } else if (this.kind === 'choice') {
            Text(this.checked ? '✓' : '')
              .fontSize(FontSize.headline)
              .fontWeight(Weight.semibold)
              .fontColor($r('app.color.primary'))
              .width(20)
              .textAlign(TextAlign.End)
              .flexShrink(0)
              .accessibilityLevel('no')
          } else if (this.kind === 'switch') {
            Toggle({ type: ToggleType.Switch, isOn: this.checked })
              .selectedColor($r('app.color.primary'))
              .switchPointColor(Color.White)
              .enabled(!this.disabled)
              .accessibilityText(this.label)
              .onChange((on: boolean) => {
                if (on !== this.checked) this.onToggle(on);
              })
          } else {
            if (!this.isFlexibleLabel()) {
              Blank()
            }
            Row() {
              this.trailing()
            }
            .flexShrink(0)
          }
        }
        .width('100%')
        .constraintSize({ minHeight: Sizes.formRowMin })
        .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .border({
      width: { top: this.isFirst ? 0 : Sizes.hairline },
      color: { top: $r('app.color.separator') }
    })
    .enabled(!this.disabled)
    .opacity(this.disabled ? Opacity.disabled : 1)
    .accessibilityGroup(this.kind === 'value' || this.kind === 'multiline' || this.kind === 'choice')
    .accessibilityText(this.kind === 'value' || this.kind === 'multiline' || this.kind === 'choice' ? this.a11yText() : '')
    .onClick(() => {
      if (this.disabled) return;
      if (this.kind === 'switch') this.onToggle(!this.checked);
      else if (this.kind === 'value' || this.kind === 'multiline' || this.kind === 'choice') this.onTap();
    })
  }
}
