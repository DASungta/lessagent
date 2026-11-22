import { record, serverBase, text } from './Wire';
import { SavedSession, RecoveryState, recoveryState } from './Core';

export interface EnvironmentEntry {
  localId: string; environmentId: string; base: string; label: string;
  enabled: boolean; kind: string; credentialRef: string; deleting?: boolean; pendingBase?: string; prRouting?: string;
  cloudAccountId?: string;
  recovery: RecoveryReference[];
  alternateRoutes?: DirectRoute[]; recoveryBase?: string; retiredCredentialRefs?: string[];
}
export interface DirectRoute { base: string; credentialRef: string; }
export function environmentRoutes(entry: EnvironmentEntry): DirectRoute[] {
  if (entry.kind === 'cloud') return [];
  return [{ base: entry.base, credentialRef: entry.credentialRef }].concat(entry.alternateRoutes || [])
    .map((route: DirectRoute): DirectRoute => ({ base: route.base, credentialRef: route.credentialRef }));
}
export function environmentRouteKey(entry: EnvironmentEntry): string {
  if (entry.kind === 'cloud') return entry.localId + ':cloud:' + (entry.cloudAccountId || '') + ':' + entry.base;
  return entry.localId + ':' + environmentRoutes(entry).map((route: DirectRoute) => route.credentialRef).join(',');
}
function credentialRef(value: Object, localId: string): string {
  const ref = text(value);
  if (ref !== 't3-v2-' + localId + '-session' &&
    !new RegExp('^t3-v2-' + localId + '-route-[a-zA-Z0-9-]{1,64}-session$').test(ref)) throw new Error('路径凭据引用越界');
  return ref;
}
export interface RecoveryReference { threadId: string; alias: string; }
export interface EnvironmentDirectory {
  schemaVersion: number; generation: number; selectedLocalId: string;
  entries: EnvironmentEntry[];
}
export interface ValueStore<T> {
  load(): Promise<T | undefined>;
  save(value: T): Promise<void>;
  clear(): Promise<void>;
}
export interface EnvironmentAssets {
  session(alias: string): ValueStore<SavedSession>;
  recovery(alias: string): ValueStore<RecoveryState>;
}
function keys(row: Record<string, Object>, expected: string[]): void {
  if (Object.keys(row).length !== expected.length || Object.keys(row).some((key: string) => !expected.includes(key))) {
    throw new Error('环境目录字段无效');
  }
}
function id(value: Object): string {
  const result = text(value);
  if (!/^[a-zA-Z0-9-]{1,64}$/.test(result)) throw new Error('环境本机标识无效');
  return result;
}
function identity(value: Object): string {
  const result = text(value);
  if (!result || result.length > 256 || /[\u0000-\u001f\u007f]/.test(result)) throw new Error('环境身份无效');
  return result;
}
export function savedSession(value: Object): SavedSession {
  const row = record(value);
  keys(row, ['base', 'environmentId', 'token', 'expiresAt']);
  const base = text(row.base);
  if (serverBase(base) !== base || !text(row.token) || typeof row.expiresAt !== 'number' ||
    !Number.isFinite(row.expiresAt) || row.expiresAt <= 0) throw new Error('安全凭据记录无效');
  return { base, environmentId: identity(row.environmentId), token: text(row.token), expiresAt: row.expiresAt as number };
}
function checkedRecovery(value: Object, base: string, environmentId: string): RecoveryState {
  const row = record(value);
  keys(row, ['base', 'environmentId', 'threadId', 'pendingId', 'pendingKind']);
  text(row.pendingId); text(row.pendingKind);
  const state = recoveryState(row, base, environmentId);
  if (!state.threadId) throw new Error('恢复会话标识无效');
  return state;
}
async function verifyAssets(directory: EnvironmentDirectory, assets: EnvironmentAssets): Promise<void> {
  const checks: Promise<void>[] = [];
  for (const entry of directory.entries) {
    if (entry.deleting || entry.pendingBase) continue;
    if (entry.kind !== 'cloud') {
      for (const route of environmentRoutes(entry)) {
        checks.push((async (): Promise<void> => {
          const value = await assets.session(route.credentialRef).load();
          if (!value) throw new Error('环境凭据记录缺失，未覆盖目录');
          const session = savedSession(value);
          if (session.base !== route.base || session.environmentId !== entry.environmentId) throw new Error('环境凭据身份不一致');
        })());
      }
    }
    for (const ref of entry.recovery) {
      checks.push((async (): Promise<void> => {
        const value = await assets.recovery(ref.alias).load();
        if (!value || checkedRecovery(value, entry.recoveryBase || entry.base, entry.environmentId).threadId !== ref.threadId) {
          throw new Error('环境恢复记录缺失或不一致');
        }
      })());
    }
  }
  await Promise.all(checks);
}
export function environmentDirectory(value: Object): EnvironmentDirectory {
  const row = record(value);
  keys(row, ['schemaVersion', 'generation', 'selectedLocalId', 'entries']);
  if (row.schemaVersion !== 2 || typeof row.generation !== 'number' || !Number.isSafeInteger(row.generation) ||
    row.generation < 0 || !Array.isArray(row.entries)) throw new Error('环境目录版本或结构无效');
  const entries: EnvironmentEntry[] = [];
  const aliases: string[] = [];
  for (const item of row.entries as Object[]) {
    const entry = record(item);
    keys(entry, ['localId', 'environmentId', 'base', 'label', 'enabled', 'kind', 'credentialRef', 'recovery'].concat(
      Object.keys(entry).includes('deleting') ? ['deleting'] : []).concat(
      Object.keys(entry).includes('pendingBase') ? ['pendingBase'] : []).concat(
      Object.keys(entry).includes('prRouting') ? ['prRouting'] : []).concat(
      Object.keys(entry).includes('cloudAccountId') ? ['cloudAccountId'] : []).concat(
      Object.keys(entry).includes('alternateRoutes') ? ['alternateRoutes'] : []).concat(
      Object.keys(entry).includes('recoveryBase') ? ['recoveryBase'] : []).concat(
      Object.keys(entry).includes('retiredCredentialRefs') ? ['retiredCredentialRefs'] : []));
    if (entry.prRouting !== undefined && !['off', 'read', 'read-write'].includes(text(entry.prRouting))) throw new Error('PR 路由权限无效');
    if (entry.deleting !== undefined && typeof entry.deleting !== 'boolean') throw new Error('环境删除状态无效');
    if (entry.pendingBase !== undefined && (serverBase(text(entry.pendingBase)) !== entry.pendingBase || entry.deleting === true)) {
      throw new Error('环境地址更新状态无效');
    }
    const localId = id(entry.localId);
    const base = text(entry.base);
    const environmentId = identity(entry.environmentId);
    const kind = text(entry.kind);
    const cloudAccountId = entry.cloudAccountId === undefined ? '' : identity(entry.cloudAccountId);
    if (serverBase(base) !== base || text(entry.label).length > 256 || typeof entry.enabled !== 'boolean' ||
      (entry.deleting === true && entry.enabled !== false) ||
      (kind !== 'bearer' && kind !== 'cloud') || !Array.isArray(entry.recovery) ||
      entries.some((e: EnvironmentEntry) => e.localId === localId ||
        (e.environmentId === environmentId && e.kind === kind))) throw new Error('环境目录条目无效');
    if (kind === 'cloud' && (!cloudAccountId || !base.startsWith('https://') ||
      entry.alternateRoutes !== undefined || entry.pendingBase !== undefined)) throw new Error('云环境目录条目无效');
    const primaryRef = kind === 'cloud' ? text(entry.credentialRef) : credentialRef(entry.credentialRef, localId);
    if (kind === 'cloud' && primaryRef !== 't3-cloud-' + localId) throw new Error('云环境凭据引用无效');
    if (aliases.includes(primaryRef)) throw new Error('重复的路径凭据引用');
    aliases.push(primaryRef);
    const alternateRoutes: DirectRoute[] = [];
    if (entry.alternateRoutes !== undefined) {
      if (!Array.isArray(entry.alternateRoutes)) throw new Error('路径目录无效');
      for (const item of entry.alternateRoutes as Object[]) {
        const route = record(item); keys(route, ['base', 'credentialRef']);
        const routeBase = text(route.base); const ref = credentialRef(route.credentialRef, localId);
        if (serverBase(routeBase) !== routeBase || routeBase === base || alternateRoutes.some((r: DirectRoute) => r.base === routeBase) || aliases.includes(ref)) throw new Error('路径地址或引用重复');
        aliases.push(ref); alternateRoutes.push({ base: routeBase, credentialRef: ref });
      }
    }
    if (entry.recoveryBase !== undefined && serverBase(text(entry.recoveryBase)) !== entry.recoveryBase) throw new Error('恢复身份锚点无效');
    const retiredCredentialRefs: string[] = [];
    if (entry.retiredCredentialRefs !== undefined) {
      if (!Array.isArray(entry.retiredCredentialRefs)) throw new Error('待清理凭据目录无效');
      for (const value of entry.retiredCredentialRefs as Object[]) {
        const ref = credentialRef(value, localId);
        if (aliases.includes(ref)) throw new Error('待清理凭据仍在使用或重复');
        aliases.push(ref); retiredCredentialRefs.push(ref);
      }
    }
    const recovery: RecoveryReference[] = [];
    for (const ref of entry.recovery as Object[]) {
      const r = record(ref);
      keys(r, ['threadId', 'alias']);
      const threadId = text(r.threadId);
      const alias = text(r.alias);
      if (!threadId || threadId.length > 128 || !alias.startsWith('t3-v2-' + localId + '-recovery-') ||
        !/^[a-zA-Z0-9-]{1,200}$/.test(alias) || aliases.includes(alias) ||
        recovery.some((prior: RecoveryReference) => prior.threadId === threadId)) throw new Error('恢复引用无效');
      aliases.push(alias); recovery.push({ threadId, alias });
    }
    const checked: EnvironmentEntry = { localId, environmentId, base, label: text(entry.label), enabled: entry.enabled as boolean,
      kind, credentialRef: primaryRef, recovery };
    if (kind === 'cloud') checked.cloudAccountId = cloudAccountId;
    if (entry.deleting !== undefined) checked.deleting = entry.deleting as boolean;
    if (entry.pendingBase !== undefined) checked.pendingBase = text(entry.pendingBase);
    if (entry.prRouting !== undefined) checked.prRouting = text(entry.prRouting);
    if (entry.alternateRoutes !== undefined) checked.alternateRoutes = alternateRoutes;
    if (entry.recoveryBase !== undefined) checked.recoveryBase = text(entry.recoveryBase);
    if (entry.retiredCredentialRefs !== undefined) checked.retiredCredentialRefs = retiredCredentialRefs;
    entries.push(checked);
  }
  const selectedLocalId = text(row.selectedLocalId);
  if (selectedLocalId && !entries.some((e: EnvironmentEntry) => e.localId === selectedLocalId)) throw new Error('所选环境不存在');
  return { schemaVersion: 2, generation: row.generation as number, selectedLocalId, entries };
}

