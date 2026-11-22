import { FontSize, LineHeight, Radius, Space, Weight } from '../common/Theme';
import {
  emptyFloatingCapsule,
  FloatingCapsuleModel,
  FloatingCapsuleStatus,
  formatWorkingDuration
} from '../protocol/FloatingStatus';

interface StatusRef {
  status: FloatingCapsuleStatus;
  tickMs: number;
}

@Component
export struct FloatingStatusCapsule {
  @Prop @Watch('syncTimer') model: FloatingCapsuleModel = emptyFloatingCapsule();
  @Prop showScrollToEnd: boolean = false;
  @State private tickMs: number = Date.now();
  private timerId: number = 0;
  onStatusTap: () => void = () => {};
  onActionTap: () => void = () => {};
  onOpenAgents: () => void = () => {};
  onOpenQueue: () => void = () => {};
  onScrollToEnd: () => void = () => {};

  aboutToAppear(): void {
    this.syncTimer();
  }

  aboutToDisappear(): void {
    this.stopTimer();
  }

  private stopTimer(): void {
    if (this.timerId) {
      clearInterval(this.timerId);
      this.timerId = 0;
    }
  }

  private syncTimer(): void {
    const status = this.model.status;
    if (status && status.kind === 'working' && status.startedAt) {
      this.tickMs = Date.now();
      if (!this.timerId) {
        this.timerId = setInterval(() => {
          const current = this.model.status;
          if (current && current.kind === 'working' && current.startedAt) {
            this.tickMs = Date.now();
          } else {
            this.stopTimer();
          }
        }, 1000) as number;
      }
    } else {
      this.stopTimer();
    }
  }

  private isWarningOnly(): boolean {
    const status = this.model.status;
    return !!status && status.kind === 'action-needed' && !this.model.agents && this.model.queuedCount === 0;
  }

  private statusDisplayText(status: FloatingCapsuleStatus): string {
    if (status.kind === 'working' && status.startedAt) {
      return '运行中 ' + formatWorkingDuration(status.startedAt, Math.max(this.tickMs, Date.now()));
    }
    return status.label;
  }

  private statusTextColor(status: FloatingCapsuleStatus): ResourceColor {
    if (status.tone === 'warning') return $r('app.color.warning');
    if (status.tone === 'danger') return $r('app.color.danger');
    return $r('app.color.ink');
  }

  private iconResource(icon: string): Resource {
    if (icon === 'subagents') return $r('app.media.ui_subagents');
    if (icon === 'terminal') return $r('app.media.ui_terminal');
    if (icon === 'clock') return $r('app.media.ui_clock');
    if (icon === 'done') return $r('app.media.status_done');
    if (icon === 'compact') return $r('app.media.ui_compact');
    if (icon === 'target') return $r('app.media.ui_target');
    if (icon === 'chat') return $r('app.media.ui_tab_chats');
    return $r('app.media.status_wait');
  }

  @Builder
  StatusContent($$: StatusRef) {
    if ($$.status.icon === 'spinner') {
      LoadingProgress()
        .width(14)
        .height(14)
        .color($r('app.color.muted'))
        .flexShrink(0)
        .accessibilityLevel('no')
    } else if ($$.status.icon === 'offline') {
      Circle()
        .width(7)
        .height(7)
        .fill($r('app.color.danger'))
        .flexShrink(0)
        .accessibilityLevel('no')
    } else if ($$.status.icon !== 'none') {
      Image(this.iconResource($$.status.icon))
        .width(14)
        .height(14)
        .objectFit(ImageFit.Contain)
        .flexShrink(0)
        .accessibilityLevel('no')
    }
    Text($$.status.kind === 'working' && $$.status.startedAt
      ? '运行中 ' + formatWorkingDuration($$.status.startedAt, Math.max($$.tickMs, Date.now()))
      : $$.status.label)
      .fontSize(FontSize.caption)
      .lineHeight(LineHeight.caption)
      .fontWeight(Weight.medium)
      .fontColor(this.statusTextColor($$.status))
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .constraintSize({ minWidth: 0 })
      .flexShrink(1)
  }

  @Builder
  VerticalDivider() {
    Divider()
      .vertical(true)
      .width(1)
      .height(16)
      .strokeWidth(1)
      .color($r('app.color.chevron'))
      .flexShrink(0)
  }

