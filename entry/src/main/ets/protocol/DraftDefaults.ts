import { objects, parseModelSelection, record } from './Wire';
import type { ModelSelection, OptionSelection } from './Wire';

export interface DraftDefaultsConnection {
  ready: boolean;
  canScope(scope: string): boolean | undefined;
  rpcRequest(method: string, payload: Object, timeoutMs?: number, fatalTimeout?: boolean): Promise<Object>;
}
export interface DraftDefaultsProject {
  id: string;
  workspaceRoot: string;
  defaultThreadEnvMode?: string | null;
  defaultModelSelection?: ModelSelection | null;
  isScratch?: boolean;
  hasThreads?: boolean;
}
export interface DraftDefaultWorkspace { mode: string; branch: string; worktreePath: string; startFromOrigin: boolean; }
export interface DraftDefaults { runtimeMode: string; workspace: DraftDefaultWorkspace; modelSelection?: ModelSelection; }
const modes: string[] = ['approval-required', 'auto-accept-edits', 'auto', 'full-access'];

function optionalObj(value: Object | undefined): Record<string, Object> {
  return value === undefined || value === null || typeof value !== 'object' || Array.isArray(value)
    ? {} as Record<string, Object> : value as Record<string, Object>;
}

function findProvider(providers: Record<string, Object>[], instanceId: string): Record<string, Object> | undefined {
  return providers.find((item: Record<string, Object>) => item.instanceId === instanceId);
}

function providerDriver(providerRow: Record<string, Object> | undefined, settings: Record<string, Object>,
  instanceId: string): string {
  if (providerRow && typeof providerRow.driver === 'string' && providerRow.driver) return providerRow.driver as string;
  const inst = optionalObj(optionalObj(settings.providerInstances)[instanceId]);
  return typeof inst.driver === 'string' ? inst.driver as string : '';
}

function isDriverAllowed(root: Record<string, Object>, driver: string): boolean {
  const limits = optionalObj(optionalObj(root.managedPolicy).limits);
  const allowed = optionalObj(limits.providers).allowedDrivers;
  if (!Array.isArray(allowed)) return true;
  return !!driver && (allowed as Object[]).includes(driver);
}

function isProviderEnabledForProject(settings: Record<string, Object>, projectId: string, instanceId: string,
  providerRow: Record<string, Object> | undefined): boolean {
  const projectOverride = optionalObj(optionalObj(optionalObj(optionalObj(settings.projectSettingsOverrides)[projectId]).providerInstances)[instanceId]);
  if (typeof projectOverride.enabled === 'boolean') return projectOverride.enabled === true;
  const inst = optionalObj(optionalObj(settings.providerInstances)[instanceId]);
  if (inst.enabled === false || optionalObj(inst.config).enabled === false) return false;
  if (providerRow !== undefined) {
    if (providerRow.enabled === false) return false;
    if (providerRow.enabled === true) return true;
  }
  if (typeof inst.enabled === 'boolean') return inst.enabled === true;
  return true;
}

function isModelCustom(settings: Record<string, Object>, instanceId: string, slug: string,
  modelRow: Record<string, Object> | undefined): boolean {
  if (modelRow && modelRow.isCustom === true) return true;
  const customModels = optionalObj(optionalObj(optionalObj(settings.providerInstances)[instanceId]).config).customModels;
  if (!Array.isArray(customModels)) return false;
  for (const item of customModels as Object[]) {
    if (typeof item === 'string' && item === slug) return true;
    if (item !== null && typeof item === 'object' && !Array.isArray(item) && optionalObj(item).slug === slug) return true;
  }
  return false;
}

function isModelHidden(settings: Record<string, Object>, instanceId: string, slug: string,
  modelRow: Record<string, Object> | undefined): boolean {
  if (isModelCustom(settings, instanceId, slug, modelRow)) return false;
  const prefs = optionalObj(optionalObj(settings.providerModelPreferences)[instanceId]);
  return Array.isArray(prefs.hiddenModels) && (prefs.hiddenModels as Object[]).includes(slug);
}

