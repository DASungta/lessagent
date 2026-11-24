import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { record } from '../protocol/Wire';
import {
  ClerkClientState, ClerkEnvironmentInfo, clerkErrorCode, clerkErrorMessage, clerkNativeEndpoint,
  ClerkSessionDescriptor, ClerkSignInAttempt, clerkSsoCallback, CloudAccountSession, cloudAccountSession,
  CloudConfig, cloudConfigured, CloudSessionExpiredError, cloudSignInReady, defaultClerkEnvironment,
  parseClerkClientEnvelope, parseClerkEnvironment, parseClerkSignInAttempt, parseClerkTemplateToken,
  PendingSsoSignIn, selectActiveClerkSession
} from '../protocol/Cloud';
import { CloudSessionStore, PendingSsoStore } from '../storage/CloudStores';
import { CloudHttpFailure, CloudHttpResult, cloudHttp } from './CloudHttp';

const RELAY_TOKEN_SKEW_MS = 10000;

export interface CloudSignInResult {
  kind: string; // 'complete' | 'needs_first_factor' | 'needs_second_factor'
  session: CloudAccountSession | undefined;
  attempt: ClerkSignInAttempt | undefined;
}

interface FapiResponse {
  result: CloudHttpResult;
  clientToken: string;
}

interface CachedTemplateToken {
  accountId: string;
  sessionId: string;
  jwtTemplate: string;
  jwt: string;
  expiresAtMillis: number;
}

export class CloudAuth {
  config: CloudConfig;
  session: CloudAccountSession | undefined = undefined;
  environmentInfo: ClerkEnvironmentInfo = defaultClerkEnvironment();
  activeAttempt: ClerkSignInAttempt | undefined = undefined;
  pendingSsoStrategy: string = '';
  status: string = '未登录';
  private store: CloudSessionStore;
  private ssoStore: PendingSsoStore;
  private workingClientToken: string = '';
  private pendingSso: PendingSsoSignIn | undefined = undefined;
  private cachedTemplateToken: CachedTemplateToken | undefined = undefined;
  private mintInFlight: Promise<string> | undefined = undefined;
  private queue: Promise<void> = Promise.resolve();
  private generation: number = 0;

  constructor(config: CloudConfig, store: CloudSessionStore = new CloudSessionStore(),
    ssoStore: PendingSsoStore = new PendingSsoStore()) {
    this.config = config;
    this.store = store;
    this.ssoStore = ssoStore;
  }

  private runSerialized<T>(action: () => Promise<T>): Promise<T> {
    const next = this.queue.then(action, action);
    this.queue = next.then(() => undefined, () => undefined);
    return next;
  }

  private endpoint(path: string, extraQuery: string = ''): string {
    return clerkNativeEndpoint(this.config.clerk.publishableKey, path, extraQuery);
  }

  private rotatedToken(headers: Record<string, string>, fallback: string): string {
    const auth = (headers['authorization'] || '').trim();
    if (!auth) return fallback;
    return auth.startsWith('Bearer ') ? auth.slice(7).trim() : auth;
  }

  private async fapi(method: http.RequestMethod, path: string, clientToken: string,
    body: string = '', extraQuery: string = ''): Promise<FapiResponse> {
    const headers: Record<string, string> = {};
    if (clientToken) headers['Authorization'] = clientToken;
    const result = await cloudHttp(this.endpoint(path, extraQuery), method, headers, body,
      body ? 'application/x-www-form-urlencoded' : '');
    const nextToken = this.rotatedToken(result.headers, clientToken);
    const response: FapiResponse = { result, clientToken: nextToken };
    return response;
  }

  private isExpiredClerkFailure(error: CloudHttpFailure): boolean {
    if (error.status === 401) return true;
    const code = clerkErrorCode(error.value);
    return code === 'client_not_found' || code === 'session_not_found' ||
      code === 'authentication_invalid' || code === 'session_token_invalid';
  }

  private mapClerkError(error: Object): Error {
    if (error instanceof CloudHttpFailure) {
      if (this.isExpiredClerkFailure(error)) {
        return new CloudSessionExpiredError(clerkErrorMessage(error.status, error.value));
      }
      return new Error(clerkErrorMessage(error.status, error.value));
    }
    return error instanceof Error ? error : new Error('T3 Connect 登录失败，请重试');
  }

