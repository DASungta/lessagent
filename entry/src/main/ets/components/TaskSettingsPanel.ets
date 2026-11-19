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
  build() {
    Column({ space: 16 }) {
      Row() {
        Button('取消').backgroundColor(Color.Transparent).fontColor($r('app.color.ink')).enabled(!this.busy).onClick(() => this.onClose())
        Text('模型与选项').fontSize(18).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button('保存').enabled(!this.busy && this.modes().includes(this.permission) && !!this.selected.model)
          .backgroundColor(Color.Transparent).fontColor($r('app.color.primary'))
          .onClick(() => this.onSave({ modelSelection: this.selected, runtimeMode: this.permission, interactionMode: this.interaction }))
      }.width('100%')
      Scroll() {
        Column({ space: 16 }) {
          TextInput({ placeholder: '搜索模型或 Provider', text: this.query }).height(38).fontSize(13)
            .backgroundColor($r('app.color.surface')).borderRadius(18).enabled(!this.busy)
            .onChange((value: string) => this.query = value)
          ForEach(this.visibleModels(), (model: ModelChoice, index: number) => {
            if (index === 0 || this.visibleModels()[index - 1].instanceId !== model.instanceId) {
              Text(this.providerLabel(model.instanceId)).fontSize(12).fontColor($r('app.color.muted'))
                .width('100%').padding({ top: index === 0 ? 0 : 8 })
            }
            Button({ type: ButtonType.Normal }) {
              Row({ space: 10 }) {
                Column({ space: 2 }) {
                  Text(model.model).fontSize(14).fontWeight(FontWeight.Medium).width('100%').maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(model.label).fontSize(11).fontColor($r('app.color.muted')).width('100%').maxLines(1)
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                if (this.selected.instanceId === model.instanceId && this.selected.model === model.model) {
                  Text('✓').fontSize(16).fontColor($r('app.color.primary'))
                }
              }.width('100%').padding(10)
            }.width('100%').backgroundColor($r('app.color.surface')).borderRadius(10)
              .enabled(!this.busy).onClick(() => {
                this.selected = { instanceId: model.instanceId, model: model.model, options: [] };
                const modes = this.modes();
                if (!modes.includes(this.permission)) this.permission = modes[0] || '';
                if (!interactionModes(this.config, this.selected).includes(this.interaction)) this.interaction = 'default';
              })
          }, (model: ModelChoice) => model.instanceId + ':' + model.model)
          ForEach(this.controls(), (control: ModelOptionControl) => {
            Column({ space: 8 }) {
              Row() {
                Text(control.label).layoutWeight(1)
                Button('默认').fontSize(12).backgroundColor(Color.Transparent).fontColor($r('app.color.primary'))
                  .enabled(!this.busy).onClick(() => this.unsetOption(control.id))
              }.width('100%')
              if (control.type === 'boolean') {
                Row() {
                  Text(this.optionValue(control.id) === undefined ? '使用默认值' : this.optionValue(control.id) === true ? '开启' : '关闭').layoutWeight(1)
                  Toggle({ type: ToggleType.Switch, isOn: this.optionValue(control.id) === true }).enabled(!this.busy)
                    .onChange((value: boolean) => this.chooseOption(control.id, value))
                }.width('100%')
              } else {
                Select(control.choices.map((choice: ModelOptionValue): SelectOption => { return { value: choice.label }; }))
                  .value(control.choices.find((choice: ModelOptionValue) => choice.id === this.optionValue(control.id))?.label || '默认')
                  .width('100%').enabled(!this.busy)
                  .onSelect((index: number) => this.chooseOption(control.id, control.choices[index].id))
              }
            }.width('100%')
          })
          Text('权限模式').fontSize(13).fontColor($r('app.color.muted')).width('100%')
          Select(this.modes().map((mode: string): SelectOption => { return { value: mode }; }))
            .value(this.permission).width('100%').enabled(!this.busy)
            .onSelect((index: number) => this.permission = this.modes()[index])
          Text('交互模式').fontSize(13).fontColor($r('app.color.muted')).width('100%')
          Select(interactionModes(this.config, this.selected).map((mode: string): SelectOption => { return { value: mode }; })).value(this.interaction).width('100%').enabled(!this.busy)
            .onSelect((index: number) => this.interaction = interactionModes(this.config, this.selected)[index])
          Row() {
            Text('Provider 状态').fontSize(13).fontColor($r('app.color.muted')).layoutWeight(1)
            Button(this.providerExpanded ? '收起' : '展开').backgroundColor(Color.Transparent)
              .fontColor($r('app.color.primary')).height(32).fontSize(11)
              .onClick(() => this.providerExpanded = !this.providerExpanded)
          }.width('100%')
          if (this.providerExpanded) {
            ForEach(this.providers(), (provider: Record<string, Object>) => {
              Column({ space: 5 }) {
                Row() {
                  Text(String(provider.displayName || provider.instanceId)).fontSize(13).fontWeight(FontWeight.Medium).layoutWeight(1)
                  Text(String(provider.status || 'unknown') + (provider.installed === false ? ' · 未安装' : '')).fontSize(11)
                    .fontColor($r('app.color.muted'))
                }.width('100%')
                Text(String(provider.message || '') + ' · ' + (Array.isArray(provider.models) ? (provider.models as Object[]).length : 0) + ' 个模型')
                  .fontSize(11).fontColor($r('app.color.muted')).width('100%').maxLines(3)
                Row({ space: 6 }) {
                  if (provider.installed === false) {
                    Button('安装').height(32).fontSize(11).backgroundColor($r('app.color.surface'))
                      .fontColor($r('app.color.ink')).enabled(!this.busy)
                      .onClick(() => this.onInstall(String(provider.instanceId)))
                  }
                  Button('刷新').height(32).fontSize(11).backgroundColor($r('app.color.surface'))
                    .fontColor($r('app.color.ink')).enabled(!this.busy)
                    .onClick(() => this.onRefreshProviders(String(provider.instanceId)))
                  if (provider.setup !== undefined && provider.setup !== null &&
                    record(provider.setup).canAuthenticate !== false) {
                    Button('登录').height(32).fontSize(11).backgroundColor($r('app.color.surface'))
                      .fontColor($r('app.color.ink')).enabled(!this.busy)
                      .onClick(() => this.onAuth(String(provider.instanceId)))
                  }
                }.width('100%')
              }.padding(9).width('100%').border({ width: 1, color: $r('app.color.border') }).borderRadius(10)
            }, (provider: Record<string, Object>) => String(provider.instanceId))
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).width('100%')
      if (this.status) { Text(this.status).fontSize(12).fontColor($r('app.color.muted')).width('100%') }
    }.padding(20).width('100%').height('100%').foregroundColor($r('app.color.ink'))
  }
}
