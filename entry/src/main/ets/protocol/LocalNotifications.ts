export interface NotificationTarget { localId: string; environmentId: string; threadId: string; }
export interface NotificationRun { id: string; status: string; }
export const NOTIFICATION_ACTION = 'com.dasungta.lessagent.OPEN_THREAD_NOTIFICATION';

export function notificationTarget(value: Object): NotificationTarget {
  const row = value as Record<string, Object>;
  const keys = ['localId', 'environmentId', 'threadId'];
  if (!row || !keys.every(key => typeof row[key] === 'string' && /^[a-zA-Z0-9._:-]{1,256}$/.test(row[key] as string))) {
    throw new Error('通知目标无效');
  }
  return { localId: row.localId as string, environmentId: row.environmentId as string, threadId: row.threadId as string };
}
export function notificationTargetKey(target: NotificationTarget): string {
  return JSON.stringify([target.localId, target.environmentId, target.threadId]);
}
export function sameNotificationTarget(a: NotificationTarget, b: NotificationTarget): boolean {
  return notificationTargetKey(a) === notificationTargetKey(b);
}
export class RunNotificationTracker {
  private statuses: Map<string, string> = new Map();
  private key(target: NotificationTarget, runId: string): string {
    return notificationTargetKey(target) + ':' + runId;
  }
  private remember(key: string, status: string): void {
    if (this.statuses.size >= 2048 && !this.statuses.has(key)) {
      const first = this.statuses.keys().next();
      if (!first.done) this.statuses.delete(first.value);
    }
    this.statuses.set(key, status);
  }
  snapshot(target: NotificationTarget, runs: NotificationRun[]): void {
    notificationTarget(target);
    const prefix = notificationTargetKey(target) + ':';
    for (const key of this.statuses.keys()) {
      if (key.startsWith(prefix)) this.statuses.delete(key);
    }
    for (const run of runs) this.remember(this.key(target, run.id), run.status);
  }
  update(target: NotificationTarget, run: NotificationRun): boolean {
    notificationTarget(target);
    if (!run.id || run.id.length > 256) return false;
    const key = this.key(target, run.id);
    const before = this.statuses.get(key);
    this.remember(key, run.status);
    return before !== undefined && ['preparing', 'starting', 'running', 'waiting'].includes(before) &&
      ['completed', 'failed', 'interrupted'].includes(run.status);
  }
  clear(): void { this.statuses.clear(); }
}