  private buildSession(descriptor: ClerkSessionDescriptor, clientToken: string): CloudAccountSession {
    return cloudAccountSession({
      version: 2,
      accountId: descriptor.userId,
      sessionId: descriptor.sessionId,
      clientToken,
      email: descriptor.email,
      displayName: descriptor.displayName,
      publishableKey: this.config.clerk.publishableKey,
      relayUrl: this.config.relay.url,
      jwtTemplate: this.config.clerk.jwtTemplate,
      redirectUri: this.config.clerk.redirectUri
    });
  }

  private async persistRotatedSessionToken(nextToken: string): Promise<void> {
    if (!this.session || !nextToken || nextToken === this.session.clientToken) return;
    const updated: CloudAccountSession = {
      version: 2,
      accountId: this.session.accountId,
      sessionId: this.session.sessionId,
      clientToken: nextToken,
      email: this.session.email,
      displayName: this.session.displayName,
      publishableKey: this.session.publishableKey,
      relayUrl: this.session.relayUrl,
      jwtTemplate: this.session.jwtTemplate,
      redirectUri: this.session.redirectUri
    };
    this.session = updated;
    try { await this.store.save(updated); } catch (_) {}
  }

  async fetchEnvironment(): Promise<ClerkEnvironmentInfo> {
    if (!cloudConfigured(this.config)) {
      this.environmentInfo = defaultClerkEnvironment();
      return this.environmentInfo;
    }
    try {
      const response = await cloudHttp(this.endpoint('/v1/environment'), http.RequestMethod.GET, {});
      this.environmentInfo = parseClerkEnvironment(response.value);
    } catch (_) {
      // Keep default environment info when offline so UI still renders usable options.
    }
    return this.environmentInfo;
  }

  async restore(): Promise<CloudAccountSession | undefined> {
    const stored = await this.store.load().catch(async (error: Error) => {
      // If a legacy v1 or malformed record exists, fail closed and ask the user to sign in cleanly.
      if (error.message.includes('解锁')) throw error;
      try { await this.store.clear(); } catch (_) {}
      return undefined;
    });
    try {
      const pending = await this.ssoStore.load();
      if (pending && pending.publishableKey === this.config.clerk.publishableKey &&
        pending.relayUrl === this.config.relay.url && pending.jwtTemplate === this.config.clerk.jwtTemplate) {
        this.pendingSso = pending;
        this.pendingSsoStrategy = pending.strategy;
      } else if (pending) {
        await this.ssoStore.clear();
      }
    } catch (_) {}

    if (!stored) {
      this.session = undefined;
      this.cachedTemplateToken = undefined;
      this.status = this.pendingSso ? '等待浏览器授权返回' : '未登录';
      return undefined;
    }
    if (stored.publishableKey !== this.config.clerk.publishableKey ||
      stored.relayUrl !== this.config.relay.url ||
      stored.jwtTemplate !== this.config.clerk.jwtTemplate) {
      await this.store.clear();
      this.session = undefined;
      this.cachedTemplateToken = undefined;
      throw new Error('T3 Connect 账号配置已变化，请重新登录');
    }

    // Best-effort refresh client session & profile; tolerate transient offline start.
    try {
      const fetched = await this.runSerialized(() => this.fapi(http.RequestMethod.GET, '/v1/client', stored.clientToken));
      const clientState = parseClerkClientEnvelope(fetched.result.value);
      const active = selectActiveClerkSession(clientState, stored.sessionId);
      if (!active) {
        await this.store.clear();
        this.session = undefined;
        this.cachedTemplateToken = undefined;
        this.status = '登录已过期，请重新登录';
        return undefined;
      }
      const refreshed = this.buildSession(active, fetched.clientToken);
      if (refreshed.clientToken !== stored.clientToken || refreshed.email !== stored.email ||
        refreshed.displayName !== stored.displayName || refreshed.sessionId !== stored.sessionId) {
        await this.store.save(refreshed);
      }
      this.session = refreshed;
      this.status = '已登录';
      return refreshed;
    } catch (error) {
      if (error instanceof CloudHttpFailure && this.isExpiredClerkFailure(error)) {
        await this.store.clear();
        this.session = undefined;
        this.cachedTemplateToken = undefined;
        this.status = '登录已过期，请重新登录';
        return undefined;
      }
      this.session = stored;
      this.status = '已登录';
      return stored;
    }
  }

  private async ensureFreshAnonymousClient(): Promise<string> {
    const response = await this.fapi(http.RequestMethod.GET, '/v1/client', '');
    if (!response.clientToken) throw new Error('Clerk 未返回客户端会话令牌');
    this.workingClientToken = response.clientToken;
    return response.clientToken;
  }

