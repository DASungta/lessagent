import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { SessionStore } from '../storage/SessionStore';
import {
  base64UrlDecode, base64UrlEncode, checkedDpopPublicJwk, DpopPublicJwk, dpopHeader, dpopPayload, dpopProof,
  dpopPublicJwk, dpopSigningInput, dpopThumbprintInput, rawEccSignature
} from '../protocol/Cloud';

interface StoredDpopKey {
  version: number;
  publicDer: string;
  privateDer: string;
  publicJwk: DpopPublicJwk;
  thumbprint: string;
}

function encoded(value: cryptoFramework.DataBlob): Uint8Array {
  if (!value.data || value.data.length === 0) throw new Error('系统未返回 DPoP 密钥编码');
  return value.data;
}

function publicPoint(der: Uint8Array): Uint8Array {
  if (der.length < 65) throw new Error('DPoP 公钥 DER 无效');
  const point = der.slice(der.length - 65);
  if (point[0] !== 0x04) throw new Error('DPoP 公钥不是未压缩 P-256 点');
  return point;
}

function base64(value: Uint8Array): string {
  return new util.Base64Helper().encodeToStringSync(value, util.Type.BASIC);
}

function bytes(value: string): Uint8Array {
  return new util.Base64Helper().decodeSync(value, util.Type.BASIC);
}

function utf8(value: string): Uint8Array {
  return new util.TextEncoder().encodeInto(value);
}

class DpopKeyPair {
  pair: cryptoFramework.KeyPair;
  publicJwk: DpopPublicJwk;
  thumbprint: string;
  constructor(pair: cryptoFramework.KeyPair, publicJwk: DpopPublicJwk, thumbprint: string) {
    this.pair = pair; this.publicJwk = publicJwk; this.thumbprint = thumbprint;
  }
}

// P-256 key lives in the device-unlocked Asset store; signing stays in CryptoFramework.
export class DpopSigner {
  private store: SessionStore<StoredDpopKey> = new SessionStore<StoredDpopKey>('t3-cloud-dpop-key-v1');
  private loaded: DpopKeyPair | undefined = undefined;
  private loading: Promise<DpopKeyPair> | undefined = undefined;

  private async digest(value: Uint8Array): Promise<Uint8Array> {
    const md = cryptoFramework.createMd('SHA256');
    await md.update({ data: value });
    return encoded(await md.digest());
  }

  async sha256Base64Url(value: string): Promise<string> {
    return base64UrlEncode(await this.digest(utf8(value)));
  }

  private async signRaw(pair: cryptoFramework.KeyPair, value: string): Promise<Uint8Array> {
    const signer = cryptoFramework.createSign('ECC256|SHA256');
    await signer.init(pair.priKey);
    const signature = encoded(await signer.sign({ data: utf8(value) }));
    return rawEccSignature(signature);
  }

  private async selfCheck(pair: cryptoFramework.KeyPair): Promise<void> {
    const challenge = 't3-code-dpop-key-self-check';
    const signature = await this.signRaw(pair, challenge);
    const verifier = cryptoFramework.createVerify('ECC256|SHA256');
    await verifier.init(pair.pubKey);
    const der = rawToDerForCheck(signature);
    if (!await verifier.verify({ data: utf8(challenge) }, { data: der })) throw new Error('DPoP 私钥与公钥不匹配');
  }

  private async generate(): Promise<DpopKeyPair> {
    const generator = cryptoFramework.createAsyKeyGenerator('ECC256');
    const pair = await generator.generateKeyPair();
    const point = publicPoint(encoded(pair.pubKey.getEncoded()));
    const publicJwk = dpopPublicJwk(point.slice(1, 33), point.slice(33, 65));
    const thumbprint = base64UrlEncode(await this.digest(utf8(dpopThumbprintInput(publicJwk))));
    await this.selfCheck(pair);
    const stored: StoredDpopKey = {
      version: 1,
      publicDer: base64(encoded(pair.pubKey.getEncoded())),
      privateDer: base64(encoded(pair.priKey.getEncoded())),
      publicJwk,
      thumbprint
    };
    await this.store.save(stored);
    return new DpopKeyPair(pair, publicJwk, thumbprint);
  }

