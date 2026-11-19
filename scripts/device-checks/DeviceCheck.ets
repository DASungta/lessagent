import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo } from '@kit.CoreFileKit';
import { pairingTarget } from '../protocol/Pairing';
import { EnvironmentDirectory, EnvironmentAssets, migrateLegacy, environmentDirectory } from '../protocol/Environment';
import { EnvironmentStore } from '../storage/EnvironmentStore';
import { SessionStore } from '../storage/SessionStore';
import { SavedSession, RecoveryState } from '../protocol/Core';

class TestAssets implements EnvironmentAssets {
  session(alias: string): SessionStore<SavedSession> { return new SessionStore<SavedSession>('r1-check-' + alias); }
  recovery(alias: string): SessionStore<RecoveryState> { return new SessionStore<RecoveryState>('r1-check-' + alias); }
}
function ensure(value: boolean): void { if (!value) throw new Error('assertion failed'); }

@Entry
@Component
struct DeviceCheck {
  @State report: string = 'R1 device checks running';
  private passed: number = 0;
  private failed: number = 0;
  private async check(name: string, run: () => Promise<void>): Promise<void> {
    try { await run(); this.passed++; hilog.info(0x0000, 'R1DeviceCheck', 'PASS %{public}s', name); }
    catch (error) {
      this.failed++;
      hilog.error(0x0000, 'R1DeviceCheck', 'FAIL %{public}s %{public}s', name, (error as Error).message);
    }
    this.report = 'R1 device checks: ' + this.passed + ' passed, ' + this.failed + ' failed';
  }
  aboutToAppear(): void { void this.run(); }
  private async run(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const root = context.filesDir + '/r1-device-check';
    if (!fileIo.accessSync(root)) fileIo.mkdirSync(root);
    const directory = new EnvironmentStore(root);
    const legacy = new SessionStore<SavedSession>('r1-check-legacy-session');
    const recovery = new SessionStore<RecoveryState>('r1-check-legacy-recovery');
    const assets = new TestAssets();
    const session: SavedSession = { base: 'https://synthetic.invalid', environmentId: 'synthetic-env', token: 'SYNTHETIC_ONLY', expiresAt: 1 };
    const pending: RecoveryState = { base: session.base, environmentId: session.environmentId, threadId: 'same-thread', pendingId: 'unknown', pendingKind: 'message' };
    const persisted = await directory.load();
    if (persisted) {
      await this.check('restart-preserves-directory-and-unknown-marker', async () => {
        const loaded = await migrateLegacy(directory, assets, legacy, recovery);
        ensure(loaded.entries.length === 1);
        ensure(JSON.stringify(await assets.recovery(loaded.entries[0].recovery[0].alias).load()) === JSON.stringify(pending));
        ensure(JSON.stringify(await legacy.load()) === JSON.stringify(session));
      });
      await this.check('cleanup-test-records', async () => {
        await legacy.clear(); await recovery.clear();
        await assets.session('t3-v2-legacy-v1-session').clear();
        await assets.recovery('t3-v2-legacy-v1-recovery-initial').clear();
        fileIo.unlinkSync(root + '/environments-v2.json');
        fileIo.rmdirSync(root);
      });
    } else {
      await this.check('pairing-ipv4-ipv6-tailnet', async () => {
        ensure(pairingTarget('192.168.1.100:3773').base === 'http://192.168.1.100:3773');
        ensure(pairingTarget('[fd00::1]:3773').base === 'http://[fd00::1]:3773');
        ensure(pairingTarget('desktop.tailnet.ts.net').base === 'https://desktop.tailnet.ts.net');
      });
      await this.check('pairing-hosted-query-hash-unicode', async () => {
        const target = pairingTarget('https://app.t3.codes/pair?host=https%3A%2F%2Fdesktop.tailnet.ts.net%2F#token=a%2Bb%26%E4%B8%AD');
        ensure(target.base === 'https://desktop.tailnet.ts.net' && target.code === 'a+b&中');
        ensure(pairingTarget('https://synthetic.invalid/?token=query#token=hash').code === 'hash');
      });
      await this.check('pairing-wrapper-wss', async () => {
        const target = pairingTarget('t3code://pair?pairingUrl=https%3A%2F%2Fsynthetic.invalid%2F%23token%3Dcode');
        ensure(target.base === 'https://synthetic.invalid' && target.code === 'code');
        ensure(pairingTarget('wss://synthetic.invalid/path').base === 'https://synthetic.invalid');
      });
      await this.check('pairing-invalid-input-rejected', async () => {
        const bad: string[] = ['ftp://test', 'https://user:secret@test', 'https://test:65536', 'http://[::zzz]', 't3code://else?pairingUrl=https://test'];
        for (const input of bad) {
          let rejected = false;
          try { pairingTarget(input); } catch (_) { rejected = true; }
          ensure(rejected);
        }
      });
      await this.check('actual-asset-save-read-and-size-limit', async () => {
        await legacy.save(session); ensure(JSON.stringify(await legacy.load()) === JSON.stringify(session));
        let rejected = false;
        try { await legacy.save({ base: session.base, environmentId: session.environmentId, token: 'x'.repeat(1025), expiresAt: 1 }); }
        catch (_) { rejected = true; }
        ensure(rejected && JSON.stringify(await legacy.load()) === JSON.stringify(session));
        await recovery.save(pending);
      });
      await this.check('migration-identity-mismatch-keeps-v1', async () => {
        await recovery.save({ base: session.base, environmentId: 'other', threadId: pending.threadId, pendingId: 'unknown', pendingKind: 'message' });
        let rejected = false;
        try { await migrateLegacy(directory, assets, legacy, recovery); } catch (_) { rejected = true; }
        ensure(rejected && await directory.load() === undefined && (await recovery.load())?.pendingId === 'unknown');
        await recovery.save(pending);
      });
      await this.check('real-asset-and-file-migration', async () => {
        const migrated = await migrateLegacy(directory, assets, legacy, recovery);
        ensure(migrated.entries.length === 1 && migrated.entries[0].recovery[0].threadId === pending.threadId);
        ensure(JSON.stringify(await directory.load()) === JSON.stringify(migrated));
        ensure((await assets.recovery(migrated.entries[0].recovery[0].alias).load())?.pendingId === 'unknown');
        ensure((await legacy.load())?.token === session.token);
      });
      await this.check('directory-schema-refuses-cross-environment-recovery', async () => {
        const d = await directory.load(); ensure(d !== undefined);
        const value = d as EnvironmentDirectory;
        value.entries[0].recovery[0].alias = 't3-v2-other-recovery-x';
        let rejected = false;
        try { environmentDirectory(value); } catch (_) { rejected = true; }
        ensure(rejected);
      });
      await this.check('directory-corruption-fails-closed', async () => {
        const path = root + '/environments-v2.json';
        const saved = fileIo.readTextSync(path);
        const f = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
        try { fileIo.writeSync(f.fd, 'broken'); } finally { fileIo.closeSync(f); }
        let rejected = false;
        try { await directory.load(); } catch (_) { rejected = true; }
        ensure(rejected);
        const restore = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
        try { fileIo.writeSync(restore.fd, saved); } finally { fileIo.closeSync(restore); }
        ensure((await directory.load())?.entries.length === 1);
      });
    }
    hilog.info(0x0000, 'R1DeviceCheck', 'DONE passed=%{public}d failed=%{public}d', this.passed, this.failed);
  }
  build() {
    Column({ space: 20 }) {
      Text('R1 isolated device checks').fontSize(22)
      Text(this.report).fontSize(18)
      Text('Synthetic data only. Restart once to verify persistence and clean up.').fontSize(14)
    }.width('100%').height('100%').justifyContent(FlexAlign.Center).padding(24)
  }
}
