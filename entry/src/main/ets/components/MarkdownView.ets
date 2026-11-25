import {
  classifyMarkdownMediaSource,
  CodeToken,
  codeTokens,
  InlineSpan,
  inlineSpans,
  MarkdownBlock,
  MarkdownListItem,
  markdownDocument,
  mathText,
  ResolvedMarkdownMedia
} from '../protocol/Markdown';
import { canSaveToPhotoGallery, mediaCopyLabel, mediaCopyValue, mediaFileName } from '../protocol/MediaTransfer';
import { parseMermaid, parseMermaidClass, parseMermaidSequence, parseMermaidState } from '../protocol/Mermaid';
import { MermaidView } from './MermaidView';
import { SequenceView } from './SequenceView';
import { ClassDiagramView } from './ClassDiagramView';
import { StateDiagramView } from './StateDiagramView';
import { FontSize, LineHeight, Radius, Space } from '../common/Theme';

@Component
export struct MarkdownMediaBlock {
  @Prop @Watch('onSourceChange') source: string = '';
  @Prop alt: string = '';
  @Prop initialKind: string = '';
  @Prop @Watch('onSourceChange') scopeKey: string = '';
  @Prop @Watch('onSourceChange') mediaReady: boolean = true;
  resolveMedia: ((source: string, refresh: boolean) => Promise<ResolvedMarkdownMedia>) | undefined = undefined;
  downloadLocalMedia: ((url: string, kind: string, displayPath: string) => Promise<string>) | undefined = undefined;
  onOpenImage: (source: string) => void = () => {};
  onCopy: ((value: string) => void) | undefined = undefined;
  onShareMedia: ((source: string, alt: string, kind: string, resolvedUrl: string, displayPath: string) => void) | undefined = undefined;
  onSaveMediaToGallery: ((source: string, alt: string, kind: string, resolvedUrl: string, displayPath: string) => void) | undefined = undefined;
  onSaveMediaToFile: ((source: string, alt: string, kind: string, resolvedUrl: string, displayPath: string) => void) | undefined = undefined;
  @State resolvedUrl: string = '';
  @State resolvedKind: string = 'image';
  @State loading: boolean = false;
  @State loadFailed: boolean = false;
  @State errorText: string = '';
  @State mediaAspectRatio: number = 0;
  private loadSeq: number = 0;
  private retriedAfterError: boolean = false;
  private fallbackTried: boolean = false;
  private displayPath: string = '';

  aboutToAppear(): void {
    this.startResolve();
  }

  aboutToDisappear(): void {
    this.loadSeq += 1;
  }

  onSourceChange(): void {
    this.retriedAfterError = false;
    this.fallbackTried = false;
    this.startResolve();
  }

  private isAttachmentSource(): boolean {
    return this.source.startsWith('t3-attachment://');
  }

  private isEnvironmentSource(): boolean {
    if (this.isAttachmentSource()) return true;
    const classified = classifyMarkdownMediaSource(this.source, '/');
    return classified.access === 'environment';
  }

  private mediaTypeLabel(): string {
    return this.resolvedKind === 'video' ? '视频' : '图片';
  }

  private clampRatio(width: number, height: number): number {
    if (width <= 0 || height <= 0) return 0;
    return Math.min(Math.max(width / height, 0.25), 4);
  }

  private startResolve(): void {
    if (this.isAttachmentSource()) {
      this.resolvedKind = this.initialKind === 'video' ? 'video' : 'image';
      if (this.resolveMedia) {
        if (!this.mediaReady) {
          this.loadSeq += 1;
          this.loading = !this.resolvedUrl;
          this.loadFailed = false;
          this.errorText = '';
          return;
        }
        void this.load(false);
        return;
      }
      this.loadSeq += 1;
      this.resolvedUrl = '';
      this.loading = false;
      this.loadFailed = false;
      this.errorText = '';
      this.mediaAspectRatio = 0;
      return;
    }
    const classified = classifyMarkdownMediaSource(this.source, '/');
    const inferredKind = this.initialKind === 'video' ? 'video' : (classified.kind || 'image');
    if (classified.access === 'direct') {
      this.loadSeq += 1;
      this.resolvedUrl = classified.uri;
      this.resolvedKind = inferredKind;
      this.displayPath = classified.displayPath;
      this.loading = false;
      this.loadFailed = false;
      this.errorText = '';
      this.mediaAspectRatio = 0;
      return;
    }
    if (classified.access === 'environment' && this.resolveMedia) {
      this.resolvedKind = inferredKind;
      if (!this.mediaReady) {
        this.loadSeq += 1;
        this.loading = !this.resolvedUrl;
        this.loadFailed = false;
        this.errorText = '';
        return;
      }
      void this.load(false);
      return;
    }
    this.loadSeq += 1;
    this.resolvedUrl = '';
    this.resolvedKind = inferredKind;
    this.displayPath = '';
    this.loading = false;
    this.loadFailed = false;
    this.errorText = '';
    this.mediaAspectRatio = 0;
  }

