import { ModelChoice } from './Core';
import { isListedThread, ScopedThread } from './Projects';
import { ComposerContextRecord, environmentContext, mentionContext, threadContext } from './R4';
import { compactObjects, record } from './Wire';

export type MentionKind = 'thread' | 'environment' | 'model' | 'file';

export interface MentionFileEntry {
  path: string;
  kind: string;
}

export interface MentionEnvironmentCandidate {
  environmentId: string;
  label: string;
}

export interface MentionModelCandidate {
  instanceId: string;
  model: string;
  label: string;
  providerLabel: string;
  providerDriver: string;
  subtitle: string;
}

export interface MentionItem {
  id: string;
  kind: MentionKind;
  label: string;
  description: string;
  environmentId: string;
  threadId: string;
  instanceId: string;
  model: string;
  providerDriver: string;
  path: string;
  fileKind: string;
}

export interface ComposerInlineTrigger {
  kind: 'mention';
  query: string;
  rangeStart: number;
  rangeEnd: number;
}

export interface TextReplacementResult {
  text: string;
  cursor: number;
}

export interface ParsedComposerContextHref {
  kind: string;
  contextId: string;
}

export interface ComposedContextMessage {
  text: string;
  context: ComposerContextRecord[];
}

export interface MatchMentionThreadsInput {
  threads: ScopedThread[];
  currentEnvironmentId: string;
  linkedEnvironmentLabels: Record<string, string>;
  excludeThreadId: string;
  query: string;
  limit?: number;
  allowEmptyQuery?: boolean;
}

export interface MatchMentionEnvironmentsInput {
  environments: MentionEnvironmentCandidate[];
  linkedEnvironmentLabels: Record<string, string>;
  currentEnvironmentId: string;
  offersLinkedEnvironments: boolean;
  query: string;
  limit?: number;
  allowEmptyQuery?: boolean;
}

const CONTEXT_HREF_PREFIX = 't3-context://v1/';
const CONTEXT_KIND_PATTERN = /^[a-z][a-z0-9-]{0,39}$/;
const CONTEXT_ID_PATTERN = /^[a-z0-9_-]{1,128}$/i;
const CONTEXT_LINK_PATTERN = /(!?)\[([^[\]\n]{0,512})\]\((t3-context:\/\/v1\/[^\s)]{1,200})\)/g;
const CONTEXT_LABEL_MAX_CHARS = 200;

function isWhitespaceChar(char: string): boolean {
  return char === ' ' || char === '\n' || char === '\t' || char === '\r';
}

function clampCursor(text: string, cursor: number): number {
  if (!Number.isFinite(cursor)) return text.length;
  return Math.max(0, Math.min(text.length, Math.floor(cursor)));
}

/** Detects an active `@query` mention token ending at the caret, matching upstream composerTrigger. */
export function detectInlineMentionTrigger(text: string, cursorInput: number): ComposerInlineTrigger | undefined {
  const cursor = clampCursor(text, cursorInput);
  let tokenIdx = cursor - 1;
  while (tokenIdx >= 0 && !isWhitespaceChar(text[tokenIdx] || '')) {
    tokenIdx -= 1;
  }
  const tokenStart = tokenIdx + 1;
  const token = text.slice(tokenStart, cursor);
  if (!token.startsWith('@')) return undefined;
  return {
    kind: 'mention',
    query: token.slice(1),
    rangeStart: tokenStart,
    rangeEnd: cursor
  };
}

export function replaceTextRange(
  text: string,
  rangeStart: number,
  rangeEnd: number,
  replacement: string
): TextReplacementResult {
  const safeStart = Math.max(0, Math.min(text.length, rangeStart));
  const safeEnd = Math.max(safeStart, Math.min(text.length, rangeEnd));
  const nextText = text.slice(0, safeStart) + replacement + text.slice(safeEnd);
  return { text: nextText, cursor: safeStart + replacement.length };
}

function fnv1a64(value: string): string {
  let forward = 0x811c9dc5;
  let reverse = 0x9dc5811c;
  for (let index = 0; index < value.length; index += 1) {
    forward ^= value.charCodeAt(index);
    forward = Math.imul(forward, 0x01000193) >>> 0;
    reverse ^= value.charCodeAt(value.length - 1 - index);
    reverse = Math.imul(reverse, 0x01000193) >>> 0;
  }
  return forward.toString(16).padStart(8, '0') + reverse.toString(16).padStart(8, '0');
}

