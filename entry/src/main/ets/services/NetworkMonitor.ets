import { connection } from '@kit.NetworkKit';

export interface NetworkStateSnapshot {
  offline: boolean;
  signature: string;
}

export type NetworkTransition = 'none' | 'offline' | 'online' | 'path-changed';

export interface NetworkObserver {
  onOffline: () => void;
  onOnline: () => void;
  onPathChanged: () => void;
}

const NET_LOST_DEBOUNCE_MS = 600;

export function bearerSignature(bearerTypes: number[]): string {
  const unique: number[] = [];
  for (const bearer of bearerTypes) {
    if (typeof bearer === 'number' && Number.isFinite(bearer) && !unique.includes(bearer)) {
      unique.push(bearer);
    }
  }
  unique.sort((a: number, b: number) => a - b);
  return unique.join(',');
}

export function classifyNetworkTransition(
  prev: NetworkStateSnapshot,
  next: NetworkStateSnapshot
): NetworkTransition {
  if (next.offline) {
    return prev.offline ? 'none' : 'offline';
  }
  if (prev.offline) {
    return 'online';
  }
  if (prev.signature && next.signature && prev.signature !== next.signature) {
    return 'path-changed';
  }
  return 'none';
}

let activeConnection: connection.NetConnection | undefined = undefined;
let currentState: NetworkStateSnapshot = { offline: false, signature: '' };
let lostTimer: number = 0;

function readBearerSignature(handle: connection.NetHandle | undefined): string {
  if (!handle || handle.netId <= 0) return '';
  try {
    const caps = connection.getNetCapabilitiesSync(handle);
    if (caps && Array.isArray(caps.bearerTypes)) {
      return bearerSignature(caps.bearerTypes as number[]);
    }
  } catch (_) {}
  return '';
}

function applyTransition(next: NetworkStateSnapshot, observer: NetworkObserver): void {
  const transition = classifyNetworkTransition(currentState, next);
  currentState = {
    offline: next.offline,
    signature: next.offline ? '' : (next.signature || currentState.signature)
  };
  if (transition === 'offline') observer.onOffline();
  else if (transition === 'online') observer.onOnline();
  else if (transition === 'path-changed') observer.onPathChanged();
}

export function startNetworkMonitor(observer: NetworkObserver): void {
  stopNetworkMonitor();
  try {
    let initialSignature = '';
    try {
      const defaultNet = connection.getDefaultNetSync();
      initialSignature = readBearerSignature(defaultNet);
    } catch (_) {}
    currentState = { offline: false, signature: initialSignature };

    const netCon = connection.createNetConnection();
    activeConnection = netCon;

    const clearPendingLost = (): void => {
      if (lostTimer) {
        clearTimeout(lostTimer);
        lostTimer = 0;
      }
    };

    const scheduleLost = (): void => {
      clearPendingLost();
      lostTimer = setTimeout(() => {
        lostTimer = 0;
        if (activeConnection !== netCon) return;
        try {
          const defaultNet = connection.getDefaultNetSync();
          if (defaultNet && defaultNet.netId > 0) {
            const sig = readBearerSignature(defaultNet);
            if (sig) {
              applyTransition({ offline: false, signature: sig }, observer);
              return;
            }
          }
        } catch (_) {}
        applyTransition({ offline: true, signature: '' }, observer);
      }, NET_LOST_DEBOUNCE_MS) as number;
    };

    netCon.on('netAvailable', (handle: connection.NetHandle) => {
      if (activeConnection !== netCon) return;
      clearPendingLost();
      const sig = readBearerSignature(handle);
      applyTransition({ offline: false, signature: sig }, observer);
    });

    netCon.on('netCapabilitiesChange', (info: connection.NetCapabilityInfo) => {
      if (activeConnection !== netCon) return;
      clearPendingLost();
      const bearers: number[] = info.netCap && Array.isArray(info.netCap.bearerTypes)
        ? info.netCap.bearerTypes as number[]
        : [];
      const sig = bearerSignature(bearers);
      applyTransition({ offline: false, signature: sig }, observer);
    });

    netCon.on('netLost', () => {
      if (activeConnection !== netCon) return;
      scheduleLost();
    });

    netCon.on('netUnavailable', () => {
      if (activeConnection !== netCon) return;
      scheduleLost();
    });

    netCon.register(() => {});
  } catch (_) {}
}

export function stopNetworkMonitor(): void {
  if (lostTimer) {
    clearTimeout(lostTimer);
    lostTimer = 0;
  }
  const existing = activeConnection;
  activeConnection = undefined;
  if (existing) {
    try { existing.unregister(() => {}); } catch (_) {}
  }
}