  private async load(): Promise<DpopKeyPair> {
    const stored = await this.store.load();
    if (!stored) return this.generate();
    try {
      if (stored.version !== 1) throw new Error('version');
      const publicJwk = checkedDpopPublicJwk(stored.publicJwk as Object);
      const generator = cryptoFramework.createAsyKeyGenerator('ECC256');
      const pair = await generator.convertKey({ data: bytes(stored.publicDer) }, { data: bytes(stored.privateDer) });
      const point = publicPoint(encoded(pair.pubKey.getEncoded()));
      const derived = dpopPublicJwk(point.slice(1, 33), point.slice(33, 65));
      if (derived.x !== publicJwk.x || derived.y !== publicJwk.y) throw new Error('pair');
      const thumbprint = base64UrlEncode(await this.digest(utf8(dpopThumbprintInput(publicJwk))));
      if (thumbprint !== stored.thumbprint) throw new Error('thumbprint');
      await this.selfCheck(pair);
      return new DpopKeyPair(pair, publicJwk, thumbprint);
    } catch (_) {
      // Do not rotate silently: a new key would orphan existing host approvals and token bindings.
      throw new Error('系统安全存储中的 DPoP 密钥已损坏；请先重置 T3 Connect 设备密钥');
    }
  }

  async ready(): Promise<DpopKeyPair> {
    if (this.loaded) return this.loaded;
    if (!this.loading) this.loading = this.load().then((value: DpopKeyPair) => {
      this.loaded = value; this.loading = undefined; return value;
    }).catch((error: Error) => {
      this.loading = undefined; throw error;
    });
    return this.loading as Promise<DpopKeyPair>;
  }

  async thumbprint(): Promise<string> {
    return (await this.ready()).thumbprint;
  }

  async publicJwk(): Promise<DpopPublicJwk> {
    return (await this.ready()).publicJwk;
  }

  async prove(method: string, target: string, accessToken?: string): Promise<string> {
    const pair = await this.ready();
    const ath = accessToken === undefined ? undefined : await this.sha256Base64Url(accessToken);
    const header = dpopHeader(pair.publicJwk);
    const payload = dpopPayload(method, target, util.generateRandomUUID(),
      Math.floor(Date.now() / 1000), ath);
    const input = dpopSigningInput(header, payload);
    return dpopProof(input, await this.signRaw(pair.pair, input));
  }

  async verifyProof(proof: string): Promise<boolean> {
    const parts = proof.split('.');
    if (parts.length !== 3) return false;
    const pair = await this.ready();
    const verifier = cryptoFramework.createVerify('ECC256|SHA256');
    await verifier.init(pair.pair.pubKey);
    const signature = rawToDerForCheck(base64UrlDecode(parts[2]));
    return verifier.verify({ data: utf8(parts[0] + '.' + parts[1]) }, { data: signature });
  }

  async reset(): Promise<void> {
    this.loaded = undefined;
    await this.store.clear();
  }
}

// CryptoFramework verify expects DER; the proof builder above always exposes raw r‖s.
function rawToDerForCheck(raw: Uint8Array): Uint8Array {
  if (raw.length !== 64) throw new Error('DPoP 签名长度无效');
  const join = (parts: Uint8Array[]): Uint8Array => {
    const length = parts.reduce((total: number, part: Uint8Array) => total + part.length, 0);
    const result = new Uint8Array(length);
    let offset = 0;
    for (const part of parts) { result.set(part, offset); offset += part.length; }
    return result;
  };
  const integer = (value: Uint8Array): Uint8Array => {
    let start = 0;
    while (start < value.length - 1 && value[start] === 0) start++;
    const trimmed = value.slice(start);
    const header = (trimmed[0] & 0x80) === 0 ? Uint8Array.from([0x02, trimmed.length]) :
      Uint8Array.from([0x02, trimmed.length + 1, 0]);
    return join([header, trimmed]);
  };
  const r = integer(raw.slice(0, 32));
  const s = integer(raw.slice(32, 64));
  return join([Uint8Array.from([0x30, r.length + s.length]), r, s]);
}

export const dpopSigner: DpopSigner = new DpopSigner();
