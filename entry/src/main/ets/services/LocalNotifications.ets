import { common, Want, wantAgent, bundleManager } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { NotificationTarget, NotificationRun, NOTIFICATION_ACTION, notificationTarget,
  sameNotificationTarget, notificationTargetKey, RunNotificationTracker } from '../protocol/LocalNotifications';

const tracker = new RunNotificationTracker();
interface ObservedThread { identity: Object; generation: number; }
const observedThreads: Map<string, ObservedThread> = new Map();
let context: common.UIAbilityContext | undefined = undefined;
let enabled: boolean = false;
let generation: number = 0;
let nextId: number = 1000;
let visible: NotificationTarget | undefined = undefined;
let pendingTarget: NotificationTarget | undefined = undefined;
let validTarget: (target: NotificationTarget) => boolean = () => false;

function notificationStatus(message: string): void {
  AppStorage.setOrCreate('t3LocalNotificationStatus', new Date().toLocaleTimeString() + ' · ' + message);
}
export async function localNotificationPermission(): Promise<boolean> {
  return notificationManager.isNotificationEnabled();
}

export async function prepareLocalNotifications(abilityContext: common.UIAbilityContext): Promise<void> {
  context = abilityContext;
  const store = await preferences.getPreferences(abilityContext, 'local-notifications');
  enabled = (await store.get('enabled', false)) === true;
  AppStorage.setOrCreate('t3LocalNotificationsEnabled', enabled);
}
export function configureNotificationTargets(validate: (target: NotificationTarget) => boolean): void { validTarget = validate; }
export function setVisibleNotificationThread(target: NotificationTarget | undefined): void { visible = target; }
export function seedRunNotifications(target: NotificationTarget, runs: NotificationRun[]): void {
  tracker.snapshot(target, runs);
}
export async function observeThreadNotifications(target: NotificationTarget, connectionGeneration: number,
  snapshotIdentity: Object, runs: NotificationRun[]): Promise<void> {
  const key = notificationTargetKey(target);
  const previous = observedThreads.get(key);
  if (!previous || previous.identity !== snapshotIdentity || previous.generation !== connectionGeneration) {
    if (observedThreads.size >= 128 && !observedThreads.has(key)) {
      const first = observedThreads.keys().next();
      if (!first.done) observedThreads.delete(first.value);
    }
    observedThreads.set(key, { identity: snapshotIdentity, generation: connectionGeneration });
    seedRunNotifications(target, runs);
    notificationStatus('连接基线已更新，不补发历史状态');
    return;
  }
  for (const run of runs) await observeRunNotification(target, run);
}
export function localNotificationsEnabled(): boolean { return enabled; }
export async function setLocalNotificationsEnabled(value: boolean): Promise<void> {
  if (!context) throw new Error('通知尚未初始化');
  if (value) {
    await notificationManager.requestEnableNotification(context);
    if (!await notificationManager.isNotificationEnabled()) throw new Error('系统尚未允许通知');
  }
  const store = await preferences.getPreferences(context, 'local-notifications');
  await store.put('enabled', value);
  try { await store.flush(); }
  catch (_) { await store.put('enabled', enabled); await store.flush(); throw new Error('通知设置保存失败'); }
  enabled = value; generation++;
  AppStorage.setOrCreate('t3LocalNotificationsEnabled', enabled);
  notificationStatus(value ? '任务通知已启用，等待新的在线状态变化' : '任务通知已关闭');
  if (!value) {
    tracker.clear(); observedThreads.clear();
    pendingTarget = undefined;
    await notificationManager.cancelAll();
  }
}
export async function observeRunNotification(target: NotificationTarget, run: NotificationRun): Promise<void> {
  const changed = tracker.update(target, run);
  if (!changed) return;
  if (!enabled || !context) { notificationStatus('已观察到结束状态；本地通知未启用'); return; }
  if (!validTarget(target)) { notificationStatus('已观察到结束状态；目标不在当前可用环境会话中'); return; }
  if (AppStorage.get<boolean>('t3Foreground') !== false && visible && sameNotificationTarget(target, visible)) {
    notificationStatus('已观察到结束状态；当前会话正在前台显示，已抑制通知'); return;
  }
  const version = generation;
  let stage = '检查系统权限';
  try {
    if (!await notificationManager.isNotificationEnabled()) { notificationStatus('系统通知权限未开启，未发布'); return; }
    stage = '创建点击操作';
    const id = nextId++;
    const app = bundleManager.getBundleInfoForSelfSync(0);
    const agent = await wantAgent.getWantAgent({
      wants: [{ bundleName: app.name, abilityName: 'EntryAbility', action: NOTIFICATION_ACTION,
        parameters: { localId: target.localId, environmentId: target.environmentId, threadId: target.threadId } }],
      operationType: wantAgent.OperationType.START_ABILITY, requestCode: id,
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    });
    if (!enabled || version !== generation || !validTarget(target)) { notificationStatus('设置或目标已变化，取消发布'); return; }
    stage = '提交系统通知';
    await notificationManager.publish({ id, notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
      content: { notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: { title: '简码', text: run.status === 'completed' ? '一个任务已完成，点击查看会话。' : '一个任务已结束，请打开会话查看状态。' } },
      wantAgent: agent, tapDismissed: true, autoDeletedTime: Date.now() + 24 * 60 * 60 * 1000 });
    if (!enabled || version !== generation || !validTarget(target)) {
      await notificationManager.cancel(id); notificationStatus('发布后目标或设置变化，已撤销通知');
    } else {
      notificationStatus('系统已接受通知；是否展示由系统通知设置决定');
      AppStorage.setOrCreate('t3LocalNotificationPublishedAt', new Date().toLocaleTimeString());
    }
    AppStorage.setOrCreate('t3LocalNotificationError', '');
  } catch (error) {
    const code = (error as BusinessError).code;
    const detail = stage + '失败' + (typeof code === 'number' ? '（代码 ' + String(code) + '）' : '');
    notificationStatus(detail);
    AppStorage.setOrCreate('t3LocalNotificationError', detail);
  }
}
export function acceptNotificationWant(want: Want): void {
  if (want.action !== NOTIFICATION_ACTION) return;
  try {
    pendingTarget = notificationTarget(want.parameters || {});
    AppStorage.setOrCreate('t3NotificationTapStatus', new Date().toLocaleTimeString() + ' · 已收到有效通知点击，等待会话定位');
    AppStorage.setOrCreate('t3NotificationTargetError', '');
  } catch (_) {
    pendingTarget = undefined;
    AppStorage.setOrCreate('t3NotificationTapStatus', new Date().toLocaleTimeString() + ' · 通知点击目标无效');
    AppStorage.setOrCreate('t3NotificationTargetError', '通知目标无效');
  }
  AppStorage.setOrCreate('t3NotificationTargetRevision', (AppStorage.get<number>('t3NotificationTargetRevision') || 0) + 1);
}
export function peekNotificationTarget(): NotificationTarget | undefined {
  return pendingTarget ? notificationTarget(pendingTarget) : undefined;
}
export function clearNotificationTarget(): void { pendingTarget = undefined; }
