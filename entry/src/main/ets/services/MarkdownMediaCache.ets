import { ResolvedMarkdownMedia } from '../protocol/Markdown';

const EXPIRY_MARGIN_MS = 60000;
const MAX_CACHE_ENTRIES = 200;

interface CachedMediaEntry {
  generation: number;
  value: ResolvedMarkdownMedia;
}

/**
 * In-memory cache & concurrent-request deduplicator for resolved Markdown media URLs.
 * Entries are scoped by connection generation, thread, workspace and authored source,
 * automatically expire before the server HMAC token expires, and never cache failures.
 */
export class MarkdownMediaCache {
  private entries: Map<string, CachedMediaEntry> = new Map<string, CachedMediaEntry>();
  private inFlight: Map<string, Promise<ResolvedMarkdownMedia>> = new Map<string, Promise<ResolvedMarkdownMedia>>();

  key(generation: number, threadId: string, cwd: string, source: string): string {
    return String(generation) + '\0' + threadId + '\0' + cwd + '\0' + source;
  }

  peek(key: string, now: number = Date.now()): ResolvedMarkdownMedia | undefined {
    const entry = this.entries.get(key);
    if (!entry) return undefined;
    if (entry.value.expiresAt > 0 && entry.value.expiresAt - EXPIRY_MARGIN_MS <= now) {
      this.entries.delete(key);
      return undefined;
    }
    return entry.value;
  }

  async resolve(generation: number, key: string, fetcher: () => Promise<ResolvedMarkdownMedia>,
    refresh: boolean = false, now: number = Date.now()): Promise<ResolvedMarkdownMedia> {
    if (!refresh) {
      const cached = this.peek(key, now);
      if (cached) return cached;
      const pending = this.inFlight.get(key);
      if (pending) return pending;
    }
    const request = fetcher().then((result: ResolvedMarkdownMedia): ResolvedMarkdownMedia => {
      if (this.inFlight.get(key) === request) this.inFlight.delete(key);
      if (result.url) {
        this.entries.delete(key);
        this.entries.set(key, { generation, value: result });
        while (this.entries.size > MAX_CACHE_ENTRIES) {
          const oldest = this.entries.keys().next();
          if (oldest.done) break;
          this.entries.delete(oldest.value);
        }
      }
      return result;
    }, (error: Error): never => {
      if (this.inFlight.get(key) === request) this.inFlight.delete(key);
      throw error;
    });
    if (!refresh) this.inFlight.set(key, request);
    return request;
  }

  pruneGeneration(currentGeneration: number): void {
    const stale: string[] = [];
    this.entries.forEach((entry: CachedMediaEntry, key: string) => {
      if (entry.generation !== currentGeneration) stale.push(key);
    });
    for (const key of stale) this.entries.delete(key);
  }

  clear(): void {
    this.entries.clear();
    this.inFlight.clear();
  }
}
