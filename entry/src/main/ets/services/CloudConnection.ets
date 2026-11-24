import { http } from '@kit.NetworkKit';
import { url } from '@kit.ArkTS';
import { record, text } from '../protocol/Wire';
import {
  CloudEnvironmentToken, cloudEnvironmentToken, ConnectApprovalPendingError,
  parseEnvironmentTokenError, RelayConnect, RelayEndpoint
} from '../protocol/Cloud';
import { CloudHttpFailure, CloudHttpResult, cloudHttp } from './CloudHttp';
import { CloudRelay } from './CloudRelay';
import { CloudEnvironmentTokenStore } from '../storage/CloudStores';
import { DpopSigner } from './Dpop';

function refreshSkew(): number { return 5000; }

export class CloudEnvironmentTransport {
  environmentId: string;
  label: string;
  private accountId: string;
  private deviceId: string;
  private relay: CloudRelay;
  private signer: DpopSigner;
  private store: CloudEnvironmentTokenStore;
  private active: () => boolean;
  private bootstrap: RelayConnect | undefined = undefined;
  private token: CloudEnvironmentToken | undefined = undefined;

  constructor(environmentId: string, label: string, accountId: string, deviceId: string,
    relay: CloudRelay, signer: DpopSigner, store: CloudEnvironmentTokenStore, active: () => boolean) {
    this.environmentId = environmentId; this.label = label; this.accountId = accountId;
    this.deviceId = deviceId; this.relay = relay; this.signer = signer; this.store = store;
    this.active = active;
  }

  private assertActive(): void {
    if (!this.active()) throw new Error('T3 Connect 账号已切换，已中止旧账号连接');
  }

  tokenExpiresAt(): number {
    return this.token ? this.token.expiresAt : 0;
  }

  private async cachedToken(): Promise<CloudEnvironmentToken | undefined> {
    this.assertActive();
    const thumbprint = await this.signer.thumbprint();
    const cached = this.token || await this.store.load(this.environmentId);
    if (cached && cached.accountId === this.accountId && cached.environmentId === this.environmentId &&
      cached.thumbprint === thumbprint && cached.expiresAt > Date.now() + refreshSkew()) {
      this.token = cached;
      return cached;
    }
    return undefined;
  }

  async cachedEndpoint(): Promise<RelayEndpoint | undefined> {
    const cached = await this.cachedToken();
    return cached ? cached.endpoint : undefined;
  }

  async endpoint(): Promise<RelayEndpoint> {
    this.assertActive();
    this.bootstrap = await this.relay.connect(this.environmentId, this.deviceId);
    this.assertActive();
    return this.bootstrap.endpoint;
  }

  private async ensureBootstrap(): Promise<RelayConnect> {
    if (this.bootstrap && this.bootstrap.expiresAt > Date.now() + refreshSkew()) return this.bootstrap;
    this.assertActive();
    this.bootstrap = await this.relay.connect(this.environmentId, this.deviceId);
    this.assertActive();
    return this.bootstrap;
  }

  private async exchange(bootstrap: RelayConnect, thumbprint: string): Promise<CloudEnvironmentToken> {
    const target = bootstrap.endpoint.httpBaseUrl + '/oauth/token';
    const proof = await this.signer.prove('POST', target);
    const body = 'grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Atoken-exchange' +
      '&subject_token=' + encodeURIComponent(bootstrap.credential) +
      '&subject_token_type=urn%3At3%3Aparams%3Aoauth%3Atoken-type%3Aenvironment-bootstrap' +
      '&requested_token_type=urn%3Aietf%3Aparams%3Aoauth%3Atoken-type%3Aaccess_token' +
      '&client_label=T3%20Code%20Harmony&client_device_type=mobile&client_os=HarmonyOS';
    let result: CloudHttpResult;
    try {
      const headers: Record<string, string> = { 'dpop': proof };
      result = await cloudHttp(target, http.RequestMethod.POST, headers, body,
        'application/x-www-form-urlencoded');
    } catch (error) {
      if (error instanceof CloudHttpFailure) {
        const mapped = parseEnvironmentTokenError(error.status, error.value, this.label, thumbprint);
        if (mapped instanceof ConnectApprovalPendingError) {
          this.bootstrap = undefined;
        }
        throw mapped;
      }
      throw error as Error;
    }
    const row = record(result.value);
    const accessToken = text(row.access_token);
    const expiresIn = row.expires_in as number;
    if (text(row.token_type) !== 'DPoP' || !accessToken || !Number.isSafeInteger(expiresIn) || expiresIn <= 0) {
      throw new Error('环境返回了无效的 DPoP 令牌');
    }
    const token: CloudEnvironmentToken = {
      environmentId: this.environmentId,
      accountId: this.accountId,
      label: this.label,
      endpoint: bootstrap.endpoint,
      accessToken,
      expiresAt: Date.now() + expiresIn * 1000,
      thumbprint
    };
    await this.store.save(token);
    return cloudEnvironmentToken(token as Object);
  }

  async accessToken(force: boolean = false): Promise<CloudEnvironmentToken> {
    this.assertActive();
    if (force) this.bootstrap = undefined;
    const thumbprint = await this.signer.thumbprint();
    if (!force) {
      const cached = this.token || await this.store.load(this.environmentId);
      if (cached && cached.accountId === this.accountId && cached.environmentId === this.environmentId &&
        cached.thumbprint === thumbprint && cached.expiresAt > Date.now() + refreshSkew()) {
        this.token = cached;
        return cached;
      }
    }
    const bootstrap = await this.ensureBootstrap();
    const token = await this.exchange(bootstrap, thumbprint);
    this.token = token;
    return token;
  }

