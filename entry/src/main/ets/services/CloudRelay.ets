import { http } from '@kit.NetworkKit';
import { record, text } from '../protocol/Wire';
import {
  CloudConfig, RelayChallenge, relayChallenge, RelayConnect, relayConnect,
  RelayEnvironmentRecord, relayEnvironments, RelayLink, relayLink, relayToken, RelayTokenCache,
  relayTokenMatches, relayStatus, RelayStatus, relayErrorMessage, RELAY_CONNECT_SCOPE,
  RELAY_MOBILE_SCOPE, RELAY_STATUS_SCOPE
} from '../protocol/Cloud';
import { CloudHttpFailure, CloudHttpResult, cloudHttp } from './CloudHttp';
import { DpopSigner } from './Dpop';
import { RelayTokenStore } from '../storage/CloudStores';

export class RelayFailure extends Error {
  status: number;
  code: string;
  reason: string;
  constructor(status: number, value: Object) {
    super(relayErrorMessage(status, value));
    this.status = status;
    let code = '';
    let reason = '';
    try {
      const row = record(value);
      code = row.code === undefined ? '' : text(row.code);
      reason = row.reason === undefined ? '' : text(row.reason);
    } catch (_) {}
    this.code = code;
    this.reason = reason;
  }
}

function failure(error: CloudHttpFailure): RelayFailure {
  return new RelayFailure(error.status, error.value);
}

function invalidBearer(error: RelayFailure): boolean {
  return error.status === 401 && error.code === 'auth_invalid' && error.reason === 'invalid_bearer';
}

export type ClerkTokenReader = (forceRefresh?: boolean) => Promise<string>;

export class CloudRelay {
  readonly relayUrl: string;
  private config: CloudConfig;
  private accountId: string;
  private readClerkToken: ClerkTokenReader;
  private active: () => boolean;
  private signer: DpopSigner;
  private tokens: RelayTokenStore;

  constructor(config: CloudConfig, accountId: string, readClerkToken: ClerkTokenReader,
    active: () => boolean, signer: DpopSigner, tokens: RelayTokenStore = new RelayTokenStore()) {
    this.config = config; this.relayUrl = config.relay.url;
    this.accountId = accountId; this.readClerkToken = readClerkToken; this.active = active;
    this.signer = signer; this.tokens = tokens;
  }

  private assertActive(): void {
    if (!this.active()) throw new Error('T3 Connect 账号已切换，已中止旧账号请求');
  }

  private target(path: string): string {
    return this.relayUrl + path;
  }

  private async exchange(scopes: string[], forceClerkRefresh: boolean = false, retryClerk: boolean = true): Promise<RelayTokenCache> {
    this.assertActive();
    const subjectToken = await this.readClerkToken(forceClerkRefresh);
    this.assertActive();
    const target = this.target('/v1/client/dpop-token');
    const proof = await this.signer.prove('POST', target);
    let result: CloudHttpResult;
    try {
      const headers: Record<string, string> = {};
      headers['dpop'] = proof;
      const body = 'grant_type=' + encodeURIComponent('urn:ietf:params:oauth:grant-type:token-exchange') +
        '&subject_token=' + encodeURIComponent(subjectToken) +
        '&subject_token_type=' + encodeURIComponent('urn:ietf:params:oauth:token-type:jwt') +
        '&requested_token_type=' + encodeURIComponent('urn:ietf:params:oauth:token-type:access_token') +
        '&resource=' + encodeURIComponent(this.relayUrl) +
        '&scope=' + encodeURIComponent(scopes.join(' ')) +
        '&client_id=t3-mobile';
      result = await cloudHttp(target, http.RequestMethod.POST, headers, body,
        'application/x-www-form-urlencoded');
    } catch (error) {
      if (error instanceof CloudHttpFailure) {
        const parsed = failure(error);
        if (retryClerk && invalidBearer(parsed)) {
          return this.exchange(scopes, true, false);
        }
        throw parsed;
      }
      throw error as Error;
    }
    this.assertActive();
    const token = relayToken(result.value, scopes);
    const cache: RelayTokenCache = {
      accountId: this.accountId,
      clientId: 't3-mobile',
      relayUrl: this.relayUrl,
      thumbprint: await this.signer.thumbprint(),
      scopes,
      accessToken: token.accessToken,
      expiresAtMillis: Date.now() + token.expiresIn * 1000
    };
    try { await this.tokens.save(cache); } catch (_) {}
    return cache;
  }

