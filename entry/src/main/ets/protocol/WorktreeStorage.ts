import { record } from './Wire';
import { WorktreeSettingsConnection, worktreeSettingLocked } from './WorktreeSettings';

type StorageValue = string | number | boolean | null;
export interface WorktreeStorageField { key: string; value: StorageValue | undefined; locked: boolean; }
export interface WorktreeStorage {
  environmentId: string;
  hostOs: string;
  managedBy: string;
  cleanupOverride: string;
  fields: WorktreeStorageField[];
}

export const WORKTREE_KEEP_VALUES: string[] = ['any-local-files', 'uncommitted-changes', 'tracked-changes'];
const RETENTION_KEYS = ['worktreeAfterDays', 'worktreeSettledAfterDays'];
const SWITCH_KEYS = ['worktreeOnMerge', 'worktreeOnDelete', 'worktreeUnchanged'];
const STORAGE_KEYS = ['worktreesDirectory', ...RETENTION_KEYS, ...SWITCH_KEYS, 'worktreeKeepWhen'];

function optionalRecord(value: Object | undefined): Record<string, Object> {
  return value === undefined || value === null ? {} as Record<string, Object> : record(value);
}
function validRetention(key: string, value: Object | undefined): boolean {
  return value === null || (typeof value === 'number' && Number.isInteger(value) &&
    value >= (key === 'worktreeSettledAfterDays' ? 0 : 1) && value <= 3650);
}
export function worktreeStorageField(state: WorktreeStorage, key: string): WorktreeStorageField | undefined {
  return state.fields.find(field => field.key === key);
}
export function worktreeStorage(config: Object, environmentId: string): WorktreeStorage {
  const root = record(config);
  const environment = record(root.environment);
  if (!environmentId || environment.environmentId !== environmentId) throw new Error('环境身份变化');
  const capabilities = optionalRecord(environment.capabilities);
  const settings = record(root.settings);
  const cleanup = optionalRecord(settings.storageCleanup);
  const policy = optionalRecord(root.managedPolicy);
  const locks = Array.isArray(policy.lockedSettings) ?
    (policy.lockedSettings as Object[]).filter(item => typeof item === 'string') as string[] : [];
  const os = optionalRecord(environment.platform).os;
  const cleanupMode = settings.worktreeCleanup === undefined || settings.worktreeCleanup === null ? '' :
    optionalRecord(settings.worktreeCleanup).mode;
  const cleanupOverride = cleanupMode === 'off' || cleanupMode === 'custom' || cleanupMode === '' ? cleanupMode as string : 'unknown';
  const fields = STORAGE_KEYS.map((key): WorktreeStorageField => {
    if (key === 'worktreesDirectory') {
      const dir = settings.worktreesDirectory;
      return { key, value: capabilities.worktreesDirectory === true && typeof dir === 'string' ? dir : undefined,
        locked: worktreeSettingLocked(locks, key) };
    }
    const supported = capabilities.storageCleanup === true && !cleanupOverride &&
      (key !== 'worktreeSettledAfterDays' || capabilities.settledWorktreeCleanup === true) &&
      (key !== 'worktreeKeepWhen' || capabilities.storageCleanupRun === true);
    const raw = cleanup[key];
    let value: StorageValue | undefined = undefined;
    if (supported) {
      if (RETENTION_KEYS.includes(key) && validRetention(key, raw)) value = raw as number | null;
      if (SWITCH_KEYS.includes(key) && typeof raw === 'boolean') value = raw;
      if (key === 'worktreeKeepWhen' && typeof raw === 'string' && WORKTREE_KEEP_VALUES.includes(raw)) value = raw;
    }
    return { key, value, locked: worktreeSettingLocked(locks, 'worktreeCleanup') ||
      worktreeSettingLocked(locks, 'storageCleanup.' + key) };
  });
  return { environmentId, hostOs: typeof os === 'string' ? os : '', cleanupOverride, fields,
    managedBy: typeof policy.organization === 'string' ? policy.organization : '组织' };
}

