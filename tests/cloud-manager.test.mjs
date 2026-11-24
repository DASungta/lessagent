import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { cloudUrl } from './load-cloud.mjs';
import { compile, data } from './load-core.mjs';
const cloud = await import(cloudUrl);

const officialKey = 'pk_live_Y2xlcmsudDMuY29kZXMk';
const customKey = 'pk_test_' + Buffer.from('clerk.custom.test$').toString('base64');

async function loadManager(options = {}) {
  const files = new Map();
  const storage = new Map();
  let thumbprintCounter = 1;
  let activeAccount = '';
  let activeFactory = undefined;
  let removedAccounts = [];
  let relayCleared = 0;
  let envTokensCleared = [];
  let signOutCalls = 0;
  let relayEnvList = options.environments || [{
    environmentId: 'env-1',
    label: 'Mac Studio',
    endpoint: { httpBaseUrl: 'https://env-1.t3.codes', wsBaseUrl: 'wss://env-1.t3.codes/', providerKind: 'cloudflare_tunnel' },
    linkedAt: Date.parse('2026-01-01T00:00:00Z')
  }];
  let refreshError = options.refreshError;
  const entries = options.entries ? structuredClone(options.entries) : [];

  const registry = {
    directory: { entries },
    clients: new Map(),
    async initialize() {},
    async setCloudAccount(accountId, factory) {
      activeAccount = accountId;
      activeFactory = factory;
    },
    async removeCloudAccount(accountId) {
      removedAccounts.push(accountId);
      for (let i = entries.length - 1; i >= 0; i--) {
        if (entries[i].kind === 'cloud' && entries[i].cloudAccountId === accountId) entries.splice(i, 1);
      }
    },
    findEnvironment(id) { return entries.find(e => e.environmentId === id); },
    findEnvironmentOfKind(id, kind) { return entries.find(e => e.environmentId === id && e.kind === kind); },
    async addCloud(environmentId, label, base, accountId) {
      const localId = 'cloud-' + environmentId;
      entries.push({ localId, environmentId, label, base, enabled: true, kind: 'cloud', cloudAccountId: accountId });
      return localId;
    },
    async syncCloudEndpoint() {},
    async reconnect() {}
  };

  class FakeAuth {
    constructor(cfg) {
      this.config = cfg;
      this.session = undefined;
      this.activeAttempt = undefined;
      this.pendingSsoStrategy = '';
      this.status = '未登录';
    }
    async fetchEnvironment() { return cloud.defaultClerkEnvironment(); }
    async restore() { return options.restoredSession; }
    async startEmailSignIn(email) {
      if (options.directComplete) {
        return {
          kind: 'complete',
          session: {
            version: 2, accountId: 'user-alice', sessionId: 'sess-1', clientToken: 'tok-1',
            email, displayName: 'Alice', publishableKey: this.config.clerk.publishableKey,
            relayUrl: this.config.relay.url, jwtTemplate: this.config.clerk.jwtTemplate,
            redirectUri: this.config.clerk.redirectUri
          },
          attempt: undefined
        };
      }
      this.activeAttempt = {
        id: 'sia_1', status: 'needs_first_factor', identifier: email, createdSessionId: '',
        firstFactorStatus: '', firstFactorStrategy: '', firstFactorError: '', externalRedirectUrl: '',
        supportedFirstFactors: [{ strategy: 'email_code', emailAddressId: 'em_1', safeIdentifier: email }],
        supportedSecondFactors: []
      };
      this.status = '请选择验证方式完成登录';
      return { kind: 'needs_first_factor', session: undefined, attempt: this.activeAttempt };
    }
    async verifyEmailCode() {
      this.activeAttempt = undefined;
      return {
        kind: 'complete',
        session: {
          version: 2, accountId: 'user-alice', sessionId: 'sess-1', clientToken: 'tok-1',
          email: 'alice@example.test', displayName: 'Alice', publishableKey: this.config.clerk.publishableKey,
          relayUrl: this.config.relay.url, jwtTemplate: this.config.clerk.jwtTemplate,
          redirectUri: this.config.clerk.redirectUri
        },
        attempt: undefined
      };
    }
    async getRelayToken() { return 'MINTED_JWT'; }
    async persist(session) { this.session = session; }
    async clear(revoke) { if (revoke) signOutCalls++; this.session = undefined; this.activeAttempt = undefined; this.status = '未登录'; }
    async cancelPending() { this.activeAttempt = undefined; this.pendingSsoStrategy = ''; this.status = '登录已取消'; }
  }

  class FakeRelay {
    constructor(cfg, accountId, readToken) { this.relayUrl = cfg.relay.url; this.accountId = accountId; this.readToken = readToken; }
    async listEnvironments() {
      if (refreshError) throw refreshError;
      return relayEnvList;
    }
    async status(env) {
      return { environmentId: env.environmentId, endpoint: env.endpoint, status: 'online', checkedAt: Date.now(), error: '', traceId: '', offlineReason: '', descriptorEnvironmentId: env.environmentId };
    }
  }

  const signer = {
    async thumbprint() { return 'Key' + thumbprintCounter + 'ThumbABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890'; },
    async reset() { thumbprintCounter++; }
  };

  class FakeOverrideStore {
    constructor() {}
    load() { return files.get('override'); }
    save(v) { const checked = cloud.parseCloudConfigOverride(v); files.set('override', checked); return checked; }
    clear() { files.delete('override'); }
  }
  class FakeOnboardingStore {
    constructor() { this.opted = new Set(); }
    isOptedOut(id) { return this.opted.has(id); }
    optOut(id) { this.opted.add(id); }
  }

  globalThis.__cloudMgr = {
    common: {},
    fileIo: {
      OpenMode: { CREATE: 1, READ_WRITE: 2, TRUNC: 4 },
      readTextSync: (p) => { if (!files.has(p)) throw new Error('enoent'); return files.get(p); },
      openSync: (p) => ({ fd: p }),
      writeSync: (fd, v) => { files.set(fd, v); },
      fsyncSync: () => {},
      closeSync: () => {}
    },
    url: { URL },
    util: { generateRandomUUID: () => '11111111-1111-4111-8111-111111111111', TextDecoder },
    environments: registry,
    CloudAuth: FakeAuth,
    CloudRelay: FakeRelay,
    CloudEnvironmentTransport: class { constructor(envId) { this.environmentId = envId; } },
    dpopSigner: signer,
    DpopSigner: Object,
    CloudEnvironmentTokenStore: class { async clear(id) { envTokensCleared.push(id); } },
    RelayTokenStore: class { async clear() { relayCleared++; } },
    CloudConfigOverrideStore: FakeOverrideStore,
    CloudOnboardingStore: FakeOnboardingStore,
    AppStorage: {
      get: (k) => storage.get(k),
      setOrCreate: (k, v) => storage.set(k, v)
    }
  };
  globalThis.AppStorage = globalThis.__cloudMgr.AppStorage;

  const source = (await readFile(new URL('../entry/src/main/ets/services/CloudManager.ets', import.meta.url), 'utf8'))
    .replace("import { common } from '@kit.AbilityKit';", 'const { common } = globalThis.__cloudMgr;')
    .replace("import { fileIo } from '@kit.CoreFileKit';", 'const { fileIo } = globalThis.__cloudMgr;')
    .replace("import { url, util } from '@kit.ArkTS';", 'const { url, util } = globalThis.__cloudMgr;')
    .replace("from '../protocol/Cloud';", 'from ' + JSON.stringify(cloudUrl) + ';')
    .replace("import { EnvironmentEntry } from '../protocol/Environment';", '')
    .replace("import { environments } from './EnvironmentRegistry';", 'const { environments } = globalThis.__cloudMgr;')
    .replace("import { CloudEnvironmentTokenStore, RelayTokenStore } from '../storage/CloudStores';",
      'const { CloudEnvironmentTokenStore, RelayTokenStore } = globalThis.__cloudMgr;')
    .replace("import { CloudConfigOverrideStore, CloudOnboardingStore } from '../storage/CloudPrefsStore';",
      'const { CloudConfigOverrideStore, CloudOnboardingStore } = globalThis.__cloudMgr;')
    .replace("import { CloudAuth, CloudSignInResult } from './CloudAuth';", 'const { CloudAuth } = globalThis.__cloudMgr;')
    .replace("import { CloudRelay } from './CloudRelay';", 'const { CloudRelay } = globalThis.__cloudMgr;')
    .replace("import { CloudEnvironmentTransport } from './CloudConnection';", 'const { CloudEnvironmentTransport } = globalThis.__cloudMgr;')
    .replace("import { DpopSigner, dpopSigner } from './Dpop';", 'const { DpopSigner, dpopSigner } = globalThis.__cloudMgr;');

  const mod = await import(data(compile(source) + '\n//' + Math.random()));
  const manager = new mod.CloudManager(cloud.OFFICIAL_CLOUD_CONFIG, '', '/synthetic');
  return {
    manager,
    getActiveAccount: () => activeAccount,
    getRemovedAccounts: () => removedAccounts,
    getRelayCleared: () => relayCleared,
    getEnvTokensCleared: () => envTokensCleared,
    getSignOutCalls: () => signOutCalls,
    setRefreshError: (err) => { refreshError = err; }
  };
}

