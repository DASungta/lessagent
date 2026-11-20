import { CodeToken, codeTokens, InlineSpan, MarkdownBlock, MarkdownListItem, markdownDocument,
  mathText } from '../protocol/Markdown';
import { parseMermaid, parseMermaidClass, parseMermaidSequence, parseMermaidState } from '../protocol/Mermaid';
import { MermaidView } from './MermaidView';
import { SequenceView } from './SequenceView';
import { ClassDiagramView } from './ClassDiagramView';
import { StateDiagramView } from './StateDiagramView';
import { FontSize, LineHeight, Radius, Space, Weight } from '../common/Theme';

@Component
export struct MarkdownView {
  @Prop markdown: string = '';
  @Prop selectable: boolean = true;
  onCopy: (value: string) => void = () => {};
  onOpenLink: (url: string) => void = () => {};
  onOpenImage: (path: string) => void = () => {};
  @State expanded: Record<string, boolean> = {};
  @State wrapCode: Record<string, boolean> = {};

  private headingSize(level: number): number {
    return level === 1 ? 24 : level === 2 ? 21 : level === 3 ? 19 : level === 4 ? 17 : 16;
  }

  private cellAlign(block: MarkdownBlock, index: number): TextAlign {
    return index < block.align.length && block.align[index] === 'right' ? TextAlign.End : TextAlign.Start;
  }

  private tokenColor(kind: string): ResourceColor {
    if (kind === 'keyword') return $r('app.color.primary');
    if (kind === 'string') return $r('app.color.diff_add_ink');
    if (kind === 'comment') return $r('app.color.muted');
    if (kind === 'number') return $r('app.color.diff_del_ink');
    return $r('app.color.ink');
  }

  @Builder
  inline(spans: InlineSpan[], size: number, lineHeight: number, color: ResourceColor,
    weight: FontWeight) {
    Text() {
      ForEach(spans, (span: InlineSpan) => {
        if (span.kind === 'strong') {
          Span(span.text).fontWeight(FontWeight.Bold)
        } else if (span.kind === 'em') {
          Span(span.text).fontStyle(FontStyle.Italic)
        } else if (span.kind === 'strike') {
          Span(span.text).decoration({ type: TextDecorationType.LineThrough, color: $r('app.color.muted') })
        } else if (span.kind === 'code') {
          Span(span.text).fontFamily('monospace').fontSize(size - 2).backgroundColor($r('app.color.group'))
        } else if (span.kind === 'link') {
          Span(span.text).fontColor($r('app.color.primary_text'))
            .decoration({ type: TextDecorationType.Underline, color: $r('app.color.primary_text') })
            .onClick(() => { if (span.href) this.onOpenLink(span.href); })
        } else if (span.kind === 'image') {
          Span('[图片] ' + span.text).fontColor($r('app.color.muted'))
            .onClick(() => { if (span.href) this.onOpenImage(span.href); })
        } else if (span.kind === 'math') {
          Span(mathText(span.text)).fontFamily('monospace').fontColor($r('app.color.ink'))
        } else {
          Span(span.text)
        }
      }, (span: InlineSpan, index: number) => index + ':' + span.kind + ':' + span.text)
    }.width('100%').fontSize(size).lineHeight(lineHeight + 'fp').fontColor(color).fontWeight(weight)
      .copyOption(this.selectable ? CopyOptions.InApp : CopyOptions.None)
  }

  @Builder
  listBlock(block: MarkdownBlock) {
    Column({ space: 4 }) {
      ForEach(block.items, (item: MarkdownListItem, index: number) => {
        Row({ space: 6 }) {
          Text(item.checked === undefined ? (item.ordered ? (block.start + index) + '.' : '•') :
            (item.checked ? '☑' : '☐'))
            .fontSize(15).fontColor(item.checked === undefined ? $r('app.color.muted') : $r('app.color.primary'))
            .width(28).textAlign(TextAlign.End)
          Column() {
            this.inline(item.spans, FontSize.body, 23, $r('app.color.ink'), FontWeight.Normal)
          }.layoutWeight(1)
        }.width('100%').padding({ left: Math.min(item.depth, 4) * 18 }).alignItems(VerticalAlign.Top)
      }, (item: MarkdownListItem, index: number) => index + ':' + item.text)
    }.width('100%')
  }

