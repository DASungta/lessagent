import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { url, util } from '@kit.ArkTS';
import {
  CloudAccountSession, CloudConfig, cloudConfig, cloudConfigured, cloudSignInReady,
  RelayEndpoint, RelayEnvironmentRecord, RelayStatus, relayOfflineMessage
} from '../protocol/Cloud';
import { EnvironmentEntry } from '../protocol/Environment';
import { environments } from './EnvironmentRegistry';
import { CloudEnvironmentTokenStore, RelayTokenStore } from '../storage/CloudStores';
import { CloudAuth } from './CloudAuth';
import { CloudRelay } from './CloudRelay';
import { CloudEnvironmentTransport } from './CloudConnection';
import { DpopSigner } from './Dpop';

export interface CloudEnvironmentView {
  environmentId: string;
  label: string;
  httpBaseUrl: string;
  linkedAt: number;
  availability: string;
  statusText: string;
  error: string;
  traceId: string;
}

interface EndpointOrigin { localHttpHost: string; localHttpPort: number; }
interface LinkProofPayload {
  challenge: string;
  relayIssuer: string;
  endpoint: RelayEndpoint;
  origin: EndpointOrigin;
}
interface RelayConfigPayload {
  relayUrl: string;
  relayIssuer: string;
  cloudUserId: string;
  environmentCredential: string;
  cloudMintPublicKey: string;
  endpointRuntime: Object | null;
}

function blankConfig(): CloudConfig {
  return { clerk: { publishableKey: '', jwtTemplate: '', oauthClientId: '', redirectUri: '' }, relay: { url: '' } };
}

function configFrom(context: common.UIAbilityContext): CloudConfig {
  const bytes = context.resourceManager.getRawFileContentSync('t3-connect.json');
  return cloudConfig(JSON.parse(new util.TextDecoder().decodeToString(bytes)) as Object);
}

function wsBase(value: string): string {
  const parsed = new url.URL(value);
  parsed.protocol = parsed.protocol === 'https:' ? 'wss:' : 'ws:';
  parsed.pathname = '/';
  parsed.search = '';
  parsed.hash = '';
  return parsed.toString();
}

function origin(value: string): EndpointOrigin {
  const parsed = new url.URL(value);
  return { localHttpHost: '127.0.0.1', localHttpPort: Number(parsed.port || (parsed.protocol === 'https:' ? 443 : 80)) };
}

function deviceIdentity(filesDir: string): string {
  const path = filesDir + '/t3-cloud-device-id';
  try {
    const stored = fileIo.readTextSync(path).trim();
    if (/^[0-9a-f-]{36}$/i.test(stored)) return stored;
  } catch (_) {}
  const value = util.generateRandomUUID();
  try {
    const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    try { fileIo.writeSync(file.fd, value); fileIo.fsyncSync(file.fd); } finally { fileIo.closeSync(file); }
  } catch (_) {}
  return value;
}

function accountIds(): string[] {
  const result: string[] = [];
  for (const entry of environments?.directory.entries || []) {
    if (entry.kind === 'cloud' && entry.cloudAccountId && !entry.deleting && !result.includes(entry.cloudAccountId)) {
      result.push(entry.cloudAccountId);
    }
  }
  return result;
}

function errorText(error: Object): string {
  return error instanceof Error ? error.message : 'T3 Connect 操作失败';
}

export class CloudManager {
  config: CloudConfig;
  configError: string = '';
  signer: DpopSigner = new DpopSigner();
  auth: CloudAuth;
  environmentTokens: CloudEnvironmentTokenStore = new CloudEnvironmentTokenStore();
  environments: CloudEnvironmentView[] = [];
  refreshing: boolean = false;
  busy: boolean = false;
  status: string = '未初始化';
  error: string = '';
  onUpdate: () => void = () => {};
  private sessionValue: CloudAccountSession | undefined = undefined;
  private relayValue: CloudRelay | undefined = undefined;
  private deviceIdValue: string = '';
  private filesDir: string;
  private generation: number = 0;
  private refreshGeneration: number = 0;

