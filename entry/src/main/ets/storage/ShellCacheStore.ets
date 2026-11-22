import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CachedShellEntry, cachedShellEntry } from '../protocol/Core';
import { record } from '../protocol/Wire';

export interface ShellCacheStorage {
  loadAll(): Promise<Record<string, CachedShellEntry>>;
  saveAll(entries: Record<string, CachedShellEntry>): Promise<void>;
}

interface ShellCacheFile {
  version: number;
  entries: Record<string, CachedShellEntry>;
}

const SHELL_CACHE_VERSION = 1;
const SHELL_CACHE_MAX_AGE_MS = 7 * 24 * 60 * 60 * 1000;
const SHELL_CACHE_MAX_BYTES = 4 * 1024 * 1024;
const SHELL_CACHE_MAX_THREADS_PER_ENV = 400;

function trimEntry(entry: CachedShellEntry): CachedShellEntry {
  const threads = entry.threads.length > SHELL_CACHE_MAX_THREADS_PER_ENV
    ? entry.threads.slice(0, SHELL_CACHE_MAX_THREADS_PER_ENV)
    : entry.threads.slice();
  return {
    environmentId: entry.environmentId,
    savedAt: entry.savedAt,
    scratchWorkspaceRoot: entry.scratchWorkspaceRoot,
    capabilities: entry.capabilities,
    projects: entry.projects.slice(),
    threads
  };
}

// Non-secret UI shell snapshots only (projects + thread list metadata); never stores credentials or prompts.
export class ShellCacheStore implements ShellCacheStorage {
  private path: string;
  constructor(filesDir: string) { this.path = filesDir + '/shell-cache-v1.json'; }

  async loadAll(): Promise<Record<string, CachedShellEntry>> {
    const result: Record<string, CachedShellEntry> = {};
    let raw = '';
    try {
      raw = fileIo.readTextSync(this.path);
    } catch (error) {
      if ((error as BusinessError).code === 13900002) return result;
      return result;
    }
    try {
      const parsed = record(JSON.parse(raw) as Object);
      if (parsed.version !== SHELL_CACHE_VERSION || parsed.entries === undefined || parsed.entries === null) {
        return result;
      }
      const entries = record(parsed.entries);
      const now = Date.now();
      for (const localId of Object.keys(entries)) {
        if (!/^[a-zA-Z0-9-]{1,64}$/.test(localId)) continue;
        try {
          const entry = cachedShellEntry(entries[localId]);
          const age = now - entry.savedAt;
          if (age >= -60000 && age <= SHELL_CACHE_MAX_AGE_MS) {
            result[localId] = entry;
          }
        } catch (_) {
          // Drop malformed individual cache record without discarding other environments.
        }
      }
      return result;
    } catch (_) {
      // Corrupt cache must never block startup; remove it quietly.
      try { fileIo.unlinkSync(this.path); } catch (_) {}
      return result;
    }
  }

  async saveAll(entries: Record<string, CachedShellEntry>): Promise<void> {
    const sanitized: Record<string, CachedShellEntry> = {};
    for (const localId of Object.keys(entries)) {
      if (!/^[a-zA-Z0-9-]{1,64}$/.test(localId)) continue;
      try {
        sanitized[localId] = trimEntry(cachedShellEntry(entries[localId] as Object));
      } catch (_) {}
    }
    const payload: ShellCacheFile = { version: SHELL_CACHE_VERSION, entries: sanitized };
    const content = JSON.stringify(payload);
    if (content.length > SHELL_CACHE_MAX_BYTES) return;
    const temporary = this.path + '.tmp';
    const file = fileIo.openSync(temporary, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, content);
      fileIo.fsyncSync(file.fd);
    } finally { fileIo.closeSync(file); }
    fileIo.renameSync(temporary, this.path);
  }
}
