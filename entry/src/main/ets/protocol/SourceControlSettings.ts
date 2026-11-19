import { record } from './Wire';
import { WorktreeSettingsConnection, worktreeSettingLocked } from './WorktreeSettings';

const SETTINGS_KEYS = ['defaultAutoPull', 'ghqCloneLayout', 'addProjectBaseDirectory', 'removeAgentCreditsOnMerge'];
export interface SourceControlField { key: string; value: string | boolean | undefined; locked: boolean; }
export interface SourceControlSettings {
  environmentId: string;
  generation?: number;
  managedBy: string;
  fields: SourceControlField[];
}
interface SourceControlConnection extends WorktreeSettingsConnection {
  generationValue?(): number;
  applyVerifiedSettingsConfig?(value: Object, environmentId: string, generation: number | undefined): void;
}

const saving = new Set<string>();

export function sourceControlField(snapshot: SourceControlSettings, key: string): SourceControlField | undefined {
  return snapshot.fields.find(field => field.key === key);
}

export function sourceControlSettings(config: Object, environmentId: string, generation?: number): SourceControlSettings {
  const root = record(config);
  if (!environmentId || record(root.environment).environmentId !== environmentId) throw new Error('环境身份已变化');
  const settings = record(root.settings);
  const policy = root.managedPolicy ? record(root.managedPolicy) : {} as Record<string, Object>;
  const locks = Array.isArray(policy.lockedSettings) ?
    (policy.lockedSettings as Object[]).filter(path => typeof path === 'string') as string[] : [];
  const fields = SETTINGS_KEYS.map((key): SourceControlField => {
    const raw = settings[key];
    const value = key === 'addProjectBaseDirectory' ? (typeof raw === 'string' ? raw : undefined) :
      typeof raw === 'boolean' ? raw : undefined;
    return { key, value, locked: worktreeSettingLocked(locks, key) };
  });
  return { environmentId, generation, fields, managedBy: typeof policy.organization === 'string' ? policy.organization : '组织' };
}

async function readConfig(connection: SourceControlConnection, generation: number | undefined): Promise<Object> {
  if (!connection.ready || connection.canScope('orchestration:read') === false) throw new Error('环境未连接或无读取权限');
  const config = await connection.rpcRequest('server.getConfig', {}, 15000, false);
  if (!connection.ready || connection.canScope('orchestration:read') === false || connection.generationValue?.() !== generation) {
    throw new Error('环境连接或读取权限已变化');
  }
  return config;
}
export async function readSourceControlSettings(connection: SourceControlConnection,
  environmentId: string): Promise<SourceControlSettings> {
  const generation = connection.generationValue?.();
  return sourceControlSettings(await readConfig(connection, generation), environmentId, generation);
}

export async function writeSourceControlSetting(connection: SourceControlConnection, snapshot: SourceControlSettings,
  key: string, value: string | boolean, stillSelected: () => boolean): Promise<SourceControlSettings> {
  const checkContext = (): void => {
    if (!stillSelected() || connection.generationValue?.() !== snapshot.generation) throw new Error('环境已变化');
    if (connection.canScope('settings:write') !== true) throw new Error('没有修改设置的权限');
  };
  checkContext();
  if (!SETTINGS_KEYS.includes(key) || (key === 'addProjectBaseDirectory' ? typeof value !== 'string' : typeof value !== 'boolean')) {
    throw new Error('源码管理设置值无效');
  }
  const normalized = typeof value === 'string' ? value.trim() : value;
  if (saving.has(snapshot.environmentId)) throw new Error('当前环境的源码管理设置正在保存');
  saving.add(snapshot.environmentId);
  try {
    const before = await readSourceControlSettings(connection, snapshot.environmentId);
    checkContext();
    const field = sourceControlField(before, key);
    if (!field || field.value === undefined) throw new Error('当前服务不支持此设置');
    if (field.locked) throw new Error('此设置由组织管理');
    if (field.value !== sourceControlField(snapshot, key)?.value) throw new Error('设置已变化，请刷新核对');
    if (field.value === normalized) return before;
    const patch: Record<string, string | boolean> = {};
    patch[key] = normalized;
    await connection.rpcRequest('server.updateSettings', { patch }, 15000, false);
    const config = await readConfig(connection, snapshot.generation);
    checkContext();
    const after = sourceControlSettings(config, snapshot.environmentId, snapshot.generation);
    if (sourceControlField(after, key)?.value !== normalized) throw new Error('回读结果与修改不一致，请刷新核对');
    if (key === 'addProjectBaseDirectory' || key === 'ghqCloneLayout') {
      connection.applyVerifiedSettingsConfig?.(config, snapshot.environmentId, snapshot.generation);
    }
    return after;
  } finally { saving.delete(snapshot.environmentId); }
}
