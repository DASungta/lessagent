import { compactArray, compactObjects, objects, record, text } from './Wire';

function textList(value: Object | undefined): string[] {
  if (value === undefined || !Array.isArray(value)) return [];
  return (value as Object[]).filter((item: Object) => typeof item === 'string') as string[];
}

export interface DiffRow {
  kind: string;
  text: string;
  oldLine: number;
  newLine: number;
}

export interface DiffHunk {
  header: string;
  rows: DiffRow[];
  lastOldLine: number;
  lastNewLine: number;
}

export interface DiffFile {
  path: string;
  previousPath: string;
  changeType: string;
  additions: number;
  deletions: number;
  binary: boolean;
  hunks: DiffHunk[];
}

export interface ReviewSource {
  id: string;
  kind: string;
  title: string;
  commitSubject: string;
  baseRef: string;
  headRef: string;
  diff: string;
  diffHash: string;
  truncated: boolean;
  files: ReviewFileStat[];
}

export interface ReviewFileStat {
  path: string;
  previousPath: string;
  changeType: string;
  additions: number;
  deletions: number;
}

export interface ReviewPreview {
  sources: ReviewSource[];
  incomplete: boolean;
}

function headerPath(value: string): string {
  let path = value.trim();
  if (path.startsWith('"') && path.endsWith('"')) path = path.slice(1, -1);
  if (path.startsWith('a/') || path.startsWith('b/')) path = path.slice(2);
  return path;
}

export function parseDiff(patch: string): DiffFile[] {
  const files: DiffFile[] = [];
  let file: DiffFile | undefined = undefined;
  let hunk: DiffHunk | undefined = undefined;
  let oldLine = 0;
  let newLine = 0;
  for (const line of patch.replace(/\r\n?/g, '\n').split('\n')) {
    if (line.startsWith('diff --git ')) {
      const match = /^diff --git (?:a\/)?(.+?) (?:b\/)?(.+)$/.exec(line);
      file = { path: match ? headerPath(match[2]) : '', previousPath: match ? headerPath(match[1]) : '',
        changeType: 'change', additions: 0, deletions: 0, binary: false, hunks: [] };
      files.push(file);
      hunk = undefined;
      continue;
    }
    if (!file) {
      if (!line.startsWith('--- ') && !line.startsWith('@@')) continue;
      file = { path: '', previousPath: '', changeType: 'change', additions: 0, deletions: 0, binary: false, hunks: [] };
      files.push(file);
    }
    if (line.startsWith('new file mode')) { file.changeType = 'new'; continue; }
    if (line.startsWith('deleted file mode')) { file.changeType = 'deleted'; continue; }
    if (line.startsWith('rename from ')) { file.previousPath = line.slice(12).trim(); file.changeType = 'rename-pure'; continue; }
    if (line.startsWith('rename to ')) { file.path = line.slice(10).trim(); file.changeType = 'rename-pure'; continue; }
    if (line.startsWith('similarity index')) continue;
    if (line.startsWith('index ')) continue;
    if (line.startsWith('--- ')) {
      const path = headerPath(line.slice(4));
      if (path !== '/dev/null') file.previousPath = path;
      continue;
    }
    if (line.startsWith('+++ ')) {
      const path = headerPath(line.slice(4));
      if (path !== '/dev/null') file.path = path;
      continue;
    }
    if (/^Binary files .* differ$/.test(line) || line === 'GIT binary patch') { file.binary = true; continue; }
    const hunkHeader = /^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@(.*)$/.exec(line);
    if (hunkHeader) {
      oldLine = Number(hunkHeader[1]);
      newLine = Number(hunkHeader[2]);
      hunk = { header: line, rows: [], lastOldLine: 0, lastNewLine: 0 };
      file.hunks.push(hunk);
      continue;
    }
    if (!hunk) continue;
    if (line.startsWith('\\ No newline')) continue;
    if (line.startsWith('+')) {
      hunk.rows.push({ kind: 'add', text: line.slice(1), oldLine: 0, newLine });
      hunk.lastNewLine = newLine;
      newLine += 1; file.additions += 1; continue;
    }
    if (line.startsWith('-')) {
      hunk.rows.push({ kind: 'del', text: line.slice(1), oldLine, newLine: 0 });
      hunk.lastOldLine = oldLine;
      oldLine += 1; file.deletions += 1; continue;
    }
    if (line.startsWith(' ')) {
      hunk.rows.push({ kind: 'context', text: line.slice(1), oldLine, newLine });
      hunk.lastOldLine = oldLine; hunk.lastNewLine = newLine;
      oldLine += 1; newLine += 1;
    }
  }
  return files.filter((entry: DiffFile) => !!entry.path || !!entry.previousPath);
}

export function diffStats(files: DiffFile[]): { additions: number; deletions: number } {
  let additions = 0;
  let deletions = 0;
  for (const file of files) { additions += file.additions; deletions += file.deletions; }
  return { additions, deletions };
}

export function reviewPreviewInput(cwd: string, baseRef: string = '', sourceKind: string = '',
  trackedOnly: boolean = false, ignoreWhitespace: boolean = false): Object {
  if (!cwd.trim()) throw new Error('缺少工作目录');
  const input: Record<string, Object> = { cwd };
  if (baseRef) input.baseRef = baseRef;
  if (sourceKind) input.sourceKind = sourceKind;
  if (trackedOnly) input.trackedOnly = true;
  if (ignoreWhitespace) input.ignoreWhitespace = true;
  return input;
}