  private async resolveCompletedSession(clientState: ClerkClientState, preferredSessionId: string,
    clientToken: string): Promise<CloudAccountSession> {
    let active = selectActiveClerkSession(clientState, preferredSessionId);
    let token = clientToken;
    if (!active) {
      const reloaded = await this.fapi(http.RequestMethod.GET, '/v1/client', token);
      token = reloaded.clientToken;
      active = selectActiveClerkSession(parseClerkClientEnvelope(reloaded.result.value), preferredSessionId);
    }
    if (!active) throw new Error('登录已完成但未读取到有效会话，请重试');
    return this.buildSession(active, token);
  }

  private async finalizeSignInResponse(result: CloudHttpResult, clientToken: string): Promise<CloudSignInResult> {
    this.workingClientToken = clientToken;
    const envelope = record(result.value);
    const attempt = parseClerkSignInAttempt(envelope.response !== undefined && envelope.response !== null ?
      envelope.response : envelope);
    const clientState = parseClerkClientEnvelope(envelope);
    if (attempt.status === 'complete') {
      const session = await this.resolveCompletedSession(clientState, attempt.createdSessionId, clientToken);
      this.activeAttempt = undefined;
      this.workingClientToken = '';
      return { kind: 'complete', session, attempt };
    }
    if (attempt.status === 'needs_second_factor') {
      this.activeAttempt = attempt;
      this.status = '需要完成两步验证';
      return { kind: 'needs_second_factor', session: undefined, attempt };
    }
    this.activeAttempt = attempt;
    this.status = '请选择验证方式完成登录';
    return { kind: 'needs_first_factor', session: undefined, attempt };
  }

  async startEmailSignIn(email: string): Promise<CloudSignInResult> {
    if (!cloudSignInReady(this.config)) throw new Error('T3 Connect 配置不完整');
    const identifier = email.trim();
    if (!identifier || !identifier.includes('@') || identifier.length > 256) {
      throw new Error('请输入有效的邮箱地址');
    }
    return this.runSerialized(async () => {
      this.activeAttempt = undefined;
      this.pendingSso = undefined;
      this.pendingSsoStrategy = '';
      try { await this.ssoStore.clear(); } catch (_) {}
      try {
        const clientToken = await this.ensureFreshAnonymousClient();
        const response = await this.fapi(http.RequestMethod.POST, '/v1/client/sign_ins', clientToken,
          'identifier=' + encodeURIComponent(identifier));
        return await this.finalizeSignInResponse(response.result, response.clientToken);
      } catch (error) {
        throw this.mapClerkError(error as Object);
      }
    });
  }

  async sendEmailCode(): Promise<ClerkSignInAttempt> {
    const attempt = this.activeAttempt;
    if (!attempt || !this.workingClientToken) throw new Error('请先输入邮箱地址');
    const factor = attempt.supportedFirstFactors.find((item) => item.strategy === 'email_code');
    if (!factor) throw new Error('该账号不支持邮箱验证码登录');
    return this.runSerialized(async () => {
      try {
        let body = 'strategy=email_code';
        if (factor.emailAddressId) body += '&email_address_id=' + encodeURIComponent(factor.emailAddressId);
        const response = await this.fapi(http.RequestMethod.POST,
          '/v1/client/sign_ins/' + encodeURIComponent(attempt.id) + '/prepare_first_factor',
          this.workingClientToken, body);
        this.workingClientToken = response.clientToken;
        const envelope = record(response.result.value);
        const updated = parseClerkSignInAttempt(envelope.response !== undefined && envelope.response !== null ?
          envelope.response : envelope);
        this.activeAttempt = updated;
        this.status = '验证码已发送到 ' + (factor.safeIdentifier || attempt.identifier || '你的邮箱');
        return updated;
      } catch (error) {
        throw this.mapClerkError(error as Object);
      }
    });
  }

  async verifyEmailCode(code: string): Promise<CloudSignInResult> {
    const attempt = this.activeAttempt;
    if (!attempt || !this.workingClientToken) throw new Error('请先输入邮箱并发送验证码');
    const cleaned = code.trim();
    if (!cleaned || cleaned.length > 32) throw new Error('请输入邮箱收到的验证码');
    return this.runSerialized(async () => {
      try {
        const body = 'strategy=email_code&code=' + encodeURIComponent(cleaned);
        const response = await this.fapi(http.RequestMethod.POST,
          '/v1/client/sign_ins/' + encodeURIComponent(attempt.id) + '/attempt_first_factor',
          this.workingClientToken, body);
        return await this.finalizeSignInResponse(response.result, response.clientToken);
      } catch (error) {
        throw this.mapClerkError(error as Object);
      }
    });
  }

