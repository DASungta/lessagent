@Component
export struct CodeLine {
  @StorageProp('t3CodeFontSize') codeFontSize: number = 13;
  @StorageProp('t3CodeWordBreak') codeWordBreak: boolean = false;
  @Prop text: string = '';
  color: ResourceColor = $r('app.color.ink');

  build() {
    Column() {
      if (this.codeWordBreak) {
        Text(this.text || ' ').width('100%').textAlign(TextAlign.Start).wordBreak(WordBreak.BREAK_ALL)
          .fontSize(this.codeFontSize).lineHeight((this.codeFontSize + 9) + 'fp')
          .fontFamily('monospace').fontColor(this.color)
      } else {
        Scroll() {
          Text(this.text || ' ').maxLines(1).textAlign(TextAlign.Start)
            .fontSize(this.codeFontSize).lineHeight((this.codeFontSize + 9) + 'fp')
            .fontFamily('monospace').fontColor(this.color)
        }.width('100%').scrollable(ScrollDirection.Horizontal).align(Alignment.TopStart)
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
