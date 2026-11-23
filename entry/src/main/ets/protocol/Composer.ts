import { compactArray, compactObjects, record, text, objects } from './Wire';
import type { ModelSelection, OptionSelection } from './Wire';

export type { OptionSelection, ModelSelection };
export interface ModelOptionValue { id: string; label: string; }
export interface ModelOptionControl { id: string; label: string; type: string; choices: ModelOptionValue[]; }
export interface TaskSettings {
  modelSelection: ModelSelection;
  runtimeMode: string;
  interactionMode: string;
}
export interface QueuedRun { id: string; messageId: string; text: string; position: number; held: boolean;
  attachmentNames: string[]; }
export const runtimeModes: string[] = ['approval-required', 'auto-accept-edits', 'auto', 'full-access'];

function optionalRecord(value: Object | undefined): Record<string, Object> {
  return value === undefined || value === null ? {} : record(value);
}
const REASONING_OPTION_IDS: string[] = [
  'reasoningEffort', 'reasoning_effort', 'effort', 'reasoning', 'variant',
  'thought_level', 'thinking_level', 'thinkingEffort', 'thinking'
];

function findSelectionOption(selection: ModelSelection | undefined, id: string): string | boolean | undefined {
  if (!selection || !selection.options) return undefined;
  const hit = selection.options.find((option: OptionSelection) => option.id === id);
  return hit ? hit.value : undefined;
}

function sameSelectionModel(a: ModelSelection | undefined, b: ModelSelection | undefined): boolean {
  return !!a && !!b && a.instanceId === b.instanceId && a.model === b.model;
}

function formatFallbackOptionValue(value: string): string {
  const normalized = value.trim().toLowerCase();
  if (!normalized || normalized === 'default') return '';
  if (normalized === 'xhigh' || normalized === 'extra_high' || normalized === 'extra-high' || normalized === 'extra') {
    return 'Extra';
  }
  if (normalized === 'high') return 'High';
  if (normalized === 'medium' || normalized === 'med') return 'Medium';
  if (normalized === 'low') return 'Low';
  if (normalized === 'minimal' || normalized === 'min') return 'Minimal';
  if (normalized === 'max') return 'Max';
  if (normalized === 'none' || normalized === 'off') return 'Off';
  return value.trim().length <= 16 ? value.trim() : '';
}

function isReasoningDescriptorRow(row: Record<string, Object>): boolean {
  return (row.type === 'select' && row.role === 'reasoning') ||
    (typeof row.id === 'string' && REASONING_OPTION_IDS.includes(row.id));
}

function resolveDescriptorOptionValue(row: Record<string, Object>, selection: ModelSelection,
  reportedSelection?: ModelSelection): string | boolean | undefined {
  const id = typeof row.id === 'string' ? row.id : '';
  const explicit = findSelectionOption(selection, id);
  if (explicit !== undefined) return explicit;
  if (sameSelectionModel(selection, reportedSelection)) {
    const reported = findSelectionOption(reportedSelection, id);
    if (reported !== undefined) return reported;
  }
  if (row.type === 'boolean') {
    return typeof row.currentValue === 'boolean' ? row.currentValue : undefined;
  }
  if (typeof row.currentValue === 'string' && row.currentValue) return row.currentValue;
  if (Array.isArray(row.options)) {
    for (const choice of compactObjects(row.options as Object)) {
      if (choice.isDefault === true && typeof choice.id === 'string') return choice.id;
    }
  }
  return undefined;
}

