import { url } from '@kit.ArkTS';
import { objects, record, text } from './Wire';

export interface CloudClerkConfig {
  publishableKey: string;
  jwtTemplate: string;
  oauthClientId: string;
  redirectUri: string;
}

export interface CloudRelayConfig {
  url: string;
}

export interface CloudConfig {
  clerk: CloudClerkConfig;
  relay: CloudRelayConfig;
}

export const CLOUD_CALLBACK = 't3code://auth/callback';

function optionalText(value: Object | undefined, maxLength: number, label: string): string {
  if (value === undefined || value === null) return '';
  const result = text(value).trim();
  if (result.length > maxLength || /[\u0000-\u001f\u007f]/.test(result)) throw new Error(label + '无效');
  return result;
}

// Upstream normalizeSecureRelayUrl: HTTPS origin only, no credentials/path/query/hash.
export function secureRelayUrl(value: string): string {
  const raw = value.trim();
  if (!raw || raw.length > 2048) throw new Error('T3 Connect 中继地址无效');
  try {
    const parsed = new url.URL(raw);
    if (parsed.protocol !== 'https:' || parsed.username || parsed.password ||
      parsed.search || parsed.hash || !/^\/+$/.test(parsed.pathname)) throw new Error('relay');
    return parsed.origin;
  } catch (_) {
    throw new Error('T3 Connect 中继地址必须是 HTTPS 根地址');
  }
}

function callbackUri(value: string): string {
  const raw = value.trim();
  if (raw !== CLOUD_CALLBACK) throw new Error('T3 Connect 回调地址必须为 ' + CLOUD_CALLBACK);
  return raw;
}

export function cloudConfig(value: Object): CloudConfig {
  const root = record(value);
  const clerk = record(root.clerk);
  const relay = record(root.relay);
  const relayUrl = optionalText(relay.url, 2048, 'T3 Connect 中继地址');
  const result: CloudConfig = {
    clerk: {
      publishableKey: optionalText(clerk.publishableKey, 512, 'Clerk publishable key'),
      jwtTemplate: optionalText(clerk.jwtTemplate, 256, 'Clerk JWT template'),
      oauthClientId: optionalText(clerk.oauthClientId, 256, 'Clerk OAuth client id'),
      redirectUri: optionalText(clerk.redirectUri, 256, 'T3 Connect 回调地址')
    },
    relay: { url: relayUrl ? secureRelayUrl(relayUrl) : '' }
  };
  if (result.clerk.publishableKey && !/^pk_(test|live)_[A-Za-z0-9+/=_-]+$/.test(result.clerk.publishableKey)) {
    throw new Error('Clerk publishable key 无效');
  }
  if (result.clerk.redirectUri) callbackUri(result.clerk.redirectUri);
  return result;
}

export function cloudConfigured(config: CloudConfig): boolean {
  return !!config.clerk.publishableKey && !!config.clerk.jwtTemplate && !!config.relay.url;
}

export function cloudSignInReady(config: CloudConfig): boolean {
  return cloudConfigured(config) && !!config.clerk.oauthClientId && config.clerk.redirectUri === CLOUD_CALLBACK;
}

function base64Bytes(value: string): Uint8Array {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let clean = value.replace(/\s/g, '');
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(clean) || clean.length % 4 === 1) throw new Error('base64');
  while (clean.length % 4) clean += '=';
  const result: number[] = [];
  for (let index = 0; index < clean.length; index += 4) {
    const a = clean[index] === '=' ? 0 : alphabet.indexOf(clean[index]);
    const b = clean[index + 1] === '=' ? 0 : alphabet.indexOf(clean[index + 1]);
    const c = clean[index + 2] === '=' ? 0 : alphabet.indexOf(clean[index + 2]);
    const d = clean[index + 3] === '=' ? 0 : alphabet.indexOf(clean[index + 3]);
    if (a < 0 || b < 0 || c < 0 || d < 0) throw new Error('base64');
    result.push((a << 2) | (b >> 4));
    if (clean[index + 2] !== '=') result.push(((b & 15) << 4) | (c >> 2));
    if (clean[index + 3] !== '=') result.push(((c & 3) << 6) | d);
  }
  return Uint8Array.from(result);
}

function latin1(value: Uint8Array): string {
  let result = '';
  for (let index = 0; index < value.length; index++) result += String.fromCharCode(value[index]);
  return result;
}

