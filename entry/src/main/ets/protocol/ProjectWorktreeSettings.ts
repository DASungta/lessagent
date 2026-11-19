import { record } from './Wire';
import { BRANCH_NAMING_MODES, WorktreeSettingsConnection, worktreeSettingLocked } from './WorktreeSettings';

export const PROJECT_WORKTREE_KEYS: string[] = [
  'newWorktreesStartFromOrigin', 'worktreeSubmodules', 'branchNamingMode', 'branchNamePrefix', 'branchNameInstructions'
];

export interface ProjectWorktreeField {
  key: string;
  value: string | undefined;
  source: 'environment' | 'project';
  locked: boolean;
}
export interface ProjectWorktreeSettings {
  environmentId: string;
  projectId: string;
  supported: boolean;
  managedBy: string;
  fields: ProjectWorktreeField[];
  projectEntry: Record<string, Object>;
  generation?: number;
}

interface ProjectWorktreeConnection extends WorktreeSettingsConnection { generationValue?(): number; }
const writing = new Set<string>();

function optionalRecord(value: Object | undefined): Record<string, Object> {
  return value === undefined ? {} as Record<string, Object> : record(value);
}
function visibleValue(key: string, raw: Object | undefined, source: string): string | undefined {
  if (key === 'newWorktreesStartFromOrigin') return typeof raw === 'boolean' ? String(raw) : undefined;
  if (key === 'worktreeSubmodules') {
    if (raw === 'recursive' || raw === 'top-level' || raw === 'none') return raw as string;
    return source === 'environment' && raw === null ? 'inherit' : undefined;
  }
  if (typeof raw !== 'string') return undefined;
  if (key === 'branchNamingMode' && !BRANCH_NAMING_MODES.includes(raw)) return undefined;
  return raw;
}
export function projectWorktreeField(snapshot: ProjectWorktreeSettings, key: string): ProjectWorktreeField | undefined {
  return snapshot.fields.find(field => field.key === key);
}
export function projectWorktreeSettings(config: Object, environmentId: string, projectId: string,
  generation?: number): ProjectWorktreeSettings {
  const root = record(config);
  const environment = record(root.environment);
  if (!environmentId || environment.environmentId !== environmentId) throw new Error('环境身份已变化');
  if (!projectId.trim() || projectId.length > 256 || /[\x00-\x1f\x7f]/.test(projectId) ||
    ['__proto__', 'prototype', 'constructor'].includes(projectId)) throw new Error('项目身份无效');
  const settings = record(root.settings);
  const capability = optionalRecord(environment.capabilities).projectSettingsOverrides === true;
  const storedOverrides = settings.projectSettingsOverrides;
  const supported = capability && storedOverrides !== undefined && storedOverrides !== null;
  const overrides = storedOverrides === null ? {} as Record<string, Object> : optionalRecord(storedOverrides);
  const projectEntry = Object.prototype.hasOwnProperty.call(overrides, projectId)
    ? record(JSON.parse(JSON.stringify(record(overrides[projectId]))) as Object) : {};
  const policy = optionalRecord(root.managedPolicy);
  const paths = Array.isArray(policy.lockedSettings)
    ? (policy.lockedSettings as Object[]).filter(item => typeof item === 'string') as string[] : [];
  const fields = PROJECT_WORKTREE_KEYS.map((key): ProjectWorktreeField => {
    const source = Object.prototype.hasOwnProperty.call(projectEntry, key) ? 'project' : 'environment';
    return { key, source, value: visibleValue(key, source === 'project' ? projectEntry[key] : settings[key], source),
      locked: worktreeSettingLocked(paths, key) ||
        worktreeSettingLocked(paths, 'projectSettingsOverrides.' + projectId + '.' + key) };
  });
  return { environmentId, projectId, generation, supported, fields, projectEntry,
    managedBy: typeof policy.organization === 'string' ? policy.organization : '组织' };
}

