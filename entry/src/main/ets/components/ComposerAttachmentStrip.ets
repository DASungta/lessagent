import { FontSize, LineHeight, Radius, Space, Weight } from '../common/Theme';
import {
  composerAttachmentExtensionBadge,
  composerAttachmentKind,
  ComposerAttachmentKind,
  composerContextChipLabel,
  formatAttachmentSize
} from '../protocol/Composer';
import { ComposerContextRecord, DraftAttachment } from '../protocol/R4';

const TILE_SIZE = 68;
const FILE_CARD_WIDTH = 156;
const TILE_RADIUS = 12;

@Component
struct ComposerAttachmentTile {
  @Prop item: DraftAttachment = { type: 'file', id: '', name: '', mimeType: '', sizeBytes: 0 };
  @Prop @Watch('onSourceChange') localUri: string = '';
  @Prop @Watch('onSourceChange') scopeKey: string = '';
  @Prop @Watch('onSourceChange') mediaReady: boolean = true;
  lookupLocalPreview: ((item: DraftAttachment) => string) | undefined = undefined;
  resolvePreview: ((item: DraftAttachment) => Promise<string>) | undefined = undefined;
  downloadLocalPreview: ((url: string, item: DraftAttachment) => Promise<string>) | undefined = undefined;
  onOpen: (item: DraftAttachment) => void = () => {};
  onRemove: (id: string) => void = () => {};

  @State private resolvedUri: string = '';
  @State private loading: boolean = false;
  @State private failed: boolean = false;
  private loadSeq: number = 0;
  private fallbackTried: boolean = false;

  aboutToAppear(): void {
    this.startResolve();
  }

  aboutToDisappear(): void {
    this.loadSeq += 1;
  }

  private kind(): ComposerAttachmentKind {
    return composerAttachmentKind(this.item.type, this.item.name, this.item.mimeType);
  }

  onSourceChange(): void {
    this.fallbackTried = false;
    this.startResolve();
  }

  private startResolve(): void {
    if (this.kind() !== 'image') {
      this.loadSeq += 1;
      this.resolvedUri = '';
      this.loading = false;
      this.failed = false;
      return;
    }
    const immediate = this.localUri || (this.lookupLocalPreview ? this.lookupLocalPreview(this.item) : '');
    if (immediate) {
      this.loadSeq += 1;
      this.resolvedUri = immediate;
      this.loading = false;
      this.failed = false;
      return;
    }
    if (!this.resolvePreview) {
      this.loadSeq += 1;
      this.resolvedUri = '';
      this.loading = false;
      this.failed = true;
      return;
    }
    if (!this.mediaReady) {
      this.loadSeq += 1;
      this.loading = !this.resolvedUri;
      this.failed = false;
      return;
    }
    void this.loadRemote();
  }

  private async loadRemote(): Promise<void> {
    if (!this.resolvePreview) return;
    const seq = ++this.loadSeq;
    this.loading = true;
    this.failed = false;
    try {
      const url = await this.resolvePreview(this.item);
      if (seq !== this.loadSeq) return;
      this.resolvedUri = url;
      this.loading = false;
      this.failed = !url;
    } catch (_) {
      if (seq !== this.loadSeq) return;
      this.resolvedUri = '';
      this.loading = false;
      this.failed = true;
    }
  }

  private async tryLocalDownload(remoteUrl: string): Promise<void> {
    if (!this.downloadLocalPreview) {
      this.resolvedUri = '';
      this.loading = false;
      this.failed = true;
      return;
    }
    const seq = ++this.loadSeq;
    this.loading = true;
    this.failed = false;
    try {
      const localUri = await this.downloadLocalPreview(remoteUrl, this.item);
      if (seq !== this.loadSeq) return;
      if (localUri) {
        this.resolvedUri = localUri;
        this.loading = false;
        this.failed = false;
        return;
      }
    } catch (_) {}
    if (seq !== this.loadSeq) return;
    this.resolvedUri = '';
    this.loading = false;
    this.failed = true;
  }

  private handleImageError(): void {
    const failedUrl = this.resolvedUri;
    if (!this.fallbackTried && this.downloadLocalPreview && /^https?:\/\//i.test(failedUrl)) {
      this.fallbackTried = true;
      void this.tryLocalDownload(failedUrl);
      return;
    }
    this.resolvedUri = '';
    this.loading = false;
    this.failed = true;
  }