function normalizeModelOptions(modelRow: Record<string, Object>, options: OptionSelection[] | undefined): OptionSelection[] | undefined {
  if (!options || options.length === 0) return undefined;
  if (modelRow.capabilities === undefined || modelRow.capabilities === null) return options.slice();
  const caps = optionalObj(modelRow.capabilities);
  const rawDescriptors = caps.optionDescriptors;
  const descriptors = Array.isArray(rawDescriptors) ? objects(rawDescriptors as Object).map(record) : [];
  if (descriptors.length === 0) return undefined;
  const valid: OptionSelection[] = [];
  for (const option of options) {
    const descriptor = descriptors.find((item: Record<string, Object>) => item.id === option.id);
    if (!descriptor) continue;
    if (descriptor.type === 'boolean') {
      if (typeof option.value === 'boolean') valid.push({ id: option.id, value: option.value });
    } else if (descriptor.type === 'select' && typeof option.value === 'string') {
      const choices = Array.isArray(descriptor.options) ? objects(descriptor.options as Object).map(record) : [];
      if (choices.some((choice: Record<string, Object>) => choice.id === option.value)) {
        valid.push({ id: option.id, value: option.value });
      }
    }
  }
  return valid.length > 0 ? valid : undefined;
}

function isUsageWindowExhausted(providerRow: Record<string, Object>, modelSlug: string, nowMs: number): boolean {
  const rawWindows = optionalObj(providerRow.usageLimits).windows;
  if (!Array.isArray(rawWindows) || (rawWindows as Object[]).length === 0) return false;
  const windows = objects(rawWindows as Object).map(record);
  const prefix = modelSlug.split('/')[0] || '';
  const exhausted = windows.filter((window: Record<string, Object>) => {
    if (typeof window.usedPercent !== 'number' || (window.usedPercent as number) < 100) return false;
    if (Array.isArray(window.modelIds) && !(window.modelIds as Object[]).includes(modelSlug)) return false;
    if (Array.isArray(window.providerIds) && !(window.providerIds as Object[]).includes(prefix)) return false;
    if (typeof window.resetsAt === 'string' && window.resetsAt) {
      const resetMs = Date.parse(window.resetsAt as string);
      if (Number.isFinite(resetMs) && resetMs <= nowMs) return false;
    }
    return true;
  });
  if (exhausted.length === 0) return false;
  const driver = typeof providerRow.driver === 'string' ? providerRow.driver as string : '';
  if (driver === 'cursor') {
    const api = exhausted.some((w: Record<string, Object>) => w.id === 'apiPercentUsed');
    const auto = exhausted.some((w: Record<string, Object>) => w.id === 'autoPercentUsed');
    return /^(auto|default|grok|composer)/.test(modelSlug) ? auto && api : api;
  }
  if (driver === 'antigravity') {
    const familyMatch = /^(gemini|claude|gpt)-/.exec(modelSlug);
    const family = familyMatch ? familyMatch[1] : '';
    return exhausted.some((w: Record<string, Object>) => {
      const poolMatch = typeof w.id === 'string' ? /^(gemini|claude|gpt|3p)-/.exec(w.id as string) : null;
      if (!poolMatch || !family) return true;
      const pool = poolMatch[1];
      return pool === family || (pool === '3p' && (family === 'claude' || family === 'gpt'));
    });
  }
  if (driver === 'codex') {
    const hasPlanWindows = windows.some((w: Record<string, Object>) => w.id === 'primary' || w.id === 'secondary');
    return exhausted.some((w: Record<string, Object>) => w.id !== 'individual' || !hasPlanWindows);
  }
  if (driver === 'opencode') {
    return exhausted.some((w: Record<string, Object>) =>
      typeof w.id !== 'string' || !(w.id as string).startsWith('go_') || modelSlug.startsWith('opencode-go/'));
  }
  return true;
}

function providerSelectable(root: Record<string, Object>, settings: Record<string, Object>, projectId: string,
  providerRow: Record<string, Object>): boolean {
  const instanceId = typeof providerRow.instanceId === 'string' ? providerRow.instanceId as string : '';
  if (!instanceId || providerRow.installed === false) return false;
  if (!isProviderEnabledForProject(settings, projectId, instanceId, providerRow)) return false;
  const driver = providerDriver(providerRow, settings, instanceId);
  if (!isDriverAllowed(root, driver)) return false;
  if (optionalObj(providerRow.auth).status === 'unauthenticated') return false;
  if (driver === 'antigravity' && providerRow.availability === 'unavailable') return false;
  return true;
}

