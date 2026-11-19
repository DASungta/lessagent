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
      Row({ space: 8 }) {
        Button({ type: ButtonType.Normal }) { Image($r('app.media.ui_back')).width(22).height(22) }
          .width(44).height(44).backgroundColor(Color.Transparent).accessibilityText('返回设置').onClick(this.onBack)
        Text('任务通知').fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
      }.width('100%').padding(8)
      Scroll() {
        Column({ space: 16 }) {
          Text('在线任务提醒').fontSize(18).fontWeight(FontWeight.Medium).width('100%')
          Text('连接期间收到任务完成或结束事件时，在通知中心提醒你。正在查看的会话不会重复提醒。')
            .fontSize(15).lineHeight('23fp').width('100%')
          Button(this.busy ? '正在更新…' : this.notificationsEnabled ? '关闭任务通知' : '启用任务通知')
            .width('100%').constraintSize({ minHeight: 48 }).borderRadius(24)
            .backgroundColor(this.notificationsEnabled ? $r('app.color.surface') : $r('app.color.primary'))
            .fontColor(this.notificationsEnabled ? $r('app.color.ink') : Color.White)
            .enabled(!this.busy).onClick(() => { void this.toggle(); })
          if (this.error) { Text(this.error).fontSize(14).width('100%') }
          Column({ space: 8 }) {
            Text('通知状态').fontSize(15).fontWeight(FontWeight.Medium).width('100%')
            Text('系统权限：' + this.permission).fontSize(13).width('100%')
            Text(this.status).fontSize(13).lineHeight('20fp').width('100%')
            if (this.publishedAt) { Text('最近系统接受：' + this.publishedAt).fontSize(13).width('100%') }
            Text(this.tapStatus).fontSize(13).lineHeight('20fp').width('100%')
          }.width('100%').padding(14).backgroundColor($r('app.color.surface')).borderRadius(12)
            .alignItems(HorizontalAlign.Start)

          Text('通知仅显示通用状态，不包含任务、消息或秘密内容。点击通知会进入对应环境的会话。')
            .fontSize(13).lineHeight('20fp').fontColor($r('app.color.muted')).width('100%')
          Text('此功能不是云推送。应用断开连接或被系统暂停后不会收到新的任务通知；重新连接也不会补发历史通知。')
            .fontSize(13).lineHeight('20fp').fontColor($r('app.color.muted')).width('100%')
        }.width('100%').padding(20).alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1).align(Alignment.TopStart)
    }.width('100%').height('100%').backgroundColor($r('app.color.canvas')).foregroundColor($r('app.color.ink'))
  }
}
