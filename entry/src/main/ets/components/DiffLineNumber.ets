@Component
export struct DiffLineNumber {
  @StorageProp('t3CodeFontSize') codeFontSize: number = 13;
  @Prop line: number = 0;
  @Prop lastLine: number = 0;
  @Prop active: boolean = false;

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Text(String(this.lastLine)).fontSize(Math.max(8, this.codeFontSize - 3)).fontFamily('monospace')
        .lineHeight((this.codeFontSize + 9) + 'fp').maxLines(1).opacity(0).accessibilityLevel('no')
      Text(this.line ? String(this.line) : '').fontSize(Math.max(8, this.codeFontSize - 3)).fontFamily('monospace')
        .lineHeight((this.codeFontSize + 9) + 'fp').maxLines(1)
        .fontColor(this.active ? $r('app.color.primary_text') : $r('app.color.muted'))
    }.padding({ right: 4 })
  }
}
