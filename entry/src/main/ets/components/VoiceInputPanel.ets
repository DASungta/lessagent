import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { VoiceInput } from '../services/VoiceInput';
import { VoiceState } from '../protocol/Voice';

@Component
export struct VoiceInputPanel {
  onBack: () => void = () => {};
  onInsert: (value: string) => void = () => {};
  @StorageLink('t3Foreground') @Watch('foregroundChanged') foreground: boolean = true;
  @State phase: string = 'idle';
  @State transcript: string = '';
  @State message: string = '仅设备端中文识别，确认后加入草稿，不会自动发送。';
  private voice: VoiceInput = new VoiceInput();
  private generation: number = 0;
  private alive: boolean = false;

  aboutToAppear(): void { this.alive = true; }
  aboutToDisappear(): void { this.alive = false; void this.cancel(); }
  private foregroundChanged(): void {
    if (!this.foreground) { void this.cancel(); this.message = '已停止语音输入，返回前台后可重新开始。'; }
  }
  private async cancel(): Promise<void> {
    ++this.generation; this.phase = 'idle'; this.transcript = '';
    try { await this.voice.cancel(); } catch (_) { this.message = '停止麦克风失败，请退出应用检查系统麦克风指示'; }
  }
  private async start(): Promise<void> {
    if (!this.foreground || this.phase === 'preparing' || this.phase === 'recording' || this.phase === 'finishing') return;
    const generation = ++this.generation;
    this.phase = 'preparing'; this.transcript = ''; this.message = '正在检查麦克风权限…';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const permission = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, ['ohos.permission.MICROPHONE']);
      if (generation !== this.generation || !this.alive || !this.foreground) return;
      if (permission.authResults[0] !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        this.phase = 'error'; this.message = '未获得麦克风权限。可以继续键盘输入，或在系统设置中允许麦克风后重试。'; return;
      }
      await this.voice.start((state: VoiceState) => {
        if (generation !== this.generation || !this.alive || !this.foreground) return;
        this.phase = state.phase; this.transcript = state.text; this.message = state.message;
      });
    } catch (_) { if (generation === this.generation) { this.phase = 'error'; this.message = '无法启动语音输入，请使用键盘或重试'; } }
  }

  build() {
    Column({ space: 16 }) {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Circle }) { Image($r('app.media.ui_back')).width(22).height(22) }
          .width(44).height(44).backgroundColor(Color.Transparent).accessibilityText('取消语音输入并返回')
          .onClick(() => { void this.cancel(); this.onBack(); })
        Text('语音输入').fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
      }.width('100%')
      Text(this.phase === 'recording' ? '正在聆听…' : this.message).fontSize(14)
        .fontColor($r('app.color.muted')).width('100%')
      TextArea({ placeholder: '识别文字会显示在这里，可在完成后修改', text: this.transcript })
        .layoutWeight(1).width('100%').fontSize(16).fontColor($r('app.color.ink'))
        .backgroundColor($r('app.color.surface')).borderRadius(12)
        .enabled(this.phase === 'ready').onChange((value: string) => { this.transcript = value; })
      if (this.phase === 'recording') {
        Button('结束录音').width('100%').constraintSize({ minHeight: 48 })
          .backgroundColor($r('app.color.primary')).fontColor($r('app.color.on_primary'))
          .onClick(() => { void this.voice.finish(); })
      } else if (this.phase === 'preparing' || this.phase === 'finishing') {
        LoadingProgress().width(28).height(28)
      } else {
        Button(this.phase === 'ready' ? '重新录入' : '开始语音输入').width('100%').constraintSize({ minHeight: 48 })
          .backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).onClick(() => { void this.start(); })
      }
      Button('加入草稿').width('100%').constraintSize({ minHeight: 48 })
        .backgroundColor($r('app.color.primary')).fontColor($r('app.color.on_primary'))
        .enabled(this.phase === 'ready' && !!this.transcript.trim())
        .onClick(() => {
          const value = this.transcript.trim();
          if (this.phase !== 'ready' || !value) return;
          this.phase = 'idle'; this.transcript = ''; this.onInsert(value);
        })
      Button('取消').width('100%').constraintSize({ minHeight: 44 }).backgroundColor(Color.Transparent)
        .fontColor($r('app.color.ink')).onClick(() => { void this.cancel(); this.onBack(); })
    }.width('100%').height('100%').padding(16).foregroundColor($r('app.color.ink')).backgroundColor($r('app.color.canvas'))
  }
}
