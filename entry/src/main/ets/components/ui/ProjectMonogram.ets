import { monogramTone, projectInitials } from '../../protocol/Monogram';
import { Radius, Sizes } from '../../common/Theme';

/**
 * 项目双字母色块：22×22、圆角 6、浅色底 + 同色系深色字（深色模式为深底浅字）。
 * 配色由项目 id 稳定哈希决定（8 组，color.json 中 monogram_N_bg / monogram_N_fg），首字母由项目名提取。
 * 字号用 vp 固定，不随系统字号放大，避免撑破色块。纯装饰，不进入读屏。
 *
 * ProjectMonogram({ projectId: project.id, name: project.title })
 */
@Component
export struct ProjectMonogram {
  @Prop projectId: string = '';
  @Prop name: string = '';
  @Prop boxSize: number = Sizes.monogram;

  private tone(): number {
    return monogramTone(this.projectId.length > 0 ? this.projectId : this.name);
  }

  private textColorOf(): ResourceColor {
    switch (this.tone()) {
      case 0: return $r('app.color.monogram_1_fg');
      case 1: return $r('app.color.monogram_2_fg');
      case 2: return $r('app.color.monogram_3_fg');
      case 3: return $r('app.color.monogram_4_fg');
      case 4: return $r('app.color.monogram_5_fg');
      case 5: return $r('app.color.monogram_6_fg');
      case 6: return $r('app.color.monogram_7_fg');
      default: return $r('app.color.monogram_8_fg');
    }
  }

  private fillColorOf(): ResourceColor {
    switch (this.tone()) {
      case 0: return $r('app.color.monogram_1_bg');
      case 1: return $r('app.color.monogram_2_bg');
      case 2: return $r('app.color.monogram_3_bg');
      case 3: return $r('app.color.monogram_4_bg');
      case 4: return $r('app.color.monogram_5_bg');
      case 5: return $r('app.color.monogram_6_bg');
      case 6: return $r('app.color.monogram_7_bg');
      default: return $r('app.color.monogram_8_bg');
    }
  }

  private glyphSize(initials: string): string {
    // 两个拉丁字符用 size 的 45%，单个字符（含 CJK）用 55%。
    const ratio = Array.from(initials).length >= 2 ? 0.45 : 0.55;
    return Math.round(this.boxSize * ratio) + 'vp';
  }

  build() {
    Text(projectInitials(this.name))
      .width(this.boxSize)
      .height(this.boxSize)
      .fontSize(this.glyphSize(projectInitials(this.name)))
      .fontWeight(700)
      .fontFamily('monospace')
      .fontColor(this.textColorOf())
      .backgroundColor(this.fillColorOf())
      .borderRadius(Radius.badge)
      .textAlign(TextAlign.Center)
      .maxLines(1)
      .flexShrink(0)
      .accessibilityLevel('no')
  }
}
