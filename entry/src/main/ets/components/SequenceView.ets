import { MermaidMessage, MermaidParticipant, MermaidSequence, parseMermaidSequence } from '../protocol/Mermaid';

@Component
export struct SequenceView {
  @Prop source: string = '';
  @State sequence: MermaidSequence | undefined = undefined;

  aboutToAppear(): void {
    this.sequence = parseMermaidSequence(this.source);
  }

  build() {
    Column() {
      if (this.sequence) {
        Stack({ alignContent: Alignment.TopStart }) {
          ForEach(this.sequence.participants, (participant: MermaidParticipant) => {
            Line().startPoint([participant.lifeline, 76])
              .endPoint([participant.lifeline, this.sequence ? this.sequence.height - 16 : 76])
              .stroke($r('app.color.border')).strokeWidth(1)
              .width(this.sequence ? this.sequence.width : 0)
              .height(this.sequence ? this.sequence.height : 0)
            Column() {
              Text(participant.label).fontSize(12).fontColor($r('app.color.ink')).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).textAlign(TextAlign.Center)
            }.width(participant.width).height(44).padding(6).justifyContent(FlexAlign.Center)
              .backgroundColor($r('app.color.surface'))
              .border({ width: 1, color: $r('app.color.border') }).borderRadius(8)
              .position({ x: participant.x, y: 20 })
          }, (participant: MermaidParticipant) => participant.id)
          ForEach(this.sequence.messages, (message: MermaidMessage, index: number) => {
            Line().startPoint([message.x1, message.y]).endPoint([message.x2, message.y])
              .stroke($r('app.color.muted')).strokeWidth(1.5)
              .width(this.sequence ? this.sequence.width : 0)
              .height(this.sequence ? this.sequence.height : 0)
            Text(message.x2 >= message.x1 ? '▸' : '◂').fontSize(12).fontColor($r('app.color.muted'))
              .position({ x: message.x2 >= message.x1 ? message.x2 - 10 : message.x2 - 2, y: message.y - 8 })
            Text(message.text).fontSize(10).fontColor($r('app.color.ink'))
              .constraintSize({ maxWidth: 220 }).maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .position({ x: Math.min(message.x1, message.x2) + 8, y: message.y - 26 })
          }, (message: MermaidMessage, index: number) => message.from + '>' + message.to + ':' + index)
        }.width(this.sequence ? this.sequence.width : 0)
          .height(this.sequence ? this.sequence.height : 0)
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
