import { FontSize, LineHeight, Radius, Space, Weight } from '../common/Theme';
import { MentionItem } from '../protocol/Mentions';
import { ProviderLogo } from './ui/ProviderLogo';

@Component
export struct ComposerMentionPopover {
  @Prop items: MentionItem[] = [];
  @Prop query: string = '';
  @Prop loading: boolean = false;
  onSelect: (item: MentionItem) => void = () => {};
  onDismiss: () => void = () => {};

  private headerLabel(): string {
    if (this.items.length > 0 && this.items.every((item: MentionItem) => item.kind === 'file')) {
      return '文件';
    }
    return '提及';
  }

  build() {
    Column({ space: 0 }) {
      Row({ space: Space.xs }) {
        Text(this.headerLabel())
          .fontSize(FontSize.badge)
          .lineHeight(LineHeight.badge)
          .fontWeight(Weight.semibold)
          .fontColor($r('app.color.muted'))
        if (this.query.trim()) {
          Text('@' + this.query.trim())
            .fontSize(FontSize.badge)
            .lineHeight(LineHeight.badge)
            .fontColor($r('app.color.primary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        } else {
          Blank()
        }
        if (this.loading) {
          LoadingProgress()
            .width(12)
            .height(12)
            .color($r('app.color.muted'))
            .accessibilityLevel('no')
        }
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          Text('×')
            .fontSize(FontSize.callout)
            .fontColor($r('app.color.muted'))
        }
        .width(24)
        .height(24)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .accessibilityText('关闭提及候选')
        .onClick(() => this.onDismiss())
      }
      .width('100%')
      .padding({ left: Space.sm, right: Space.xs, top: 6, bottom: 4 })
      .alignItems(VerticalAlign.Center)

      if (this.items.length > 0) {
        Scroll() {
          Column({ space: 0 }) {
            ForEach(this.items, (item: MentionItem, index: number) => {
              Button({ type: ButtonType.Normal, stateEffect: true }) {
                Row({ space: Space.xs }) {
                  if (item.kind === 'model') {
                    Row() {
                      ProviderLogo({ driver: item.providerDriver, model: item.model, logoSize: 15 })
                    }.width(18).height(18).justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center).flexShrink(0)
                  } else {
                    Image(
                      item.kind === 'thread' ? $r('app.media.ui_tab_chats') :
                      item.kind === 'environment' ? $r('app.media.ui_env_desktop') :
                      item.fileKind === 'directory' ? $r('app.media.ui_folder') :
                      $r('app.media.ui_tool_file')
                    )
                      .width(15)
                      .height(15)
                      .opacity(0.72)
                      .flexShrink(0)
                      .accessibilityLevel('no')
                  }
                  Text(item.label)
                    .fontSize(FontSize.callout)
                    .lineHeight(LineHeight.callout)
                    .fontWeight(Weight.medium)
                    .fontColor($r('app.color.ink'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .constraintSize({ maxWidth: item.kind === 'thread' ? '48%' : '62%' })
                    .flexShrink(0)
                  if (item.description) {
                    Text(item.description)
                      .fontSize(FontSize.caption)
                      .lineHeight(LineHeight.caption)
                      .fontColor($r('app.color.muted'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                      .textAlign(TextAlign.Start)
                  } else {
                    Blank()
                  }
                }
                .width('100%')
                .padding({ left: Space.sm, right: Space.sm, top: 9, bottom: 9 })
                .alignItems(VerticalAlign.Center)
                .border({
                  width: { bottom: index === this.items.length - 1 ? 0 : 0.5 },
                  color: $r('app.color.border')
                })
              }
              .width('100%')
              .padding(0)
              .backgroundColor(Color.Transparent)
              .onClick(() => this.onSelect(item))
            }, (item: MentionItem) => item.id + '|' + item.label + '|' + item.description)
          }
          .width('100%')
        }
        .constraintSize({ maxHeight: 192 })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .width('100%')
      } else {
        Text(this.loading ? '正在搜索…' : '没有匹配的会话、环境、模型或文件')
          .fontSize(FontSize.caption)
          .lineHeight(LineHeight.caption)
          .fontColor($r('app.color.muted'))
          .width('100%')
          .padding({ left: Space.sm, right: Space.sm, top: 6, bottom: 10 })
      }
    }
    .id('composer-mention-popover')
    .width('100%')
    .backgroundColor($r('app.color.card'))
    .borderRadius(Radius.card)
    .border({ width: 1, color: $r('app.color.border') })
    .clip(true)
    .shadow({ radius: 12, color: '#1A000000', offsetX: 0, offsetY: 2 })
  }
}
