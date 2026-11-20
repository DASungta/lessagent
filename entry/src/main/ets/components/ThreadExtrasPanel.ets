import { FontSize, LineHeight, Radius, Space, Weight } from '../common/Theme';
import { BackgroundTaskView, DraftAttachment, GuestMessageView, GuestShareView, PlanView, SubagentView, TokenUsage } from '../protocol/R4';
import { AppButton } from './ui/AppButton';
import { GroupCard } from './ui/GroupCard';
import { StatusBadge } from './ui/StatusBadge';
import { TopBar } from './ui/TopBar';

@Component
export struct ThreadExtrasPanel {
  @Prop busy: boolean = false;
  @Prop plans: PlanView[] = [];
  @Prop subagents: SubagentView[] = [];
  @Prop backgroundTasks: BackgroundTaskView[] = [];
  @Prop usage: TokenUsage | undefined = undefined;
  @Prop guest: GuestShareView | undefined = undefined;
  @Prop connected: boolean = false;
  onClose: () => void = () => {};
  onCopy: (text: string) => void = () => {};
  onOpenThread: (threadId: string, remoteEnvironmentId: string) => void = () => {};
  onStopSubagent: (id: string) => void = () => {};
  onFork: (sideChat: boolean) => void = () => {};
  onCreateGuest: () => void = () => {};
  onCloseGuest: () => void = () => {};
  onResolveGuest: (id: string, send: boolean) => void = () => {};
  onUsage: () => void = () => {};

