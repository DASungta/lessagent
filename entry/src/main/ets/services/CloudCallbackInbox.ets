import { isCloudCallbackUri } from '../protocol/Cloud';

let pending: string = '';

// A callback only reaches the auth service after exact redirect validation; this inbox holds no token.
export function acceptCloudCallback(uri: string): boolean {
  if (!uri) return false;
  if (!isCloudCallbackUri(uri)) return false;
  pending = uri;
  AppStorage.setOrCreate('t3CloudCallbackRevision',
    (AppStorage.get<number>('t3CloudCallbackRevision') || 0) + 1);
  return true;
}

export function takeCloudCallback(): string {
  const value = pending;
  pending = '';
  return value;
}