function sameValue(left: Object | undefined, right: Object | undefined): boolean {
  if (left === right) return true;
  if (!left || !right || typeof left !== 'object' || typeof right !== 'object' || Array.isArray(left) !== Array.isArray(right)) return false;
  const a = left as Record<string, Object>;
  const b = right as Record<string, Object>;
  const keys = Object.keys(a);
  return keys.length === Object.keys(b).length && keys.every(key =>
    Object.prototype.hasOwnProperty.call(b, key) && sameValue(a[key], b[key]));
}
export async function readProjectWorktreeSettings(connection: ProjectWorktreeConnection, environmentId: string,
  projectId: string): Promise<ProjectWorktreeSettings> {
  if (!connection.ready || connection.canScope('orchestration:read') === false) throw new Error('环境未连接或无读取权限');
  const generation = connection.generationValue?.();
  const config = await connection.rpcRequest('server.getConfig', {}, 15000, false);
  if (!connection.ready || generation !== connection.generationValue?.() || connection.canScope('orchestration:read') === false) {
    throw new Error('连接或读取权限已变化');
  }
  return projectWorktreeSettings(config, environmentId, projectId, generation);
}

function checkWrite(connection: ProjectWorktreeConnection, snapshot: ProjectWorktreeSettings, stillSelected: () => boolean): void {
  if (!connection.ready || !stillSelected() || snapshot.generation !== connection.generationValue?.()) throw new Error('项目或连接已变化');
  if (connection.canScope('settings:write') !== true) throw new Error('当前连接没有修改设置的权限');
  if (!snapshot.supported) throw new Error('当前服务不支持项目设置覆盖');
}
async function update(connection: ProjectWorktreeConnection, snapshot: ProjectWorktreeSettings, keys: string[],
  value: string | null, stillSelected: () => boolean): Promise<ProjectWorktreeSettings> {
  checkWrite(connection, snapshot, stillSelected);
  const target = snapshot.environmentId + '\n' + snapshot.projectId;
  if (writing.has(target)) throw new Error('该项目设置正在保存，请稍候');
  writing.add(target);
  try {
    const before = await readProjectWorktreeSettings(connection, snapshot.environmentId, snapshot.projectId);
    checkWrite(connection, before, stillSelected);
    if (before.generation !== snapshot.generation || !sameValue(before.projectEntry, snapshot.projectEntry)) {
      throw new Error('项目覆盖已变化，请刷新核对');
    }
    const next = { ...before.projectEntry };
    for (const key of keys) {
      const field = projectWorktreeField(before, key);
      if (!field || field.value === undefined) throw new Error('当前服务不支持此工作树设置');
      if (field.locked) throw new Error('此设置由组织管理');
      if (value === null) {
        delete next[key];
      } else {
        const mode = projectWorktreeField(before, 'branchNamingMode')?.value;
        if ((key === 'branchNamePrefix' && mode !== 'static') || (key === 'branchNameInstructions' && mode !== 'custom')) {
          throw new Error('当前分支命名模式不支持此设置');
        }
        const validated = key === 'newWorktreesStartFromOrigin' && (value === 'true' || value === 'false')
          ? value === 'true' : value;
        if (visibleValue(key, validated, 'project') === undefined) throw new Error('工作树设置值无效');
        next[key] = typeof validated === 'string' ? validated.trim() : validated;
      }
    }
    if (sameValue(before.projectEntry, next)) return before;
    const overrides: Record<string, Object> = {};
    // An empty replacement clears the known fields while retaining any unknown stored fields.
    overrides[before.projectId] = next;
    await connection.rpcRequest('server.updateSettings', { patch: { projectSettingsOverrides: overrides } }, 15000, false);
    const after = await readProjectWorktreeSettings(connection, before.environmentId, before.projectId);
    checkWrite(connection, after, stillSelected);
    if (after.generation !== before.generation || !sameValue(after.projectEntry, next)) throw new Error('回读结果与修改不一致，请刷新核对');
    return after;
  } finally { writing.delete(target); }
}

export function writeProjectWorktreeSettings(connection: ProjectWorktreeConnection, snapshot: ProjectWorktreeSettings,
  key: string, value: string | null, stillSelected: () => boolean): Promise<ProjectWorktreeSettings> {
  return update(connection, snapshot, [key], value, stillSelected);
}
export function clearProjectWorktreeSettings(connection: ProjectWorktreeConnection, snapshot: ProjectWorktreeSettings,
  stillSelected: () => boolean): Promise<ProjectWorktreeSettings> {
  const keys = snapshot.fields.filter(field => field.source === 'project').map(field => field.key);
  return update(connection, snapshot, keys, null, stillSelected);
}
