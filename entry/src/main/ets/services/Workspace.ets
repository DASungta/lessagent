import { util } from '@kit.ArkTS';
import { EnvironmentEntry } from '../protocol/Environment';
import { EnvironmentRegistry } from './EnvironmentRegistry';
import { T3Client } from './T3Client';
import {
  ProjectGroup, ScopedProject, ScopedThread, SnoozePresetSetting,
  cloneDestination, cloneDirectoryPath, inferProjectTitle, newProjectPathPreview, projectCreateCommand,
  projectDeleteCommand, projectUpdateCommand, resolveProjectPath, threadCommand,
  threadMetadataCommand, threadRegenerateCommand, threadMovePayload, threadView, ThreadView, topOfPinnedRun
} from '../protocol/Projects';

export interface UndoStep {
  action: string;
  orderKey: string;
  snoozedUntil: string;
  restoreUnsettledAt: string;
}

export interface WorkspaceUndo {
  label: string;
  thread: ScopedThread;
  kind: string;
  steps: UndoStep[];
}

export interface CloneView {
  projectId: string;
  remoteUrl: string;
  destinationPath: string;
  phase: string;
  stage: string;
  percent: number;
  detail: string;
  stalled: boolean;
  error: string;
}

export interface AddProjectEnvironment {
  localId: string;
  environmentId: string;
  label: string;
  platform: string;
  baseDirectory: string;
  newProjectsRoot: string;
  scratchWorkspaceRoot: string;
  ghqCloneLayout: boolean;
  ready: boolean;
  client: T3Client;
}

interface VisitExtra { visitedAt: string; opened: boolean; searchQuery?: string; }
interface UnsettleExtra { reason: string; restoreUnsettledAt?: string; }
interface SnoozeExtra { snoozedUntil: string; }
interface ReasonExtra { reason: string; }
interface OrderKeyExtra { orderKey?: string; }
interface AutoSettleExtra { enabled: boolean; }
interface CloneStartPayload {
  projectId: string; title: string; createdAt: string; remoteUrl: string; destinationPath: string;
}
interface TrackFolderEntryPayload { path: string; name: string; }
interface TrackFoldersPatchPayload { trackFolders: TrackFolderEntryPayload[]; }
interface UntrackFoldersPatchPayload { untrackFolders: string[]; }
interface PublishPayload { cwd: string; provider: string; repository: string; visibility: string; }
interface SearchPayload { query: string; limit: number; projectIds?: string[]; }
interface EmptyPayload { }

function commandId(): string { return util.generateRandomUUID(); }
function sleep(ms: number): Promise<void> { return new Promise<void>((resolve) => { setTimeout(resolve, ms); }); }

function optional(value: Object | undefined): string {
  return value === undefined || value === null || typeof value !== 'string' ? '' : value;
}

function record(value: Object): Record<string, Object> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) throw new Error('服务返回格式无效');
  return value as Record<string, Object>;
}

export class WorkspaceActions {
  private registry: EnvironmentRegistry;
  private pendingKeys: Set<string> = new Set();
  constructor(registry: EnvironmentRegistry) { this.registry = registry; }

  private client(localId: string): T3Client {
    const value = this.registry.clients.get(localId);
    if (!value?.ready) throw new Error('环境未连接，请先重试');
    return value;
  }
  private key(localId: string, target: string, action: string): string {
    return localId + ':' + target + ':' + action;
  }
  pending(key: string): boolean { return this.pendingKeys.has(key); }
  private async run<T>(key: string, action: () => Promise<T>): Promise<T> {
    if (this.pendingKeys.has(key)) throw new Error('该操作正在进行');
    this.pendingKeys.add(key);
    try { return await action(); }
    catch (error) {
      const message = (error as Error).message || '操作失败';
      if (/HTTP|WebSocket|超时|发送失败|连接已变更|服务端拒绝/.test(message)) {
        throw new Error(message + '；结果未确认，请刷新列表核对，不会自动重试');
      }
      throw error as Error;
    } finally { this.pendingKeys.delete(key); }
  }

