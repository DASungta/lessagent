import { connection } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';

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
const MONITOR_RESTART_DELAY_MS = 1000;

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
let restartTimer: number = 0;
let monitorEpoch: number = 0;

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

function readDefaultSnapshot(): NetworkStateSnapshot {
  try {
    const defaultNet = connection.getDefaultNetSync();
    if (defaultNet && defaultNet.netId > 0) {
      return { offline: false, signature: readBearerSignature(defaultNet) };
    }
  } catch (_) {}
  return { offline: false, signature: '' };
}

function applyTransition(next: NetworkStateSnapshot, observer: NetworkObserver): void {
  const transition = classifyNetworkTransition(currentState, next);
  currentState = {
    offline: next.offline,
    signature: next.offline ? '' : (next.signature || currentState.signature)
  };
  try {
    if (transition === 'offline') observer.onOffline();
    else if (transition === 'online') observer.onOnline();
    else if (transition === 'path-changed') observer.onPathChanged();
  } catch (_) {
    // Observer defects must never terminate the background network monitor.
  }
}

function releaseActiveConnection(): void {
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

function scheduleRestart(observer: NetworkObserver, epoch: number, restartDelayMs: number): void {
  if (epoch !== monitorEpoch || restartTimer) return;
  restartTimer = setTimeout(() => {
    restartTimer = 0;
    if (epoch !== monitorEpoch) return;
    attachNetworkMonitor(observer, epoch, restartDelayMs, true);
  }, restartDelayMs) as number;
}

function attachNetworkMonitor(observer: NetworkObserver, epoch: number, restartDelayMs: number,
  isRestart: boolean): void {
  releaseActiveConnection();
  if (epoch !== monitorEpoch) return;
  try {
    const snapshot = readDefaultSnapshot();
    if (isRestart) {
      // A restarted listener may have missed network changes while it was down.
      applyTransition(snapshot, observer);
    } else {
      currentState = snapshot;
    }

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
        if (activeConnection !== netCon || epoch !== monitorEpoch) return;
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
      if (activeConnection !== netCon || epoch !== monitorEpoch) return;
      try {
        clearPendingLost();
        const sig = readBearerSignature(handle);
        applyTransition({ offline: false, signature: sig }, observer);
      } catch (_) {}
    });

    netCon.on('netCapabilitiesChange', (info: connection.NetCapabilityInfo) => {
      if (activeConnection !== netCon || epoch !== monitorEpoch) return;
      try {
        clearPendingLost();
        const bearers: number[] = info.netCap && Array.isArray(info.netCap.bearerTypes)
          ? info.netCap.bearerTypes as number[]
          : [];
        const sig = bearerSignature(bearers);
        applyTransition({ offline: false, signature: sig }, observer);
      } catch (_) {}
    });

    netCon.on('netLost', () => {
      if (activeConnection !== netCon || epoch !== monitorEpoch) return;
      try { scheduleLost(); } catch (_) {}
    });

    netCon.on('netUnavailable', () => {
      if (activeConnection !== netCon || epoch !== monitorEpoch) return;
      try { scheduleLost(); } catch (_) {}
    });

    netCon.register((error: BusinessError) => {
      if (activeConnection !== netCon || epoch !== monitorEpoch) return;
      if (error && error.code !== 0) {
        releaseActiveConnection();
        scheduleRestart(observer, epoch, restartDelayMs);
      }
    });
  } catch (_) {
    releaseActiveConnection();
    scheduleRestart(observer, epoch, restartDelayMs);
  }
}

export function startNetworkMonitor(observer: NetworkObserver,
  restartDelayMs: number = MONITOR_RESTART_DELAY_MS): void {
  stopNetworkMonitor();
  const epoch = monitorEpoch;
  attachNetworkMonitor(observer, epoch, Math.max(10, restartDelayMs), false);
}

export function stopNetworkMonitor(): void {
  monitorEpoch++;
  if (restartTimer) {
    clearTimeout(restartTimer);
    restartTimer = 0;
  }
  releaseActiveConnection();
}