  async verifyPassword(password: string): Promise<CloudSignInResult> {
    const attempt = this.activeAttempt;
    if (!attempt || !this.workingClientToken) throw new Error('请先输入邮箱地址');
    if (!password) throw new Error('请输入账号密码');
    return this.runSerialized(async () => {
      try {
        const body = 'strategy=password&password=' + encodeURIComponent(password);
        const response = await this.fapi(http.RequestMethod.POST,
          '/v1/client/sign_ins/' + encodeURIComponent(attempt.id) + '/attempt_first_factor',
          this.workingClientToken, body);
        return await this.finalizeSignInResponse(response.result, response.clientToken);
      } catch (error) {
        throw this.mapClerkError(error as Object);
      }
    });
  }

  async prepareSecondFactor(strategy: string): Promise<ClerkSignInAttempt> {
    const attempt = this.activeAttempt;
    if (!attempt || !this.workingClientToken) throw new Error('没有等待中的两步验证');
    return this.runSerialized(async () => {
      try {
        const factor = attempt.supportedSecondFactors.find((item) => item.strategy === strategy);
        let body = 'strategy=' + encodeURIComponent(strategy);
        if (factor?.emailAddressId) body += '&email_address_id=' + encodeURIComponent(factor.emailAddressId);
        const response = await this.fapi(http.RequestMethod.POST,
          '/v1/client/sign_ins/' + encodeURIComponent(attempt.id) + '/prepare_second_factor',
          this.workingClientToken, body);
        this.workingClientToken = response.clientToken;
        const envelope = record(response.result.value);
        const updated = parseClerkSignInAttempt(envelope.response !== undefined && envelope.response !== null ?
          envelope.response : envelope);
        this.activeAttempt = updated;
        this.status = '已发送二次验证码';
        return updated;
      } catch (error) {
        throw this.mapClerkError(error as Object);
      }
    });
  }

  async verifySecondFactor(strategy: string, code: string): Promise<CloudSignInResult> {
    const attempt = this.activeAttempt;
    if (!attempt || !this.workingClientToken) throw new Error('没有等待中的两步验证');
    const cleaned = code.trim();
    if (!cleaned || cleaned.length > 64) throw new Error('请输入两步验证码');
    return this.runSerialized(async () => {
      try {
        const body = 'strategy=' + encodeURIComponent(strategy) + '&code=' + encodeURIComponent(cleaned);
        const response = await this.fapi(http.RequestMethod.POST,
          '/v1/client/sign_ins/' + encodeURIComponent(attempt.id) + '/attempt_second_factor',
          this.workingClientToken, body);
        return await this.finalizeSignInResponse(response.result, response.clientToken);
      } catch (error) {
        throw this.mapClerkError(error as Object);
      }
    });
  }

  async beginSso(strategy: string, context: common.UIAbilityContext): Promise<void> {
    if (!cloudSignInReady(this.config)) throw new Error('T3 Connect 配置不完整');
    if (!/^oauth_[a-z0-9_]+$/.test(strategy)) throw new Error('不支持的第三方登录方式');
    await this.runSerialized(async () => {
      this.activeAttempt = undefined;
      try {
        const clientToken = await this.ensureFreshAnonymousClient();
        const redirect = this.config.clerk.redirectUri;
        const body = 'strategy=' + encodeURIComponent(strategy) +
          '&redirect_url=' + encodeURIComponent(redirect) +
          '&action_complete_redirect_url=' + encodeURIComponent(redirect);
        const response = await this.fapi(http.RequestMethod.POST, '/v1/client/sign_ins', clientToken, body);
        const envelope = record(response.result.value);
        const attempt = parseClerkSignInAttempt(envelope.response !== undefined && envelope.response !== null ?
          envelope.response : envelope);
        if (!attempt.externalRedirectUrl) {
          throw new Error('Clerk 未返回第三方登录跳转地址，请确认重定向白名单已包含 ' + redirect);
        }
        const pending: PendingSsoSignIn = {
          signInId: attempt.id,
          strategy,
          clientToken: response.clientToken,
          publishableKey: this.config.clerk.publishableKey,
          relayUrl: this.config.relay.url,
          jwtTemplate: this.config.clerk.jwtTemplate,
          redirectUri: redirect,
          createdAt: Date.now()
        };
        await this.ssoStore.save(pending);
        this.pendingSso = pending;
        this.pendingSsoStrategy = strategy;
        this.workingClientToken = response.clientToken;
        try {
          await context.openLink(attempt.externalRedirectUrl);
          this.status = '请在系统浏览器完成第三方授权，完成后将自动返回';
        } catch (_) {
          this.pendingSso = undefined;
          this.pendingSsoStrategy = '';
          try { await this.ssoStore.clear(); } catch (_) {}
          this.status = '无法打开系统浏览器';
          throw new Error('无法打开系统浏览器，请检查系统浏览器设置');
        }
      } catch (error) {
        throw this.mapClerkError(error as Object);
      }
    });
  }

