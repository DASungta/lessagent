import { FontSize, LineHeight, Opacity, Radius, Weight } from '../common/Theme';
import { MessageFooterMeta } from '../protocol/ThreadItems';

const COPY_FEEDBACK_DURATION_MS = 1200;

@Component
export struct MessageFooter {
  @Prop messageId: string = '';
  @Prop role: string = 'assistant';
  @Prop text: string = '';
  @Prop timestampLabel: string = '';
  @Consume('t3MessageFooterMap') footerMap: Record<string, MessageFooterMeta>;
  @Consume('t3ForkingMessageId') forkingMessageId: string;
  @Consume('t3CanOperateChat') canOperateChat: boolean;
  onCopy: (value: string) => Promise<boolean> = async () => false;
  onFork: (messageId: string, runId: string, sourceThreadId: string) => void = () => {};
  @State copied: boolean = false;
  private copyTimer: number = 0;

  aboutToDisappear(): void {
    if (this.copyTimer) {
      clearTimeout(this.copyTimer);
      this.copyTimer = 0;
    }
  }

  private meta(): MessageFooterMeta | undefined {
    return this.messageId && this.footerMap ? this.footerMap[this.messageId] : undefined;
  }

  private handleCopy(): void {
    if (!this.text.trim()) return;
    void this.onCopy(this.text).then((ok: boolean) => {
      if (!ok) return;
      this.copied = true;
      if (this.copyTimer) clearTimeout(this.copyTimer);
      this.copyTimer = setTimeout(() => {
        this.copyTimer = 0;
        this.copied = false;
      }, COPY_FEEDBACK_DURATION_MS);
    });
  }

  @Builder
  copyButton() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      if (this.copied) {
        Image($r('app.media.ui_check'))
          .width(16)
          .height(16)
          .objectFit(ImageFit.Contain)
          .draggable(false)
          .accessibilityLevel('no')
      } else {
        Image($r('app.media.ui_copy'))
          .width(16)
          .height(16)
          .objectFit(ImageFit.Contain)
          .draggable(false)
          .accessibilityLevel('no')
      }
    }
    .width(36)
    .height(36)
    .borderRadius(Radius.tool)
    .backgroundColor(Color.Transparent)
    .accessibilityText(this.copied ? '已复制' : '复制消息')
    .onClick(() => this.handleCopy())
  }

  @Builder
  forkButton(meta: MessageFooterMeta) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      if (this.forkingMessageId === this.messageId) {
        LoadingProgress()
          .width(16)
          .height(16)
          .color($r('app.color.muted'))
      } else {
        Image($r('app.media.ui_fork'))
          .width(16)
          .height(16)
          .objectFit(ImageFit.Contain)
          .draggable(false)
          .accessibilityLevel('no')
      }
    }
    .width(36)
    .height(36)
    .borderRadius(Radius.tool)
    .backgroundColor(Color.Transparent)
    .enabled(this.canOperateChat && this.forkingMessageId === '')
    .opacity(this.canOperateChat && (this.forkingMessageId === '' || this.forkingMessageId === this.messageId)
      ? 1 : Opacity.disabled)
    .accessibilityText(this.forkingMessageId === this.messageId ? '正在分叉会话' : '从这条回复分叉会话')
    .onClick(() => {
      if (!this.canOperateChat || this.forkingMessageId !== '') return;
      this.onFork(this.messageId, meta.forkRunId, meta.forkSourceThreadId);
    })
  }

  build() {
    Column() {
      if (this.meta() && this.meta()!.showFooter &&
        (this.meta()!.canCopy || this.meta()!.canFork || this.timestampLabel.length > 0)) {
        if (this.role === 'user') {
          Row({ space: 4 }) {
            if (this.timestampLabel) {
              Text(this.timestampLabel)
                .fontSize(FontSize.caption)
                .lineHeight(LineHeight.caption)
                .fontWeight(Weight.medium)
                .fontColor($r('app.color.muted'))
            }
            if (this.meta()!.canCopy) {
              this.copyButton()
            }
          }
          .width('100%')
          .justifyContent(FlexAlign.End)
          .alignItems(VerticalAlign.Center)
          .margin({ top: 2 })
        } else {
          Row({ space: 6 }) {
            if (this.meta()!.canCopy) {
              this.copyButton()
            }
            if (this.meta()!.canFork) {
              this.forkButton(this.meta()!)
            }
            if (this.timestampLabel) {
              Text(this.timestampLabel)
                .fontSize(FontSize.caption)
                .lineHeight(LineHeight.caption)
                .fontWeight(Weight.medium)
                .fontColor($r('app.color.muted'))
                .margin({ left: (this.meta()!.canCopy || this.meta()!.canFork) ? 4 : 0 })
            }
          }
          .width('100%')
          .justifyContent(FlexAlign.Start)
          .alignItems(VerticalAlign.Center)
          .margin({ top: 4 })
        }
      }
    }.width('100%')
  }
}