  entries(): EnvironmentEntry[] {
    return this.registry.directory.entries.filter((entry: EnvironmentEntry) =>
      !entry.deleting && !entry.pendingBase && this.registry.entryVisible(entry));
  }
  addEnvironments(): AddProjectEnvironment[] {
    const result: AddProjectEnvironment[] = [];
    for (const entry of this.entries()) {
      const client = this.registry.clients.get(entry.localId);
      if (!client) continue;
      result.push({
        localId: entry.localId,
        environmentId: entry.environmentId,
        label: entry.label,
        platform: client.platform,
        baseDirectory: client.addProjectBaseDirectory,
        newProjectsRoot: client.newProjectsRoot,
        scratchWorkspaceRoot: client.scratchWorkspaceRoot,
        ghqCloneLayout: client.ghqCloneLayout,
        ready: client.canCreateProject(),
        client
      });
    }
    return result;
  }
  environment(environmentId: string): AddProjectEnvironment | undefined {
    return this.addEnvironments().find((entry: AddProjectEnvironment) => entry.environmentId === environmentId);
  }
  presets(localId: string): SnoozePresetSetting[] {
    return this.client(localId).snoozePresets;
  }

  async visit(thread: ScopedThread, opened: boolean, query: string = ''): Promise<void> {
    const client = this.client(thread.localId);
    if (!client.supports('threadVisitedTracking')) return;
    try {
      const extra: VisitExtra = { visitedAt: new Date().toISOString(), opened };
      if (query) extra.searchQuery = query;
      await client.dispatchCommand(threadCommand(commandId(), 'thread.visit', thread.id, extra));
    } catch (_) { /* Read tracking is best effort and must not block opening. */ }
  }
  async markUnread(thread: ScopedThread): Promise<void> {
    await this.run(this.key(thread.localId, thread.id, 'unread'), async () => {
      await this.client(thread.localId).dispatchCommand(threadCommand(commandId(), 'thread.mark-unread', thread.id));
    });
  }