  async completeSsoCallback(uri: string): Promise<CloudSignInResult> {
    return this.runSerialized(async (): Promise<CloudSignInResult> => {
      const pending = this.pendingSso || await this.ssoStore.load();
      // Consume immediately so a replayed deep link cannot complete twice.
      this.pendingSso = undefined;
      this.pendingSsoStrategy = '';
      try { await this.ssoStore.clear(); } catch (_) {}
      if (!pending) {
        throw new Error('没有等待中的第三方登录，请重新发起登录');
      }
      if (pending.publishableKey !== this.config.clerk.publishableKey ||
        pending.relayUrl !== this.config.relay.url ||
        pending.jwtTemplate !== this.config.clerk.jwtTemplate) {
        throw new Error('T3 Connect 配置已变化，请重新发起登录');
      }
      const callback = clerkSsoCallback(uri, pending.redirectUri);
      try {
        const extraQuery = callback.rotatingTokenNonce ?
          'rotating_token_nonce=' + encodeURIComponent(callback.rotatingTokenNonce) : '';
        const response = await this.fapi(http.RequestMethod.GET,
          '/v1/client/sign_ins/' + encodeURIComponent(pending.signInId),
          pending.clientToken, '', extraQuery);
        const envelope = record(response.result.value);
        const attempt = parseClerkSignInAttempt(envelope.response !== undefined && envelope.response !== null ?
          envelope.response : envelope);
        const clientState = parseClerkClientEnvelope(envelope);
        let token = response.clientToken;
        this.workingClientToken = token;

        if (attempt.status === 'complete') {
          const session = await this.resolveCompletedSession(clientState,
            attempt.createdSessionId || callback.createdSessionId, token);
          this.activeAttempt = undefined;
          this.workingClientToken = '';
          const completed: CloudSignInResult = { kind: 'complete', session, attempt };
          return completed;
        }
        if (attempt.status === 'needs_second_factor') {
          this.activeAttempt = attempt;
          this.status = '需要完成两步验证';
          const needsSecond: CloudSignInResult = { kind: 'needs_second_factor', session: undefined, attempt };
          return needsSecond;
        }
        if (attempt.firstFactorStatus === 'transferable') {
          const signUpResponse = await this.fapi(http.RequestMethod.POST, '/v1/client/sign_ups',
            token, 'transfer=true');
          token = signUpResponse.clientToken;
          this.workingClientToken = token;
          const signUpEnvelope = record(signUpResponse.result.value);
          const signUpBody = signUpEnvelope.response !== undefined && signUpEnvelope.response !== null ?
            record(signUpEnvelope.response) : signUpEnvelope;
          const signUpClient = parseClerkClientEnvelope(signUpEnvelope);
          const createdId = typeof signUpBody.created_session_id === 'string' ?
            (signUpBody.created_session_id as string) : '';
          if (signUpBody.status === 'complete' || createdId) {
            const session = await this.resolveCompletedSession(signUpClient, createdId, token);
            this.activeAttempt = undefined;
            this.workingClientToken = '';
            const transferred: CloudSignInResult = { kind: 'complete', session, attempt };
            return transferred;
          }
          throw new Error('该第三方账号尚未完成 T3 Connect 注册，请先在 app.t3.codes 完成首次注册后再登录');
        }
        const activeFallback = selectActiveClerkSession(clientState, callback.createdSessionId);
        if (activeFallback) {
          const session = this.buildSession(activeFallback, token);
          this.activeAttempt = undefined;
          this.workingClientToken = '';
          const fallbackResult: CloudSignInResult = { kind: 'complete', session, attempt };
          return fallbackResult;
        }
        if (attempt.firstFactorError) {
          throw new Error(attempt.firstFactorError);
        }
        throw new Error('第三方登录未完成，请重试');
      } catch (error) {
        throw this.mapClerkError(error as Object);
      }
    });
  }

