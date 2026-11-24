import { fileIo } from '@kit.CoreFileKit';
import { CloudConfigOverride, parseCloudConfigOverride } from '../protocol/Cloud';

function writeTextAtomic(path: string, content: string): void {
  const temp = path + '.tmp';
  const file = fileIo.openSync(temp, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
  try {
    fileIo.writeSync(file.fd, content);
    fileIo.fsyncSync(file.fd);
  } finally {
    fileIo.closeSync(file);
  }
  fileIo.renameSync(temp, path);
}

// Public non-secret deployment override (Relay URL, Clerk Publishable Key, JWT template).
export class CloudConfigOverrideStore {
  private path: string;
  constructor(filesDir: string) {
    this.path = filesDir + '/t3-cloud-config-override.json';
  }

  load(): CloudConfigOverride | undefined {
    try {
      const raw = fileIo.readTextSync(this.path);
      if (!raw.trim()) return undefined;
      return parseCloudConfigOverride(JSON.parse(raw) as Object);
    } catch (_) {
      return undefined;
    }
  }

  save(value: CloudConfigOverride): CloudConfigOverride {
    const checked = parseCloudConfigOverride(value as Object);
    writeTextAtomic(this.path, JSON.stringify(checked));
    return checked;
  }

  clear(): void {
    try { fileIo.unlinkSync(this.path); } catch (_) {}
  }
}

// Tracks per-account "Don't show T3 Connect onboarding again" opt-outs.
export class CloudOnboardingStore {
  private path: string;
  constructor(filesDir: string) {
    this.path = filesDir + '/t3-cloud-onboarding-optout.json';
  }

  private loadIds(): string[] {
    try {
      const raw = fileIo.readTextSync(this.path);
      const parsed = JSON.parse(raw) as Object;
      if (!Array.isArray(parsed)) return [];
      const ids: string[] = [];
      for (const item of parsed as Object[]) {
        if (typeof item === 'string' && item.trim() && !ids.includes(item.trim())) ids.push(item.trim());
      }
      return ids;
    } catch (_) {
      return [];
    }
  }

  isOptedOut(accountId: string): boolean {
    if (!accountId.trim()) return false;
    return this.loadIds().includes(accountId.trim());
  }

  optOut(accountId: string): void {
    const trimmed = accountId.trim();
    if (!trimmed) return;
    const ids = this.loadIds();
    if (!ids.includes(trimmed)) {
      ids.push(trimmed);
      writeTextAtomic(this.path, JSON.stringify(ids.slice(-32)));
    }
  }
}
