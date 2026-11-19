import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError, screenLock } from '@kit.BasicServicesKit';
import { SessionStore } from './SessionStore';
import {
  base64UrlEncode, CloudAccountSession, cloudAccountSession, CloudEnvironmentToken, cloudEnvironmentToken,
  RelayTokenCache, relayTokenCache
} from '../protocol/Cloud';

interface CloudSessionManifest {
  version: number;
  generation: number;
  chunks: number;
  bytes: number;
}

const CLOUD_CHUNK_BYTES = 800;
const CLOUD_SESSION_LIMIT = 65536;

function alias(value: string): Uint8Array {
  return new util.TextEncoder().encodeInto(value);
}

// Clerk session tokens can exceed one Asset item. Chunks are verified before the manifest commits.
export class CloudSessionStore {
  private manifestAlias: string = 't3-cloud-account-manifest-v1';
  private prefix: string = 't3-cloud-account-session-';

  private async requireUnlocked(): Promise<void> {
    try {
      if (await screenLock.isScreenLocked()) throw new Error('locked');
    } catch (_) { throw new Error('请解锁设备后访问 T3 Connect 安全存储'); }
  }

  private async read(name: string): Promise<Uint8Array | undefined> {
    await this.requireUnlocked();
    try {
      const rows = await asset.query(new Map<asset.Tag, asset.Value>([[asset.Tag.ALIAS, alias(name)],
        [asset.Tag.RETURN_TYPE, asset.ReturnType.ALL]]));
      await this.requireUnlocked();
      return rows[0].get(asset.Tag.SECRET) as Uint8Array;
    } catch (error) {
      if ((error as BusinessError).code === 24000002) return undefined;
      throw new Error('无法读取 T3 Connect 安全存储，请解锁设备后重试');
    }
  }

  private async write(name: string, value: Uint8Array): Promise<void> {
    await this.requireUnlocked();
    try {
      await asset.add(new Map<asset.Tag, asset.Value>([[asset.Tag.ALIAS, alias(name)], [asset.Tag.SECRET, value],
        [asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_UNLOCKED],
        [asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE]]));
    } catch (_) { throw new Error('T3 Connect 安全存储保存失败'); }
    const checked = await this.read(name);
    if (!checked || checked.length !== value.length || !checked.every((byte: number, index: number) => byte === value[index])) {
      throw new Error('T3 Connect 安全存储回读校验失败');
    }
  }

  private async remove(name: string): Promise<void> {
    await this.requireUnlocked();
    try { await asset.remove(new Map<asset.Tag, asset.Value>([[asset.Tag.ALIAS, alias(name)]])); }
    catch (error) { if ((error as BusinessError).code !== 24000002) throw new Error('T3 Connect 安全存储删除失败'); }
  }

  private manifest(value: Uint8Array): CloudSessionManifest {
    const parsed = JSON.parse(new util.TextDecoder().decodeToString(value)) as CloudSessionManifest;
    if (parsed.version !== 1 || !Number.isSafeInteger(parsed.generation) || parsed.generation < 1 ||
      !Number.isSafeInteger(parsed.chunks) || parsed.chunks < 1 || parsed.chunks > 80 ||
      !Number.isSafeInteger(parsed.bytes) || parsed.bytes < 1 || parsed.bytes > CLOUD_SESSION_LIMIT) {
      throw new Error('T3 Connect 账号存储清单无效');
    }
    return parsed;
  }

  async load(): Promise<CloudAccountSession | undefined> {
    const encoded = await this.read(this.manifestAlias);
    if (!encoded) return undefined;
    const manifest = this.manifest(encoded);
    const parts: Uint8Array[] = [];
    let length = 0;
    for (let index = 0; index < manifest.chunks; index++) {
      const part = await this.read(this.prefix + manifest.generation + '-' + index);
      if (!part) throw new Error('T3 Connect 账号存储分片缺失');
      parts.push(part); length += part.length;
    }
    if (length !== manifest.bytes) throw new Error('T3 Connect 账号存储长度不一致');
    const joined = new Uint8Array(length);
    let offset = 0;
    for (const part of parts) { joined.set(part, offset); offset += part.length; }
    return cloudAccountSession(JSON.parse(new util.TextDecoder().decodeToString(joined)) as Object);
  }

  async save(value: CloudAccountSession): Promise<void> {
    const checked = cloudAccountSession(value);
    const bytes = new util.TextEncoder().encodeInto(JSON.stringify(checked));
    if (bytes.length > CLOUD_SESSION_LIMIT) throw new Error('T3 Connect 账号记录过大，未保存');
    const old = await this.read(this.manifestAlias);
    const previous = old ? this.manifest(old) : undefined;
    const generation = (previous?.generation || 0) + 1;
    const count = Math.ceil(bytes.length / CLOUD_CHUNK_BYTES);
    const written: string[] = [];
    try {
      for (let index = 0; index < count; index++) {
        const name = this.prefix + generation + '-' + index;
        written.push(name);
        await this.write(name, bytes.slice(index * CLOUD_CHUNK_BYTES,
          Math.min(bytes.length, (index + 1) * CLOUD_CHUNK_BYTES)));
      }
      const manifest: CloudSessionManifest = { version: 1, generation, chunks: count, bytes: bytes.length };
      await this.write(this.manifestAlias,
        new util.TextEncoder().encodeInto(JSON.stringify(manifest)));
    } catch (error) {
      for (const name of written) { try { await this.remove(name); } catch (_) {} }
      throw error as Error;
    }
    if (previous) {
      // shortcut: old-generation chunks can remain after an interrupted cleanup; they are unreadable.
      for (let index = 0; index < previous.chunks; index++) {
        try { await this.remove(this.prefix + previous.generation + '-' + index); } catch (_) {}
      }
    }
  }

  async clear(): Promise<void> {
    const encoded = await this.read(this.manifestAlias);
    if (encoded) {
      const manifest = this.manifest(encoded);
      await this.remove(this.manifestAlias);
      for (let index = 0; index < manifest.chunks; index++) {
        try { await this.remove(this.prefix + manifest.generation + '-' + index); } catch (_) {}
      }
      return;
    }
    await this.remove(this.manifestAlias);
  }
}

export class RelayTokenStore {
  private store: SessionStore<RelayTokenCache> = new SessionStore<RelayTokenCache>('t3-cloud-relay-token-v1');
  async load(): Promise<RelayTokenCache | undefined> {
    const value = await this.store.load();
    return value ? relayTokenCache(value as Object) : undefined;
  }
  async save(value: RelayTokenCache): Promise<void> { await this.store.save(relayTokenCache(value as Object)); }
  async clear(): Promise<void> { await this.store.clear(); }
}

function environmentAlias(environmentId: string): string {
  return 't3-cloud-env-token-' + base64UrlEncode(new util.TextEncoder().encodeInto(environmentId));
}

export class CloudEnvironmentTokenStore {
  async load(environmentId: string): Promise<CloudEnvironmentToken | undefined> {
    const value = await new SessionStore<CloudEnvironmentToken>(environmentAlias(environmentId)).load();
    return value ? cloudEnvironmentToken(value as Object) : undefined;
  }
  async save(value: CloudEnvironmentToken): Promise<void> {
    const checked = cloudEnvironmentToken(value as Object);
    await new SessionStore<CloudEnvironmentToken>(environmentAlias(checked.environmentId)).save(checked);
  }
  async clear(environmentId: string): Promise<void> {
    await new SessionStore<CloudEnvironmentToken>(environmentAlias(environmentId)).clear();
  }
}
