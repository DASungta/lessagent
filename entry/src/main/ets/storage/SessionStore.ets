import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { SavedSession } from '../protocol/Core';
import { BusinessError, screenLock } from '@kit.BasicServicesKit';

export class SessionStore<T = SavedSession> {
  private alias: Uint8Array;
  constructor(name: string = 't3-harmony-session-v1') { this.alias = new util.TextEncoder().encodeInto(name); }
  private async requireUnlocked(): Promise<void> {
    try {
      if (await screenLock.isScreenLocked()) throw new Error('locked');
    } catch (_) { throw new Error('请解锁设备后访问系统安全存储'); }
  }
  async load(): Promise<T | undefined> {
    await this.requireUnlocked();
    try {
      const rows = await asset.query(new Map<asset.Tag, asset.Value>([[asset.Tag.ALIAS, this.alias], [asset.Tag.RETURN_TYPE, asset.ReturnType.ALL]]));
      await this.requireUnlocked();
      return JSON.parse(new util.TextDecoder().decodeToString(rows[0].get(asset.Tag.SECRET) as Uint8Array)) as T;
    } catch (error) {
      if ((error as BusinessError).code === 24000002) return undefined;
      throw new Error('无法读取系统安全存储，请解锁设备后重试');
    }
  }
  async save(value: T): Promise<void> {
    await this.requireUnlocked();
    const content = JSON.stringify(value);
    const secret = new util.TextEncoder().encodeInto(content);
    // shortcut: one Asset record; use encrypted file storage if a server issues larger credentials.
    if (secret.length > 1024) throw new Error('凭据超过系统安全存储大小限制，未保存');
    try {
      await asset.add(new Map<asset.Tag, asset.Value>([[asset.Tag.ALIAS, this.alias], [asset.Tag.SECRET, secret],
        [asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_UNLOCKED],
        [asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE]]));
    } catch (_) { throw new Error('系统安全存储保存失败'); }
    if (JSON.stringify(await this.load()) !== content) throw new Error('系统安全存储回读校验失败');
  }
  async clear(): Promise<void> {
    await this.requireUnlocked();
    try { await asset.remove(new Map<asset.Tag, asset.Value>([[asset.Tag.ALIAS, this.alias]])); }
    catch (error) { if ((error as BusinessError).code !== 24000002) throw new Error('系统安全存储删除失败'); }
  }
}
