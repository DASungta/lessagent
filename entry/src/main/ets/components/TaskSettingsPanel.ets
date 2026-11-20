import { TopBar } from './ui/TopBar';
import { GroupCard } from './ui/GroupCard';
import { FormRow } from './ui/FormRow';
import { AppButton } from './ui/AppButton';
import { StatusBadge } from './ui/StatusBadge';
import { SectionHeader } from './ui/SectionHeader';
import { FontSize, LineHeight, Radius, Sizes, Space, Weight } from '../common/Theme';
import { ModelChoice } from '../protocol/Core';
import { ModelSelection, OptionSelection, TaskSettings, ModelOptionControl, ModelOptionValue, optionControls, supportedModes, interactionModes } from '../protocol/Composer';
import { record } from '../protocol/Wire';

@Component
export struct TaskSettingsPanel {
  @Prop models: ModelChoice[] = [];
  @Prop config: Record<string, Object> = {};
  @Prop settings: TaskSettings;
  @Prop busy: boolean = false;
  @Prop status: string = '';
  onSave: (value: TaskSettings) => void = () => {};
  onClose: () => void = () => {};
  onInstall: (instanceId: string) => void = () => {};
  onAuth: (instanceId: string) => void = () => {};
  onRefreshProviders: (instanceId: string) => void = () => {};
  @State selected: ModelSelection = { instanceId: '', model: '' };
  @State permission: string = 'approval-required';
  @State interaction: string = 'default';
  @State query: string = '';
  @State providerExpanded: boolean = false;

