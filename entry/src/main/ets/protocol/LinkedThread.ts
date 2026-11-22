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
