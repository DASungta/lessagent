import { TopBar } from './ui/TopBar';
import { GroupCard } from './ui/GroupCard';
import { FormRow } from './ui/FormRow';
import { AppButton } from './ui/AppButton';
import { FontSize, LineHeight, Radius, Sizes, Space } from '../common/Theme';
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
    Column({ space: 0 }) {
      TopBar({
        title: '暂缓会话',
        subtitle: this.thread ? this.thread.label : '',
        showBack: true,
        closeStyle: true,
        backLabel: '关闭暂缓',
        onBack: () => this.onClose()
      })
      Scroll() {
        Column({ space: 0 }) {
          GroupCard({ title: '快捷时间' }) {
            ForEach(this.presets, (preset: SnoozePreset, index: number) => {
              FormRow({
                kind: 'value',
                label: preset.label,
                value: preset.whenLabel,
                valueMuted: true,
                disabled: this.busy,
                isFirst: index === 0,
                onTap: () => { void this.submit(preset.snoozedUntil); }
              })
            }, (preset: SnoozePreset) => preset.id)
          }

          GroupCard({ title: '自定义时间' }) {
            Column() {
              Column({ space: Space.xs }) {
                Row({ space: Space.xs }) {
                  TextInput({ placeholder: 'YYYY-MM-DD', text: this.date }).layoutWeight(3).height(40)
                    .fontSize(FontSize.body).fontColor($r('app.color.ink'))
                    .backgroundColor($r('app.color.group')).borderRadius(Radius.tool).padding({ left: 10, right: 10 })
                    .onChange((value: string) => this.date = value).accessibilityText('暂缓日期')
                  TextInput({ placeholder: 'HH:mm', text: this.time }).layoutWeight(2).height(40)
                    .fontSize(FontSize.body).fontColor($r('app.color.ink'))
                    .backgroundColor($r('app.color.group')).borderRadius(Radius.tool).padding({ left: 10, right: 10 })
                    .onChange((value: string) => this.time = value).accessibilityText('暂缓时间')
                }.width('100%')
                AppButton({
                  label: '按日期暂缓', kind: 'primary', fill: true, compact: true,
                  disabled: this.busy, onTap: () => this.submitCustom()
                })
              }.width('100%')
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
            .constraintSize({ minHeight: Sizes.formRowMin })
            .justifyContent(FlexAlign.Center)
            Column() {
              Column({ space: Space.xs }) {
                Row({ space: Space.xs }) {
                  TextInput({ placeholder: '2', text: this.amount }).layoutWeight(1).height(40)
                    .fontSize(FontSize.body).fontColor($r('app.color.ink'))
                    .backgroundColor($r('app.color.group')).borderRadius(Radius.tool).padding({ left: 10, right: 10 })
                    .type(InputType.Number).onChange((value: string) => this.amount = value).accessibilityText('暂缓时长')
                  Select([{ value: '分钟' }, { value: '小时' }, { value: '天' }])
                    .value(this.unit === 'minutes' ? '分钟' : this.unit === 'days' ? '天' : '小时')
                    .backgroundColor($r('app.color.group')).fontColor($r('app.color.ink'))
                    .onSelect((index: number) => this.unit = index === 0 ? 'minutes' : index === 2 ? 'days' : 'hours')
                    .height(40).layoutWeight(1)
                }.width('100%')
                AppButton({
                  label: '按时长暂缓', kind: 'secondary', fill: true, compact: true,
                  disabled: this.busy, onTap: () => this.submitDuration()
                })
              }.width('100%')
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
            .constraintSize({ minHeight: Sizes.formRowMin })
            .justifyContent(FlexAlign.Center)
            .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
          }

          if (this.error) {
            Text(this.error).fontSize(FontSize.callout).lineHeight(LineHeight.callout).fontColor($r('app.color.danger'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.sm }).width('100%')
          }
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: Space.sm, right: Space.sm, bottom: Space.lg })
      }.width('100%').layoutWeight(1).align(Alignment.TopStart)
    }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
  }
}
