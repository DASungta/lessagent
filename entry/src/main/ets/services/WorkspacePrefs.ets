import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import type { ThreadProjectRef } from '../protocol/Projects';
import { DEFAULT_TERMINAL_FONT_SIZE, validTerminalFontSize } from '../protocol/Terminal';

export const DEFAULT_CODE_FONT_SIZE = 13;
export const MIN_CODE_FONT_SIZE = 8;
export const MAX_CODE_FONT_SIZE = 18;

export interface WorkspacePreferences {
  schemaVersion: number;
  projectGroupingMode: string;
  environmentFilter: string;
  projectFilterKey: string;
  projectFilterGroupingMode?: string;
  threadSortOrder: string;
  archivedSortOrder: string;
  workingShelfEnabled: boolean;
  useLastProjectForNewThreads: boolean;
  lastThreadProject?: ThreadProjectRef;
  workingShelfExpanded: boolean;
  snoozedShelfExpanded: boolean;
  settledShelfExpanded: boolean;
  followUpBehavior: string;
  terminalFontSize: number;
  codeFontSize: number | null;
  codeWordBreak: boolean;
  pullRequestHideTestFiles: boolean;
  sideThreadOpenTarget: string;
}

export function defaultWorkspacePreferences(): WorkspacePreferences {
  return {
    schemaVersion: 1, projectGroupingMode: 'repository', environmentFilter: '', projectFilterKey: '',
    threadSortOrder: 'updated_at', archivedSortOrder: 'newest', workingShelfEnabled: true,
    useLastProjectForNewThreads: true,
    workingShelfExpanded: false, snoozedShelfExpanded: false, settledShelfExpanded: true, followUpBehavior: 'steer', terminalFontSize: DEFAULT_TERMINAL_FONT_SIZE, codeFontSize: null, codeWordBreak: false, pullRequestHideTestFiles: false, sideThreadOpenTarget: 'panel'
  };
}

function threadProjectRef(value: Object | undefined): ThreadProjectRef | undefined {
  if (value === undefined || value === null || typeof value !== 'object' || Array.isArray(value)) return undefined;
  const project = value as Record<string, Object>;
  const environmentId = project.environmentId;
  const projectId = project.projectId;
  if (typeof environmentId !== 'string' || !environmentId.trim() || environmentId.length > 256 ||
    typeof projectId !== 'string' || !projectId.trim() || projectId.length > 256) return undefined;
  return { environmentId, projectId };
}

export function workspacePreferences(value: Object): WorkspacePreferences {
  const row = value as Record<string, Object>;
  if (row === null || typeof row !== 'object' || Array.isArray(value) || row.schemaVersion !== 1) {
    throw new Error('R3 偏好版本无效');
  }
  const mode = typeof row.projectGroupingMode === 'string' ? row.projectGroupingMode : '';
  if (!['repository', 'repository_path', 'separate'].includes(mode)) throw new Error('项目分组方式无效');
  const sort = typeof row.threadSortOrder === 'string' ? row.threadSortOrder : '';
  if (!['updated_at', 'created_at'].includes(sort)) throw new Error('会话排序方式无效');
  const archived = typeof row.archivedSortOrder === 'string' ? row.archivedSortOrder : '';
  if (!['newest', 'oldest'].includes(archived)) throw new Error('归档排序方式无效');
  const env = typeof row.environmentFilter === 'string' ? row.environmentFilter : '';
  const project = typeof row.projectFilterKey === 'string' ? row.projectFilterKey : '';
  const filterMode = typeof row.projectFilterGroupingMode === 'string' &&
    ['repository', 'repository_path', 'separate'].includes(row.projectFilterGroupingMode) ? row.projectFilterGroupingMode : mode;
  if (env.length > 256 || project.length > 512) throw new Error('列表过滤条件无效');
  const followUp = row.followUpBehavior === undefined ? 'steer' : row.followUpBehavior;
  if (followUp !== 'queue' && followUp !== 'steer') throw new Error('后续消息方式无效');
  const sideTarget = row.sideThreadOpenTarget === undefined ? 'panel' : row.sideThreadOpenTarget;
  if (sideTarget !== 'panel' && sideTarget !== 'main') throw new Error('子会话打开方式无效');
  return {
    schemaVersion: 1, projectGroupingMode: mode, environmentFilter: env, projectFilterKey: project,
    projectFilterGroupingMode: project ? filterMode : undefined,
    threadSortOrder: sort, archivedSortOrder: archived,
    workingShelfEnabled: row.workingShelfEnabled !== false,
    useLastProjectForNewThreads: row.useLastProjectForNewThreads !== false,
    lastThreadProject: threadProjectRef(row.lastThreadProject),
    workingShelfExpanded: row.workingShelfExpanded === true,
    snoozedShelfExpanded: row.snoozedShelfExpanded === true,
    settledShelfExpanded: row.settledShelfExpanded !== false,
    followUpBehavior: followUp as string,
    terminalFontSize: validTerminalFontSize(row.terminalFontSize) ? row.terminalFontSize as number : DEFAULT_TERMINAL_FONT_SIZE,
    codeFontSize: typeof row.codeFontSize === 'number' && Number.isFinite(row.codeFontSize)
      ? Math.min(MAX_CODE_FONT_SIZE, Math.max(MIN_CODE_FONT_SIZE, Math.round(row.codeFontSize))) : null,
    codeWordBreak: row.codeWordBreak === true,
    pullRequestHideTestFiles: row.pullRequestHideTestFiles === true,
    sideThreadOpenTarget: sideTarget as string
  };
}