// Directory commit is the only activation point. Fixed legacy aliases make retries crash-idempotent.
// Never run v1 and v2 writers together after activation.
export async function migrateLegacy(directoryStore: ValueStore<EnvironmentDirectory>, assets: EnvironmentAssets,
  legacySession: ValueStore<SavedSession>, legacyRecovery: ValueStore<RecoveryState>): Promise<EnvironmentDirectory> {
  const existing = await directoryStore.load();
  if (existing !== undefined) {
    const checked = environmentDirectory(existing);
    await verifyAssets(checked, assets);
    return checked;
  }
  const source = await legacySession.load();
  const oldRecovery = await legacyRecovery.load();
  const directory: EnvironmentDirectory = { schemaVersion: 2, generation: 1, selectedLocalId: '', entries: [] };
  if (source === undefined) {
    if (oldRecovery !== undefined) throw new Error('存在无对应凭据的恢复记录，请先核对；旧记录已保留');
  } else {
    const session = savedSession(source); // Expiry does not erase environment or pending facts.
    const recovery = oldRecovery !== undefined ? checkedRecovery(oldRecovery, session.base, session.environmentId) : undefined;
    if (recovery && !recovery.threadId) throw new Error('旧恢复会话标识无效，旧记录已保留');
    const entry: EnvironmentEntry = { localId: 'legacy-v1', environmentId: session.environmentId,
      base: session.base, label: session.environmentId, enabled: true, kind: 'bearer',
      credentialRef: 't3-v2-legacy-v1-session', recovery: [] };
    const target = assets.session(entry.credentialRef);
    await target.save(session);
    if (JSON.stringify(await target.load()) !== JSON.stringify(session)) throw new Error('凭据回读校验失败，旧记录已保留');
    if (recovery) {
      const alias = 't3-v2-legacy-v1-recovery-initial';
      const targetRecovery = assets.recovery(alias);
      await targetRecovery.save(recovery);
      if (JSON.stringify(await targetRecovery.load()) !== JSON.stringify(recovery)) throw new Error('恢复记录回读校验失败，旧记录已保留');
      entry.recovery.push({ threadId: recovery.threadId, alias });
    }
    directory.entries.push(entry); directory.selectedLocalId = entry.localId;
  }
  await verifyAssets(directory, assets);
  await directoryStore.save(environmentDirectory(directory));
  return directory;
}

// Upstream state/pullRequestRouting.ts: both saved endpoints must opt in.
export function pullRequestRoutingAllowed(directory: EnvironmentDirectory, originId: string, targetId: string, write: boolean): boolean {
  const origin = directory.entries.find((e: EnvironmentEntry) => e.localId === originId);
  const target = directory.entries.find((e: EnvironmentEntry) => e.localId === targetId);
  if (!origin?.enabled || !target?.enabled || origin.deleting || target.deleting || origin.pendingBase || target.pendingBase) return false;
  const sourcePermission = origin.prRouting || 'off'; const targetPermission = target.prRouting || 'off';
  return write ? sourcePermission === 'read-write' && targetPermission === 'read-write' :
    ['read', 'read-write'].includes(sourcePermission) && ['read', 'read-write'].includes(targetPermission);
}