function usableModelSelection(root: Record<string, Object>, settings: Record<string, Object>,
  providers: Record<string, Object>[], projectId: string, candidate: ModelSelection,
  allowLegacy: boolean): ModelSelection | undefined {
  const providerRow = findProvider(providers, candidate.instanceId);
  if (!providerRow || !providerSelectable(root, settings, projectId, providerRow)) return undefined;
  const driver = providerDriver(providerRow, settings, candidate.instanceId);
  const rawModels = providerRow.models;
  const modelList = Array.isArray(rawModels) ? objects(rawModels as Object).map(record) : [];
  const modelRow = modelList.find((item: Record<string, Object>) => item.slug === candidate.model);
  if (!modelRow) return undefined;
  if (!allowLegacy && driver !== 'antigravity' && modelRow.isLegacy === true) return undefined;
  if (isModelHidden(settings, candidate.instanceId, candidate.model, modelRow)) return undefined;
  const options = normalizeModelOptions(modelRow, candidate.options);
  return options && options.length > 0
    ? { instanceId: candidate.instanceId, model: candidate.model, options }
    : { instanceId: candidate.instanceId, model: candidate.model };
}

function catalogFallbackModelSelection(root: Record<string, Object>, settings: Record<string, Object>,
  providers: Record<string, Object>[], projectId: string): ModelSelection | undefined {
  let firstNonLegacy: ModelSelection | undefined = undefined;
  let firstAvailable: ModelSelection | undefined = undefined;
  for (const providerRow of providers) {
    if (!providerSelectable(root, settings, projectId, providerRow)) continue;
    const instanceId = providerRow.instanceId as string;
    const rawModels = providerRow.models;
    const rawList = Array.isArray(rawModels) ? objects(rawModels as Object).map(record) : [];
    const visible = rawList.filter((item: Record<string, Object>) =>
      typeof item.slug === 'string' && item.slug && !isModelHidden(settings, instanceId, item.slug as string, item));
    const orderRaw = optionalObj(optionalObj(settings.providerModelPreferences)[instanceId]).modelOrder;
    if (Array.isArray(orderRaw) && (orderRaw as Object[]).length > 0) {
      const order = new Map<string, number>();
      (orderRaw as Object[]).forEach((slug: Object, idx: number) => {
        if (typeof slug === 'string' && !order.has(slug)) order.set(slug, idx);
      });
      visible.sort((a: Record<string, Object>, b: Record<string, Object>) => {
        const ra = order.has(a.slug as string) ? order.get(a.slug as string)! : Number.MAX_SAFE_INTEGER;
        const rb = order.has(b.slug as string) ? order.get(b.slug as string)! : Number.MAX_SAFE_INTEGER;
        return ra - rb;
      });
    }
    for (const modelRow of visible) {
      const slug = modelRow.slug as string;
      const choice: ModelSelection = { instanceId, model: slug };
      if (!firstAvailable) firstAvailable = choice;
      if (modelRow.isLegacy !== true) {
        if (modelRow.isDefault === true) return choice;
        if (!firstNonLegacy) firstNonLegacy = choice;
      }
    }
  }
  return firstNonLegacy || firstAvailable;
}

function resolveDefaultModelSelection(root: Record<string, Object>, originalSettings: Record<string, Object>,
  project: DraftDefaultsProject, nowMs: number): ModelSelection | undefined {
  const providers = Array.isArray(root.providers) ? objects(root.providers as Object).map(record) : [];
  if (providers.length === 0) return undefined;
  const overrides = optionalObj(originalSettings.projectSettingsOverrides);
  const override = optionalObj(overrides[project.id]);
  const hasOverrideKey = Object.prototype.hasOwnProperty.call(override, 'defaultModelSelection') &&
    override.defaultModelSelection !== undefined;
  const explicitProjectNull = hasOverrideKey && override.defaultModelSelection === null;
  let projectCandidate: ModelSelection | undefined = undefined;
  if (hasOverrideKey) {
    if (override.defaultModelSelection !== null) projectCandidate = parseModelSelection(override.defaultModelSelection);
  } else if (!originalSettings.projectSettingsFolded && project.defaultModelSelection !== undefined &&
    project.defaultModelSelection !== null) {
    projectCandidate = parseModelSelection(project.defaultModelSelection as Object);
  }
  let selected = projectCandidate
    ? usableModelSelection(root, originalSettings, providers, project.id, projectCandidate, false)
    : undefined;
  if (!selected && !explicitProjectNull) {
    const envCandidate = parseModelSelection(originalSettings.defaultModelSelection);
    if (envCandidate) {
      selected = usableModelSelection(root, originalSettings, providers, project.id, envCandidate, false);
    }
  }
  if (selected && originalSettings.fallbackModelSelection !== undefined && originalSettings.fallbackModelSelection !== null) {
    const selectedProvider = findProvider(providers, selected.instanceId);
    if (selectedProvider && isUsageWindowExhausted(selectedProvider, selected.model, nowMs)) {
      const fallbackCandidate = parseModelSelection(originalSettings.fallbackModelSelection);
      const fallbackSelected = fallbackCandidate
        ? usableModelSelection(root, originalSettings, providers, project.id, fallbackCandidate, true)
        : undefined;
      if (fallbackSelected) {
        const fallbackProvider = findProvider(providers, fallbackSelected.instanceId);
        if (fallbackProvider && !isUsageWindowExhausted(fallbackProvider, fallbackSelected.model, nowMs)) {
          selected = fallbackSelected;
        }
      }
    }
  }
  if (!selected) selected = catalogFallbackModelSelection(root, originalSettings, providers, project.id);
  return selected;
}

