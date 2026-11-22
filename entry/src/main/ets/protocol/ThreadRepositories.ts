import { compactArray, record, text } from './Wire';
import { PROJECT_TRACKED_FOLDERS_MAX, ProjectTrackedFolder } from './Projects';

// Upstream 60863edc41 multi-repository project contracts & threadRepositories logic.

export const TASK_FOLDER_DEFAULT_REPOSITORIES_MAX = 8;
export const THREAD_REPOSITORY_SECTIONS_VISIBLE = 4;

export interface WorkspaceFolder {
  name: string;
  path: string;
  state: string; // 'git' | 'plain' | 'missing'
  discovered?: boolean;
}

export interface WorkspaceScannedFolder {
  path: string;
  name: string;
  isGitRepository: boolean;
  source: string; // 'child' | 'code-workspace'
}

export interface WorkspaceScanResult {
  workspaceRoot: string;
  isGitRepository: boolean;
  codeWorkspaceFile: string;
  folders: WorkspaceScannedFolder[];
}

export interface TaskFolderRepository {
  repositoryPath: string;
  worktreePath: string;
  name: string;
}

export interface TaskFolder {
  root: string;
  projectId: string;
  projectRoot: string;
  anchor: string;
  projectPath: string;
  projectIsWorktree: boolean;
  repositories: TaskFolderRepository[];
}

export interface ThreadRepositoryScope {
  scopeId: string;
  name: string;
  repositoryPath: string;
  cwd: string;
  relativePath?: string;
}

export interface ThreadGitRepository {
  repositoryPath: string;
  name: string;
  cwd: string;
}

export interface PinnedThreadRepository {
  repositoryPath: string;
  name: string;
}

export interface ThreadRepositorySection {
  key: string;
  name: string;
  cwd: string;
  origin: string; // 'pinned' | 'changed' | 'worktree' | 'tracked'
}

export interface ThreadRepositorySections {
  visible: ThreadRepositorySection[];
  hidden: ThreadRepositorySection[];
}

export interface WorktreeRepositoryChoice {
  repositoryPath: string;
  name: string;
  relativePath?: string;
}

export interface WorktreeRepositoryPath {
  path: string;
}

export interface WorktreeRepositorySelection {
  selected: string[];
  label: string;
  needsChoice: boolean;
  strategyRepositories?: WorktreeRepositoryPath[];
}

function optionalStr(value: Object | undefined): string {
  return typeof value === 'string' ? value.trim() : '';
}

function safeFolderPath(value: Object | undefined): string {
  const s = optionalStr(value);
  if (!s || s.length > 2048 || /[\u0000-\u001f\u007f]/.test(s)) return '';
  return s;
}

function safeFolderName(value: Object | undefined, fallback: string): string {
  const raw = typeof value === 'string' ? value.replace(/[\u0000-\u001f\u007f]+/g, ' ').trim() : '';
  const chosen = raw || fallback;
  return chosen.length > 128 ? chosen.slice(0, 128) : chosen;
}

export function folderStateLabel(state: string): string {
  if (state === 'git') return 'Git 仓库';
  if (state === 'missing') return '目录缺失';
  if (state === 'plain') return '普通目录';
  return '';
}

export function parseWorkspaceFolders(value: Object): WorkspaceFolder[] {
  const row = record(value);
  const seen = new Set<string>();
  const parsed = compactArray(row.folders, (entry: Object): WorkspaceFolder => {
    const item = record(entry);
    const folderPath = safeFolderPath(item.path);
    const name = safeFolderName(item.name, folderPath);
    const state = text(item.state);
    if (!folderPath || !name || !['git', 'plain', 'missing'].includes(state)) {
      throw new Error('工作区目录项无效');
    }
    const folder: WorkspaceFolder = { name, path: folderPath, state };
    if (item.discovered === true) folder.discovered = true;
    return folder;
  });
  const result: WorkspaceFolder[] = [];
  for (const folder of parsed) {
    if (seen.has(folder.path)) continue;
    seen.add(folder.path);
    result.push(folder);
  }
  return result;
}