export function clerkFrontendApi(publishableKey: string): string {
  const parts = publishableKey.split('_');
  if (parts.length < 3 || (parts[0] !== 'pk' || (parts[1] !== 'test' && parts[1] !== 'live'))) {
    throw new Error('Clerk publishable key 无效');
  }
  let decoded: string;
  try {
    decoded = latin1(base64Bytes(parts.slice(2).join('_'))).replace(/\$+$/, '');
  } catch (_) {
    throw new Error('Clerk publishable key 无效');
  }
  if (!decoded || decoded.includes('/') || /[\u0000-\u0020]/.test(decoded)) throw new Error('Clerk publishable key 无效');
  try {
    const parsed = new url.URL('https://' + decoded);
    if (parsed.protocol !== 'https:' || parsed.username || parsed.password || parsed.pathname !== '/' ||
      parsed.search || parsed.hash) throw new Error('clerk');
    return parsed.origin;
  } catch (_) {
    throw new Error('Clerk publishable key 无效');
  }
}

function randomToken(value: string, label: string, minimum: number, maximum: number): string {
  const result = value.trim();
  if (result.length < minimum || result.length > maximum || !/^[A-Za-z0-9._~-]+$/.test(result)) {
    throw new Error(label + '无效');
  }
  return result;
}

export function oauthAuthorizeUrl(config: CloudConfig, state: string, challenge: string): string {
  if (!cloudSignInReady(config)) throw new Error('T3 Connect 尚未完成鸿蒙客户端注册与公开配置');
  const checkedState = randomToken(state, '登录状态', 16, 256);
  const checkedChallenge = randomToken(challenge, 'PKCE 校验值', 43, 43);
  const endpoint = clerkFrontendApi(config.clerk.publishableKey) + '/oauth/authorize';
  const params = 'response_type=code&client_id=' + encodeURIComponent(config.clerk.oauthClientId) +
    '&redirect_uri=' + encodeURIComponent(config.clerk.redirectUri) +
    '&scope=' + encodeURIComponent('openid profile email') +
    '&code_challenge=' + encodeURIComponent(checkedChallenge) + '&code_challenge_method=S256' +
    '&state=' + encodeURIComponent(checkedState);
  return endpoint + '?' + params;
}

export function oauthTokenForm(code: string, verifier: string, config: CloudConfig): string {
  if (!cloudSignInReady(config)) throw new Error('T3 Connect 尚未完成鸿蒙客户端注册与公开配置');
  const checkedCode = text(code).trim();
  if (!checkedCode || checkedCode.length > 8192 || /[\u0000-\u001f\u007f]/.test(checkedCode)) throw new Error('登录回调凭据无效');
  const checkedVerifier = randomToken(verifier, 'PKCE 校验值', 43, 128);
  return 'grant_type=authorization_code&code=' + encodeURIComponent(checkedCode) +
    '&client_id=' + encodeURIComponent(config.clerk.oauthClientId) +
    '&redirect_uri=' + encodeURIComponent(config.clerk.redirectUri) +
    '&code_verifier=' + encodeURIComponent(checkedVerifier);
}

export interface OAuthCallback { code: string; state: string; }

export function oauthCallback(uri: string, expectedState: string, redirectUri: string): OAuthCallback {
  let parsed: url.URL;
  try {
    parsed = new url.URL(uri);
  } catch (_) {
    throw new Error('T3 Connect 登录回调无效');
  }
  const expected = new url.URL(redirectUri);
  if (parsed.protocol !== expected.protocol || parsed.hostname !== expected.hostname ||
    parsed.pathname !== expected.pathname || parsed.username || parsed.password ||
    parsed.hash || parsed.params.get('error')) throw new Error('T3 Connect 登录回调无效');
  const state = parsed.params.get('state') || '';
  const code = parsed.params.get('code') || '';
  if (!state || state !== expectedState) throw new Error('T3 Connect 登录状态不匹配，请重新登录');
  if (!code || code.length > 8192 || /[\u0000-\u001f\u007f]/.test(code)) throw new Error('T3 Connect 登录码无效');
  return { code, state };
}

export function base64UrlEncode(value: Uint8Array): string {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  let result = '';
  for (let index = 0; index < value.length; index += 3) {
    const a = value[index];
    const b = index + 1 < value.length ? value[index + 1] : 0;
    const c = index + 2 < value.length ? value[index + 2] : 0;
    result += alphabet[a >> 2];
    result += alphabet[((a & 3) << 4) | (b >> 4)];
    if (index + 1 < value.length) result += alphabet[((b & 15) << 2) | (c >> 6)];
    if (index + 2 < value.length) result += alphabet[c & 63];
  }
  return result;
}

