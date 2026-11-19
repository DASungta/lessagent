import { FontSize, LineHeight, Radius, Space } from '../../common/Theme';

/**
 * 分组卡片：可选组标题 + card 底圆角 14 的行容器 + 可选脚注。
 * 页面底色用 group，卡片左右留 12（父容器 padding）。行之间的分隔线由 FormRow 自己画：第一行传 isFirst: true。
 *
 * GroupCard({ title: '运行位置', footnote: '每次新建线程使用项目根工作区。' }) {
 *   FormRow({ label: '项目', value: this.project, isFirst: true, onTap: () => this.pickProject() })
 *   FormRow({ label: '模型', placeholder: '请选择', onTap: () => this.pickModel() })
 * }
 */
@Component
export struct GroupCard {
  @Prop title: string = '';
  @Prop footnote: string = '';
  @BuilderParam content: () => void = this.noContent;

  @Builder noContent() {}

  build() {
    Column() {
      if (this.title.length > 0) {
        Text(this.title)
          .fontSize(FontSize.caption)
          .lineHeight(LineHeight.caption)
          .fontColor($r('app.color.muted'))
          .padding({ left: Space.xxs, right: Space.xxs, bottom: 5 })
          .accessibilityLevel('yes')
      }
      Column() {
        this.content()
      }
      .width('100%')
      .backgroundColor($r('app.color.card'))
      .borderRadius(Radius.card)
      .clip(true)
      if (this.footnote.length > 0) {
        Text(this.footnote)
          .fontSize(FontSize.caption)
          .lineHeight(LineHeight.caption)
          .fontColor($r('app.color.muted'))
          .padding({ left: 6, right: 6, top: 6 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: Space.sm })
  }
}
