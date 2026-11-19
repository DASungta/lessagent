import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { appearanceMode } from '../protocol/Settings';

export let currentAppearance: string = 'system';

export async function prepareAppearance(context: common.Context): Promise<void> {
  const store = await preferences.getPreferences(context, 'appearance');
  const value = await store.get('mode', 'system');
  const mode = typeof value === 'string' ? value : 'system';
  context.getApplicationContext().setColorMode(appearanceMode(mode) as ConfigurationConstant.ColorMode);
  currentAppearance = mode;
}

export async function saveAppearance(context: common.Context, mode: string): Promise<void> {
  const color = appearanceMode(mode);
  const previous = currentAppearance;
  const store = await preferences.getPreferences(context, 'appearance');
  await store.put('mode', mode);
  try {
    await store.flush();
    context.getApplicationContext().setColorMode(color as ConfigurationConstant.ColorMode);
    currentAppearance = mode;
  } catch (_) {
    await store.put('mode', previous);
    await store.flush();
    throw new Error('外观保存失败，请重试');
  }
}
