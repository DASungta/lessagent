import { FontSize, LineHeight, Radius, Space, Weight } from '../common/Theme';
import {
  AgentFeedbackAnswer,
  AgentFeedbackRequestView,
  feedbackCardPreview,
  feedbackKindLabel,
  feedbackRequestDisplay
} from '../protocol/AgentFeedback';
import { AppButton } from './ui/AppButton';
import { StatusBadge, BadgeTone } from './ui/StatusBadge';

@Component
export struct FeedbackRequestCard {
  @Prop item: AgentFeedbackRequestView;
  @Prop canOperate: boolean = true;
  @Prop busy: boolean = false;
  onAnswer: (turnItemId: string, answer: AgentFeedbackAnswer, includeConversation: boolean) => Promise<void> =
    async () => {};

  @State includeConversation: boolean = false;
  @State detailsExpanded: boolean = false;
  @State submitting: boolean = false;
  @State error: string = '';

  private badgeTone(): BadgeTone {
    const display = feedbackRequestDisplay(this.item);
    if (display.kind === 'pending') return 'info';
    if (display.kind === 'pending-elsewhere') return 'warning';
    return display.outcome === 'sent' ? 'success' : 'neutral';
  }

  private async submit(answer: AgentFeedbackAnswer): Promise<void> {
    if (this.submitting || this.busy) return;
    this.submitting = true;
    this.error = '';
    try {
      await this.onAnswer(this.item.id, answer, answer === 'send' && this.includeConversation);
    } catch (reason) {
      this.error = (reason as Error).message || '反馈操作失败，请稍后重试';
    } finally {
      this.submitting = false;
    }
  }

  private traceSummaryText(): string {
    const preview = feedbackCardPreview(this.item, this.includeConversation);
    if (!preview.trace) return '无轨迹信息';
    const parts: string[] = [
      preview.trace.turns + ' 轮对话',
      preview.trace.entries.length + ' 条记录'
    ];
    if (preview.trace.textTurns > 0) parts.push('含 ' + preview.trace.textTurns + ' 轮正文');
    if (preview.trace.truncated) parts.push('已截断');
    return parts.join(' · ');
  }

  build() {
    Column({ space: Space.xs }) {
      Row({ space: Space.xs }) {
        StatusBadge({ text: feedbackKindLabel(this.item.preview.kind), tone: 'neutral' })
        Text(this.item.preview.subject || 'Agent 反馈报告')
          .fontSize(FontSize.body)
          .lineHeight(LineHeight.body)
          .fontWeight(Weight.semibold)
          .fontColor($r('app.color.ink'))
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        StatusBadge({ text: feedbackRequestDisplay(this.item).label, tone: this.badgeTone() })
      }.width('100%').alignItems(VerticalAlign.Center)

      if (this.item.preview.actual) {
        Text(this.item.preview.actual)
          .fontSize(FontSize.callout)
          .lineHeight(LineHeight.callout)
          .fontColor($r('app.color.ink'))
          .width('100%')
          .maxLines(this.detailsExpanded ? 20 : 3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      Button({ type: ButtonType.Normal }) {
        Text(this.detailsExpanded ? '收起上报详情' : '查看上报内容（' + this.traceSummaryText() + '）')
          .fontSize(FontSize.caption)
          .fontColor($r('app.color.primary_text'))
          .width('100%')
      }
      .width('100%')
      .padding({ top: 4, bottom: 4 })
      .backgroundColor(Color.Transparent)
      .onClick(() => { this.detailsExpanded = !this.detailsExpanded; })

      if (this.detailsExpanded) {
        Column({ space: Space.xs }) {
          if (this.item.preview.expected) {
            Text('预期：' + this.item.preview.expected)
              .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted')).width('100%')
          }
          if (this.item.preview.actual) {
            Text('实际：' + this.item.preview.actual)
              .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted')).width('100%')
          }
          if (this.item.preview.workaround) {
            Text('临时绕过：' + this.item.preview.workaround)
              .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted')).width('100%')
          }
          Text('轨迹：' + this.traceSummaryText())
            .fontSize(FontSize.badge).lineHeight(LineHeight.caption).fontColor($r('app.color.muted')).width('100%')
        }
        .width('100%')
        .padding(Space.sm)
        .backgroundColor($r('app.color.group'))
        .borderRadius(Radius.tool)
        .alignItems(HorizontalAlign.Start)
      }

      if (feedbackRequestDisplay(this.item).kind === 'pending') {
        if (this.item.conversationTrace !== undefined) {
          Row({ space: Space.xs }) {
            Toggle({ type: ToggleType.Switch, isOn: this.includeConversation })
              .enabled(!this.submitting && !this.busy && this.canOperate)
              .onChange((checked: boolean) => { this.includeConversation = checked; })
            Text('附带相关轮次的脱敏对话正文')
              .fontSize(FontSize.caption)
              .lineHeight(LineHeight.caption)
              .fontColor($r('app.color.muted'))
              .layoutWeight(1)
          }.width('100%').alignItems(VerticalAlign.Center)
        }

        if (this.error) {
          Text(this.error).fontSize(FontSize.caption).fontColor($r('app.color.danger')).width('100%')
        }

        Row({ space: Space.xs }) {
          Column() {
            AppButton({
              label: '不发送',
              kind: 'secondary',
              compact: true,
              fill: true,
              disabled: this.submitting || this.busy || !this.canOperate,
              onTap: () => { void this.submit('decline'); }
            })
          }.layoutWeight(1)
          Column() {
            AppButton({
              label: this.submitting ? '提交中…' : '发送报告',
              kind: 'primary',
              compact: true,
              fill: true,
              disabled: this.submitting || this.busy || !this.canOperate,
              onTap: () => { void this.submit('send'); }
            })
          }.layoutWeight(1)
        }.width('100%').padding({ top: Space.xxs })
      }
    }
    .width('100%')
    .padding(Space.md)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('app.color.card'))
    .borderRadius(Radius.card)
  }
}