  async archive(thread: ScopedThread): Promise<void> {
    await this.run(this.key(thread.localId, thread.id, 'archive'), async () => {
      await this.client(thread.localId).dispatchCommand(threadCommand(commandId(), 'thread.archive', thread.id));
    });
  }
  async unarchive(thread: ScopedThread): Promise<void> {
    await this.run(this.key(thread.localId, thread.id, 'unarchive'), async () => {
      await this.client(thread.localId).dispatchCommand(threadCommand(commandId(), 'thread.unarchive', thread.id));
    });
  }
  async deleteThread(thread: ScopedThread): Promise<void> {
    await this.run(this.key(thread.localId, thread.id, 'delete'), async () => {
      await this.client(thread.localId).dispatchCommand(threadCommand(commandId(), 'thread.delete', thread.id));
    });
  }
  async settle(thread: ScopedThread): Promise<WorkspaceUndo> {
    const undo = this.undoPlan('settle', thread);
    await this.run(this.key(thread.localId, thread.id, 'settle'), async () => {
      await this.client(thread.localId).dispatchCommand(threadCommand(commandId(), 'thread.settle', thread.id));
    });
    return undo;
  }
  async unsettle(thread: ScopedThread, restore: string = ''): Promise<void> {
    await this.run(this.key(thread.localId, thread.id, 'unsettle'), async () => {
      const extra: UnsettleExtra = { reason: 'user' };
      if (restore) extra.restoreUnsettledAt = restore;
      await this.client(thread.localId).dispatchCommand(threadCommand(commandId(), 'thread.unsettle', thread.id, extra));
    });
  }
  async snooze(thread: ScopedThread, snoozedUntil: string): Promise<void> {
    if (!Number.isFinite(Date.parse(snoozedUntil)) || Date.parse(snoozedUntil) <= Date.now()) {
      throw new Error('暂缓时间必须晚于现在');
    }
    await this.run(this.key(thread.localId, thread.id, 'snooze'), async () => {
      const extra: SnoozeExtra = { snoozedUntil };
      await this.client(thread.localId).dispatchCommand(threadCommand(commandId(), 'thread.snooze', thread.id, extra));
    });
  }
  async unsnooze(thread: ScopedThread): Promise<void> {
    await this.run(this.key(thread.localId, thread.id, 'unsnooze'), async () => {
      const extra: ReasonExtra = { reason: 'user' };
      await this.client(thread.localId).dispatchCommand(threadCommand(commandId(), 'thread.unsnooze', thread.id, extra));
    });
  }
  async pin(thread: ScopedThread, orderKey: string = ''): Promise<void> {
    await this.run(this.key(thread.localId, thread.id, 'pin'), async () => {
      const extra: OrderKeyExtra = {};
      if (orderKey) extra.orderKey = orderKey;
      await this.client(thread.localId).dispatchCommand(threadCommand(commandId(), 'thread.pin', thread.id, extra));
    });
  }
  async unpin(thread: ScopedThread): Promise<void> {
    await this.run(this.key(thread.localId, thread.id, 'unpin'), async () => {
      await this.client(thread.localId).dispatchCommand(threadCommand(commandId(), 'thread.unpin', thread.id));
    });
  }
  async setAutoSettle(thread: ScopedThread, enabled: boolean): Promise<void> {
    await this.run(this.key(thread.localId, thread.id, 'auto-settle'), async () => {
      const extra: AutoSettleExtra = { enabled };
      const client = this.client(thread.localId);
      await client.dispatchCommand(threadCommand(commandId(), 'thread.auto-settle.set', thread.id, extra));
      const value = enabled ? '' : new Date().toISOString();
      thread.autoSettleDisabledAt = value;
      const row = client.shell.threads.find((item: ThreadView) => item.id === thread.id);
      if (row) row.autoSettleDisabledAt = value;
    });
  }
  async rename(thread: ScopedThread, title: string): Promise<void> {
    const next = title.trim();
    if (!next) throw new Error('会话名称不能为空');
    if (next === thread.label) return;
    await this.run(this.key(thread.localId, thread.id, 'rename'), async () => {
      await this.client(thread.localId).dispatchCommand(threadMetadataCommand(commandId(), thread.id, next));
    });
  }
  async regenerateTitle(thread: ScopedThread): Promise<void> {
    if (thread.titleRegenerationRequestId) throw new Error('正在重生成会话名称');
    await this.run(this.key(thread.localId, thread.id, 'regenerate'), async () => {
      await this.client(thread.localId).dispatchCommand(threadRegenerateCommand(commandId(), thread.id));
    });
  }
  async move(thread: ScopedThread, ordered: ScopedThread[], up: boolean): Promise<void> {
    const section = thread.pinnedAt ? 'pinned' : 'active';
    const payload = threadMovePayload(ordered, thread, up, section);
    const type = section === 'pinned' ? 'thread.pin.reorder' : 'thread.active.reorder';
    await this.run(this.key(thread.localId, thread.id, 'move'), async () => {
      await this.client(thread.localId).dispatchCommand(threadCommand(commandId(), type, thread.id, payload));
    });
  }
  async turnIntoProject(thread: ScopedThread): Promise<void> {
    await this.run(this.key(thread.localId, thread.id, 'into-project'), async () => {
      await this.client(thread.localId).createProjectFromThread(thread.id);
    });
  }

