import { FontSize, LineHeight, Radius, Space } from '../common/Theme';
import { QueuedRun } from '../protocol/Composer';
import { AppButton } from './ui/AppButton';
import { StatusBadge } from './ui/StatusBadge';
import { TopBar } from './ui/TopBar';

@Component
export struct QueuePanel {
  @Prop runs: QueuedRun[] = [];
  @Prop busy: boolean = false;
  @Prop active: boolean = false;
  @Prop status: string = '';
  onAction: (action: string, id: string, before: string | null, text: string) => void = () => {};
  onClose: () => void = () => {};
  @State editingId: string = '';
  @State editedText: string = '';
  build() {
    Column() {
      TopBar({
        title: '消息队列 · ' + this.runs.length,
        showBack: true,
        closeStyle: true,
        onBack: () => { if (!this.busy) this.onClose(); }
      })
      Column({ space: Space.sm }) {
        if (this.runs.some((run: QueuedRun) => run.held)) {
          AppButton({
            label: '恢复队列',
            kind: 'primary',
            fill: true,
            disabled: this.busy,
            onTap: () => this.onAction('resume', '', null, '')
          })
        }
        List({ space: Space.sm }) {
          ForEach(this.runs, (run: QueuedRun, index: number) => {
            ListItem() {
              Column({ space: Space.xs }) {
                Row({ space: Space.xs }) {
                  Text('#' + (index + 1)).fontSize(FontSize.caption).fontColor($r('app.color.muted'))
                  StatusBadge({ text: run.held ? '暂停' : '等待中', tone: run.held ? 'warning' : 'info' })
                }.width('100%').alignItems(VerticalAlign.Center)
                if (this.editingId === run.id) {
                  TextArea({ text: this.editedText })
                    .onChange((value: string) => { this.editedText = value; })
                    .height(110)
                    .fontSize(FontSize.body)
                    .fontColor($r('app.color.ink'))
                    .backgroundColor($r('app.color.group'))
                    .borderRadius(Radius.button)
                    .padding(Space.sm)
                    .enabled(!this.busy)
                  Row({ space: Space.xs }) {
                    AppButton({
                      label: '取消编辑',
                      kind: 'secondary',
                      compact: true,
                      disabled: this.busy,
                      onTap: () => { this.editingId = ''; this.editedText = ''; }
                    })
                    AppButton({
                      label: '保存',
                      kind: 'primary',
                      compact: true,
                      disabled: this.busy || !this.editedText.trim(),
                      onTap: () => {
                        const text = this.editedText;
                        this.editingId = ''; this.editedText = '';
                        this.onAction('edit', run.id, null, text);
                      }
                    })
                  }.width('100%').justifyContent(FlexAlign.End)
                } else {
                  Text(run.text || '消息内容未随当前快照提供')
                    .fontSize(FontSize.body).lineHeight(LineHeight.body).fontColor($r('app.color.ink')).width('100%')
                  ForEach(run.attachmentNames, (name: string) => {
                    Text('附件 · ' + name).fontSize(FontSize.caption).fontColor($r('app.color.muted')).width('100%')
                  })
                  Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                    Row() {
                      AppButton({
                        label: '编辑',
                        kind: 'secondary',
                        compact: true,
                        disabled: this.busy || !run.text,
                        onTap: () => { this.editingId = run.id; this.editedText = run.text; }
                      })
                    }.margin({ right: Space.xs, top: Space.xxs })
                    if (index > 0) {
                      Row() {
                        AppButton({
                          label: '上移',
                          kind: 'secondary',
                          compact: true,
                          disabled: this.busy,
                          onTap: () => this.onAction('reorder', run.id, this.runs[index - 1].id, '')
                        })
                      }.margin({ right: Space.xs, top: Space.xxs })
                    }
                    if (index < this.runs.length - 1) {
                      Row() {
                        AppButton({
                          label: '下移',
                          kind: 'secondary',
                          compact: true,
                          disabled: this.busy,
                          onTap: () => this.onAction('reorder', run.id, index + 2 < this.runs.length ? this.runs[index + 2].id : null, '')
                        })
                      }.margin({ right: Space.xs, top: Space.xxs })
                    }
                    Row() {
                      AppButton({
                        label: '立即引导',
                        kind: 'secondary',
                        compact: true,
                        disabled: this.busy,
                        onTap: () => this.onAction('promote', run.id, null, '')
                      })
                    }.margin({ right: Space.xs, top: Space.xxs })
                    if (!this.active) {
                      Row() {
                        AppButton({
                          label: '立即开始',
                          kind: 'secondary',
                          compact: true,
                          disabled: this.busy,
                          onTap: () => this.onAction('start', run.id, null, '')
                        })
                      }.margin({ right: Space.xs, top: Space.xxs })
                    }
                    Row() {
                      AppButton({
                        label: '移除',
                        kind: 'danger',
                        compact: true,
                        disabled: this.busy,
                        onTap: () => {
                          AlertDialog.show({
                            title: '移除待发送消息？',
                            message: '此操作会取消这条排队消息。',
                            primaryButton: { value: '取消', action: () => {} },
                            secondaryButton: { value: '移除', action: () => this.onAction('cancel', run.id, null, '') }
                          });
                        }
                      })
                    }.margin({ right: Space.xs, top: Space.xxs })
                  }.width('100%')
                }
              }.padding(Space.md).width('100%').backgroundColor($r('app.color.card')).borderRadius(Radius.card)
            }
          }, (run: QueuedRun) => run.id)
          if (!this.runs.length) {
            ListItem() {
              Column() {
                Text('没有排队消息').fontSize(FontSize.body).fontColor($r('app.color.muted')).width('100%')
              }.width('100%').padding(Space.md).backgroundColor($r('app.color.card')).borderRadius(Radius.card)
            }
          }
        }.layoutWeight(1).width('100%')
        if (this.status) {
          Text(this.status).fontSize(FontSize.caption).fontColor($r('app.color.muted')).width('100%')
        }
      }.layoutWeight(1).width('100%').padding({ left: Space.page, right: Space.page, top: Space.xs, bottom: Space.md })
    }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
  }
}
