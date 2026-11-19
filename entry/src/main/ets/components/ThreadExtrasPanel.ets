import { BackgroundTaskView, DraftAttachment, GuestMessageView, GuestShareView, PlanView, SubagentView, TokenUsage } from '../protocol/R4';

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
    Scroll() {
      Column({ space: 14 }) {
        Row() {
          Text('会话状态').fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
          Button('×').width(40).height(40).backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
            .accessibilityText('关闭').onClick(this.onClose)
        }.width('100%')
        if (this.usage) {
          Column({ space: 5 }) {
            Text('用量').fontSize(12).fontColor($r('app.color.muted')).width('100%')
            Text(this.usage.inputTokens + ' 输入 · ' + this.usage.outputTokens + ' 输出' +
              (this.usage.maxTokens ? ' / ' + this.usage.maxTokens : '') + (this.usage.cost ? ' · ' + this.usage.cost : ''))
              .fontSize(14).width('100%')
            Button('查看用量与管理限制').height(38).backgroundColor($r('app.color.surface'))
              .fontColor($r('app.color.ink')).width('100%').onClick(this.onUsage)
          }.width('100%')
        }
        if (this.plans.length) {
          Text('计划').fontSize(12).fontColor($r('app.color.muted')).width('100%')
          ForEach(this.plans, (plan: PlanView) => {
            Column({ space: 6 }) {
              Text(plan.streaming ? '正在生成计划' : '计划 · ' + plan.status).fontSize(13).fontColor($r('app.color.muted')).width('100%')
              Text(plan.markdown).fontSize(14).width('100%').maxLines(12).copyOption(CopyOptions.InApp)
              Button('复制计划').height(36).width('100%').backgroundColor($r('app.color.surface'))
                .fontColor($r('app.color.ink')).onClick(() => this.onCopy(plan.markdown))
            }.padding(12).width('100%').backgroundColor($r('app.color.surface')).borderRadius(12)
          }, (plan: PlanView) => plan.id)
        }
        if (this.subagents.length) {
          Text('子 Agent 与后台工作').fontSize(12).fontColor($r('app.color.muted')).width('100%')
          ForEach(this.subagents, (agent: SubagentView) => {
            Column({ space: 6 }) {
              Row() {
                Text(agent.title).fontSize(14).fontWeight(FontWeight.Medium).layoutWeight(1).maxLines(1)
                Text(agent.status).fontSize(11).fontColor($r('app.color.muted'))
              }.width('100%')
              if (agent.pendingKind) { Text('子会话待处理：' + agent.pendingKind).fontSize(12).fontColor($r('app.color.primary')).width('100%') }
              if (agent.detail) { Text(agent.detail).fontSize(12).fontColor($r('app.color.muted')).width('100%').maxLines(4) }
              Row({ space: 8 }) {
                if (agent.childThreadId || agent.remoteThreadId) {
                  Button('打开').height(34).layoutWeight(1).backgroundColor($r('app.color.surface'))
                    .fontColor($r('app.color.ink')).enabled(this.connected)
                    .onClick(() => this.onOpenThread(agent.childThreadId || agent.remoteThreadId, agent.remoteEnvironmentId))
                }
                if (agent.canStop) {
                  Button('停止').height(34).layoutWeight(1).backgroundColor($r('app.color.surface'))
                    .fontColor($r('app.color.ink')).enabled(!this.busy).onClick(() => this.onStopSubagent(agent.id))
                }
              }.width('100%')
            }.padding(12).width('100%').border({ width: 1, color: $r('app.color.border') }).borderRadius(12)
          }, (agent: SubagentView) => agent.id)
        }
        if (this.backgroundTasks.length) {
          Text('后台工作').fontSize(12).fontColor($r('app.color.muted')).width('100%')
          ForEach(this.backgroundTasks, (task: BackgroundTaskView) => {
            Button(task.label + ' · ' + task.kind).width('100%').height(38).fontSize(12)
              .backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink'))
              .enabled(task.childThreadId !== '')
              .onClick(() => this.onOpenThread(task.childThreadId, ''))
          }, (task: BackgroundTaskView) => task.id)
        }
        Text('分叉与共享').fontSize(12).fontColor($r('app.color.muted')).width('100%')
        Button('从最新运行分叉会话').height(40).width('100%').backgroundColor($r('app.color.surface'))
          .fontColor($r('app.color.ink')).enabled(!this.busy && this.connected).onClick(() => this.onFork(false))
        Button('开启 Side chat').height(40).width('100%').backgroundColor($r('app.color.surface'))
          .fontColor($r('app.color.ink')).enabled(!this.busy && this.connected).onClick(() => this.onFork(true))
        if (this.guest) {
          Text((this.guest.guestName || '访客') + ' · ' + (Date.parse(this.guest.expiresAt) <= Date.now() ? '链接已过期' : '链接有效'))
            .fontSize(13).width('100%')
          ForEach(this.guest.messages.filter((message: GuestMessageView) => message.status === 'pending'),
            (message: GuestMessageView) => {
              Column({ space: 6 }) {
                Text(message.text || '访客发送了附件').fontSize(13).width('100%').maxLines(4)
                ForEach(message.attachments, (attachment: DraftAttachment) => {
                  Text('附件 · ' + attachment.name).fontSize(11).fontColor($r('app.color.muted')).width('100%')
                })
                Row({ space: 8 }) {
                  Button('发送访客消息').height(36).layoutWeight(1).backgroundColor($r('app.color.primary'))
                    .fontColor($r('app.color.on_primary')).enabled(!this.busy)
                    .onClick(() => this.onResolveGuest(message.id, true))
                  Button('忽略').height(36).layoutWeight(1).backgroundColor($r('app.color.surface'))
                    .fontColor($r('app.color.ink')).enabled(!this.busy)
                    .onClick(() => this.onResolveGuest(message.id, false))
                }.width('100%')
              }.padding(10).width('100%').backgroundColor($r('app.color.surface')).borderRadius(10)
            }, (message: GuestMessageView) => message.id)
          Button('停止共享').height(40).width('100%').backgroundColor($r('app.color.surface'))
            .fontColor($r('app.color.ink')).enabled(!this.busy).onClick(this.onCloseGuest)
        } else {
          Button('创建访客链接').height(40).width('100%').backgroundColor($r('app.color.surface'))
            .fontColor($r('app.color.ink')).enabled(!this.busy && this.connected).onClick(this.onCreateGuest)
        }
      }.padding(20).width('100%').alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').align(Alignment.TopStart)
      .foregroundColor($r('app.color.ink')).backgroundColor($r('app.color.canvas'))
  }
}