/** 汇总当前模型的推理强度 / 速度等选项摘要，展示在输入栏模型名称旁（如 Extra、High Fast）。 */
export function modelOptionsSummary(config: Object, selection: ModelSelection,
  reportedSelection?: ModelSelection): string {
  if (!selection.instanceId && !selection.model) return '';
  const root = optionalRecord(config);
  const provider = compactObjects(root.providers).find((p: Record<string, Object>) => p.instanceId === selection.instanceId);
  const model = provider ? compactObjects(provider.models).find((m: Record<string, Object>) => m.slug === selection.model) : undefined;
  const caps = model ? optionalRecord(model.capabilities) : {};
  const descriptors = compactObjects(caps.optionDescriptors);

  if (descriptors.length > 0) {
    let fastModeFallbackLabel = '';
    let speedLabel = '';
    let reasoningLabelIndex = -1;
    const labels: string[] = [];

    for (const row of descriptors) {
      const id = typeof row.id === 'string' ? row.id : '';
      const type = typeof row.type === 'string' ? row.type : '';
      const rowLabel = typeof row.label === 'string' ? row.label : id;
      const currentValue = resolveDescriptorOptionValue(row, selection, reportedSelection);

      if (id === 'fastMode' && type === 'boolean') {
        speedLabel = currentValue === true ? 'Fast' : '';
        fastModeFallbackLabel = speedLabel || 'Normal';
        continue;
      }
      if (id === 'ultracode' && type === 'boolean') {
        if (currentValue === true) labels.push(rowLabel);
        continue;
      }
      if (id === 'serviceTier' && type === 'select' && Array.isArray(row.options)) {
        const choices = compactObjects(row.options as Object);
        const fastTier = choices.find((c: Record<string, Object>) => c.label === 'Fast');
        const ultrafastTier = choices.find((c: Record<string, Object>) => c.label === 'Ultrafast');
        if (((fastTier || ultrafastTier) && currentValue === 'default') ||
          (fastTier && currentValue === fastTier.id) ||
          (ultrafastTier && currentValue === ultrafastTier.id)) {
          speedLabel = ultrafastTier && currentValue === ultrafastTier.id ? 'Ultrafast' :
            fastTier && currentValue === fastTier.id ? 'Fast' : '';
          const matchedTier = choices.find((c: Record<string, Object>) => c.id === currentValue);
          fastModeFallbackLabel = matchedTier && typeof matchedTier.label === 'string' ? matchedTier.label : 'Normal';
          continue;
        }
      }

      let label = '';
      if (type === 'boolean') {
        if (typeof currentValue === 'boolean') {
          label = rowLabel + ' ' + (currentValue ? 'On' : 'Off');
        }
      } else if (type === 'select' && typeof currentValue === 'string' && Array.isArray(row.options)) {
        const choices = compactObjects(row.options as Object);
        const matched = choices.find((c: Record<string, Object>) => c.id === currentValue);
        if (matched) {
          label = typeof matched.label === 'string' && matched.label.trim()
            ? matched.label.trim()
            : formatFallbackOptionValue(currentValue);
        }
      }
      if (label) {
        if (reasoningLabelIndex === -1 && type === 'select' && isReasoningDescriptorRow(row)) {
          reasoningLabelIndex = labels.length;
        }
        labels.push(label);
      }
    }

    if (labels.length === 0 && fastModeFallbackLabel) return fastModeFallbackLabel;
    if (speedLabel) {
      if (reasoningLabelIndex >= 0) labels[reasoningLabelIndex] = labels[reasoningLabelIndex] + ' ' + speedLabel;
      else labels.push(speedLabel);
    }
    return labels.join(' · ');
  }

  const fallbackOptions = (selection.options && selection.options.length > 0)
    ? selection.options
    : (sameSelectionModel(selection, reportedSelection) && reportedSelection?.options ? reportedSelection.options : []);
  const fallbackLabels: string[] = [];
  let fallbackSpeed = '';
  for (const option of fallbackOptions) {
    if ((option.id === 'fastMode' || option.id === 'fast') && typeof option.value === 'boolean') {
      if (option.value) fallbackSpeed = 'Fast';
      continue;
    }
    if (typeof option.value === 'string') {
      const formatted = formatFallbackOptionValue(option.value);
      if (formatted) fallbackLabels.push(formatted);
    }
  }
  if (fallbackSpeed) {
    if (fallbackLabels.length > 0) fallbackLabels[0] = fallbackLabels[0] + ' ' + fallbackSpeed;
    else fallbackLabels.push(fallbackSpeed);
  }
  return fallbackLabels.join(' · ');
}

