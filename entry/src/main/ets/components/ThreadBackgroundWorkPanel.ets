import { FontSize, LineHeight, Radius, Sizes, Space, Weight } from '../common/Theme';
import { PendingBackgroundTaskView } from '../protocol/FloatingStatus';
import { AppButton } from './ui/AppButton';
import { TopBar } from './ui/TopBar';

function kindLabel(kind: string): string {
  if (kind === 'subagent') return '子 Agent';
  if (kind === 'command') return '命令';
  if (kind === 'monitor') return '监控';
  return '后台任务';
}

function kindIcon(kind: string): Resource {
  if (kind === 'subagent') return $r('app.media.ui_subagents');
  if (kind === 'monitor') return $r('app.media.ui_clock');
  return $r('app.media.ui_terminal');
}

@Component
export struct ThreadBackgroundWorkPanel {
  @Prop tasks: PendingBackgroundTaskView[] = [];
  @Prop canOperate: boolean = false;
  @Prop stopPending: boolean = false;
  @Prop busy: boolean = false;
  onClose: () => void = () => {};
  onOpenThread: (threadId: string) => void = () => {};
  onStopAll: () => void = () => {};

  build() {
    Column() {
      TopBar({
        title: '后台工作',
        showBack: true,
        closeStyle: true,
        backLabel: '关闭后台工作',
        onBack: () => this.onClose()
      })
      Scroll() {
        Column({ space: Space.sm }) {
          if (!this.tasks.length) {
            Column() {
              Text('当前没有后台任务在运行')
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
            Column() {
              ForEach(this.tasks, (task: PendingBackgroundTaskView, index: number) => {
                Button({ type: ButtonType.Normal, stateEffect: task.childThreadId !== '' }) {
                  Row({ space: Space.sm }) {
                    Image(kindIcon(task.kind))
                      .width(16)
                      .height(16)
                      .objectFit(ImageFit.Contain)
                      .opacity(0.78)
                      .accessibilityLevel('no')
                    Column({ space: 2 }) {
                      Text(task.label)
                        .fontSize(FontSize.body)
                        .lineHeight(LineHeight.body)
                        .fontWeight(Weight.medium)
                        .fontColor($r('app.color.ink'))
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .width('100%')
                      Text(kindLabel(task.kind) + (task.awaited ? ' · 等待完成' : ''))
                        .fontSize(FontSize.caption)
                        .lineHeight(LineHeight.caption)
                        .fontColor($r('app.color.muted'))
                        .width('100%')
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                    if (task.childThreadId) {
                      Image($r('app.media.ui_chevron_right'))
                        .width(Sizes.chevron)
                        .height(Sizes.chevron)
                        .opacity(0.6)
                        .accessibilityLevel('no')
                    }
                  }
                  .width('100%')
                  .constraintSize({ minHeight: Sizes.listRowMin })
                  .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
                  .alignItems(VerticalAlign.Center)
                }
                .width('100%')
                .backgroundColor(Color.Transparent)
                .border({
                  width: { top: index > 0 ? Sizes.hairline : 0 },
                  color: { top: $r('app.color.separator') }
                })
                .enabled(task.childThreadId !== '')
                .accessibilityText(task.childThreadId ? '打开子 Agent：' + task.label : task.label + '，' + kindLabel(task.kind))
                .onClick(() => {
                  if (task.childThreadId) this.onOpenThread(task.childThreadId);
                })
              }, (task: PendingBackgroundTaskView) => task.taskId + '|' + task.kind + '|' + task.label + '|' +
                task.childThreadId + '|' + String(task.awaited))
            }
            .width('100%')
            .backgroundColor($r('app.color.card'))
            .borderRadius(Radius.card)
            .clip(true)

            if (this.canOperate) {
              Column() {
                AppButton({
                  label: this.stopPending ? '正在停止…' : '停止后台工作',
                  kind: 'danger',
                  fill: true,
                  disabled: this.busy || this.stopPending,
                  onTap: () => this.onStopAll()
                })
              }.width('100%').padding({ top: Space.xs })
            }
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
