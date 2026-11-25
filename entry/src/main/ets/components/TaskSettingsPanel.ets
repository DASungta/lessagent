import { TopBar } from './ui/TopBar';
import { GroupCard } from './ui/GroupCard';
import { FormRow } from './ui/FormRow';
import { AppButton } from './ui/AppButton';
import { StatusBadge } from './ui/StatusBadge';
import { SectionHeader } from './ui/SectionHeader';
import { ProviderLogo } from './ui/ProviderLogo';
import { FontSize, LineHeight, Radius, Sizes, Space, Weight } from '../common/Theme';
import { ModelChoice } from '../protocol/Core';
import {
  ModelSelection, OptionSelection, TaskSettings, ModelOptionControl, ModelOptionValue,
  ModelFavoriteEntry, modelFavoriteKey, parseModelFavorites, serverHasModelFavorites,
  optionControls, supportedModes, interactionModes
} from '../protocol/Composer';
import { record } from '../protocol/Wire';

@Component
export struct TaskSettingsPanel {
  @Prop models: ModelChoice[] = [];
  @Prop config: Record<string, Object> = {};
  @Prop localFavorites: ModelFavoriteEntry[] = [];
  @Prop @Watch('syncSettings') settings: TaskSettings;
  @Prop busy: boolean = false;
  @Prop status: string = '';
  onSave: (value: TaskSettings) => void = () => {};
  onClose: () => void = () => {};
  onInstall: (instanceId: string) => void = () => {};
  onAuth: (instanceId: string) => void = () => {};
  onRefreshProviders: (instanceId: string) => void = () => {};
  onToggleFavorite: (provider: string, model: string, favorite: boolean) => Promise<void> = async () => {};
  @State selected: ModelSelection = { instanceId: '', model: '' };
  @State permission: string = 'approval-required';
  @State interaction: string = 'default';
  @State query: string = '';
  @State favoritesOnly: boolean = false;
  @State providerFilter: string = '';
  @State showLegacy: boolean = false;
  @State optimisticFavorites: Record<string, boolean> = {};
  @State providerExpanded: boolean = false;