export function optionControls(config: Object, selection: ModelSelection): ModelOptionControl[] {
  const provider = compactObjects(record(config).providers).find((p: Record<string, Object>) => p.instanceId === selection.instanceId);
  const model = provider ? compactObjects(provider.models).find((m: Record<string, Object>) => m.slug === selection.model) : undefined;
  const caps = model ? optionalRecord(model.capabilities) : {};
  return compactArray(caps.optionDescriptors, (value: Object): ModelOptionControl => {
    const row = record(value);
    if (row.type !== 'select' && row.type !== 'boolean') throw new Error('未知模型选项类型');
    return { id: text(row.id), label: text(row.label), type: text(row.type), choices:
      row.type === 'boolean' ? [] : compactArray(objects(row.options), (item: Object): ModelOptionValue => {
        const choice = record(item); return { id: text(choice.id), label: text(choice.label) };
      }) };
  });
}
export function supportedModes(config: Object, selection: ModelSelection): string[] {
  const row = record(config);
  const provider = compactObjects(row.providers).find((p: Record<string, Object>) => p.instanceId === selection.instanceId);
  const policy = optionalRecord(optionalRecord(row.managedPolicy).limits);
  const ceiling = policy.maxRuntimeMode === undefined ? runtimeModes.length - 1 : runtimeModes.indexOf(text(policy.maxRuntimeMode));
  return runtimeModes.filter((mode: string, index: number) => index <= ceiling &&
    (!Array.isArray(provider?.supportedRuntimeModes) || (provider.supportedRuntimeModes as Object[]).includes(mode)));
}
export function interactionModes(config: Object, selection: ModelSelection): string[] {
  const provider = compactObjects(record(config).providers).find((p: Record<string, Object>) => p.instanceId === selection.instanceId);
  return provider?.showInteractionModeToggle === false ? ['default'] : ['default', 'plan'];
}
export function validateTaskSettings(config: Object, projectId: string, settings: TaskSettings): TaskSettings {
  const row = record(config);
  const selection = settings.modelSelection;
  const provider = compactObjects(row.providers).find((p: Record<string, Object>) => p.instanceId === selection.instanceId);
  const overrides = optionalRecord(optionalRecord(optionalRecord(row.settings).projectSettingsOverrides)[projectId]);
  const projectProvider = optionalRecord(optionalRecord(overrides.providerInstances)[selection.instanceId]);
  const allowed = optionalRecord(optionalRecord(optionalRecord(row.managedPolicy).limits).providers).allowedDrivers;
  if (!provider || provider.installed === false || (projectProvider.enabled === undefined ? provider.enabled === false : projectProvider.enabled === false) ||
    (Array.isArray(allowed) && !allowed.includes(provider.driver)) ||
    !compactObjects(provider.models).some((value: Record<string, Object>) => value.slug === selection.model)) {
    throw new Error('模型在当前项目不可用，请重新选择');
  }
  if (!supportedModes(config, selection).includes(settings.runtimeMode)) throw new Error('当前 Provider 或组织策略不允许此权限模式');
  if (!interactionModes(config, selection).includes(settings.interactionMode)) throw new Error('此 Provider 不支持所选交互模式');
  const controls = optionControls(config, selection);
  const seen: string[] = [];
  for (const option of selection.options || []) {
    const control = controls.find((value: ModelOptionControl) => value.id === option.id);
    if (!control || seen.includes(option.id) || (control.type === 'boolean' ? typeof option.value !== 'boolean' :
      !control.choices.some((choice: ModelOptionValue) => choice.id === option.value))) throw new Error('模型选项已失效，请重新选择');
    seen.push(option.id);
  }
  return settings;
}
export function launchTask(commandId: string, threadId: string, messageId: string, projectId: string,
  prompt: string, settings: TaskSettings, attachments: Object[] = [], context: Object | undefined = undefined,
  workspaceStrategy: Object = { type: 'root' }): Object {
  if (!projectId.trim() || (!prompt.trim() && attachments.length === 0) || prompt.length > 1000000) {
    throw new Error('请选择项目并填写任务或添加附件');
  }
  const title = prompt.trim() ? prompt.trim().replace(/\s+/g, ' ').slice(0, 72) : 'New task';
  return { commandId, threadId, projectId, creationSource: 'mobile', title, generateTitle: true,
    modelSelection: settings.modelSelection, runtimeMode: settings.runtimeMode, interactionMode: settings.interactionMode,
    workspaceStrategy, initialMessage: { messageId, text: prompt, attachments,
      ...(context === undefined ? {} : { context }) } };
}
export function queuedRuns(runs: Record<string, Object>[], messages: Record<string, Object>[]): QueuedRun[] {
  return compactArray(
    runs.filter((run: Record<string, Object>) => run.status === 'queued'),
    (entry: Object): QueuedRun => {
      const run = record(entry);
      const messageId = text(run.userMessageId);
      const message = messages.find((row: Record<string, Object>) => row.id === messageId);
      const attachments = message && message.attachments !== undefined ? compactArray(message.attachments, (value: Object) =>
        text(record(value).name)) : [];
      return { id: text(run.id), messageId, text: message && typeof message.text === 'string' ? message.text : '',
        position: typeof run.queuePosition === 'number' ? run.queuePosition : Number.MAX_SAFE_INTEGER,
        held: run.queueHeld === true, attachmentNames: attachments };
    }
  ).sort((a: QueuedRun, b: QueuedRun) => a.position - b.position);
}
export function queueCommand(commandId: string, threadId: string, action: string, runId: string,
  beforeRunId: string | null = null, prompt: string = ''): Object {
  if (action === 'resume') return { type: 'queue.resume', commandId, threadId };
  if (!['start', 'cancel', 'edit', 'reorder'].includes(action) || !runId) throw new Error('队列操作无效');
  if (action === 'reorder' && beforeRunId === runId) throw new Error('不能将任务排在自身之前');
  if (action === 'edit' && !prompt.trim()) throw new Error('请输入待发送内容');
  return { type: 'queued-run.' + action, commandId, threadId, runId,
    ...(action === 'edit' ? { text: prompt } : {}), ...(action === 'reorder' ? { beforeRunId } : {}) };
}

