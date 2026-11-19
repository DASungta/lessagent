import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { base64UrlDecode } from '../protocol/Cloud';
import { DpopSigner } from '../services/Dpop';

function ensure(value: boolean): void { if (!value) throw new Error('cloud DPoP device assertion failed'); }

@Entry
@Component
struct CloudDpopCheck {
  @State report: string = 'Cloud DPoP checks running';
  private stage: string = 'start';
  aboutToAppear(): void {
    void this.run().catch((error: Error) => {
      this.report = 'FAIL at ' + this.stage;
      hilog.error(0x0000, 'R2CloudDpopCheck', 'FAIL at %{public}s: %{public}s', this.stage, error.message);
    });
  }
  private async run(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const signer = new DpopSigner();
    this.stage = 'load-or-create-key';
    const before = await signer.thumbprint();
    ensure(before.length === 43);
    const target = 'https://relay.example.test/v1/client/dpop-token?secret=query#fragment';
    this.stage = 'create-proof';
    const proof = await signer.prove('post', target, 'SYNTHETIC_ACCESS_TOKEN');
    const parts = proof.split('.');
    ensure(parts.length === 3);
    const header = JSON.parse(new util.TextDecoder().decodeToString(base64UrlDecode(parts[0]))) as Record<string, Object>;
    const payload = JSON.parse(new util.TextDecoder().decodeToString(base64UrlDecode(parts[1]))) as Record<string, Object>;
    ensure(header.typ === 'dpop+jwt' && header.alg === 'ES256');
    const jwk = header.jwk as Record<string, Object>;
    ensure(jwk.kty === 'EC' && jwk.crv === 'P-256');
    ensure(base64UrlDecode(jwk.x as string).length === 32 && base64UrlDecode(jwk.y as string).length === 32);
    ensure(payload.htm === 'POST' && payload.htu === 'https://relay.example.test/v1/client/dpop-token');
    ensure(typeof payload.jti === 'string' && (payload.jti as string).length > 0);
    ensure(typeof payload.iat === 'number' && Math.abs(Math.floor(Date.now() / 1000) - (payload.iat as number)) <= 5);
    ensure(typeof payload.ath === 'string' && (payload.ath as string).length === 43);
    ensure(base64UrlDecode(parts[2]).length === 64);
    this.stage = 'verify-proof';
    ensure(await signer.verifyProof(proof));
    const tampered = parts[0] + '.' + parts[1] + '.' +
      (parts[2].startsWith('A') ? 'B' : 'A') + parts[2].slice(1);
    ensure(!await signer.verifyProof(tampered));
    this.stage = 'reload-key';
    const reloaded = new DpopSigner();
    ensure(await reloaded.thumbprint() === before);
    const output = fileIo.openSync(context.getApplicationContext().filesDir + '/r2-dpop-result.json',
      fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(output.fd, JSON.stringify({
        passed: 6, failed: 0,
        keyPersistedAcrossInstances: true,
        thumbprintLength: before.length,
        proofVerifiedWithCryptoFramework: true,
        tamperedProofRejected: true,
        rawSignatureBytes: 64,
        htuRemovedQueryAndHash: true,
        methodUppercase: true,
        athPresent: true,
        storage: 'Asset DEVICE_UNLOCKED',
        crypto: 'CryptoFramework ECC256|SHA256',
        huksUsed: false,
        relayVerified: false,
        networkUsed: false
      }));
      fileIo.fsyncSync(output.fd);
    } finally { fileIo.closeSync(output); }
    this.report = '6 Cloud DPoP checks passed';
    hilog.info(0x0000, 'R2CloudDpopCheck', 'DONE passed=6 failed=0');
  }
  build() {
    Column({ space: 20 }) { Text('R2 isolated Cloud DPoP checks').fontSize(22); Text(this.report).fontSize(18) }
      .width('100%').height('100%').justifyContent(FlexAlign.Center).padding(24)
  }
}