function hasDirectoryBelowRoot(path: string): boolean {
  let depth = 0;
  for (const segment of path.split('/')) {
    if (!segment || segment === '.') continue;
    if (segment === '..') depth = Math.max(0, depth - 1);
    else depth++;
  }
  return depth > 0;
}
export function worktreeDirectory(hostOs: string, input: string): string {
  const path = input.trim();
  if (path === '') return path;
  if (/[\u0000-\u001f\u007f]/.test(path) || !['darwin', 'linux', 'windows'].includes(hostOs)) {
    throw new Error('请填写宿主机绝对目录');
  }
  if (/^~(?:[\\/]|$)/.test(path)) return path;
  if (hostOs === 'windows') {
    const normalized = path.replace(/\\/g, '/');
    const root = /^(?:[A-Za-z]:\/|\/\/[^/?]+\/[^/]+\/)/.exec(normalized);
    if (root && hasDirectoryBelowRoot(normalized.slice(root[0].length))) return path;
  } else if (path.startsWith('/') && hasDirectoryBelowRoot(path)) return path;
  throw new Error('请填写宿主机绝对目录，不能使用根目录');
}

export function worktreeStorageText(value: StorageValue | undefined): string {
  return value === undefined || value === null ? '' : String(value);
}
export function worktreeStorageNeedsConfirmation(state: WorktreeStorage, key: string, input: string): boolean {
  const previous = worktreeStorageField(state, key)?.value;
  if (SWITCH_KEYS.includes(key)) return input === 'true' && previous === false;
  if (RETENTION_KEYS.includes(key)) return input.trim() !== '' &&
    (previous === null || (typeof previous === 'number' && Number(input) < previous));
  if (key === 'worktreeKeepWhen' && typeof previous === 'string') {
    return WORKTREE_KEEP_VALUES.indexOf(input) > WORKTREE_KEEP_VALUES.indexOf(previous);
  }
  return false;
}

export function worktreeStorageValue(state: WorktreeStorage, key: string, input: string): StorageValue {
  const field = worktreeStorageField(state, key);
  if (!field || field.value === undefined) throw new Error('当前服务不支持此设置');
  if (field.locked) throw new Error('此设置由组织管理');
  if (key === 'worktreesDirectory') return worktreeDirectory(state.hostOs, input);
  if (key === 'worktreeKeepWhen' && WORKTREE_KEEP_VALUES.includes(input)) return input;
  if (SWITCH_KEYS.includes(key) && (input === 'true' || input === 'false')) return input === 'true';
  if (RETENTION_KEYS.includes(key)) {
    const value = input.trim();
    if (value === '') return null;
    if (/^\d+$/.test(value) && validRetention(key, Number(value))) return Number(value);
  }
  throw new Error('设置值无效');
}

export async function readWorktreeStorage(connection: WorktreeSettingsConnection, environmentId: string): Promise<WorktreeStorage> {
  if (!connection.ready || connection.canScope('orchestration:read') === false) throw new Error('环境未连接或没有读取权限');
  const result = await connection.rpcRequest('server.getConfig', {}, 15000, false);
  if (!connection.ready || connection.canScope('orchestration:read') === false) throw new Error('连接或读取权限已变化');
  return worktreeStorage(result, environmentId);
}

export async function writeWorktreeStorage(connection: WorktreeSettingsConnection, environmentId: string, key: string,
  input: string, confirmed: boolean, stillSelected: () => boolean): Promise<WorktreeStorage> {
  if (connection.canScope('settings:write') !== true) throw new Error('此连接没有修改设置的权限');
  const before = await readWorktreeStorage(connection, environmentId);
  if (!stillSelected() || connection.canScope('settings:write') !== true) throw new Error('环境或权限已变化');
  const value = worktreeStorageValue(before, key, input);
  if (value === worktreeStorageField(before, key)?.value) return before;
  if (!confirmed && worktreeStorageNeedsConfirmation(before, key, input)) throw new Error('请刷新后确认清理范围');
  const field: Record<string, StorageValue> = {};
  field[key] = value;
  const patch = key === 'worktreesDirectory' ? field : { storageCleanup: field };
  await connection.rpcRequest('server.updateSettings', { patch }, 15000, false);
  const after = await readWorktreeStorage(connection, environmentId);
  if (worktreeStorageField(after, key)?.value !== value) throw new Error('回读结果与修改不一致，请刷新核对');
  return after;
}