function comparisonPath(value: string): string {
  const normalized = value.trim().replace(/\\/g, '/').replace(/\/+$/, '');
  return /^[A-Za-z]:\//.test(normalized) || normalized.startsWith('//') ? normalized.toLowerCase() : normalized;
}

function settingsFor(config: Object, expectedEnvironment: string, project: DraftDefaultsProject): Record<string, Object> {
  const root = record(config);
  if (!expectedEnvironment || record(root.environment).environmentId !== expectedEnvironment) throw new Error('草稿环境身份已变化');
  if (!project.id.trim()) throw new Error('草稿项目无效');
  const settings = record(root.settings);
  const allOverrides = settings.projectSettingsOverrides === undefined ? {} as Record<string, Object> : record(settings.projectSettingsOverrides);
  const override = allOverrides[project.id] === undefined ? {} as Record<string, Object> : record(allOverrides[project.id]);
  const result: Record<string, Object> = { ...settings };
  if (settings.projectSettingsFolded !== undefined && typeof settings.projectSettingsFolded !== 'boolean') throw new Error('项目默认设置版本无效');
  if (!settings.projectSettingsFolded && project.defaultThreadEnvMode !== undefined && project.defaultThreadEnvMode !== null) {
    result.defaultThreadEnvMode = project.defaultThreadEnvMode;
  }
  for (const key of ['defaultRuntimeMode', 'defaultThreadEnvMode', 'newWorktreesStartFromOrigin']) {
    if (override[key] !== undefined) result[key] = override[key];
  }
  return result;
}

function projectFileMode(value: Object): string {
  const file = record(value);
  if (file.exists === false) return 'local';
  if (file.relativePath !== 't3.json' || typeof file.contents !== 'string' || file.truncated !== false || file.contents.length > 1048576) {
    throw new Error('项目 t3.json 未完整读取，不能确定默认工作区');
  }
  // Match upstream's JSON comments/trailing commas while preserving quoted URLs.
  const clean = file.contents.replace(/("(?:[^"\\]|\\.)*")|\/\/[^\r\n]*|\/\*[\s\S]*?\*\//g,
    (match: string, literal: string): string => literal ? match : ' ')
    .replace(/("(?:[^"\\]|\\.)*")|,(\s*[}\]])/g,
      (match: string, literal: string, bracket: string): string => literal ? match : bracket || '');
  let data: Record<string, Object>;
  try { data = record(JSON.parse(clean)); } catch (_) { throw new Error('项目 t3.json 格式无效，请修复后重试'); }
  if (data.defaultThreadEnvMode === undefined) return 'local';
  if (data.defaultThreadEnvMode !== 'local' && data.defaultThreadEnvMode !== 'worktree') throw new Error('项目默认工作区不受支持');
  return data.defaultThreadEnvMode as string;
}

