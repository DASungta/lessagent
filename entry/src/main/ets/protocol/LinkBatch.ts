import { RpcFailure } from './Wire';

export const LINK_BATCH_CONCURRENCY = 4;

export type LinkBatchBlock =
  | 'links_unknown'
  | 'linked'
  | 'not_connected'
  | 'no_access'
  | 'no_address';

export type LinkListState = 'loading' | 'failed' | 'loaded';

export interface LinkBatchMachine {
  localId: string;
  environmentId: string;
  label: string;
  urls: string[];
  connected: boolean;
  linked: boolean;
}

export interface LinkBatchCandidate {
  machine: LinkBatchMachine;
  blocked: LinkBatchBlock | null;
}

export function linkBatchCandidates(
  machines: LinkBatchMachine[],
  writable: Set<string>,
  linksState: LinkListState
): LinkBatchCandidate[] {
  return machines.map((machine: LinkBatchMachine): LinkBatchCandidate => {
    let blocked: LinkBatchBlock | null = null;
    if (linksState !== 'loaded') blocked = 'links_unknown';
    else if (machine.linked) blocked = 'linked';
    else if (!machine.connected) blocked = 'not_connected';
    else if (!writable.has(machine.environmentId)) blocked = 'no_access';
    else if (machine.urls.length === 0) blocked = 'no_address';
    return { machine, blocked };
  });
}

export function linkBatchBlockLabel(blocked: LinkBatchBlock): string {
  if (blocked === 'links_unknown') return '尚未确认是否已链接';
  if (blocked === 'linked') return '已链接';
  if (blocked === 'not_connected') return '当前客户端未连接到此环境';
  if (blocked === 'no_access') return '当前会话无权在此环境生成配对码';
  return '没有其他机器可访问的地址';
}

export type PeerLinkFailureKind = 'unreachable' | 'code_refused' | 'wrong_environment' | 'other';
export type LinkBatchFailure = PeerLinkFailureKind | 'no_code';

export interface LinkBatchOutcome {
  kind: 'linked' | 'failed';
  failure?: LinkBatchFailure;
  detail: string;
}

export function peerLinkFailureKind(error: RpcFailure): PeerLinkFailureKind {
  if (error.answeredAs) return 'wrong_environment';
  if (error.errorReason === 'unreachable' || error.errorReason === 'not_a_t3_environment') return 'unreachable';
  if (error.errorReason === 'pairing_rejected') return 'code_refused';
  return 'other';
}

export function linkBatchFailureLabel(failure: LinkBatchFailure): string {
  if (failure === 'unreachable') return '目标不可达';
  if (failure === 'code_refused') return '配对码被拒绝';
  if (failure === 'wrong_environment') return '响应的环境身份不匹配';
  if (failure === 'no_code') return '无法从该环境生成配对码';
  return '链接失败';
}

/**
 * Only the linking environment's structured PeerLinkError passes its message through;
 * other errors might contain request details and are never echoed.
 */
export function linkBatchFailureFromError(error: Object | undefined): LinkBatchOutcome {
  if (error instanceof RpcFailure && error.errorTag === 'PeerLinkError') {
    return {
      kind: 'failed',
      failure: peerLinkFailureKind(error),
      detail: error.errorMessage || ''
    };
  }
  return { kind: 'failed', failure: 'other', detail: '' };
}

export interface PeerLinkCreateInput {
  url: string;
  alternateUrls?: string[];
  expectedEnvironmentId: string;
  expectedLabel: string;
  pairingCode: string;
  access: string;
}

export interface RunLinkBatchInput {
  machines: LinkBatchMachine[];
  access: string;
  mint: (machine: LinkBatchMachine, access: string) => Promise<string>;
  link: (payload: PeerLinkCreateInput) => Promise<void>;
  refreshLinks: () => void;
  onOutcome?: (environmentId: string, outcome: LinkBatchOutcome) => void;
}

export async function runLinkBatch(input: RunLinkBatchInput): Promise<Map<string, LinkBatchOutcome>> {
  const outcomes: Map<string, LinkBatchOutcome> = new Map();
  const queue: LinkBatchMachine[] = input.machines.slice();

  const linkOne = async (machine: LinkBatchMachine): Promise<LinkBatchOutcome> => {
    if (machine.urls.length === 0) {
      return { kind: 'failed', failure: 'unreachable', detail: '' };
    }
    let code = '';
    try {
      code = await input.mint(machine, input.access);
    } catch (_) {
      return { kind: 'failed', failure: 'no_code', detail: '' };
    }
    if (!code.trim()) {
      return { kind: 'failed', failure: 'no_code', detail: '' };
    }
    const payload: PeerLinkCreateInput = {
      url: machine.urls[0],
      expectedEnvironmentId: machine.environmentId,
      expectedLabel: machine.label,
      pairingCode: code,
      access: input.access
    };
    if (machine.urls.length > 1) {
      payload.alternateUrls = machine.urls.slice(1);
    }
    try {
      await input.link(payload);
      return { kind: 'linked', detail: '' };
    } catch (error) {
      return linkBatchFailureFromError(error as Object);
    }
  };

  const worker = async (): Promise<void> => {
    while (queue.length > 0) {
      const machine = queue.shift();
      if (!machine) break;
      let outcome: LinkBatchOutcome;
      try {
        outcome = await linkOne(machine);
      } catch (_) {
        outcome = { kind: 'failed', failure: 'other', detail: '' };
      }
      outcomes.set(machine.environmentId, outcome);
      if (input.onOutcome) input.onOutcome(machine.environmentId, outcome);
    }
  };

  const workers: Promise<void>[] = [];
  const count = Math.min(LINK_BATCH_CONCURRENCY, Math.max(1, input.machines.length));
  for (let i = 0; i < count; i += 1) {
    workers.push(worker());
  }
  await Promise.all(workers);

  let anyLinked = false;
  outcomes.forEach((outcome: LinkBatchOutcome) => {
    if (outcome.kind === 'linked') anyLinked = true;
  });
  if (anyLinked) input.refreshLinks();
  return outcomes;
}

export interface LinkBatchSummary {
  linked: number;
  failed: string[];
}

export function linkBatchSummary(outcomes: Map<string, LinkBatchOutcome>): LinkBatchSummary {
  const failed: string[] = [];
  let linked = 0;
  outcomes.forEach((outcome: LinkBatchOutcome, envId: string) => {
    if (outcome.kind === 'linked') linked += 1;
    else failed.push(envId);
  });
  return { linked, failed };
}