  build() {
    if (this.model.visible || this.showScrollToEnd) {
      Row() {
        Row()
          .width(2)
          .height(1)
          .flexShrink(0)
          .accessibilityLevel('no')
          .hitTestBehavior(HitTestMode.None)
        if (this.model.visible) {
          Row() {
            if (this.model.status) {
              if (this.model.status.clickable) {
                Row({ space: 6 }) {
                  this.StatusContent({ status: this.model.status, tickMs: this.tickMs })
                }
                .height('100%')
                .padding({ left: 14, right: 12 })
                .alignItems(VerticalAlign.Center)
                .flexShrink(1)
                .constraintSize({ minWidth: 0 })
                .clip(true)
                .stateStyles({
                  normal: { .opacity(1) },
                  pressed: { .opacity(0.65) }
                })
                .accessibilityGroup(true)
                .accessibilityText(this.model.status.accessibilityLabel)
                .onClick(() => this.onStatusTap())
              } else {
                Row({ space: 6 }) {
                  this.StatusContent({ status: this.model.status, tickMs: this.tickMs })
                }
                .height('100%')
                .padding({ left: 14, right: 12 })
                .alignItems(VerticalAlign.Center)
                .flexShrink(1)
                .constraintSize({ minWidth: 0 })
                .clip(true)
                .accessibilityGroup(true)
                .accessibilityText(this.model.status.accessibilityLabel)
                .hitTestBehavior(HitTestMode.None)
              }
            }
            if (this.model.status && this.model.status.actionLabel) {
              this.VerticalDivider()
              Button({ type: ButtonType.Normal, stateEffect: true }) {
                Text(this.model.status.actionLabel)
                  .fontSize(FontSize.caption)
                  .lineHeight(LineHeight.caption)
                  .fontWeight(Weight.medium)
                  .fontColor($r('app.color.ink'))
                  .maxLines(1)
              }
              .height('100%')
              .padding({ left: 12, right: 12 })
              .backgroundColor(Color.Transparent)
              .flexShrink(0)
              .enabled(!this.model.status.actionDisabled)
              .opacity(this.model.status.actionDisabled ? 0.45 : 1)
              .accessibilityText(this.model.status.actionLabel)
              .onClick(() => this.onActionTap())
            }
            if (this.model.agents) {
              if (this.model.status) {
                this.VerticalDivider()
              }
              Button({ type: ButtonType.Normal, stateEffect: true }) {
                Row({ space: 5 }) {
                  Image($r('app.media.ui_subagents'))
                    .width(14)
                    .height(14)
                    .objectFit(ImageFit.Contain)
                    .flexShrink(0)
                    .accessibilityLevel('no')
                  Text(this.model.agents.label)
                    .fontSize(FontSize.caption)
                    .lineHeight(LineHeight.caption)
                    .fontWeight(Weight.medium)
                    .fontColor($r('app.color.ink'))
                    .maxLines(1)
                }
                .height('100%')
                .alignItems(VerticalAlign.Center)
              }
              .height('100%')
              .padding({ left: 12, right: 13 })
              .backgroundColor(Color.Transparent)
              .flexShrink(0)
              .accessibilityText(this.model.agents.accessibilityLabel)
              .onClick(() => this.onOpenAgents())
            }
            if (this.model.queuedCount > 0) {
              if (this.model.status || this.model.agents) {
                this.VerticalDivider()
              }
              Button({ type: ButtonType.Normal, stateEffect: true }) {
                Row({ space: 5 }) {
                  Image($r('app.media.ui_queue'))
                    .width(14)
                    .height(14)
                    .objectFit(ImageFit.Contain)
                    .flexShrink(0)
                    .accessibilityLevel('no')
                  Text(this.model.queuedCount + ' 排队')
                    .fontSize(FontSize.caption)
                    .lineHeight(LineHeight.caption)
                    .fontWeight(Weight.medium)
                    .fontColor($r('app.color.ink'))
                    .maxLines(1)
                }
                .height('100%')
                .alignItems(VerticalAlign.Center)
              }
              .height('100%')
              .padding({ left: 12, right: 13 })
              .backgroundColor(Color.Transparent)
              .flexShrink(0)
              .accessibilityText('打开队列，' + this.model.queuedCount + ' 条排队消息')
              .onClick(() => this.onOpenQueue())
            }
          }
          .height(40)
          .borderRadius(Radius.full)
          .backgroundColor(this.isWarningOnly() ? $r('app.color.warning_bg') : $r('app.color.tab_bar_bg'))
          .border({
            width: 1,
            color: this.isWarningOnly() ? $r('app.color.warning_border') : $r('app.color.border')
          })
          .shadow({ radius: 12, color: '#24000000', offsetX: 0, offsetY: 2 })
          .clip(true)
          .flexShrink(1)
          .alignItems(VerticalAlign.Center)
          .hitTestBehavior(HitTestMode.Transparent)
        }
        if (!this.model.visible && this.showScrollToEnd) {
          Blank()
            .hitTestBehavior(HitTestMode.None)
        }
        if (this.showScrollToEnd) {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            Image($r('app.media.ui_down'))
              .width(16)
              .height(16)
              .objectFit(ImageFit.Contain)
              .accessibilityLevel('no')
          }
          .width(38)
          .height(38)
          .margin({ left: this.model.visible ? Space.xs : 0, right: 2 })
          .flexShrink(0)
          .backgroundColor($r('app.color.tab_bar_bg'))
          .border({ width: 1, color: $r('app.color.border') })
          .shadow({ radius: 10, color: '#24000000', offsetX: 0, offsetY: 2 })
          .accessibilityText('滚动到最新消息')
          .onClick(() => this.onScrollToEnd())
        } else {
          Row()
            .width(2)
            .height(1)
            .flexShrink(0)
            .accessibilityLevel('no')
            .hitTestBehavior(HitTestMode.None)
        }
      }
      .width('100%')
      .padding({ left: Space.sm - 2, right: Space.sm - 2, bottom: Space.xs })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(HitTestMode.Transparent)
    }
  }
}
