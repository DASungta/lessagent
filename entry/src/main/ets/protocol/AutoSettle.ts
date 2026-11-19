import { record } from './Wire';
import { WorktreeSettingsConnection } from './WorktreeSettings';

export type AutoSettleKey =
  'sidebarAutoSettleOnMerge' | 'sidebarAutoSettleAfterDays' | 'sidebarAutoSettleKeepPullRequests';
export type AutoSettleValue = boolean | number | null;

export interface AutoSettleField {
  key: AutoSettleKey;
  value: AutoSettleValue | undefined;
  locked: boolean;
}
export interface AutoSettleSettings {
  fields: AutoSettleField[];
  managedBy: string;
}

export const DEFAULT_AUTO_SETTLE_DAYS = 7;
const keys: AutoSettleKey[] = [
  'sidebarAutoSettleOnMerge', 'sidebarAutoSettleAfterDays', 'sidebarAutoSettleKeepPullRequests'
];

export function validAutoSettleDays(value: unknown): value is number {
  return typeof value === 'number' && value >= 1 && value <= 90;
}

export function autoSettleField(snapshot: AutoSettleSettings, key: AutoSettleKey): AutoSettleField {
  const field = snapshot.fields.find(item => item.key === key);
  if (!field) throw new Error('不支持此设置项');
  return field;
}

export function autoSettleSettings(config: Object, expectedEnvironment: string): AutoSettleSettings {
  const root = record(config);
  const environment = record(root.environment);
  if (!expectedEnvironment || environment.environmentId !== expectedEnvironment) {
    throw new Error('环境身份变化，请重新打开设置');
  }
  const capabilities = environment.capabilities === undefined ? {} as Record<string, Object> : record(environment.capabilities);
  const settings = record(root.settings);
  const policy = root.managedPolicy === undefined ? {} as Record<string, Object> : record(root.managedPolicy);
  const locks = Array.isArray(policy.lockedSettings) ? policy.lockedSettings : [];
  return {
    managedBy: typeof policy.organization === 'string' ? policy.organization : '组织',
    fields: keys.map((key: AutoSettleKey): AutoSettleField => {
      const supported = capabilities.threadAutoSettlement === true &&
        (key !== 'sidebarAutoSettleKeepPullRequests' || capabilities.threadAutoSettlementScope === true);
      const raw = settings[key];
      let value: AutoSettleValue | undefined = undefined;
      if (key === 'sidebarAutoSettleAfterDays') {
        if (raw === null) value = null;
        else if (validAutoSettleDays(raw)) value = raw as number;
      } else if (typeof raw === 'boolean') value = raw;
      return {
        key, value: supported ? value : undefined,
        locked: locks.some(path => typeof path === 'string' &&
          (path === key || path.startsWith(key + '.') || key.startsWith(path + '.')))
      };
    })
  };
}

export async function readAutoSettleSettings(connection: WorktreeSettingsConnection,
  environmentId: string): Promise<AutoSettleSettings> {
  if (!connection.ready) throw new Error('环境未连接');
  const config = await connection.rpcRequest('server.getConfig', {}, 15000, false);
  if (!connection.ready) throw new Error('环境已断开');
  return autoSettleSettings(config, environmentId);
}

export async function writeAutoSettleSetting(connection: WorktreeSettingsConnection,
  environmentId: string, key: AutoSettleKey, value: AutoSettleValue): Promise<AutoSettleSettings> {
  if (connection.canScope('settings:write') === false) throw new Error('此连接没有修改设置的权限');
  const before = await readAutoSettleSettings(connection, environmentId);
  if (connection.canScope('settings:write') === false) throw new Error('修改设置的权限已变化');
  const field = autoSettleField(before, key);
  if (field.value === undefined || field.locked) throw new Error('设置不受支持或受组织策略限制');
  const valid = key === 'sidebarAutoSettleAfterDays'
    ? value === null || validAutoSettleDays(value) : typeof value === 'boolean';
  if (!valid) throw new Error('设置值无效');
  if (field.value === value) return before;
  const patch: Record<string, AutoSettleValue> = {};
  patch[key] = value;
  await connection.rpcRequest('server.updateSettings', { patch }, 15000, false);
  const after = await readAutoSettleSettings(connection, environmentId);
  if (autoSettleField(after, key).value !== value) throw new Error('回读结果与修改不一致，请刷新核对');
  return after;
}
