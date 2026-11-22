import { FontSize, LineHeight, Radius, Space, Weight } from '../common/Theme';
import { formatWorkingDuration } from '../protocol/FloatingStatus';
import { SubagentView } from '../protocol/R4';
import { AppButton } from './ui/AppButton';
import { BadgeTone, StatusBadge } from './ui/StatusBadge';
import { TopBar } from './ui/TopBar';

function subagentStatusText(status: string): string {
  if (status === 'running') return '运行中';
  if (status === 'pending') return '排队中';
  if (status === 'waiting') return '等待中';
  if (status === 'idle') return '空闲';
  if (status === 'completed') return '已完成';
  if (status === 'failed') return '失败';
  if (status === 'cancelled') return '已取消';
  if (status === 'interrupted') return '已停止';
  return status || '未知';
}

function subagentStatusTone(status: string): BadgeTone {
  if (status === 'running' || status === 'pending' || status === 'waiting') return 'info';
  if (status === 'completed') return 'success';
  if (status === 'failed') return 'danger';
  return 'neutral';
}

@Component
export struct ThreadAgentsPanel {
  @Prop @Watch('syncTimer') subagents: SubagentView[] = [];
  @Prop busy: boolean = false;
  @Prop connected: boolean = false;
  @State private nowMs: number = Date.now();
  private timerId: number = 0;
  onClose: () => void = () => {};
  onOpenThread: (threadId: string, remoteEnvironmentId: string) => void = () => {};
  onStopSubagent: (id: string) => void = () => {};

  aboutToAppear(): void {
    this.syncTimer();
  }

  aboutToDisappear(): void {
    if (this.timerId) {
      clearInterval(this.timerId);
      this.timerId = 0;
    }
  }

  private hasActiveAgent(): boolean {
    return this.subagents.some((agent: SubagentView) =>
      agent.status === 'pending' || agent.status === 'running' || agent.status === 'waiting');
  }

  private syncTimer(): void {
    if (this.hasActiveAgent()) {
      if (!this.timerId) {
        this.nowMs = Date.now();
        this.timerId = setInterval(() => {
          if (this.hasActiveAgent()) {
            this.nowMs = Date.now();
          } else if (this.timerId) {
            clearInterval(this.timerId);
            this.timerId = 0;
          }
        }, 1000) as number;
      }
    } else if (this.timerId) {
      clearInterval(this.timerId);
      this.timerId = 0;
    }
  }

  private elapsedLabel(agent: SubagentView): string {
    if (!agent.startedAt) return '';
    const startMs = Date.parse(agent.startedAt);
    if (!Number.isFinite(startMs)) return '';
    const active = agent.status === 'pending' || agent.status === 'running' || agent.status === 'waiting';
    if (active) return formatWorkingDuration(agent.startedAt, this.nowMs);
    if (agent.status !== 'completed' || !agent.completedAt) return '';
    const endMs = Date.parse(agent.completedAt);
    if (!Number.isFinite(endMs) || endMs <= startMs) return '';
    return formatWorkingDuration(agent.startedAt, endMs);
  }

  private pendingLabel(kind: string): string {
    if (kind === 'user_input') return '等待回答问题';
    return '等待审批操作';
  }

  private confirmStop(agent: SubagentView): void {
    AlertDialog.show({
      title: agent.isWorkflow ? '停止工作流？' : '停止子 Agent？',
      message: agent.isWorkflow
        ? '「' + agent.title + '」中正在运行的子 Agent 将全部停止。'
        : '将请求停止「' + agent.title + '」。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '停止',
        fontColor: $r('app.color.danger'),
        action: () => { this.onStopSubagent(agent.id); }
      }
    });
  }

  build() {
    Column() {
      TopBar({
        title: '子 Agent · ' + this.subagents.length,
        showBack: true,
        closeStyle: true,
        backLabel: '关闭子 Agent 列表',
        onBack: () => this.onClose()
      })
      Scroll() {
        Column({ space: Space.sm }) {
          if (!this.subagents.length) {
            Column() {
              Text('当前轮次没有子 Agent')
                .fontSize(FontSize.body)
                .lineHeight(LineHeight.body)
                .fontColor($r('app.color.muted'))
                .textAlign(TextAlign.Center)
                .width('100%')
            }
            .padding(Space.lg)
            .width('100%')
            .backgroundColor($r('app.color.card'))
            .borderRadius(Radius.card)
          } else {
            ForEach(this.subagents, (agent: SubagentView) => {
              Column({ space: Space.xs }) {
                Row({ space: Space.xs }) {
                  Text(agent.title)
                    .fontSize(FontSize.body)
                    .lineHeight(LineHeight.body)
                    .fontWeight(Weight.medium)
                    .fontColor($r('app.color.ink'))
                    .layoutWeight(1)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (this.elapsedLabel(agent)) {
                    Text(this.elapsedLabel(agent))
                      .fontSize(FontSize.caption)
                      .lineHeight(LineHeight.caption)
                      .fontColor($r('app.color.muted'))
                      .flexShrink(0)
                  }
                  StatusBadge({
                    text: subagentStatusText(agent.status),
                    tone: subagentStatusTone(agent.status)
                  })
                }.width('100%').alignItems(VerticalAlign.Center)

                if (agent.pendingKind) {
                  Text('子会话待处理：' + this.pendingLabel(agent.pendingKind))
                    .fontSize(FontSize.caption)
                    .lineHeight(LineHeight.caption)
                    .fontColor($r('app.color.warning'))
                    .width('100%')
                }
                if (agent.detail) {
                  Text(agent.detail)
                    .fontSize(FontSize.caption)
                    .lineHeight(LineHeight.caption)
                    .fontColor($r('app.color.muted'))
                    .width('100%')
                    .maxLines(4)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                if (agent.childThreadId || agent.remoteThreadId || agent.canStop) {
                  Row({ space: Space.xs }) {
                    if (agent.childThreadId || agent.remoteThreadId) {
                      Row() {
                        AppButton({
                          label: '打开会话',
                          kind: 'secondary',
                          compact: true,
                          fill: true,
                          disabled: !this.connected,
                          onTap: () => this.onOpenThread(agent.childThreadId || agent.remoteThreadId, agent.remoteEnvironmentId)
                        })
                      }.layoutWeight(1)
                    }
                    if (agent.canStop) {
                      Row() {
                        AppButton({
                          label: '停止',
                          kind: 'danger',
                          compact: true,
                          fill: true,
                          disabled: this.busy || !this.connected,
                          onTap: () => this.confirmStop(agent)
                        })
                      }.layoutWeight(1)
                    }
                  }.width('100%').padding({ top: Space.xxs })
                }
              }
              .padding(Space.md)
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .backgroundColor($r('app.color.card'))
              .borderRadius(Radius.card)
            }, (agent: SubagentView) => agent.id + '|' + agent.status + '|' + String(agent.canStop) + '|' +
              agent.pendingKind + '|' + agent.detail + '|' + agent.title + '|' + agent.updatedAt + '|' +
              String(this.busy) + '|' + String(this.connected))
          }
        }
        .padding({ left: Space.page, right: Space.page, top: Space.xs, bottom: Space.lg })
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.group'))
    .foregroundColor($r('app.color.ink'))
  }
}