  private settleUndo(thread: ScopedThread): UndoStep[] {
    const steps: UndoStep[] = [{ action: 'unsettle', restoreUnsettledAt: thread.unsettledAt,
      orderKey: '', snoozedUntil: '' }];
    if (thread.pinnedAt) steps.push({ action: 'pin', orderKey: thread.pinOrderKey, restoreUnsettledAt: '', snoozedUntil: '' });
    else if (thread.activeOrderKey) steps.push({ action: 'reorderActive', orderKey: thread.activeOrderKey, restoreUnsettledAt: '', snoozedUntil: '' });
    if (thread.snoozedUntil && Date.parse(thread.snoozedUntil) > Date.now()) {
      steps.push({ action: 'snooze', orderKey: '', restoreUnsettledAt: '', snoozedUntil: thread.snoozedUntil });
    }
    return steps;
  }
  undoPlan(kind: string, thread: ScopedThread): WorkspaceUndo {
    if (kind === 'snooze') {
      return { label: '已暂缓', thread, kind, steps: [{ action: 'unsnooze', orderKey: '', restoreUnsettledAt: '', snoozedUntil: '' }] };
    }
    if (kind === 'unpin') {
      const steps: UndoStep[] = [{ action: 'pin', orderKey: thread.pinOrderKey, restoreUnsettledAt: '', snoozedUntil: '' }];
      if (thread.snoozedUntil && Date.parse(thread.snoozedUntil) > Date.now()) {
        steps.push({ action: 'snooze', orderKey: '', restoreUnsettledAt: '', snoozedUntil: thread.snoozedUntil });
      }
      return { label: '已取消固定', thread, kind, steps };
    }
    return { label: '已 Settle', thread, kind: 'settle', steps: this.settleUndo(thread) };
  }
  async executeUndo(undo: WorkspaceUndo): Promise<void> {
    for (const step of undo.steps) {
      if (step.action === 'unsettle') await this.unsettle(undo.thread, step.restoreUnsettledAt);
      else if (step.action === 'unsnooze') await this.unsnooze(undo.thread);
      else if (step.action === 'pin') await this.pin(undo.thread, step.orderKey);
      else if (step.action === 'reorderActive') {
        await this.run(this.key(undo.thread.localId, undo.thread.id, 'move'), async () => {
          await this.client(undo.thread.localId).dispatchCommand(threadCommand(commandId(), 'thread.active.reorder', undo.thread.id,
            { orderKey: step.orderKey }));
        });
      } else if (step.action === 'snooze' && Date.parse(step.snoozedUntil) > Date.now()) {
        await this.snooze(undo.thread, step.snoozedUntil);
      }
    }
  }

  async updateProjects(projects: ScopedProject[], patch: Object): Promise<void> {
    for (const project of projects) {
      await this.run(this.key(project.localId, project.id, 'project-update'), async () => {
        await this.client(project.localId).projectMutate(projectUpdateCommand(commandId(), project.id, patch));
      });
    }
  }
  async trackProjectFolder(project: ScopedProject, folderPath: string, name: string): Promise<void> {
    const cleanPath = resolveProjectPath(folderPath, this.client(project.localId).platform);
    const cleanName = (name.trim() || inferProjectTitle(cleanPath)).slice(0, 128);
    if (!cleanName) throw new Error('请输入仓库名称');
    const patch: TrackFoldersPatchPayload = { trackFolders: [{ path: cleanPath, name: cleanName }] };
    await this.run(this.key(project.localId, project.id, 'project-track:' + cleanPath), async () => {
      await this.client(project.localId).projectMutate(projectUpdateCommand(commandId(), project.id, patch));
    });
  }
  async untrackProjectFolder(project: ScopedProject, folderPath: string): Promise<void> {
    const cleanPath = folderPath.trim();
    if (!cleanPath) throw new Error('缺少目录路径');
    const patch: UntrackFoldersPatchPayload = { untrackFolders: [cleanPath] };
    await this.run(this.key(project.localId, project.id, 'project-untrack:' + cleanPath), async () => {
      await this.client(project.localId).projectMutate(projectUpdateCommand(commandId(), project.id, patch));
    });
  }
  async deleteProject(project: ScopedProject): Promise<void> {
    await this.run(this.key(project.localId, project.id, 'project-delete'), async () => {
      await this.client(project.localId).projectMutate(projectDeleteCommand(commandId(), project.id));
    });
  }
  async createProject(environment: AddProjectEnvironment, workspaceRoot: string, projectId: string = ''): Promise<string> {
    const path = resolveProjectPath(workspaceRoot, environment.platform);
    const id = projectId || util.generateRandomUUID();
    await this.run(this.key(environment.localId, id, 'project-create'), async () => {
      await this.client(environment.localId).projectMutate(projectCreateCommand(commandId(), id, path));
    });
    return id;
  }
  async createNewProject(environment: AddProjectEnvironment, name: string): Promise<Record<string, Object>> {
    if (!environment.newProjectsRoot) throw new Error('此环境未配置新项目目录');
    const trimmed = name.trim();
    if (!trimmed) throw new Error('请输入项目名称');
    return this.run(this.key(environment.localId, 'new-project', 'create'), async () => {
      return record(await this.client(environment.localId).createNewProject(trimmed));
    });
  }
  async ensureScratch(environment: AddProjectEnvironment): Promise<string> {
    const result = await this.run(this.key(environment.localId, 'scratch', 'open'), async () => {
      return record(await this.client(environment.localId).ensureScratch());
    });
    return optional(result.projectId);
  }
  async startClone(environment: AddProjectEnvironment, remoteUrl: string, destinationPath: string,
    title: string, projectId: string = ''): Promise<string> {
    const id = projectId || util.generateRandomUUID();
    const path = resolveProjectPath(destinationPath, environment.platform);
    await this.run(this.key(environment.localId, id, 'clone'), async () => {
      const payload: CloneStartPayload = {
        projectId: id, title, createdAt: new Date().toISOString(), remoteUrl, destinationPath: path
      };
      await this.client(environment.localId).startProjectClone(payload);
    });
    return id;
  }
  async publish(environment: AddProjectEnvironment, cwd: string, provider: string, repository: string): Promise<void> {
    const payload: PublishPayload = { cwd, provider, repository, visibility: 'private' };
    await this.client(environment.localId).publishRepository(payload);
  }
  async waitForProject(environment: AddProjectEnvironment, projectId: string, timeoutMs: number = 15000): Promise<boolean> {
    const until = Date.now() + timeoutMs;
    while (Date.now() < until) {
      if (this.client(environment.localId).shell.projects.some((project) => project.id === projectId)) return true;
      await sleep(300);
    }
    return false;
  }

