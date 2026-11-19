import { url } from '@kit.ArkTS';
import { LinkRequestView } from './Core';
import { pairingTarget } from './Pairing';
export interface LinkMachine { localId: string; environmentId: string; label: string; urls: string[]; connected: boolean; linked: boolean; }
export interface LinkTarget { kind: string; localId: string; environmentId: string; label: string; urls: string[]; linked: boolean; }
export function linkOrigin(value: string): string {
  try { if (!/^https?:\/\//i.test(value)) return ''; return pairingTarget(value).base; } catch (_) { return ''; }
}
export function linkReachableAddresses(values: string[]): string[] {
  const addresses: string[] = [];
  for (const value of values) {
    const base = linkOrigin(value); if (!base) continue;
    const host = new url.URL(base).hostname.toLowerCase().replace(/^\[|\]$/g, '').replace(/\.+$/, '');
    if (host === 'localhost' || host === '::1' || /^127\.\d+\.\d+\.\d+$/.test(host)) continue;
    if (!addresses.includes(base)) addresses.push(base);
  }
  return addresses;
}
function hintRank(label: string, hint: string): number {
  const name = label.trim().toLowerCase(); const wanted = hint.trim().toLowerCase().replace(/^(?:my|our|the)\s+/, '');
  if (!wanted) return 4;
  if (name === wanted) return 0; if (name.startsWith(wanted)) return 1; if (name.includes(wanted)) return 2;
  const words = (value: string): string => ' ' + value.toLowerCase().split(/[^\p{L}\p{N}]+/u).join(' ').trim() + ' ';
  return words(wanted).includes(words(name)) ? 3 : 4;
}
export function initialLinkMachine(item: LinkRequestView, machines: LinkMachine[]): string {
  if (item.environmentId && !item.url) return item.environmentId;
  if (!item.hint.trim()) return '';
  let selected = ''; let best = 4;
  for (const machine of machines) { const rank = hintRank(machine.label, item.hint); if (rank < best) { best = rank; selected = machine.environmentId; } }
  return selected;
}
export function resolveLinkTarget(item: LinkRequestView, machines: LinkMachine[], choice: string): LinkTarget {
  let selected = item.environmentId || choice;
  if (item.url) {
    const origin = linkOrigin(item.url);
    const matches = origin ? machines.filter((machine: LinkMachine) => machine.urls.some((base: string) => linkOrigin(base) === origin)) : [];
    // An agent's claimed identity never makes an unknown or ambiguous address trusted.
    selected = matches.length === 1 ? matches[0].environmentId : 'another-address';
  }
  if (!selected) return { kind: 'none', localId: '', environmentId: '', label: '', urls: [], linked: false };
  if (selected === 'another-address') return { kind: 'address', localId: '', environmentId: '', label: linkOrigin(item.url) || '另一地址', urls: [], linked: false };
  const machine = machines.find((candidate: LinkMachine) => candidate.environmentId === selected);
  return { kind: 'machine', localId: machine?.localId || '', environmentId: selected, label: machine?.label || '该环境', urls: machine?.urls || [], linked: machine?.linked || false };
}