  private async load(refresh: boolean): Promise<void> {
    if (!this.resolveMedia) return;
    const seq = ++this.loadSeq;
    this.loading = true;
    this.loadFailed = false;
    this.errorText = '';
    if (refresh) this.resolvedUrl = '';
    try {
      const resolved = await this.resolveMedia(this.source, refresh);
      if (seq !== this.loadSeq) return;
      this.resolvedUrl = resolved.url;
      this.resolvedKind = resolved.kind || this.resolvedKind || 'image';
      this.displayPath = resolved.displayPath || this.alt || this.source;
      this.mediaAspectRatio = this.clampRatio(resolved.width, resolved.height);
      this.loading = false;
      this.loadFailed = !resolved.url;
      this.errorText = resolved.url ? '' : (this.mediaTypeLabel() + '链接无效');
    } catch (error) {
      if (seq !== this.loadSeq) return;
      this.loading = false;
      this.resolvedUrl = '';
      this.loadFailed = true;
      this.errorText = (error as Error).message || (this.mediaTypeLabel() + '加载失败');
    }
  }

  private async tryLocalFallback(remoteUrl: string): Promise<void> {
    if (!this.downloadLocalMedia) return;
    const seq = ++this.loadSeq;
    this.loading = true;
    this.loadFailed = false;
    this.errorText = '';
    this.resolvedUrl = '';
    try {
      const localUri = await this.downloadLocalMedia(remoteUrl, this.resolvedKind, this.displayPath || this.alt || this.source);
      if (seq !== this.loadSeq) return;
      if (localUri) {
        this.resolvedUrl = localUri;
        this.loading = false;
        this.loadFailed = false;
        this.errorText = '';
        return;
      }
      throw new Error(this.mediaTypeLabel() + '本地缓存失败');
    } catch (error) {
      if (seq !== this.loadSeq) return;
      this.loading = false;
      this.resolvedUrl = '';
      this.loadFailed = true;
      this.errorText = (error as Error).message || (this.mediaTypeLabel() + '无法加载，点按重试');
    }
  }

  private handleMediaError(): void {
    const failedUrl = this.resolvedUrl;
    if (!this.retriedAfterError && this.resolveMedia && this.isEnvironmentSource()) {
      this.retriedAfterError = true;
      void this.load(true);
      return;
    }
    if (!this.fallbackTried && this.downloadLocalMedia && /^https?:\/\//i.test(failedUrl)) {
      this.fallbackTried = true;
      void this.tryLocalFallback(failedUrl);
      return;
    }
    this.resolvedUrl = '';
    this.loading = false;
    this.loadFailed = true;
    this.errorText = this.mediaTypeLabel() + '无法加载，点按重试';
  }

  private effectiveDisplayPath(): string {
    if (this.displayPath) return this.displayPath;
    if (this.isAttachmentSource()) return this.alt;
    return this.source;
  }

  private effectiveFileName(): string {
    return mediaFileName(this.effectiveDisplayPath(), this.alt, this.resolvedUrl, '', this.resolvedKind);
  }

  private canSaveGallery(): boolean {
    return canSaveToPhotoGallery(this.effectiveFileName(), '', this.resolvedKind);
  }

  private copyValue(): string {
    return mediaCopyValue(this.effectiveDisplayPath(), this.resolvedUrl);
  }

  private copyLabel(): string {
    return mediaCopyLabel(this.effectiveDisplayPath(), this.resolvedUrl);
  }

