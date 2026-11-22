import { compactArray, objects, record, RpcFailure, text } from './Wire';

export const LINKED_THREAD_RETRY_MS = 15000;

export interface PeerLinkName {
  environmentId: string;
  label: string;
}

export function parsePeerLinkNames(value: Object): PeerLinkName[] {
  const obj = record(value);
  return compactArray(obj.links, (entry: Object): PeerLinkName => {
    const row = record(entry);
    const environmentId = text(row.environmentId).trim();
    const label = typeof row.label === 'string' ? row.label.trim() : '';
    if (!environmentId) throw new Error('无效环境标识');
    return { environmentId, label: label || environmentId };
  });
}

export interface ParsedThreadLink {
  environmentId: string;
  threadId: string;
  decodedThreadId: string;
}

function decodePathSegment(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch (_) {
    return value;
  }
}

/**
 * Parses upstream thread link formats:
 * - t3-thread://v1/<threadId>
 * - t3-thread://v2/<environmentId>/<threadId>
 * - https://app.t3.codes/threads/<encodedEnvironmentId>/<encodedThreadId>
 */
export function parseThreadLinkHref(href: string): ParsedThreadLink | undefined {
  const trimmed = href.trim();
  if (!trimmed) return undefined;
  const v1 = /^t3-thread:\/\/v1\/([^/?#]+)\/?(?:[?#].*)?$/i.exec(trimmed);
  if (v1) {
    const raw = v1[1];
    const decoded = decodePathSegment(raw).trim();
    if (!raw.trim() || !decoded) return undefined;
    return { environmentId: '', threadId: raw, decodedThreadId: decoded };
  }
  const v2 = /^t3-thread:\/\/v2\/([^/?#]+)\/([^/?#]+)\/?(?:[?#].*)?$/i.exec(trimmed);
  if (v2) {
    const envId = decodePathSegment(v2[1]).trim();
    const rawThread = v2[2];
    const decoded = decodePathSegment(rawThread).trim();
    if (!envId || !rawThread.trim() || !decoded) return undefined;
    return { environmentId: envId, threadId: rawThread, decodedThreadId: decoded };
  }
  const web = /^https:\/\/app\.t3\.codes\/threads\/([^/?#]+)\/([^/?#]+)\/?(?:[?#].*)?$/i.exec(trimmed);
  if (web) {
    const envId = decodePathSegment(web[1]).trim();
    const rawThread = web[2];
    const decoded = decodePathSegment(rawThread).trim();
    if (!envId || !rawThread.trim() || !decoded) return undefined;
    return { environmentId: envId, threadId: rawThread, decodedThreadId: decoded };
  }
  return undefined;
}

export function threadLinkCandidates(threadId: string, decodedThreadId: string): string[] {
  const raw = threadId.trim();
  const decoded = decodedThreadId.trim();
  if (!raw && !decoded) return [];
  if (!decoded || decoded === raw) return [raw];
  return [decoded, raw];
}

export interface LinkedThreadTarget {
  viaLocalId: string;
  viaEnvironmentId: string;
  viaLabel: string;
  environmentId: string;
  threadId: string;
  label: string;
}

export type LinkedThreadResolution = 'direct' | 'linked' | 'unavailable';

export interface LinkedThreadOpenInput {
  ownConnected: boolean;
  targetEnvironmentId: string;
  viaEnvironmentId: string;
  linkedEnvironmentsEnabled: boolean;
}

export function resolveLinkedThreadOpen(input: LinkedThreadOpenInput): LinkedThreadResolution {
  if (input.ownConnected) return 'direct';
  if (
    input.viaEnvironmentId.trim() !== '' &&
    input.targetEnvironmentId.trim() !== '' &&
    input.viaEnvironmentId !== input.targetEnvironmentId &&
    input.linkedEnvironmentsEnabled
  ) {
    return 'linked';
  }
  return 'unavailable';
}

export type LinkedThreadFailureReason =
  | 'disabled'
  | 'unknown_link'
  | 'expired'
  | 'rejected'
  | 'unreachable'
  | 'thread_not_found'
  | 'incompatible'
  | 'unauthorized'
  | 'unknown';

export interface LinkedThreadFailure {
  reason: LinkedThreadFailureReason;
  retryable: boolean;
  title: string;
  detail: string;
  label: string;
}

export function isLinkedThreadUnreachable(error: Object | undefined): boolean {
  if (!(error instanceof RpcFailure)) return false;
  if (error.errorTag === 'PeerLinkThreadReadError' && error.errorReason === 'unreachable') return true;
  if (!error.known) return true;
  return false;
}

export function linkedThreadFailure(error: Object | undefined, fallbackLabel: string): LinkedThreadFailure {
  const defaultLabel = fallbackLabel.trim() || '链接环境';
  if (error instanceof RpcFailure) {
    const label = error.errorLabel.trim() || defaultLabel;
    if (error.errorTag === 'EnvironmentAuthorizationError') {
      return {
        reason: 'unauthorized',
        retryable: false,
        title: '没有查看此会话的权限',
        detail: '当前连接缺少读取链接环境会话的权限，请在所属环境授权后重试。',
        label
      };
    }
    if (error.errorTag === 'PeerLinkThreadReadError') {
      const r = error.errorReason;
      if (r === 'disabled') {
        return {
          reason: 'disabled',
          retryable: false,
          title: '链接环境未开启',
          detail: '当前环境未启用链接环境功能，无法读取远端会话。',
          label
        };
      }
      if (r === 'unknown_link') {
        return {
          reason: 'unknown_link',
          retryable: false,
          title: '尚未链接目标环境',
          detail: '当前环境没有到「' + label + '」的环境链接，请先在服务端建立链接。',
          label
        };
      }
      if (r === 'expired') {
        return {
          reason: 'expired',
          retryable: false,
          title: '环境链接已过期',
          detail: '到「' + label + '」的链接已过期，请在服务端重新配对后再试。',
          label
        };
      }
      if (r === 'rejected') {
        return {
          reason: 'rejected',
          retryable: false,
          title: '目标环境拒绝了读取',
          detail: '「' + label + '」拒绝了此链接的读取请求（链接权限不足或已被撤销）。',
          label
        };
      }
      if (r === 'unreachable') {
        return {
          reason: 'unreachable',
          retryable: true,
          title: '暂时无法连接「' + label + '」',
          detail: '目标环境当前不可达，将在稍后自动重试。',
          label
        };
      }
      if (r === 'thread_not_found') {
        return {
          reason: 'thread_not_found',
          retryable: false,
          title: '未找到此会话',
          detail: '「' + label + '」上不存在该会话，可能已被删除。',
          label
        };
      }
      if (r === 'incompatible') {
        return {
          reason: 'incompatible',
          retryable: false,
          title: '目标环境版本不兼容',
          detail: '「' + label + '」运行的服务端版本较旧，暂不支持跨环境只读查看。',
          label
        };
      }
    }
    if (!error.known) {
      return {
        reason: 'unreachable',
        retryable: true,
        title: '连接中断',
        detail: error.message || '与中转环境的连接已中断，稍后将自动重试。',
        label
      };
    }
    return {
      reason: 'unknown',
      retryable: false,
      title: '无法读取远端会话',
      detail: error.errorMessage || error.message || '服务端拒绝了该读取请求。',
      label
    };
  }
  const msg = error instanceof Error ? error.message : '';
  return {
    reason: 'unknown',
    retryable: false,
    title: '无法读取远端会话',
    detail: msg || '读取链接环境会话失败。',
    label: defaultLabel
  };
}

export function isLinkedThreadWorking(runs: Record<string, Object>[]): boolean {
  return runs.some((run: Record<string, Object>) =>
    typeof run.status === 'string' &&
    (run.status === 'preparing' || run.status === 'starting' || run.status === 'running' || run.status === 'waiting')
  );
}

export interface LinkedThreadHistoryPage {
  items: Record<string, Object>[];
  nextCursor: string;
  hasMoreHistory: boolean;
}

export function parseLinkedThreadHistoryPage(value: Object): LinkedThreadHistoryPage {
  const row = record(value);
  const items: Record<string, Object>[] = [];
  for (const projected of objects(row.items)) {
    const entry = record(projected);
    if (entry.item !== undefined && entry.item !== null) {
      const extracted = record(entry.item);
      if (entry.visibility !== undefined) extracted.visibility = entry.visibility;
      if (entry.sourceThreadId !== undefined) extracted.sourceThreadId = entry.sourceThreadId;
      items.push(extracted);
    }
  }
  return {
    items,
    nextCursor: typeof row.nextCursor === 'string' ? row.nextCursor : '',
    hasMoreHistory: row.hasMoreHistory === true
  };
}

export type PeerLinkClientPairingUnsupportedReason = 'link_access' | 'version' | 'refused' | 'unreachable';

export interface PeerLinkClientPairingCredentialResult {
  type: 'credential';
  environmentId: string;
  label: string;
  urls: string[];
  credential: string;
  expiresAt: string;
}

export interface PeerLinkClientPairingUnsupportedResult {
  type: 'unsupported';
  environmentId: string;
  label: string;
  urls: string[];
  reason: PeerLinkClientPairingUnsupportedReason;
}

export type PeerLinkClientPairingResult =
  | PeerLinkClientPairingCredentialResult
  | PeerLinkClientPairingUnsupportedResult;

export function parsePeerLinkClientPairingResult(value: Object): PeerLinkClientPairingResult {
  const row = record(value);
  const type = text(row.type);
  const environmentId = text(row.environmentId).trim();
  const label = typeof row.label === 'string' && row.label.trim() ? row.label.trim() : environmentId;
  if (!environmentId) throw new Error('无效的目标环境标识');
  const urls: string[] = [];
  if (Array.isArray(row.urls)) {
    for (const item of row.urls as Object[]) {
      if (typeof item === 'string' && /^https?:\/\//i.test(item.trim())) {
        urls.push(item.trim());
      }
    }
  }
  if (type === 'credential') {
    const credential = text(row.credential).trim();
    const expiresAt = typeof row.expiresAt === 'string' ? row.expiresAt : '';
    if (!credential) throw new Error('缺少一次性配对凭据');
    return { type: 'credential', environmentId, label, urls, credential, expiresAt };
  }
  if (type === 'unsupported') {
    const rawReason = typeof row.reason === 'string' ? row.reason : 'refused';
    const reason: PeerLinkClientPairingUnsupportedReason =
      rawReason === 'link_access' || rawReason === 'version' || rawReason === 'refused' || rawReason === 'unreachable'
        ? rawReason : 'refused';
    return { type: 'unsupported', environmentId, label, urls, reason };
  }
  throw new Error('未知的客户端配对响应类型');
}

export interface LinkedEnvironmentPrefill {
  environmentId: string;
  label: string;
  host: string;
  credential: string;
  manualReason: string;
}

export interface LinkedEnvironmentConnectOutcome {
  type: 'already_connected' | 'prefill' | 'unreachable';
  localId: string;
  label: string;
  prefill?: LinkedEnvironmentPrefill;
}

export interface PrepareLinkedEnvironmentInput {
  environmentId: string;
  label: string;
  alreadyConnectedLocalId: string;
  requestPairing: () => Promise<PeerLinkClientPairingResult | undefined>;
  reaches: (url: string) => Promise<boolean>;
}

export function linkedManualReasonMessage(label: string, reason: string): string {
  const name = label.trim() || '目标环境';
  if (reason === 'link_access') {
    return '当前环境链接不是完全访问权限，请在「' + name + '」手动获取一次性配对码后连接';
  }
  if (reason === 'version') {
    return '「' + name + '」服务端版本较旧，不支持自动发放配对码，请手动输入配对码连接';
  }
  if (reason === 'refused') {
    return '「' + name + '」拒绝了自动配对，请手动输入一次性配对码连接';
  }
  if (reason === 'unreachable') {
    return '中转环境暂时联系不上「' + name + '」，若本机可直接访问，可手动输入配对码连接';
  }
  return '请确认「' + name + '」地址并输入一次性配对码后连接';
}

export async function prepareLinkedEnvironmentConnection(
  input: PrepareLinkedEnvironmentInput
): Promise<LinkedEnvironmentConnectOutcome> {
  if (input.alreadyConnectedLocalId.trim()) {
    return {
      type: 'already_connected',
      localId: input.alreadyConnectedLocalId.trim(),
      label: input.label
    };
  }
  const pairing = await input.requestPairing();
  if (!pairing) {
    return {
      type: 'prefill',
      localId: '',
      label: input.label,
      prefill: {
        environmentId: input.environmentId,
        label: input.label,
        host: '',
        credential: '',
        manualReason: 'manual'
      }
    };
  }
  const urls = pairing.urls;
  const checks = await Promise.all(urls.map((url: string) => input.reaches(url).catch(() => false)));
  let reachableHost = '';
  for (let i = 0; i < urls.length; i += 1) {
    if (checks[i]) {
      reachableHost = urls[i];
      break;
    }
  }
  if (pairing.type === 'unsupported') {
    return {
      type: 'prefill',
      localId: '',
      label: pairing.label,
      prefill: {
        environmentId: pairing.environmentId,
        label: pairing.label,
        host: reachableHost || (urls.length > 0 ? urls[0] : ''),
        credential: '',
        manualReason: pairing.reason
      }
    };
  }
  if (!reachableHost) {
    return {
      type: 'unreachable',
      localId: '',
      label: pairing.label
    };
  }
  return {
    type: 'prefill',
    localId: '',
    label: pairing.label,
    prefill: {
      environmentId: pairing.environmentId,
      label: pairing.label,
      host: reachableHost,
      credential: pairing.credential,
      manualReason: ''
    }
  };
}