  @Builder
  removeBadge() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row() {
        Text('×')
          .fontSize(13)
          .lineHeight('14fp')
          .fontWeight(Weight.semibold)
          .fontColor('#FFFFFF')
      }
      .width(20)
      .height(20)
      .borderRadius(10)
      .backgroundColor('#99000000')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
    }
    .width(28)
    .height(28)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .accessibilityText('移除附件 ' + this.item.name)
    .onClick(() => this.onRemove(this.item.id))
  }

  build() {
    if (this.kind() === 'image') {
      Stack({ alignContent: Alignment.TopEnd }) {
        Stack({ alignContent: Alignment.Center }) {
          if (this.resolvedUri) {
            Image(this.resolvedUri)
              .width(TILE_SIZE)
              .height(TILE_SIZE)
              .objectFit(ImageFit.Cover)
              .draggable(false)
              .onError(() => { this.handleImageError(); })
          } else if (this.loading) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color($r('app.color.muted'))
              .accessibilityLevel('no')
          } else {
            Column({ space: 2 }) {
              Image($r('app.media.ui_image'))
                .width(20)
                .height(20)
                .opacity(0.6)
                .accessibilityLevel('no')
              Text(this.item.name || '图片')
                .fontSize(FontSize.badge)
                .lineHeight(LineHeight.badge)
                .fontColor($r('app.color.muted'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .padding({ left: 4, right: 4 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
          }
        }
        .width(TILE_SIZE)
        .height(TILE_SIZE)
        .backgroundColor($r('app.color.card'))
        .borderRadius(TILE_RADIUS)
        .border({ width: 0.5, color: $r('app.color.border') })
        .clip(true)
        .accessibilityGroup(true)
        .accessibilityText('预览图片附件 ' + this.item.name)
        .onClick(() => this.onOpen(this.item))

        this.removeBadge()
      }
      .width(TILE_SIZE)
      .height(TILE_SIZE)
      .flexShrink(0)
    } else if (this.kind() === 'video') {
      Stack({ alignContent: Alignment.TopEnd }) {
        Stack({ alignContent: Alignment.BottomStart }) {
          Column() {
            Text('▶')
              .fontSize(18)
              .fontColor($r('app.color.ink'))
              .opacity(0.85)
          }
          .width(TILE_SIZE)
          .height(TILE_SIZE)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .padding({ bottom: 12 })

          Row() {
            Text(composerAttachmentExtensionBadge(this.item.name, this.item.mimeType))
              .fontSize(10)
              .lineHeight('12fp')
              .fontWeight(Weight.semibold)
              .fontColor($r('app.color.muted'))
              .maxLines(1)
          }
          .width('100%')
          .padding({ left: 6, right: 6, top: 3, bottom: 4 })
          .backgroundColor($r('app.color.group'))
          .justifyContent(FlexAlign.Center)
        }
        .width(TILE_SIZE)
        .height(TILE_SIZE)
        .backgroundColor($r('app.color.card'))
        .borderRadius(TILE_RADIUS)
        .border({ width: 0.5, color: $r('app.color.border') })
        .clip(true)
        .accessibilityGroup(true)
        .accessibilityText('预览视频附件 ' + this.item.name)
        .onClick(() => this.onOpen(this.item))

        this.removeBadge()
      }
      .width(TILE_SIZE)
      .height(TILE_SIZE)
      .flexShrink(0)
    } else {
      Stack({ alignContent: Alignment.TopEnd }) {
        Row({ space: 8 }) {
          Column() {
            Text(composerAttachmentExtensionBadge(this.item.name, this.item.mimeType))
              .fontSize(10)
              .lineHeight('12fp')
              .fontWeight(Weight.semibold)
              .fontColor($r('app.color.ink'))
              .maxLines(1)
          }
          .width(38)
          .height(38)
          .borderRadius(8)
          .backgroundColor($r('app.color.group'))
          .border({ width: 0.5, color: $r('app.color.border') })
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .flexShrink(0)

          Column({ space: 2 }) {
            Text(this.item.name)
              .fontSize(FontSize.caption)
              .lineHeight('15fp')
              .fontWeight(Weight.medium)
              .fontColor($r('app.color.ink'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .wordBreak(WordBreak.BREAK_ALL)
              .width('100%')
            if (formatAttachmentSize(this.item.sizeBytes)) {
              Text(formatAttachmentSize(this.item.sizeBytes))
                .fontSize(FontSize.badge)
                .lineHeight(LineHeight.badge)
                .fontColor($r('app.color.muted'))
                .maxLines(1)
            }
          }
          .layoutWeight(1)
          .padding({ right: 16 })
          .alignItems(HorizontalAlign.Start)
        }
        .width(FILE_CARD_WIDTH)
        .height(TILE_SIZE)
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.card'))
        .borderRadius(TILE_RADIUS)
        .border({ width: 0.5, color: $r('app.color.border') })
        .alignItems(VerticalAlign.Center)
        .accessibilityGroup(true)
        .accessibilityText('查看文件附件 ' + this.item.name)
        .onClick(() => this.onOpen(this.item))

        this.removeBadge()
      }
      .width(FILE_CARD_WIDTH)
      .height(TILE_SIZE)
      .flexShrink(0)
    }
  }
}

@Component
export struct ComposerAttachmentStrip {
  @Prop attachments: DraftAttachment[] = [];
  @Prop contexts: ComposerContextRecord[] = [];
  @Prop uploading: boolean = false;
  @Prop previewUris: Record<string, string> = {};
  @Prop scopeKey: string = '';
  @Prop mediaReady: boolean = true;
  lookupLocalPreview: ((item: DraftAttachment) => string) | undefined = undefined;
  resolvePreview: ((item: DraftAttachment) => Promise<string>) | undefined = undefined;
  downloadLocalPreview: ((url: string, item: DraftAttachment) => Promise<string>) | undefined = undefined;
  onOpenAttachment: (item: DraftAttachment) => void = () => {};
  onRemoveAttachment: (id: string) => void = () => {};
  onRemoveContext: (contextId: string) => void = () => {};
  onCancelUpload: () => void = () => {};

  build() {
    Column({ space: 0 }) {
      if (this.attachments.length > 0 || this.uploading) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.attachments, (item: DraftAttachment) => {
              ComposerAttachmentTile({
                item,
                localUri: this.previewUris[item.id] || '',
                scopeKey: this.scopeKey,
                mediaReady: this.mediaReady,
                lookupLocalPreview: this.lookupLocalPreview,
                resolvePreview: this.resolvePreview,
                downloadLocalPreview: this.downloadLocalPreview,
                onOpen: (target: DraftAttachment) => this.onOpenAttachment(target),
                onRemove: (id: string) => this.onRemoveAttachment(id)
              })
            }, (item: DraftAttachment) => item.id + '|' + item.name + '|' + (this.previewUris[item.id] || ''))
            if (this.uploading) {
              Column({ space: 4 }) {
                LoadingProgress()
                  .width(18)
                  .height(18)
                  .color($r('app.color.muted'))
                  .accessibilityLevel('no')
                Text('上传中')
                  .fontSize(FontSize.badge)
                  .lineHeight(LineHeight.badge)
                  .fontColor($r('app.color.muted'))
              }
              .width(TILE_SIZE)
              .height(TILE_SIZE)
              .backgroundColor($r('app.color.card'))
              .borderRadius(TILE_RADIUS)
              .border({ width: 0.5, color: $r('app.color.border') })
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .flexShrink(0)
              .accessibilityText('正在上传附件，点击取消')
              .onClick(() => this.onCancelUpload())
            }
          }
          .padding({ left: 12, right: 12, top: 10, bottom: this.contexts.length > 0 ? 4 : 6 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .align(Alignment.Start)
        .width('100%')
      }

      if (this.contexts.length > 0) {
        Scroll() {
          Row({ space: 6 }) {
            ForEach(this.contexts, (item: ComposerContextRecord) => {
              Row({ space: 4 }) {
                if (item.kind === 'thread' || item.kind === 'environment' || item.kind === 'mention' ||
                  item.kind === 'terminal' || item.kind === 'skill') {
                  Image(
                    item.kind === 'thread' ? $r('app.media.ui_tab_chats') :
                    item.kind === 'environment' ? $r('app.media.ui_env_desktop') :
                    item.kind === 'terminal' ? $r('app.media.ui_terminal') :
                    item.kind === 'skill' ? $r('app.media.proj_icon_sparkles') :
                    $r('app.media.ui_tool_file')
                  )
                    .width(12)
                    .height(12)
                    .opacity(0.72)
                    .flexShrink(0)
                    .accessibilityLevel('no')
                }
                Text(composerContextChipLabel(item.kind, item.label))
                  .fontSize(FontSize.caption)
                  .lineHeight(LineHeight.caption)
                  .fontColor($r('app.color.ink'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .constraintSize({ maxWidth: 180 })
                Text('×')
                  .fontSize(FontSize.callout)
                  .fontColor($r('app.color.muted'))
              }
              .height(28)
              .padding({ left: 9, right: 8 })
              .backgroundColor($r('app.color.card'))
              .borderRadius(Radius.tool)
              .border({ width: 0.5, color: $r('app.color.border') })
              .alignItems(VerticalAlign.Center)
              .accessibilityDescription('移除引用 ' + item.label)
              .onClick(() => this.onRemoveContext(item.contextId))
            }, (item: ComposerContextRecord) => item.contextId + '|' + item.label)
          }
          .padding({
            left: 12,
            right: 12,
            top: (this.attachments.length > 0 || this.uploading) ? 2 : 10,
            bottom: 4
          })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .align(Alignment.Start)
        .width('100%')
      }
    }
    .width('100%')
  }
}