  /** Synchronizes local picker state when the parent updates `settings`. */
  private syncSettings(): void {
    this.selected = { instanceId: this.settings.modelSelection.instanceId, model: this.settings.modelSelection.model,
      options: (this.settings.modelSelection.options || []).slice() };
    this.permission = this.settings.runtimeMode;
    this.interaction = this.settings.interactionMode;
  }
  aboutToAppear(): void {
    this.syncSettings();
  }
  private controls(): ModelOptionControl[] { return optionControls(this.config, this.selected); }
  private modes(): string[] { return supportedModes(this.config, this.selected); }
  private effectiveFavoriteKeys(): Set<string> {
    const source = serverHasModelFavorites(this.config) ? parseModelFavorites(this.config) : this.localFavorites;
    const keys: Set<string> = new Set();
    for (const item of source) {
      keys.add(modelFavoriteKey(item.provider, item.model));
    }
    for (const key of Object.keys(this.optimisticFavorites)) {
      if (this.optimisticFavorites[key]) keys.add(key);
      else keys.delete(key);
    }
    return keys;
  }
  private isFavorite(model: ModelChoice): boolean {
    return this.effectiveFavoriteKeys().has(modelFavoriteKey(model.instanceId, model.model));
  }
  private hasLegacyModels(): boolean {
    return this.models.some((model: ModelChoice) => model.legacy === true);
  }
  private allProviderIds(): string[] {
    const ids: string[] = [];
    for (const m of this.models) {
      if (!ids.includes(m.instanceId)) ids.push(m.instanceId);
    }
    return ids;
  }
  private visibleModels(): ModelChoice[] {
    const query = this.query.trim().toLowerCase();
    const favs = this.effectiveFavoriteKeys();
    return this.models.filter((model: ModelChoice) => {
      if (this.providerFilter && model.instanceId !== this.providerFilter) return false;
      const isSelected = this.selected.instanceId === model.instanceId && this.selected.model === model.model;
      if (!this.showLegacy && model.legacy === true && !isSelected) return false;
      if (model.hidden === true && !isSelected) return false;
      if (this.favoritesOnly && !favs.has(modelFavoriteKey(model.instanceId, model.model))) return false;
      if (query) {
        const hay = (model.label + ' ' + model.model + ' ' + this.providerLabel(model.instanceId)).toLowerCase();
        if (!hay.includes(query)) return false;
      }
      return true;
    });
  }
  private toggleFavorite(model: ModelChoice): void {
    const key = modelFavoriteKey(model.instanceId, model.model);
    const nextValue = !this.isFavorite(model);
    const nextMap: Record<string, boolean> = {};
    for (const k of Object.keys(this.optimisticFavorites)) nextMap[k] = this.optimisticFavorites[k];
    nextMap[key] = nextValue;
    this.optimisticFavorites = nextMap;
    void this.onToggleFavorite(model.instanceId, model.model, nextValue).catch(() => {
      const revert: Record<string, boolean> = {};
      for (const k of Object.keys(this.optimisticFavorites)) {
        if (k !== key) revert[k] = this.optimisticFavorites[k];
      }
      this.optimisticFavorites = revert;
    });
  }
  private providers(): Record<string, Object>[] {
    if (this.config.providers === undefined) return [];
    return (this.config.providers as Object[]).map((value: Object): Record<string, Object> => record(value));
  }
  private providerLabel(instanceId: string): string {
    const provider = this.providers().find((row: Record<string, Object>) => row.instanceId === instanceId);
    return provider && typeof provider.displayName === 'string' ? provider.displayName : instanceId;
  }
  private providerDriver(instanceId: string): string {
    const provider = this.providers().find((row: Record<string, Object>) => row.instanceId === instanceId);
    return provider && typeof provider.driver === 'string' && provider.driver ? provider.driver : instanceId;
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

      Column({ space: 0 }) {
        Row({ space: Space.xs }) {
          Image($r('app.media.ui_search')).width(16).height(16).opacity(0.6).accessibilityLevel('no')
          TextInput({ placeholder: '搜索模型或 Provider', text: this.query })
            .layoutWeight(1).height(40).fontSize(FontSize.body).fontColor($r('app.color.ink'))
            .placeholderColor($r('app.color.placeholder')).backgroundColor(Color.Transparent).padding(0)
            .enabled(!this.busy).onChange((value: string) => this.query = value)
        }
        .width('100%').padding({ left: Space.sm, right: Space.sm }).backgroundColor($r('app.color.card'))
        .borderRadius(Radius.button).margin({ top: Space.xxs, bottom: Space.xs }).alignItems(VerticalAlign.Center)

        Scroll() {
          Row({ space: Space.xs }) {
            Button(this.favoritesOnly ? '★ 仅收藏' : '☆ 仅收藏')
              .height(32)
              .fontSize(FontSize.caption)
              .fontWeight(this.favoritesOnly ? Weight.semibold : Weight.regular)
              .fontColor(this.favoritesOnly ? $r('app.color.on_prominent') : $r('app.color.ink'))
              .backgroundColor(this.favoritesOnly ? $r('app.color.prominent') : $r('app.color.card'))
              .borderRadius(Radius.full)
              .padding({ left: 12, right: 12 })
              .accessibilityText(this.favoritesOnly ? '仅收藏模型，已开启' : '仅收藏模型')
              .onClick(() => { this.favoritesOnly = !this.favoritesOnly; })

            if (this.allProviderIds().length > 1) {
              Button('全部 Provider')
                .height(32)
                .fontSize(FontSize.caption)
                .fontWeight(this.providerFilter === '' ? Weight.semibold : Weight.regular)
                .fontColor(this.providerFilter === '' ? $r('app.color.primary_text') : $r('app.color.ink'))
                .backgroundColor(this.providerFilter === '' ? $r('app.color.info_bg') : $r('app.color.card'))
                .borderRadius(Radius.full)
                .padding({ left: 12, right: 12 })
                .onClick(() => { this.providerFilter = ''; })
              ForEach(this.allProviderIds(), (pid: string) => {
                Button(this.providerLabel(pid))
                  .height(32)
                  .fontSize(FontSize.caption)
                  .fontWeight(this.providerFilter === pid ? Weight.semibold : Weight.regular)
                  .fontColor(this.providerFilter === pid ? $r('app.color.primary_text') : $r('app.color.ink'))
                  .backgroundColor(this.providerFilter === pid ? $r('app.color.info_bg') : $r('app.color.card'))
                  .borderRadius(Radius.full)
                  .padding({ left: 12, right: 12 })
                  .onClick(() => { this.providerFilter = this.providerFilter === pid ? '' : pid; })
              }, (pid: string) => pid)
            }

            if (this.hasLegacyModels()) {
              Button(this.showLegacy ? '含旧模型' : '显示旧模型')
                .height(32)
                .fontSize(FontSize.caption)
                .fontColor(this.showLegacy ? $r('app.color.primary_text') : $r('app.color.muted'))
                .backgroundColor(this.showLegacy ? $r('app.color.info_bg') : $r('app.color.card'))
                .borderRadius(Radius.full)
                .padding({ left: 12, right: 12 })
                .onClick(() => { this.showLegacy = !this.showLegacy; })
            }
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .margin({ bottom: Space.xs })
      }
      .width('100%')
      .padding({ left: Space.sm, right: Space.sm })

      Scroll() {
        Column({ space: 0 }) {

          if (!this.visibleProviderIds().length) {
            GroupCard() {
              FormRow({
                kind: 'value',
                label: this.favoritesOnly && !this.providerFilter && !this.query.trim() ? '暂无收藏模型' : '没有匹配的模型',
                value: '',
                valueMuted: true,
                chevron: false,
                isFirst: true
              })
            }
          } else {
            ForEach(this.visibleProviderIds(), (providerId: string) => {
              Column() {
                Row({ space: 6 }) {
                  ProviderLogo({ driver: this.providerDriver(providerId), logoSize: 14 })
                  Text(this.providerLabel(providerId))
                    .fontSize(FontSize.caption)
                    .lineHeight(LineHeight.caption)
                    .fontColor($r('app.color.muted'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
                .padding({ left: Space.xxs, right: Space.xxs, bottom: 5 })
                Column() {
                  ForEach(this.modelsForProvider(providerId), (model: ModelChoice, index: number) => {
                    Row({ space: 0 }) {
                      Column() {
                        FormRow({
                          kind: 'choice',
                          label: model.model,
                          subtitle: model.label + (model.legacy ? ' · 旧模型' : ''),
                          checked: this.selected.instanceId === model.instanceId && this.selected.model === model.model,
                          disabled: this.busy,
                          isFirst: true,
                          onTap: () => {
                            this.selected = { instanceId: model.instanceId, model: model.model, options: [] };
                            const modes = this.modes();
                            if (!modes.includes(this.permission)) this.permission = modes[0] || '';
                            if (!interactionModes(this.config, this.selected).includes(this.interaction)) this.interaction = 'default';
                          }
                        })
                      }.layoutWeight(1)
                      Button({ type: ButtonType.Normal, stateEffect: true }) {
                        Text(this.isFavorite(model) ? '★' : '☆')
                          .fontSize(18)
                          .lineHeight('22fp')
                          .fontColor(this.isFavorite(model) ? $r('app.color.warning') : $r('app.color.muted'))
                          .textAlign(TextAlign.Center)
                      }
                        .width(44)
                        .height(44)
                        .padding(0)
                        .margin({ right: 4 })
                        .flexShrink(0)
                        .backgroundColor(Color.Transparent)
                        .borderRadius(Radius.tool)
                        .enabled(!this.busy)
                        .accessibilityText((this.isFavorite(model) ? '取消收藏 ' : '收藏 ') + model.model)
                        .onClick(() => this.toggleFavorite(model))
                    }
                    .width('100%')
                    .alignItems(VerticalAlign.Center)
                    .border({ width: { top: index === 0 ? 0 : Sizes.hairline }, color: { top: $r('app.color.separator') } })
                  }, (model: ModelChoice) => model.instanceId + ':' + model.model)
                }
                .width('100%')
                .backgroundColor($r('app.color.card'))
                .borderRadius(Radius.card)
                .clip(true)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding({ top: Space.sm })
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
                    ProviderLogo({ driver: String(provider.driver || provider.instanceId || ''), logoSize: 16 })
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