export function parseWorkspaceScan(value: Object): WorkspaceScanResult {
  const row = record(value);
  const workspaceRoot = safeFolderPath(row.workspaceRoot);
  if (!workspaceRoot) throw new Error('扫描工作区路径无效');
  const folders = compactArray(row.folders, (entry: Object): WorkspaceScannedFolder => {
    const item = record(entry);
    const folderPath = safeFolderPath(item.path);
    const name = safeFolderName(item.name, folderPath);
    const source = text(item.source);
    if (!folderPath || !name || (source !== 'child' && source !== 'code-workspace')) {
      throw new Error('扫描目录项无效');
    }
    return {
      path: folderPath,
      name,
      isGitRepository: item.isGitRepository === true,
      source
    };
  });
  return {
    workspaceRoot,
    isGitRepository: row.isGitRepository === true,
    codeWorkspaceFile: typeof row.codeWorkspaceFile === 'string' ? row.codeWorkspaceFile : '',
    folders
  };
}

export function parseTaskFolder(value: Object): TaskFolder {
  const row = record(value);
  const root = safeFolderPath(row.root);
  const projectId = optionalStr(row.projectId);
  const projectRoot = safeFolderPath(row.projectRoot);
  const anchor = safeFolderPath(row.anchor);
  const projectPath = safeFolderPath(row.projectPath);
  if (!root || !projectId || !projectRoot || !anchor || !projectPath) {
    throw new Error('任务目录结构无效');
  }
  const repositories = compactArray(row.repositories, (entry: Object): TaskFolderRepository => {
    const item = record(entry);
    const repositoryPath = safeFolderPath(item.repositoryPath);
    const worktreePath = safeFolderPath(item.worktreePath);
    const name = safeFolderName(item.name, repositoryPath);
    if (!repositoryPath || !worktreePath || !name) throw new Error('任务仓库项无效');
    return { repositoryPath, worktreePath, name };
  });
  return {
    root,
    projectId,
    projectRoot,
    anchor,
    projectPath,
    projectIsWorktree: row.projectIsWorktree === true,
    repositories
  };
}

export function parseTaskFolderResult(value: Object): TaskFolder | undefined {
  const row = record(value);
  if (row.taskFolder === null || row.taskFolder === undefined) return undefined;
  return parseTaskFolder(row.taskFolder);
}

/**
 * Folders a project's `.code-workspace` file lists that the project does not cover yet.
 */
export function suggestedTrackedFolders(
  tracked: ProjectTrackedFolder[],
  scanned: WorkspaceScannedFolder[]
): ProjectTrackedFolder[] {
  const seen = new Set<string>(tracked.map((folder: ProjectTrackedFolder) => folder.path));
  const result: ProjectTrackedFolder[] = [];
  for (const folder of scanned) {
    if (folder.source !== 'code-workspace' || seen.has(folder.path)) continue;
    seen.add(folder.path);
    const name = folder.name.slice(0, 128).trim() || folder.path;
    result.push({ path: folder.path, name });
  }
  return result;
}

/**
 * The list to send as a project's `trackedFolders` after adding folders; null when exceeding limit.
 */
export function appendTrackedFolders(
  tracked: ProjectTrackedFolder[],
  added: ProjectTrackedFolder[]
): ProjectTrackedFolder[] | null {
  const seen = new Set<string>(tracked.map((folder: ProjectTrackedFolder) => folder.path));
  const next: ProjectTrackedFolder[] = tracked.slice();
  for (const folder of added) {
    if (seen.has(folder.path)) continue;
    seen.add(folder.path);
    next.push({ path: folder.path, name: folder.name });
  }
  return next.length > PROJECT_TRACKED_FOLDERS_MAX ? null : next;
}

function isAbsolutePath(path: string): boolean {
  return path.startsWith('/') || /^[a-zA-Z]:[\\/]/.test(path);
}

function pathSegments(path: string): { root: string; segments: string[] } | undefined {
  const normalized = path.replace(/\\/g, '/');
  const segments = normalized.split('/').filter((segment: string) => segment.length > 0);
  if (normalized.startsWith('/')) return { root: '/', segments };
  const drive = segments[0];
  if (drive === undefined || !/^[a-zA-Z]:$/.test(drive)) return undefined;
  return { root: drive.toLowerCase(), segments: segments.slice(1) };
}