  aboutToAppear(): void {
    this.selected = { instanceId: this.settings.modelSelection.instanceId, model: this.settings.modelSelection.model,
      options: (this.settings.modelSelection.options || []).slice() };
    this.permission = this.settings.runtimeMode; this.interaction = this.settings.interactionMode;
  }
  private controls(): ModelOptionControl[] { return optionControls(this.config, this.selected); }
  private modes(): string[] { return supportedModes(this.config, this.selected); }
  private visibleModels(): ModelChoice[] {
    const query = this.query.trim().toLowerCase();
    return query ? this.models.filter((model: ModelChoice) => model.label.toLowerCase().includes(query)) : this.models;
  }
  private providers(): Record<string, Object>[] {
    if (this.config.providers === undefined) return [];
    return (this.config.providers as Object[]).map((value: Object): Record<string, Object> => record(value));
  }
  private providerLabel(instanceId: string): string {
    const provider = this.providers().find((row: Record<string, Object>) => row.instanceId === instanceId);
    return provider && typeof provider.displayName === 'string' ? provider.displayName : instanceId;
  }
  private chooseOption(id: string, value: string | boolean): void {
    const options = (this.selected.options || []).filter((option: OptionSelection) => option.id !== id);
    options.push({ id, value });
    this.selected = { instanceId: this.selected.instanceId, model: this.selected.model, options };
  }
  private unsetOption(id: string): void {
    this.selected = { instanceId: this.selected.instanceId, model: this.selected.model,
      options: (this.selected.options || []).filter((option: OptionSelection) => option.id !== id) };
  }
  private optionValue(id: string): string | boolean | undefined {
    return this.selected.options?.find((option: OptionSelection) => option.id === id)?.value;
  }
  private visibleProviderIds(): string[] {
    const ids: string[] = [];
    for (const m of this.visibleModels()) {
      if (!ids.includes(m.instanceId)) ids.push(m.instanceId);
    }
    return ids;
  }
  private modelsForProvider(instanceId: string): ModelChoice[] {
    return this.visibleModels().filter((model: ModelChoice) => model.instanceId === instanceId);
  }
  build() {
    Column({ space: 0 }) {
      TopBar({
        title: '模型与选项',
        showBack: true,
        closeStyle: true,
        backLabel: '取消',
        onBack: () => { if (!this.busy) this.onClose(); }
      }) {
        AppButton({
          label: '保存',
          kind: 'text',
          disabled: this.busy || !this.modes().includes(this.permission) || !this.selected.model,
          onTap: () => this.onSave({ modelSelection: this.selected, runtimeMode: this.permission, interactionMode: this.interaction })
        })
      }

      Scroll() {
        Column({ space: 0 }) {
          Row({ space: Space.xs }) {
            Image($r('app.media.ui_search')).width(16).height(16).opacity(0.6).accessibilityLevel('no')
            TextInput({ placeholder: '搜索模型或 Provider', text: this.query })
              .layoutWeight(1).height(40).fontSize(FontSize.body).fontColor($r('app.color.ink'))
              .placeholderColor($r('app.color.placeholder')).backgroundColor(Color.Transparent).padding(0)
              .enabled(!this.busy).onChange((value: string) => this.query = value)
          }
          .width('100%').padding({ left: Space.sm, right: Space.sm }).backgroundColor($r('app.color.card'))
          .borderRadius(Radius.button).margin({ top: Space.xxs, bottom: Space.xxs }).alignItems(VerticalAlign.Center)

          if (!this.visibleProviderIds().length) {
            GroupCard() {
              FormRow({ kind: 'value', label: '没有匹配的模型', value: '', valueMuted: true, chevron: false, isFirst: true })
            }
          } else {
            ForEach(this.visibleProviderIds(), (providerId: string) => {
              GroupCard({ title: this.providerLabel(providerId) }) {
                ForEach(this.modelsForProvider(providerId), (model: ModelChoice, index: number) => {
                  FormRow({
                    kind: 'choice',
                    label: model.model,
                    subtitle: model.label,
                    checked: this.selected.instanceId === model.instanceId && this.selected.model === model.model,
                    disabled: this.busy,
                    isFirst: index === 0,
                    onTap: () => {
                      this.selected = { instanceId: model.instanceId, model: model.model, options: [] };
                      const modes = this.modes();
                      if (!modes.includes(this.permission)) this.permission = modes[0] || '';
                      if (!interactionModes(this.config, this.selected).includes(this.interaction)) this.interaction = 'default';
                    }
                  })
                }, (model: ModelChoice) => model.instanceId + ':' + model.model)
              }
            }, (providerId: string) => providerId)
          }

          GroupCard({ title: '运行选项' }) {
            ForEach(this.controls(), (control: ModelOptionControl, index: number) => {
              if (control.type === 'boolean') {
                FormRow({
                  kind: 'switch',
                  label: control.label,
                  subtitle: this.optionValue(control.id) === undefined ? '使用默认值' : this.optionValue(control.id) === true ? '已开启' : '已关闭',
                  checked: this.optionValue(control.id) === true,
                  disabled: this.busy,
                  isFirst: index === 0,
                  onToggle: (value: boolean) => this.chooseOption(control.id, value)
                })
              } else {
                Column({ space: Space.xxs }) {
                  Row({ space: 10 }) {
                    Text(control.label).fontSize(FontSize.body).fontColor($r('app.color.ink')).layoutWeight(1)
                    AppButton({
                      label: '默认', kind: 'text', disabled: this.busy,
                      onTap: () => this.unsetOption(control.id)
                    })
                  }.width('100%').alignItems(VerticalAlign.Center)
                  Select(control.choices.map((choice: ModelOptionValue): SelectOption => { return { value: choice.label }; }))
                    .value(control.choices.find((choice: ModelOptionValue) => choice.id === this.optionValue(control.id))?.label || '默认')
                    .width('100%').constraintSize({ minHeight: 38 }).enabled(!this.busy)
                    .backgroundColor($r('app.color.group')).fontColor($r('app.color.ink'))
                    .onSelect((idx: number) => this.chooseOption(control.id, control.choices[idx].id))
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
                .constraintSize({ minHeight: Sizes.formRowMin })
                .justifyContent(FlexAlign.Center)
                .border({ width: { top: index === 0 ? 0 : Sizes.hairline }, color: { top: $r('app.color.separator') } })
              }
            }, (control: ModelOptionControl) => control.id)

            Row({ space: 10 }) {
              Text('权限模式').fontSize(FontSize.body).fontColor($r('app.color.ink')).flexShrink(0)
              Select(this.modes().map((mode: string): SelectOption => { return { value: mode }; }))
                .value(this.permission).layoutWeight(1).constraintSize({ minHeight: 38 }).enabled(!this.busy)
                .backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
                .onSelect((index: number) => this.permission = this.modes()[index])
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
            .constraintSize({ minHeight: Sizes.formRowMin })
            .border({ width: { top: this.controls().length === 0 ? 0 : Sizes.hairline }, color: { top: $r('app.color.separator') } })

            Row({ space: 10 }) {
              Text('交互模式').fontSize(FontSize.body).fontColor($r('app.color.ink')).flexShrink(0)
              Select(interactionModes(this.config, this.selected).map((mode: string): SelectOption => { return { value: mode }; }))
                .value(this.interaction).layoutWeight(1).constraintSize({ minHeight: 38 }).enabled(!this.busy)
                .backgroundColor(Color.Transparent).fontColor($r('app.color.ink'))
                .onSelect((index: number) => this.interaction = interactionModes(this.config, this.selected)[index])
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
            .constraintSize({ minHeight: Sizes.formRowMin })
            .border({ width: { top: Sizes.hairline }, color: { top: $r('app.color.separator') } })
          }

          Column() {
            SectionHeader({
              title: 'Provider 状态',
              collapsible: true,
              collapsed: !this.providerExpanded,
              onToggle: () => { this.providerExpanded = !this.providerExpanded; }
            })
          }.width('100%').padding({ top: Space.xs })

          if (this.providerExpanded) {
            GroupCard() {
              ForEach(this.providers(), (provider: Record<string, Object>, index: number) => {
                Column({ space: Space.xs }) {
                  Row({ space: Space.xs }) {
                    Text(String(provider.displayName || provider.instanceId))
                      .fontSize(FontSize.body).fontWeight(Weight.medium).fontColor($r('app.color.ink')).layoutWeight(1)
                    StatusBadge({
                      text: String(provider.status || 'unknown') + (provider.installed === false ? ' · 未安装' : ''),
                      tone: provider.installed === false ? 'warning' : provider.status === 'ready' ? 'success' : 'neutral'
                    })
                  }.width('100%').alignItems(VerticalAlign.Center)
                  Text(String(provider.message || '') + ' · ' + (Array.isArray(provider.models) ? (provider.models as Object[]).length : 0) + ' 个模型')
                    .fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted')).width('100%').maxLines(3)
                  Row({ space: Space.xs }) {
                    if (provider.installed === false) {
                      AppButton({ label: '安装', kind: 'secondary', compact: true, disabled: this.busy, onTap: () => this.onInstall(String(provider.instanceId)) })
                    }
                    AppButton({ label: '刷新', kind: 'secondary', compact: true, disabled: this.busy, onTap: () => this.onRefreshProviders(String(provider.instanceId)) })
                    if (provider.setup !== undefined && provider.setup !== null &&
                      record(provider.setup).canAuthenticate !== false) {
                      AppButton({ label: '登录', kind: 'secondary', compact: true, disabled: this.busy, onTap: () => this.onAuth(String(provider.instanceId)) })
                    }
                  }.width('100%')
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                .padding({ left: 14, right: 14, top: Space.xs, bottom: Space.xs })
                .constraintSize({ minHeight: Sizes.formRowMin })
                .justifyContent(FlexAlign.Center)
                .border({ width: { top: index === 0 ? 0 : Sizes.hairline }, color: { top: $r('app.color.separator') } })
              }, (provider: Record<string, Object>) => String(provider.instanceId))
            }
          }

          if (this.status) {
            Text(this.status).fontSize(FontSize.caption).lineHeight(LineHeight.caption).fontColor($r('app.color.muted'))
              .padding({ left: Space.xxs, right: Space.xxs, top: Space.sm }).width('100%')
          }
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: Space.sm, right: Space.sm, bottom: Space.lg })
      }.layoutWeight(1).width('100%').align(Alignment.TopStart)
    }.width('100%').height('100%').backgroundColor($r('app.color.group')).foregroundColor($r('app.color.ink'))
  }
}