function reviewFileStat(value: Object): ReviewFileStat {
  const row = record(value);
  return {
    path: text(row.path), previousPath: row.previousPath === null || row.previousPath === undefined ? '' : text(row.previousPath),
    changeType: typeof row.changeType === 'string' ? row.changeType : 'change',
    additions: Number(row.additions), deletions: Number(row.deletions)
  };
}

export function reviewPreview(value: Object): ReviewPreview {
  const row = record(value);
  const sources = compactArray(objects(row.sources), (source: Object): ReviewSource => {
    const item = record(source);
    return {
      id: text(item.id), kind: text(item.kind), title: text(item.title),
      commitSubject: typeof item.commitSubject === 'string' ? item.commitSubject : '',
      baseRef: item.baseRef === null || item.baseRef === undefined ? '' : text(item.baseRef),
      headRef: item.headRef === null || item.headRef === undefined ? '' : text(item.headRef),
      diff: text(item.diff), diffHash: text(item.diffHash), truncated: item.truncated === true,
      files: item.files === undefined ? [] : compactArray(item.files, reviewFileStat)
    };
  });
  return { sources, incomplete: row.incomplete === true };
}

export interface DiffSelection {
  filePath: string;
  sectionId: string;
  sectionTitle: string;
  startIndex: number;
  endIndex: number;
  rangeLabel: string;
  text: string;
  diff: string;
}

/** A selected diff run keeps its header so the composer sees the file and hunk context. */
export function selectedDiff(file: DiffFile, hunk: DiffHunk, start: number, end: number): DiffSelection {
  const from = Math.max(0, Math.min(start, end));
  const to = Math.min(hunk.rows.length - 1, Math.max(start, end));
  const rows = hunk.rows.slice(from, to + 1);
  const first = rows[0];
  const last = rows[rows.length - 1];
  const label = rows.length === 1 ? '行 ' + (first.newLine || first.oldLine) :
    '行 ' + (first.newLine || first.oldLine) + '–' + (last.newLine || last.oldLine);
  const text = rows.map((row: DiffRow) => (row.kind === 'add' ? '+' : row.kind === 'del' ? '-' : ' ') + row.text).join('\n');
  return {
    filePath: file.path || file.previousPath, sectionId: 'review:' + (file.path || file.previousPath) + ':' + hunk.header,
    sectionTitle: file.path || file.previousPath, startIndex: from, endIndex: to, rangeLabel: label, text,
    diff: 'diff --git a/' + (file.previousPath || file.path) + ' b/' + (file.path || file.previousPath) + '\n' +
      '--- a/' + (file.previousPath || file.path) + '\n+++ b/' + (file.path || file.previousPath) + '\n' +
      hunk.header + '\n' + text
  };
}

