import { FontSize, Weight } from '../common/Theme';
import { isTallEnoughToFold, USER_MESSAGE_FOLDED_HEIGHT } from '../protocol/ThreadItems';

@Component
export struct CollapsibleUserMessageBody {
  @Prop @Watch('resetMeasurement') messageKey: string = '';
  @Prop collapsible: boolean = true;
  @Consume('t3ExpandedUserMessages') expandedUserMessages: Record<string, boolean>;
  onToggle: () => void = () => {};
  @BuilderParam content: () => void = this.noContent;

  @State tallEnough: boolean = false;
  @State contentWidth: number = 0;

  @Builder noContent() {}

  private resetMeasurement(): void {
    this.tallEnough = false;
    this.contentWidth = 0;
  }

  private isExpanded(): boolean {
    return !!this.messageKey && !!this.expandedUserMessages && this.expandedUserMessages[this.messageKey] === true;
  }

  private canCollapse(): boolean {
    return this.collapsible && this.tallEnough;
  }

  private isCollapsed(): boolean {
    return this.canCollapse() && !this.isExpanded();
  }

  build() {
    Column({ space: 0 }) {
      Stack({ alignContent: Alignment.BottomStart }) {
        Column() {
          Column() {
            this.content()
          }
          .alignItems(HorizontalAlign.Start)
          .onAreaChange((_, area: Area) => {
            const width = Number(area.width);
            if (Number.isFinite(width) && width > 0 && Math.abs(width - this.contentWidth) > 0.5) {
              this.contentWidth = width;
            }
            // Folded, layout reports the clipped height, which would read as short and unfold it in a loop.
            if (!this.isCollapsed()) {
              const height = Number(area.height);
              const next = isTallEnoughToFold(height);
              if (next !== this.tallEnough) this.tallEnough = next;
            }
          })
        }
        .alignItems(HorizontalAlign.Start)
        .constraintSize(this.isCollapsed() ? { maxHeight: USER_MESSAGE_FOLDED_HEIGHT } : {})
        .clip(this.isCollapsed())

        if (this.isCollapsed() && this.contentWidth > 0) {
          Column()
            .width(this.contentWidth)
            .height(36)
            .linearGradient({
              direction: GradientDirection.Bottom,
              colors: [[$r('app.color.bubble_transparent'), 0.0], [$r('app.color.bubble'), 1.0]]
            })
            .hitTestBehavior(HitTestMode.None)
        }
      }
      .alignContent(Alignment.BottomStart)

      if (this.canCollapse()) {
        Row() {
          Text(this.isExpanded() ? '收起' : '展开全文')
            .fontSize(FontSize.caption)
            .fontWeight(Weight.medium)
            .fontColor($r('app.color.primary_text'))
        }
        .width(this.contentWidth > 0 ? this.contentWidth : undefined)
        .justifyContent(FlexAlign.End)
        .alignItems(VerticalAlign.Center)
        .constraintSize({ minHeight: 36 })
        .padding({ top: 6 })
        .accessibilityText(this.isExpanded() ? '收起长消息' : '展开全文')
        .onClick(() => { this.onToggle(); })
      }
    }
    .alignItems(HorizontalAlign.Start)
  }
}
