import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo } from '@kit.CoreFileKit';
import { EnvironmentAssets } from '../protocol/Environment';
import { PairingTarget } from '../protocol/Pairing';
import { SavedSession, RecoveryState } from '../protocol/Core';
import { EnvironmentRegistry } from '../services/EnvironmentRegistry';
import { SessionStore } from '../storage/SessionStore';
import { T3Client } from '../services/T3Client';
interface Fixture { a: PairingTarget; b: PairingTarget; replacementA: string; threadId: string; cleanupPrevious?: boolean; }
class TestAssets implements EnvironmentAssets {
  session(alias: string): SessionStore<SavedSession> { return new SessionStore<SavedSession>('r1-refresh-' + alias); }
  recovery(alias: string): SessionStore<RecoveryState> { return new SessionStore<RecoveryState>('r1-refresh-' + alias); }
}
function ensure(value: boolean): void { if (!value) throw new Error('credential refresh device assertion failed'); }
@Entry
@Component
struct CredentialRefreshCheck {
  @State report: string = 'Credential refresh checks running';
  private stage: string = 'start';
  aboutToAppear(): void {
    void this.run().catch(() => {
      this.report = 'FAIL at ' + this.stage;
      hilog.error(0x0000, 'R1RefreshCheck', 'FAIL at %{public}s', this.stage);
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
    const input = appFiles + '/r1-refresh.json';
    const fixture = JSON.parse(fileIo.readTextSync(input)) as Fixture;
    fileIo.unlinkSync(input);
    ensure(!!fixture.a.code && !!fixture.b.code && !!fixture.replacementA && !!fixture.threadId);
    const root = context.filesDir + '/r1-refresh-check';
    if (!fileIo.accessSync(root)) fileIo.mkdirSync(root);
    const legacy = new SessionStore<SavedSession>('r1-refresh-legacy');
    const legacyRecovery = new SessionStore<RecoveryState>('r1-refresh-legacy-recovery');
    const registry = new EnvironmentRegistry(root, new TestAssets(), legacy, legacyRecovery);
    this.stage = 'isolated-pairing';
    await registry.initialize();
    if (fixture.cleanupPrevious === true) {
      // Explicit retry cleanup is restricted to this diagnostic's own synthetic marker and aliases.
      for (const old of registry.directory.entries.slice()) {
        ensure(old.base === fixture.a.base || old.base === fixture.b.base);
        for (const ref of old.recovery) {
          const value = await registry.assets.recovery(ref.alias).load();
          ensure(!!value && value.threadId === fixture.threadId && (!value.pendingId || value.pendingId === 'r1-refresh-synthetic-unknown'));
          if (!value) throw new Error('missing diagnostic recovery');
          await registry.saveRecovery(old.localId, { base: value.base, environmentId: value.environmentId, threadId: value.threadId, pendingId: '', pendingKind: '' });
        }
        await registry.remove(old.localId);
      }
    }
    ensure(registry.directory.entries.length === 0);
    const a = await registry.add(fixture.a.base, fixture.a.code);
    const b = await registry.add(fixture.b.base, fixture.b.code);
    const entry = registry.entry(a); const client = registry.clients.get(a);
    const other = registry.entry(b); const otherClient = registry.clients.get(b);
    ensure(!!client && !!otherClient && client.ready && otherClient.ready);
    const otherSession = JSON.stringify(await registry.assets.session(other.credentialRef).load());
    const pending: RecoveryState = { base: entry.base, environmentId: entry.environmentId,
      threadId: fixture.threadId, pendingId: 'r1-refresh-synthetic-unknown', pendingKind: 'message' };
    await registry.saveRecovery(a, pending);
    const recoveryRef = registry.entry(a).recovery[0].alias;
    const store = registry.assets.session(entry.credentialRef);
    const expired = await store.load(); ensure(!!expired);
    if (!expired || !client || !otherClient) throw new Error('missing isolated fixture');
    expired.expiresAt = 1; await store.save(expired);
    this.stage = 'expired-with-unknown';
    await registry.setEnabled(a, false);
    const before = JSON.stringify(registry.directory);
    let rejected = false;
    try { await registry.add(entry.base, 'r1-deliberately-invalid'); } catch (_) { rejected = true; }
    client.disconnect('invalid-code check finished');
    ensure(rejected && JSON.stringify(registry.directory) === before);
    ensure(JSON.stringify(await store.load()) === JSON.stringify(expired));
    ensure(JSON.stringify(await registry.assets.recovery(recoveryRef).load()) === JSON.stringify(pending));
    this.stage = 'known-address-refresh';
    ensure(await registry.add(entry.base, fixture.replacementA) === a);
    ensure(registry.clients.get(a) === client && client.ready && registry.entry(a).enabled);
    ensure(registry.directory.entries.length === 2 && registry.directory.selectedLocalId === a);
    ensure(registry.entry(a).credentialRef === entry.credentialRef && registry.entry(a).recovery[0].alias === recoveryRef);
    ensure(JSON.stringify(client.recovery) === JSON.stringify(pending));
    const renewed = await store.load(); ensure(!!renewed && renewed.expiresAt > Date.now());
    ensure(JSON.stringify(await registry.assets.session(other.credentialRef).load()) === otherSession && otherClient.ready);
    this.stage = 'oversize-readback';
    let oversized = false;
    if (!renewed) throw new Error('missing renewed credential');
    try { await store.save({ base: renewed.base, environmentId: renewed.environmentId, token: 'x'.repeat(1025), expiresAt: renewed.expiresAt }); }
    catch (_) { oversized = true; }
    ensure(oversized && JSON.stringify(await store.load()) === JSON.stringify(renewed));
    this.stage = 'controlled-cleanup';
    // Only this diagnostic's synthetic unknown marker is cleared; no message was submitted.
    await this.synchronized(client); await client.acknowledgeUnknown();
    await registry.remove(a); ensure(otherClient.ready && registry.directory.entries.length === 1);
    await registry.remove(b); ensure(registry.directory.entries.length === 0);
    fileIo.unlinkSync(root + '/environments-v2.json'); fileIo.rmdirSync(root);
    const output = fileIo.openSync(appFiles + '/r1-refresh-result.json', fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    try { fileIo.writeSync(output.fd, JSON.stringify({ passed: 5, failed: 0, realServices: true, paidModelsUsed: false, productDirectoryTouched: false })); fileIo.fsyncSync(output.fd); }
    finally { fileIo.closeSync(output); }
    this.report = '5 native credential refresh groups passed';
    hilog.info(0x0000, 'R1RefreshCheck', 'DONE passed=5 failed=0');
  }
  build() {
    Column({ space: 20 }) { Text('R1 isolated credential refresh').fontSize(22); Text(this.report).fontSize(18) }
      .width('100%').height('100%').justifyContent(FlexAlign.Center).padding(24)
  }
}
