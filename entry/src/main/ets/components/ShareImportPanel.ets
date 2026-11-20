import { IncomingShareAttachment, MAX_SHARED_TEXT_CHARS, SharePart, shareDraftText } from '../protocol/IncomingShare';
import { image } from '@kit.ImageKit';
import { FontSize, LineHeight, Opacity, Radius, Sizes, Space, Weight } from '../common/Theme';
import { AppButton } from './ui/AppButton';
import { TopBar } from './ui/TopBar';

@Component
export struct ShareImportPanel {
  @Prop parts: SharePart[] = [];
  @Prop @Watch('closePreview') shareId: number = 0;
  @Prop @Watch('attachmentsChanged') attachments: IncomingShareAttachment[] = [];
  @Prop destination: string = '';
  @Prop @Watch('busyChanged') busy: boolean = false;
  @Prop uploading: boolean = false;
  @Prop uploadedCount: number = 0;
  @Prop error: string = '';
  @StorageLink('t3Foreground') @Watch('foregroundChanged') foreground: boolean = true;
  @State previewId: string = '';
  @State thumbnail: image.PixelMap | undefined = undefined;
  @State thumbnailLoading: boolean = false;
  @State thumbnailReading: boolean = false;
  @State thumbnailError: string = '';
  onEdit: (id: number, text: string) => void = () => {};
  onRemove: (id: number) => void = () => {};
  onRemoveAttachment: (id: string) => void = () => {};
  loadThumbnail: (shareId: number, attachmentId: string, stillSelected: () => boolean) => Promise<image.PixelMap> =
    async () => { throw new Error('图片预览不可用'); };
  onCancelUpload: () => void = () => {};
  onConfirm: () => void = () => {};
  onChooseDestination: () => void = () => {};
  onCancel: () => void = () => {};
  private previewRevision: number = 0;
  private alive: boolean = false;
  private previewRead: Promise<image.PixelMap> | undefined = undefined;

  aboutToAppear(): void { this.alive = true; }
  aboutToDisappear(): void { this.alive = false; this.closePreview(); }