  constructor(config: CloudConfig, configError: string, filesDir: string) {
    this.config = config; this.configError = configError; this.filesDir = filesDir;
    this.auth = new CloudAuth(config, this.signer);
  }

  get configured(): boolean { return cloudConfigured(this.config); }
  get signInReady(): boolean { return cloudSignInReady(this.config); }
  get signedIn(): boolean { return !!this.sessionValue; }
  get session(): CloudAccountSession | undefined { return this.sessionValue; }
  get deviceId(): string { return this.deviceIdValue; }

  private notify(): void {
    try { this.onUpdate(); } catch (_) {}
    AppStorage.setOrCreate('t3CloudRevision', (AppStorage.get<number>('t3CloudRevision') || 0) + 1);
  }

  async initialize(): Promise<void> {
    this.deviceIdValue = deviceIdentity(this.filesDir);
    try { await environments?.initialize(); }
    catch (error) {
      this.status = '环境目录尚未就绪';
      this.error = errorText(error as Object);
      this.notify();
      return;
    }
    if (!this.configured) {
      await environments?.setCloudAccount('', undefined);
      this.status = this.configError || 'T3 Connect 未配置';
      this.notify();
      return;
    }
    try {
      const restored = await this.auth.restore();
      if (restored) {
        await this.cleanupForeignAccounts(restored.accountId);
        await this.activate(restored, false);
      }
      else {
        await environments?.setCloudAccount('', undefined);
        this.status = '未登录';
      }
    } catch (error) {
      this.error = errorText(error as Object);
      this.status = '账号恢复失败';
      await environments?.setCloudAccount('', undefined);
    }
    this.notify();
  }

  private relay(session: CloudAccountSession, generation: number): CloudRelay {
    return new CloudRelay(this.config, session.accountId, session.accessToken,
      () => this.generation === generation && this.sessionValue?.accountId === session.accountId && this.sessionValue.accessToken === session.accessToken,
      this.signer);
  }

  private async activate(session: CloudAccountSession, persist: boolean): Promise<void> {
    if (persist) await this.auth.persist(session);
    this.generation++;
    const generation = this.generation;
    this.sessionValue = session;
    this.relayValue = this.relay(session, generation);
    const relay = this.relayValue;
    await environments?.setCloudAccount(session.accountId, (entry: EnvironmentEntry) => new CloudEnvironmentTransport(
      entry.environmentId, entry.label, session.accountId, this.deviceIdValue, relay, this.signer,
      this.environmentTokens,
      () => this.generation === generation && this.sessionValue?.accountId === session.accountId));
    this.status = 'T3 Connect 已登录';
    this.error = '';
    this.notify();
    await this.refresh();
    if (generation !== this.generation) return;
    const entries = (environments?.directory.entries || []).filter((entry: EnvironmentEntry) => entry.kind === 'cloud' &&
      entry.cloudAccountId === session.accountId && entry.enabled && !entry.deleting);
    await Promise.all(entries.map(async (entry: EnvironmentEntry) => {
      if (generation !== this.generation) return;
      try { await environments?.reconnect(entry.localId); }
      catch (error) { if (generation === this.generation) { this.error = errorText(error as Object); this.notify(); } }
    }));
  }

  async beginSignIn(context: common.UIAbilityContext): Promise<void> {
    if (this.busy) return;
    this.busy = true; this.error = '';
    try { await this.auth.begin(context); this.status = this.auth.status; }
    catch (error) { this.error = errorText(error as Object); this.status = this.error; throw error as Error; }
    finally { this.busy = false; this.notify(); }
  }

  async completeCallback(uri: string): Promise<void> {
    if (this.busy) return;
    this.busy = true; this.error = '';
    try {
      const next = await this.auth.complete(uri);
      const current = this.sessionValue;
      if (current && current.accountId !== next.accountId) this.deactivate();
      await this.cleanupForeignAccounts(next.accountId);
      await this.auth.persist(next);
      await this.activate(next, false);
      this.status = 'T3 Connect 已登录';
    } catch (error) {
      this.error = errorText(error as Object);
      this.status = this.error;
      throw error as Error;
    } finally { this.busy = false; this.notify(); }
  }

