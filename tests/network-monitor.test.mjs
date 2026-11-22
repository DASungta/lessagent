import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { compile, data } from './load-core.mjs';

const raw = await readFile(new URL('../entry/src/main/ets/services/NetworkMonitor.ets', import.meta.url), 'utf8');
const stripped = raw.replace("import { connection } from '@kit.NetworkKit';", 'const connection = globalThis.__netKit;');
const { bearerSignature, classifyNetworkTransition } = await import(data(compile(stripped)));

test('bearerSignature deduplicates and sorts bearer types deterministically', () => {
  assert.equal(bearerSignature([4, 1, 1]), '1,4');
  assert.equal(bearerSignature([0]), '0');
  assert.equal(bearerSignature([]), '');
});

test('classifyNetworkTransition distinguishes offline, online recovery, and bearer/VPN path changes', () => {
  const wifi = { offline: false, signature: '1' };
  const wifiVpn = { offline: false, signature: '1,4' };
  const cellular = { offline: false, signature: '0' };
  const offline = { offline: true, signature: '' };

  assert.equal(classifyNetworkTransition(wifi, wifi), 'none');
  assert.equal(classifyNetworkTransition(wifi, wifiVpn), 'path-changed');
  assert.equal(classifyNetworkTransition(wifi, cellular), 'path-changed');
  assert.equal(classifyNetworkTransition(wifi, offline), 'offline');
  assert.equal(classifyNetworkTransition(offline, offline), 'none');
  assert.equal(classifyNetworkTransition(offline, cellular), 'online');
  assert.equal(classifyNetworkTransition({ offline: false, signature: '' }, wifi), 'none');
});
