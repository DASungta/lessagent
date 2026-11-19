import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo } from '@kit.CoreFileKit';
import { SessionStore } from '../storage/SessionStore';
import { EnvironmentStore, ProtectedEnvironmentAssets } from '../storage/EnvironmentStore';
import { SavedSession, RecoveryState } from '../protocol/Core';
interface UpgradeAuditResult {
  schemaVersion: number; localId: string; environmentId: string; threadId: string; pendingId: string; pendingKind: string;
  realCredentialExactlyPreserved: boolean; oldRecoveryExactlyPreserved: boolean; noPlaintextTokenInDirectory: boolean;
  selectedEnvironmentPreserved: boolean; generationUnchanged: boolean;
}
function ensure(value: boolean): void { if (!value) throw new Error('actual upgrade audit failed'); }
@Entry
@Component
struct UpgradeAudit {
  @State report: string = 'Reading protected upgrade evidence';
  aboutToAppear(): void { void this.run().catch((error: Error) => { this.report = 'FAIL'; hilog.error(0x0000, 'R1UpgradeAudit', 'FAIL %{public}s', error.message); }); }
  private async run(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const directory = await new EnvironmentStore(context.filesDir).load();
    ensure(!!directory && directory.schemaVersion === 2 && directory.selectedLocalId === 'legacy-v1' && directory.entries.length === 1);
    const entry = directory!.entries[0];
    ensure(entry.base === 'http://127.0.0.1:47831' && entry.recovery.length === 1 && entry.recovery[0].threadId === 'r1-collision-thread');
    const oldSession = await new SessionStore<SavedSession>().load();
    const oldRecovery = await new SessionStore<RecoveryState>('t3-harmony-recovery-v1').load();
    const assets = new ProtectedEnvironmentAssets();
    const session = await assets.session(entry.credentialRef).load();
    const recovery = await assets.recovery(entry.recovery[0].alias).load();
    ensure(!!session && !!recovery && !!oldSession && !!oldRecovery);
    ensure(JSON.stringify(session) === JSON.stringify(oldSession) && JSON.stringify(recovery) === JSON.stringify(oldRecovery));
    ensure(recovery!.pendingId === 'r1-synthetic-unconfirmed' && recovery!.pendingKind === 'message');
    const encoded = JSON.stringify(directory);
    ensure(!encoded.includes(session!.token) && !encoded.includes('"token"'));
    const reread = await new EnvironmentStore(context.filesDir).load();
    ensure(reread?.generation === directory!.generation);
    const result: UpgradeAuditResult = { schemaVersion: 2, localId: entry.localId, environmentId: entry.environmentId,
      threadId: recovery!.threadId, pendingId: recovery!.pendingId, pendingKind: recovery!.pendingKind,
      realCredentialExactlyPreserved: true, oldRecoveryExactlyPreserved: true, noPlaintextTokenInDirectory: true,
      selectedEnvironmentPreserved: true, generationUnchanged: true };
    const file = fileIo.openSync(context.getApplicationContext().filesDir + '/r1-upgrade-audit.json', fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    try { fileIo.writeSync(file.fd, JSON.stringify(result)); fileIo.fsyncSync(file.fd); }
    finally { fileIo.closeSync(file); }
    this.report = 'PASS actual v1 to v2 upgrade; credentials and pending marker unchanged';
    hilog.info(0x0000, 'R1UpgradeAudit', 'PASS real-credential-and-recovery-exactly-preserved');
  }
  build() {
    Column({ space: 20 }) { Text('R1 actual upgrade audit').fontSize(22); Text(this.report).fontSize(18) }
      .width('100%').height('100%').justifyContent(FlexAlign.Center).padding(24)
  }
}
