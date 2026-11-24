const serverClockOffsets: Map<string, number> = new Map();

export function recordServerClock(
  environmentId: string,
  serverTimeIso: string | undefined,
  sentAtMs: number,
  receivedAtMs: number
): void {
  const envId = (environmentId || '').trim();
  if (!envId || !serverTimeIso) return;
  const serverMs = Date.parse(serverTimeIso);
  if (!Number.isFinite(serverMs) || !Number.isFinite(sentAtMs) || !Number.isFinite(receivedAtMs)) {
    return;
  }
  const midpoint = sentAtMs + (receivedAtMs - sentAtMs) / 2;
  serverClockOffsets.set(envId, serverMs - midpoint);
}

/**
 * Raises a stale negative clock offset when a server-stamped timestamp is ahead
 * of the estimated server clock (e.g. after VM/WSL or host sleep catch-up).
 */
export function observeServerTime(
  environmentId: string,
  serverTimeMs: number,
  receivedAtMs: number = Date.now()
): void {
  const envId = (environmentId || '').trim();
  if (!envId) return;
  const currentOffset = serverClockOffsets.get(envId);
  if (currentOffset === undefined || !Number.isFinite(serverTimeMs) || !Number.isFinite(receivedAtMs)) {
    return;
  }
  if (receivedAtMs + currentOffset >= serverTimeMs) return;
  serverClockOffsets.set(envId, serverTimeMs - receivedAtMs);
}

export function observeServerIsoTime(
  environmentId: string,
  isoTime: string | undefined,
  receivedAtMs: number = Date.now()
): void {
  if (!isoTime) return;
  const ms = Date.parse(isoTime);
  if (Number.isFinite(ms)) {
    observeServerTime(environmentId, ms, receivedAtMs);
  }
}

export function serverClockOffset(environmentId: string): number {
  const envId = (environmentId || '').trim();
  if (!envId) return 0;
  return serverClockOffsets.get(envId) ?? 0;
}

export function toServerClock(environmentId: string, clientMs: number): number {
  return clientMs + serverClockOffset(environmentId);
}

export function fromServerClock(environmentId: string, serverMs: number): number {
  return serverMs - serverClockOffset(environmentId);
}

export function serverNowMs(environmentId: string, clientNowMs: number = Date.now()): number {
  return toServerClock(environmentId, clientNowMs);
}

export function clearServerClock(environmentId: string): void {
  const envId = (environmentId || '').trim();
  if (envId) serverClockOffsets.delete(envId);
}

export function resetAllServerClocks(): void {
  serverClockOffsets.clear();
}
