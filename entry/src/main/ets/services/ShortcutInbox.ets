import { Want } from '@kit.AbilityKit';

export type ShortcutAction = 'new-task' | 'sessions';
export interface ShortcutRequest { id: number; action: ShortcutAction; }

const MAX_SHORTCUT_AGE_MS = 30000;
const MAX_FORM_PARAMS_LENGTH = 256;
let pending: ShortcutRequest | undefined = undefined;
let receivedAt = 0;
let sequence = 0;

function formParams(value: Object | undefined): Record<string, Object> | undefined {
  if (typeof value !== 'string' || value.length > MAX_FORM_PARAMS_LENGTH) return undefined;
  try {
    const parsed = JSON.parse(value) as Object;
    return parsed !== null && typeof parsed === 'object' && !Array.isArray(parsed)
      ? parsed as Record<string, Object> : undefined;
  } catch (_) { return undefined; }
}

// A launcher Want requests navigation only. Never retain its URI or other parameters.
export function acceptShortcutWant(want: Want): boolean {
  const direct = want.parameters?.['t3ShortcutAction'];
  // FormLink delivers its params as a JSON string under Want.parameters.params.
  const nested = formParams(want.parameters?.['params']);
  const nestedAction = nested?.['t3ShortcutAction'];
  if (direct === undefined && nestedAction === undefined) return false;
  if (nestedAction !== undefined && ((direct !== undefined && direct !== nestedAction) || (nested && Object.keys(nested).length !== 1))) return true;
  const action = direct === undefined ? nestedAction : direct;
  if ((action === 'new-task' || action === 'sessions') && !want.uri &&
    want.action !== 'ohos.want.action.sendData' && want.action !== 'ohos.want.action.viewData') {
    pending = { id: ++sequence, action: action as ShortcutAction };
    receivedAt = Date.now();
    AppStorage.setOrCreate('t3ShortcutGeneration', sequence);
  }
  return true;
}

export function peekShortcut(): ShortcutRequest | undefined {
  if (pending) {
    const elapsed = Date.now() - receivedAt;
    if (elapsed < 0 || elapsed >= MAX_SHORTCUT_AGE_MS) pending = undefined;
  }
  return pending;
}

export function consumeShortcut(id: number): boolean {
  if (peekShortcut()?.id !== id) return false;
  pending = undefined;
  return true;
}