export class WorkspacePrefsStore {
  private path: string;
  constructor(filesDir: string) { this.path = filesDir + '/r3-preferences.json'; }
  async load(): Promise<WorkspacePreferences> {
    try {
      return workspacePreferences(JSON.parse(fileIo.readTextSync(this.path)) as Object);
    } catch (error) {
      if ((error as BusinessError).code === 13900002) return defaultWorkspacePreferences();
      throw new Error('R3 偏好记录不可读或损坏，已使用默认值');
    }
  }
  async save(value: WorkspacePreferences): Promise<void> {
    const checked = workspacePreferences(value);
    const content = JSON.stringify(checked);
    const temporary = this.path + '.tmp';
    const file = fileIo.openSync(temporary, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, content);
      fileIo.fsyncSync(file.fd);
    } finally { fileIo.closeSync(file); }
    if (fileIo.readTextSync(temporary) !== content) throw new Error('R3 偏好回读校验失败');
    fileIo.renameSync(temporary, this.path);
  }
}

export let workspacePrefs: WorkspacePreferences = defaultWorkspacePreferences();
export let workspacePrefsStore: WorkspacePrefsStore | undefined = undefined;

export async function prepareWorkspacePreferences(filesDir: string): Promise<void> {
  workspacePrefsStore = new WorkspacePrefsStore(filesDir);
  try { workspacePrefs = await workspacePrefsStore.load(); }
  catch (_) { workspacePrefs = defaultWorkspacePreferences(); }
  AppStorage.setOrCreate('t3CodeFontSize', effectiveCodeFontSize());
  AppStorage.setOrCreate('t3CodeWordBreak', workspacePrefs.codeWordBreak);
  AppStorage.setOrCreate('t3HideTestFiles', workspacePrefs.pullRequestHideTestFiles);
}

export function saveWorkspacePreferences(): void {
  if (!workspacePrefsStore) return;
  const snapshot = workspacePreferences(JSON.parse(JSON.stringify(workspacePrefs)) as Object);
  void workspacePrefsStore.save(snapshot).catch(() => {});
}

export async function setFollowUpBehavior(value: string): Promise<void> {
  if (!['queue', 'steer'].includes(value)) throw new Error('后续消息方式无效');
  if (!workspacePrefsStore) throw new Error('设置尚未初始化');
  const snapshot = workspacePreferences(JSON.parse(JSON.stringify(workspacePrefs)) as Object);
  snapshot.followUpBehavior = value;
  await workspacePrefsStore.save(snapshot);
  workspacePrefs.followUpBehavior = value;
}

