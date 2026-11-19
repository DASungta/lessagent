import { MermaidClass, MermaidClassDiagram, MermaidRelation, parseMermaidClass } from '../protocol/Mermaid';

@Component
export struct ClassDiagramView {
  @Prop source: string = '';
  @State diagram: MermaidClassDiagram | undefined = undefined;

  aboutToAppear(): void {
    this.diagram = parseMermaidClass(this.source);
  }

  build() {
    Column() {
      if (this.diagram) {
        Stack({ alignContent: Alignment.TopStart }) {
          ForEach(this.diagram.relations, (relation: MermaidRelation, index: number) => {
            Line().startPoint([relation.x1, relation.y1]).endPoint([relation.x2, relation.y2])
              .stroke($r('app.color.border')).strokeWidth(1.5)
              .width(this.diagram ? this.diagram.width : 0)
              .height(this.diagram ? this.diagram.height : 0)
            Text('▾').fontSize(12).fontColor($r('app.color.muted'))
              .position({ x: relation.x2 - 6, y: relation.y2 - 14 })
            if (relation.label) {
              Text(relation.label).fontSize(10).fontColor($r('app.color.muted'))
                .position({ x: (relation.x1 + relation.x2) / 2 + 6, y: (relation.y1 + relation.y2) / 2 })
            }
          }, (relation: MermaidRelation, index: number) => relation.from + '>' + relation.to + ':' + index)
          ForEach(this.diagram.classes, (item: MermaidClass) => {
            Column() {
              Text(item.label).fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.ink'))
                .width('100%').textAlign(TextAlign.Center)
              Divider().color($r('app.color.border'))
              Column({ space: 1 }) {
                ForEach(item.members.slice(0, 6), (member: string) => {
                  Text(member).fontSize(10).fontFamily('monospace').fontColor($r('app.color.muted'))
                    .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }, (member: string, index: number) => index + ':' + member)
              }.width('100%').alignItems(HorizontalAlign.Start)
            }.width(item.width).height(item.height).padding(6)
              .justifyContent(FlexAlign.Start)
              .backgroundColor($r('app.color.surface'))
              .border({ width: 1, color: $r('app.color.border') }).borderRadius(8)
              .position({ x: item.x, y: item.y })
          }, (item: MermaidClass) => item.id)
        }.width(this.diagram ? this.diagram.width : 0)
          .height(this.diagram ? this.diagram.height : 0)
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