  private deactivate(): void {
    this.generation++;
    this.sessionValue = undefined;
    this.relayValue = undefined;
    this.environments = [];
    this.refreshing = false;
  }

  async signOut(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    const old = this.sessionValue;
    const accounts = accountIds();
    if (old && !accounts.includes(old.accountId)) accounts.push(old.accountId);
    this.deactivate();
    this.status = '正在退出 T3 Connect';
    this.notify();
    let failure = '';
    try { await environments?.setCloudAccount('', undefined); }
    catch (error) { failure = errorText(error as Object); }
    try { await this.auth.clear(); }
    catch (error) { failure = errorText(error as Object); }
    for (const account of accounts) {
      try { await this.cleanupAccount(account); }
      catch (error) { failure = errorText(error as Object); }
    }
    this.status = failure ? '已退出登录，但本机云环境清理未完成' : '已退出 T3 Connect';
    this.error = failure;
    this.busy = false;
    this.notify();
    if (failure) throw new Error(failure);
  }

  private async cleanupAccount(accountId: string): Promise<void> {
    const ids: string[] = [];
    for (const entry of environments?.directory.entries || []) {
      if (entry.kind === 'cloud' && entry.cloudAccountId === accountId) ids.push(entry.environmentId);
    }
    let failure: Error | undefined = undefined;
    try { await environments?.removeCloudAccount(accountId); }
    catch (error) { failure = error as Error; }
    try { await new RelayTokenStore().clear(); } catch (_) {}
    for (const environmentId of ids) {
      try { await this.environmentTokens.clear(environmentId); } catch (_) {}
    }
    if (failure) throw failure;
  }

  private async cleanupForeignAccounts(keepAccountId: string): Promise<void> {
    for (const account of accountIds()) {
      if (account !== keepAccountId) await this.cleanupAccount(account);
    }
  }

  async refresh(): Promise<void> {
    const session = this.sessionValue;
    const relay = this.relayValue;
    if (!session || !relay) throw new Error('请先登录 T3 Connect');
    const generation = ++this.refreshGeneration;
    this.refreshing = true; this.error = ''; this.notify();
    try {
      const listed = await relay.listEnvironments();
      if (generation !== this.refreshGeneration || this.sessionValue?.accountId !== session.accountId) return;
      this.environments = listed.map((record: RelayEnvironmentRecord): CloudEnvironmentView => ({
        environmentId: record.environmentId,
        label: record.label,
        httpBaseUrl: record.endpoint.httpBaseUrl,
        linkedAt: record.linkedAt,
        availability: 'checking',
        statusText: '正在检查中继状态',
        error: '',
        traceId: ''
      }));
      this.notify();
      await Promise.all(listed.map(async (environment: RelayEnvironmentRecord) => {
        if (generation !== this.refreshGeneration || this.sessionValue?.accountId !== session.accountId) return;
        const view = this.environments.find((row: CloudEnvironmentView) => row.environmentId === environment.environmentId);
        if (!view) return;
        try {
          const status: RelayStatus = await relay.status(environment);
          if (generation !== this.refreshGeneration) return;
          view.availability = status.status;
          view.statusText = status.status === 'online' ? '可用 · 中继在线' : relayOfflineMessage(status);
          view.traceId = status.traceId;
          await environments?.syncCloudEndpoint(environment.environmentId, session.accountId,
            environment.label, environment.endpoint.httpBaseUrl);
        } catch (error) {
          if (generation !== this.refreshGeneration) return;
          view.availability = 'error';
          view.error = errorText(error as Object);
          view.statusText = view.error;
        }
        this.notify();
      }));
    } catch (error) {
      if (generation === this.refreshGeneration) {
        this.error = errorText(error as Object);
        this.status = this.error;
      }
    } finally {
      if (generation === this.refreshGeneration) { this.refreshing = false; this.notify(); }
    }
  }

  registered(environmentId: string): string {
    return environments?.findEnvironment(environmentId)?.localId || '';
  }
  cloudRegistered(environmentId: string): string {
    return environments?.findEnvironmentOfKind(environmentId, 'cloud')?.localId || '';
  }