export function relativeFolderPath(from: string, to: string): string | undefined {
  const source = pathSegments(from);
  const target = pathSegments(to);
  if (source === undefined || target === undefined || source.root !== target.root) {
    return undefined;
  }
  const same = (left: string, right: string): boolean =>
    source.root === '/' ? left === right : left.toLowerCase() === right.toLowerCase();
  let shared = 0;
  while (
    shared < source.segments.length &&
    shared < target.segments.length &&
    same(source.segments[shared], target.segments[shared])
  ) {
    shared += 1;
  }
  const up: string[] = [];
  for (let i = shared; i < source.segments.length; i += 1) up.push('..');
  return up.concat(target.segments.slice(shared)).join('/');
}

export function isRelativePathInsideFolder(relativePath: string): boolean {
  return relativePath !== '..' && !relativePath.startsWith('../') && !isAbsolutePath(relativePath);
}

export function repositoryFilePath(relativePath: string, filePath: string): string {
  return relativePath === '' || relativePath === '.' ? filePath : relativePath + '/' + filePath;
}

export function isRepositoryCheckpointScope(scope: Record<string, Object>): boolean {
  return typeof scope.repositoryPath === 'string' && scope.repositoryPath.trim().length > 0;
}

export function repositoryCheckpointScopeIds(scopes: Record<string, Object>[]): Set<string> {
  const result = new Set<string>();
  for (const scope of scopes) {
    if (isRepositoryCheckpointScope(scope) && typeof scope.id === 'string' && scope.id) {
      result.add(scope.id);
    }
  }
  return result;
}

function lastPathName(cwd: string): string {
  const parts = cwd.replace(/\\/g, '/').split('/').filter((part: string) => part.length > 0);
  return parts.length > 0 ? parts[parts.length - 1] : cwd;
}

function byNameThenPath(left: ThreadRepositoryScope, right: ThreadRepositoryScope): number {
  return left.name.localeCompare(right.name) || left.repositoryPath.localeCompare(right.repositoryPath);
}

export function threadRepositoryScopes(scopes: Record<string, Object>[]): ThreadRepositoryScope[] {
  const result: ThreadRepositoryScope[] = [];
  for (const scope of scopes) {
    if (!isRepositoryCheckpointScope(scope)) continue;
    const scopeId = optionalStr(scope.id);
    const repositoryPath = optionalStr(scope.repositoryPath);
    const cwd = optionalStr(scope.cwd);
    if (!scopeId || !repositoryPath || !cwd) continue;
    const parentId = optionalStr(scope.parentScopeId);
    const parent = parentId ? scopes.find((candidate: Record<string, Object>) => candidate.id === parentId) : undefined;
    const parentCwd = parent && typeof parent.cwd === 'string' ? parent.cwd : undefined;
    const relativePath = parentCwd !== undefined ? relativeFolderPath(parentCwd, cwd) : undefined;
    const label = optionalStr(scope.label);
    const entry: ThreadRepositoryScope = {
      scopeId,
      name: label || lastPathName(cwd),
      repositoryPath,
      cwd
    };
    if (relativePath !== undefined) entry.relativePath = relativePath;
    result.push(entry);
  }
  return result.sort(byNameThenPath);
}

export function threadChangedRepositories(
  checkpoints: Record<string, Object>[],
  checkpointScopes: Record<string, Object>[]
): ThreadRepositoryScope[] {
  const scopes = threadRepositoryScopes(checkpointScopes);
  if (scopes.length < 2) return scopes;
  const lastChange = new Map<string, number>();
  for (const checkpoint of checkpoints) {
    if (checkpoint.runId === null || checkpoint.runId === undefined || checkpoint.runId === '') continue;
    const scopeId = optionalStr(checkpoint.scopeId);
    if (!scopeId) continue;
    const ordinal = typeof checkpoint.ordinalWithinScope === 'number' ? checkpoint.ordinalWithinScope as number : -1;
    const latest = lastChange.get(scopeId);
    if (latest === undefined || ordinal > latest) lastChange.set(scopeId, ordinal);
  }
  return scopes.slice().sort((left: ThreadRepositoryScope, right: ThreadRepositoryScope): number => {
    const rightOrd = lastChange.get(right.scopeId);
    const leftOrd = lastChange.get(left.scopeId);
    return (rightOrd !== undefined ? rightOrd : -1) - (leftOrd !== undefined ? leftOrd : -1);
  });
}

