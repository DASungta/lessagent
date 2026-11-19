import { common } from '@kit.AbilityKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { record, text } from '../protocol/Wire';
import {
  base64UrlEncode, clerkFrontendApi, clerkTokenSubject, CloudAccountSession, CloudConfig,
  cloudAccountSession, cloudSignInReady, oauthAuthorizeUrl, oauthCallback, oauthTokenForm
} from '../protocol/Cloud';
import { CloudSessionStore } from '../storage/CloudStores';
import { CloudHttpFailure, CloudHttpResult, cloudHttp } from './CloudHttp';
import { DpopSigner } from './Dpop';

interface PendingLogin { state: string; verifier: string; generation: number; }

export class CloudAuth {
  config: CloudConfig;
  session: CloudAccountSession | undefined = undefined;
  status: string = '未登录';
  private store: CloudSessionStore;
  private signer: DpopSigner;
  private pending: PendingLogin | undefined = undefined;
  private generation: number = 0;

  constructor(config: CloudConfig, signer: DpopSigner, store: CloudSessionStore = new CloudSessionStore()) {
    this.config = config; this.signer = signer; this.store = store;
  }

  private random(byteLength: number): string {
    return base64UrlEncode(cryptoFramework.createRandom().generateRandomSync(byteLength).data);
  }

  async restore(): Promise<CloudAccountSession | undefined> {
    const stored = await this.store.load();
    if (!stored) { this.session = undefined; this.status = '未登录'; return undefined; }
    if (stored.relayUrl !== this.config.relay.url || stored.clientId !== this.config.clerk.oauthClientId ||
      stored.jwtTemplate !== this.config.clerk.jwtTemplate || stored.redirectUri !== this.config.clerk.redirectUri) {
      await this.store.clear();
      throw new Error('T3 Connect 账号配置已变化，请重新登录');
    }
    if (stored.expiresAt <= Date.now()) {
      await this.store.clear();
      this.session = undefined;
      this.status = '登录已过期，请重新登录';
      return undefined;
    }
    this.session = stored;
    this.status = '已登录';
    return stored;
  }

  async begin(context: common.UIAbilityContext): Promise<void> {
    if (!cloudSignInReady(this.config)) {
      throw new Error('T3 Connect 尚未完成 Clerk 公开配置与鸿蒙 OAuth 客户端注册');
    }
    const verifier = this.random(48);
    const state = this.random(32);
    const challenge = await this.signer.sha256Base64Url(verifier);
    this.generation++;
    this.pending = { state, verifier, generation: this.generation };
    const target = oauthAuthorizeUrl(this.config, state, challenge);
    try {
      await context.openLink(target);
      this.status = '请在系统浏览器完成登录';
    } catch (_) {
      this.pending = undefined;
      this.status = '无法打开系统登录页';
      throw new Error('无法打开系统登录页，请检查浏览器与网络');
    }
  }

  async complete(uri: string): Promise<CloudAccountSession> {
    const pending = this.pending;
    // Consume before any request so a repeated callback cannot replay the authorization code.
    this.pending = undefined;
    if (!pending || pending.generation !== this.generation) {
      throw new Error('没有等待中的 T3 Connect 登录，请重新发起登录');
    }
    const callback = oauthCallback(uri, pending.state, this.config.clerk.redirectUri);
    const target = clerkFrontendApi(this.config.clerk.publishableKey) + '/oauth/token';
    let result: CloudHttpResult;
    try {
      result = await cloudHttp(target, http.RequestMethod.POST,
        {}, oauthTokenForm(callback.code, pending.verifier, this.config),
        'application/x-www-form-urlencoded');
    } catch (error) {
      if (error instanceof CloudHttpFailure) throw new Error('Clerk 登录失败（HTTP ' + error.status + '），请重试');
      throw error as Error;
    }
    const row = record(result.value);
    const accessToken = text(row.access_token);
    const tokenType = text(row.token_type);
    const expiresIn = row.expires_in as number;
    if ((tokenType !== 'Bearer' && tokenType !== 'DPoP') || !accessToken ||
      !Number.isSafeInteger(expiresIn) || expiresIn <= 0) throw new Error('Clerk 返回了无效的登录令牌');
    const accountId = clerkTokenSubject(accessToken);
    return {
      accountId,
      accessToken,
      expiresAt: Date.now() + expiresIn * 1000,
      relayUrl: this.config.relay.url,
      clientId: this.config.clerk.oauthClientId,
      redirectUri: this.config.clerk.redirectUri,
      jwtTemplate: this.config.clerk.jwtTemplate
    };
  }

  async persist(value: CloudAccountSession): Promise<void> {
    const checked = cloudAccountSession(value);
    await this.store.save(checked);
    this.session = checked;
    this.status = '已登录';
  }

  async clear(): Promise<void> {
    this.generation++;
    this.pending = undefined;
    this.session = undefined;
    this.status = '未登录';
    await this.store.clear();
  }

  cancelPending(): void {
    this.generation++;
    this.pending = undefined;
    this.status = '登录已取消';
  }
}
