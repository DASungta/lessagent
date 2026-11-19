import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { T3Client } from '../services/T3Client';
import { SessionStore } from '../storage/SessionStore';
import { SavedSession } from '../protocol/Core';
interface NegativeCase { name: string; base: string; expectedStatus: string; }
interface NegativeResult { name: string; passed: boolean; status: string; noCredentialSaved: boolean; }
interface NegativeEvidence { deviceTime: number; results: NegativeResult[]; noRealCredentialsUsed: boolean; }
@Entry
@Component
struct TransportCheck {
  @State report: string = 'Running native transport negative checks';
  aboutToAppear(): void { void this.run().catch(() => { this.report = 'FAIL setup'; hilog.error(0x0000, 'R1TransportCheck', 'SETUP_FAILED'); }); }
  private async run(): Promise<void> {
    const cases: NegativeCase[] = [
      { name: 'oauth-redirect-not-followed', base: 'http://192.168.10.75:47841', expectedStatus: '2300047' },
      { name: 'oauth-307-body-not-forwarded', base: 'http://192.168.10.75:47846', expectedStatus: '2300047' },
      { name: 'self-signed-tls-rejected', base: 'https://192.168.10.75:47843', expectedStatus: '2300060' },
      { name: 'protocol-rejected-before-credential', base: 'http://192.168.10.75:47845', expectedStatus: '协议不兼容' }
    ];
    const results: NegativeResult[] = [];
    for (const test of cases) {
      const connection = new T3Client();
      const store = new SessionStore<SavedSession>('r1-negative-' + util.generateRandomUUID());
      connection.store = store;
      try {
        await connection.connect(test.base, 'SYNTHETIC_NEGATIVE_ONLY');
        const noCredentialSaved = await store.load() === undefined;
        const passed = !connection.ready && noCredentialSaved && connection.status.includes(test.expectedStatus);
        results.push({ name: test.name, passed, status: connection.status, noCredentialSaved });
        hilog.info(0x0000, 'R1TransportCheck', '%{public}s %{public}s', passed ? 'PASS' : 'FAIL', test.name);
      } finally { connection.disconnect(); await store.clear(); }
    }
    const evidence: NegativeEvidence = { deviceTime: Date.now(), results, noRealCredentialsUsed: true };
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const file = fileIo.openSync(context.getApplicationContext().filesDir + '/r1-transport-negative.json', fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    try { fileIo.writeSync(file.fd, JSON.stringify(evidence)); fileIo.fsyncSync(file.fd); }
    finally { fileIo.closeSync(file); }
    const passed = results.filter((test: NegativeResult) => test.passed).length;
    this.report = passed + '/' + results.length + ' native checks passed; compare host counters before accepting';
    hilog.info(0x0000, 'R1TransportCheck', 'DONE passed=%{public}d total=%{public}d', passed, results.length);
  }
  build() {
    Column({ space: 20 }) { Text('R1 native negative transport checks').fontSize(22); Text(this.report).fontSize(18) }
      .width('100%').height('100%').justifyContent(FlexAlign.Center).padding(24)
  }
}
