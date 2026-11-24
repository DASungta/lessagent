import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError, screenLock } from '@kit.BasicServicesKit';
import { SessionStore } from './SessionStore';
import {
  base64UrlEncode, CloudAccountSession, cloudAccountSession, CloudEnvironmentToken, cloudEnvironmentToken,
  PendingSsoSignIn, pendingSsoSignIn, RelayTokenCache, relayTokenCache
} from '../protocol/Cloud';

interface CloudAssetManifest {
  version: number;
  generation: number;
  chunks: number;
  bytes: number;
}

const CLOUD_CHUNK_BYTES = 800;
const CLOUD_RECORD_LIMIT = 65536;
const PENDING_SSO_MAX_AGE_MS = 15 * 60 * 1000;

function alias(value: string): Uint8Array {
  return new util.TextEncoder().encodeInto(value);
}

// HarmonyOS AssetStore limits each secret item to 1024 bytes; chunked records commit only after
// every chunk reads back byte-for-byte identical.
class ChunkedAssetStore {
  private manifestAlias: string;
  private prefix: string;
  private label: string;

  constructor(manifestAlias: string, prefix: string, label: string) {
    this.manifestAlias = manifestAlias;
    this.prefix = prefix;
    this.label = label;
  }

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

  private manifest(value: Uint8Array): CloudAssetManifest {
    const parsed = JSON.parse(new util.TextDecoder().decodeToString(value)) as CloudAssetManifest;
    if (parsed.version !== 1 || !Number.isSafeInteger(parsed.generation) || parsed.generation < 1 ||
      !Number.isSafeInteger(parsed.chunks) || parsed.chunks < 1 || parsed.chunks > 84 ||
      !Number.isSafeInteger(parsed.bytes) || parsed.bytes < 1 || parsed.bytes > CLOUD_RECORD_LIMIT) {
      throw new Error(this.label + '存储清单无效');
    }
    return parsed;
  }

  async loadObject(): Promise<Object | undefined> {
    const encoded = await this.read(this.manifestAlias);
    if (!encoded) return undefined;
    const manifest = this.manifest(encoded);
    const parts: Uint8Array[] = [];
    let length = 0;
    for (let index = 0; index < manifest.chunks; index++) {
      const part = await this.read(this.prefix + manifest.generation + '-' + index);
      if (!part) throw new Error(this.label + '存储分片缺失');
      parts.push(part); length += part.length;
    }
    if (length !== manifest.bytes) throw new Error(this.label + '存储长度不一致');
    const joined = new Uint8Array(length);
    let offset = 0;
    for (const part of parts) { joined.set(part, offset); offset += part.length; }
    return JSON.parse(new util.TextDecoder().decodeToString(joined)) as Object;
  }

  async saveObject(value: Object): Promise<void> {
    const bytes = new util.TextEncoder().encodeInto(JSON.stringify(value));
    if (bytes.length > CLOUD_RECORD_LIMIT) throw new Error(this.label + '记录过大，未保存');
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
      const manifest: CloudAssetManifest = { version: 1, generation, chunks: count, bytes: bytes.length };
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

export class CloudSessionStore {
  private store: ChunkedAssetStore = new ChunkedAssetStore(
    't3-cloud-account-manifest-v1', 't3-cloud-account-session-', 'T3 Connect 账号');

  async load(): Promise<CloudAccountSession | undefined> {
    const value = await this.store.loadObject();
    return value ? cloudAccountSession(value) : undefined;
  }

  async save(value: CloudAccountSession): Promise<void> {
    await this.store.saveObject(cloudAccountSession(value) as Object);
  }

  async clear(): Promise<void> {
    await this.store.clear();
  }
}

export class PendingSsoStore {
  private store: ChunkedAssetStore = new ChunkedAssetStore(
    't3-cloud-pending-sso-v2-manifest', 't3-cloud-pending-sso-v2-', 'T3 Connect 第三方登录状态');
  private legacy: SessionStore<PendingSsoSignIn> = new SessionStore<PendingSsoSignIn>('t3-cloud-pending-sso-v1');

  async load(): Promise<PendingSsoSignIn | undefined> {
    let raw = await this.store.loadObject();
    if (!raw) {
      const legacy = await this.legacy.load();
      if (legacy) raw = legacy as Object;
    }
    if (!raw) return undefined;
    try {
      const checked = pendingSsoSignIn(raw);
      if (Date.now() - checked.createdAt > PENDING_SSO_MAX_AGE_MS) {
        await this.clear();
        return undefined;
      }
      return checked;
    } catch (_) {
      await this.clear();
      return undefined;
    }
  }

  async save(value: PendingSsoSignIn): Promise<void> {
    await this.store.saveObject(pendingSsoSignIn(value as Object) as Object);
    try { await this.legacy.clear(); } catch (_) {}
  }

  async clear(): Promise<void> {
    await this.store.clear();
    try { await this.legacy.clear(); } catch (_) {}
  }
}

export class RelayTokenStore {
  private store: ChunkedAssetStore = new ChunkedAssetStore(
    't3-cloud-relay-token-v2-manifest', 't3-cloud-relay-token-v2-', 'T3 Connect 中继令牌');
  private legacy: SessionStore<RelayTokenCache> = new SessionStore<RelayTokenCache>('t3-cloud-relay-token-v1');

  async load(): Promise<RelayTokenCache | undefined> {
    const raw = await this.store.loadObject();
    if (raw) return relayTokenCache(raw);
    const legacy = await this.legacy.load();
    return legacy ? relayTokenCache(legacy as Object) : undefined;
  }

  async save(value: RelayTokenCache): Promise<void> {
    await this.store.saveObject(relayTokenCache(value as Object) as Object);
    try { await this.legacy.clear(); } catch (_) {}
  }

  async clear(): Promise<void> {
    await this.store.clear();
    try { await this.legacy.clear(); } catch (_) {}
  }
}

function encodedEnvironmentKey(environmentId: string): string {
  return base64UrlEncode(new util.TextEncoder().encodeInto(environmentId));
}

function legacyEnvironmentAlias(environmentId: string): string {
  return 't3-cloud-env-token-' + encodedEnvironmentKey(environmentId);
}

function environmentTokenChunkStore(environmentId: string): ChunkedAssetStore {
  const key = encodedEnvironmentKey(environmentId);
  return new ChunkedAssetStore('t3-ce-m-' + key, 't3-ce-c-' + key + '-', 'T3 Connect 环境令牌');
}

export class CloudEnvironmentTokenStore {
  async load(environmentId: string): Promise<CloudEnvironmentToken | undefined> {
    const raw = await environmentTokenChunkStore(environmentId).loadObject();
    if (raw) return cloudEnvironmentToken(raw);
    const legacy = await new SessionStore<CloudEnvironmentToken>(legacyEnvironmentAlias(environmentId)).load();
    return legacy ? cloudEnvironmentToken(legacy as Object) : undefined;
  }

  async save(value: CloudEnvironmentToken): Promise<void> {
    const checked = cloudEnvironmentToken(value as Object);
    await environmentTokenChunkStore(checked.environmentId).saveObject(checked as Object);
    try { await new SessionStore<CloudEnvironmentToken>(legacyEnvironmentAlias(checked.environmentId)).clear(); } catch (_) {}
  }

  async clear(environmentId: string): Promise<void> {
    await environmentTokenChunkStore(environmentId).clear();
    try { await new SessionStore<CloudEnvironmentToken>(legacyEnvironmentAlias(environmentId)).clear(); } catch (_) {}
  }
}