  async getRelayToken(forceRefresh: boolean = false): Promise<string> {
    const active = this.session;
    if (!active) throw new CloudSessionExpiredError('请先登录 T3 Connect');
    if (!forceRefresh && this.cachedTemplateToken &&
      this.cachedTemplateToken.accountId === active.accountId &&
      this.cachedTemplateToken.sessionId === active.sessionId &&
      this.cachedTemplateToken.jwtTemplate === this.config.clerk.jwtTemplate &&
      this.cachedTemplateToken.expiresAtMillis > Date.now() + RELAY_TOKEN_SKEW_MS) {
      return this.cachedTemplateToken.jwt;
    }
    if (!forceRefresh && this.mintInFlight) return this.mintInFlight;
    const generation = this.generation;
    const promise = this.runSerialized(async (): Promise<string> => {
      const current = this.session;
      if (!current || generation !== this.generation) {
        throw new CloudSessionExpiredError('T3 Connect 账号已切换，请重新登录');
      }
      if (!forceRefresh && this.cachedTemplateToken &&
        this.cachedTemplateToken.accountId === current.accountId &&
        this.cachedTemplateToken.sessionId === current.sessionId &&
        this.cachedTemplateToken.jwtTemplate === this.config.clerk.jwtTemplate &&
        this.cachedTemplateToken.expiresAtMillis > Date.now() + RELAY_TOKEN_SKEW_MS) {
        return this.cachedTemplateToken.jwt;
      }
      try {
        const path = '/v1/client/sessions/' + encodeURIComponent(current.sessionId) +
          '/tokens/' + encodeURIComponent(this.config.clerk.jwtTemplate);
        const response = await this.fapi(http.RequestMethod.POST, path, current.clientToken);
        if (generation !== this.generation || !this.session || this.session.accountId !== current.accountId) {
          throw new CloudSessionExpiredError('T3 Connect 账号已切换');
        }
        await this.persistRotatedSessionToken(response.clientToken);
        const minted = parseClerkTemplateToken(response.result.value, current.accountId);
        this.cachedTemplateToken = {
          accountId: current.accountId,
          sessionId: current.sessionId,
          jwtTemplate: this.config.clerk.jwtTemplate,
          jwt: minted.jwt,
          expiresAtMillis: minted.expiresAtMillis
        };
        return minted.jwt;
      } catch (error) {
        this.cachedTemplateToken = undefined;
        throw this.mapClerkError(error as Object);
      }
    });
    this.mintInFlight = promise;
    try {
      return await promise;
    } finally {
      if (this.mintInFlight === promise) this.mintInFlight = undefined;
    }
  }

  async persist(value: CloudAccountSession): Promise<void> {
    const checked = cloudAccountSession(value);
    await this.store.save(checked);
    this.generation++;
    this.session = checked;
    this.activeAttempt = undefined;
    this.pendingSso = undefined;
    this.pendingSsoStrategy = '';
    this.workingClientToken = '';
    this.cachedTemplateToken = undefined;
    this.status = '已登录';
  }

  async clear(revokeRemote: boolean = true): Promise<void> {
    const previous = this.session;
    this.generation++;
    this.session = undefined;
    this.activeAttempt = undefined;
    this.pendingSso = undefined;
    this.pendingSsoStrategy = '';
    this.workingClientToken = '';
    this.cachedTemplateToken = undefined;
    this.status = '未登录';
    if (revokeRemote && previous) {
      try {
        await this.runSerialized(() => this.fapi(http.RequestMethod.POST,
          '/v1/client/sessions/' + encodeURIComponent(previous.sessionId) + '/remove',
          previous.clientToken));
      } catch (_) {}
    }
    try { await this.ssoStore.clear(); } catch (_) {}
    await this.store.clear();
  }

  async cancelPending(): Promise<void> {
    this.activeAttempt = undefined;
    this.pendingSso = undefined;
    this.pendingSsoStrategy = '';
    this.workingClientToken = '';
    this.status = this.session ? '已登录' : '登录已取消';
    try { await this.ssoStore.clear(); } catch (_) {}
  }
}
