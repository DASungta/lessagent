import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SessionStore } from '../storage/SessionStore';
import { SavedSession, RecoveryState } from '../protocol/Core';
interface UpgradeInput { base: string; environmentId: string; threadId: string; }
interface UpgradeEvidence { base: string; environmentId: string; threadId: string; pendingId: string; pendingKind: string;
  directoryPath: string; legacySessionPreserved: boolean; v2DirectoryAbsent: boolean; agentTasksSubmitted: number; }
function ensure(value: boolean): void { if (!value) throw new Error('upgrade fixture boundary failed'); }
@Entry
@Component
struct UpgradePrepare {
  @State report: string = 'Checking archived v1 data';
  aboutToAppear(): void { void this.run().catch((error: Error) => { this.report = 'FAIL'; hilog.error(0x0000, 'R1UpgradePrepare', 'FAIL %{public}s', error.message); }); }
  private async run(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const shared = context.getApplicationContext().filesDir;
    const input = JSON.parse(fileIo.readTextSync(shared + '/r1-upgrade-meta.json')) as UpgradeInput;
    ensure(input.base === 'http://127.0.0.1:47831' && input.threadId === 'r1-collision-thread');
    const directoryPath = context.filesDir + '/environments-v2.json';
    ensure(!fileIo.accessSync(directoryPath));
    const sessionStore = new SessionStore<SavedSession>();
    const recoveryStore = new SessionStore<RecoveryState>('t3-harmony-recovery-v1');
    const session = await sessionStore.load(); const recovery = await recoveryStore.load();
    ensure(!!session && session.base === input.base && session.environmentId === input.environmentId && session.expiresAt > Date.now());
    ensure(!!recovery && recovery.base === input.base && recovery.environmentId === input.environmentId && recovery.threadId === input.threadId);
    const current = recovery as RecoveryState;
    ensure(current.pendingId === '' && current.pendingKind === '');
    const pending: RecoveryState = { base: current.base, environmentId: current.environmentId, threadId: current.threadId,
      pendingId: 'r1-synthetic-unconfirmed', pendingKind: 'message' };
    await recoveryStore.save(pending);
    ensure(JSON.stringify(await recoveryStore.load()) === JSON.stringify(pending));
    ensure(JSON.stringify(await sessionStore.load()) === JSON.stringify(session));
    const evidence: UpgradeEvidence = { base: input.base, environmentId: input.environmentId, threadId: input.threadId,
      pendingId: pending.pendingId, pendingKind: pending.pendingKind, directoryPath, legacySessionPreserved: true,
      v2DirectoryAbsent: true, agentTasksSubmitted: 0 };
    const f = fileIo.openSync(shared + '/r1-upgrade-seed-result.json', fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    try { fileIo.writeSync(f.fd, JSON.stringify(evidence)); fileIo.fsyncSync(f.fd); } finally { fileIo.closeSync(f); }
    fileIo.unlinkSync(shared + '/r1-upgrade-meta.json');
    this.report = 'PASS v1 real session preserved; synthetic unknown marker saved';
    hilog.info(0x0000, 'R1UpgradePrepare', 'PASS real-v1-session-and-synthetic-pending-ready');
  }
  build() {
    Column({ space: 20 }) { Text('R1 real upgrade preparation').fontSize(22); Text(this.report).fontSize(18) }
      .width('100%').height('100%').justifyContent(FlexAlign.Center).padding(24)
  }
}