  private async access(scopes: string[], rejected?: string): Promise<RelayTokenCache> {
    this.assertActive();
    const thumbprint = await this.signer.thumbprint();
    const cached = await this.tokens.load();
    if (cached && cached.accessToken !== rejected &&
      relayTokenMatches(cached, this.accountId, 't3-mobile', this.relayUrl, thumbprint, scopes, Date.now())) {
      return cached;
    }
    if (rejected) { try { await this.tokens.clear(); } catch (_) {} }
    return this.exchange(scopes, !!rejected, true);
  }

  private async request(method: http.RequestMethod, path: string, scopes: string[],
    body: string = '', contentType: string = '', retry: boolean = true): Promise<Object> {
    this.assertActive();
    const token = await this.access(scopes);
    const target = this.target(path);
    const proof = await this.signer.prove(method as string, target, token.accessToken);
    this.assertActive();
    try {
      const headers: Record<string, string> = {
        'Authorization': 'DPoP ' + token.accessToken,
        'dpop': proof
      };
      const result = await cloudHttp(target, method, headers, body, contentType);
      this.assertActive();
      return result.value;
    } catch (error) {
      if (error instanceof CloudHttpFailure) {
        const parsed = failure(error);
        if (retry && invalidBearer(parsed)) {
          await this.access(scopes, token.accessToken);
          return this.request(method, path, scopes, body, contentType, false);
        }
        throw parsed;
      }
      throw error as Error;
    }
  }

  private async bearer(method: http.RequestMethod, path: string,
    body: string = '', contentType: string = '', forceClerkRefresh: boolean = false, retry: boolean = true): Promise<Object> {
    this.assertActive();
    const clerkToken = await this.readClerkToken(forceClerkRefresh);
    this.assertActive();
    try {
      const headers: Record<string, string> = { 'Authorization': 'Bearer ' + clerkToken };
      const result = await cloudHttp(this.target(path), method, headers, body, contentType);
      this.assertActive();
      return result.value;
    } catch (error) {
      if (error instanceof CloudHttpFailure) {
        const parsed = failure(error);
        if (retry && invalidBearer(parsed)) {
          return this.bearer(method, path, body, contentType, true, false);
        }
        throw parsed;
      }
      throw error as Error;
    }
  }

  async listEnvironments(): Promise<RelayEnvironmentRecord[]> {
    return relayEnvironments(await this.bearer(http.RequestMethod.GET, '/v1/environments'));
  }

  async createLinkChallenge(): Promise<RelayChallenge> {
    return relayChallenge(await this.bearer(http.RequestMethod.POST,
      '/v1/client/environment-link-challenges', JSON.stringify({
        notificationsEnabled: false,
        liveActivitiesEnabled: false,
        managedTunnelsEnabled: true
      }), 'application/json'));
  }

  async linkEnvironment(environmentId: string, proof: string, deviceId: string): Promise<RelayLink> {
    const payload = JSON.stringify({
      deviceId,
      proof,
      notificationsEnabled: false,
      liveActivitiesEnabled: false,
      managedTunnelsEnabled: true
    });
    return relayLink(await this.bearer(http.RequestMethod.POST, '/v1/client/environment-links',
      payload, 'application/json'), environmentId);
  }

  async unlinkEnvironment(environmentId: string): Promise<void> {
    await this.bearer(http.RequestMethod.DELETE,
      '/v1/client/environment-links/' + encodeURIComponent(environmentId));
  }

  async status(environment: RelayEnvironmentRecord): Promise<RelayStatus> {
    return relayStatus(await this.request(http.RequestMethod.POST,
      '/v1/environments/' + encodeURIComponent(environment.environmentId) + '/status',
      [RELAY_STATUS_SCOPE, RELAY_CONNECT_SCOPE]), environment);
  }

  async connect(environmentId: string, deviceId: string): Promise<RelayConnect> {
    const thumbprint = await this.signer.thumbprint();
    return relayConnect(await this.request(http.RequestMethod.POST,
      '/v1/environments/' + encodeURIComponent(environmentId) + '/connect',
      [RELAY_CONNECT_SCOPE], JSON.stringify({
        deviceId,
        clientKeyThumbprint: thumbprint
      }), 'application/json'), environmentId);
  }

  async listDevices(): Promise<Object[]> {
    const value = record(await this.bearer(http.RequestMethod.GET, '/v2/client/devices'));
    return Array.isArray(value.devices) ? value.devices as Object[] : [];
  }

  async unregisterDevice(deviceId: string): Promise<void> {
    await this.request(http.RequestMethod.DELETE,
      '/v1/mobile/devices/' + encodeURIComponent(deviceId), [RELAY_MOBILE_SCOPE]);
  }

  async resetTokenCache(): Promise<void> {
    await this.tokens.clear();
  }
}