export function base64UrlDecode(value: string): Uint8Array {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  if (!value || value.length > 16384 || !/^[A-Za-z0-9_-]+$/.test(value) || value.length % 4 === 1) {
    throw new Error('base64url 无效');
  }
  const bytes: number[] = [];
  let buffer = 0;
  let bits = 0;
  for (const character of value) {
    const index = alphabet.indexOf(character);
    if (index < 0) throw new Error('base64url 无效');
    buffer = (buffer << 6) | index;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      bytes.push((buffer >> bits) & 255);
    }
  }
  if (bits > 0 && (buffer & ((1 << bits) - 1)) !== 0) throw new Error('base64url 无效');
  return Uint8Array.from(bytes);
}

function utf8(value: string): Uint8Array {
  const bytes: number[] = [];
  for (let index = 0; index < value.length; index++) {
    const code = value.charCodeAt(index);
    if (code >= 0xd800 && code <= 0xdbff && index + 1 < value.length) {
      const low = value.charCodeAt(++index);
      if (low < 0xdc00 || low > 0xdfff) throw new Error('UTF-8 无效');
      const point = 0x10000 + ((code - 0xd800) << 10) + (low - 0xdc00);
      bytes.push(0xf0 | (point >> 18), 0x80 | ((point >> 12) & 63), 0x80 | ((point >> 6) & 63), 0x80 | (point & 63));
    } else if (code <= 0x7f) bytes.push(code);
    else if (code <= 0x7ff) bytes.push(0xc0 | (code >> 6), 0x80 | (code & 63));
    else bytes.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 63), 0x80 | (code & 63));
  }
  return Uint8Array.from(bytes);
}

function jwsSegment(value: Object): string {
  return base64UrlEncode(utf8(JSON.stringify(value)));
}

function utf8String(value: Uint8Array): string {
  let result = '';
  for (let index = 0; index < value.length;) {
    const first = value[index++];
    let code = 0;
    if (first < 0x80) code = first;
    else if ((first & 0xe0) === 0xc0 && index < value.length) code = ((first & 31) << 6) | (value[index++] & 63);
    else if ((first & 0xf0) === 0xe0 && index + 1 < value.length) {
      code = ((first & 15) << 12) | ((value[index++] & 63) << 6) | (value[index++] & 63);
    } else if ((first & 0xf8) === 0xf0 && index + 2 < value.length) {
      code = ((first & 7) << 18) | ((value[index++] & 63) << 12) |
        ((value[index++] & 63) << 6) | (value[index++] & 63);
    } else throw new Error('UTF-8 无效');
    if (code <= 0xffff) result += String.fromCharCode(code);
    else {
      code -= 0x10000;
      result += String.fromCharCode(0xd800 + (code >> 10), 0xdc00 + (code & 1023));
    }
  }
  return result;
}

function tokenPayload(token: string): Record<string, Object> {
  const parts = token.split('.');
  if (parts.length < 2 || parts.length > 3) throw new Error('登录令牌格式无效');
  return record(JSON.parse(utf8String(base64UrlDecode(parts[1]))) as Object);
}

export function clerkTokenSubject(token: string): string {
  const payload = tokenPayload(token);
  const subject = text(payload.sub);
  if (!subject || subject.length > 256 || /[\u0000-\u001f\u007f]/.test(subject)) throw new Error('登录账号身份无效');
  return subject;
}

export function normalizeDpopHtu(value: string): string {
  try {
    const parsed = new url.URL(value);
    if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') throw new Error('scheme');
    parsed.hash = '';
    parsed.search = '';
    return parsed.toString();
  } catch (_) {
    throw new Error('DPoP 目标地址无效');
  }
}

export interface DpopPublicJwk { kty: string; crv: string; x: string; y: string; }

export function dpopPublicJwk(x: Uint8Array, y: Uint8Array): DpopPublicJwk {
  if (x.length !== 32 || y.length !== 32) throw new Error('DPoP 公钥坐标必须为 32 字节');
  return { kty: 'EC', crv: 'P-256', x: base64UrlEncode(x), y: base64UrlEncode(y) };
}

export function checkedDpopPublicJwk(value: Object): DpopPublicJwk {
  const row = record(value);
  if (text(row.kty) !== 'EC' || text(row.crv) !== 'P-256' || base64UrlDecode(text(row.x)).length !== 32 ||
    base64UrlDecode(text(row.y)).length !== 32) throw new Error('DPoP 公钥无效');
  return { kty: 'EC', crv: 'P-256', x: text(row.x), y: text(row.y) };
}

export function dpopThumbprintInput(jwk: DpopPublicJwk): string {
  return JSON.stringify({ crv: jwk.crv, kty: jwk.kty, x: jwk.x, y: jwk.y });
}

