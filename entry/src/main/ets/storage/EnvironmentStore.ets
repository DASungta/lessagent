import { fileIo } from '@kit.CoreFileKit';
import { EnvironmentDirectory, environmentDirectory, EnvironmentAssets } from '../protocol/Environment';
import { SavedSession, RecoveryState } from '../protocol/Core';
import { SessionStore } from './SessionStore';
import { BusinessError } from '@kit.BasicServicesKit';

// Only non-secret metadata lives here; credentials and recovery remain in DEVICE_UNLOCKED Assets.
export class EnvironmentStore {
  private path: string;
  constructor(filesDir: string) { this.path = filesDir + '/environments-v2.json'; }
  async load(): Promise<EnvironmentDirectory | undefined> {
    try { return environmentDirectory(JSON.parse(fileIo.readTextSync(this.path)) as Object); }
    catch (error) {
      if ((error as BusinessError).code === 13900002) return undefined;
      throw new Error('环境目录不可读或损坏，未覆盖原记录');
    }
  }
  async save(value: EnvironmentDirectory): Promise<void> {
    const content = JSON.stringify(environmentDirectory(value));
    const temporary = this.path + '.tmp';
    const file = fileIo.openSync(temporary, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, content);
      fileIo.fsyncSync(file.fd);
    } finally { fileIo.closeSync(file); }
    const checked = environmentDirectory(JSON.parse(fileIo.readTextSync(temporary)) as Object);
    if (JSON.stringify(checked) !== content) throw new Error('环境目录回读校验失败');
    fileIo.renameSync(temporary, this.path);
  }
  async clear(): Promise<void> {
    // Keep an empty committed directory so v1 cannot resurrect after removal.
    const old = await this.load();
    await this.save({ schemaVersion: 2, generation: (old?.generation || 0) + 1, selectedLocalId: '', entries: [] });
  }
}
export class ProtectedEnvironmentAssets implements EnvironmentAssets {
  session(alias: string): SessionStore<SavedSession> { return new SessionStore<SavedSession>(alias); }
  recovery(alias: string): SessionStore<RecoveryState> { return new SessionStore<RecoveryState>(alias); }
}
