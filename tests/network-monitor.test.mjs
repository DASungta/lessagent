import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { compile, data } from './load-core.mjs';

const raw = await readFile(new URL('../entry/src/main/ets/services/NetworkMonitor.ets', import.meta.url), 'utf8');
const stripped = raw
  .replace("import { connection } from '@kit.NetworkKit';", 'const connection = new Proxy({}, { get: (_, k) => globalThis.__netKit?.[k] });')
  .replace("import { BusinessError } from '@kit.BasicServicesKit';", '');
const { bearerSignature, classifyNetworkTransition, startNetworkMonitor, stopNetworkMonitor } = await import(data(compile(stripped)));

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

test('C3: NetworkMonitor survives observer exceptions and restarts after startup or registration defects', async () => {
  let createCalls = 0;
  let currentBearers = [1];
  let latestListeners = {};
  let unregisterCalls = 0;

  globalThis.__netKit = {
    getDefaultNetSync: () => ({ netId: 10 }),
    getNetCapabilitiesSync: () => ({ bearerTypes: currentBearers }),
    createNetConnection: () => {
      createCalls++;
      if (createCalls === 1) throw new Error('transient netkit failure');
      const listeners = {};
      latestListeners = listeners;
      return {
        on: (event, cb) => { listeners[event] = cb; },
        register: (cb) => {
          if (createCalls === 2) {
            // Simulate network switching to VPN while listener was failing registration
            currentBearers = [1, 4];
            queueMicrotask(() => cb({ code: 2100001 }));
          } else {
            queueMicrotask(() => cb({ code: 0 }));
          }
        },
        unregister: () => { unregisterCalls++; }
      };
    }
  };

  const events = [];
  let throwOnce = true;
  try {
    startNetworkMonitor({
      onOffline: () => { events.push('offline'); },
      onOnline: () => { events.push('online'); },
      onPathChanged: () => {
        events.push('path-changed');
        if (throwOnce) {
          throwOnce = false;
          throw new Error('unexpected observer defect');
        }
      }
    }, 15);

    // Wait for create failure -> restart 1 (register error) -> restart 2 (succeeds & reconciles missed change)
    await new Promise((r) => setTimeout(r, 90));
    assert.equal(createCalls, 3, 'monitor must restart after both startup throw and register failure');
    assert.ok(unregisterCalls >= 1);
    assert.deepEqual(events, ['path-changed'], 'restarted monitor must reconcile missed bearer change');

    // Even though the first onPathChanged threw, subsequent events must keep working
    latestListeners.netCapabilitiesChange({ netCap: { bearerTypes: [0] } });
    assert.deepEqual(events, ['path-changed', 'path-changed']);
  } finally {
    stopNetworkMonitor();
  }
});