export function dpopHeader(jwk: DpopPublicJwk): Object {
  return { typ: 'dpop+jwt', alg: 'ES256', jwk };
}

export function dpopPayload(method: string, target: string, jti: string, iat: number, ath?: string): Object {
  const checkedMethod = method.trim().toUpperCase();
  if (!checkedMethod || checkedMethod.length > 16 || /[^A-Z]/.test(checkedMethod)) throw new Error('DPoP HTTP 方法无效');
  if (!jti || jti.length > 128 || /[\u0000-\u001f\u007f]/.test(jti)) throw new Error('DPoP jti 无效');
  if (!Number.isSafeInteger(iat) || iat <= 0) throw new Error('DPoP 时间无效');
  const payload: Record<string, Object> = { htm: checkedMethod, htu: normalizeDpopHtu(target), jti, iat };
  if (ath !== undefined) {
    if (!ath || !/^[A-Za-z0-9_-]{43}$/.test(ath)) throw new Error('DPoP ath 无效');
    payload.ath = ath;
  }
  return payload;
}

export function dpopSigningInput(header: Object, payload: Object): string {
  return jwsSegment(header) + '.' + jwsSegment(payload);
}

export function dpopProof(signingInput: string, signatureRaw: Uint8Array): string {
  if (signatureRaw.length !== 64) throw new Error('DPoP ES256 签名必须为 64 字节 r‖s');
  return signingInput + '.' + base64UrlEncode(signatureRaw);
}

function derLength(value: Uint8Array, offset: number): { length: number; next: number } {
  if (offset >= value.length) throw new Error('ECC DER 长度无效');
  const first = value[offset];
  if (first < 0x80) return { length: first, next: offset + 1 };
  const count = first & 0x7f;
  if (count < 1 || count > 2 || offset + count >= value.length) throw new Error('ECC DER 长度无效');
  let length = 0;
  for (let index = 0; index < count; index++) length = (length << 8) | value[offset + 1 + index];
  return { length, next: offset + 1 + count };
}

function derInteger(value: Uint8Array, offset: number, size: number): { bytes: Uint8Array; next: number } {
  if (offset >= value.length || value[offset] !== 0x02) throw new Error('ECC DER 整数无效');
  const length = derLength(value, offset + 1);
  const start = length.next;
  const end = start + length.length;
  if (length.length < 1 || end > value.length) throw new Error('ECC DER 整数无效');
  let first = start;
  while (first < end - 1 && value[first] === 0) first++;
  const significant = value.slice(first, end);
  if (significant.length > size) throw new Error('ECC 签名数值过大');
  const bytes = new Uint8Array(size);
  bytes.set(significant, size - significant.length);
  return { bytes, next: end };
}

// Harmony ECDSA returns DER. DPoP/JWS requires the raw fixed-width r‖s pair.
export function rawEccSignature(value: Uint8Array): Uint8Array {
  if (value.length === 64) return value.slice();
  if (value.length < 8 || value.length > 80 || value[0] !== 0x30) throw new Error('ECC 签名格式无效');
  const sequence = derLength(value, 1);
  if (sequence.next + sequence.length !== value.length) throw new Error('ECC 签名长度无效');
  const r = derInteger(value, sequence.next, 32);
  const s = derInteger(value, r.next, 32);
  if (s.next !== value.length) throw new Error('ECC 签名尾部无效');
  const result = new Uint8Array(64);
  result.set(r.bytes, 0);
  result.set(s.bytes, 32);
  return result;
}

export interface RelayEndpoint { httpBaseUrl: string; wsBaseUrl: string; providerKind: string; }

export interface RelayEnvironmentRecord {
  environmentId: string;
  label: string;
  endpoint: RelayEndpoint;
  linkedAt: number;
}

function secureHttpBase(value: Object): string {
  const raw = text(value);
  try {
    const parsed = new url.URL(raw);
    if (parsed.protocol !== 'https:' || parsed.username || parsed.password || parsed.search || parsed.hash) throw new Error('https');
    return parsed.origin;
  } catch (_) {
    throw new Error('T3 Connect 环境地址必须是 HTTPS');
  }
}

function secureWsBase(value: Object): string {
  const raw = text(value);
  try {
    const parsed = new url.URL(raw);
    if (parsed.protocol !== 'wss:' || parsed.username || parsed.password || parsed.search || parsed.hash) throw new Error('wss');
    return parsed.protocol + '//' + parsed.host + '/';
  } catch (_) {
    throw new Error('T3 Connect 环境 WebSocket 地址必须是 WSS');
  }
}

