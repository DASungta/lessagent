import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { compile, data } from './load-core.mjs';
const protocolUrl = data(compile(await readFile(new URL('../entry/src/main/ets/protocol/LocalNotifications.ts', import.meta.url), 'utf8')));
const api = await import(protocolUrl);
const target = {localId:'local-a',environmentId:'env-a',threadId:'thread-a'};
test('notification route validates all three identities and never accepts URL/path payloads', () => {
  assert.deepEqual(api.notificationTarget(target),target);
  for(const value of [{}, {...target,threadId:'../x'}, {...target,localId:''}, {...target,environmentId:123}, {...target,threadId:'x'.repeat(257)}]) assert.throws(()=>api.notificationTarget(value));
  assert.equal(api.sameNotificationTarget(target,{...target,localId:'local-b'}),false);
});
test('run notifications require an observed active-to-terminal transition, never snapshot history', () => {
  const tracker = new api.RunNotificationTracker();
  tracker.snapshot(target,[{id:'old',status:'completed'},{id:'active',status:'running'}]);
  assert.equal(tracker.update(target,{id:'old',status:'completed'}),false);
  assert.equal(tracker.update(target,{id:'unknown',status:'completed'}),false);
  assert.equal(tracker.update(target,{id:'active',status:'completed'}),true);
  assert.equal(tracker.update(target,{id:'active',status:'completed'}),false);
  assert.equal(tracker.update({...target,localId:'local-b'},{id:'active',status:'completed'}),false);
  tracker.snapshot(target,[{id:'r',status:'running'}]);
  assert.equal(tracker.update(target,{id:'r',status:'cancelled'}),false);
  tracker.snapshot(target,[{id:'reconnect',status:'running'}]);
  tracker.snapshot(target,[]);
  assert.equal(tracker.update(target,{id:'reconnect',status:'completed'}),false);
  tracker.clear(); assert.equal(tracker.update(target,{id:'active',status:'failed'}),false);
});
test('opt-in, generation baseline, visible thread suppression and tap parsing use only safe data', async () => {
  const values = new Map(); const publications=[]; let enabledBySystem = true; let requested=0; let persisted=false;
  globalThis.AppStorage={get:k=>values.get(k),setOrCreate:(k,v)=>values.set(k,v)};
  globalThis.__notify={
    manager:{requestEnableNotification:async()=>{requested++;}, isNotificationEnabled:async()=>enabledBySystem,
      publish:async v=>publications.push(v),cancelAll:async()=>{},cancel:async()=>{}, SlotType:{SERVICE_INFORMATION:2},ContentType:{NOTIFICATION_CONTENT_BASIC_TEXT:0}},
    agent:{OperationType:{START_ABILITY:1},WantAgentFlags:{UPDATE_PRESENT_FLAG:1},getWantAgent:async v=>v},
    bundle:{getBundleInfoForSelfSync:()=>({name:'test.bundle'})},
    prefs:{getPreferences:async()=>({get:async()=>persisted,put:async(_k,v)=>persisted=v,flush:async()=>{}})}
  };
  let source = await readFile(new URL('../entry/src/main/ets/services/LocalNotifications.ets', import.meta.url),'utf8');
  source=source.replace("import { common, Want, wantAgent, bundleManager } from '@kit.AbilityKit';",'const wantAgent=globalThis.__notify.agent; const bundleManager=globalThis.__notify.bundle;')
    .replace("import { BusinessError } from '@kit.BasicServicesKit';", '')
    .replace("import { notificationManager } from '@kit.NotificationKit';",'const notificationManager=globalThis.__notify.manager;')
    .replace("import { preferences } from '@kit.ArkData';",'const preferences=globalThis.__notify.prefs;')
    .replace("'../protocol/LocalNotifications'",JSON.stringify(protocolUrl));
  const service=await import(data(compile(source)));
  await service.prepareLocalNotifications({}); assert.equal(requested,0); assert.equal(service.localNotificationsEnabled(),false);
  service.configureNotificationTargets(t=>t.localId===target.localId && t.environmentId===target.environmentId);
  const identity={};
  await service.observeThreadNotifications(target,1,identity,[{id:'r',status:'running'}]);
  await service.observeThreadNotifications(target,1,identity,[{id:'r',status:'completed'}]);assert.equal(publications.length,0);
  await service.setLocalNotificationsEnabled(true);assert.equal(requested,1);
  await service.observeThreadNotifications(target,2,identity,[{id:'r',status:'running'}]);
  await service.observeThreadNotifications(target,3,identity,[{id:'r',status:'completed'}]);assert.equal(publications.length,0);
  await service.observeThreadNotifications(target,3,identity,[{id:'r2',status:'running'}]);
  service.setVisibleNotificationThread(target);
  await service.observeThreadNotifications(target,3,identity,[{id:'r2',status:'completed'}]); assert.equal(publications.length,0);
  service.setVisibleNotificationThread(undefined);
  await service.observeThreadNotifications(target,3,identity,[{id:'r3',status:'running'}]);
  await service.observeThreadNotifications(target,3,identity,[{id:'r3',status:'failed'}]);assert.equal(publications.length,1);
  assert.match(values.get('t3LocalNotificationStatus'),/系统已接受/);
  assert.ok(values.get('t3LocalNotificationPublishedAt'));
  assert.equal(api.NOTIFICATION_ACTION, 'com.dasungta.lessagent.OPEN_THREAD_NOTIFICATION');
  assert.deepEqual(publications[0].wantAgent.wants[0].parameters,target);
  assert.equal(publications[0].content.normal.title,'简码');
  assert.equal(publications[0].content.normal.text,'一个任务已结束，请打开会话查看状态。');
  await service.observeThreadNotifications(target,3,identity,[{id:'r3',status:'failed'}]);assert.equal(publications.length,1);
  service.acceptNotificationWant({action:api.NOTIFICATION_ACTION,parameters:target});assert.deepEqual(service.peekNotificationTarget(),target);
  assert.match(values.get('t3NotificationTapStatus'),/已收到有效通知点击/);
  service.clearNotificationTarget(); assert.equal(service.peekNotificationTarget(),undefined);
  service.acceptNotificationWant({action:api.NOTIFICATION_ACTION,parameters:{...target,threadId:'file:///secret'}});assert.equal(service.peekNotificationTarget(),undefined);
  assert.ok(!values.get('t3NotificationTargetError').includes('secret'));
  enabledBySystem=false;
  await assert.rejects(service.setLocalNotificationsEnabled(true));
  await service.setLocalNotificationsEnabled(false);assert.equal(service.localNotificationsEnabled(),false);
  delete globalThis.__notify;delete globalThis.AppStorage;
});