export function resolveDraftDefaults(config: Object, expectedEnvironment: string, project: DraftDefaultsProject,
  file?: Object): DraftDefaults {
  const root = record(config);
  const settings = settingsFor(config, expectedEnvironment, project);
  let runtime = settings.defaultRuntimeMode === undefined ? 'approval-required' : settings.defaultRuntimeMode;
  if (typeof runtime !== 'string' || !modes.includes(runtime)) throw new Error('服务端默认权限不受支持');
  const policy = root.managedPolicy === undefined ? {} as Record<string, Object> : record(root.managedPolicy);
  const limits = policy.limits === undefined ? {} as Record<string, Object> : record(policy.limits);
  const maximum = limits.maxRuntimeMode;
  if (maximum !== undefined) {
    if (typeof maximum !== 'string' || !modes.includes(maximum)) throw new Error('组织权限上限不受支持');
    if (modes.indexOf(runtime) > modes.indexOf(maximum)) runtime = maximum;
  }
  const configured = settings.defaultThreadEnvMode;
  let mode: string;
  if (configured === null) {
    if (file === undefined && !project.isScratch && project.workspaceRoot) throw new Error('尚未读取项目默认工作区');
    mode = file === undefined ? 'local' : projectFileMode(file);
  } else if (configured === undefined) mode = 'local';
  else if (configured === 'local' || configured === 'worktree') mode = configured as string;
  else throw new Error('服务端默认工作区不受支持');
  const remote = settings.newWorktreesStartFromOrigin;
  if (remote !== undefined && typeof remote !== 'boolean') throw new Error('工作树远端起点设置无效');
  const original = record(root.settings);
  const overrides = original.projectSettingsOverrides === undefined ? {} as Record<string, Object> : record(original.projectSettingsOverrides);
  const override = overrides[project.id] === undefined ? {} as Record<string, Object> : record(overrides[project.id]);
  const projectMode = override.defaultThreadEnvMode !== undefined ||
    (!original.projectSettingsFolded && project.defaultThreadEnvMode !== undefined && project.defaultThreadEnvMode !== null);
  const fileMode = configured === null && file !== undefined && mode === 'worktree';
  if (project.isScratch) mode = 'local';
  else if (mode === 'worktree' && project.hasThreads === false && !projectMode && !fileMode && typeof root.newProjectsRoot === 'string') {
    const parent = comparisonPath(root.newProjectsRoot);
    const folder = comparisonPath(project.workspaceRoot);
    const child = folder.startsWith(parent + '/') ? folder.slice(parent.length + 1) : '';
    if (child && !child.includes('/')) mode = 'local';
  }
  const modelSelection = resolveDefaultModelSelection(root, original, project, Date.now());
  if (modelSelection && Array.isArray(root.providers)) {
    const providerRow = findProvider(objects(root.providers as Object).map(record), modelSelection.instanceId);
    if (providerRow && Array.isArray(providerRow.supportedRuntimeModes) &&
      (providerRow.supportedRuntimeModes as Object[]).length > 0) {
      const ceiling = maximum === undefined ? modes.length - 1 : modes.indexOf(maximum as string);
      const supported = (providerRow.supportedRuntimeModes as Object[])
        .filter((item: Object): boolean => typeof item === 'string' && modes.includes(item as string) &&
          modes.indexOf(item as string) <= ceiling) as string[];
      if (supported.length > 0 && !supported.includes(runtime as string)) runtime = supported[0];
    }
  }
  const workspace: DraftDefaultWorkspace = { mode, branch: '', worktreePath: '',
    startFromOrigin: remote === undefined ? true : remote as boolean };
  return modelSelection
    ? { runtimeMode: runtime as string, workspace, modelSelection }
    : { runtimeMode: runtime as string, workspace };
}

export async function readDraftDefaults(connection: DraftDefaultsConnection, expectedEnvironment: string,
  project: DraftDefaultsProject): Promise<DraftDefaults> {
  if (!connection.ready || connection.canScope('orchestration:read') === false) throw new Error('当前连接不能读取新任务默认设置');
  const config = await connection.rpcRequest('server.getConfig', {}, 15000, false);
  const settings = settingsFor(config, expectedEnvironment, project);
  let file: Object | undefined = undefined;
  if (settings.defaultThreadEnvMode === null && project.workspaceRoot && !project.isScratch) {
    if (connection.canScope('filesystem:read') === false) throw new Error('需要文件读取权限才能解析项目默认工作区');
    file = await connection.rpcRequest('projects.readFile', { cwd: project.workspaceRoot, relativePath: 't3.json', allowMissing: true }, 15000, false);
  }
  if (!connection.ready) throw new Error('读取默认设置时连接已断开');
  return resolveDraftDefaults(config, expectedEnvironment, project, file);
}
