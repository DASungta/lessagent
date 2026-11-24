import { record } from './Wire';
import { AgentFeedbackMode, parseAgentFeedbackMode } from './AgentFeedback';
import { WorktreeSettingsConnection } from './WorktreeSettings';

export type LabsSettingKey = 'linkedEnvironmentsEnabled' | 'fastWorktreeCheckout';

export interface LabsField {
  value: boolean | undefined;
  locked: boolean;
}

export interface LabsAgentFeedbackField {
  value: AgentFeedbackMode | undefined;
  locked: boolean;
}

export interface LabsSettings {
  environmentId: string;
  managedBy: string;
  linkedEnvironmentsEnabled: LabsField;
  fastWorktreeCheckout: LabsField;
  agentFeedback: LabsAgentFeedbackField;
}

export function labsSettings(config: Object, expectedEnvironment: string): LabsSettings {
  const root = record(config);
  const environment = record(root.environment);
  if (!expectedEnvironment || environment.environmentId !== expectedEnvironment) throw new Error('环境身份变化，请重新打开实验室');
  const capabilities = environment.capabilities === undefined ? {} as Record<string, Object> : record(environment.capabilities);
  const settings = record(root.settings);
  const policy = root.managedPolicy === undefined ? {} as Record<string, Object> : record(root.managedPolicy);
  const locks = Array.isArray(policy.lockedSettings) ? policy.lockedSettings : [];
  const isLocked = (key: string): boolean => locks.some((path: Object) => typeof path === 'string' &&
    (key === path || path.startsWith(key + '.') || key.startsWith(path + '.')));
  const field = (key: LabsSettingKey, eligible: boolean): LabsField => {
    const current = settings[key];
    return {
      value: eligible && typeof current === 'boolean' ? current : undefined,
      locked: isLocked(key)
    };
  };
  const feedbackEligible = capabilities.agentFeedback === true;
  const feedbackMode = feedbackEligible ? parseAgentFeedbackMode(settings.agentFeedback) : undefined;
  return {
    environmentId: expectedEnvironment,
    managedBy: typeof policy.organization === 'string' ? policy.organization : '组织',
    linkedEnvironmentsEnabled: field('linkedEnvironmentsEnabled', capabilities.peerLinks === true),
    fastWorktreeCheckout: field('fastWorktreeCheckout', capabilities.fastWorktreeCheckout === true),
    agentFeedback: {
      value: feedbackMode,
      locked: isLocked('agentFeedback')
    }
  };
}

export async function readLabsSettings(connection: WorktreeSettingsConnection, environmentId: string): Promise<LabsSettings> {
  if (!connection.ready) throw new Error('环境未连接');
  const config = await connection.rpcRequest('server.getConfig', {}, 15000, false);
  if (!connection.ready) throw new Error('环境已断开');
  return labsSettings(config, environmentId);
}

export async function writeLabsSetting(connection: WorktreeSettingsConnection,
  environmentId: string, key: LabsSettingKey, value: boolean): Promise<LabsSettings> {
  if ((key !== 'linkedEnvironmentsEnabled' && key !== 'fastWorktreeCheckout') || typeof value !== 'boolean') {
    throw new Error('不支持此实验设置');
  }
  if (connection.canScope('settings:write') === false) throw new Error('此连接没有修改设置的权限');
  const current = await readLabsSettings(connection, environmentId);
  if (connection.canScope('settings:write') === false) throw new Error('修改设置的权限已变化');
  if (current[key].value === undefined || current[key].locked) throw new Error('设置不受支持或受组织策略限制');
  if (current[key].value === value) return current;
  const patch = key === 'linkedEnvironmentsEnabled' ? { linkedEnvironmentsEnabled: value } : { fastWorktreeCheckout: value };
  await connection.rpcRequest('server.updateSettings', { patch }, 15000, false);
  const result = await readLabsSettings(connection, environmentId);
  if (result[key].value !== value) throw new Error('回读结果与修改不一致，请刷新核对');
  return result;
}

export async function writeAgentFeedbackMode(
  connection: WorktreeSettingsConnection,
  environmentId: string,
  mode: AgentFeedbackMode
): Promise<LabsSettings> {
  if (mode !== 'off' && mode !== 'on-request' && mode !== 'auto') {
    throw new Error('不支持此反馈模式');
  }
  if (connection.canScope('settings:write') === false) throw new Error('此连接没有修改设置的权限');
  const current = await readLabsSettings(connection, environmentId);
  if (connection.canScope('settings:write') === false) throw new Error('修改设置的权限已变化');
  if (current.agentFeedback.value === undefined || current.agentFeedback.locked) {
    throw new Error('设置不受支持或受组织策略限制');
  }
  if (current.agentFeedback.value === mode) return current;
  const feedbackPatch: Record<string, Object> = { mode };
  const patch: Record<string, Object> = { agentFeedback: feedbackPatch };
  await connection.rpcRequest('server.updateSettings', { patch }, 15000, false);
  const result = await readLabsSettings(connection, environmentId);
  if (result.agentFeedback.value !== mode) throw new Error('回读结果与修改不一致，请刷新核对');
  return result;
}
