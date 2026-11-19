import { record } from './Wire';
import { WorktreeSettingsConnection } from './WorktreeSettings';

export const threadDefaultRuntimeModes: string[] = ['approval-required', 'auto-accept-edits', 'auto', 'full-access'];
export interface ThreadDefaultField { key: string; value: string; supported: boolean; locked: boolean; }
export interface ThreadDefaults {
  environmentId: string;
  fields: ThreadDefaultField[];
  managedBy: string;
  maxRuntimeMode: string;
}

function choices(key: string): string[] {
  if (key === 'defaultRuntimeMode') return threadDefaultRuntimeModes;
  if (key === 'defaultThreadEnvMode') return ['inherit', 'local', 'worktree'];
  if (key === 'responseStreamingMode') return ['turn', 'paragraph'];
  if (key === 'enableAgentBrowserAccess') return ['true', 'false'];
  return [];
}
export function threadDefaultField(snapshot: ThreadDefaults, key: string): ThreadDefaultField {
  const field = snapshot.fields.find((item: ThreadDefaultField) => item.key === key);
  if (!field) throw new Error('不支持此设置项');
  return field;
}
export function threadDefaultAllowed(snapshot: ThreadDefaults, key: string, value: string): boolean {
  const field = threadDefaultField(snapshot, key);
  if (!field.supported || field.locked || !choices(key).includes(value)) return false;
  return key !== 'defaultRuntimeMode' || (snapshot.maxRuntimeMode !== 'unknown' &&
    threadDefaultRuntimeModes.indexOf(value) <= threadDefaultRuntimeModes.indexOf(snapshot.maxRuntimeMode));
}
export function threadDefaults(config: Object, expectedEnvironment: string): ThreadDefaults {
  const root = record(config);
  if (!expectedEnvironment || record(root.environment).environmentId !== expectedEnvironment) {
    throw new Error('环境身份变化，请重新打开设置');
  }
  const settings = record(root.settings);
  const managed = root.managedPolicy ? record(root.managedPolicy) : {} as Record<string, Object>;
  const limits = managed.limits ? record(managed.limits) : {} as Record<string, Object>;
  const locks = Array.isArray(managed.lockedSettings) ? managed.lockedSettings as Object[] : [];
  const max = limits.maxRuntimeMode;
  const fields: ThreadDefaultField[] = [];
  for (const key of ['defaultRuntimeMode', 'defaultThreadEnvMode', 'responseStreamingMode', 'enableAgentBrowserAccess']) {
    const raw = settings[key];
    const value = key === 'defaultThreadEnvMode' && raw === null ? 'inherit' :
      typeof raw === 'string' ? raw : typeof raw === 'boolean' ? String(raw) : '';
    const supported = choices(key).includes(value) &&
      (key === 'enableAgentBrowserAccess' ? typeof raw === 'boolean' :
        key === 'defaultThreadEnvMode' ? raw === null || raw === 'local' || raw === 'worktree' : typeof raw === 'string');
    const locked = locks.some((item: Object) => typeof item === 'string' &&
      (item === key || item.startsWith(key + '.') || key.startsWith(item + '.')));
    fields.push({ key, value, supported, locked });
  }
  return { environmentId: expectedEnvironment, fields,
    managedBy: typeof managed.organization === 'string' ? managed.organization : '组织',
    maxRuntimeMode: max === undefined ? 'full-access' : typeof max === 'string' && threadDefaultRuntimeModes.includes(max) ? max : 'unknown' };
}
export function threadDefaultsPatch(snapshot: ThreadDefaults, key: string, value: string): Object {
  if (!threadDefaultAllowed(snapshot, key, value)) throw new Error('设置不受支持或受组织策略限制');
  if (key === 'defaultRuntimeMode') return { defaultRuntimeMode: value };
  if (key === 'defaultThreadEnvMode') return { defaultThreadEnvMode: value === 'inherit' ? null : value };
  if (key === 'responseStreamingMode') return { responseStreamingMode: value };
  if (key === 'enableAgentBrowserAccess') return { enableAgentBrowserAccess: value === 'true' };
  throw new Error('不支持此设置项');
}
export async function readThreadDefaults(connection: WorktreeSettingsConnection, environmentId: string): Promise<ThreadDefaults> {
  if (!connection.ready) throw new Error('环境未连接');
  const config = await connection.rpcRequest('server.getConfig', {}, 15000, false);
  if (!connection.ready) throw new Error('环境已断开');
  return threadDefaults(config, environmentId);
}
export async function writeThreadDefault(connection: WorktreeSettingsConnection, environmentId: string,
  key: string, value: string): Promise<ThreadDefaults> {
  if (connection.canScope('settings:write') === false) throw new Error('此连接没有修改设置的权限');
  const before = await readThreadDefaults(connection, environmentId);
  if (connection.canScope('settings:write') === false) throw new Error('修改设置的权限已变化');
  const patch = threadDefaultsPatch(before, key, value);
  await connection.rpcRequest('server.updateSettings', { patch }, 15000, false);
  const after = await readThreadDefaults(connection, environmentId);
  if (threadDefaultField(after, key).value !== value) throw new Error('回读结果与修改不一致，请刷新核对');
  return after;
}