export function toComposerContextId(producerId: string): string {
  if (CONTEXT_ID_PATTERN.test(producerId)) return producerId;
  const slug = producerId
    .replace(/[^a-z0-9_-]+/gi, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 48);
  return (slug || 'ctx') + '-' + fnv1a64(producerId);
}

export function toKindScopedComposerContextId(kind: string, producerId: string): string {
  return toComposerContextId(kind + '_' + producerId);
}

export function sanitizeComposerContextLabel(label: string, kind: string): string {
  const normalized = (label || '')
    .replace(/[[\]\\\r\n]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  let end = CONTEXT_LABEL_MAX_CHARS;
  if (normalized.length > end) {
    const before = normalized.charCodeAt(end - 1);
    const after = normalized.charCodeAt(end);
    if (before >= 0xd800 && before <= 0xdbff && after >= 0xdc00 && after <= 0xdfff) end -= 1;
  }
  const cleaned = normalized.slice(0, end);
  return cleaned.length > 0 ? cleaned : kind;
}

export function formatComposerContextReference(kind: string, contextId: string, label: string): string {
  const cleanLabel = sanitizeComposerContextLabel(label, kind);
  const prefix = kind === 'image' ? '!' : '';
  return prefix + '[' + cleanLabel + '](' + CONTEXT_HREF_PREFIX + kind + '/' + contextId + ')';
}

export function parseComposerContextHref(href: string): ParsedComposerContextHref | undefined {
  if (!href || !href.startsWith(CONTEXT_HREF_PREFIX)) return undefined;
  const rest = href.slice(CONTEXT_HREF_PREFIX.length);
  const parts = rest.split('/');
  if (parts.length !== 2) return undefined;
  const kind = parts[0];
  const contextId = parts[1];
  if (!CONTEXT_KIND_PATTERN.test(kind) || !CONTEXT_ID_PATTERN.test(contextId)) return undefined;
  return { kind, contextId };
}

export function collectComposerContextIds(text: string): Set<string> {
  const ids: Set<string> = new Set();
  if (!text || !text.includes('](' + CONTEXT_HREF_PREFIX)) return ids;
  CONTEXT_LINK_PATTERN.lastIndex = 0;
  let match: RegExpExecArray | null = CONTEXT_LINK_PATTERN.exec(text);
  while (match !== null) {
    const parsed = parseComposerContextHref(match[3]);
    if (parsed) ids.add(parsed.contextId);
    match = CONTEXT_LINK_PATTERN.exec(text);
  }
  return ids;
}

/**
 * Ensures every structured context record has an inline `t3-context://v1/<kind>/<contextId>`
 * reference in the wire message text so the server's `projectComposerContextForProvider` expands
 * it into `<t3_context>` for the agent. Appends references so leading slash commands stay intact.
 */
export function composeMessageWithContexts(
  prompt: string,
  context: ComposerContextRecord[]
): ComposedContextMessage {
  if (!context || context.length === 0) {
    return { text: prompt, context: [] };
  }
  const referenced = collectComposerContextIds(prompt);
  const missing: string[] = [];
  for (const item of context) {
    if (!item || !item.contextId || referenced.has(item.contextId)) continue;
    referenced.add(item.contextId);
    missing.push(formatComposerContextReference(item.kind, item.contextId, item.label));
  }
  if (missing.length === 0) {
    return { text: prompt, context };
  }
  const suffix = missing.join(' ');
  const text = prompt.trim().length > 0 ? prompt.trimEnd() + '\n\n' + suffix : suffix;
  return { text, context };
}

export function deterministicThreadContext(
  environmentId: string,
  threadId: string,
  title: string
): ComposerContextRecord {
  const cleanTitle = sanitizeComposerContextLabel(title, 'thread');
  return threadContext(
    environmentId,
    threadId,
    cleanTitle,
    toKindScopedComposerContextId('thread', threadId)
  );
}

export function deterministicEnvironmentContext(
  environmentId: string,
  label: string
): ComposerContextRecord {
  const cleanLabel = sanitizeComposerContextLabel(label, 'environment');
  return environmentContext(
    environmentId,
    cleanLabel,
    toKindScopedComposerContextId('environment', environmentId)
  );
}

export function deterministicFileContext(path: string): ComposerContextRecord {
  return mentionContext(path, toKindScopedComposerContextId('mention', path));
}

export function formatComposerModelMention(instanceId: string, model: string): string {
  return 'model:' + instanceId.trim() + '/' + model.trim();
}

export function extractMentionModelCandidates(
  config: Object | undefined,
  fallbackModels: ModelChoice[]
): MentionModelCandidate[] {
  const result: MentionModelCandidate[] = [];
  const seen: Set<string> = new Set();
  if (config !== undefined && config !== null && typeof config === 'object' && !Array.isArray(config)) {
    const root = record(config);
    for (const provider of compactObjects(root.providers)) {
      const instanceId = typeof provider.instanceId === 'string' ? provider.instanceId.trim() : '';
      if (!instanceId) continue;
      if (provider.installed === false || provider.enabled === false) continue;
      const status = typeof provider.status === 'string' ? provider.status : '';
      if (status && status !== 'ready') continue;
      const availability = typeof provider.availability === 'string' ? provider.availability : '';
      if (availability === 'unavailable') continue;
      const auth = provider.auth !== undefined && provider.auth !== null && typeof provider.auth === 'object' && !Array.isArray(provider.auth)
        ? provider.auth as Record<string, Object> : undefined;
      if (auth && auth.status === 'unauthenticated') continue;
      const driver = typeof provider.driver === 'string' && provider.driver.trim() ? provider.driver.trim() : instanceId;
      const providerLabel =
        (typeof provider.displayName === 'string' && provider.displayName.trim()) ||
        (typeof provider.label === 'string' && provider.label.trim()) ||
        (typeof provider.name === 'string' && provider.name.trim()) ||
        instanceId;
      for (const modelRow of compactObjects(provider.models)) {
        const slug = typeof modelRow.slug === 'string' ? modelRow.slug.trim() : '';
        if (!slug) continue;
        if (modelRow.hidden === true || modelRow.legacy === true || modelRow.unavailable === true) continue;
        const key = instanceId + '\0' + slug;
        if (seen.has(key)) continue;
        seen.add(key);
        const label = typeof modelRow.name === 'string' && modelRow.name.trim() ? modelRow.name.trim() : slug;
        const subtitle =
          (typeof modelRow.subProvider === 'string' && modelRow.subProvider.trim()) ||
          (typeof modelRow.subtitle === 'string' && modelRow.subtitle.trim()) ||
          '';
        result.push({
          instanceId,
          model: slug,
          label,
          providerLabel,
          providerDriver: driver,
          subtitle
        });
      }
    }
  }
  if (result.length > 0) return result;
  for (const choice of fallbackModels) {
    if (!choice.instanceId || !choice.model || choice.hidden === true || choice.legacy === true) continue;
    const key = choice.instanceId + '\0' + choice.model;
    if (seen.has(key)) continue;
    seen.add(key);
    const label = choice.name && choice.name.trim() ? choice.name.trim() :
      (choice.label.includes(' / ') ? choice.label.split(' / ').slice(1).join(' / ') : choice.model);
    result.push({
      instanceId: choice.instanceId,
      model: choice.model,
      label,
      providerLabel: choice.instanceId,
      providerDriver: choice.instanceId,
      subtitle: ''
    });
  }
  return result;
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function parseTimestampMs(iso: string): number {
  if (!iso) return 0;
  const parsed = Date.parse(iso);
  return Number.isFinite(parsed) ? parsed : 0;
}

function threadRecencyMs(thread: ScopedThread): number {
  return Math.max(
    parseTimestampMs(thread.updatedAt),
    parseTimestampMs(thread.latestUserMessageAt),
    parseTimestampMs(thread.createdAt)
  );
}

function scoreFieldMatch(field: string, token: string): number {
  const lower = field.toLowerCase();
  if (!lower) return -1;
  if (lower === token) return 0;
  if (lower.startsWith(token)) return 2;
  const idx = lower.indexOf(token);
  if (idx < 0) return -1;
  const prev = lower[idx - 1];
  if (prev === ' ' || prev === '-' || prev === '_' || prev === '/' || prev === ':' || prev === '.') {
    return 4;
  }
  return 6;
}

interface RankedThread {
  thread: ScopedThread;
  score: number;
  recency: number;
  ownSideChat: boolean;
}

export function matchMentionThreads(input: MatchMentionThreadsInput): MentionItem[] {
  const trimmed = input.query.trim().toLowerCase();
  const limit = input.limit !== undefined && input.limit > 0 ? input.limit : 5;
  if (!trimmed && input.allowEmptyQuery !== true) return [];
  const tokens = trimmed ? trimmed.split(/\s+/).filter((t: string) => t.length > 0) : [];
  const seen: Set<string> = new Set();
  const ranked: RankedThread[] = [];

  for (const thread of input.threads) {
    if (!thread.id || !thread.environmentId) continue;
    const isCurrentEnv = thread.environmentId === input.currentEnvironmentId;
    const linkedLabel = input.linkedEnvironmentLabels[thread.environmentId] || '';
    if (!isCurrentEnv && !linkedLabel) continue;
    if (input.excludeThreadId && thread.id === input.excludeThreadId && isCurrentEnv) continue;
    if (thread.archivedAt || thread.deletedAt) continue;

    const ownSideChat = thread.lineageSideChat === true &&
      isCurrentEnv &&
      !!input.excludeThreadId &&
      thread.lineageParentThreadId === input.excludeThreadId &&
      !!thread.latestUserMessageAt;
    if (!isListedThread(thread) && !ownSideChat) continue;

    const dedupeKey = thread.environmentId + '\0' + thread.id;
    if (seen.has(dedupeKey)) continue;
    seen.add(dedupeKey);

    let totalScore = 0;
    if (tokens.length > 0) {
      let matchedAll = true;
      for (const token of tokens) {
        let best = -1;
        const titleScore = scoreFieldMatch(thread.label || '', token);
        if (titleScore >= 0) best = titleScore;
        const projectScore = scoreFieldMatch(thread.projectLabel || '', token);
        if (projectScore >= 0 && (best < 0 || projectScore + 20 < best)) best = projectScore + 20;
        const branchScore = scoreFieldMatch(thread.branch || '', token);
        if (branchScore >= 0 && (best < 0 || branchScore + 30 < best)) best = branchScore + 30;
        const envName = isCurrentEnv ? (thread.environmentLabel || '') : (linkedLabel || thread.environmentLabel || '');
        const envScore = scoreFieldMatch(envName, token);
        if (envScore >= 0 && (best < 0 || envScore + 35 < best)) best = envScore + 35;
        const idScore = scoreFieldMatch(thread.id, token);
        if (idScore >= 0 && (best < 0 || idScore + 45 < best)) best = idScore + 45;
        if (best < 0) {
          matchedAll = false;
          break;
        }
        totalScore += best;
      }
      if (!matchedAll) continue;
    }

    ranked.push({
      thread,
      score: totalScore,
      recency: threadRecencyMs(thread),
      ownSideChat
    });
  }

  ranked.sort((a: RankedThread, b: RankedThread) => {
    if (a.score !== b.score) return a.score - b.score;
    if (a.recency !== b.recency) return b.recency - a.recency;
    return a.thread.id.localeCompare(b.thread.id);
  });

  return ranked.slice(0, limit).map((entry: RankedThread): MentionItem => {
    const t = entry.thread;
    const isCurrentEnv = t.environmentId === input.currentEnvironmentId;
    const remoteMachine = isCurrentEnv ? '' : (input.linkedEnvironmentLabels[t.environmentId] || t.environmentLabel || t.environmentId);
    const description = entry.ownSideChat
      ? '侧聊'
      : remoteMachine
        ? '会话 · ' + remoteMachine
        : (t.projectLabel ? '会话 · ' + t.projectLabel : '会话');
    return {
      id: 'thread:' + t.environmentId + ':' + t.id,
      kind: 'thread',
      label: t.label.trim() || '未命名会话',
      description,
      environmentId: t.environmentId,
      threadId: t.id,
      instanceId: '',
      model: '',
      providerDriver: '',
      path: '',
      fileKind: ''
    };
  });
}

export function matchMentionEnvironments(input: MatchMentionEnvironmentsInput): MentionItem[] {
  if (!input.offersLinkedEnvironments) return [];
  const query = input.query.trim().toLowerCase();
  if (!query && input.allowEmptyQuery !== true) return [];
  const limit = input.limit !== undefined && input.limit > 0 ? input.limit : 5;
  const seen: Set<string> = new Set();
  const candidates: MentionEnvironmentCandidate[] = [];

  for (const env of input.environments) {
    const envId = env.environmentId.trim();
    if (!envId || envId === input.currentEnvironmentId || seen.has(envId)) continue;
    seen.add(envId);
    candidates.push({ environmentId: envId, label: env.label.trim() || envId });
  }
  for (const envId of Object.keys(input.linkedEnvironmentLabels)) {
    const cleanId = envId.trim();
    if (!cleanId || cleanId === input.currentEnvironmentId || seen.has(cleanId)) continue;
    seen.add(cleanId);
    const label = (input.linkedEnvironmentLabels[envId] || '').trim() || cleanId;
    candidates.push({ environmentId: cleanId, label });
  }

  return candidates
    .filter((candidate: MentionEnvironmentCandidate) =>
      !query ||
      candidate.label.toLowerCase().includes(query) ||
      candidate.environmentId.toLowerCase().includes(query))
    .slice(0, limit)
    .map((candidate: MentionEnvironmentCandidate): MentionItem => ({
      id: 'environment:' + candidate.environmentId,
      kind: 'environment',
      label: candidate.label,
      description: '环境 · 机器',
      environmentId: candidate.environmentId,
      threadId: '',
      instanceId: '',
      model: '',
      providerDriver: '',
      path: '',
      fileKind: ''
    }));
}

function modelSearchQueries(query: string, requireMinQuery: boolean): string[] {
  const spaced = query.replace(/[:/]+/g, ' ').trim();
  const unhyphenated = spaced.replace(/-+/g, ' ').trim();
  if (requireMinQuery && unhyphenated.replace(/\s+/g, '').length < 2) return [];
  if (!unhyphenated) return [];
  return unhyphenated === spaced ? [spaced] : [spaced, unhyphenated];
}

interface RankedModel {
  candidate: MentionModelCandidate;
  score: number;
}

export function matchMentionModels(
  candidates: MentionModelCandidate[],
  query: string,
  limit: number = 8,
  requireMinQuery: boolean = true
): MentionItem[] {
  const variants = modelSearchQueries(query, requireMinQuery);
  if (variants.length === 0) return [];
  for (const words of variants) {
    const tokens = words.toLowerCase().split(/\s+/).filter((t: string) => t.length > 0);
    if (tokens.length === 0) continue;
    const patterns = tokens.map((token: string) => new RegExp('(?:^|[^a-z0-9\\u4e00-\\u9fff])' + escapeRegExp(token), 'i'));
    const ranked: RankedModel[] = [];
    for (const candidate of candidates) {
      const haystack = [
        candidate.label,
        candidate.model,
        candidate.subtitle,
        candidate.providerDriver,
        candidate.providerLabel
      ].join(' ').toLowerCase();
      if (!patterns.every((pattern: RegExp) => pattern.test(haystack))) continue;
      let score = 0;
      for (const token of tokens) {
        const nameScore = scoreFieldMatch(candidate.label, token);
        const slugScore = scoreFieldMatch(candidate.model, token);
        const provScore = scoreFieldMatch(candidate.providerLabel + ' ' + candidate.providerDriver, token);
        let best = 20;
        if (nameScore >= 0 && nameScore < best) best = nameScore;
        if (slugScore >= 0 && slugScore + 2 < best) best = slugScore + 2;
        if (provScore >= 0 && provScore + 8 < best) best = provScore + 8;
        score += best;
      }
      ranked.push({ candidate, score });
    }
    if (ranked.length > 0) {
      ranked.sort((a: RankedModel, b: RankedModel) =>
        a.score !== b.score ? a.score - b.score : a.candidate.label.localeCompare(b.candidate.label));
      return ranked.slice(0, limit).map((entry: RankedModel): MentionItem => {
        const c = entry.candidate;
        return {
          id: 'model:' + c.instanceId + ':' + c.model,
          kind: 'model',
          label: c.label,
          description: c.subtitle ? (c.providerLabel + ' · ' + c.subtitle) : c.providerLabel,
          environmentId: '',
          threadId: '',
          instanceId: c.instanceId,
          model: c.model,
          providerDriver: c.providerDriver,
          path: '',
          fileKind: ''
        };
      });
    }
  }
  return [];
}

export function mentionFileItems(
  entries: MentionFileEntry[],
  limit: number = 20
): MentionItem[] {
  const result: MentionItem[] = [];
  const seen: Set<string> = new Set();
  for (const entry of entries) {
    const path = (entry.path || '').trim();
    if (!path || seen.has(path)) continue;
    seen.add(path);
    const parts = path.split('/');
    const base = parts[parts.length - 1] || path;
    const dir = parts.length > 1 ? parts.slice(0, -1).join('/') : '';
    result.push({
      id: 'file:' + path,
      kind: 'file',
      label: base,
      description: dir || (entry.kind === 'directory' ? '工作区目录' : '工作区文件'),
      environmentId: '',
      threadId: '',
      instanceId: '',
      model: '',
      providerDriver: '',
      path,
      fileKind: entry.kind === 'directory' ? 'directory' : 'file'
    });
    if (result.length >= limit) break;
  }
  return result;
}
