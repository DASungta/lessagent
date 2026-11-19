// Harmony SDK key codes; kept platform-free so shortcut guards run in host tests.
export const KEY_F = 2022;
export const KEY_N = 2030;
export const KEY_ENTER = 2054;
export const KEY_ESCAPE = 2070;
export const KEY_META_LEFT = 2076;
export const KEY_META_RIGHT = 2077;

export interface KeyboardInput {
  keyCode: number;
  down: boolean;
  keyboard: boolean;
  deviceId: number;
  ctrl: boolean;
  alt: boolean;
  shift: boolean;
}

export interface KeyboardContext {
  foreground: boolean;
  composing: boolean;
  textFocused: boolean;
  composerFocused: boolean;
  blocked: boolean;
  busy: boolean;
  unknownSubmission: boolean;
  canSend: boolean;
  canSearch: boolean;
  canNewTask: boolean;
  canBack: boolean;
}

export interface KeyboardHelpItem {
  keys: string;
  action: string;
  detail: string;
}

export const KEYBOARD_HELP: KeyboardHelpItem[] = [
  { keys: 'Ctrl / Cmd + F', action: '搜索会话', detail: '未编辑文字时，打开会话搜索。' },
  { keys: 'Ctrl / Cmd + N', action: '新建任务', detail: '未编辑文字时，打开项目选择。' },
  { keys: 'Esc', action: '返回', detail: '未编辑文字时，返回上一页；输入时留给输入法。' },
  { keys: 'Ctrl / Cmd + Enter', action: '发送消息', detail: '仅在消息输入框中生效，沿用当前发送模式与安全检查。' },
  { keys: 'Enter / Shift + Enter', action: '换行', detail: '不会通过快捷键自动发送消息。' }
];

export class KeyboardCommands {
  private pressed: Set<number> = new Set();
  private deviceId: number = -1;

  reset(): void { this.pressed.clear(); this.deviceId = -1; }

  handle(input: KeyboardInput, context: KeyboardContext): string {
    if (!input.keyboard || !context.foreground) { this.reset(); return ''; }
    if (input.deviceId !== this.deviceId) { this.reset(); this.deviceId = input.deviceId; }
    if (!input.down) { this.pressed.delete(input.keyCode); return ''; }
    const repeated = this.pressed.has(input.keyCode);
    this.pressed.add(input.keyCode);
    if (repeated || context.composing || context.blocked || context.busy || context.unknownSubmission) return '';
    const meta = this.pressed.has(KEY_META_LEFT) || this.pressed.has(KEY_META_RIGHT);
    const modifier = (input.ctrl || meta) && !(input.ctrl && meta);
    if (input.alt || input.shift) return '';
    if (input.keyCode === KEY_ESCAPE && !modifier && !input.ctrl && !meta && !context.textFocused)
      return context.canBack ? 'back' : '';
    if (!modifier) return '';
    if (input.keyCode === KEY_ENTER)
      return context.composerFocused && context.canSend ? 'send' : '';
    if (context.textFocused) return '';
    if (input.keyCode === KEY_F && context.canSearch) return 'search';
    if (input.keyCode === KEY_N && context.canNewTask) return 'new-task';
    return '';
  }
}