  @Builder
  tableBlock(block: MarkdownBlock) {
    Scroll() {
      Column() {
        Row() {
          ForEach(block.header, (cell: string, index: number) => {
            Text(cell).fontColor($r('app.color.ink')).fontSize(13).fontWeight(FontWeight.Medium).padding(8)
              .width(160).textAlign(this.cellAlign(block, index))
          }, (cell: string, index: number) => 'h' + index)
        }.backgroundColor($r('app.color.group'))
        ForEach(block.rows, (row: string[], rowIndex: number) => {
          Row() {
            ForEach(row, (cell: string, index: number) => {
              Text(cell).fontColor($r('app.color.ink')).fontSize(13).padding(8).width(160)
                .textAlign(this.cellAlign(block, index))
            }, (cell: string, index: number) => 'c' + rowIndex + '-' + index)
          }.border({ width: { top: 1 }, color: $r('app.color.border') })
        }, (row: string[], rowIndex: number) => 'r' + rowIndex)
      }.alignItems(HorizontalAlign.Start).border({ width: 1, color: $r('app.color.border') }).borderRadius(10)
    }.scrollable(ScrollDirection.Horizontal).align(Alignment.Start).width('100%')
  }

  @Builder
  codeBlock(block: MarkdownBlock, key: string) {
    Column({ space: Space.xxs }) {
      Row({ space: Space.xs }) {
        Text(block.language || '代码').fontSize(FontSize.caption).fontColor($r('app.color.muted'))
        Blank()
        Button(this.wrapCode[key] ? '不换行' : '换行').backgroundColor(Color.Transparent).fontColor($r('app.color.muted'))
          .fontSize(FontSize.caption).constraintSize({ minHeight: 36 }).padding({ left: Space.xs, right: Space.xs })
          .onClick(() => { this.wrapCode[key] = !this.wrapCode[key]; })
        Button('复制').backgroundColor(Color.Transparent).fontColor($r('app.color.muted'))
          .fontSize(FontSize.caption).constraintSize({ minHeight: 36 }).padding({ left: Space.xs, right: 0 })
          .onClick(() => this.onCopy(block.text))
      }.width('100%')
      if (this.wrapCode[key]) {
        Column({ space: 0 }) {
          ForEach(codeTokens(block.text, block.language), (tokens: CodeToken[], lineIndex: number) => {
            Text() {
              ForEach(tokens, (token: CodeToken, tokenIndex: number) => {
                Span(token.text).fontColor(this.tokenColor(token.kind))
              }, (token: CodeToken, tokenIndex: number) => tokenIndex + ':' + token.kind)
            }.fontFamily('monospace').fontSize(FontSize.mono).lineHeight(LineHeight.mono).width('100%')
              .copyOption(CopyOptions.InApp)
          }, (tokens: CodeToken[], lineIndex: number) => String(lineIndex))
        }.width('100%').alignItems(HorizontalAlign.Start)
      } else {
        Scroll() {
          Column({ space: 0 }) {
            ForEach(codeTokens(block.text, block.language), (tokens: CodeToken[], lineIndex: number) => {
              Text() {
                ForEach(tokens, (token: CodeToken, tokenIndex: number) => {
                  Span(token.text).fontColor(this.tokenColor(token.kind))
                }, (token: CodeToken, tokenIndex: number) => tokenIndex + ':' + token.kind)
              }.fontFamily('monospace').fontSize(FontSize.mono).lineHeight(LineHeight.mono).constraintSize({ minHeight: LineHeight.mono })
                .copyOption(CopyOptions.InApp)
            }, (tokens: CodeToken[], lineIndex: number) => String(lineIndex))
          }.alignItems(HorizontalAlign.Start)
        }.scrollable(ScrollDirection.Horizontal).align(Alignment.Start).width('100%')
      }
    }.width('100%').padding({ left: Space.sm, right: Space.sm, top: Space.xs, bottom: Space.sm })
      .backgroundColor($r('app.color.card')).borderRadius(Radius.tool).border({ width: 1, color: $r('app.color.border') })
  }

