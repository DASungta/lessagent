import { MermaidDiagram, MermaidEdge, MermaidNode, parseMermaid } from '../protocol/Mermaid';

@Component
export struct MermaidView {
  @Prop source: string = '';
  @State diagram: MermaidDiagram | undefined = undefined;

  aboutToAppear(): void {
    this.diagram = parseMermaid(this.source);
  }

  private radius(node: MermaidNode): number {
    return node.shape === 'circle' ? node.height / 2 : node.shape === 'diamond' ? 6 : 10;
  }

  build() {
    Column() {
      if (this.diagram) {
        Stack({ alignContent: Alignment.TopStart }) {
          ForEach(this.diagram.edges, (edge: MermaidEdge, index: number) => {
            Line().startPoint([edge.x1, edge.y1]).endPoint([edge.x2, edge.y2])
              .stroke($r('app.color.border')).strokeWidth(1.5)
              .width(this.diagram ? this.diagram.width : 0)
              .height(this.diagram ? this.diagram.height : 0)
            Text(this.diagram && this.diagram.direction === 'LR' ? '▸' : '▾')
              .fontSize(12).fontColor($r('app.color.muted'))
              .position({ x: this.diagram && this.diagram.direction === 'LR' ? edge.x2 - 12 : edge.x2 - 6,
                y: this.diagram && this.diagram.direction === 'LR' ? edge.y2 - 8 : edge.y2 - 14 })
            if (edge.label) {
              Text(edge.label).fontSize(10).fontColor($r('app.color.muted'))
                .position({ x: (edge.x1 + edge.x2) / 2 - 20, y: (edge.y1 + edge.y2) / 2 - 8 })
            }
          }, (edge: MermaidEdge, index: number) => edge.from + '>' + edge.to + ':' + index)
          ForEach(this.diagram.nodes, (node: MermaidNode) => {
            Column() {
              Text(node.label).fontSize(12).fontColor($r('app.color.ink')).maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).textAlign(TextAlign.Center)
            }.width(node.width).height(node.height).padding(6)
              .justifyContent(FlexAlign.Center)
              .backgroundColor($r('app.color.surface'))
              .border({ width: 1, color: $r('app.color.border') })
              .borderRadius(this.radius(node))
              .position({ x: node.x, y: node.y })
          }, (node: MermaidNode) => node.id)
        }.width(this.diagram ? this.diagram.width : 0)
          .height(this.diagram ? this.diagram.height : 0)
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
