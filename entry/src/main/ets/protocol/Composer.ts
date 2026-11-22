import { record, text, objects } from './Wire';
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
    for (const item of objects(row.options as Object)) {
      const choice = record(item);
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
  const rawProviders = root.providers;
  const provider = Array.isArray(rawProviders)
    ? objects(rawProviders as Object).map(record).find((p: Record<string, Object>) => p.instanceId === selection.instanceId)
    : undefined;
  const rawModels = provider ? provider.models : undefined;
  const model = Array.isArray(rawModels)
    ? objects(rawModels as Object).map(record).find((m: Record<string, Object>) => m.slug === selection.model)
    : undefined;
  const caps = model ? optionalRecord(model.capabilities) : {};
  const rawDescriptors = caps.optionDescriptors;
  const descriptors = Array.isArray(rawDescriptors) ? objects(rawDescriptors as Object).map(record) : [];

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
        const choices = objects(row.options as Object).map(record);
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
        const choices = objects(row.options as Object).map(record);
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
  const provider = objects(record(config).providers || []).map(record).find((p) => p.instanceId === selection.instanceId);
  const model = provider ? objects(provider.models || []).map(record).find((m) => m.slug === selection.model) : undefined;
  const caps = model ? optionalRecord(model.capabilities) : {};
  return objects(caps.optionDescriptors || []).map((value: Object): ModelOptionControl => {
    const row = record(value);
    if (row.type !== 'select' && row.type !== 'boolean') throw new Error('未知模型选项类型');
    return { id: text(row.id), label: text(row.label), type: text(row.type), choices:
      row.type === 'boolean' ? [] : objects(row.options).map((item: Object): ModelOptionValue => {
        const choice = record(item); return { id: text(choice.id), label: text(choice.label) };
      }) };
  });
}
export function supportedModes(config: Object, selection: ModelSelection): string[] {
  const row = record(config);
  const provider = objects(row.providers || []).map(record).find((p) => p.instanceId === selection.instanceId);
  const policy = optionalRecord(optionalRecord(row.managedPolicy).limits);
  const ceiling = policy.maxRuntimeMode === undefined ? runtimeModes.length - 1 : runtimeModes.indexOf(text(policy.maxRuntimeMode));
  return runtimeModes.filter((mode: string, index: number) => index <= ceiling &&
    (!provider?.supportedRuntimeModes || (provider.supportedRuntimeModes as string[]).includes(mode)));
}
export function interactionModes(config: Object, selection: ModelSelection): string[] {
  const provider = objects(record(config).providers || []).map(record).find((p) => p.instanceId === selection.instanceId);
  return provider?.showInteractionModeToggle === false ? ['default'] : ['default', 'plan'];
}
export function validateTaskSettings(config: Object, projectId: string, settings: TaskSettings): TaskSettings {
  const row = record(config);
  const selection = settings.modelSelection;
  const provider = objects(row.providers || []).map(record).find((p) => p.instanceId === selection.instanceId);
  const overrides = optionalRecord(optionalRecord(optionalRecord(row.settings).projectSettingsOverrides)[projectId]);
  const projectProvider = optionalRecord(optionalRecord(overrides.providerInstances)[selection.instanceId]);
  const allowed = optionalRecord(optionalRecord(optionalRecord(row.managedPolicy).limits).providers).allowedDrivers;
  if (!provider || provider.installed === false || (projectProvider.enabled === undefined ? provider.enabled === false : projectProvider.enabled === false) ||
    (Array.isArray(allowed) && !allowed.includes(provider.driver)) ||
    !objects(provider.models || []).some((value: Object) => record(value).slug === selection.model)) {
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
  return runs.filter((run: Record<string, Object>) => run.status === 'queued').map((run: Record<string, Object>): QueuedRun => {
    const messageId = text(run.userMessageId);
    const message = messages.find((row: Record<string, Object>) => row.id === messageId);
    const attachments = message && message.attachments !== undefined ? objects(message.attachments).map((value: Object) =>
      text(record(value).name)) : [];
    return { id: text(run.id), messageId, text: message ? text(message.text) : '',
      position: typeof run.queuePosition === 'number' ? run.queuePosition : Number.MAX_SAFE_INTEGER,
      held: run.queueHeld === true, attachmentNames: attachments };
  }).sort((a: QueuedRun, b: QueuedRun) => a.position - b.position);
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
