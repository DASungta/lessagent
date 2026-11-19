import { pairingTarget, PairingTarget } from '../protocol/Pairing';

let pending: PairingTarget | undefined = undefined;
// Want payloads are untrusted: only prefill a form, never connect or persist the code.
export function acceptPairingLink(uri: string): void {
  if (!uri) return;
  try {
    if (!/^t3code:\/\/pair(?:[/?]|$)/i.test(uri)) throw new Error('link');
    pending = pairingTarget(uri);
    AppStorage.setOrCreate('t3PairingError', '');
  } catch (_) {
    pending = undefined;
    AppStorage.setOrCreate('t3PairingError', '配对链接无效，请检查后重新打开');
  }
  AppStorage.setOrCreate('t3PairingRevision', (AppStorage.get<number>('t3PairingRevision') || 0) + 1);
}
export function takePairingLink(): PairingTarget | undefined {
  const target = pending; pending = undefined; return target;
}