test('CloudManager computes device code, completes sign-in with onboarding opt-out, and switches custom deployment cleanly', async () => {
  const ctx = await loadManager();
  await ctx.manager.initialize();
  assert.equal(ctx.manager.configured, true);
  assert.equal(ctx.manager.isCustomConfig, false);
  assert.match(ctx.manager.deviceCode, /^[A-Z2-9]{4}-[A-Z2-9]{4}$/);

  const first = await ctx.manager.startEmailSignIn('alice@example.test');
  assert.equal(first.kind, 'needs_first_factor');
  assert.equal(ctx.manager.signedIn, false);

  const done = await ctx.manager.verifyEmailCode('123456');
  assert.equal(done.kind, 'complete');
  assert.equal(ctx.manager.signedIn, true);
  assert.equal(ctx.manager.showOnboarding, true);
  assert.equal(ctx.manager.environments.length, 1);
  assert.equal(ctx.manager.environments[0].providerKind, 'cloudflare_tunnel');
  assert.equal(ctx.getActiveAccount(), 'user-alice');

  // Dismiss with opt-out persists across future sign-ins.
  ctx.manager.dismissOnboarding(true);
  assert.equal(ctx.manager.showOnboarding, false);

  // Connecting a discovered server adds it to the directory and resets cleanly on device key rotation.
  const localId = await ctx.manager.connectEnvironment('env-1');
  assert.equal(localId, 'cloud-env-1');
  const codeBefore = ctx.manager.deviceCode;
  await ctx.manager.resetDeviceKey();
  assert.notEqual(ctx.manager.deviceCode, codeBefore);
  assert.ok(ctx.getEnvTokensCleared().includes('env-1'));

  // Saving a custom deployment while signed in signs out first, switches config, and marks isCustomConfig.
  await ctx.manager.saveConfigOverride(customKey, 'custom-tpl', 'https://custom.relay.test');
  assert.equal(ctx.manager.signedIn, false);
  assert.equal(ctx.manager.isCustomConfig, true);
  assert.equal(ctx.manager.config.relay.url, 'https://custom.relay.test');
  assert.equal(ctx.manager.config.clerk.jwtTemplate, 'custom-tpl');
  assert.equal(ctx.getSignOutCalls(), 1);
  assert.ok(ctx.getRemovedAccounts().includes('user-alice'));

  // Resetting returns to official defaults.
  await ctx.manager.resetConfigOverride();
  assert.equal(ctx.manager.isCustomConfig, false);
  assert.equal(ctx.manager.config.relay.url, 'https://relay.t3.codes');
  assert.equal(ctx.manager.config.clerk.publishableKey, officialKey);
});

test('CloudManager deactivates session cleanly when refresh receives CloudSessionExpiredError', async () => {
  const ctx = await loadManager({ directComplete: true });
  await ctx.manager.initialize();
  await ctx.manager.startEmailSignIn('alice@example.test');
  assert.equal(ctx.manager.signedIn, true);

  ctx.setRefreshError(new cloud.CloudSessionExpiredError('T3 Connect 登录已过期，请重新登录'));
  await ctx.manager.refresh();
  assert.equal(ctx.manager.signedIn, false);
  assert.equal(ctx.getActiveAccount(), '');
  assert.match(ctx.manager.error, /登录已过期/);
});