export function threadGitRepositories(
  changed: ThreadGitRepository[],
  taskFolder: TaskFolder | undefined,
  folders: WorkspaceFolder[] | undefined,
  threadCwd: string
): ThreadGitRepository[] {
  const reached: ThreadGitRepository[] = [];
  if (taskFolder !== undefined) {
    for (const repo of taskFolder.repositories) {
      reached.push({ repositoryPath: repo.repositoryPath, name: repo.name, cwd: repo.worktreePath });
    }
  } else if (folders !== undefined) {
    for (const folder of folders) {
      if (folder.state === 'git' && folder.path !== threadCwd) {
        reached.push({ repositoryPath: folder.path, name: folder.name, cwd: folder.path });
      }
    }
  }
  if (reached.length === 0) return changed.slice();
  const reachedByPath = new Map<string, ThreadGitRepository>();
  for (const repo of reached) reachedByPath.set(repo.repositoryPath, repo);
  const listed = new Set<string>(changed.map((repo: ThreadGitRepository) => repo.repositoryPath));
  const result: ThreadGitRepository[] = [];
  for (const repo of changed) {
    const updated = reachedByPath.get(repo.repositoryPath);
    result.push(updated !== undefined ? updated : repo);
  }
  for (const repo of reached) {
    if (!listed.has(repo.repositoryPath)) result.push(repo);
  }
  return result;
}

export function threadRepositorySections(
  changed: ThreadRepositoryScope[],
  pinned: PinnedThreadRepository[],
  threadCwd: string,
  showAll: boolean,
  taskFolder: TaskFolder | undefined,
  reachesTracked: boolean = true
): ThreadRepositorySections {
  const sections: ThreadRepositorySection[] = [];
  if (taskFolder !== undefined) {
    const byPath = new Map<string, TaskFolderRepository>();
    for (const repo of taskFolder.repositories) byPath.set(repo.repositoryPath, repo);
    const ordered: string[] = [];
    const seen = new Set<string>();
    for (const scope of changed) {
      if (byPath.has(scope.repositoryPath) && !seen.has(scope.repositoryPath)) {
        seen.add(scope.repositoryPath);
        ordered.push(scope.repositoryPath);
      }
    }
    for (const repo of taskFolder.repositories) {
      if (!seen.has(repo.repositoryPath)) {
        seen.add(repo.repositoryPath);
        ordered.push(repo.repositoryPath);
      }
    }
    for (const repoPath of ordered) {
      const repo = byPath.get(repoPath)!;
      sections.push({ key: repoPath, name: repo.name, cwd: repo.worktreePath, origin: 'worktree' });
    }
    for (const scope of changed) {
      if (byPath.has(scope.repositoryPath)) continue;
      const relative = relativeFolderPath(taskFolder.root, scope.cwd);
      if (relative !== undefined && isRelativePathInsideFolder(relative)) {
        sections.push({ key: scope.repositoryPath, name: scope.name, cwd: scope.cwd, origin: 'changed' });
      }
    }
  } else {
    const seen = new Set<string>(threadCwd ? [threadCwd] : []);
    const add = (section: ThreadRepositorySection): void => {
      if (seen.has(section.key)) return;
      seen.add(section.key);
      sections.push(section);
    };
    if (reachesTracked) {
      for (const pin of pinned) {
        add({ key: pin.repositoryPath, name: pin.name, cwd: pin.repositoryPath, origin: 'pinned' });
      }
    }
    for (const scope of changed) {
      add({ key: scope.repositoryPath, name: scope.name, cwd: scope.cwd, origin: 'changed' });
    }
  }
  if (sections.length === 0) return { visible: [], hidden: [] };
  if (showAll || sections.length <= THREAD_REPOSITORY_SECTIONS_VISIBLE) {
    return { visible: sections, hidden: [] };
  }
  return {
    visible: sections.slice(0, THREAD_REPOSITORY_SECTIONS_VISIBLE),
    hidden: sections.slice(THREAD_REPOSITORY_SECTIONS_VISIBLE)
  };
}

