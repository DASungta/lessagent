import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo } from '@kit.CoreFileKit';
import { EnvironmentAssets } from '../protocol/Environment';
import { PairingTarget } from '../protocol/Pairing';
import { SavedSession, RecoveryState } from '../protocol/Core';
import { EnvironmentRegistry } from '../services/EnvironmentRegistry';
import { SessionStore } from '../storage/SessionStore';
interface Fixture { a: PairingTarget; b: PairingTarget; }
class TestAssets implements EnvironmentAssets {
  session(alias: string): SessionStore<SavedSession> { return new SessionStore<SavedSession>('r1-reg-' + alias); }
  recovery(alias: string): SessionStore<RecoveryState> { return new SessionStore<RecoveryState>('r1-reg-' + alias); }
}
function ensure(value: boolean): void { if (!value) throw new Error('device registry assertion failed'); }
@Entry
@Component
struct RegistryCheck {
  @State report: string = 'Registry checks running';
  aboutToAppear(): void { void this.run().catch((error: Error) => { this.report = 'FAIL'; hilog.error(0x0000, 'R1RegistryCheck', 'FAIL %{public}s', error.message); }); }
  private async run(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const fixturePath = context.getApplicationContext().filesDir + '/r1-network.json';
    const fixture = JSON.parse(fileIo.readTextSync(fixturePath)) as Fixture;
    fileIo.unlinkSync(fixturePath);
    const root = context.filesDir + '/r1-registry-check';
    if (!fileIo.accessSync(root)) fileIo.mkdirSync(root);
    const legacy = new SessionStore<SavedSession>('r1-reg-legacy');
    const legacyRecovery = new SessionStore<RecoveryState>('r1-reg-legacy-recovery');
    const registry = new EnvironmentRegistry(root, new TestAssets(), legacy, legacyRecovery);
    await registry.initialize();
    ensure(registry.directory.entries.length === 0);
    const a = await registry.add(fixture.a.base, fixture.a.code);
    const b = await registry.add(fixture.b.base, fixture.b.code);
    ensure(registry.clients.get(a)?.ready === true && registry.clients.get(b)?.ready === true);
    hilog.info(0x0000, 'R1RegistryCheck', 'PASS registry-two-real-environments');
    const originalClient = registry.clients.get(a);
    const originalSession = JSON.stringify(await registry.assets.session(registry.entry(a).credentialRef).load());
    ensure(await registry.add(fixture.a.base, '') === a);
    ensure(registry.clients.get(a) === originalClient && registry.directory.entries.length === 2);
    ensure(JSON.stringify(await registry.assets.session(registry.entry(a).credentialRef).load()) === originalSession);
    hilog.info(0x0000, 'R1RegistryCheck', 'PASS known-address-reuses-client-and-credential');
    await registry.select(a);
    await registry.setEnabled(a, false);
    ensure(registry.clients.get(a)?.ready === false && registry.clients.get(b)?.ready === true);
    await registry.setEnabled(a, true);
    ensure(registry.clients.get(a)?.ready === true && registry.clients.get(b)?.ready === true);
    hilog.info(0x0000, 'R1RegistryCheck', 'PASS select-disable-reenable-independent');
    const entryA = registry.entry(a); const entryB = registry.entry(b);
    const pending: RecoveryState = { base: entryA.base, environmentId: entryA.environmentId,
      threadId: 'same-thread', pendingId: 'synthetic-unknown', pendingKind: 'message' };
    await registry.saveRecovery(a, pending);
    await registry.saveRecovery(b, { base: entryB.base, environmentId: entryB.environmentId,
      threadId: 'same-thread', pendingId: '', pendingKind: '' });
    ensure(registry.entry(a).recovery[0].alias !== registry.entry(b).recovery[0].alias);
    let blocked = false;
    try { await registry.remove(a); } catch (_) { blocked = true; }
    ensure(blocked && registry.directory.entries.length === 2);
    hilog.info(0x0000, 'R1RegistryCheck', 'PASS same-thread-scope-and-unknown-removal-protection');
    // Synthetic metadata only: no message was ever dispatched for this marker.
    await registry.saveRecovery(a, { base: pending.base, environmentId: pending.environmentId,
      threadId: pending.threadId, pendingId: '', pendingKind: '' });
    await registry.remove(a);
    ensure(registry.clients.get(b)?.ready === true && registry.directory.entries.length === 1);
    await registry.remove(b);
    ensure(registry.directory.entries.length === 0);
    hilog.info(0x0000, 'R1RegistryCheck', 'PASS removal-cleans-only-target-environment');
    await legacy.save({ base: entryA.base, environmentId: entryA.environmentId, token: 'SYNTHETIC_ONLY', expiresAt: 1 });
    await registry.initialize();
    ensure(registry.directory.entries.length === 0);
    await legacy.clear(); await legacyRecovery.clear();
    fileIo.unlinkSync(root + '/environments-v2.json'); fileIo.rmdirSync(root);
    const probe = context.getApplicationContext().filesDir + '/r1-probe.txt';
    if (fileIo.accessSync(probe)) fileIo.unlinkSync(probe);
    this.report = '6 registry groups passed';
    hilog.info(0x0000, 'R1RegistryCheck', 'PASS no-legacy-resurrection-and-cleanup');
    hilog.info(0x0000, 'R1RegistryCheck', 'DONE passed=6 failed=0');
  }
  build() {
    Column({ space: 20 }) { Text('R1 isolated registry checks').fontSize(22); Text(this.report).fontSize(18) }
      .width('100%').height('100%').justifyContent(FlexAlign.Center).padding(24)
  }
}