function escapeAttribute(value: string): string {
  return value.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

export function reviewCommentContext(selection: DiffSelection, comment: string, contextId: string): Object {
  if (!comment.trim()) throw new Error('请输入评论');
  if (comment.length > 16000 || selection.diff.length > 32000) throw new Error('审阅评论过长');
  let fence = '```';
  const runs = selection.diff.match(/`+/g) || [];
  for (const run of runs) if (run.length >= fence.length) fence = '`'.repeat(run.length + 1);
  const textValue = [
    '<review_comment sectionId="' + escapeAttribute(selection.sectionId) +
      '" sectionTitle="' + escapeAttribute(selection.sectionTitle) +
      '" filePath="' + escapeAttribute(selection.filePath) +
      '" startIndex="' + selection.startIndex + '" endIndex="' + selection.endIndex +
      '" rangeLabel="' + escapeAttribute(selection.rangeLabel) + '">',
    comment.trim(), fence + 'diff', selection.diff, fence, '</review_comment>'
  ].join('\n');
  return { version: 1, kind: 'review-comment', contextId,
    label: selection.filePath + ' · ' + selection.rangeLabel,
    payload: { sectionId: selection.sectionId, sectionTitle: selection.sectionTitle,
      filePath: selection.filePath, startIndex: selection.startIndex, endIndex: selection.endIndex,
      rangeLabel: selection.rangeLabel, text: textValue, diff: selection.diff, fenceLanguage: 'diff' } };
}

export function fileSelectionContext(filePath: string, from: number, to: number, textValue: string,
  contextId: string): Object {
  const label = from === to ? '行 ' + (from + 1) : '行 ' + (from + 1) + '–' + (to + 1);
  return { version: 1, kind: 'review-comment', contextId, label: filePath + ' · ' + label,
    payload: { sectionId: 'file:' + filePath + ':' + from, sectionTitle: filePath, filePath,
      startIndex: from, endIndex: to, rangeLabel: label,
      text: '<review_comment filePath="' + escapeAttribute(filePath) + '" rangeLabel="' +
        escapeAttribute(label) + '">\n' + textValue + '\n</review_comment>', diff: '' } };
}

export function fileCommentContext(filePath: string, comment: string, contextId: string): Object {
  if (!comment.trim() || comment.length > 16000) throw new Error('文件评论无效或过长');
  return { version: 1, kind: 'review-comment', contextId, label: filePath + ' · 文件评论',
    payload: { sectionId: 'file:' + filePath, sectionTitle: filePath, filePath,
      startIndex: 0, endIndex: 0, rangeLabel: '文件评论',
      text: '<review_comment filePath="' + escapeAttribute(filePath) +
        '" rangeLabel="文件评论">\n' + comment.trim() + '\n</review_comment>', diff: '' } };
}

export interface VcsChange { path: string; insertions: number; deletions: number; }
export interface VcsView {
  isRepo: boolean;
  refName: string;
  hasPrimaryRemote: boolean;
  isDefaultRef: boolean;
  hasWorkingTreeChanges: boolean;
  files: VcsChange[];
  insertions: number;
  deletions: number;
  hasUpstream: boolean;
  ahead: number;
  behind: number;
  rootPath: string;
  providerKind: string;
  prNumber: number;
  prState: string;
  prTitle: string;
  prUrl: string;
}

export function emptyVcs(): VcsView {
  return { isRepo: false, refName: '', hasPrimaryRemote: false, isDefaultRef: false,
    hasWorkingTreeChanges: false, files: [], insertions: 0, deletions: 0, hasUpstream: false,
    ahead: 0, behind: 0, rootPath: '', providerKind: '', prNumber: 0, prState: '', prTitle: '', prUrl: '' };
}

function mergeVcs(current: VcsView, value: Record<string, Object>): VcsView {
  const workingTree = value.workingTree === undefined ? undefined : record(value.workingTree);
  const provider = value.sourceControlProvider === undefined || value.sourceControlProvider === null ?
    undefined : record(value.sourceControlProvider);
  const pr = value.pr === undefined || value.pr === null ? undefined : record(value.pr);
  return {
    isRepo: value.isRepo === undefined ? current.isRepo : value.isRepo === true,
    refName: value.refName === null ? '' : (typeof value.refName === 'string' ? value.refName : current.refName),
    hasPrimaryRemote: value.hasPrimaryRemote === undefined ? current.hasPrimaryRemote : value.hasPrimaryRemote === true,
    isDefaultRef: value.isDefaultRef === undefined ? current.isDefaultRef : value.isDefaultRef === true,
    hasWorkingTreeChanges: value.hasWorkingTreeChanges === undefined ? current.hasWorkingTreeChanges :
      value.hasWorkingTreeChanges === true,
    files: workingTree === undefined ? current.files : compactArray(workingTree.files, (file: Object): VcsChange => {
      const row = record(file);
      return { path: text(row.path), insertions: Number(row.insertions) || 0, deletions: Number(row.deletions) || 0 };
    }),
    insertions: workingTree === undefined ? current.insertions : (typeof workingTree.insertions === 'number' ? workingTree.insertions : 0),
    deletions: workingTree === undefined ? current.deletions : (typeof workingTree.deletions === 'number' ? workingTree.deletions : 0),
    hasUpstream: value.hasUpstream === undefined ? current.hasUpstream : value.hasUpstream === true,
    ahead: typeof value.aheadCount === 'number' ? value.aheadCount : current.ahead,
    behind: typeof value.behindCount === 'number' ? value.behindCount : current.behind,
    rootPath: workingTree !== undefined && typeof workingTree.rootPath === 'string' ? workingTree.rootPath : current.rootPath,
    providerKind: provider === undefined ? current.providerKind : (typeof provider.kind === 'string' ? provider.kind : current.providerKind),
    prNumber: pr === undefined ? current.prNumber : (typeof pr.number === 'number' ? pr.number : 0),
    prState: pr === undefined ? current.prState : (typeof pr.state === 'string' ? pr.state : ''),
    prTitle: pr === undefined ? current.prTitle : (typeof pr.title === 'string' ? pr.title : ''),
    prUrl: pr === undefined ? current.prUrl : (typeof pr.url === 'string' ? pr.url : '')
  };
}

export function applyVcsStatus(current: VcsView, value: Object): VcsView {
  const event = record(value);
  const rawTag = event._tag || event.kind || event.type;
  const tag = typeof rawTag === 'string' ? rawTag : '';
  if (tag === 'snapshot') {
    const merged = mergeVcs(emptyVcs(), record(event.local));
    return event.remote === null || event.remote === undefined ? merged : mergeVcs(merged, record(event.remote));
  }
  if (tag === 'localUpdated') return mergeVcs(current, record(event.local));
  if (tag === 'remoteUpdated') return event.remote === null || event.remote === undefined ? current : mergeVcs(current, record(event.remote));
  return mergeVcs(current, event);
}

export function gitActionInput(actionId: string, cwd: string, action: string, commitMessage: string = '',
  featureBranch: boolean = false, filePaths: string[] = [], threadId: string = '',
  projectId: string = ''): Object {
  if (!/^[a-z0-9_-]{8,128}$/i.test(actionId)) throw new Error('操作标识无效');
  if (!cwd.trim()) throw new Error('缺少工作目录');
  if (!['commit', 'push', 'create_pr', 'commit_push', 'commit_push_pr'].includes(action)) throw new Error('Git 操作无效');
  if ((action === 'commit' || action === 'commit_push' || action === 'commit_push_pr') && !commitMessage.trim()) {
    throw new Error('请输入提交信息');
  }
  if (commitMessage.length > 10000) throw new Error('提交信息过长');
  const input: Record<string, Object> = { actionId, cwd, action };
  if (commitMessage.trim()) input.commitMessage = commitMessage.trim();
  if (featureBranch) input.featureBranch = true;
  if (filePaths.length) input.filePaths = filePaths;
  if (threadId) input.threadId = threadId;
  if (projectId) input.projectId = projectId;
  return input;
}

export function pullInput(cwd: string): Object {
  if (!cwd.trim()) throw new Error('缺少工作目录');
  return { cwd };
}

export function switchRefInput(cwd: string, refName: string): Object {
  if (!cwd.trim() || !refName.trim()) throw new Error('分支无效');
  return { cwd, refName };
}

export interface RefView { name: string; isRemote: boolean; current: boolean; isDefault: boolean; worktreePath: string; }

export interface PullRequestPage {
  rows: PullRequestRow[];
  errors: string[];
  truncated: boolean;
  nextCursor: string;
  nextCursors?: Record<string, string>;
}

export interface ReviewerSelection {
  id: string;
  kind: string;
}

export interface LabelCandidateView {
  name: string;
  applied: boolean;
}

export interface ReviewerCandidateView {
  id: string;
  kind: string;
  name: string;
  requested: boolean;
}

export function listRefs(cwd: string, query: string = ''): Object {
  const payload: Record<string, Object> = { cwd, refKind: 'all', limit: 100 };
  if (query.trim()) payload.query = query.trim().slice(0, 256);
  return payload;
}

export function vcsWatchInput(cwd: string): Object {
  if (!cwd.trim()) throw new Error('缺少工作目录');
  return { cwd, includeRemote: true };
}

export function refs(value: Object): RefView[] {
  return compactArray(objects(record(value).refs), (ref: Object): RefView => {
    const row = record(ref);
    return { name: text(row.name), isRemote: row.isRemote === true, current: row.current === true,
      isDefault: row.isDefault === true, worktreePath: row.worktreePath === null || row.worktreePath === undefined ? '' : text(row.worktreePath) };
  });
}

export interface PullRequestRow {
  provider: string;
  host: string;
  projectId: string;
  projectTitle: string;
  repository: string;
  number: number;
  title: string;
  url: string;
  author: string;
  headBranch: string;
  baseBranch: string;
  state: string;
  draft: boolean;
  additions: number;
  deletions: number;
  updatedAt: string;
  reviewDecision: string;
  checksState: string;
  labels: string[];
  stackPosition: number;
  stackSize: number;
  localId?: string;
  environmentLabel?: string;
}

export interface PullRequestProjectRepository {
  canonicalKey: string;
  displayName: string;
}

export interface PullRequestProjectSource {
  localId: string;
  environmentId: string;
  environmentLabel: string;
  id: string;
  label: string;
  workspaceRoot: string;
  archivedAt: string;
  pinnedAt: string;
  isScratch: boolean;
  repository: PullRequestProjectRepository | undefined;
}

export interface PullRequestProjectChoice {
  key: string;
  localId: string;
  environmentId: string;
  environmentLabel: string;
  projectId: string;
  label: string;
  title: string;
  repository: string;
  canonicalKey: string;
  pinned: boolean;
  duplicateLabel: boolean;
}

export function pullRequestProjectKey(localId: string, projectId: string): string {
  return localId + ':' + projectId;
}

export function normalizePullRequestCursors(cursors: Record<string, string> | undefined): Record<string, string> {
  const result: Record<string, string> = {};
  if (!cursors) return result;
  for (const key of Object.keys(cursors)) {
    const trimmedKey = key.trim();
    const value = cursors[key];
    if (trimmedKey && typeof value === 'string' && value.trim()) {
      result[trimmedKey] = value.trim();
    }
  }
  return result;
}

export function parsePullRequestCursors(value: Object | undefined | null): Record<string, string> {
  const result: Record<string, string> = {};
  if (value === undefined || value === null || typeof value !== 'object' || Array.isArray(value)) return result;
  const source = record(value);
  for (const key of Object.keys(source)) {
    const trimmedKey = key.trim();
    const entry = source[key];
    if (trimmedKey && typeof entry === 'string' && entry.trim()) {
      result[trimmedKey] = entry.trim();
    }
  }
  return result;
}

export function hasPullRequestCursors(cursors: Record<string, string> | undefined): boolean {
  if (!cursors) return false;
  for (const key of Object.keys(cursors)) {
    if (cursors[key]) return true;
  }
  return false;
}

export function firstPullRequestCursor(cursors: Record<string, string> | undefined): string {
  if (!cursors) return '';
  if (cursors.default) return cursors.default;
  for (const key of Object.keys(cursors)) {
    if (cursors[key]) return cursors[key];
  }
  return '';
}

function distinguishChoiceTitles(choices: PullRequestProjectChoice[],
  suffix: (choice: PullRequestProjectChoice) => string): PullRequestProjectChoice[] {
  const counts = new Map<string, number>();
  for (const choice of choices) {
    const key = choice.title.toLowerCase();
    counts.set(key, (counts.get(key) || 0) + 1);
  }
  return choices.map((choice: PullRequestProjectChoice): PullRequestProjectChoice => {
    const count = counts.get(choice.title.toLowerCase()) || 0;
    const extra = count > 1 ? suffix(choice).trim() : '';
    const title = extra ? choice.title + ' · ' + extra : choice.title;
    return {
      key: choice.key,
      localId: choice.localId,
      environmentId: choice.environmentId,
      environmentLabel: choice.environmentLabel,
      projectId: choice.projectId,
      label: choice.label,
      title,
      repository: choice.repository,
      canonicalKey: choice.canonicalKey,
      pinned: choice.pinned,
      duplicateLabel: choice.duplicateLabel || count > 1
    };
  });
}

export function pullRequestProjectChoices(projects: PullRequestProjectSource[],
  envLocalId: string = '', selectedKey: string = ''): PullRequestProjectChoice[] {
  const byRepo = new Map<string, PullRequestProjectSource>();
  for (const project of projects) {
    if (project.isScratch) continue;
    const key = pullRequestProjectKey(project.localId, project.id);
    const isSelected = !!selectedKey && key === selectedKey;
    if (project.archivedAt && !isSelected) continue;
    if (envLocalId && project.localId !== envLocalId && !isSelected) continue;
    const canonical = project.repository && project.repository.canonicalKey ?
      project.repository.canonicalKey.toLowerCase() : '';
    const dedupeKey = canonical ? project.localId + ':repo:' + canonical : project.localId + ':project:' + project.id;
    if (!byRepo.has(dedupeKey) || isSelected) {
      byRepo.set(dedupeKey, project);
    }
  }
  const unique: PullRequestProjectSource[] = [];
  byRepo.forEach((project: PullRequestProjectSource) => { unique.push(project); });
  const hasAnyRepo = unique.some((project: PullRequestProjectSource) =>
    !!(project.repository && project.repository.canonicalKey));
  const filtered = hasAnyRepo ? unique.filter((project: PullRequestProjectSource) =>
    !!(project.repository && project.repository.canonicalKey) ||
      (!!selectedKey && pullRequestProjectKey(project.localId, project.id) === selectedKey)) : unique;
  const rawChoices = filtered.map((project: PullRequestProjectSource): PullRequestProjectChoice => ({
    key: pullRequestProjectKey(project.localId, project.id),
    localId: project.localId,
    environmentId: project.environmentId,
    environmentLabel: project.environmentLabel,
    projectId: project.id,
    label: project.label,
    title: project.label,
    repository: project.repository ? (project.repository.displayName || project.repository.canonicalKey) : '',
    canonicalKey: project.repository ? project.repository.canonicalKey : '',
    pinned: !!project.pinnedAt,
    duplicateLabel: false
  }));
  const byEnv = distinguishChoiceTitles(rawChoices, (choice: PullRequestProjectChoice) =>
    choice.environmentLabel || choice.environmentId || choice.localId);
  const byRepoName = distinguishChoiceTitles(byEnv, (choice: PullRequestProjectChoice) =>
    choice.repository || choice.projectId);
  return byRepoName.sort((left: PullRequestProjectChoice, right: PullRequestProjectChoice) => {
    if (left.pinned !== right.pinned) return left.pinned ? -1 : 1;
    return left.title.localeCompare(right.title);
  });
}

export function tagPullRequestRows(rows: PullRequestRow[], localId: string, environmentLabel: string): PullRequestRow[] {
  return rows.map((row: PullRequestRow): PullRequestRow => ({
    provider: row.provider,
    host: row.host,
    projectId: row.projectId,
    projectTitle: row.projectTitle,
    repository: row.repository,
    number: row.number,
    title: row.title,
    url: row.url,
    author: row.author,
    headBranch: row.headBranch,
    baseBranch: row.baseBranch,
    state: row.state,
    draft: row.draft,
    additions: row.additions,
    deletions: row.deletions,
    updatedAt: row.updatedAt,
    reviewDecision: row.reviewDecision,
    checksState: row.checksState,
    labels: row.labels,
    stackPosition: row.stackPosition,
    stackSize: row.stackSize,
    localId,
    environmentLabel
  }));
}

export function pullRequestRowIdentity(row: PullRequestRow, crossEnvironment: boolean): string {
  const hostOrProvider = (row.host || row.provider || '').toLowerCase();
  const repo = (row.repository || '').toLowerCase();
  if (crossEnvironment) {
    return hostOrProvider + ':' + repo + ':' + row.number;
  }
  return (row.localId || '') + ':' + hostOrProvider + ':' + row.projectId + ':' + repo + ':' + row.number;
}

function comparePullRequestRows(left: PullRequestRow, right: PullRequestRow): number {
  const leftTime = left.updatedAt ? Date.parse(left.updatedAt) : NaN;
  const rightTime = right.updatedAt ? Date.parse(right.updatedAt) : NaN;
  if (Number.isFinite(leftTime) && Number.isFinite(rightTime) && leftTime !== rightTime) {
    return rightTime - leftTime;
  }
  if (Number.isFinite(leftTime) !== Number.isFinite(rightTime)) {
    return Number.isFinite(rightTime) ? 1 : -1;
  }
  if (left.updatedAt && right.updatedAt && left.updatedAt !== right.updatedAt) {
    return right.updatedAt.localeCompare(left.updatedAt);
  }
  return right.number - left.number;
}

export function mergePullRequestRows(existing: PullRequestRow[], incoming: PullRequestRow[],
  crossEnvironment: boolean = false, preferredLocalId: string = ''): PullRequestRow[] {
  const merged = new Map<string, PullRequestRow>();
  const insert = (row: PullRequestRow, fromIncoming: boolean): void => {
    const key = pullRequestRowIdentity(row, crossEnvironment);
    const held = merged.get(key);
    if (!held) {
      merged.set(key, row);
      return;
    }
    if (!crossEnvironment) {
      if (fromIncoming) merged.set(key, row);
      return;
    }
    const heldPreferred = !!preferredLocalId && held.localId === preferredLocalId;
    const rowPreferred = !!preferredLocalId && row.localId === preferredLocalId;
    if (rowPreferred && !heldPreferred) {
      merged.set(key, row);
      return;
    }
    if (heldPreferred && !rowPreferred) {
      return;
    }
    if (fromIncoming && comparePullRequestRows(row, held) <= 0) {
      merged.set(key, row);
    }
  };
  for (const row of existing) insert(row, false);
  for (const row of incoming) insert(row, true);
  const result: PullRequestRow[] = [];
  merged.forEach((row: PullRequestRow) => { result.push(row); });
  const hasTimestamps = result.some((row: PullRequestRow) => !!row.updatedAt);
  if (hasTimestamps || crossEnvironment) {
    result.sort(comparePullRequestRows);
  }
  return result;
}

function actor(value: Object | undefined | null): string {
  if (value === undefined || value === null) return '';
  const row = record(value);
  return typeof row.login === 'string' ? row.login : (typeof row.name === 'string' ? row.name : '');
}

function stringOr(value: Object | undefined | null, fallback: string = ''): string {
  return typeof value === 'string' ? value : fallback;
}

export function pullRequestRows(value: Object): { rows: PullRequestRow[]; errors: string[]; truncated: boolean;
  providers: Array<{ kind: string; host: string; configured: boolean; configuredDetail: string }> } {
  const result = record(value);
  const rows = compactArray(objects(result.entries), (entry: Object): PullRequestRow => {
    const row = record(entry);
    const stack = row.stack === undefined || row.stack === null ? undefined : record(row.stack);
    return {
      provider: text(row.provider),
      host: typeof row.host === 'string' ? row.host : '',
      projectId: text(row.projectId), projectTitle: text(row.projectTitle),
      repository: text(row.repository), number: Number(row.number), title: text(row.title), url: text(row.url),
      author: actor(row.author), headBranch: text(row.headBranch), baseBranch: text(row.baseBranch),
      state: text(row.state), draft: row.isDraft === true,
      additions: typeof row.additions === 'number' ? row.additions : 0,
      deletions: typeof row.deletions === 'number' ? row.deletions : 0,
      updatedAt: typeof row.updatedAt === 'string' ? row.updatedAt : '',
      reviewDecision: typeof row.reviewDecision === 'string' ? row.reviewDecision : '',
      checksState: typeof row.checksState === 'string' ? row.checksState : '',
      labels: compactArray(row.labels, (label: Object) => text(record(label).name)),
      stackPosition: stack === undefined ? 0 : Number(stack.position),
      stackSize: stack === undefined ? 0 : Number(stack.size)
    };
  });
  const errors = compactArray(result.errors, (error: Object) => text(record(error).message));
  const providers = compactArray(result.providers, (provider: Object) => {
    const row = record(provider);
    return { kind: text(row.kind), host: text(row.host), configured: row.configured === true,
      configuredDetail: row.detail === null || row.detail === undefined ? '' : text(row.detail) };
  });
  return { rows, errors, truncated: result.truncated === true, providers };
}

export function pullRequestListInput(state: string, query: string, cursor: string = '', projectId: string = '',
  cursors?: Record<string, string>): Object {
  if (!['all', 'open', 'closed', 'merged'].includes(state)) throw new Error('PR 状态无效');
  const input: Record<string, Object> = { state, involvement: 'all', limit: 30 };
  if (query.trim()) input.query = query.trim().slice(0, 200);
  const normalizedCursors = normalizePullRequestCursors(cursors);
  if (hasPullRequestCursors(normalizedCursors)) {
    input.cursors = normalizedCursors;
  } else if (cursor) {
    input.cursors = { default: cursor };
  }
  if (projectId) input.projectId = projectId;
  return input;
}

export function pullRequestRef(projectId: string, repository: string, number: number, host: string = ''): Object {
  if (!projectId || !repository.trim() || !Number.isSafeInteger(number) || number <= 0) throw new Error('PR 标识无效');
  const ref: Record<string, Object> = { projectId, repository, number };
  if (host) ref.host = host;
  return ref;
}

export interface PullRequestDetailView {
  number: number;
  title: string;
  body: string;
  url: string;
  state: string;
  draft: boolean;
  repository: string;
  projectId: string;
  headBranch: string;
  baseBranch: string;
  additions: number;
  deletions: number;
  changedFiles: number;
  mergeable: string;
  mergeMethods: string[];
  actions: string[];
  comment: boolean;
  reviewVerdicts: string[];
  inlineComment: boolean;
  checksState: string;
  checks: Array<{ name: string; state: string; url: string; description: string }>;
  reviewers: string[];
  labels: string[];
  viewer: string;
  activity: PullRequestActivityView;
}

export interface PullRequestCheckView {
  name: string;
  status: string;
  url: string;
  description: string;
}

export interface PullRequestChecksView {
  state: string;
  checks: PullRequestCheckView[];
}

export function pullRequestChecks(value: Object | null | undefined): PullRequestChecksView | undefined {
  if (value === undefined || value === null) return undefined;
  const row = record(value);
  return {
    state: typeof row.state === 'string' ? row.state : '',
    checks: compactArray(row.checks, (check: Object): PullRequestCheckView => {
      const item = record(check);
      return {
        name: typeof item.name === 'string' ? item.name : 'Check',
        status: typeof item.status === 'string' ? item.status : 'unknown',
        url: typeof item.url === 'string' ? item.url : '',
        description: typeof item.description === 'string' ? item.description : ''
      };
    })
  };
}

export interface ReviewGuideFile {
  path: string;
  note: string;
}

export interface ReviewGuideExcerpt {
  path: string;
  side: string;
  start: number;
  end: number;
  caption: string;
}

export interface ReviewGuideNote {
  path: string;
  line: number;
  title: string;
  body: string;
}

export interface ReviewGuideStop {
  title: string;
  summary: string;
  attentionKind: string;
  attentionNote: string;
  files: ReviewGuideFile[];
  excerpts: ReviewGuideExcerpt[];
  notes: ReviewGuideNote[];
  questions: string[];
}

export interface PullRequestGuideView {
  headSha: string;
  generatedAt: string;
  stops: ReviewGuideStop[];
  running: boolean;
  runDetail: string;
  currentHeadSha: string;
  stale: boolean;
}

export function pullRequestGuide(value: Object): PullRequestGuideView {
  const row = record(value);
  const guide = row.guide === undefined || row.guide === null ? undefined : record(row.guide);
  const run = row.run === undefined || row.run === null ? undefined : record(row.run);
  const stops = guide === undefined ? [] : compactArray(guide.stops, (entry: Object): ReviewGuideStop => {
    const stop = record(entry);
    const attention = stop.attention === undefined || stop.attention === null ? undefined : record(stop.attention);
    return {
      title: text(stop.title), summary: typeof stop.summary === 'string' ? stop.summary : '',
      attentionKind: attention === undefined ? '' : text(attention.kind),
      attentionNote: attention === undefined ? '' : text(attention.note),
      files: compactArray(stop.files, (file: Object) => {
        const item = record(file);
        return { path: text(item.path), note: typeof item.note === 'string' ? item.note : '' };
      }),
      excerpts: compactArray(stop.excerpts, (excerpt: Object) => {
        const item = record(excerpt);
        return { path: text(item.path), side: text(item.side), start: Number(item.start),
          end: Number(item.end), caption: typeof item.caption === 'string' ? item.caption : '' };
      }),
      notes: compactArray(stop.notes, (note: Object) => {
        const item = record(note);
        return { path: text(item.path), line: Number(item.line), title: text(item.title),
          body: typeof item.body === 'string' ? item.body : '' };
      }),
      questions: textList(stop.questions)
    };
  });
  const currentHeadSha = row.currentHeadSha === undefined || row.currentHeadSha === null ? '' : text(row.currentHeadSha);
  const headSha = guide === undefined ? '' : text(guide.headSha);
  return {
    headSha: headSha, generatedAt: guide === undefined ? '' : text(guide.generatedAt), stops: stops,
    running: run !== undefined && text(run._tag) === 'Running',
    runDetail: run !== undefined && typeof run.detail === 'string' ? run.detail : '',
    currentHeadSha: currentHeadSha,
    stale: guide !== undefined && currentHeadSha !== '' && headSha !== currentHeadSha
  };
}

export function pullRequestDetail(value: Object): PullRequestDetailView {
  const row = record(value);
  const caps = row.capabilities === undefined ? {} : record(row.capabilities);
  const permissions = row.viewerPermissions === undefined ? {} : record(row.viewerPermissions);
  const review = caps.review === undefined || caps.review === null ? {} : record(caps.review);
  const checks = compactArray(row.checks, (check: Object) => {
    const item = record(check);
    return { name: typeof item.name === 'string' ? item.name : (typeof item.title === 'string' ? item.title : 'Check'),
      state: typeof item.state === 'string' ? item.state :
        (typeof item.status === 'string' ? item.status : String(item.conclusion || 'unknown')),
      url: typeof item.url === 'string' ? item.url : '', description: typeof item.description === 'string' ? item.description : '' };
  });
  return {
    number: Number(row.number), title: text(row.title), body: typeof row.body === 'string' ? row.body : '',
    url: text(row.url), state: text(row.state), draft: row.isDraft === true,
    repository: text(row.repository), projectId: text(row.projectId),
    headBranch: text(row.headBranch), baseBranch: text(row.baseBranch),
    additions: Number(row.additions), deletions: Number(row.deletions), changedFiles: Number(row.changedFiles),
    mergeable: typeof row.mergeability === 'string' ? row.mergeability : String(row.mergeability || 'unknown'),
    mergeMethods: compactArray(caps.mergeMethods, (method: Object) => text(method)),
    actions: compactArray(permissions.actions, (action: Object) => text(action)),
    comment: permissions.comment === true,
    reviewVerdicts: compactArray(review.verdicts, (verdict: Object) => text(verdict)),
    inlineComment: review.inlineComment === true,
    checksState: typeof row.checksState === 'string' ? row.checksState : '',
    checks,
    reviewers: compactArray(row.reviewers, (reviewer: Object) => actor(reviewer)),
    labels: compactArray(row.labels, (label: Object) => text(record(label).name)),
    viewer: typeof row.viewer === 'string' ? row.viewer : '',
    activity: pullRequestActivity(row)
  };
}

export interface PullRequestCommentView {
  id: string;
  author: string;
  body: string;
  createdAt: string;
}

export interface PullRequestThreadCommentView {
  id: string;
  author: string;
  body: string;
}

export interface PullRequestThreadView {
  id: string;
  path: string;
  resolved: boolean;
  comments: PullRequestThreadCommentView[];
}

export interface PullRequestCommitView {
  sha: string;
  subject: string;
}

export interface PullRequestActivityView {
  comments: PullRequestCommentView[];
  threads: PullRequestThreadView[];
  commits: PullRequestCommitView[];
}

export function pullRequestActivity(value: Object): PullRequestActivityView {
  const row = record(value);
  return {
    comments: compactArray(row.comments, (comment: Object): PullRequestCommentView => {
      const item = record(comment);
      return { id: stringOr(item.id), author: actor(item.author), body: stringOr(item.body),
        createdAt: typeof item.createdAt === 'string' ? item.createdAt : '' };
    }),
    threads: compactArray(row.reviewThreads, (thread: Object): PullRequestThreadView => {
      const item = record(thread);
      return { id: stringOr(item.id), path: typeof item.path === 'string' ? item.path : '',
        resolved: item.resolved === true,
        comments: compactArray(item.comments, (comment: Object): PullRequestThreadCommentView => {
          const entry = record(comment);
          return { id: stringOr(entry.id), author: actor(entry.author), body: stringOr(entry.body) };
        }) };
    }),
    commits: compactArray(row.commits, (commit: Object): PullRequestCommitView => {
      const item = record(commit);
      return { sha: stringOr(item.sha), subject: typeof item.subject === 'string' ? item.subject : stringOr(item.message) };
    })
  };
}

export function pullRequestPatch(value: Object): { patch: string; truncated: boolean; nextCursor: string } {
  const row = record(value);
  return { patch: text(row.patch), truncated: row.truncated === true,
    nextCursor: row.nextCursor === null ? '' : text(row.nextCursor) };
}

export function reviewSubmitInput(ref: Object, verdict: string, body: string,
  comments: Object[] = []): Object {
  if (!['comment', 'approve', 'request-changes'].includes(verdict)) throw new Error('审阅结论无效');
  if (body.length > 65536) throw new Error('审阅内容过长');
  return Object.assign({}, ref, { verdict, body, comments });
}

export function reviewCommentDraft(path: string, row: DiffRow, body: string): Object {
  const position: Record<string, Object> = row.kind === 'add' ?
    { kind: 'added', newLine: row.newLine } :
    row.kind === 'del' ? { kind: 'deleted', oldLine: row.oldLine } :
      { kind: 'context', oldLine: row.oldLine, newLine: row.newLine, side: 'right' };
  return { path, position, body };
}

export function commentInput(ref: Object, body: string): Object {
  if (!body.trim() || body.length > 65536) throw new Error('评论内容无效');
  return Object.assign({}, ref, { body });
}

export function actionInput(ref: Object, action: string, mergeMethod: string = '',
  updateMethod: string = ''): Object {
  const source = record(ref);
  const input: Record<string, Object> = {};
  for (const key of Object.keys(source)) input[key] = source[key];
  input.action = action;
  if (mergeMethod) input.mergeMethod = mergeMethod;
  if (updateMethod) input.updateMethod = updateMethod;
  return input;
}

export function pullRequestStateLabel(state: string, draft: boolean): string {
  if (draft) return '草稿';
  return state === 'open' ? '开放' : state === 'merged' ? '已合并' : state === 'closed' ? '已关闭' : state;
}

export function prActionDisabled(action: string, detail: PullRequestDetailView): string {
  if (detail.actions.length === 0) return '服务端未提供 PR 操作能力';
  if (!detail.actions.includes(action)) return '当前账号或仓库不允许此操作';
  if (action === 'merge' && detail.mergeable !== 'mergeable') return 'PR 当前不可合并（' + detail.mergeable + '）';
  return '';
}

export interface LinkedPullRequestView {
  host: string;
  repository: string;
  number: number;
  url: string;
  source: string;
  state: string;
  title: string;
  headBranch: string;
  baseBranch: string;
  draft: boolean;
  watching: boolean;
  stackPosition: number;
  stackSize: number;
}

export function linkedPullRequests(value: Object): LinkedPullRequestView[] {
  const details = record(value);
  if (details.pullRequests === undefined) return [];
  return compactArray(objects(details.pullRequests), (entry: Object): LinkedPullRequestView => {
    const row = record(entry);
    const snapshot = row.snapshot === undefined || row.snapshot === null ? undefined : record(row.snapshot);
    const watch = row.watch === undefined || row.watch === null ? undefined : record(row.watch);
    const stack = row.stack === undefined || row.stack === null ? undefined : record(row.stack);
    const layers = stack === undefined ? [] : compactObjects(stack.layers);
    const layer = layers.find((item: Record<string, Object>) => item.number === row.number);
    return {
      host: text(row.host), repository: text(row.repository), number: Number(row.number),
      url: text(row.url), source: text(row.source),
      state: snapshot ? text(snapshot.state) : '',
      title: snapshot ? text(snapshot.title) : '',
      headBranch: snapshot ? text(snapshot.headBranch) : '',
      baseBranch: snapshot ? text(snapshot.baseBranch) : '',
      draft: snapshot !== undefined && snapshot.isDraft === true,
      watching: watch !== undefined,
      stackPosition: layer && typeof layer.position === 'number' ? layer.position : 0,
      stackSize: layers.length
    };
  });
}

export function linkedPullRequestCommand(type: string, commandId: string, threadId: string,
  link: LinkedPullRequestView, watching: boolean = false): Object {
  if (!threadId || !link.host || !link.repository || !Number.isSafeInteger(link.number) || link.number <= 0) {
    throw new Error('关联 PR 标识无效');
  }
  const command: Record<string, Object> = { type, commandId, threadId, host: link.host,
    repository: link.repository, number: link.number };
  if (type === 'thread.pull-request.watch') {
    command.watching = watching;
    command.link = { url: link.url, source: link.source };
  }
  return command;
}