export function pinThreadRepository(
  pinned: PinnedThreadRepository[],
  repository: PinnedThreadRepository
): PinnedThreadRepository[] {
  if (pinned.some((entry: PinnedThreadRepository) => entry.repositoryPath === repository.repositoryPath)) {
    return pinned;
  }
  return pinned.concat([repository]);
}

export function unpinThreadRepository(
  pinned: PinnedThreadRepository[],
  repositoryPath: string
): PinnedThreadRepository[] {
  return pinned.filter((entry: PinnedThreadRepository) => entry.repositoryPath !== repositoryPath);
}

export function otherTaskFolderRepositories(
  folders: WorkspaceFolder[],
  taskFolder: TaskFolder
): PinnedThreadRepository[] {
  const present = new Set<string>(taskFolder.repositories.map((repo: TaskFolderRepository) => repo.repositoryPath));
  const result: PinnedThreadRepository[] = [];
  for (const folder of folders) {
    if (folder.state !== 'git' || folder.path === taskFolder.projectRoot || present.has(folder.path)) continue;
    result.push({ repositoryPath: folder.path, name: folder.name });
  }
  return result;
}

export function worktreeRepositoryChoices(
  folders: WorkspaceFolder[],
  projectRoot: string
): WorktreeRepositoryChoice[] {
  const result: WorktreeRepositoryChoice[] = [];
  for (const folder of folders) {
    if (folder.state !== 'git') continue;
    const relative = relativeFolderPath(projectRoot, folder.path);
    const choice: WorktreeRepositoryChoice = { repositoryPath: folder.path, name: folder.name };
    if (relative !== undefined && relative !== '' && isRelativePathInsideFolder(relative)) {
      choice.relativePath = relative;
    }
    result.push(choice);
  }
  return result;
}

export function resolveWorktreeRepositorySelection(
  choices: WorktreeRepositoryChoice[] | null,
  chosen: string[] | undefined
): WorktreeRepositorySelection {
  if (choices === null) {
    const selected = chosen !== undefined ? chosen.slice() : [];
    const result: WorktreeRepositorySelection = { selected, label: '关联仓库', needsChoice: false };
    if (chosen !== undefined) {
      result.strategyRepositories = chosen.map((path: string): WorktreeRepositoryPath => ({ path }));
    }
    return result;
  }
  const takesAllByDefault = choices.length <= TASK_FOLDER_DEFAULT_REPOSITORIES_MAX;
  const wanted = chosen === undefined ? null : new Set<string>(chosen);
  const selected: string[] = [];
  for (const choice of choices) {
    if (wanted === null ? takesAllByDefault : wanted.has(choice.repositoryPath)) {
      selected.push(choice.repositoryPath);
    }
  }
  const needsChoice = chosen === undefined && !takesAllByDefault;
  let label: string;
  if (needsChoice) label = '选择仓库';
  else if (selected.length === 0) label = '不创建仓库工作树';
  else if (selected.length !== 1 && selected.length === choices.length) label = '全部仓库（' + selected.length + '）';
  else label = selected.length + ' 个仓库';
  const result: WorktreeRepositorySelection = { selected, label, needsChoice };
  if (chosen !== undefined) {
    result.strategyRepositories = selected.map((path: string): WorktreeRepositoryPath => ({ path }));
  }
  return result;
}

export function filterPathsToRepositoryFolder<T>(
  items: T[],
  pathOf: (item: T) => string,
  folder: string,
  folders: string[]
): T[] {
  return items.filter((item: T): boolean => {
    const filePath = pathOf(item);
    let owner = '';
    for (const candidate of folders) {
      if (candidate.length > owner.length && filePath.startsWith(candidate + '/')) {
        owner = candidate;
      }
    }
    return owner === folder;
  });
}