export function relayEndpoint(value: Object): RelayEndpoint {
  const row = record(value);
  const providerKind = text(row.providerKind);
  if (!['manual', 'cloudflare_tunnel', 't3_relay'].includes(providerKind)) throw new Error('T3 Connect 环境端点类型无效');
  return { httpBaseUrl: secureHttpBase(row.httpBaseUrl), wsBaseUrl: secureWsBase(row.wsBaseUrl), providerKind };
}

export function relayEnvironment(value: Object): RelayEnvironmentRecord {
  const row = record(value);
  const environmentId = text(row.environmentId);
  const label = text(row.label).trim();
  const linkedAt = Date.parse(text(row.linkedAt));
  if (!environmentId || environmentId.length > 256 || /[\u0000-\u001f\u007f]/.test(environmentId) ||
    !label || label.length > 256 || !Number.isFinite(linkedAt)) throw new Error('T3 Connect 环境记录无效');
  return { environmentId, label, endpoint: relayEndpoint(row.endpoint), linkedAt };
}

export function relayEnvironments(value: Object): RelayEnvironmentRecord[] {
  const result: RelayEnvironmentRecord[] = [];
  for (const item of objects(record(value).environments)) {
    const environment = relayEnvironment(item);
    if (result.some((row: RelayEnvironmentRecord) => row.environmentId === environment.environmentId)) {
      throw new Error('T3 Connect 环境列表重复');
    }
    result.push(environment);
  }
  return result;
}

export interface RelayStatus {
  environmentId: string;
  endpoint: RelayEndpoint;
  status: string;
  checkedAt: number;
  error: string;
  traceId: string;
  offlineReason: string;
  descriptorEnvironmentId: string;
}

export function relayStatus(value: Object, expected: RelayEnvironmentRecord): RelayStatus {
  const row = record(value);
  const environmentId = text(row.environmentId);
  const endpoint = relayEndpoint(row.endpoint);
  const status = text(row.status);
  const checkedAt = Date.parse(text(row.checkedAt));
  if (environmentId !== expected.environmentId || endpoint.httpBaseUrl !== expected.endpoint.httpBaseUrl ||
    endpoint.wsBaseUrl !== expected.endpoint.wsBaseUrl || endpoint.providerKind !== expected.endpoint.providerKind ||
    (status !== 'online' && status !== 'offline') || !Number.isFinite(checkedAt)) {
    throw new Error('中继返回了不一致的环境状态');
  }
  let descriptorEnvironmentId = '';
  if (row.descriptor !== undefined) {
    descriptorEnvironmentId = text(record(row.descriptor).environmentId);
    if (descriptorEnvironmentId !== environmentId) throw new Error('中继返回了不一致的环境描述');
  }
  return {
    environmentId, endpoint, status, checkedAt,
    error: row.error === undefined ? '' : text(row.error),
    traceId: row.traceId === undefined ? '' : text(row.traceId),
    offlineReason: row.offlineReason === undefined ? '' : text(row.offlineReason),
    descriptorEnvironmentId
  };
}

export interface RelayConnect { environmentId: string; endpoint: RelayEndpoint; credential: string; expiresAt: number; }

export function relayConnect(value: Object, expectedEnvironmentId: string): RelayConnect {
  const row = record(value);
  const environmentId = text(row.environmentId);
  const credential = text(row.credential);
  const expiresAt = Date.parse(text(row.expiresAt));
  if (environmentId !== expectedEnvironmentId || !credential || credential.length > 8192 ||
    /[\u0000-\u001f\u007f]/.test(credential) || !Number.isFinite(expiresAt)) throw new Error('中继返回了无效的环境连接凭据');
  return { environmentId, endpoint: relayEndpoint(row.endpoint), credential, expiresAt };
}

export interface RelayChallenge { challenge: string; expiresAt: number; }
export function relayChallenge(value: Object): RelayChallenge {
  const row = record(value);
  const challenge = text(row.challenge);
  const expiresAt = Date.parse(text(row.expiresAt));
  if (!challenge || challenge.length > 8192 || !Number.isFinite(expiresAt)) throw new Error('中继返回了无效的链接挑战');
  return { challenge, expiresAt };
}

export interface RelayLink {
  environmentId: string;
  endpoint: RelayEndpoint;
  relayIssuer: string;
  environmentCredential: string;
  cloudMintPublicKey: string;
  cloudUserId: string;
  endpointRuntime: Object | undefined;
}

