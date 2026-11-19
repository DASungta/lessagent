import { util, url } from '@kit.ArkTS';
import { directHostKind } from '../protocol/Hosts';
import { T3Client, CloudTransport } from './T3Client';
import { SessionStore } from '../storage/SessionStore';
import { EnvironmentStore, ProtectedEnvironmentAssets } from '../storage/EnvironmentStore';
import { EnvironmentDirectory, EnvironmentEntry, EnvironmentAssets, RecoveryReference, DirectRoute, environmentRoutes, environmentDirectory, migrateLegacy, savedSession, pullRequestRoutingAllowed } from '../protocol/Environment';
import { RecoveryState, RecoveryStorage, SessionStorage, recoveryState, SavedSession } from '../protocol/Core';
import { pairingTarget } from '../protocol/Pairing';

class ScopedSession implements SessionStorage {
  private registry: EnvironmentRegistry;
  private localId: string;
  constructor(registry: EnvironmentRegistry, localId: string) { this.registry = registry; this.localId = localId; }
  async load(base?: string): Promise<SavedSession | undefined> {
    const entry = this.registry.entry(this.localId);
    const route = environmentRoutes(entry).find((route: DirectRoute) => route.base === (base || entry.base));
    if (!route) throw new Error('连接路径已移除');
    const value = await this.registry.assets.session(route.credentialRef).load();
    if (value && (value.base !== route.base || value.environmentId !== entry.environmentId)) throw new Error('路径凭据身份不一致');
    return value;
  }
  async save(value: SavedSession): Promise<void> {
    const entry = this.registry.entry(this.localId);
    const route = environmentRoutes(entry).find((route: DirectRoute) => route.base === value.base);
    if (!route || value.environmentId !== entry.environmentId) throw new Error('路径凭据身份不一致');
    await this.registry.assets.session(route.credentialRef).save(value);
  }
  async clear(): Promise<void> { throw new Error('请通过环境管理移除连接'); }
}

class ScopedRecovery implements RecoveryStorage {
  private registry: EnvironmentRegistry;
  private localId: string;
  constructor(registry: EnvironmentRegistry, localId: string) { this.registry = registry; this.localId = localId; }
  async load(): Promise<RecoveryState | undefined> {
    const entry = this.registry.entry(this.localId);
    const ref = entry.recovery[0];
    return ref ? this.registry.assets.recovery(ref.alias).load() : undefined;
  }
  async save(value: RecoveryState): Promise<void> { await this.registry.saveRecovery(this.localId, value); }
  async clear(): Promise<void> { throw new Error('恢复记录仅能随已核对的环境移除'); }
}

