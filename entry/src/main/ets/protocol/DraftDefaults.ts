import { record } from './Wire';

export interface DraftDefaultsConnection {
  ready: boolean;
  canScope(scope: string): boolean | undefined;
  rpcRequest(method: string, payload: Object, timeoutMs?: number, fatalTimeout?: boolean): Promise<Object>;
}
export interface DraftDefaultsProject {
  id: string;
  workspaceRoot: string;
  defaultThreadEnvMode?: string | null;
  isScratch?: boolean;
  hasThreads?: boolean;
}
export interface DraftDefaultWorkspace { mode: string; branch: string; worktreePath: string; startFromOrigin: boolean; }
export interface DraftDefaults { runtimeMode: string; workspace: DraftDefaultWorkspace; }
const modes: string[] = ['approval-required', 'auto-accept-edits', 'auto', 'full-access'];

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
  return { runtimeMode: runtime as string, workspace: { mode, branch: '', worktreePath: '', startFromOrigin: remote === undefined ? true : remote as boolean } };
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
