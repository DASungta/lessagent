import { url } from '@kit.ArkTS';
import { serverBase } from './Wire';

export interface PairingTarget { base: string; code: string; }

// Fixed upstream: features/connection/pairing.ts and shared/remote.ts (ad1b136).
// Parsing only fills fields; it never grants access or opens a scanned URL.
export function pairingTarget(input: string, code: string = ''): PairingTarget {
  let raw = input.trim();
  if (!raw || raw.length > 16384 || /[\u0000-\u0020\\]/.test(raw)) throw new Error('配对地址无效');
  try {
    let parsed = new url.URL(raw.includes('://') ? raw :
      (/^(\d{1,3}\.){3}\d{1,3}(:\d+)?(\/|$)/.test(raw) || raw.startsWith('[') ? 'http://' : 'https://') + raw);
    if (parsed.protocol === 't3code:') {
      if (parsed.hostname !== 'pair' || (parsed.pathname !== '' && parsed.pathname !== '/')) throw new Error('link');
      raw = parsed.params.get('pairingUrl') || '';
      if (!raw || !/^https?:\/\/|^wss?:\/\//i.test(raw)) throw new Error('link');
      parsed = new url.URL(raw);
    }
    const hash = new url.URLParams(parsed.hash.slice(1));
    const embeddedCode = hash.get('token') || parsed.params.get('token') || '';
    const hosted = parsed.params.get('host');
    if (hosted && embeddedCode) {
      if (/[\u0000-\u0020\\]/.test(hosted)) throw new Error('host');
      parsed = new url.URL(hosted);
    }
    if (parsed.username || parsed.password || !parsed.hostname || /[\u0000-\u0020\\]/.test(raw)) throw new Error('host');
    if (parsed.protocol === 'ws:') parsed.protocol = 'http:';
    if (parsed.protocol === 'wss:') parsed.protocol = 'https:';
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') throw new Error('scheme');
    const explicitCode = code.trim();
    if (explicitCode && embeddedCode && explicitCode !== embeddedCode.trim()) throw new Error('conflict');
    const credential = explicitCode || embeddedCode.trim();
    if (credential.length > 4096 || /[\u0000-\u001f\u007f]/.test(credential)) throw new Error('code');
    return { base: serverBase(parsed.protocol + '//' + parsed.host), code: credential };
  } catch (_) { throw new Error('配对地址或配对码无效，请检查后重试'); }
}