export interface ComposerExpandInput {
  text: string;
  previewText?: string;
  compactTextWidthVp: number;
  singleLineTextWidthVp: number;
  measuredLineCount: number;
  currentlyExpanded: boolean;
}

export interface CompactEditorGeometryInput {
  rowWidthVp: number;
  measuredSlotLeftVp: number;
  measuredSlotWidthVp: number;
  hasSendModeBadge: boolean;
}

export interface CompactEditorGeometry {
  leftVp: number;
  widthVp: number;
  textWidthVp: number;
}

export interface ExpandedModelLayout {
  iconOnly: boolean;
  showSummary: boolean;
  maxLabelWidthVp: number;
  maxSummaryWidthVp: number;
  maxButtonWidthVp: number;
}

const COMPACT_LEFT_DEFAULT_VP = 48;
const COMPACT_RIGHT_RESERVED_VP = 94;
const COMPACT_BADGE_RESERVED_VP = 54;
const COMPACT_FALLBACK_WIDTH_VP = 140;
const COMPACT_TEXT_INSET_VP = 16;
const EXPAND_HYSTERESIS_VP = 4;

const EXPANDED_MODEL_FALLBACK_SLOT_VP = 180;
const EXPANDED_MODEL_ICON_ONLY_MIN_VP = 56;
const EXPANDED_MODEL_CHROME_NO_SUMMARY_VP = 55;
const EXPANDED_MODEL_CHROME_WITH_SUMMARY_VP = 60;
const EXPANDED_MODEL_SUMMARY_MIN_BUDGET_VP = 72;
const EXPANDED_MODEL_SUMMARY_MAX_VP = 88;
const EXPANDED_MODEL_MIN_PART_VP = 24;

/** 决定输入框是否应从紧凑单行胶囊切换为多行上下布局（与原版 useCompactComposerEditor 一致并防边界抖动）。 */
export function shouldExpandComposer(input: ComposerExpandInput): boolean {
  const effective = (input.text || '') + (input.previewText || '');
  if (effective.length === 0) return false;
  if (effective.includes('\n') || effective.includes('\r')) return true;
  if (Number.isFinite(input.measuredLineCount) && input.measuredLineCount > 1) return true;
  const compactWidth = Number.isFinite(input.compactTextWidthVp) ? Math.max(0, input.compactTextWidthVp) : 0;
  const singleLineWidth = Number.isFinite(input.singleLineTextWidthVp) ? Math.max(0, input.singleLineTextWidthVp) : 0;
  if (compactWidth > 0 && singleLineWidth > 0) {
    const threshold = input.currentlyExpanded ? Math.max(0, compactWidth - EXPAND_HYSTERESIS_VP) : compactWidth;
    if (singleLineWidth > threshold) return true;
  }
  return false;
}