export function relayLink(value: Object, expectedEnvironmentId: string): RelayLink {
  const row = record(value);
  const environmentId = text(row.environmentId);
  const endpoint = relayEndpoint(row.endpoint);
  const relayIssuer = secureRelayUrl(text(row.relayIssuer));
  const environmentCredential = text(row.environmentCredential);
  const cloudMintPublicKey = text(row.cloudMintPublicKey);
  const cloudUserId = text(row.cloudUserId);
  if (environmentId !== expectedEnvironmentId || endpoint.providerKind !== 'cloudflare_tunnel' ||
    !environmentCredential || !cloudMintPublicKey || !cloudUserId) {
    throw new Error('中继返回了不一致的环境链接凭据');
  }
  return { environmentId, endpoint, relayIssuer, environmentCredential, cloudMintPublicKey, cloudUserId,
    endpointRuntime: row.endpointRuntime === undefined || row.endpointRuntime === null ? undefined : record(row.endpointRuntime) };
}

export const RELAY_CONNECT_SCOPE = 'environment:connect';
export const RELAY_STATUS_SCOPE = 'environment:status';
export const RELAY_MOBILE_SCOPE = 'mobile:registration';

export function relayScopes(value: string[]): string[] {
  const result: string[] = [];
  for (const scope of value) {
    if (![RELAY_CONNECT_SCOPE, RELAY_STATUS_SCOPE, RELAY_MOBILE_SCOPE].includes(scope) || result.includes(scope)) {
      throw new Error('T3 Connect 权限范围无效');
    }
    result.push(scope);
  }
  return result;
}

export interface RelayToken {
  accessToken: string;
  issuedTokenType: string;
  tokenType: string;
  expiresIn: number;
  scopes: string[];
}

function sameScopes(left: string[], right: string[]): boolean {
  return left.length === right.length && left.every((scope: string) => right.includes(scope));
}

export function relayToken(value: Object, requested: string[]): RelayToken {
  const row = record(value);
  const tokenType = text(row.token_type);
  const issuedTokenType = text(row.issued_token_type);
  const expiresIn = row.expires_in as number;
  const scopes = text(row.scope).split(/\s+/).filter((scope: string) => !!scope);
  const granted = relayScopes(scopes);
  if (tokenType !== 'DPoP' || issuedTokenType !== 'urn:ietf:params:oauth:token-type:access_token' ||
    !text(row.access_token) || !Number.isSafeInteger(expiresIn) || expiresIn <= 0 || !sameScopes(granted, relayScopes(requested))) {
    throw new Error('中继返回了无效或超出请求范围的令牌');
  }
  return { accessToken: text(row.access_token), issuedTokenType, tokenType, expiresIn, scopes: granted };
}

export interface RelayTokenCache {
  accountId: string;
  clientId: string;
  relayUrl: string;
  thumbprint: string;
  scopes: string[];
  accessToken: string;
  expiresAtMillis: number;
}

export function relayTokenCache(value: Object): RelayTokenCache {
  const row = record(value);
  const scopes = relayScopes(objects(row.scopes).map((scope: Object) => text(scope)));
  const expiresAtMillis = row.expiresAtMillis as number;
  const clientId = text(row.clientId);
  if (clientId !== 't3-mobile' || !text(row.accountId) || !text(row.relayUrl) || !text(row.thumbprint) ||
    !text(row.accessToken) || !Number.isSafeInteger(expiresAtMillis)) throw new Error('中继令牌缓存无效');
  return {
    accountId: text(row.accountId), clientId, relayUrl: text(row.relayUrl), thumbprint: text(row.thumbprint),
    scopes, accessToken: text(row.accessToken), expiresAtMillis
  };
}

export function relayTokenMatches(token: RelayTokenCache, accountId: string, clientId: string,
  relayUrl: string, thumbprint: string, scopes: string[], now: number): boolean {
  return token.accountId === accountId && token.clientId === clientId && token.relayUrl === relayUrl &&
    token.thumbprint === thumbprint && token.expiresAtMillis > now + 5000 &&
    scopes.every((scope: string) => token.scopes.includes(scope));
}

export interface CloudEnvironmentToken {
  environmentId: string;
  accountId: string;
  label: string;
  endpoint: RelayEndpoint;
  accessToken: string;
  expiresAt: number;
  thumbprint: string;
}

export function cloudEnvironmentToken(value: Object): CloudEnvironmentToken {
  const row = record(value);
  const environmentId = text(row.environmentId);
  const accountId = text(row.accountId);
  const accessToken = text(row.accessToken);
  const thumbprint = text(row.thumbprint);
  const expiresAt = row.expiresAt as number;
  if (!environmentId || !accountId || !accessToken || !thumbprint || !Number.isSafeInteger(expiresAt) || expiresAt <= 0) {
    throw new Error('环境 DPoP 令牌缓存无效');
  }
  return { environmentId, accountId, label: text(row.label), endpoint: relayEndpoint(row.endpoint),
    accessToken, expiresAt, thumbprint };
}

