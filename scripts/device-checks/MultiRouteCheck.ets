import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo } from '@kit.CoreFileKit';
import { DirectRoute, EnvironmentAssets, environmentRoutes } from '../protocol/Environment';
import { PairingTarget } from '../protocol/Pairing';
import { SavedSession, RecoveryState } from '../protocol/Core';
import { EnvironmentRegistry } from '../services/EnvironmentRegistry';
import { T3Client } from '../services/T3Client';
import { SessionStore } from '../storage/SessionStore';
interface Fixture { primary: PairingTarget; alternate: PairingTarget; foreign: PairingTarget; threadId: string; }
class TestAssets implements EnvironmentAssets {
  session(alias: string): SessionStore<SavedSession> { return new SessionStore<SavedSession>('r1-routes-' + alias); }
  recovery(alias: string): SessionStore<RecoveryState> { return new SessionStore<RecoveryState>('r1-routes-' + alias); }
}
function ensure(value: boolean): void { if (!value) throw new Error('multi-route device assertion failed'); }
@Entry
@Component
struct MultiRouteCheck {
  @State report: string = 'Multi-route checks running';
  private stage: string = 'start';
  aboutToAppear(): void {
    void this.run().catch((error: Error) => {
      this.report = 'FAIL at ' + this.stage;
      hilog.error(0x0000, 'R1MultiRouteCheck', 'FAIL at %{public}s: %{public}s', this.stage, error.message);
    });
  }
  private synchronized(connection: T3Client): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      const previous = connection.onUpdate;
      const timer = setTimeout(() => { connection.onUpdate = previous; reject(new Error('snapshot not received')); }, 10000);
      connection.onUpdate = () => {
        previous();
        if (connection.thread && connection.thread.cursor >= 0) {
          clearTimeout(timer); connection.onUpdate = previous; resolve();
        }
      };
      connection.onUpdate();
    });
  }
  private async run(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const appFiles = context.getApplicationContext().filesDir;
    const input = appFiles + '/r1-routes.json';
    const fixture = JSON.parse(fileIo.readTextSync(input)) as Fixture;
    fileIo.unlinkSync(input);
    const root = context.filesDir + '/r1-multi-route-check';
    if (!fileIo.accessSync(root)) fileIo.mkdirSync(root);
    const legacy = new SessionStore<SavedSession>('r1-routes-legacy');
    const legacyRecovery = new SessionStore<RecoveryState>('r1-routes-legacy-recovery');
    const registry = new EnvironmentRegistry(root, new TestAssets(), legacy, legacyRecovery);
    this.stage = 'primary-pair';
    await registry.initialize();
    for (const old of registry.directory.entries.slice()) {
      ensure(old.base === fixture.primary.base || old.base === fixture.alternate.base);
      for (const reference of old.recovery) {
        const value = await registry.assets.recovery(reference.alias).load();
        ensure(!!value && (value.pendingId === '' || value.pendingId === 'r1-routes-synthetic-unknown'));
        if (value?.pendingId) {
          await registry.saveRecovery(old.localId, { base: value.base, environmentId: value.environmentId,
            threadId: value.threadId, pendingId: '', pendingKind: '' });
        }
      }
      await registry.remove(old.localId);
    }
    ensure(registry.directory.entries.length === 0);
    const localId = await registry.add(fixture.primary.base, fixture.primary.code);
    const client = registry.clients.get(localId);
    ensure(!!client && client.ready && environmentRoutes(registry.entry(localId)).length === 1);
    if (!client) throw new Error('missing client');
    const primaryRef = registry.entry(localId).credentialRef;
    const pending: RecoveryState = { base: fixture.primary.base, environmentId: registry.entry(localId).environmentId,
      threadId: fixture.threadId, pendingId: 'r1-routes-synthetic-unknown', pendingKind: 'message' };
    await registry.saveRecovery(localId, pending);
    await registry.setPullRequestRouting(localId, 'read');
    this.stage = 'alternate-pair';
    await registry.addRoute(localId, fixture.alternate.base, fixture.alternate.code);
    let entry = registry.entry(localId);
    ensure(environmentRoutes(entry).length === 2 && entry.alternateRoutes?.length === 1);
    if (!entry.alternateRoutes) throw new Error('missing alternate');
    const alternateRef = entry.alternateRoutes[0].credentialRef;
    ensure(alternateRef !== primaryRef && entry.prRouting === undefined);
    ensure(registry.clients.get(localId) === client && client.ready && client.connectedBase === fixture.primary.base);
    ensure(JSON.stringify(await registry.assets.recovery(entry.recovery[0].alias).load()) === JSON.stringify(pending));
    const primarySession = await registry.assets.session(primaryRef).load();
    const alternateSession = await registry.assets.session(alternateRef).load();
    ensure(!!primarySession && primarySession.base === fixture.primary.base);
    ensure(!!alternateSession && alternateSession.base === fixture.alternate.base);
    this.stage = 'identity-before-foreign-code';
    const before = JSON.stringify(registry.directory);
    let foreignRejected = false;
    try { await registry.addRoute(localId, fixture.foreign.base, fixture.foreign.code); }
    catch (error) { foreignRejected = String((error as Error).message).includes('身份已变化'); }
    ensure(foreignRejected && JSON.stringify(registry.directory) === before);
    this.stage = 'reorder-and-reconnect';
    await registry.reorderRoutes(localId, [alternateRef, primaryRef]);
    entry = registry.entry(localId);
    ensure(entry.base === fixture.alternate.base && entry.recoveryBase === fixture.primary.base);
    ensure(JSON.stringify(await registry.assets.recovery(entry.recovery[0].alias).load()) === JSON.stringify(pending));
    await registry.reconnect(localId);
    ensure(client.ready && client.connectedBase === fixture.alternate.base && client.recoveryBase === fixture.primary.base);
    await registry.setPullRequestRouting(localId, 'read');
    await registry.reorderRoutes(localId, [primaryRef, alternateRef]);
    ensure(registry.entry(localId).prRouting === 'read');
    await registry.reconnect(localId);
    ensure(client.connectedBase === fixture.primary.base);
    this.stage = 'remove-active-route-switch';
    await registry.removeRoute(localId, primaryRef);
    entry = registry.entry(localId);
    ensure(environmentRoutes(entry).length === 1 && entry.base === fixture.alternate.base);
    ensure(client.ready && client.connectedBase === fixture.alternate.base);
    ensure(await registry.assets.session(primaryRef).load() === undefined);
    ensure(JSON.stringify(await registry.assets.recovery(entry.recovery[0].alias).load()) === JSON.stringify(pending));
    this.stage = 'controlled-unknown-sync';
    await this.synchronized(client);
    this.stage = 'controlled-unknown-ack';
    await client.acknowledgeUnknown();
    this.stage = 'controlled-last-route-remove';
    await registry.removeRoute(localId, alternateRef);
    ensure(registry.directory.entries.length === 0 && registry.clients.size === 0);
    ensure(await registry.assets.session(alternateRef).load() === undefined);
    fileIo.unlinkSync(root + '/environments-v2.json'); fileIo.rmdirSync(root);
    const output = fileIo.openSync(appFiles + '/r1-routes-result.json', fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(output.fd, JSON.stringify({ passed: 6, failed: 0, primaryBase: fixture.primary.base,
        alternateBase: fixture.alternate.base, foreignCodeExchanged: false, unknownRecoveryPreserved: true,
        recoveryAnchoredToOriginalBase: true, activeRouteRemovalReconnected: true,
        productDirectoryTouched: false, messagesSent: 0 }));
      fileIo.fsyncSync(output.fd);
    } finally { fileIo.closeSync(output); }
    this.report = '6 multi-route checks passed';
    hilog.info(0x0000, 'R1MultiRouteCheck', 'DONE passed=6 failed=0');
  }
  build() {
    Column({ space: 20 }) { Text('R1 isolated multi-route checks').fontSize(22); Text(this.report).fontSize(18) }
      .width('100%').height('100%').justifyContent(FlexAlign.Center).padding(24)
  }
}