  async requestJson(path: string, method: http.RequestMethod, body: string = '',
    json: boolean = false, extraHeaders?: Record<string, string>, retry: boolean = true): Promise<Object> {
    this.assertActive();
    const bootstrap = await this.ensureBootstrap();
    let token = await this.accessToken();
    if (token.endpoint.httpBaseUrl !== bootstrap.endpoint.httpBaseUrl ||
      token.endpoint.wsBaseUrl !== bootstrap.endpoint.wsBaseUrl) token = await this.accessToken(true);
    const target = bootstrap.endpoint.httpBaseUrl + path;
    const proof = await this.signer.prove(method as string, target, token.accessToken);
    this.assertActive();
    const headers: Record<string, string> = {
      'Authorization': 'DPoP ' + token.accessToken,
      'dpop': proof
    };
    if (extraHeaders) {
      for (const key of Object.keys(extraHeaders)) headers[key] = extraHeaders[key];
    }
    try {
      const result = await cloudHttp(target, method, headers, body,
        body ? (json ? 'application/json' : 'application/x-www-form-urlencoded') : '');
      this.assertActive();
      return result.value;
    } catch (error) {
      if (error instanceof CloudHttpFailure) {
        if (retry && error.status === 401) {
          await this.accessToken(true);
          return this.requestJson(path, method, body, json, extraHeaders, false);
        }
        throw new Error(error.status === 403 ? 'T3 Connect 环境不允许此操作' :
          error.status === 404 ? 'T3 Connect 环境不支持此接口' : 'T3 Connect 环境请求失败');
      }
      throw error as Error;
    }
  }

  private async ticket(usePath: string, barePath: string, token: CloudEnvironmentToken,
    endpoint: RelayEndpoint): Promise<string> {
    const target = endpoint.httpBaseUrl + usePath;
    const proof = await this.signer.prove('POST', target, token.accessToken);
    try {
      const headers: Record<string, string> = {
        'Authorization': 'DPoP ' + token.accessToken,
        'dpop': proof
      };
      const result = await cloudHttp(target, http.RequestMethod.POST, headers);
      return text(record(result.value).ticket);
    } catch (error) {
      if (!(error instanceof CloudHttpFailure) || error.status !== 404) {
        throw error instanceof CloudHttpFailure ?
          new Error('T3 Connect 环境未签发 WebSocket 票据') : error as Error;
      }
      const fallback = endpoint.httpBaseUrl + barePath;
      const fallbackProof = await this.signer.prove('POST', fallback, token.accessToken);
      const headers: Record<string, string> = {
        'Authorization': 'DPoP ' + token.accessToken,
        'dpop': fallbackProof
      };
      const result = await cloudHttp(fallback, http.RequestMethod.POST, headers);
      return text(record(result.value).ticket);
    }
  }

  async socketUrl(): Promise<string> {
    this.assertActive();
    let usedCachedWithoutBootstrap = false;
    let endpoint: RelayEndpoint;
    let token: CloudEnvironmentToken;
    if (this.bootstrap && this.bootstrap.expiresAt > Date.now() + refreshSkew()) {
      endpoint = this.bootstrap.endpoint;
      token = await this.accessToken();
      if (token.endpoint.httpBaseUrl !== endpoint.httpBaseUrl ||
        token.endpoint.wsBaseUrl !== endpoint.wsBaseUrl) token = await this.accessToken(true);
    } else {
      const cached = await this.cachedToken();
      if (cached) {
        token = cached;
        endpoint = cached.endpoint;
        usedCachedWithoutBootstrap = true;
      } else {
        const bootstrap = await this.ensureBootstrap();
        endpoint = bootstrap.endpoint;
        token = await this.accessToken();
        if (token.endpoint.httpBaseUrl !== endpoint.httpBaseUrl ||
          token.endpoint.wsBaseUrl !== endpoint.wsBaseUrl) token = await this.accessToken(true);
      }
    }
    let ticket: string;
    try {
      ticket = await this.ticket('/api/auth/websocket-ticket/rpc',
        '/api/auth/websocket-ticket', token, endpoint);
    } catch (error) {
      if (!usedCachedWithoutBootstrap) throw error as Error;
      this.token = undefined;
      this.bootstrap = undefined;
      token = await this.accessToken(true);
      endpoint = token.endpoint;
      ticket = await this.ticket('/api/auth/websocket-ticket/rpc',
        '/api/auth/websocket-ticket', token, endpoint);
    }
    if (!ticket || ticket.length > 8192) throw new Error('T3 Connect WebSocket 票据无效');
    const socket = new url.URL(endpoint.wsBaseUrl);
    if (socket.pathname === '' || socket.pathname === '/') socket.pathname = '/ws';
    const proof = await this.signer.prove('GET',
      (socket.protocol === 'wss:' ? 'https:' : 'http:') + '//' + socket.host + socket.pathname, ticket);
    return socket.toString() + '?orchestrationProtocol=2&wsTicket=' + encodeURIComponent(ticket) +
      '&dpop=' + encodeURIComponent(proof) + '&clientSurface=mobile&clientOs=HarmonyOS' +
      '&clientDeviceType=phone&connectionMethod=relay&frameParts=1';
  }

  async renew(): Promise<number> {
    this.bootstrap = undefined;
    const token = await this.accessToken(true);
    return token.expiresAt;
  }

  async reset(): Promise<void> {
    this.bootstrap = undefined; this.token = undefined;
    await this.store.clear(this.environmentId);
  }
}