export interface CloudAccountSession {
  accountId: string;
  accessToken: string;
  expiresAt: number;
  relayUrl: string;
  clientId: string;
  redirectUri: string;
  jwtTemplate: string;
}

export function cloudAccountSession(value: Object): CloudAccountSession {
  const row = record(value);
  const accountId = text(row.accountId);
  const accessToken = text(row.accessToken);
  const relayUrl = secureRelayUrl(text(row.relayUrl));
  const expiresAt = row.expiresAt as number;
  const redirectUri = text(row.redirectUri);
  const clientId = text(row.clientId);
  const jwtTemplate = text(row.jwtTemplate);
  if (!accountId || !accessToken || !Number.isSafeInteger(expiresAt) || expiresAt <= 0 ||
    !clientId || !jwtTemplate || redirectUri !== CLOUD_CALLBACK) throw new Error('T3 Connect 账号记录无效');
  return { accountId, accessToken, expiresAt, relayUrl, clientId, redirectUri, jwtTemplate };
}

export interface CloudDevice { proofKeyThumbprint: string; verificationCode: string; label: string; approvedAt: number; }
export interface CloudPairingLink {
  id: string;
  createdAt: number;
  expiresAt: number;
  verificationCode: string;
  clientLabel: string;
  clientOs: string;
  clientBrowser: string;
}
export interface AuthAccess {
  pairingLinks: CloudPairingLink[];
  devices: CloudDevice[];
}

function clientDescription(value: Object | undefined): { label: string; os: string; browser: string } {
  if (value === undefined) return { label: '', os: '', browser: '' };
  const client = record(value);
  return {
    label: client.label === undefined ? '' : text(client.label),
    os: client.os === undefined ? '' : text(client.os),
    browser: client.browser === undefined ? '' : text(client.browser)
  };
}

function pairingLink(value: Object): CloudPairingLink {
  const link = record(value);
  const id = text(link.id);
  const createdAt = Date.parse(text(link.createdAt));
  const expiresAt = Date.parse(text(link.expiresAt));
  if (!id || !Number.isFinite(createdAt) || !Number.isFinite(expiresAt)) throw new Error('设备批准请求无效');
  const request = link.connectDeviceRequest === undefined ? undefined : record(link.connectDeviceRequest);
  const client = clientDescription(request === undefined ? undefined : request.client);
  return { id, createdAt, expiresAt,
    verificationCode: request === undefined ? '' : text(request.verificationCode),
    clientLabel: client.label, clientOs: client.os, clientBrowser: client.browser };
}

export function authAccess(value: Object): AuthAccess {
  const row = record(value);
  const pairingLinks: CloudPairingLink[] = [];
  for (const item of objects(row.pairingLinks)) {
    const link = pairingLink(item);
    if (pairingLinks.some((existing: CloudPairingLink) => existing.id === link.id)) throw new Error('设备批准请求无效');
    pairingLinks.push(link);
  }
  const devices: CloudDevice[] = [];
  if (row.connectDevices !== undefined) {
    for (const item of objects(row.connectDevices)) {
      const device = record(item);
      const thumbprint = text(device.proofKeyThumbprint);
      const approvedAt = Date.parse(text(device.approvedAt));
      const client = clientDescription(device.client);
      if (!thumbprint || !Number.isFinite(approvedAt)) throw new Error('已批准设备记录无效');
      devices.push({ proofKeyThumbprint: thumbprint, verificationCode: text(device.verificationCode),
        label: client.label || client.browser || client.os || '新设备', approvedAt });
    }
  }
  return { pairingLinks, devices };
}

export function applyAuthAccessEvent(current: AuthAccess, value: Object): AuthAccess {
  const event = record(value);
  const type = text(event.type);
  if (type === 'snapshot') return authAccess(record(event.payload));
  const payload = record(event.payload);
  if (type === 'pairingLinkUpserted') {
    const link = pairingLink(payload);
    return { pairingLinks: [link].concat(current.pairingLinks.filter((item: CloudPairingLink) => item.id !== link.id)), devices: current.devices };
  }
  if (type === 'pairingLinkRemoved') {
    const id = text(payload.id);
    return { pairingLinks: current.pairingLinks.filter((item: CloudPairingLink) => item.id !== id), devices: current.devices };
  }
  if (type === 'clientUpserted' || type === 'clientRemoved') return current;
  throw new Error('未知设备访问事件');
}

