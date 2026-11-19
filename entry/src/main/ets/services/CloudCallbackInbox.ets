let pending: string = '';

// A callback only reaches the auth service after exact state/PKCE validation; this inbox holds no token.
export function acceptCloudCallback(uri: string): void {
  if (!uri) return;
  if (!/^t3code:\/\/auth\/callback(?:[/?]|$)/i.test(uri)) return;
  pending = uri;
  AppStorage.setOrCreate('t3CloudCallbackRevision',
    (AppStorage.get<number>('t3CloudCallbackRevision') || 0) + 1);
}

export function takeCloudCallback(): string {
  const value = pending;
  pending = '';
  return value;
}
