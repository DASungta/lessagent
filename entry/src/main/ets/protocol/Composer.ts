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
