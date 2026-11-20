import { TopBar } from './ui/TopBar';
import { GroupCard } from './ui/GroupCard';
import { FormRow } from './ui/FormRow';
import { AppButton } from './ui/AppButton';
import { StatusBadge } from './ui/StatusBadge';
import { FontSize, LineHeight, Sizes, Space, Weight } from '../common/Theme';
import { localNotificationsEnabled, setLocalNotificationsEnabled, localNotificationPermission } from '../services/LocalNotifications';

@Component
export struct NotificationSettingsPanel {
  onBack: () => void = () => {};
  @State notificationsEnabled: boolean = localNotificationsEnabled();
  @State busy: boolean = false;
  @State error: string = '';
  @State permission: string = '正在读取';
  @StorageLink('t3LocalNotificationStatus') status: string = '尚未观察到通知事件';
  @StorageLink('t3LocalNotificationPublishedAt') publishedAt: string = '';
  @StorageLink('t3NotificationTapStatus') tapStatus: string = '尚未收到通知点击';
  aboutToAppear(): void { void this.refreshPermission(); }
  private async refreshPermission(): Promise<void> {
    try { this.permission = await localNotificationPermission() ? '允许' : '未允许'; }
    catch (_) { this.permission = '读取失败'; }
  }
  private async toggle(): Promise<void> {
    if (this.busy) return;
    this.busy = true; this.error = '';
    try { await setLocalNotificationsEnabled(!this.notificationsEnabled); }
    catch (_) { this.error = '无法更新通知设置，请检查系统权限后重试'; }
    finally { this.notificationsEnabled = localNotificationsEnabled(); this.busy = false; void this.refreshPermission(); }
  }
  build() {
    Column({ space: 0 }) {
      TopBar({ title: '任务通知', showBack: true, backLabel: '返回设置', onBack: () => this.onBack() })
      Scroll() {
        Column({ space: 0 }) {
          GroupCard({
            title: '在线任务提醒',
            footnote: '连接期间收到任务完成或结束事件时，在通知中心提醒你。正在查看的会话不会重复提醒。'
          }) {
            FormRow({
              kind: 'switch',
              label: '启用任务通知',
              checked: this.notificationsEnabled,
              disabled: this.busy,
              isFirst: true,
              onToggle: () => { void this.toggle(); }
            })
          }
          if (this.error) {
            Text(this.error)
              .fontSize(FontSize.callout).lineHeight(LineHeight.callout).fontColor($r('app.color.danger'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.xs }).width('100%')
          }
          GroupCard({
            title: '通知状态',
            footnote: '通知仅显示通用状态，不包含任务、消息或秘密内容。此功能不是云推送，断开后不会收到通知或补发历史通知。'
          }) {
            Row({ space: Space.sm }) {
              Text('系统权限')
                .fontSize(FontSize.body).lineHeight(LineHeight.body).fontWeight(Weight.regular)
                .fontColor($r('app.color.ink')).layoutWeight(1)
              StatusBadge({
                text: this.permission,
                tone: this.permission === '允许' ? 'success' : this.permission === '读取失败' ? 'danger' : 'warning'
              })
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
            .constraintSize({ minHeight: Sizes.formRowMin })
            .alignItems(VerticalAlign.Center)
            FormRow({ kind: 'multiline', label: '运行状态', value: this.status, valueMuted: true })
            if (this.publishedAt) {
              FormRow({ kind: 'value', label: '最近系统接受', value: this.publishedAt, valueMuted: true, chevron: false })
            }
            FormRow({ kind: 'multiline', label: '通知点击', value: this.tapStatus, valueMuted: true })
          }
          Column() {
            AppButton({
              label: this.busy ? '正在更新…' : this.notificationsEnabled ? '关闭任务通知' : '启用任务通知',
              kind: this.notificationsEnabled ? 'secondary' : 'primary',
              fill: true,
              loading: this.busy,
              onTap: () => { void this.toggle(); }
            })
          }.width('100%').padding({ top: Space.md })
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: Space.sm, right: Space.sm, bottom: Space.lg })
      }.width('100%').layoutWeight(1).align(Alignment.TopStart)
    }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
  }
}
