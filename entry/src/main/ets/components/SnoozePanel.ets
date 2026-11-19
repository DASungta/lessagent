import {
  ScopedThread, SnoozePreset, SnoozePresetSetting, resolveCustomSnooze, resolveSnoozePresets
} from '../protocol/Projects';

function pad(value: number): string { return value < 10 ? '0' + value : String(value); }
function localDate(value: Date): string {
  return value.getFullYear() + '-' + pad(value.getMonth() + 1) + '-' + pad(value.getDate());
}
function localTime(value: Date): string { return pad(value.getHours()) + ':' + pad(value.getMinutes()); }

@Component
export struct SnoozePanel {
  thread: ScopedThread | undefined = undefined;
  @Prop settings: SnoozePresetSetting[] = [];
  @State presets: SnoozePreset[] = [];
  @State amount: string = '2';
  @State unit: string = 'hours';
  @State date: string = localDate(new Date(Date.now() + 3600000));
  @State time: string = localTime(new Date(Date.now() + 3600000));
  @State error: string = '';
  @State busy: boolean = false;
  onClose: () => void = () => {};
  onSnooze: (thread: ScopedThread, snoozedUntil: string) => Promise<void> = async () => {};

  aboutToAppear(): void {
    this.presets = resolveSnoozePresets(new Date(), this.settings);
  }
  private async submit(value: string): Promise<void> {
    if (!this.thread || this.busy) return;
    this.error = '';
    if (!value || !Number.isFinite(Date.parse(value)) || Date.parse(value) <= Date.now()) {
      this.error = '请选择晚于现在的时间';
      return;
    }
    this.busy = true;
    try { await this.onSnooze(this.thread, value); }
    catch (error) { this.error = (error as Error).message; }
    finally { this.busy = false; }
  }
  private submitCustom(): void {
    const value = resolveCustomSnooze({
      mode: 'date', date: this.date, time: this.time, amount: this.amount, unit: this.unit
    }, new Date());
    if (!value) { this.error = '请输入有效的未来日期和时间'; return; }
    void this.submit(value);
  }
  private submitDuration(): void {
    const value = resolveCustomSnooze({
      mode: 'duration', date: this.date, time: this.time, amount: this.amount, unit: this.unit
    }, new Date());
    if (!value) { this.error = '请输入正数时长'; return; }
    void this.submit(value);
  }

  build() {
    Column({ space: 14 }) {
      Row() {
        Button('×').width(44).height(44).backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
          .accessibilityText('关闭暂缓').onClick(this.onClose)
        Text('暂缓会话').fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
      }.width('100%')
      if (this.thread) {
        Text(this.thread.label).fontSize(13).fontColor($r('app.color.muted')).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      }
      Scroll() {
        Column({ space: 10 }) {
          Text('快捷时间').fontSize(12).fontColor($r('app.color.muted')).width('100%')
          ForEach(this.presets, (preset: SnoozePreset) => {
            Button({ type: ButtonType.Normal }) {
              Row() {
                Text(preset.label).fontSize(15).fontColor($r('app.color.ink'))
                Blank()
                Text(preset.whenLabel).fontSize(12).fontColor($r('app.color.muted'))
              }.width('100%').padding({ left: 4, right: 4 })
            }.width('100%').height(48).backgroundColor($r('app.color.surface')).borderRadius(12)
              .enabled(!this.busy).onClick(() => void this.submit(preset.snoozedUntil))
          }, (preset: SnoozePreset) => preset.id)
          Divider().color($r('app.color.border'))
          Text('自定义时间').fontSize(12).fontColor($r('app.color.muted')).width('100%')
          Row({ space: 8 }) {
            TextInput({ placeholder: 'YYYY-MM-DD', text: this.date }).layoutWeight(3).height(44)
              .fontSize(14).onChange((value: string) => this.date = value).accessibilityText('暂缓日期')
            TextInput({ placeholder: 'HH:mm', text: this.time }).layoutWeight(2).height(44)
              .fontSize(14).onChange((value: string) => this.time = value).accessibilityText('暂缓时间')
          }.width('100%')
          Button('按日期暂缓').height(44).backgroundColor($r('app.color.primary')).fontColor($r('app.color.on_primary'))
            .borderRadius(12).enabled(!this.busy).onClick(() => this.submitCustom())
          Text('或按时长').fontSize(12).fontColor($r('app.color.muted')).width('100%')
          Row({ space: 8 }) {
            TextInput({ placeholder: '2', text: this.amount }).layoutWeight(1).height(44).fontSize(14)
              .type(InputType.Number).onChange((value: string) => this.amount = value).accessibilityText('暂缓时长')
            Select([{ value: '分钟' }, { value: '小时' }, { value: '天' }])
              .value(this.unit === 'minutes' ? '分钟' : this.unit === 'days' ? '天' : '小时')
              .onSelect((index: number) => this.unit = index === 0 ? 'minutes' : index === 2 ? 'days' : 'hours')
              .height(44).layoutWeight(1)
          }.width('100%')
          Button('按时长暂缓').height(44).backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink'))
            .borderRadius(12).enabled(!this.busy).onClick(() => this.submitDuration())
          if (this.error) { Text(this.error).fontSize(13).fontColor($r('app.color.danger')).width('100%') }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1)
    }.width('100%').height('100%').padding(20).foregroundColor($r('app.color.ink'))
  }
}