  async search(environments: EnvironmentEntry[], query: string, projectIds: string[]): Promise<Record<string, string>> {
    const result: Record<string, string> = {};
    const trimmed = query.trim().slice(0, 200);
    if (trimmed.length < 2) return result;
    await Promise.all(environments.map(async (entry: EnvironmentEntry) => {
      const client = this.registry.clients.get(entry.localId);
      if (!client?.ready) return;
      try {
        const payload: SearchPayload = { query: trimmed, limit: 50 };
        if (projectIds.length) payload.projectIds = projectIds;
        const value = record(await client.searchThreads(payload));
        for (const match of (value.matches as Object[]) || []) {
          const row = record(match);
          const threadId = optional(row.threadId);
          const snippet = optional(row.snippet);
          if (threadId && snippet) result[entry.localId + ':' + threadId] = snippet;
        }
        if (Array.isArray(value.threads)) {
          for (const thread of value.threads as Object[]) {
            const row = threadView(thread);
            const existing = client.shell.threads.findIndex((item: ThreadView) => item.id === row.id);
            if (existing < 0) client.shell.threads.push(row); else client.shell.threads[existing] = row;
            result[entry.localId + ':' + row.id] = result[entry.localId + ':' + row.id] || '';
          }
        }
      } catch (_) { /* Search is an enhancement; the local title/project filter remains. */ }
    }));
    return result;
  }

  async archiveSnapshot(entries: EnvironmentEntry[]): Promise<Record<string, Object>> {
    const result: Record<string, Object> = {};
    await Promise.all(entries.map(async (entry: EnvironmentEntry) => {
      const client = this.registry.clients.get(entry.localId);
      if (!client?.ready) return;
      try { result[entry.localId] = await client.archivedShellSnapshot(); } catch (_) {}
    }));
    return result;
  }

  watchClones(environment: AddProjectEnvironment, update: (clones: CloneView[]) => void): (value: Object) => void {
    const callback = (value: Object): void => {
      if (!Array.isArray(value)) return;
      const rows = value as Object[];
      const clones: CloneView[] = [];
      for (const item of rows) {
        const row = record(item);
        clones.push({
          projectId: optional(row.projectId), remoteUrl: optional(row.remoteUrl),
          destinationPath: optional(row.destinationPath), phase: optional(row.phase),
          stage: optional(row.stage), percent: typeof row.percent === 'number' ? row.percent as number : 0,
          detail: optional(row.detail), stalled: row.stalled === true, error: optional(row.error)
        });
      }
      update(clones);
    };
    const payload: EmptyPayload = {};
    return this.client(environment.localId).watchRpcStream('subscribeProjectClones', payload, callback);
  }

  newProjectPreview(environment: AddProjectEnvironment, name: string): string {
    return newProjectPathPreview(environment.newProjectsRoot, name);
  }
  cloneDestination(environment: AddProjectEnvironment, base: string, remoteUrl: string): string {
    return cloneDestination(base, cloneDirectoryPath(remoteUrl, environment.ghqCloneLayout));
  }
}
