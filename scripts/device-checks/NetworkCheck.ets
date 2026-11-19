import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo } from '@kit.CoreFileKit';
import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { pairingTarget, PairingTarget } from '../protocol/Pairing';
import { T3Client } from '../services/T3Client';
import { SavedSession } from '../protocol/Core';
import { SessionStore } from '../storage/SessionStore';
interface NetworkFixture { a: PairingTarget; b: PairingTarget; }
function ensure(value: boolean): void { if (!value) throw new Error('device assertion failed'); }

@Entry
@Component
struct NetworkCheck {
  @State report: string = 'R1 network checks running';
  private passed: number = 0;
  private failed: number = 0;
  private timer: number = 0;
  private lockedSeen: boolean = false;
  private probing: boolean = false;
  private lockStore: SessionStore<SavedSession> = new SessionStore<SavedSession>('r1-net-lock');
  private async check(name: string, run: () => Promise<void>): Promise<void> {
    try { await run(); this.passed++; hilog.info(0x0000, 'R1NetworkCheck', 'PASS %{public}s', name); }
    catch (error) { this.failed++; hilog.error(0x0000, 'R1NetworkCheck', 'FAIL %{public}s %{public}s', name, (error as Error).message); }
    this.report = 'R1 network: ' + this.passed + ' passed, ' + this.failed + ' failed';
  }
  aboutToAppear(): void { void this.run().catch(() => { hilog.error(0x0000, 'R1NetworkCheck', 'SETUP_FAILED'); }); }
  aboutToDisappear(): void { clearInterval(this.timer); }
  private async run(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const fixturePath = context.getApplicationContext().filesDir + '/r1-network.json';
    hilog.info(0x0000, 'R1NetworkCheck', 'FIXTURE_PATH %{public}s', fixturePath);
    const fixture = JSON.parse(fileIo.readTextSync(fixturePath)) as NetworkFixture;
    fileIo.unlinkSync(fixturePath);
    const a = new T3Client(); const b = new T3Client();
    const aStore = new SessionStore<SavedSession>('r1-net-a');
    const bStore = new SessionStore<SavedSession>('r1-net-b');
    a.store = aStore; b.store = bStore;
    a.recoveryStore = new SessionStore('r1-net-recovery-a');
    b.recoveryStore = new SessionStore('r1-net-recovery-b');
    await this.check('lan-a-real-oauth-websocket-config', async () => {
      const target = pairingTarget(fixture.a.base, fixture.a.code);
      await a.connect(target.base, target.code); ensure(a.ready);
    });
    await this.check('lan-b-independent-oauth-websocket-config', async () => {
      const target = pairingTarget(fixture.b.base, fixture.b.code);
      await b.connect(target.base, target.code); ensure(a.ready && b.ready);
      const sa = await aStore.load(); const sb = await bStore.load();
      ensure(!!sa && !!sb && sa.environmentId !== sb.environmentId && sa.token !== sb.token);
    });
    await this.check('disconnect-a-preserves-b-and-reconnects-a', async () => {
      a.suspend(); ensure(!a.ready && b.ready); await a.resume(); ensure(a.ready && b.ready);
    });
    await this.check('invalid-credential-rejected-without-overwriting-b', async () => {
      const saved = await bStore.load();
      await b.connect(fixture.b.base, 'SYNTHETIC_INVALID_CODE');
      ensure(!b.ready && JSON.stringify(await bStore.load()) === JSON.stringify(saved));
      await b.connect(fixture.b.base); ensure(b.ready);
    });
    a.disconnect(); b.disconnect();
    await aStore.clear(); await bStore.clear();
    const synthetic: SavedSession = { base: 'https://synthetic.invalid', environmentId: 'lock-probe', token: 'SYNTHETIC_ONLY', expiresAt: 1 };
    await this.lockStore.save(synthetic);
    ensure(JSON.stringify(await this.lockStore.load()) === JSON.stringify(synthetic));
    this.timer = setInterval(() => { void this.probe(); }, 500);
    hilog.info(0x0000, 'R1NetworkCheck', 'LOCK_PROBE_READY network_passed=%{public}d failed=%{public}d', this.passed, this.failed);
  }
  private async probe(): Promise<void> {
    if (this.probing) return;
    this.probing = true;
    try {
      const alias = new util.TextEncoder().encodeInto('r1-net-lock');
      try {
        await asset.query(new Map<asset.Tag, asset.Value>([[asset.Tag.ALIAS, alias], [asset.Tag.RETURN_TYPE, asset.ReturnType.ALL]]));
      } catch (error) {
        const code = (error as BusinessError).code;
        if (code !== 24000005) { hilog.error(0x0000, 'R1NetworkCheck', 'PROBE_ERROR code=%{public}d', code); return; }
        let denied = false;
        try { await this.lockStore.load(); } catch (_) { denied = true; }
        if (!this.lockedSeen && denied) {
          this.lockedSeen = true;
          hilog.info(0x0000, 'R1NetworkCheck', 'PASS locked-asset-denied code=24000005 wrapper-fails-closed');
        }
        return;
      }
      if (this.lockedSeen) {
        ensure((await this.lockStore.load())?.environmentId === 'lock-probe');
        await this.lockStore.clear(); clearInterval(this.timer);
        this.report = 'Lock denied and unlock recovery passed';
        hilog.info(0x0000, 'R1NetworkCheck', 'PASS unlock-preserves-record-and-cleanup');
      }
    } finally { this.probing = false; }
  }
  build() {
    Column({ space: 20 }) {
      Text('R1 isolated network / lock checks').fontSize(22)
      Text(this.report).fontSize(18)
      Text('No agent tasks. Test aliases only. Unlock manually after the lock probe.').fontSize(14)
    }.width('100%').height('100%').justifyContent(FlexAlign.Center).padding(24)
  }
}