export interface DeviceApprovalPrompt { pairingLinkId: string; title: string; message: string; }

export function deviceName(label: string, os: string, browser: string): string {
  if (label.trim()) return label.trim();
  if (browser.trim() && os.trim()) return browser.trim() + ' · ' + os.trim();
  return browser.trim() || os.trim() || '新设备';
}

export function deviceApprovalPrompts(environmentLabel: string, links: CloudPairingLink[],
  shownIds: string[], now: number): DeviceApprovalPrompt[] {
  return links.filter((link: CloudPairingLink) => !!link.verificationCode && link.expiresAt > now && !shownIds.includes(link.id))
    .sort((left: CloudPairingLink, right: CloudPairingLink) => left.createdAt - right.createdAt)
    .map((link: CloudPairingLink): DeviceApprovalPrompt => ({
      pairingLinkId: link.id,
      title: '批准此设备？',
      message: deviceName(link.clientLabel, link.clientOs, link.clientBrowser) +
        ' 想通过 T3 Connect 连接 ' + environmentLabel + '。设备显示代码 ' + link.verificationCode +
        '。只有代码一致时才批准。'
    }));
}

export function connectDeviceVerificationCode(thumbprint: string): string {
  const base64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  const pairing = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let code = '';
  for (const character of thumbprint.slice(0, 8)) {
    const value = Math.max(0, base64.indexOf(character));
    code += pairing[value % pairing.length];
  }
  return code.slice(0, 4) + '-' + code.slice(4);
}

export function relayOfflineMessage(status: RelayStatus): string {
  if (status.offlineReason === 'tunnel_released') return '托管隧道已释放，无法通过 T3 Connect 连接。';
  if (status.error) return status.error;
  return 'T3 Connect 中继显示环境离线。';
}

export function relayErrorMessage(status: number, value: Object): string {
  let code = '';
  let reason = '';
  let traceId = '';
  try {
    const row = record(value);
    code = row.code === undefined ? '' : text(row.code);
    reason = row.reason === undefined ? '' : text(row.reason);
    traceId = row.traceId === undefined ? '' : text(row.traceId);
  } catch (_) {}
  let message = 'T3 Connect 请求失败（HTTP ' + status + '）';
  if (code === 'auth_invalid') message = reason === 'invalid_bearer' ? 'T3 Connect 登录已过期，请重新登录。' :
    reason === 'invalid_dpop' ? 'DPoP 设备密钥未通过中继校验。' :
    reason === 'missing_bearer' ? '缺少 T3 Connect 登录凭据。' :
    '当前账号无权执行此 T3 Connect 操作。';
  else if (code === 'environment_link_proof_invalid') message = '环境链接证明无效，未建立链接。';
  else if (code === 'environment_link_proof_expired') message = '环境链接挑战已过期，请重试。';
  else if (code === 'environment_connect_not_authorized') {
    message = reason === 'environment_link_not_found' ? '此环境未链接到当前账号。' :
      reason === 'managed_endpoint_allocation_not_ready' ? '托管隧道尚未就绪，请稍后重试。' :
      reason === 'client_proof_key_thumbprint_missing' ? '连接未绑定 DPoP 设备密钥。' :
      '此设备或账号尚未获准连接该环境。';
  } else if (code === 'environment_endpoint_unavailable') {
    message = reason === 'endpoint_request_failed' ? '中继无法访问环境，请检查主机隧道。' :
      reason === 'endpoint_response_invalid' ? '中继收到无效的环境响应。' : 'T3 Connect 环境端点不可用。';
  } else if (code === 'environment_endpoint_timed_out') message = 'T3 Connect 环境连接超时。';
  else if (code === 'environment_link_unavailable') message = 'T3 Connect 中继未配置托管隧道。';
  else if (code === 'environment_link_limit_exceeded') message = '此账号的托管隧道数量已达上限。';
  else if (code === 'internal_error') message = 'T3 Connect 中继暂时不可用。';
  return traceId ? message + ' Trace ID: ' + traceId : message;
}

export interface CloudAccountStep { kind: string; accountId: string; previousAccountId: string; transition: boolean; }

export function planCloudAccountStep(previous: string | undefined, next: string): CloudAccountStep {
  if (previous === next) return { kind: 'none', accountId: next, previousAccountId: '', transition: false };
  if (!next) return { kind: 'signout', accountId: '', previousAccountId: previous || '',
    transition: previous !== undefined };
  return { kind: 'signin', accountId: next, previousAccountId: previous || '', transition: previous !== undefined };
}