export async function setWorkingShelfEnabled(value: boolean): Promise<void> {
  if (!workspacePrefsStore) throw new Error('设置尚未初始化');
  const snapshot = workspacePreferences(JSON.parse(JSON.stringify(workspacePrefs)) as Object);
  snapshot.workingShelfEnabled = value;
  await workspacePrefsStore.save(snapshot);
  workspacePrefs.workingShelfEnabled = value;
}

export async function setUseLastProjectForNewThreads(value: boolean): Promise<void> {
  if (!workspacePrefsStore) throw new Error('设置尚未初始化');
  const snapshot = workspacePreferences(JSON.parse(JSON.stringify(workspacePrefs)) as Object);
  snapshot.useLastProjectForNewThreads = value;
  await workspacePrefsStore.save(snapshot);
  workspacePrefs.useLastProjectForNewThreads = value;
}

export function rememberThreadProject(project: ThreadProjectRef): void {
  const next = threadProjectRef(project);
  const current = workspacePrefs.lastThreadProject;
  if (!next || (current?.environmentId === next.environmentId && current.projectId === next.projectId)) return;
  workspacePrefs.lastThreadProject = next;
  saveWorkspacePreferences();
}

export async function setTerminalFontSize(value: number): Promise<void> {
  if (!validTerminalFontSize(value)) throw new Error('终端字号无效');
  if (!workspacePrefsStore) throw new Error('设置尚未初始化');
  const snapshot = workspacePreferences(JSON.parse(JSON.stringify(workspacePrefs)) as Object);
  snapshot.terminalFontSize = value;
  await workspacePrefsStore.save(snapshot);
  workspacePrefs.terminalFontSize = value;
}

export function effectiveCodeFontSize(): number { return workspacePrefs.codeFontSize ?? DEFAULT_CODE_FONT_SIZE; }

export async function setCodeFontSize(value: number | null): Promise<void> {
  if (value !== null && (!Number.isInteger(value) || value < MIN_CODE_FONT_SIZE || value > MAX_CODE_FONT_SIZE)) {
    throw new Error('代码字号无效');
  }
  if (!workspacePrefsStore) throw new Error('设置尚未初始化');
  const snapshot = workspacePreferences(JSON.parse(JSON.stringify(workspacePrefs)) as Object);
  snapshot.codeFontSize = value;
  await workspacePrefsStore.save(snapshot);
  workspacePrefs.codeFontSize = value;
  AppStorage.setOrCreate('t3CodeFontSize', effectiveCodeFontSize());
}

export async function setCodeWordBreak(value: boolean): Promise<void> {
  if (typeof value !== 'boolean') throw new Error('代码换行设置无效');
  if (!workspacePrefsStore) throw new Error('设置尚未初始化');
  const snapshot = workspacePreferences(JSON.parse(JSON.stringify(workspacePrefs)) as Object);
  snapshot.codeWordBreak = value;
  await workspacePrefsStore.save(snapshot);
  workspacePrefs.codeWordBreak = value;
  AppStorage.setOrCreate('t3CodeWordBreak', value);
}

export async function setPullRequestHideTestFiles(value: boolean): Promise<void> {
  if (typeof value !== 'boolean') throw new Error('测试文件筛选设置无效');
  if (!workspacePrefsStore) {
    workspacePrefs.pullRequestHideTestFiles = value;
    AppStorage.setOrCreate('t3HideTestFiles', value);
    return;
  }
  const snapshot = workspacePreferences(JSON.parse(JSON.stringify(workspacePrefs)) as Object);
  snapshot.pullRequestHideTestFiles = value;
  await workspacePrefsStore.save(snapshot);
  workspacePrefs.pullRequestHideTestFiles = value;
  AppStorage.setOrCreate('t3HideTestFiles', value);
}

export async function setSideThreadOpenTarget(value: string): Promise<void> {
  if (value !== 'panel' && value !== 'main') throw new Error('子会话打开方式无效');
  if (!workspacePrefsStore) throw new Error('设置尚未初始化');
  const snapshot = workspacePreferences(JSON.parse(JSON.stringify(workspacePrefs)) as Object);
  snapshot.sideThreadOpenTarget = value;
  await workspacePrefsStore.save(snapshot);
  workspacePrefs.sideThreadOpenTarget = value;
}
