import { prepareLocalNotifications, acceptNotificationWant } from '../services/LocalNotifications';
import { acceptIncomingShare } from '../services/ShareInbox';
import { acceptShortcutWant } from '../services/ShortcutInbox';
import { prepareAppearance } from '../services/Appearance';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { acceptPairingLink } from '../services/PairingInbox';
import { acceptCloudCallback } from '../services/CloudCallbackInbox';
import { cloud, prepareCloud } from '../services/CloudManager';
import { UIAbility, Want } from '@kit.AbilityKit';
import { client } from '../services/T3Client';
import { environments, prepareEnvironments } from '../services/EnvironmentRegistry';
import { prepareWorkspacePreferences } from '../services/WorkspacePrefs';
import { prepareDrafts } from '../storage/DraftStore';
import { window, KeyboardAvoidMode } from '@kit.ArkUI';

export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | undefined = undefined;
  private keepAwake: boolean = false;
  onCreate(want: Want): void {
    if (acceptShortcutWant(want)) return;
    this.keepAwake = want.parameters?.['r1KeepAwake'] === true;
    acceptNotificationWant(want);
    void acceptIncomingShare(want);
    acceptPairingLink(want.uri || '');
    acceptCloudCallback(want.uri || '');
  }
  onNewWant(want: Want): void {
    if (acceptShortcutWant(want)) return;
    if (want.parameters?.['r1KeepAwake'] !== undefined) this.keepAwake = want.parameters['r1KeepAwake'] === true;
    acceptNotificationWant(want);
    void acceptIncomingShare(want);
    this.applyKeepAwake(); acceptPairingLink(want.uri || ''); acceptCloudCallback(want.uri || '');
  }
  onWindowStageCreate(stage: window.WindowStage): void {
    prepareEnvironments(this.context.filesDir);
    void prepareLocalNotifications(this.context).catch(() => {
      AppStorage.setOrCreate('t3LocalNotificationError', '通知设置读取失败');
    });
    void prepareDrafts(this.context.filesDir);
    void prepareCloud(this.context, this.context.filesDir).catch((error: Error) => {
      AppStorage.setOrCreate('t3CloudError', error.message || 'T3 Connect 初始化失败');
    });
    void prepareAppearance(this.context).catch(() => {
      hilog.warn(0x0000, 'Appearance', 'Unable to restore appearance');
    }).then(() => prepareWorkspacePreferences(this.context.filesDir)).catch(() => {}).then(() => {
      stage.loadContent('pages/Index').then(() => {
        this.mainWindow = stage.getMainWindowSync(); this.applyKeepAwake();
        this.mainWindow.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
      }).catch(() => {
        client.disconnect('页面加载失败');
      });
    });
  }
  private applyKeepAwake(): void {
    const main = this.mainWindow;
    if (!main) return;
    const enabled = this.keepAwake && AppStorage.get<boolean>('t3Foreground') !== false;
    void main.setWindowKeepScreenOn(enabled).then(() => {
      if (this.keepAwake) hilog.info(0x0000, 'R1KeepAwake', 'windowKeepScreenOn=%{public}s', String(main.getWindowProperties().isKeepScreenOn));
    }).catch(() => { hilog.warn(0x0000, 'R1KeepAwake', 'Unable to change window keep-screen-on'); });
  }
  onForeground(): void {
    AppStorage.setOrCreate('t3Foreground', true); this.applyKeepAwake();
    void cloud?.onForeground().catch(() => {});
    void environments?.resume().catch(() => { client.status = '请解锁后安全重连'; client.onUpdate(); });
  }
  onBackground(): void {
    AppStorage.setOrCreate('t3Foreground', false); this.applyKeepAwake();
    environments?.suspend();
  }
}
