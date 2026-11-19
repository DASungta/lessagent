// Direct-route classification from the pinned upstream hostClassification.ts.
export function directHostKind(value: string): string {
  const host = value.toLowerCase().replace(/^\[|\]$/g, '').replace(/\.+$/, '');
  const parseIpv4 = (value: string): number[] => {
    const parts = value.split('.').map(Number);
    return parts.length === 4 && parts.every((part: number) => Number.isInteger(part) && part >= 0 && part <= 255) ? parts : [];
  };
  const ipv4 = parseIpv4(host);
  if (host === 'localhost' || host === '::1' || ipv4[0] === 127) return 'loopback';
  if (host.endsWith('.ts.net') || host.startsWith('fd7a:115c:a1e0:')) return 'tailnet';
  if (ipv4[0] === 100 && ipv4[1] >= 64 && ipv4[1] <= 127) return 'vpn';
  let parts = ipv4;
  if (host.startsWith('::ffff:')) {
    const suffix = host.slice(7); parts = parseIpv4(suffix);
    if (!parts.length && /^[\da-f]{1,4}:[\da-f]{1,4}$/.test(suffix)) {
      const tokens = suffix.split(':'); const high = Number.parseInt(tokens[0], 16); const low = Number.parseInt(tokens[1], 16);
      parts = [high >>> 8, high & 255, low >>> 8, low & 255];
    }
  }
  const first = Number.parseInt(host.split(':')[0], 16);
  const privateIpv4 = parts.length === 4 && (parts[0] === 0 || parts[0] === 10 || parts[0] === 127 ||
    (parts[0] === 100 && parts[1] >= 64 && parts[1] <= 127) || (parts[0] === 172 && parts[1] >= 16 && parts[1] <= 31) ||
    (parts[0] === 192 && parts[1] === 168) || (parts[0] === 169 && parts[1] === 254) || (parts[0] === 198 && parts[1] >= 18 && parts[1] <= 19));
  const privateIpv6 = host.includes(':') && Number.isInteger(first) && ((first & 0xfe00) === 0xfc00 || (first & 0xffc0) === 0xfe80);
  return privateIpv4 || privateIpv6 || host === '::' || host.endsWith('.localhost') || host.endsWith('.local') ||
    host === 'home.arpa' || host.endsWith('.home.arpa') || (!host.includes('.') && !host.includes(':')) ? 'lan' : 'public';
}
