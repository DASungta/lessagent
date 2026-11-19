/**
 * 设计令牌（非颜色部分）。来源：docs/design/style-guide.html 第 2 节。
 * 颜色一律用 $r('app.color.xxx')，见 resources/base|dark/element/color.json 与 docs/design/README.md。
 *
 * 字号单位 fp（跟随系统字号缩放）；行高用 'NNfp' 字符串，与字号同步缩放。
 * 间距、圆角、尺寸单位 vp（ArkUI 数字默认单位）。
 */

/** 字号（fp）。只用这 7 档，11 号只留给角标。 */
export class FontSize {
  static readonly title: number = 22;
  static readonly headline: number = 17;
  static readonly body: number = 15;
  static readonly callout: number = 13;
  static readonly caption: number = 12;
  static readonly mono: number = 13;
  static readonly badge: number = 11;
}

/** 与 FontSize 一一对应的行高。 */
export class LineHeight {
  static readonly title: string = '28fp';
  static readonly headline: string = '22fp';
  static readonly body: string = '22fp';
  static readonly callout: string = '18fp';
  static readonly caption: string = '16fp';
  static readonly mono: string = '19fp';
  static readonly badge: string = '14fp';
}

/**
 * 字重约定：正文 regular；列表主行 / 按钮文字 / 强调 medium；标题栏、分组标题、主按钮 semibold；
 * 只有首页字标与空态标题用 bold。
 */
export class Weight {
  static readonly regular: number = 400;
  static readonly medium: number = 500;
  static readonly semibold: number = 600;
  static readonly bold: number = 700;
}

/** 间距（4 的倍数）。页面左右边距用 page。 */
export class Space {
  static readonly xxs: number = 4;
  static readonly xs: number = 8;
  static readonly sm: number = 12;
  static readonly md: number = 16;
  static readonly lg: number = 24;
  static readonly xl: number = 32;
  static readonly page: number = 16;
}

/** 圆角。 */
export class Radius {
  /** 角标、项目色块 */
  static readonly badge: number = 6;
  /** 工具行、代码块 */
  static readonly tool: number = 10;
  /** 按钮、搜索框 */
  static readonly button: number = 12;
  /** 分组卡片 */
  static readonly card: number = 14;
  /** 消息气泡 */
  static readonly bubble: number = 18;
  /** 输入区 */
  static readonly composer: number = 22;
  /** 全圆：图标按钮、胶囊。ArkUI 圆角超过半高时按半高绘制。 */
  static readonly full: number = 999;
}

/** 固定尺寸。 */
export class Sizes {
  static readonly topBar: number = 52;
  static readonly iconHit: number = 40;
  static readonly icon: number = 22;
  static readonly listRowMin: number = 56;
  static readonly formRowMin: number = 50;
  static readonly buttonHeight: number = 46;
  /** 卡片、对话框里的紧凑按钮 */
  static readonly buttonHeightCompact: number = 38;
  static readonly monogram: number = 22;
  static readonly chevron: number = 16;
  /** 分隔线粗细 */
  static readonly hairline: number = 1;
}

/** 状态透明度。 */
export class Opacity {
  static readonly disabled: number = 0.38;
  static readonly pressed: number = 0.7;
}
