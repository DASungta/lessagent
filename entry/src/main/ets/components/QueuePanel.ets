import { QueuedRun } from '../protocol/Composer';

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
    Column({ space: 16 }) {
      Row() {
        Text('消息队列 · ' + this.runs.length).fontSize(18).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button('关闭').backgroundColor(Color.Transparent).fontColor($r('app.color.ink')).enabled(!this.busy).onClick(() => this.onClose())
      }.width('100%')
      if (this.runs.some((run: QueuedRun) => run.held)) {
        Button('恢复队列').enabled(!this.busy).onClick(() => this.onAction('resume', '', null, ''))
      }
      List({ space: 16 }) {
        ForEach(this.runs, (run: QueuedRun, index: number) => {
          ListItem() {
            Column({ space: 8 }) {
              Text((index + 1) + (run.held ? ' · 暂停' : ' · 等待中')).fontSize(12).fontColor($r('app.color.muted')).width('100%')
              if (this.editingId === run.id) {
                TextArea({ text: this.editedText }).onChange((value: string) => this.editedText = value).height(110).enabled(!this.busy)
                Row() {
                  Button('取消编辑').onClick(() => { this.editingId = ''; this.editedText = ''; }).enabled(!this.busy)
                  Button('保存').enabled(!this.busy && !!this.editedText.trim())
                    .onClick(() => {
                      const text = this.editedText;
                      this.editingId = ''; this.editedText = '';
                      this.onAction('edit', run.id, null, text);
                    })
                }
              } else {
                Text(run.text || '消息内容未随当前快照提供').fontSize(15).width('100%')
                ForEach(run.attachmentNames, (name: string) => {
                  Text('附件 · ' + name).fontSize(11).fontColor($r('app.color.muted')).width('100%')
                })
                Row({ space: 4 }) {
                  Button('编辑').fontSize(12).enabled(!this.busy && !!run.text)
                    .onClick(() => { this.editingId = run.id; this.editedText = run.text; })
                  if (index > 0) {
                    Button('上移').fontSize(12).enabled(!this.busy)
                      .onClick(() => this.onAction('reorder', run.id, this.runs[index - 1].id, ''))
                  }
                  if (index < this.runs.length - 1) {
                    Button('下移').fontSize(12).enabled(!this.busy)
                      .onClick(() => this.onAction('reorder', run.id, index + 2 < this.runs.length ? this.runs[index + 2].id : null, ''))
                  }
                  Button('立即引导').fontSize(12).enabled(!this.busy)
                    .onClick(() => this.onAction('promote', run.id, null, ''))
                  if (!this.active) {
                    Button('立即开始').fontSize(12).enabled(!this.busy)
                      .onClick(() => this.onAction('start', run.id, null, ''))
                  }
                  Button('移除').fontSize(12).enabled(!this.busy)
                    .onClick(() => AlertDialog.show({ title: '移除待发送消息？', message: '此操作会取消这条排队消息。',
                      primaryButton: { value: '取消', action: () => {} }, secondaryButton: { value: '移除',
                        action: () => this.onAction('cancel', run.id, null, '') } }))
                }.width('100%')
              }
            }.padding(12).width('100%').border({ width: 0.5, color: $r('app.color.border') }).borderRadius(12)
          }
        }, (run: QueuedRun) => run.id)
        if (!this.runs.length) { ListItem() { Text('没有排队消息').fontColor($r('app.color.muted')) } }
      }.layoutWeight(1).width('100%')
      if (this.status) { Text(this.status).fontSize(12).fontColor($r('app.color.muted')).width('100%') }
    }.padding(20).width('100%').height('100%').foregroundColor($r('app.color.ink'))
  }
}