  build() {
    Column() {
      TopBar({ title: '会话状态', showBack: true, closeStyle: true, onBack: this.onClose })
      Scroll() {
        Column({ space: Space.sm }) {
          if (this.usage) {
            GroupCard({ title: '用量' }) {
              Column({ space: Space.sm }) {
                Text(this.usage.inputTokens + ' 输入 · ' + this.usage.outputTokens + ' 输出' +
                  (this.usage.maxTokens ? ' / ' + this.usage.maxTokens : '') + (this.usage.cost ? ' · ' + this.usage.cost : ''))
                  .fontSize(FontSize.body).lineHeight(LineHeight.body).fontColor($r('app.color.ink')).width('100%')
                AppButton({ label: '查看用量与管理限制', kind: 'secondary', compact: true, fill: true, onTap: this.onUsage })
              }.padding(Space.md).width('100%').alignItems(HorizontalAlign.Start)
            }
          }
          if (this.plans.length) {
            Text('计划')
              .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs }).width('100%')
            ForEach(this.plans, (plan: PlanView) => {
              Column({ space: Space.xs }) {
                StatusBadge({
                  text: plan.streaming ? '正在生成计划' : '计划 · ' + plan.status,
                  tone: plan.streaming ? 'info' : 'neutral'
                })
                Text(plan.markdown)
                  .fontSize(FontSize.body).lineHeight(LineHeight.body).fontColor($r('app.color.ink'))
                  .width('100%').maxLines(12).copyOption(CopyOptions.InApp)
                AppButton({
                  label: '复制计划',
                  kind: 'secondary',
                  compact: true,
                  fill: true,
                  onTap: () => this.onCopy(plan.markdown)
                })
              }.padding(Space.md).width('100%').alignItems(HorizontalAlign.Start)
                .backgroundColor($r('app.color.card')).borderRadius(Radius.card)
            }, (plan: PlanView) => plan.id)
          }
          if (this.subagents.length) {
            Text('子 Agent 与后台工作')
              .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs }).width('100%')
            ForEach(this.subagents, (agent: SubagentView) => {
              Column({ space: Space.xs }) {
                Row({ space: Space.xs }) {
                  Text(agent.title)
                    .fontSize(FontSize.body).lineHeight(LineHeight.body).fontWeight(Weight.medium)
                    .fontColor($r('app.color.ink')).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  StatusBadge({ text: agent.status, tone: agent.canStop ? 'info' : 'neutral' })
                }.width('100%').alignItems(VerticalAlign.Center)
                if (agent.pendingKind) {
                  Text('子会话待处理：' + agent.pendingKind)
                    .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.primary_text')).width('100%')
                }
                if (agent.detail) {
                  Text(agent.detail)
                    .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted'))
                    .width('100%').maxLines(4)
                }
                Row({ space: Space.xs }) {
                  if (agent.childThreadId || agent.remoteThreadId) {
                    Row() {
                      AppButton({
                        label: '打开',
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
                        disabled: this.busy,
                        onTap: () => this.onStopSubagent(agent.id)
                      })
                    }.layoutWeight(1)
                  }
                }.width('100%')
              }.padding(Space.md).width('100%').alignItems(HorizontalAlign.Start)
                .backgroundColor($r('app.color.card')).borderRadius(Radius.card)
            }, (agent: SubagentView) => agent.id)
          }
          if (this.backgroundTasks.length) {
            GroupCard({ title: '后台工作' }) {
              Column({ space: Space.xs }) {
                ForEach(this.backgroundTasks, (task: BackgroundTaskView) => {
                  AppButton({
                    label: task.label + ' · ' + task.kind,
                    kind: 'secondary',
                    compact: true,
                    fill: true,
                    disabled: task.childThreadId === '',
                    onTap: () => this.onOpenThread(task.childThreadId, '')
                  })
                }, (task: BackgroundTaskView) => task.id)
              }.padding(Space.sm).width('100%')
            }
          }
          GroupCard({ title: '分叉与共享' }) {
            Column({ space: Space.xs }) {
              AppButton({
                label: '从最新运行分叉会话',
                kind: 'secondary',
                compact: true,
                fill: true,
                disabled: this.busy || !this.connected,
                onTap: () => this.onFork(false)
              })
              AppButton({
                label: '开启 Side chat',
                kind: 'secondary',
                compact: true,
                fill: true,
                disabled: this.busy || !this.connected,
                onTap: () => this.onFork(true)
              })
              if (this.guest) {
                Row({ space: Space.xs }) {
                  Text(this.guest.guestName || '访客')
                    .fontSize(FontSize.callout).fontWeight(Weight.medium).fontColor($r('app.color.ink')).layoutWeight(1)
                  StatusBadge({
                    text: Date.parse(this.guest.expiresAt) <= Date.now() ? '链接已过期' : '链接有效',
                    tone: Date.parse(this.guest.expiresAt) <= Date.now() ? 'warning' : 'success'
                  })
                }.width('100%').padding({ top: Space.xxs })
                ForEach(this.guest.messages.filter((message: GuestMessageView) => message.status === 'pending'),
                  (message: GuestMessageView) => {
                    Column({ space: Space.xs }) {
                      Text(message.text || '访客发送了附件')
                        .fontSize(FontSize.callout).lineHeight(LineHeight.callout).fontColor($r('app.color.ink'))
                        .width('100%').maxLines(4)
                      ForEach(message.attachments, (attachment: DraftAttachment) => {
                        Text('附件 · ' + attachment.name).fontSize(FontSize.caption).fontColor($r('app.color.muted')).width('100%')
                      })
                      Row({ space: Space.xs }) {
                        Row() {
                          AppButton({
                            label: '发送访客消息',
                            kind: 'primary',
                            compact: true,
                            fill: true,
                            disabled: this.busy,
                            onTap: () => this.onResolveGuest(message.id, true)
                          })
                        }.layoutWeight(1)
                        Row() {
                          AppButton({
                            label: '忽略',
                            kind: 'secondary',
                            compact: true,
                            fill: true,
                            disabled: this.busy,
                            onTap: () => this.onResolveGuest(message.id, false)
                          })
                        }.layoutWeight(1)
                      }.width('100%')
                    }.padding(Space.sm).width('100%').backgroundColor($r('app.color.group')).borderRadius(Radius.tool)
                  }, (message: GuestMessageView) => message.id)
                AppButton({
                  label: '停止共享',
                  kind: 'danger',
                  compact: true,
                  fill: true,
                  disabled: this.busy,
                  onTap: this.onCloseGuest
                })
              } else {
                AppButton({
                  label: '创建访客链接',
                  kind: 'secondary',
                  compact: true,
                  fill: true,
                  disabled: this.busy || !this.connected,
                  onTap: this.onCreateGuest
                })
              }
            }.padding(Space.md).width('100%').alignItems(HorizontalAlign.Start)
          }
        }.padding({ left: Space.page, right: Space.page, top: Space.xs, bottom: Space.lg }).width('100%').alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).width('100%').align(Alignment.TopStart)
    }.width('100%').height('100%').foregroundColor($r('app.color.ink')).backgroundColor($r('app.color.group'))
  }
}