/** 计算单行输入态中间 TextArea 槽位坐标、总宽及用于换行判断的可用文字宽度。 */
export function resolveCompactEditorGeometry(input: CompactEditorGeometryInput): CompactEditorGeometry {
  const measuredW = Number.isFinite(input.measuredSlotWidthVp) ? input.measuredSlotWidthVp : 0;
  const measuredL = Number.isFinite(input.measuredSlotLeftVp) ? input.measuredSlotLeftVp : 0;
  if (measuredW > 0) {
    const widthVp = Math.max(40, measuredW);
    return {
      leftVp: Math.max(0, measuredL),
      widthVp,
      textWidthVp: Math.max(0, widthVp - COMPACT_TEXT_INSET_VP)
    };
  }
  const rowW = Number.isFinite(input.rowWidthVp) ? input.rowWidthVp : 0;
  const leftVp = COMPACT_LEFT_DEFAULT_VP + (input.hasSendModeBadge ? COMPACT_BADGE_RESERVED_VP : 0);
  const widthVp = rowW > 0
    ? Math.max(60, rowW - leftVp - COMPACT_RIGHT_RESERVED_VP)
    : COMPACT_FALLBACK_WIDTH_VP;
  return {
    leftVp,
    widthVp,
    textWidthVp: Math.max(0, widthVp - COMPACT_TEXT_INSET_VP)
  };
}

/** 为展开态底部模型选择器计算严格不溢出的名称与选项摘要最大宽度预算，兼容超长模型名与大字体。 */
export function layoutExpandedModelControl(
  slotWidthVp: number,
  labelWidthVp: number,
  summaryWidthVp: number,
  hasSummary: boolean
): ExpandedModelLayout {
  const rawSlot = Number.isFinite(slotWidthVp) && slotWidthVp > 0 ? Math.floor(slotWidthVp) : EXPANDED_MODEL_FALLBACK_SLOT_VP;
  const safeSlot = Math.max(0, rawSlot);
  if (safeSlot < EXPANDED_MODEL_ICON_ONLY_MIN_VP) {
    return {
      iconOnly: true,
      showSummary: false,
      maxLabelWidthVp: 0,
      maxSummaryWidthVp: 0,
      maxButtonWidthVp: safeSlot
    };
  }
  const withSummaryBudget = Math.max(0, safeSlot - EXPANDED_MODEL_CHROME_WITH_SUMMARY_VP);
  const canShowSummary = hasSummary && withSummaryBudget >= EXPANDED_MODEL_SUMMARY_MIN_BUDGET_VP;
  if (!canShowSummary) {
    return {
      iconOnly: false,
      showSummary: false,
      maxLabelWidthVp: Math.max(0, safeSlot - EXPANDED_MODEL_CHROME_NO_SUMMARY_VP),
      maxSummaryWidthVp: 0,
      maxButtonWidthVp: safeSlot
    };
  }
  const budget = withSummaryBudget;
  const defaultSummaryCap = Math.max(EXPANDED_MODEL_MIN_PART_VP, Math.min(EXPANDED_MODEL_SUMMARY_MAX_VP, Math.floor(budget * 0.36)));
  const needLabel = Number.isFinite(labelWidthVp) && labelWidthVp > 0 ? Math.ceil(labelWidthVp) + 2 : budget;
  const needSummary = Number.isFinite(summaryWidthVp) && summaryWidthVp > 0 ? Math.ceil(summaryWidthVp) + 2 : defaultSummaryCap;

  let maxLabelWidthVp: number;
  let maxSummaryWidthVp: number;
  if (needLabel + needSummary <= budget) {
    maxSummaryWidthVp = needSummary;
    maxLabelWidthVp = Math.max(needLabel, budget - needSummary);
  } else if (needSummary <= defaultSummaryCap) {
    maxSummaryWidthVp = needSummary;
    maxLabelWidthVp = Math.max(EXPANDED_MODEL_MIN_PART_VP, budget - maxSummaryWidthVp);
  } else if (needLabel <= budget - defaultSummaryCap) {
    maxLabelWidthVp = needLabel;
    maxSummaryWidthVp = Math.max(EXPANDED_MODEL_MIN_PART_VP, budget - maxLabelWidthVp);
  } else {
    maxSummaryWidthVp = defaultSummaryCap;
    maxLabelWidthVp = Math.max(EXPANDED_MODEL_MIN_PART_VP, budget - maxSummaryWidthVp);
  }
  if (maxLabelWidthVp + maxSummaryWidthVp > budget) {
    maxLabelWidthVp = Math.max(0, budget - maxSummaryWidthVp);
  }
  return {
    iconOnly: false,
    showSummary: true,
    maxLabelWidthVp,
    maxSummaryWidthVp,
    maxButtonWidthVp: safeSlot
  };
}