  @Builder
  mermaidBlock(block: MarkdownBlock) {
    Column({ space: Space.xxs }) {
      Row() {
        Text('mermaid').fontSize(FontSize.caption).fontColor($r('app.color.muted'))
        Blank()
        Button('复制').backgroundColor(Color.Transparent).fontColor($r('app.color.muted')).fontSize(FontSize.caption)
          .constraintSize({ minHeight: 36 }).padding({ left: Space.xs, right: 0 }).onClick(() => this.onCopy(block.text))
      }.width('100%')
      Scroll() {
        MermaidView({ source: block.text })
      }.scrollable(ScrollDirection.Horizontal).align(Alignment.Start).width('100%')
    }.width('100%').padding(Space.sm).backgroundColor($r('app.color.card')).borderRadius(Radius.tool)
      .border({ width: 1, color: $r('app.color.border') })
  }

  @Builder
  sequenceBlock(block: MarkdownBlock) {
    Column({ space: Space.xxs }) {
      Row() {
        Text('mermaid').fontSize(FontSize.caption).fontColor($r('app.color.muted'))
        Blank()
        Button('复制').backgroundColor(Color.Transparent).fontColor($r('app.color.muted')).fontSize(FontSize.caption)
          .constraintSize({ minHeight: 36 }).padding({ left: Space.xs, right: 0 }).onClick(() => this.onCopy(block.text))
      }.width('100%')
      Scroll() {
        SequenceView({ source: block.text })
      }.scrollable(ScrollDirection.Horizontal).align(Alignment.Start).width('100%')
    }.width('100%').padding(Space.sm).backgroundColor($r('app.color.card')).borderRadius(Radius.tool)
      .border({ width: 1, color: $r('app.color.border') })
  }

  @Builder
  classBlock(block: MarkdownBlock) {
    Column({ space: Space.xxs }) {
      Row() {
        Text('mermaid').fontSize(FontSize.caption).fontColor($r('app.color.muted'))
        Blank()
        Button('复制').backgroundColor(Color.Transparent).fontColor($r('app.color.muted')).fontSize(FontSize.caption)
          .constraintSize({ minHeight: 36 }).padding({ left: Space.xs, right: 0 }).onClick(() => this.onCopy(block.text))
      }.width('100%')
      Scroll() {
        ClassDiagramView({ source: block.text })
      }.scrollable(ScrollDirection.Horizontal).align(Alignment.Start).width('100%')
    }.width('100%').padding(Space.sm).backgroundColor($r('app.color.card')).borderRadius(Radius.tool)
      .border({ width: 1, color: $r('app.color.border') })
  }

  @Builder
  stateBlock(block: MarkdownBlock) {
    Column({ space: Space.xxs }) {
      Row() {
        Text('mermaid').fontSize(FontSize.caption).fontColor($r('app.color.muted'))
        Blank()
        Button('复制').backgroundColor(Color.Transparent).fontColor($r('app.color.muted')).fontSize(FontSize.caption)
          .constraintSize({ minHeight: 36 }).padding({ left: Space.xs, right: 0 }).onClick(() => this.onCopy(block.text))
      }.width('100%')
      Scroll() {
        StateDiagramView({ source: block.text })
      }.scrollable(ScrollDirection.Horizontal).align(Alignment.Start).width('100%')
    }.width('100%').padding(Space.sm).backgroundColor($r('app.color.card')).borderRadius(Radius.tool)
      .border({ width: 1, color: $r('app.color.border') })
  }

