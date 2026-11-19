import { record } from './Wire';

export const BRANCH_NAMING_MODES: string[] = ['static', 'semantic', 'custom'];

export interface WorktreeDefaults {
  environmentId: string;
  remote: boolean;
  submodules: string;
  remoteLocked: boolean;
  submodulesLocked: boolean;
  managedBy: string;
  branchNamingMode: string | undefined;
  branchNamePrefix: string | undefined;
  branchNameInstructions: string | undefined;
  lockedPaths: string[];
}
export interface WorktreeSettingsConnection {
  ready: boolean;
  canScope(scope: string): boolean | undefined;
  rpcRequest(method: string, payload: Object, timeoutMs?: number, fatalTimeout?: boolean): Promise<Object>;
}

export function worktreeDefaults(config: Object, expectedEnvironment: string): WorktreeDefaults {
  const root = record(config);
  const environment = record(root.environment);
  if (!expectedEnvironment || environment.environmentId !== expectedEnvironment) throw new Error('环境身份变化，请重新打开设置');
  const settings = record(root.settings);
  if (typeof settings.newWorktreesStartFromOrigin !== 'boolean') throw new Error('服务端未提供工作树默认设置');
  const modules = settings.worktreeSubmodules;
  if (modules !== null && modules !== 'recursive' && modules !== 'top-level' && modules !== 'none') {
    throw new Error('服务端子模块设置尚不受此客户端支持');
  }
  const managed = root.managedPolicy ? record(root.managedPolicy) : {} as Record<string, Object>;
  const locked = Array.isArray(managed.lockedSettings)
    ? (managed.lockedSettings as Object[]).filter(item => typeof item === 'string') as string[] : [];
  const mode = settings.branchNamingMode;
  return {
    environmentId: expectedEnvironment, remote: settings.newWorktreesStartFromOrigin,
    submodules: modules === null ? 'inherit' : modules as string,
    remoteLocked: worktreeSettingLocked(locked, 'newWorktreesStartFromOrigin'),
    submodulesLocked: worktreeSettingLocked(locked, 'worktreeSubmodules'),
    branchNamingMode: typeof mode === 'string' && BRANCH_NAMING_MODES.includes(mode) ? mode : undefined,
    branchNamePrefix: typeof settings.branchNamePrefix === 'string' ? settings.branchNamePrefix : undefined,
    branchNameInstructions: typeof settings.branchNameInstructions === 'string' ? settings.branchNameInstructions : undefined,
    lockedPaths: locked,
    managedBy: typeof managed.organization === 'string' ? managed.organization : '组织'
  };
}

export function worktreeSettingLocked(paths: string[], key: string): boolean {
  return paths.some(path => path === key || path.startsWith(key + '.') || key.startsWith(path + '.'));
}
export function worktreeValue(current: WorktreeDefaults, key: string): string | undefined {
  if (key === 'newWorktreesStartFromOrigin') return String(current.remote);
  if (key === 'worktreeSubmodules') return current.submodules;
  if (key === 'branchNamingMode') return current.branchNamingMode;
  if (key === 'branchNamePrefix') return current.branchNamingMode === 'static' ? current.branchNamePrefix : undefined;
  if (key === 'branchNameInstructions') return current.branchNamingMode === 'custom' ? current.branchNameInstructions : undefined;
  return undefined;
}

export function worktreePatch(current: WorktreeDefaults, key: string, value: string): Object {
  if (key === 'newWorktreesStartFromOrigin') {
    if (current.remoteLocked) throw new Error('此设置由组织管理');
    if (value !== 'true' && value !== 'false') throw new Error('工作树起点无效');
    return { newWorktreesStartFromOrigin: value === 'true' };
  }
  if (key === 'worktreeSubmodules') {
    if (current.submodulesLocked) throw new Error('此设置由组织管理');
    if (!['inherit', 'recursive', 'top-level', 'none'].includes(value)) throw new Error('子模块选项无效');
    return { worktreeSubmodules: value === 'inherit' ? null : value };
  }
  if (worktreeSettingLocked(current.lockedPaths, key)) throw new Error('此设置由组织管理');
  if (worktreeValue(current, key) !== undefined) {
    if (key === 'branchNamingMode' && BRANCH_NAMING_MODES.includes(value)) return { branchNamingMode: value };
    if (key === 'branchNamePrefix') return { branchNamePrefix: value.trim() };
    if (key === 'branchNameInstructions') return { branchNameInstructions: value.trim() };
  }
  throw new Error('不支持此设置项');
}

export async function readWorktreeDefaults(connection: WorktreeSettingsConnection, expectedEnvironment: string): Promise<WorktreeDefaults> {
  if (!connection.ready) throw new Error('环境未连接');
  const config = await connection.rpcRequest('server.getConfig', {}, 15000, false);
  if (!connection.ready) throw new Error('环境已断开');
  return worktreeDefaults(config, expectedEnvironment);
}

function hasWriteScope(connection: WorktreeSettingsConnection, key: string): boolean {
  const scope = connection.canScope('settings:write');
  if (key === 'newWorktreesStartFromOrigin' || key === 'worktreeSubmodules') return scope !== false;
  return scope === true;
}

export async function writeWorktreeDefault(connection: WorktreeSettingsConnection,
  expectedEnvironment: string, key: string, value: string, stillSelected: () => boolean = () => true): Promise<WorktreeDefaults> {
  if (!hasWriteScope(connection, key)) throw new Error('此连接没有修改设置的权限');
  // Re-read policy and identity immediately before writing; never replay a failed mutation.
  const current = await readWorktreeDefaults(connection, expectedEnvironment);
  if (!hasWriteScope(connection, key) || !stillSelected()) throw new Error('修改的环境或权限已变化');
  const patch = worktreePatch(current, key, value);
  await connection.rpcRequest('server.updateSettings', { patch }, 15000, false);
  const result = await readWorktreeDefaults(connection, expectedEnvironment);
  const expected = key === 'branchNamePrefix' || key === 'branchNameInstructions' ? value.trim() : value;
  if (worktreeValue(result, key) !== expected) {
    throw new Error('回读结果与修改不一致，请刷新核对');
  }
  return result;
}