  private attachmentsChanged(): void {
    if (this.previewId && !this.attachments.some((item: IncomingShareAttachment) => item.id === this.previewId)) {
      this.closePreview();
    }
  }
  private busyChanged(): void { if (this.busy) this.closePreview(); }
  private foregroundChanged(): void { if (!this.foreground) this.closePreview(); }
  private closePreview(): void {
    this.previewRevision++;
    const previous = this.thumbnail;
    this.thumbnail = undefined; this.previewId = ''; this.thumbnailLoading = false; this.thumbnailError = '';
    if (previous) void previous.release().catch(() => {});
  }
  private async showPreview(attachmentId: string): Promise<void> {
    if (!this.alive || !this.foreground || this.busy ||
      !this.attachments.some((item: IncomingShareAttachment) => item.id === attachmentId && item.type === 'image')) return;
    const same = this.previewId === attachmentId;
    this.closePreview();
    if (same) return;
    const shareId = this.shareId;
    const revision = this.previewRevision;
    this.previewId = attachmentId; this.thumbnailLoading = true;
    const current = (): boolean => this.alive && this.foreground && !this.busy && this.previewRevision === revision &&
      this.shareId === shareId && this.previewId === attachmentId &&
      this.attachments.some((item: IncomingShareAttachment) => item.id === attachmentId && item.type === 'image');
    const previous = this.previewRead;
    if (previous) await previous.catch(() => {});
    if (!current()) return;
    const request = this.loadThumbnail(shareId, attachmentId, current);
    this.previewRead = request;
    this.thumbnailReading = true;
    try {
      const thumbnail = await request;
      if (!current()) { void thumbnail.release().catch(() => {}); return; }
      this.thumbnail = thumbnail;
    } catch (error) {
      if (current()) this.thumbnailError = (error as Error).message || '图片预览不可用，仍可上传原附件。';
    } finally {
      if (this.previewRead === request) { this.previewRead = undefined; this.thumbnailReading = false; }
      if (current()) this.thumbnailLoading = false;
    }
  }
  private partLimit(id: number): number {
    const others = shareDraftText(this.parts.filter((part: SharePart) => part.id !== id));
    return Math.max(1, MAX_SHARED_TEXT_CHARS - others.length - (others.length ? 2 : 0));
  }
  private charCount(): number { return shareDraftText(this.parts).length; }
  private canSave(): boolean {
    const value = shareDraftText(this.parts);
    return !this.busy && !this.thumbnailReading && !this.thumbnailLoading && !!this.destination && (value.length > 0 || this.attachments.length > 0) &&
      value.length <= MAX_SHARED_TEXT_CHARS && !value.includes('\u0000');
  }
  private fileSize(bytes: number): string {
    if (bytes >= 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + ' MiB';
    if (bytes >= 1024) return (bytes / 1024).toFixed(1) + ' KiB';
    return bytes + ' 字节';
  }
  private summary(): string {
    const count = this.attachments.length;
    const files = count + ' 个附件 · ' + this.fileSize(this.attachments.reduce((sum: number, item: IncomingShareAttachment) => sum + item.sizeBytes, 0));
    if (!this.parts.length) return count ? files : '没有待保存的内容';
    const text = this.parts.length + ' 项文字或链接 · ' + this.charCount() + ' / ' + MAX_SHARED_TEXT_CHARS + ' 字符';
    return count ? text + ' · ' + files : text;
  }
  build() {
    Column() {
      TopBar({
        title: '导入分享',
        showBack: true,
        closeStyle: true,
        backLabel: this.uploading ? '取消上传' : '取消',
        onBack: () => {
          if (this.uploading) this.onCancelUpload();
          else if (!this.busy) this.onCancel();
        }
      }) {
        if (this.uploading) {
          AppButton({ label: '取消上传', kind: 'text', compact: true, onTap: () => this.onCancelUpload() })
        }
      }
      Column({ space: Space.sm }) {
        Text(this.attachments.length ? '确认后将附件上传到所选环境，并保存为新草稿。稍后由你手动发送。' :
          '确认目标并保存为新草稿，稍后由你手动发送。')
          .fontSize(FontSize.callout).lineHeight(LineHeight.callout)
          .fontColor($r('app.color.muted')).width('100%')
        Button({ type: ButtonType.Normal }) {
          Row({ space: Space.xs }) {
            Text(this.destination || '选择环境与项目')
              .fontSize(FontSize.body).fontColor($r('app.color.ink')).layoutWeight(1)
            Image($r('app.media.ui_chevron_right')).width(Sizes.chevron).height(Sizes.chevron)
              .opacity(0.45).accessibilityLevel('no')
          }.width('100%').padding(14).constraintSize({ minHeight: Sizes.formRowMin })
        }.width('100%').padding(0).backgroundColor($r('app.color.card')).borderRadius(Radius.card)
          .enabled(!this.busy).opacity(this.busy ? Opacity.disabled : 1).onClick(this.onChooseDestination)
        Text(this.summary())
          .fontSize(FontSize.callout).lineHeight(LineHeight.callout).fontColor($r('app.color.muted')).width('100%')
        Scroll() {
          Column({ space: Space.sm }) {
            ForEach(this.parts, (part: SharePart, index: number) => {
              Column({ space: Space.xs }) {
                Row({ space: Space.xs }) {
                  Text('第 ' + (index + 1) + ' 项 · ' + (part.kind === 'link' ? '链接' : '文字'))
                    .fontSize(FontSize.callout).fontColor($r('app.color.muted')).fontWeight(Weight.medium).layoutWeight(1)
                  Button('移除', { type: ButtonType.Normal }).constraintSize({ minWidth: Sizes.iconHit, minHeight: 36 })
                    .fontSize(FontSize.callout).fontColor($r('app.color.danger')).backgroundColor(Color.Transparent)
                    .accessibilityText('移除第 ' + (index + 1) + ' 项')
                    .enabled(!this.busy).onClick(() => this.onRemove(part.id))
                }.width('100%').alignItems(VerticalAlign.Center)
                TextArea({ text: part.text, placeholder: '分享内容' }).width('100%').fontSize(FontSize.body)
                  .constraintSize({ minHeight: 72 }).maxLines(6, { overflowMode: MaxLinesMode.SCROLL })
                  .fontColor($r('app.color.ink')).backgroundColor($r('app.color.group')).borderRadius(Radius.button).padding(Space.sm)
                  .maxLength(this.partLimit(part.id)).enabled(!this.busy)
                  .onChange((value: string) => { this.onEdit(part.id, value); })
                  .accessibilityText('编辑第 ' + (index + 1) + ' 项')
              }.width('100%').padding(14).backgroundColor($r('app.color.card')).borderRadius(Radius.card)
            }, (part: SharePart) => String(part.id))
            ForEach(this.attachments, (item: IncomingShareAttachment) => {
              Column({ space: Space.xs }) {
                Row({ space: Space.xs }) {
                  Column({ space: 2 }) {
                    Text(item.name).fontColor($r('app.color.ink')).fontSize(FontSize.body).fontWeight(Weight.medium)
                      .width('100%').wordBreak(WordBreak.BREAK_ALL)
                    Text(this.fileSize(item.sizeBytes))
                      .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted')).width('100%')
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  Button('移除', { type: ButtonType.Normal }).constraintSize({ minWidth: Sizes.iconHit, minHeight: 36 })
                    .fontSize(FontSize.callout).fontColor($r('app.color.danger')).backgroundColor(Color.Transparent)
                    .accessibilityText('移除附件 ' + item.name).enabled(!this.busy).onClick(() => {
                      if (this.previewId === item.id) this.closePreview();
                      this.onRemoveAttachment(item.id);
                    })
                }.width('100%').alignItems(VerticalAlign.Center)
                if (item.type === 'image') {
                  Button(this.previewId === item.id ? '收起图片预览' : '查看图片', { type: ButtonType.Normal })
                    .constraintSize({ minWidth: Sizes.iconHit, minHeight: Sizes.buttonHeightCompact })
                    .fontSize(FontSize.callout).fontColor($r('app.color.ink'))
                    .backgroundColor($r('app.color.group')).borderRadius(Radius.tool).enabled(!this.busy)
                    .accessibilityText((this.previewId === item.id ? '收起图片预览 ' : '查看图片 ') + item.name)
                    .onClick(() => { void this.showPreview(item.id); })
                  if (this.previewId === item.id) {
                    if (this.thumbnailLoading) {
                      Text('正在读取本地预览…').fontSize(FontSize.callout).fontColor($r('app.color.muted')).width('100%')
                    }
                    if (this.thumbnailError) {
                      Text(this.thumbnailError).fontSize(FontSize.callout).fontColor($r('app.color.danger')).width('100%')
                    }
                    if (this.thumbnail) {
                      Image(this.thumbnail).width('100%').height(148).objectFit(ImageFit.Contain).borderRadius(Radius.tool)
                        .accessibilityText(item.name + ' 的本地图片预览')
                    }
                  }
                }
              }.width('100%').alignItems(HorizontalAlign.Start).padding(14).backgroundColor($r('app.color.card')).borderRadius(Radius.card)
            }, (item: IncomingShareAttachment) => item.id)
          }.width('100%')
        }.width('100%').layoutWeight(1).align(Alignment.TopStart)
        if (this.charCount() > MAX_SHARED_TEXT_CHARS) {
          Text('分享内容超过总字数上限，请缩短后保存。')
            .fontSize(FontSize.callout).fontColor($r('app.color.danger')).width('100%')
        }
        if (this.error) {
          Text(this.error).fontSize(FontSize.callout).fontColor($r('app.color.danger')).width('100%')
        }
        if (this.uploadedCount) {
          Text('已确认上传 ' + this.uploadedCount + ' / ' + this.attachments.length + ' 个附件')
            .fontSize(FontSize.callout).fontColor($r('app.color.muted')).width('100%')
        }
        AppButton({
          label: this.uploading ? '正在上传…' : this.busy ? '正在保存…' :
            this.attachments.length ? '确认上传并保存草稿' : '保存为新草稿',
          kind: 'primary',
          fill: true,
          loading: this.uploading || this.busy,
          disabled: !this.canSave(),
          onTap: this.onConfirm
        })
      }.layoutWeight(1).width('100%').padding({ left: Space.page, right: Space.page, top: Space.xxs, bottom: Space.md })
    }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
  }
}