  @Builder
  detailsBlock(block: MarkdownBlock, key: string) {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        Image(this.expanded[key] ? $r('app.media.ui_up') : $r('app.media.ui_down')).width(16).height(16)
        Text(block.summary).fontSize(14).fontWeight(FontWeight.Medium).layoutWeight(1)
      }.width('100%').constraintSize({ minHeight: 44 })
        .accessibilityText(block.summary + (this.expanded[key] ? '，已展开' : '，已折叠'))
        .onClick(() => { this.expanded[key] = !this.expanded[key]; })
      if (this.expanded[key]) {
        MarkdownView({ markdown: block.body, selectable: this.selectable,
          onCopy: this.onCopy, onOpenLink: this.onOpenLink, onOpenImage: this.onOpenImage })
      }
    }.width('100%').padding(10).border({ width: 1, color: $r('app.color.border') }).borderRadius(10)
  }

  @Builder
  blockView(block: MarkdownBlock, index: number) {
    if (block.kind === 'heading') {
      this.inline(block.spans, this.headingSize(block.level), this.headingSize(block.level) * 1.35,
        $r('app.color.ink'), FontWeight.Medium)
    } else if (block.kind === 'paragraph') {
      this.inline(block.spans, FontSize.body, 23, $r('app.color.ink'), FontWeight.Normal)
    } else if (block.kind === 'quote') {
      Row({ space: 10 }) {
        Divider().vertical(true).height('100%').color($r('app.color.border'))
        Column() {
          this.inline(block.spans, FontSize.body, 22, $r('app.color.muted'), FontWeight.Normal)
        }.layoutWeight(1)
      }.width('100%').alignItems(VerticalAlign.Top)
    } else if (block.kind === 'list') {
      this.listBlock(block)
    } else if (block.kind === 'table') {
      this.tableBlock(block)
    } else if (block.kind === 'code') {
      if (block.language.toLowerCase() === 'mermaid' && parseMermaid(block.text)) {
        this.mermaidBlock(block)
      } else if (block.language.toLowerCase() === 'mermaid' && parseMermaidSequence(block.text)) {
        this.sequenceBlock(block)
      } else if (block.language.toLowerCase() === 'mermaid' && parseMermaidClass(block.text)) {
        this.classBlock(block)
      } else if (block.language.toLowerCase() === 'mermaid' && parseMermaidState(block.text)) {
        this.stateBlock(block)
      } else {
        this.codeBlock(block, String(index))
      }
    } else if (block.kind === 'details') {
      this.detailsBlock(block, String(index))
    } else if (block.kind === 'math') {
      Scroll() {
        Text(mathText(block.text)).fontFamily('monospace').fontSize(FontSize.body).padding(Space.sm)
          .copyOption(CopyOptions.InApp)
      }.scrollable(ScrollDirection.Horizontal).align(Alignment.Start).width('100%')
        .backgroundColor($r('app.color.card')).borderRadius(Radius.tool).border({ width: 1, color: $r('app.color.border') })
    } else if (block.kind === 'hr') {
      Divider().color($r('app.color.border')).width('100%')
    } else if (block.kind === 'image') {
      if (/^(https?:\/\/|data:image\/)/i.test(block.url) &&
        !/\.(mp4|webm|mov|m4v)(\?|$)/i.test(block.url)) {
        Image(block.url).width('100%').constraintSize({ maxHeight: 320 }).objectFit(ImageFit.Contain)
          .borderRadius(10).onClick(() => this.onOpenImage(block.url))
      } else if (/^https?:\/\/.+\.(mp4|webm|mov|m4v)(\?|$)/i.test(block.url)) {
        Video({ src: block.url }).width('100%').height(220).controls(true)
      } else {
        Row({ space: 8 }) {
          Text('图片').fontSize(12).fontColor($r('app.color.muted'))
          Text(block.alt || block.url).fontSize(13).fontColor($r('app.color.primary_text'))
            .layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.padding(10).width('100%').backgroundColor($r('app.color.group')).borderRadius(10)
          .onClick(() => this.onOpenImage(block.url))
      }
    }
  }

  build() {
    Column({ space: 10 }) {
      ForEach(markdownDocument(this.markdown), (block: MarkdownBlock, index: number) => {
        this.blockView(block, index)
      }, (block: MarkdownBlock, index: number) => index + ':' + block.kind + ':' + block.text.slice(0, 40))
    }.width('100%').alignItems(HorizontalAlign.Start).foregroundColor($r('app.color.ink'))
  }
}
