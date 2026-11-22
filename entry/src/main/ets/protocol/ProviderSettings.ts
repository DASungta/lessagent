import { compactArray, record, objects } from './Wire';

export interface ProviderModelView { id: string; name: string; }
export interface ProviderView {
  id: string; name: string; driver: string; status: string; authStatus: string;
  enabled: boolean; installed: boolean; allowed: boolean; canAuthenticate: boolean; models: ProviderModelView[];
}
export interface ProviderAuthView {
  instanceId: string; phase: string; flowId: string; interactionId: string; type: string;
  url: string; code: string; requiresConsent: boolean; expiresAt: number;
}
function safeText(value: Object | undefined, fallback: string = ''): string {
  return typeof value === 'string' ? value.slice(0, 256) : fallback;
}
function identity(value: Object | undefined, optional: boolean = false): string {
  if (optional && (value === null || value === undefined)) return '';
  if (typeof value !== 'string' || !value.trim() || value !== value.trim() || value.length > 256 || /[\u0000-\u001f]/.test(value)) throw new Error('身份字段无效');
  return value;
}
export function providerCatalog(config: Object, expectedEnvironment: string): ProviderView[] {
  const root = record(config);
  if (record(root.environment).environmentId !== expectedEnvironment || !expectedEnvironment) throw new Error('环境身份不一致');
  const policy = root.managedPolicy ? record(root.managedPolicy) : {} as Record<string, Object>;
  const limits = policy.limits ? record(policy.limits) : {} as Record<string, Object>;
  const providerLimits = limits.providers ? record(limits.providers) : {} as Record<string, Object>;
  const allowed = providerLimits.allowedDrivers;
  const seen: string[] = [];
  return objects(root.providers).map((item: Object): ProviderView => {
    const row = record(item); const id = identity(row.instanceId);
    if (!id || seen.includes(id)) throw new Error('Provider 身份无效');
    seen.push(id);
    const setup = row.setup ? record(row.setup) : {} as Record<string, Object>;
    const auth = row.auth ? record(row.auth) : {} as Record<string, Object>;
    return { id, name: safeText(row.displayName, id), driver: safeText(row.driver),
      status: safeText(row.status, 'unknown'), authStatus: safeText(auth.status, 'unknown'),
      enabled: row.enabled === true, installed: row.installed === true,
      allowed: !Array.isArray(allowed) || allowed.includes(row.driver), canAuthenticate: setup.canAuthenticate === true,
      models: compactArray(row.models, (value: Object): ProviderModelView => {
        const model = record(value);
        const slug = safeText(model.slug);
        if (!slug) throw new Error('模型标识无效');
        return { id: slug, name: safeText(model.name, slug) };
      }) };
  });
}
export function providerStatus(provider: ProviderView): string {
  if (!provider.allowed) return '组织策略不可用';
  if (!provider.enabled) return '已停用';
  if (!provider.installed) return '尚未安装';
  if (provider.authStatus === 'unauthenticated') return '尚未登录';
  if (provider.status === 'error') return '连接异常';
  if (provider.status === 'warning') return '需要检查';
  if (provider.authStatus === 'authenticated') return '已登录';
  return provider.status === 'ready' ? '就绪 · 登录状态未知' : '状态未知';
}
export function providerSignInUrl(value: Object | undefined): string {
  if (value === null || value === undefined || value === '') return '';
  if (typeof value !== 'string' || value.length > 16384 || /[\s\\\u0000-\u001f]/.test(value) ||
    !/^https?:\/\/[^/?#@]+(?:[/?#].*)?$/i.test(value)) throw new Error('登录地址无效');
  return value;
}
export function providerAuthView(value: Object, instanceId: string): ProviderAuthView {
  const row = record(value);
  if (row.instanceId !== instanceId) throw new Error('登录状态身份不匹配');
  const phases = ['idle', 'starting', 'waiting', 'verifying', 'succeeded', 'failed', 'cancelled'];
  if (!phases.includes(String(row.phase))) throw new Error('登录状态不受支持');
  const interaction = row.interaction ? record(row.interaction) : {} as Record<string, Object>;
  const type = safeText(interaction.type);
  const expiresAt = row.expiresAt === null || row.expiresAt === undefined ? 0 : Date.parse(String(row.expiresAt));
  if (!Number.isFinite(expiresAt)) throw new Error('登录期限无效');
  return { instanceId, phase: row.phase as string, flowId: identity(row.flowId, true),
    interactionId: identity(interaction.id, true), type,
    url: providerSignInUrl(type === 'browser' || type === 'deviceCode' ? interaction.url : type ? undefined : row.authorizationUrl),
    code: type === 'deviceCode' ? safeText(interaction.userCode) : '',
    requiresConsent: type === 'browser' && interaction.requiresConsent === true, expiresAt };
}
export function providerAuthActive(state: ProviderAuthView): boolean {
  return ['starting', 'waiting', 'verifying'].includes(state.phase) && (!state.expiresAt || state.expiresAt > Date.now());
}
export function providerAuthLabel(state: ProviderAuthView): string {
  if (state.expiresAt && state.expiresAt <= Date.now() && ['starting', 'waiting', 'verifying'].includes(state.phase)) return '登录已过期，请取消后重试';
  switch (state.phase) {
    case 'idle': return '尚未开始登录';
    case 'starting': return '正在准备登录';
    case 'waiting': return '等待你完成验证';
    case 'verifying': return '服务端正在验证';
    case 'succeeded': return '服务端确认登录成功，请刷新模型目录';
    case 'failed': return '登录失败，请检查服务端后重试';
    case 'cancelled': return '服务端确认已取消';
    default: return '状态未知';
  }
}
