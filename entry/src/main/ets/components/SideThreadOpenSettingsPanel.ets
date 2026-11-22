import { TopBar } from './ui/TopBar';
import { GroupCard } from './ui/GroupCard';
import { FormRow } from './ui/FormRow';
import { FontSize, LineHeight, Space } from '../common/Theme';
import { workspacePrefs, setSideThreadOpenTarget } from '../services/WorkspacePrefs';

@Component
export struct SideThreadOpenSettingsPanel {
  onBack: () => void = () => {};
  @State selected: string = workspacePrefs.sideThreadOpenTarget;
  @State busy: boolean = false;
  @State error: string = '';

  private async save(value: string): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    this.error = '';
    try {
      await setSideThreadOpenTarget(value);
      this.selected = workspacePrefs.sideThreadOpenTarget;
    } catch (_) {
      this.error = '设置未保存，请重试';
    } finally {
      this.busy = false;
    }
  }

  @Builder
  option(value: string, title: string, detail: string, isFirst: boolean = false) {
    FormRow({
      kind: 'choice',
      label: title,
      subtitle: detail,
      checked: this.selected === value,
      disabled: this.busy,
      isFirst,
      onTap: () => { void this.save(value); }
    })
  }

  build() {
    Column({ space: 0 }) {
      TopBar({ title: '子会话打开方式', showBack: true, backLabel: '返回设置', onBack: () => this.onBack() })
      Scroll() {
        Column({ space: 0 }) {
          GroupCard({
            title: '点击子智能体、侧聊或链接会话时',
            footnote: '三类入口统一遵守此设置。无论哪种方式，关闭或返回时都会回到父会话原位置。'
          }) {
            this.option('panel', '面板打开', '在当前会话上方以面板展开，不打断父会话浏览；也可随时切到主视图。', true)
            this.option('main', '主视图打开', '直接在主聊天页面打开，点返回即可回到父会话原滚动位置。', false)
          }
          if (this.error) {
            Text(this.error)
              .fontSize(FontSize.callout)
              .lineHeight(LineHeight.callout)
              .fontColor($r('app.color.danger'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.sm })
              .width('100%')
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: Space.sm, right: Space.sm, bottom: Space.lg })
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.group'))
    .foregroundColor($r('app.color.ink'))
  }
}