  @Builder
  mediaContextMenu() {
    Menu() {
      MenuItem({ content: this.resolvedKind === 'video' ? '全屏播放' : '全屏预览' })
        .onClick(() => { this.onOpenImage(this.source); })
      if (this.onSaveMediaToGallery && this.canSaveGallery()) {
        MenuItem({ content: '保存到相册' })
          .onClick(() => {
            this.onSaveMediaToGallery!(this.source, this.alt, this.resolvedKind, this.resolvedUrl, this.effectiveDisplayPath());
          })
      }
      if (this.onSaveMediaToFile) {
        MenuItem({ content: '保存到文件' })
          .onClick(() => {
            this.onSaveMediaToFile!(this.source, this.alt, this.resolvedKind, this.resolvedUrl, this.effectiveDisplayPath());
          })
      }
      if (this.onShareMedia) {
        MenuItem({ content: '分享' })
          .onClick(() => {
            this.onShareMedia!(this.source, this.alt, this.resolvedKind, this.resolvedUrl, this.effectiveDisplayPath());
          })
      }
      if (this.onCopy && this.copyValue()) {
        MenuItem({ content: this.copyLabel() })
          .onClick(() => {
            const value = this.copyValue();
            if (value) this.onCopy!(value);
          })
      }
    }
  }