export class EnvironmentRegistry {
  directory: EnvironmentDirectory = { schemaVersion: 2, generation: 0, selectedLocalId: '', entries: [] };
  clients: Map<string, T3Client> = new Map();
  assets: EnvironmentAssets;
  cloudAccountId: string = '';
  private cloudFactory: ((entry: EnvironmentEntry) => CloudTransport) | undefined = undefined;
  private legacySession: SessionStorage;
  private legacyRecovery: RecoveryStorage;
  onUpdate: () => void = () => {};
  initialized: boolean = false;
  private initializing: Promise<void> | undefined = undefined;
  private store: EnvironmentStore;
  private writes: Promise<void> = Promise.resolve();
  constructor(filesDir: string, assets: EnvironmentAssets = new ProtectedEnvironmentAssets(),
    legacySession: SessionStorage = new SessionStore(),
    legacyRecovery: RecoveryStorage = new SessionStore<RecoveryState>('t3-harmony-recovery-v1')) {
    this.store = new EnvironmentStore(filesDir); this.assets = assets;
    this.legacySession = legacySession; this.legacyRecovery = legacyRecovery;
  }
  private write(action: () => Promise<void>): Promise<void> {
    const result = this.writes.then(action);
    this.writes = result.catch(() => {});
    return result;
  }
  private notify(): void {
    // UI failures must never turn a committed directory into a credential rollback.
    try { this.onUpdate(); } catch (_) {}
  }
  private copy(): EnvironmentDirectory { return environmentDirectory(JSON.parse(JSON.stringify(this.directory)) as Object); }
  private async commit(next: EnvironmentDirectory): Promise<void> {
    next.generation = this.directory.generation + 1;
    await this.store.save(next);
    this.directory = next;
    this.notify();
  }
  entry(localId: string): EnvironmentEntry {
    const entry = this.directory.entries.find((e: EnvironmentEntry) => e.localId === localId);
    if (!entry || entry.deleting || entry.pendingBase) throw new Error('环境不存在或正在移除');
    return entry;
  }
  async initialize(): Promise<void> {
    await this.runInitialize(false);
  }
  async reload(): Promise<void> {
    this.clients.forEach((client: T3Client) => client.disconnect('正在重新读取环境目录'));
    this.clients.clear();
    this.initialized = false;
    await this.runInitialize(true);
  }
  private async runInitialize(force: boolean): Promise<void> {
    if (this.initialized && !force) return;
    if (this.initializing) return this.initializing;
    this.initializing = this.initializeOnce();
    try { await this.initializing; }
    finally { this.initializing = undefined; }
  }
  private async initializeOnce(): Promise<void> {
    this.directory = await migrateLegacy(this.store, this.assets, this.legacySession, this.legacyRecovery);
    for (const entry of this.directory.entries.slice()) {
      if (entry.deleting) await this.finishRemoval(entry.localId);
      else {
        if (entry.pendingBase) await this.finishEdit(entry.localId);
        if (entry.retiredCredentialRefs?.length) await this.finishRetiredCredentials(entry.localId);
        if (entry.retiredCredentialRefs?.length) await this.finishRetiredCredentials(entry.localId);
        this.bind(this.entry(entry.localId));
      }
    }
    this.initialized = true;
  }
  entryVisible(entry: EnvironmentEntry): boolean {
    return entry.kind !== 'cloud' || (!!this.cloudAccountId && entry.cloudAccountId === this.cloudAccountId);
  }
  findEnvironment(environmentId: string): EnvironmentEntry | undefined {
    return this.directory.entries.find((entry: EnvironmentEntry) => entry.environmentId === environmentId && !entry.deleting);
  }
  findEnvironmentOfKind(environmentId: string, kind: string): EnvironmentEntry | undefined {
    return this.directory.entries.find((entry: EnvironmentEntry) =>
      entry.environmentId === environmentId && entry.kind === kind && !entry.deleting);
  }
  async setCloudAccount(accountId: string, factory: ((entry: EnvironmentEntry) => CloudTransport) | undefined): Promise<void> {
    await this.write(async () => {
      this.cloudAccountId = accountId;
      this.cloudFactory = factory;
      for (const entry of this.directory.entries.filter((row: EnvironmentEntry) => row.kind === 'cloud')) {
        const active = !!accountId && entry.cloudAccountId === accountId && !!factory;
        const existing = this.clients.get(entry.localId);
        if (!active) {
          existing?.disconnect('T3 Connect 账号已退出');
          this.clients.delete(entry.localId);
        } else if (existing) {
          existing.disconnect('T3 Connect 账号凭证已更新');
          existing.cloud = factory?.(entry);
          existing.status = existing.cloud ? '未连接' : 'T3 Connect 未登录';
        } else {
          this.bind(entry);
        }
      }
      const selected = this.directory.entries.find((entry: EnvironmentEntry) => entry.localId === this.directory.selectedLocalId);
      if (selected && !selected.deleting && this.entryVisible(selected)) return;
      const next = this.copy();
      next.selectedLocalId = next.entries.find((entry: EnvironmentEntry) => !entry.deleting && this.entryVisible(entry))?.localId || '';
      await this.commit(next);
    });
  }
  async addCloud(environmentId: string, label: string, base: string, accountId: string): Promise<string> {
    let localId = '';
    await this.write(async () => {
      if (!this.cloudAccountId || accountId !== this.cloudAccountId || !this.cloudFactory) {
        throw new Error('T3 Connect 账号未激活');
      }
      if (!base.startsWith('https://')) throw new Error('T3 Connect 环境地址必须是 HTTPS');
      const existing = this.findEnvironmentOfKind(environmentId, 'cloud');
      if (existing) {
        if (existing.cloudAccountId === accountId) { localId = existing.localId; return; }
        throw new Error('该环境已属于另一个 T3 Connect 账号');
      }
      localId = util.generateRandomUUID();
      const entry: EnvironmentEntry = { localId, environmentId, base, label,
        enabled: true, kind: 'cloud', cloudAccountId: accountId,
        credentialRef: 't3-cloud-' + localId, recovery: [] };
      const client = this.bind(entry);
      const next = this.copy(); next.entries.push(entry); next.selectedLocalId = localId;
      try { await this.commit(next); }
      catch (error) { client.disconnect('环境目录保存失败'); this.clients.delete(localId); throw error as Error; }
    });
    return localId;
  }
  async syncCloudEndpoint(environmentId: string, accountId: string, label: string, base: string): Promise<void> {
    await this.write(async () => {
      const entry = this.directory.entries.find((row: EnvironmentEntry) => row.kind === 'cloud' &&
        row.cloudAccountId === accountId && row.environmentId === environmentId && !row.deleting);
      if (!entry || (entry.base === base && entry.label === label)) return;
      const next = this.copy();
      const target = next.entries.find((row: EnvironmentEntry) => row.localId === entry.localId) as EnvironmentEntry;
      const anchor = target.recoveryBase || target.base;
      target.base = base; target.label = label;
      target.recoveryBase = anchor === base ? undefined : anchor;
      const client = this.clients.get(entry.localId);
      if (client) client.recoveryBase = anchor;
      await this.commit(next);
    });
  }
  async removeCloudAccount(accountId: string): Promise<void> {
    const entries = this.directory.entries.filter((entry: EnvironmentEntry) =>
      entry.kind === 'cloud' && entry.cloudAccountId === accountId && !entry.deleting);
    for (const entry of entries) await this.remove(entry.localId);
  }
  private bind(entry: EnvironmentEntry): T3Client {
    const client = new T3Client();
    client.expectedEnvironmentId = entry.environmentId;
    client.recoveryBase = entry.recoveryBase || entry.base;
    client.reconnectSavedRoutes = () => this.reconnect(entry.localId);
    client.recoveryStore = new ScopedRecovery(this, entry.localId);
    client.onUpdate = () => this.notify();
    if (entry.kind === 'cloud') {
      client.cloud = this.cloudFactory && entry.cloudAccountId === this.cloudAccountId ? this.cloudFactory(entry) : undefined;
      client.status = client.cloud ? '未连接' : 'T3 Connect 未登录';
    } else client.store = new ScopedSession(this, entry.localId);
    this.clients.set(entry.localId, client);
    return client;
  }
  async saveRecovery(localId: string, value: RecoveryState): Promise<void> {
    await this.write(async () => {
      const entry = this.entry(localId);
      const checked = recoveryState(value, entry.recoveryBase || entry.base, entry.environmentId);
      if (!checked.threadId) throw new Error('恢复会话标识无效');
      const ref = entry.recovery.find((r) => r.threadId === checked.threadId);
      const alias = ref?.alias || 't3-v2-' + localId + '-recovery-' + util.generateRandomUUID();
      await this.assets.recovery(alias).save(checked);
      const next = this.copy();
      const target = next.entries.find((e: EnvironmentEntry) => e.localId === localId) as EnvironmentEntry;
      const reference: RecoveryReference = { threadId: checked.threadId, alias };
      target.recovery = [reference].concat(target.recovery.filter((r) => r.threadId !== checked.threadId));
      await this.commit(next);
    });
  }
  async add(input: string, code: string): Promise<string> {
    let added = '';
    await this.write(async () => {
      const target = pairingTarget(input, code);
      const knownEntries = this.directory.entries.filter((e: EnvironmentEntry) => environmentRoutes(e).some((route: DirectRoute) => route.base === target.base));
      if (knownEntries.length > 1) throw new Error('此地址对应多个环境，请先核对连接记录');
      const known = knownEntries[0];
      if (known) {
        const entry = this.entry(known.localId);
        const client = this.clients.get(entry.localId);
        if (!client) throw new Error('环境尚未初始化');
        // A known address may refresh its credential; its pinned identity and recovery aliases stay intact.
        await client.connect(target.base, target.code);
        if (!client.ready) throw new Error(client.status);
        if (!entry.enabled || this.directory.selectedLocalId !== entry.localId) {
          const next = this.copy();
          const restored = next.entries.find((e: EnvironmentEntry) => e.localId === entry.localId) as EnvironmentEntry;
          restored.enabled = true; next.selectedLocalId = entry.localId;
          try { await this.commit(next); } catch (error) { client.disconnect('连接记录保存失败，请重试'); throw error as Error; }
        }
        added = entry.localId; return;
      }
      const localId = util.generateRandomUUID();
      const client = new T3Client();
      const credentialRef = 't3-v2-' + localId + '-session';
      const store = this.assets.session(credentialRef);
      client.store = store;
      client.validateIdentity = (environmentId: string) => {
        if (this.directory.entries.some((e: EnvironmentEntry) => e.environmentId === environmentId)) {
          throw new Error('该环境已添加，请使用已有地址更新配对；更改地址须从已有环境设置操作');
        }
      };
      try {
        await client.connect(target.base, target.code);
        if (!client.ready) throw new Error(client.status);
        const saved = savedSession(await store.load() as SavedSession);
        const entry: EnvironmentEntry = { localId, environmentId: saved.environmentId, base: saved.base,
          label: client.environmentLabel || client.server, enabled: true, kind: 'bearer', credentialRef, recovery: [] };
        const next = this.copy(); next.entries.push(entry); next.selectedLocalId = localId;
        this.clients.set(localId, client);
        await this.commit(next);
        client.validateIdentity = () => {};
        client.expectedEnvironmentId = entry.environmentId;
        client.recoveryBase = entry.base;
        client.store = new ScopedSession(this, localId);
        client.reconnectSavedRoutes = () => this.reconnect(localId);
        client.recoveryStore = new ScopedRecovery(this, localId);
        client.onUpdate = () => this.notify();
        this.clients.set(localId, client);
        added = localId;
      } catch (error) {
        client.disconnect(); this.clients.delete(localId); await store.clear(); throw error as Error;
      }
    });
    this.notify();
    return added;
  }
  async select(localId: string): Promise<void> {
    await this.write(async () => {
      this.entry(localId);
      if (this.directory.selectedLocalId === localId) return;
      const next = this.copy(); next.selectedLocalId = localId; await this.commit(next);
    });
  }
  async setEnabled(localId: string, enabled: boolean): Promise<void> {
    await this.write(async () => {
      this.entry(localId);
      const next = this.copy();
      const entry = next.entries.find((e: EnvironmentEntry) => e.localId === localId) as EnvironmentEntry;
      entry.enabled = enabled; await this.commit(next);
      if (!enabled) this.clients.get(localId)?.disconnect('环境已停用，服务端任务继续');
    });
    if (enabled) await this.reconnect(localId);
  }
  async reconnect(localId: string, code: string = ''): Promise<void> {
    const entry = this.entry(localId);
    if (!entry.enabled) throw new Error('请先启用环境');
    const client = this.clients.get(localId);
    if (!client) throw new Error('环境尚未初始化');
    if (entry.kind === 'cloud') {
      if (!client.cloud) throw new Error('T3 Connect 未登录或账号不匹配');
      await client.connect(entry.base);
      if (client.ready) return;
      throw new Error(client.status);
    }
    const routes = code ? environmentRoutes(entry).slice(0, 1) : environmentRoutes(entry);
    for (const route of routes) {
      await client.connect(route.base, code);
      if (client.ready) return;
    }
    throw new Error(client.status);
  }
  private replaceRoutes(entry: EnvironmentEntry, routes: DirectRoute[]): void {
    if (!routes.length) throw new Error('环境至少需要一条连接路径');
    const anchor = entry.recoveryBase || entry.base;
    entry.base = routes[0].base; entry.credentialRef = routes[0].credentialRef;
    entry.alternateRoutes = routes.length > 1 ? routes.slice(1) : undefined;
    entry.recoveryBase = anchor === entry.base ? undefined : anchor;
  }
  private insertRoute(routes: DirectRoute[], route: DirectRoute): DirectRoute[] {
    const kind = directHostKind(new url.URL(route.base).hostname);
    const rank = (kind: string): number => kind === 'loopback' ? 0 : kind === 'lan' ? 1 : ['tailnet', 'vpn'].includes(kind) ? 2 : 3;
    const index = routes.findIndex((existing: DirectRoute) => {
      const existingKind = directHostKind(new url.URL(existing.base).hostname);
      return rank(existingKind) > rank(kind) || existingKind === kind;
    });
    const result = routes.slice(); result.splice(index < 0 ? result.length : index, 0, route); return result;
  }
  async addRoute(localId: string, input: string, code: string): Promise<void> {
    await this.write(async () => {
      const entry = this.entry(localId);
      if (entry.kind !== 'bearer') throw new Error('T3 Connect 环境不接受直连路径');
      const target = pairingTarget(input, code);
      const owner = this.clients.get(localId);
      if (owner?.connectionPending || owner?.submitting) throw new Error('正在连接或提交，请稍候添加路径');
      const existing = environmentRoutes(entry).find((route: DirectRoute) => route.base === target.base);
      const reference = existing?.credentialRef || 't3-v2-' + localId + '-route-' + util.generateRandomUUID() + '-session';
      const store = this.assets.session(reference); const probe = new T3Client();
      probe.expectedEnvironmentId = entry.environmentId; probe.store = store;
      let committed = false;
      try {
        await probe.connect(target.base, target.code);
        if (!probe.ready) throw new Error(probe.status);
        const saved = savedSession(await store.load() as SavedSession);
        if (saved.base !== target.base || saved.environmentId !== entry.environmentId) throw new Error('路径凭据回读身份不一致');
        if (!existing || !entry.enabled) {
          const next = this.copy(); const edited = next.entries.find((e: EnvironmentEntry) => e.localId === localId) as EnvironmentEntry;
          if (!existing) {
            this.replaceRoutes(edited, this.insertRoute(environmentRoutes(entry), { base: target.base, credentialRef: reference }));
            edited.prRouting = undefined;
          }
          edited.enabled = true; await this.commit(next);
        }
        committed = true;
      } finally {
        probe.disconnect();
        if (!committed && !existing) await store.clear();
      }
    });
    if (!this.clients.get(localId)?.submitting) await this.reconnect(localId);
  }
  async reorderRoutes(localId: string, references: string[]): Promise<void> {
    await this.write(async () => {
      const entry = this.entry(localId); const routes = environmentRoutes(entry);
      if (references.length !== routes.length || new Set(references).size !== routes.length ||
        references.some((ref: string) => !routes.some((route: DirectRoute) => route.credentialRef === ref))) throw new Error('路径排序必须包含每条路径一次');
      if (references.every((ref: string, index: number) => ref === routes[index].credentialRef)) return;
      const ordered = references.map((ref: string): DirectRoute => routes.find((route: DirectRoute) => route.credentialRef === ref) as DirectRoute);
      const next = this.copy(); this.replaceRoutes(next.entries.find((e: EnvironmentEntry) => e.localId === localId) as EnvironmentEntry, ordered);
      await this.commit(next);
    });
  }
  async removeRoute(localId: string, reference: string): Promise<void> {
    let reconnect = false;
    await this.write(async () => {
      const entry = this.entry(localId); const routes = environmentRoutes(entry);
      const removed = routes.find((route: DirectRoute) => route.credentialRef === reference);
      if (!removed) return;
      if (routes.length === 1) { await this.beginRemoval(localId); return; }
      const client = this.clients.get(localId);
      // An unresolved marker is environment-scoped recovery state, not an in-flight request.
      // Removing one direct route may reconnect elsewhere; whole-environment removal still blocks it.
      if (client?.connectionPending || client?.submitting) throw new Error('请先核对正在连接或提交的请求');
      const next = this.copy(); const edited = next.entries.find((e: EnvironmentEntry) => e.localId === localId) as EnvironmentEntry;
      this.replaceRoutes(edited, routes.filter((route: DirectRoute) => route.credentialRef !== reference));
      edited.retiredCredentialRefs = (edited.retiredCredentialRefs || []).concat([reference]); edited.prRouting = undefined;
      reconnect = !!client?.ready && client.connectedBase === removed.base && entry.enabled;
      if (reconnect) client?.disconnect('正在切换已保存的连接路径');
      await this.commit(next); await this.finishRetiredCredentials(localId);
    });
    if (reconnect) await this.reconnect(localId);
  }
  private async finishRetiredCredentials(localId: string): Promise<void> {
    const entry = this.entry(localId);
    for (const reference of entry.retiredCredentialRefs || []) await this.assets.session(reference).clear();
    const next = this.copy(); const edited = next.entries.find((e: EnvironmentEntry) => e.localId === localId) as EnvironmentEntry;
    edited.retiredCredentialRefs = undefined; await this.commit(next);
  }
  async edit(localId: string, label: string, address: string): Promise<void> {
    let reconnect = false;
    await this.write(async () => {
      const entry = this.entry(localId);
      if (entry.kind !== 'bearer') throw new Error('T3 Connect 环境地址由中继管理，不能手动编辑');
      const target = pairingTarget(address);
      if (target.code || !label.trim() || label.trim().length > 256) throw new Error('名称或 URL 无效；URL 不应包含配对码');
      const client = this.clients.get(localId);
      if (!client || client.connectionPending || client.mutationPending) throw new Error('请先核对正在连接、提交或结果未知的请求');
      if (target.base !== entry.base) {
        client.disconnect('正在验证环境地址');
        for (const ref of entry.recovery) {
          const value = await this.assets.recovery(ref.alias).load();
          if (!value || recoveryState(value, entry.recoveryBase || entry.base, entry.environmentId).pendingId) throw new Error('请先核对所有未知提交');
        }
        await client.verifyIdentity(target.base);
      }
      const next = this.copy();
      const edited = next.entries.find((e: EnvironmentEntry) => e.localId === localId) as EnvironmentEntry;
      edited.label = label.trim();
      if (target.base !== entry.base) {
        if (environmentRoutes(entry).some((route: DirectRoute) => route.base === target.base)) throw new Error('此路径已存在，请调整路径排序');
        edited.pendingBase = target.base;
        edited.prRouting = undefined; // A changed endpoint revokes client-side PR trust before credentials move.
      }
      await this.commit(next);
      if (edited.pendingBase) { await this.finishEdit(localId); reconnect = edited.enabled; }
    });
    if (reconnect) await this.reconnect(localId);
  }
  private async finishEdit(localId: string): Promise<void> {
    const entry = this.directory.entries.find((e: EnvironmentEntry) => e.localId === localId);
    if (!entry?.pendingBase) throw new Error('没有待完成的地址更新');
    const session = await this.assets.session(entry.credentialRef).load();
    if (!session || session.environmentId !== entry.environmentId || (session.base !== entry.base && session.base !== entry.pendingBase)) {
      throw new Error('地址更新凭据身份不一致');
    }
    const checked = savedSession(session); checked.base = entry.pendingBase;
    await this.assets.session(entry.credentialRef).save(checked);
    const anchor = entry.recoveryBase || entry.base;
    for (const ref of entry.recovery) {
      const value = await this.assets.recovery(ref.alias).load();
      if (!value || (value.base !== anchor && value.base !== entry.pendingBase)) throw new Error('地址更新恢复记录不一致');
      const state = recoveryState(value, value.base, entry.environmentId);
      if (state.threadId !== ref.threadId) throw new Error('地址更新恢复会话不一致');
      if (state.base !== anchor) { state.base = anchor; await this.assets.recovery(ref.alias).save(state); }
    }
    const next = this.copy();
    const edited = next.entries.find((e: EnvironmentEntry) => e.localId === localId) as EnvironmentEntry;
    edited.base = entry.pendingBase; edited.pendingBase = undefined;
    edited.recoveryBase = anchor;
    await this.commit(next);
  }
  async setPullRequestRouting(localId: string, permission: string): Promise<void> {
    await this.write(async () => {
      if (!this.initialized || !['off', 'read', 'read-write'].includes(permission)) throw new Error('PR 路由设置无效或环境目录未就绪');
      const checked = this.entry(localId);
      if (checked.kind !== 'bearer') throw new Error('T3 Connect 环境暂不支持 PR 路由');
      const next = this.copy();
      const entry = next.entries.find((e: EnvironmentEntry) => e.localId === localId) as EnvironmentEntry;
      entry.prRouting = permission === 'off' ? undefined : permission;
      await this.commit(next);
    });
  }
  canRoutePullRequest(originId: string, targetId: string, write: boolean): boolean {
    return this.initialized && pullRequestRoutingAllowed(this.directory, originId, targetId, write);
  }
  async remove(localId: string): Promise<void> {
    await this.write(() => this.beginRemoval(localId));
  }
  private async beginRemoval(localId: string): Promise<void> {
    const entry = this.entry(localId);
    const client = this.clients.get(localId);
    if (client?.connectionPending || client?.mutationPending) throw new Error('请先核对正在连接、提交或结果未知的请求');
    client?.disconnect('正在核对本机环境移除条件');
    // Read every thread, including a non-selected unknown submission, before any destructive step.
    for (const ref of entry.recovery) {
      const state = await this.assets.recovery(ref.alias).load();
      if (!state || recoveryState(state, entry.recoveryBase || entry.base, entry.environmentId).pendingId) {
        throw new Error('请先同步原会话并核对未知提交，未移除环境');
      }
    }
    this.clients.get(localId)?.disconnect('正在移除本机环境');
    const next = this.copy();
    const target = next.entries.find((e: EnvironmentEntry) => e.localId === localId) as EnvironmentEntry;
    target.enabled = false; target.deleting = true;
    await this.commit(next); await this.finishRemoval(localId);
  }
  private async finishRemoval(localId: string): Promise<void> {
    const entry = this.directory.entries.find((e: EnvironmentEntry) => e.localId === localId);
    if (!entry?.deleting) throw new Error('环境未进入移除状态');
    for (const ref of entry.recovery) await this.assets.recovery(ref.alias).clear();
    for (const route of environmentRoutes(entry)) await this.assets.session(route.credentialRef).clear();
    for (const ref of entry.retiredCredentialRefs || []) await this.assets.session(ref).clear();
    if (localId === 'legacy-v1') {
      await this.legacySession.clear();
      await this.legacyRecovery.clear();
    }
    this.clients.delete(localId);
    const next = this.copy(); next.entries = next.entries.filter((e: EnvironmentEntry) => e.localId !== localId);
    if (next.selectedLocalId === localId) next.selectedLocalId = next.entries.find((e: EnvironmentEntry) => !e.deleting)?.localId || '';
    await this.commit(next);
  }
  suspend(): void { this.clients.forEach((client: T3Client) => client.suspend()); }
  async resume(): Promise<void> {
    await Promise.all(this.directory.entries.filter((entry: EnvironmentEntry) => entry.enabled && !entry.deleting)
      .map(async (entry: EnvironmentEntry) => {
        const client = this.clients.get(entry.localId);
        try { await client?.resume(); } catch (error) { if (client) { client.status = (error as Error).message || '该环境连接恢复失败'; this.notify(); } }
      }));
  }
}

export let environments: EnvironmentRegistry | undefined = undefined;
export function prepareEnvironments(filesDir: string): void {
  environments?.suspend();
  environments = new EnvironmentRegistry(filesDir);
}
