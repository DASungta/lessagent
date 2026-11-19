import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo } from '@kit.CoreFileKit';
import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError, commonEventManager, screenLock } from '@kit.BasicServicesKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { SavedSession, RecoveryState } from '../protocol/Core';
import { SessionStore } from '../storage/SessionStore';
interface LockEvidence {
  readyAt: number; lockedAt: number; unlockedAt: number; lastProbeAt: number;
  queries: number; deniedCode: number; wrapperDenied: boolean; recovered: boolean;
  delayMs: number; events: string[]; secureMode: boolean; lockedReadable: boolean; screenApiLocked: boolean;
}
@Entry
@Component
struct LockCheck {
  @State report: string = 'Preparing actual lock check';
  private path: string = '';
  private timer: number = 0;
  private taskId: number = -1;
  private probing: boolean = false;
  private subscriber: commonEventManager.CommonEventSubscriber | undefined = undefined;
  private state: LockEvidence = { readyAt: 0, lockedAt: 0, unlockedAt: 0, lastProbeAt: 0,
    queries: 0, deniedCode: 0, wrapperDenied: false, recovered: false, delayMs: 0, events: [], secureMode: false, lockedReadable: false, screenApiLocked: false };
  private session: SessionStore<SavedSession> = new SessionStore<SavedSession>('r1-lock-v2-session');
  private recovery: SessionStore<RecoveryState> = new SessionStore<RecoveryState>('r1-lock-v2-recovery');
  aboutToAppear(): void { void this.run().catch((e: Error) => { this.report = 'SETUP FAILED'; hilog.error(0x0000, 'R1LockCheck', 'SETUP_FAILED %{public}s', e.message); }); }
  private persist(): void {
    const f = fileIo.openSync(this.path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    try { fileIo.writeSync(f.fd, JSON.stringify(this.state)); fileIo.fsyncSync(f.fd); }
    finally { fileIo.closeSync(f); }
  }
  private async run(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.path = context.getApplicationContext().filesDir + '/r1-lock-evidence.json';
    this.state.secureMode = await screenLock.isSecureMode();
    hilog.info(0x0000, 'R1LockCheck', 'SECURE_MODE %{public}s', String(this.state.secureMode));
    await this.session.save({ base: 'https://synthetic.invalid', environmentId: 'lock-v2', token: 'SYNTHETIC_ONLY', expiresAt: 1 });
    await this.recovery.save({ base: 'https://synthetic.invalid', environmentId: 'lock-v2', threadId: 'synthetic-thread', pendingId: 'unknown', pendingKind: 'message' });
    this.subscriber = await commonEventManager.createSubscriber({ events: [commonEventManager.Support.COMMON_EVENT_SCREEN_OFF,
      commonEventManager.Support.COMMON_EVENT_SCREEN_LOCKED, commonEventManager.Support.COMMON_EVENT_SCREEN_UNLOCKED] });
    commonEventManager.subscribe(this.subscriber, (error, data) => {
      if (error && error.code) return;
      void this.event(data.event);
    });
    const delay = backgroundTaskManager.requestSuspendDelay('R1 isolated Asset lock verification', () => {
      clearInterval(this.timer); this.persist();
      hilog.info(0x0000, 'R1LockCheck', 'DELAY_EXPIRED');
    });
    this.taskId = delay.requestId; this.state.delayMs = delay.actualDelayTime;
    this.state.readyAt = Date.now(); this.persist();
    this.timer = setInterval(() => { void this.probe(); }, 500);
    this.report = 'Ready for lock; evidence persists in private file';
    hilog.info(0x0000, 'R1LockCheck', 'READY delayMs=%{public}d', delay.actualDelayTime);
  }
  private async event(name: string): Promise<void> {
    this.state.events.push(name);
    if (name === commonEventManager.Support.COMMON_EVENT_SCREEN_LOCKED) this.state.lockedAt = Date.now();
    if (name === commonEventManager.Support.COMMON_EVENT_SCREEN_UNLOCKED) this.state.unlockedAt = Date.now();
    this.persist();
    hilog.info(0x0000, 'R1LockCheck', 'EVENT %{public}s', name);
    await this.probe();
  }
  private async probe(): Promise<void> {
    if (this.probing) return;
    this.probing = true;
    try {
      this.state.queries++; this.state.lastProbeAt = Date.now();
      this.state.screenApiLocked = await screenLock.isScreenLocked();
      if (this.state.screenApiLocked && !this.state.wrapperDenied) {
        try { await this.session.load(); } catch (_) { this.state.wrapperDenied = true; }
        this.persist();
        hilog.info(0x0000, 'R1LockCheck', 'LOCK_WRAPPER_DENIED %{public}s', String(this.state.wrapperDenied));
      }
      try {
        const alias = new util.TextEncoder().encodeInto('r1-lock-v2-session');
        await asset.query(new Map<asset.Tag, asset.Value>([[asset.Tag.ALIAS, alias], [asset.Tag.RETURN_TYPE, asset.ReturnType.ALL]]));
      } catch (error) {
        const code = (error as BusinessError).code;
        if (code === 24000005 && !this.state.deniedCode) {
          this.state.deniedCode = code;
          try { await this.session.load(); } catch (_) { this.state.wrapperDenied = true; }
          this.persist();
          hilog.info(0x0000, 'R1LockCheck', 'LOCK_DENIED code=%{public}d wrapper=%{public}s', code, String(this.state.wrapperDenied));
        }
        return;
      }
      if (this.state.lockedAt && !this.state.unlockedAt && !this.state.lockedReadable) {
        this.state.lockedReadable = (await this.session.load())?.environmentId === 'lock-v2';
        this.persist();
      }
      if (this.state.unlockedAt) {
        const saved = await this.session.load(); const recovery = await this.recovery.load();
        this.state.recovered = saved?.environmentId === 'lock-v2' && recovery?.pendingId === 'unknown' && recovery?.pendingKind === 'message';
        this.persist(); clearInterval(this.timer);
        await this.session.clear(); await this.recovery.clear();
        await new SessionStore<SavedSession>('r1-net-lock').clear();
        if (this.taskId >= 0) backgroundTaskManager.cancelSuspendDelay(this.taskId);
        if (this.subscriber) await commonEventManager.unsubscribe(this.subscriber);
        this.report = this.state.recovered && this.state.wrapperDenied ? 'PASS locked denial and unknown marker recovery' : 'FAIL lock guard or recovery';
        hilog.info(0x0000, 'R1LockCheck', 'DONE recovered=%{public}s', String(this.state.recovered));
      }
    } finally { this.probing = false; }
  }
  build() {
    Column({ space: 20 }) { Text('R1 actual Asset lock check').fontSize(22); Text(this.report).fontSize(18) }
      .width('100%').height('100%').justifyContent(FlexAlign.Center).padding(24)
  }
}
