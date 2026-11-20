import { AppButton } from './ui/AppButton';
import { FontSize, LineHeight, Radius, Space } from '../common/Theme';
import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { PairingTarget } from '../protocol/Pairing';
import { PairingScanner } from '../services/PairingScanner';

@Component
export struct PairingScanCard {
  @Prop @Watch('activityChanged') active: boolean = true;
  @StorageLink('t3Foreground') @Watch('activityChanged') foreground: boolean = true;
  @State permitted: boolean = false;
  @State complete: boolean = false;
  @State settingsNeeded: boolean = false;
  @State error: string = '';
  onTarget: (value: PairingTarget) => void = () => {};
  private scanner: PairingScanner = new PairingScanner();
  private controller: XComponentController = new XComponentController();
  private surface: boolean = false;
  private viewWidth: number = 0;
  private viewHeight: number = 0;
  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  aboutToAppear(): void {
    try {
      this.permitted = abilityAccessCtrl.createAtManager().checkAccessTokenSync(this.context().applicationInfo.accessTokenId, 'ohos.permission.CAMERA') === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (_) { this.permitted = false; this.error = '无法读取相机权限，可以手动输入。'; }
  }
  aboutToDisappear(): void { void this.stop(); }
  private activityChanged(): void {
    if (!this.active || !this.foreground) void this.stop();
    else void this.start();
  }
  private async stop(): Promise<void> {
    try { await this.scanner.stop(); } catch (_) { this.error = '相机关闭失败，请退出此页重试'; }
  }
  private async start(): Promise<void> {
    if (!this.active || !this.foreground || !this.permitted || this.complete || !this.surface || !this.viewWidth || !this.viewHeight) return;
    try { await this.scanner.start({ width: this.viewWidth, height: this.viewHeight, surfaceId: this.controller.getXComponentSurfaceId() },
      (target: PairingTarget) => { this.complete = true; this.error = ''; this.onTarget(target); },
      (message: string) => { this.complete = true; this.error = message; });
    } catch (_) { this.error = '相机启动失败，请重试'; }
  }
  private async permission(settings: boolean = false): Promise<void> {
    try {
      const manager = abilityAccessCtrl.createAtManager();
      let granted: boolean;
      if (settings) {
        const grants = await manager.requestPermissionOnSetting(this.context(), ['ohos.permission.CAMERA']);
        granted = grants[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
        this.settingsNeeded = !granted;
      } else {
        const result = await manager.requestPermissionsFromUser(this.context(), ['ohos.permission.CAMERA']);
        granted = result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
        this.settingsNeeded = !granted && result.dialogShownResults?.[0] !== true;
      }
      this.permitted = granted; this.complete = false;
      this.error = granted ? '' : '需要相机权限才能扫码，也可以手动输入。';
    } catch (_) { this.error = '无法获取相机权限，请在系统设置中检查'; this.settingsNeeded = true; }
  }

  build() {
    Column({ space: Space.sm }) {
      if (this.permitted && !this.complete && this.active && this.foreground) {
        XComponent({ id: 't3-pairing-camera', type: XComponentType.SURFACE, controller: this.controller })
          .width('100%').height(220).borderRadius(Radius.card).clip(true)
          .onLoad(() => { this.surface = true; void this.start(); })
          .onDestroy(() => { this.surface = false; void this.stop(); })
          .onAreaChange((_, area: Area) => {
            const width = this.getUIContext().vp2px(Number(area.width)); const height = this.getUIContext().vp2px(Number(area.height));
            if (width !== this.viewWidth || height !== this.viewHeight) { this.viewWidth = width; this.viewHeight = height; void this.start(); }
          })
      } else {
        Text(this.complete && !this.error ? '已识别配对地址' : '扫描 T3 Code 配对二维码')
          .fontSize(FontSize.body).lineHeight(LineHeight.body).fontColor($r('app.color.muted'))
          .width('100%').height(88).textAlign(TextAlign.Center)
      }
      if (!this.permitted) {
        Row({ space: Space.xs }) {
          AppButton({ label: '允许相机扫码', kind: 'secondary', compact: true, disabled: !this.active, onTap: () => { void this.permission(); } })
          if (this.settingsNeeded) {
            AppButton({ label: '打开权限设置', kind: 'secondary', compact: true, disabled: !this.active, onTap: () => { void this.permission(true); } })
          }
        }
      } else if (this.complete) {
        AppButton({
          label: '重新扫描', kind: 'secondary', compact: true, disabled: !this.active,
          onTap: () => { this.complete = false; this.error = ''; }
        })
      }
      if (this.error) {
        Text(this.error).fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.danger')).width('100%')
      }
    }.padding(Space.sm).width('100%').backgroundColor($r('app.color.card')).borderRadius(Radius.card)
  }
}
