import { monogramTone, projectIconColorKey, projectInitials, resolveLucideIconSlug } from '../../protocol/Monogram';
import { ProjectIconView } from '../../protocol/Projects';
import { Radius, Sizes } from '../../common/Theme';

/**
 * 项目图标 / 双字母色块：默认 22×22、圆角 6、浅色底 + 同色系深色前景（深色模式为深底浅前景）。
 * 若项目在服务端配置了 projectIcon（lucide / emoji / monogram），优先同步展示服务端图标；
 * 否则回退到按项目 id 稳定哈希的 8 色首字母色块。纯装饰，不进入读屏。
 *
 * ProjectMonogram({ projectId: project.id, name: project.title, icon: project.projectIcon })
 */
@Component
export struct ProjectMonogram {
  @Prop projectId: string = '';
  @Prop name: string = '';
  @Prop icon: ProjectIconView | undefined = undefined;
  @Prop boxSize: number = Sizes.monogram;

  private tone(): number {
    return monogramTone(this.projectId.length > 0 ? this.projectId : this.name);
  }

  private cornerRadius(): number {
    if (this.boxSize >= 32) return 8;
    if (this.boxSize >= 26) return 7;
    return Radius.badge;
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

  private iconFgColor(color: string): ResourceColor {
    switch (projectIconColorKey(color)) {
      case 'gray': return $r('app.color.proj_icon_gray_fg');
      case 'red': return $r('app.color.proj_icon_red_fg');
      case 'orange': return $r('app.color.proj_icon_orange_fg');
      case 'amber': return $r('app.color.proj_icon_amber_fg');
      case 'yellow': return $r('app.color.proj_icon_yellow_fg');
      case 'lime': return $r('app.color.proj_icon_lime_fg');
      case 'green': return $r('app.color.proj_icon_green_fg');
      case 'emerald': return $r('app.color.proj_icon_emerald_fg');
      case 'teal': return $r('app.color.proj_icon_teal_fg');
      case 'cyan': return $r('app.color.proj_icon_cyan_fg');
      case 'sky': return $r('app.color.proj_icon_sky_fg');
      case 'blue': return $r('app.color.proj_icon_blue_fg');
      case 'indigo': return $r('app.color.proj_icon_indigo_fg');
      case 'violet': return $r('app.color.proj_icon_violet_fg');
      case 'purple': return $r('app.color.proj_icon_purple_fg');
      case 'fuchsia': return $r('app.color.proj_icon_fuchsia_fg');
      case 'pink': return $r('app.color.proj_icon_pink_fg');
      case 'rose': return $r('app.color.proj_icon_rose_fg');
      default: return this.textColorOf();
    }
  }

  private iconBgColor(color: string): ResourceColor {
    switch (projectIconColorKey(color)) {
      case 'gray': return $r('app.color.proj_icon_gray_bg');
      case 'red': return $r('app.color.proj_icon_red_bg');
      case 'orange': return $r('app.color.proj_icon_orange_bg');
      case 'amber': return $r('app.color.proj_icon_amber_bg');
      case 'yellow': return $r('app.color.proj_icon_yellow_bg');
      case 'lime': return $r('app.color.proj_icon_lime_bg');
      case 'green': return $r('app.color.proj_icon_green_bg');
      case 'emerald': return $r('app.color.proj_icon_emerald_bg');
      case 'teal': return $r('app.color.proj_icon_teal_bg');
      case 'cyan': return $r('app.color.proj_icon_cyan_bg');
      case 'sky': return $r('app.color.proj_icon_sky_bg');
      case 'blue': return $r('app.color.proj_icon_blue_bg');
      case 'indigo': return $r('app.color.proj_icon_indigo_bg');
      case 'violet': return $r('app.color.proj_icon_violet_bg');
      case 'purple': return $r('app.color.proj_icon_purple_bg');
      case 'fuchsia': return $r('app.color.proj_icon_fuchsia_bg');
      case 'pink': return $r('app.color.proj_icon_pink_bg');
      case 'rose': return $r('app.color.proj_icon_rose_bg');
      default: return this.fillColorOf();
    }
  }

  private lucideMedia(slug: string): Resource {
    switch (slug) {
      case 'folder-code': return $r('app.media.proj_icon_folder_code');
      case 'code-2': return $r('app.media.proj_icon_code_2');
      case 'terminal': return $r('app.media.proj_icon_terminal');
      case 'globe-2': return $r('app.media.proj_icon_globe_2');
      case 'server': return $r('app.media.proj_icon_server');
      case 'database': return $r('app.media.proj_icon_database');
      case 'bot': return $r('app.media.proj_icon_bot');
      case 'sparkles': return $r('app.media.proj_icon_sparkles');
      case 'smartphone': return $r('app.media.proj_icon_smartphone');
      case 'monitor': return $r('app.media.proj_icon_monitor');
      case 'cloud-cog': return $r('app.media.proj_icon_cloud_cog');
      case 'package': return $r('app.media.proj_icon_package');
      case 'book-open': return $r('app.media.proj_icon_book_open');
      case 'flask-conical': return $r('app.media.proj_icon_flask_conical');
      case 'shield-check': return $r('app.media.proj_icon_shield_check');
      case 'rocket': return $r('app.media.proj_icon_rocket');
      case 'gamepad-2': return $r('app.media.proj_icon_gamepad_2');
      case 'music': return $r('app.media.proj_icon_music');
      case 'image': return $r('app.media.proj_icon_image');
      case 'shopping-bag': return $r('app.media.proj_icon_shopping_bag');
      case 'git-branch': return $r('app.media.proj_icon_git_branch');
      case 'workflow': return $r('app.media.proj_icon_workflow');
      case 'wrench': return $r('app.media.proj_icon_wrench');
      case 'layers-3': return $r('app.media.proj_icon_layers_3');
      default: return $r('app.media.proj_icon_message_square_dashed');
    }
  }

  private lucideSlug(): string {
    if (this.icon === undefined || this.icon.kind !== 'lucide') return '';
    return resolveLucideIconSlug(this.icon.name);
  }

  private glyphSize(initials: string): string {
    // 两个拉丁字符用 size 的 45%，单个字符（含 CJK）用 55%。
    const ratio = Array.from(initials).length >= 2 ? 0.45 : 0.55;
    return Math.round(this.boxSize * ratio) + 'vp';
  }

  private innerIconSize(): number {
    return Math.max(12, Math.round(this.boxSize * 0.62));
  }

  private monogramLabel(): string {
    if (this.icon !== undefined && this.icon.kind === 'monogram' && this.icon.text.trim().length > 0) {
      return this.icon.text.trim();
    }
    return projectInitials(this.name);
  }

  build() {
    if (this.icon !== undefined && this.icon.kind === 'lucide' && this.lucideSlug().length > 0) {
      Column() {
        Image(this.lucideMedia(this.lucideSlug()))
          .width(this.innerIconSize())
          .height(this.innerIconSize())
          .fillColor(this.iconFgColor(this.icon.color))
          .accessibilityLevel('no')
      }
      .width(this.boxSize)
      .height(this.boxSize)
      .backgroundColor(this.iconBgColor(this.icon.color))
      .borderRadius(this.cornerRadius())
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .flexShrink(0)
      .accessibilityLevel('no')
    } else if (this.icon !== undefined && this.icon.kind === 'emoji' && this.icon.emoji.trim().length > 0) {
      Column() {
        Text(this.icon.emoji.trim())
          .fontSize(Math.max(11, Math.round(this.boxSize * 0.6)) + 'vp')
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .accessibilityLevel('no')
      }
      .width(this.boxSize)
      .height(this.boxSize)
      .backgroundColor($r('app.color.proj_icon_gray_bg'))
      .borderRadius(this.cornerRadius())
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .flexShrink(0)
      .accessibilityLevel('no')
    } else {
      Text(this.monogramLabel())
        .width(this.boxSize)
        .height(this.boxSize)
        .fontSize(this.glyphSize(this.monogramLabel()))
        .fontWeight(700)
        .fontFamily('monospace')
        .fontColor(this.icon !== undefined && this.icon.kind === 'monogram'
          ? this.iconFgColor(this.icon.color) : this.textColorOf())
        .backgroundColor(this.icon !== undefined && this.icon.kind === 'monogram'
          ? this.iconBgColor(this.icon.color) : this.fillColorOf())
        .borderRadius(this.cornerRadius())
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .flexShrink(0)
        .accessibilityLevel('no')
    }
  }
}