  build() {
    if (this.resolvedUrl && this.resolvedKind === 'video') {
      Column({ space: 0 }) {
        Video({ src: this.resolvedUrl })
          .width('100%')
          .height(220)
          .objectFit(ImageFit.Contain)
          .controls(true)
          .backgroundColor(Color.Black)
          .onError(() => { this.handleMediaError(); })
        Row({ space: 10 }) {
          Text(this.alt || '视频')
            .fontSize(12)
            .fontColor($r('app.color.muted'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .onClick(() => this.onOpenImage(this.source))
          if (this.onSaveMediaToGallery || this.onSaveMediaToFile) {
            Text('保存')
              .fontSize(12)
              .fontColor($r('app.color.primary_text'))
              .padding({ left: 4, right: 4, top: 2, bottom: 2 })
              .onClick(() => {
                if (this.onSaveMediaToGallery && this.canSaveGallery()) {
                  this.onSaveMediaToGallery(this.source, this.alt, this.resolvedKind, this.resolvedUrl, this.effectiveDisplayPath());
                } else if (this.onSaveMediaToFile) {
                  this.onSaveMediaToFile(this.source, this.alt, this.resolvedKind, this.resolvedUrl, this.effectiveDisplayPath());
                }
              })
          }
          if (this.onShareMedia) {
            Text('分享')
              .fontSize(12)
              .fontColor($r('app.color.primary_text'))
              .padding({ left: 4, right: 4, top: 2, bottom: 2 })
              .onClick(() => {
                this.onShareMedia!(this.source, this.alt, this.resolvedKind, this.resolvedUrl, this.effectiveDisplayPath());
              })
          }
          Text('全屏')
            .fontSize(12)
            .fontColor($r('app.color.primary_text'))
            .padding({ left: 4, right: 2, top: 2, bottom: 2 })
            .onClick(() => this.onOpenImage(this.source))
        }
        .width('100%')
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.card'))
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .borderRadius(10)
      .border({ width: 1, color: $r('app.color.border') })
      .clip(true)
      .bindContextMenu(this.mediaContextMenu(), ResponseType.LongPress)
    } else if (this.resolvedUrl) {
      Column() {
        if (this.mediaAspectRatio > 0) {
          Image(this.resolvedUrl)
            .width('100%')
            .aspectRatio(this.mediaAspectRatio)
            .constraintSize({ maxHeight: 360 })
            .objectFit(ImageFit.Contain)
            .draggable(false)
            .accessibilityText(this.alt || '图片')
            .onError(() => { this.handleMediaError(); })
        } else {
          Image(this.resolvedUrl)
            .width('100%')
            .constraintSize({ minHeight: 120, maxHeight: 360 })
            .objectFit(ImageFit.Contain)
            .draggable(false)
            .accessibilityText(this.alt || '图片')
            .onComplete((event) => {
              if (event && event.width > 0 && event.height > 0 && this.mediaAspectRatio <= 0) {
                this.mediaAspectRatio = this.clampRatio(event.width, event.height);
              }
            })
            .onError(() => { this.handleMediaError(); })
        }
      }
      .width('100%')
      .backgroundColor($r('app.color.card'))
      .borderRadius(10)
      .border({ width: 1, color: $r('app.color.border') })
      .clip(true)
      .onClick(() => this.onOpenImage(this.source))
      .bindContextMenu(this.mediaContextMenu(), ResponseType.LongPress)
    } else if (this.loading) {
      Row({ space: 8 }) {
        LoadingProgress().width(16).height(16).color($r('app.color.muted'))
        Text(this.alt ? '正在加载' + this.mediaTypeLabel() + '：' + this.alt : '正在加载' + this.mediaTypeLabel() + '…')
          .fontSize(13)
          .fontColor($r('app.color.muted'))
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .padding(10)
      .width('100%')
      .backgroundColor($r('app.color.group'))
      .borderRadius(10)
      .alignItems(VerticalAlign.Center)
    } else if (this.loadFailed) {
      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text(this.alt || this.source)
            .fontSize(13)
            .fontColor($r('app.color.primary_text'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.errorText) {
            Text(this.errorText)
              .fontSize(12)
              .fontColor($r('app.color.muted'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if ((this.resolveMedia && this.isEnvironmentSource()) || this.downloadLocalMedia) {
          Button('重试', { type: ButtonType.Normal })
            .fontSize(12)
            .fontColor($r('app.color.primary_text'))
            .backgroundColor($r('app.color.card'))
            .borderRadius(8)
            .constraintSize({ minHeight: 32 })
            .padding({ left: 10, right: 10 })
            .onClick(() => {
              this.retriedAfterError = false;
              this.fallbackTried = false;
              if (this.resolveMedia && this.isEnvironmentSource()) {
                void this.load(true);
              } else {
                this.startResolve();
              }
            })
        }
      }
      .padding(10)
      .width('100%')
      .backgroundColor($r('app.color.group'))
      .borderRadius(10)
      .alignItems(VerticalAlign.Center)
      .onClick(() => this.onOpenImage(this.source))
    } else {
      Row({ space: 8 }) {
        Text(this.mediaTypeLabel()).fontSize(12).fontColor($r('app.color.muted'))
        Text(this.alt || this.source).fontSize(13).fontColor($r('app.color.primary_text'))
          .layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.padding(10).width('100%').backgroundColor($r('app.color.group')).borderRadius(10)
        .onClick(() => this.onOpenImage(this.source))
    }
  }
}

@Component
export struct MarkdownView {
  @Prop markdown: string = '';
  @Prop selectable: boolean = true;
  @Prop compact: boolean = false;
  @Prop mediaScopeKey: string = '';
  @Prop mediaReady: boolean = true;
  onCopy: (value: string) => void = () => {};
  onOpenLink: (url: string) => void = () => {};
  onOpenImage: (path: string) => void = () => {};
  onShareMedia: ((source: string, alt: string, kind: string, resolvedUrl: string, displayPath: string) => void) | undefined = undefined;
  onSaveMediaToGallery: ((source: string, alt: string, kind: string, resolvedUrl: string, displayPath: string) => void) | undefined = undefined;
  onSaveMediaToFile: ((source: string, alt: string, kind: string, resolvedUrl: string, displayPath: string) => void) | undefined = undefined;
  resolveMedia: ((source: string, refresh: boolean) => Promise<ResolvedMarkdownMedia>) | undefined = undefined;
  downloadLocalMedia: ((url: string, kind: string, displayPath: string) => Promise<string>) | undefined = undefined;
  @State expanded: Record<string, boolean> = {};
  @State wrapCode: Record<string, boolean> = {};

  private bodySize(): number {
    return this.compact ? FontSize.callout : FontSize.body;
  }

  private bodyLineHeight(): number {
    return this.compact ? 20 : 23;
  }

  private bodyColor(): ResourceColor {
    return this.compact ? $r('app.color.muted') : $r('app.color.ink');
  }

  private headingSize(level: number): number {
    if (this.compact) return level <= 2 ? 15 : 14;
    return level === 1 ? 24 : level === 2 ? 21 : level === 3 ? 19 : level === 4 ? 17 : 16;
  }

  private cellAlign(block: MarkdownBlock, index: number): TextAlign {
    return index < block.align.length && block.align[index] === 'right' ? TextAlign.End : TextAlign.Start;
  }

  private tokenColor(kind: string): ResourceColor {
    if (kind === 'keyword') return $r('app.color.primary_text');
    if (kind === 'string') return $r('app.color.diff_add_ink');
    if (kind === 'comment') return $r('app.color.muted');
    if (kind === 'number') return $r('app.color.diff_del_ink');
    return $r('app.color.ink');
  }

  private imageSpans(spans: InlineSpan[]): InlineSpan[] {
    return spans.filter((span: InlineSpan) => span.kind === 'image' && !!span.href);
  }

  private hasNonImageText(spans: InlineSpan[]): boolean {
    return spans.some((span: InlineSpan) => span.kind !== 'image' && span.text.trim().length > 0);
  }

  @Builder
  inline(spans: InlineSpan[], size: number, lineHeight: number, color: ResourceColor,
    weight: FontWeight) {
    if (this.hasNonImageText(spans) || this.imageSpans(spans).length === 0) {
      Text() {
        ForEach(spans, (span: InlineSpan) => {
          if (span.kind === 'strong') {
            Span(span.text).fontWeight(FontWeight.Bold)
          } else if (span.kind === 'em') {
            Span(span.text).fontStyle(FontStyle.Italic)
          } else if (span.kind === 'strike') {
            Span(span.text).decoration({ type: TextDecorationType.LineThrough, color: $r('app.color.muted') })
          } else if (span.kind === 'code') {
            Span(span.text).fontFamily('monospace').fontSize(size - 2)
              .fontWeight(span.bold ? FontWeight.Bold : weight).backgroundColor($r('app.color.group'))
          } else if (span.kind === 'link') {
            if (span.href && span.href.startsWith('t3-context://')) {
              Span(span.text).fontColor($r('app.color.primary_text')).fontWeight(FontWeight.Medium)
                .onClick(() => { if (span.href) this.onOpenLink(span.href); })
            } else {
              Span(span.text).fontColor($r('app.color.primary_text'))
                .decoration({ type: TextDecorationType.Underline, color: $r('app.color.primary_text') })
                .onClick(() => { if (span.href) this.onOpenLink(span.href); })
            }
          } else if (span.kind === 'image') {
            Span((classifyMarkdownMediaSource(span.href || '', '/').kind === 'video' ? '[视频] ' : '[图片] ') + (span.text || '媒体'))
              .fontColor($r('app.color.muted'))
              .onClick(() => { if (span.href) this.onOpenImage(span.href); })
          } else if (span.kind === 'math') {
            Span(mathText(span.text)).fontFamily('monospace').fontColor($r('app.color.ink'))
          } else {
            Span(span.text)
          }
        }, (span: InlineSpan, index: number) => index + ':' + span.kind + ':' + span.text + ':' + (span.href || ''))
      }.width('100%').fontSize(size).lineHeight(lineHeight + 'fp').fontColor(color).fontWeight(weight)
        .copyOption(this.selectable ? CopyOptions.InApp : CopyOptions.None)
    }
    if (this.imageSpans(spans).length > 0) {
      Column({ space: 6 }) {
        ForEach(this.imageSpans(spans), (span: InlineSpan, index: number) => {
          MarkdownMediaBlock({
            source: span.href || '',
            alt: span.text,
            scopeKey: this.mediaScopeKey,
            mediaReady: this.mediaReady,
            resolveMedia: this.resolveMedia,
            downloadLocalMedia: this.downloadLocalMedia,
            onOpenImage: this.onOpenImage,
            onCopy: this.onCopy,
            onShareMedia: this.onShareMedia,
            onSaveMediaToGallery: this.onSaveMediaToGallery,
            onSaveMediaToFile: this.onSaveMediaToFile
          })
        }, (span: InlineSpan, index: number) => index + ':' + (span.href || '') + ':' + span.text)
      }.width('100%').margin({ top: this.hasNonImageText(spans) ? 6 : 0 })
    }
  }

  @Builder
  listBlock(block: MarkdownBlock) {
    Column({ space: this.compact ? 3 : 4 }) {
      ForEach(block.items, (item: MarkdownListItem, index: number) => {
        Row({ space: 6 }) {
          Text(item.checked === undefined
            ? (item.displayMarker || (item.ordered ? item.marker : '•'))
            : (item.checked ? '☑' : '☐'))
            .fontSize(this.bodySize())
            .lineHeight(this.bodyLineHeight() + 'fp')
            .fontColor(item.checked === undefined ? $r('app.color.muted') : $r('app.color.primary_text'))
            .constraintSize({ minWidth: this.compact ? 22 : 28 })
            .maxLines(1)
            .flexShrink(0)
            .textAlign(TextAlign.End)
          Column() {
            this.inline(item.spans, this.bodySize(), this.bodyLineHeight(), this.bodyColor(), FontWeight.Normal)
          }.layoutWeight(1)
        }.width('100%').padding({ left: Math.min(item.depth, 4) * (this.compact ? 12 : 18) }).alignItems(VerticalAlign.Top)
      }, (item: MarkdownListItem, index: number) =>
        index + ':' + item.depth + ':' + item.displayMarker + ':' + String(item.checked) + ':' + item.text)
    }.width('100%')
  }

  @Builder
  tableBlock(block: MarkdownBlock) {
    Scroll() {
      Column() {
        Row() {
          ForEach(block.header, (cell: string, index: number) => {
            Column() {
              this.inline(inlineSpans(cell), 13, 19, $r('app.color.ink'), FontWeight.Medium)
            }.width(136).padding(8).alignItems(this.cellAlign(block, index) === TextAlign.End ? HorizontalAlign.End : HorizontalAlign.Start)
          }, (cell: string, index: number) => 'h' + index)
        }.backgroundColor($r('app.color.group'))
        ForEach(block.rows, (row: string[], rowIndex: number) => {
          Row() {
            ForEach(row, (cell: string, index: number) => {
              Column() {
                this.inline(inlineSpans(cell), 13, 19, $r('app.color.ink'), FontWeight.Normal)
              }.width(136).padding(8).alignItems(this.cellAlign(block, index) === TextAlign.End ? HorizontalAlign.End : HorizontalAlign.Start)
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
        MarkdownView({
          markdown: block.body,
          selectable: this.selectable,
          compact: this.compact,
          mediaScopeKey: this.mediaScopeKey,
          mediaReady: this.mediaReady,
          onCopy: this.onCopy,
          onOpenLink: this.onOpenLink,
          onOpenImage: this.onOpenImage,
          onShareMedia: this.onShareMedia,
          onSaveMediaToGallery: this.onSaveMediaToGallery,
          onSaveMediaToFile: this.onSaveMediaToFile,
          resolveMedia: this.resolveMedia,
          downloadLocalMedia: this.downloadLocalMedia
        })
      }
    }.width('100%').padding(10).border({ width: 1, color: $r('app.color.border') }).borderRadius(10)
  }

  @Builder
  blockView(block: MarkdownBlock, index: number) {
    if (block.kind === 'heading') {
      this.inline(block.spans, this.headingSize(block.level), Math.round(this.headingSize(block.level) * 1.35),
        this.bodyColor(), FontWeight.Medium)
    } else if (block.kind === 'paragraph') {
      this.inline(block.spans, this.bodySize(), this.bodyLineHeight(), this.bodyColor(), FontWeight.Normal)
    } else if (block.kind === 'quote') {
      Column() {
        this.inline(block.spans, this.bodySize(), this.bodyLineHeight(), $r('app.color.muted'), FontWeight.Normal)
      }.width('100%').padding({ left: 12, top: 2, bottom: 2 })
        .border({ width: { left: 3 }, color: $r('app.color.border') })
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
      MarkdownMediaBlock({
        source: block.url,
        alt: block.alt,
        scopeKey: this.mediaScopeKey,
        mediaReady: this.mediaReady,
        resolveMedia: this.resolveMedia,
        downloadLocalMedia: this.downloadLocalMedia,
        onOpenImage: this.onOpenImage,
        onCopy: this.onCopy,
        onShareMedia: this.onShareMedia,
        onSaveMediaToGallery: this.onSaveMediaToGallery,
        onSaveMediaToFile: this.onSaveMediaToFile
      })
    }
  }

  private blockKey(block: MarkdownBlock, index: number): string {
    if (block.kind === 'image') return index + ':image:' + block.url + ':' + block.alt;
    if (block.kind === 'list') {
      const last = block.items.length > 0 ? block.items[block.items.length - 1] : undefined;
      return index + ':list:' + block.items.length + ':' + block.text.length + ':' +
        block.text.slice(0, 24) + ':' + (last ? last.displayMarker + ':' + last.text.slice(-24) : '');
    }
    if (block.kind === 'table') {
      return index + ':table:' + block.header.join('|').slice(0, 24) + ':' + block.rows.length + ':' +
        (block.rows.length > 0 ? block.rows[block.rows.length - 1].join('|').slice(-24) : '');
    }
    return index + ':' + block.kind + ':' + block.text.length + ':' + block.text.slice(0, 40) + ':' + block.text.slice(-24);
  }

  build() {
    Column({ space: this.compact ? 6 : 10 }) {
      ForEach(markdownDocument(this.markdown), (block: MarkdownBlock, index: number) => {
        this.blockView(block, index)
      }, (block: MarkdownBlock, index: number) => this.blockKey(block, index))
    }.width('100%').alignItems(HorizontalAlign.Start).foregroundColor($r('app.color.ink'))
  }
}
