import { SyntaxToken, SyntaxTokenKind, tokenizeCodeLine, WordDiffSegment } from '../protocol/FilePreview';

@Component
export struct CodeLine {
  @StorageProp('t3CodeFontSize') codeFontSize: number = 13;
  @StorageProp('t3CodeWordBreak') codeWordBreak: boolean = false;
  @StorageProp('t3SystemColorMode') systemColorMode: number = -1;
  @StorageProp('t3AppearanceMode') appearanceMode: string = '';
  @Prop text: string = '';
  @Prop language: string = '';
  @Prop wordSegments: WordDiffSegment[] = [];
  @Prop diffKind: string = '';
  color: ResourceColor = $r('app.color.ink');

  private isDark(): boolean {
    if (this.appearanceMode === 'dark') return true;
    if (this.appearanceMode === 'light') return false;
    return this.systemColorMode === 0;
  }

  private tokenColor(kind: SyntaxTokenKind): ResourceColor {
    if (kind === 'plain') return this.color;
    const dark = this.isDark();
    if (kind === 'keyword') return dark ? '#c792ea' : '#7c3aed';
    if (kind === 'string') return dark ? '#c3e88d' : '#15803d';
    if (kind === 'comment') return dark ? '#7a8499' : '#6b7280';
    if (kind === 'number') return dark ? '#f78c6c' : '#c2410c';
    if (kind === 'type') return dark ? '#82aaff' : '#0369a1';
    return this.color;
  }

  private wordHighlightColor(): ResourceColor {
    const dark = this.isDark();
    if (this.diffKind === 'add') return dark ? '#2d6a4f' : '#bbf7d0';
    if (this.diffKind === 'del') return dark ? '#7f1d1d' : '#fecaca';
    return dark ? '#334155' : '#e2e8f0';
  }

  @Builder
  richText(wrap: boolean) {
    if (this.wordSegments.length > 0) {
      Text() {
        ForEach(this.wordSegments, (seg: WordDiffSegment, idx: number) => {
          Span(seg.text)
            .fontColor(this.color)
            .fontWeight(seg.changed ? FontWeight.Medium : FontWeight.Normal)
            .textBackgroundStyle(seg.changed ? { color: this.wordHighlightColor(), radius: 2 } : {})
        }, (_seg: WordDiffSegment, idx: number) => String(idx))
      }
      .width(wrap ? '100%' : undefined)
      .maxLines(wrap ? undefined : 1)
      .wordBreak(wrap ? WordBreak.BREAK_ALL : WordBreak.NORMAL)
      .textAlign(TextAlign.Start)
      .fontSize(this.codeFontSize)
      .lineHeight((this.codeFontSize + 9) + 'fp')
      .fontFamily('monospace')
    } else if (this.language && this.text && this.text.length <= 600) {
      Text() {
        ForEach(tokenizeCodeLine(this.text, this.language), (tok: SyntaxToken, idx: number) => {
          Span(tok.text).fontColor(this.tokenColor(tok.kind))
        }, (_tok: SyntaxToken, idx: number) => String(idx))
      }
      .width(wrap ? '100%' : undefined)
      .maxLines(wrap ? undefined : 1)
      .wordBreak(wrap ? WordBreak.BREAK_ALL : WordBreak.NORMAL)
      .textAlign(TextAlign.Start)
      .fontSize(this.codeFontSize)
      .lineHeight((this.codeFontSize + 9) + 'fp')
      .fontFamily('monospace')
    } else {
      Text(this.text || ' ')
        .width(wrap ? '100%' : undefined)
        .maxLines(wrap ? undefined : 1)
        .wordBreak(wrap ? WordBreak.BREAK_ALL : WordBreak.NORMAL)
        .textAlign(TextAlign.Start)
        .fontSize(this.codeFontSize)
        .lineHeight((this.codeFontSize + 9) + 'fp')
        .fontFamily('monospace')
        .fontColor(this.color)
    }
  }

  build() {
    Column() {
      if (this.codeWordBreak) {
        this.richText(true)
      } else {
        Scroll() {
          this.richText(false)
        }.width('100%').scrollable(ScrollDirection.Horizontal).align(Alignment.TopStart)
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
