import { ThreadView } from './Projects';

export type SideThreadOpenTarget = 'panel' | 'main';
export const DEFAULT_SIDE_THREAD_OPEN_TARGET: SideThreadOpenTarget = 'panel';

export type SideThreadKind = 'side-chat' | 'subagent' | 'provider-subagent' | 'linked';
export type SideThreadComposer = 'composer' | 'read-only' | 'read-only-connect';
export type SideThreadOpenIntent = 'primary' | 'alternate' | SideThreadOpenTarget;

export function parseSideThreadOpenTarget(value: Object | undefined): SideThreadOpenTarget {
  if (value === 'main') return 'main';
  return DEFAULT_SIDE_THREAD_OPEN_TARGET;
}

export function validSideThreadOpenTarget(value: Object | undefined): boolean {
  return value === 'panel' || value === 'main';
}

export interface ThreadLineageLike {
  lineageSideChat: boolean;
  lineageParentThreadId: string;
  lineageRelationship: string;
  creationSource?: string;
}

export function sideThreadKindOf(thread: ThreadLineageLike | undefined): 'side-chat' | 'subagent' | 'provider-subagent' | undefined {
  if (!thread) return undefined;
  if (thread.lineageSideChat && thread.lineageParentThreadId) return 'side-chat';
  if (thread.lineageRelationship !== 'subagent') return undefined;
  return thread.creationSource === 'provider' ? 'provider-subagent' : 'subagent';
}

export function sideThreadComposer(kind: SideThreadKind): SideThreadComposer {
  if (kind === 'linked') return 'read-only-connect';
  if (kind === 'provider-subagent') return 'read-only';
  return 'composer';
}

export function resolveSideThreadOpenTarget(
  preference: SideThreadOpenTarget,
  intent: SideThreadOpenIntent = 'primary',
  panelAvailable: boolean = true
): SideThreadOpenTarget {
  if (!panelAvailable) return 'main';
  if (intent === 'primary') return preference;
  if (intent === 'alternate') return preference === 'panel' ? 'main' : 'panel';
  return intent;
}

export interface SideThreadTarget {
  kind: 'side-chat' | 'subagent' | 'provider-subagent';
  localId: string;
  environmentId: string;
  environmentLabel: string;
  threadId: string;
  title: string;
}

export interface SideThreadReturnPoint {
  localId: string;
  threadId: string;
  scrollY: number;
  scrollIndex: number;
}

const MAX_RETURN_STACK = 20;

export function pushSideThreadReturn(
  stack: SideThreadReturnPoint[],
  point: SideThreadReturnPoint
): SideThreadReturnPoint[] {
  if (!point.localId || !point.threadId) return stack.slice();
  const next = stack.slice();
  const top = next.length > 0 ? next[next.length - 1] : undefined;
  if (top && top.localId === point.localId && top.threadId === point.threadId) {
    next[next.length - 1] = point;
    return next;
  }
  next.push(point);
  if (next.length > MAX_RETURN_STACK) {
    return next.slice(next.length - MAX_RETURN_STACK);
  }
  return next;
}

export interface PopSideThreadReturnResult {
  point: SideThreadReturnPoint | undefined;
  rest: SideThreadReturnPoint[];
}

export function popSideThreadReturn(stack: SideThreadReturnPoint[]): PopSideThreadReturnResult {
  if (stack.length === 0) return { point: undefined, rest: [] };
  const point = stack[stack.length - 1];
  return { point, rest: stack.slice(0, stack.length - 1) };
}

export function sideChatsForThread(threads: ThreadView[], parentThreadId: string): ThreadView[] {
  const parentId = parentThreadId.trim();
  if (!parentId) return [];
  return threads
    .filter((t: ThreadView) => !t.archivedAt && !t.deletedAt && t.lineageSideChat && t.lineageParentThreadId === parentId)
    .sort((a: ThreadView, b: ThreadView) => Date.parse(b.updatedAt || b.createdAt || '') - Date.parse(a.updatedAt || a.createdAt || ''));
}

export function sideThreadKindLabel(kind: SideThreadKind): string {
  if (kind === 'side-chat') return '侧聊';
  if (kind === 'provider-subagent') return 'Provider 子智能体';
  if (kind === 'subagent') return '子智能体';
  return '链接环境会话';
}
