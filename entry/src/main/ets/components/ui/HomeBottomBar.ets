import { Sizes, Space } from '../../common/Theme';

export type HomeTab = 'sessions' | 'home-pulls' | 'usage' | 'settings';

@Component
struct HomeTabButton {
  icon: Resource = $r('app.media.ui_tab_chats');
  @Prop label: string = '';
  @Prop selected: boolean = false;
  onTap: () => void = () => {};

  build() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Image(this.icon)
        .width(Sizes.icon)
        .height(Sizes.icon)
        .objectFit(ImageFit.Contain)
        .draggable(false)
        .opacity(this.selected ? 1 : 0.65)
        .accessibilityLevel('no')
    }
    .layoutWeight(1)
    .height(42)
    .borderRadius(21)
    .backgroundColor(this.selected ? $r('app.color.tab_bar_active') : Color.Transparent)
    .accessibilityText(this.label + (this.selected ? '，已选中' : ''))
    .onClick(() => this.onTap())
  }
}

/**
 * 首页底部悬浮四栏 + 右侧新任务按钮。
 * 左侧胶囊容器承载 4 个一级标签（会话 / 拉取请求 / 用量 / 设置），右侧为深色方形圆角 FAB。
 */
@Component
export struct HomeBottomBar {
  @Prop activeTab: HomeTab = 'sessions';
  onSelectTab: (tab: HomeTab) => void = () => {};
  onNewTask: () => void = () => {};

  build() {
    Row({ space: Space.sm }) {
      Row({ space: 2 }) {
        HomeTabButton({ icon: $r('app.media.ui_tab_chats'), label: '会话',
          selected: this.activeTab === 'sessions', onTap: () => this.onSelectTab('sessions') })
        HomeTabButton({ icon: $r('app.media.ui_tab_pulls'), label: '拉取请求',
          selected: this.activeTab === 'home-pulls', onTap: () => this.onSelectTab('home-pulls') })
        HomeTabButton({ icon: $r('app.media.ui_tab_usage'), label: '用量',
          selected: this.activeTab === 'usage', onTap: () => this.onSelectTab('usage') })
        HomeTabButton({ icon: $r('app.media.ui_tab_settings'), label: '设置',
          selected: this.activeTab === 'settings', onTap: () => this.onSelectTab('settings') })
      }
      .layoutWeight(1)
      .height(54)
      .borderRadius(27)
      .padding({ left: 6, right: 6 })
      .backgroundColor($r('app.color.tab_bar_bg'))
      .border({ width: 0.5, color: $r('app.color.border') })
      .shadow({ radius: 16, color: '#24000000', offsetX: 0, offsetY: 4 })
      .alignItems(VerticalAlign.Center)

      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Image($r('app.media.ui_fab_compose'))
          .width(Sizes.icon)
          .height(Sizes.icon)
          .objectFit(ImageFit.Contain)
          .draggable(false)
          .accessibilityLevel('no')
      }
      .width(54)
      .height(54)
      .borderRadius(16)
      .backgroundColor($r('app.color.prominent'))
      .shadow({ radius: 14, color: '#2e000000', offsetX: 0, offsetY: 5 })
      .accessibilityText('新建任务')
      .onClick(() => this.onNewTask())
    }
    .width('100%')
    .padding({ left: Space.md, right: Space.md, bottom: Space.md, top: Space.xs })
    .alignItems(VerticalAlign.Center)
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