  async connectEnvironment(environmentId: string): Promise<string> {
    const session = this.sessionValue;
    const relay = this.relayValue;
    if (!session || !relay) throw new Error('请先登录 T3 Connect');
    const view = this.environments.find((row: CloudEnvironmentView) => row.environmentId === environmentId);
    if (!view) throw new Error('T3 Connect 环境列表已更新，请刷新后重试');
    if (view.availability === 'offline') throw new Error(view.statusText);
    const existing = environments?.findEnvironmentOfKind(environmentId, 'cloud');
    const localId = existing?.localId || await environments?.addCloud(environmentId, view.label,
      view.httpBaseUrl, session.accountId) as string;
    if (!localId) throw new Error('无法保存 T3 Connect 环境');
    try { await environments?.reconnect(localId); }
    catch (error) { this.error = errorText(error as Object); this.notify(); throw error as Error; }
    this.notify();
    return localId;
  }

  async linkLocalEnvironment(localId: string): Promise<void> {
    const registry = environments;
    const session = this.sessionValue;
    const relay = this.relayValue;
    if (!registry || !session || !relay) throw new Error('请先登录 T3 Connect');
    const entry = registry.entry(localId);
    if (entry.kind !== 'bearer') throw new Error('只有直连环境需要链接到 T3 Connect');
    const client = registry.clients.get(localId);
    if (!client?.ready) throw new Error('请先连接此环境再链接到 T3 Connect');
    const challenge = await relay.createLinkChallenge();
    const proofPayload: LinkProofPayload = {
      challenge: challenge.challenge,
      relayIssuer: this.config.relay.url,
      endpoint: {
        httpBaseUrl: entry.base,
        wsBaseUrl: wsBase(entry.base),
        providerKind: 'cloudflare_tunnel'
      },
      origin: origin(entry.base)
    };
    const proof = await client.linkProof(proofPayload);
    const link = await relay.linkEnvironment(entry.environmentId, proof, this.deviceIdValue);
    if (link.cloudUserId !== session.accountId) throw new Error('中继返回了其他账号的环境链接');
    const configure: RelayConfigPayload = {
      relayUrl: this.config.relay.url,
      relayIssuer: link.relayIssuer,
      cloudUserId: link.cloudUserId,
      environmentCredential: link.environmentCredential,
      cloudMintPublicKey: link.cloudMintPublicKey,
      endpointRuntime: link.endpointRuntime === undefined ? null : link.endpointRuntime
    };
    try {
      await client.configureRelay(configure);
    } catch (error) {
      try { await relay.unlinkEnvironment(entry.environmentId); } catch (_) {}
      throw error as Error;
    }
    try {
      let cloudLocal = environments?.findEnvironmentOfKind(entry.environmentId, 'cloud')?.localId;
      if (!cloudLocal) cloudLocal = await environments?.addCloud(entry.environmentId, entry.label,
        link.endpoint.httpBaseUrl, session.accountId) as string;
      if (cloudLocal) await environments?.reconnect(cloudLocal);
    } catch (error) {
      this.error = errorText(error as Object);
    }
    await this.refresh();
    this.status = '环境已链接到 T3 Connect';
    this.notify();
  }

  async unlinkEnvironment(environmentId: string): Promise<void> {
    const relay = this.relayValue;
    if (!relay) throw new Error('请先登录 T3 Connect');
    await relay.unlinkEnvironment(environmentId);
    await this.refresh();
    this.notify();
  }

  async onForeground(): Promise<void> {
    if (!this.sessionValue || this.refreshing) return;
    try { await this.refresh(); } catch (_) {}
  }
}

export let cloud: CloudManager | undefined = undefined;

export async function prepareCloud(context: common.UIAbilityContext, filesDir: string): Promise<void> {
  let config: CloudConfig = blankConfig();
  let configError = '';
  try { config = configFrom(context); }
  catch (error) {
    configError = errorText(error as Object);
  }
  cloud = new CloudManager(config, configError, filesDir);
  await cloud.initialize();
}
