import { customScan, scanCore } from '@kit.ScanKit';
import { pairingTarget, PairingTarget } from '../protocol/Pairing';

// ScanKit owns one camera stream per process, including while old views are releasing.
let hardwareWork: Promise<void> = Promise.resolve();
let hardwareOwner: PairingScanner | undefined = undefined;

export class PairingScanner {
  private generation: number = 0;
  private initialized: boolean = false;
  private running: boolean = false;
  private enqueue(action: () => Promise<void>): Promise<void> {
    const next = hardwareWork.then(action); hardwareWork = next.catch(() => {}); return next;
  }
  private async release(): Promise<void> {
    try { if (this.running) await customScan.stop(); }
    finally {
      this.running = false;
      if (this.initialized) { await customScan.release(); this.initialized = false; }
    }
  }
  start(view: customScan.ViewControl, onTarget: (value: PairingTarget) => void, onError: (message: string) => void): Promise<void> {
    const generation = ++this.generation;
    return this.enqueue(async () => {
      if (generation !== this.generation) return;
      if (hardwareOwner && hardwareOwner !== this) { hardwareOwner.generation++; await hardwareOwner.release(); }
      await this.release();
      if (generation !== this.generation) return;
      hardwareOwner = this;
      let consumed = false;
      try {
        customScan.init({ scanTypes: [scanCore.ScanType.QR_CODE], enableMultiMode: false, enableAlbum: false });
        this.initialized = true; this.running = true;
        customScan.start(view, (error, rows) => {
          if (generation !== this.generation || consumed) return;
          consumed = true;
          if (error && error.code) onError('扫码失败，请重试');
          else {
            try {
              if (!rows.length) throw new Error('empty');
              onTarget(pairingTarget(rows[0].originalValue));
            } catch (_) { onError('二维码不是有效的配对地址，请重新扫描'); }
          }
          void this.stop().catch(() => onError('相机关闭失败，请退出此页重试'));
        });
      } catch (_) {
        await this.release();
        if (generation === this.generation) onError('无法启动相机，请检查权限后重试');
      }
    });
  }
  stop(): Promise<void> {
    this.generation++;
    return this.enqueue(async () => {
      await this.release();
      if (hardwareOwner === this) hardwareOwner = undefined;
    });
  }
}
