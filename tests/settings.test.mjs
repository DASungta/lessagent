import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { compile, data } from './load-core.mjs';
const settingsUrl = data(compile(await readFile(new URL('../entry/src/main/ets/protocol/Settings.ts', import.meta.url), 'utf8')));
const settings = await import(settingsUrl);

test('settings search handles blank, case and multiple terms', () => {
  assert.equal(settings.settingsMatch('', '环境'), true);
  assert.equal(settings.settingsMatch('t3 connect', '环境 T3 Connect'), true);
  assert.equal(settings.settingsMatch('关于 许可', '关于 开源许可'), true);
  assert.equal(settings.settingsMatch('秘密', '诊断'), false);
});
test('diagnostic export accepts only bounded version and non-negative counts', () => {
  assert.match(settings.diagnosticSummary('0.1.1', 2, 4, 1), /环境数: 2/);
  assert.throws(() => settings.diagnosticSummary('0.1\ntoken=secret', 0, 0, 0));
  assert.throws(() => settings.diagnosticSummary('0.1', -1, 0, 0));
  assert.throws(() => settings.diagnosticSummary('0.1', 1.5, 0, 0));
  assert.deepEqual(['system','light','dark'].map(settings.appearanceMode), [-1,1,0]);
  assert.throws(() => settings.appearanceMode('unexpected'));
});
test('appearance persists, restores and retains prior mode after a failed flush', async () => {
  let stored = 'system';
  let applied = -1;
  let fail = false;
  const store = { get: async () => stored, put: async (_key, value) => { stored = value; }, flush: async () => { if (fail) { fail = false; throw Error('disk'); } } };
  globalThis.__r7prefs = { getPreferences: async () => store };
  const source = (await readFile(new URL('../entry/src/main/ets/services/Appearance.ets', import.meta.url), 'utf8'))
    .replace("import { common, ConfigurationConstant } from '@kit.AbilityKit';", '')
    .replace("import { preferences } from '@kit.ArkData';", 'const preferences = globalThis.__r7prefs;')
    .replace("'../protocol/Settings'", JSON.stringify(settingsUrl));
  const service = await import(data(compile(source)));
  const context = { getApplicationContext: () => ({ setColorMode: value => { applied = value; } }) };
  await service.prepareAppearance(context);
  await service.saveAppearance(context, 'dark');
  assert.equal(stored, 'dark'); assert.equal(applied, 0);
  await service.prepareAppearance(context);
  assert.equal(service.currentAppearance, 'dark');
  fail = true;
  await assert.rejects(service.saveAppearance(context, 'light'));
  assert.equal(stored, 'dark'); assert.equal(service.currentAppearance, 'dark'); assert.equal(applied, 0);
  await assert.rejects(service.saveAppearance(context, 'invalid'));
  delete globalThis.__r7prefs;
});

test('follow-up preference only changes automatic delivery while running',()=>{
 assert.equal(settings.followUpDelivery('auto',false,'queue'),'auto');
 assert.equal(settings.followUpDelivery('auto',true,'queue'),'queue');
 assert.equal(settings.followUpDelivery('auto',true,'steer'),'steer');
 assert.equal(settings.followUpDelivery('queue',true,'steer'),'queue');
 assert.equal(settings.followUpDelivery('steer',false,'queue'),'steer');
 assert.throws(()=>settings.followUpDelivery('auto',true,'invalid'));
});

test('Working settings switch reads the reactive prop and binds its mutation directly', async () => {
  const panel = await readFile(new URL('../entry/src/main/ets/components/SettingsPanel.ets', import.meta.url), 'utf8');
  const branch = panel.split("if (settingsMatch(this.query, '工作中 Working 会话 分组 排序')) {")[1]
    .split("if (settingsMatch(this.query, '工作树存储")[0];
  assert.match(branch, /FormRow\(\{[\s\S]*label:\s*'工作中分组'[\s\S]*kind:\s*'switch'[\s\S]*checked:\s*this\.workingShelfEnabled[\s\S]*disabled:\s*this\.savingWorkingShelf[\s\S]*onToggle:\s*\(\) => \{ void this\.changeWorkingShelf\(\); \}/);
  assert.match(panel, /await this.onWorkingShelf\(!this.workingShelfEnabled\)/);
});

test('settings navigation buttons read their current count props directly', async () => {
  const panel = await readFile(new URL('../entry/src/main/ets/components/SettingsPanel.ets', import.meta.url), 'utf8');
  const navigation = panel.split("Text('连接与项目')")[1].split("Text('项目分组')")[0];
  for (const [label, count, action] of [
    ['环境', 'environmentCount', 'onEnvironments'],
    ['项目', 'projectCount', 'onProjects'],
    ['归档会话', 'archivedCount', 'onArchive'],
  ]) {
    const button = navigation.split(`Text('${label}')`)[1].split('Button(')[0];
    assert.ok(button.includes(`Text(String(this.${count}))`));
    assert.ok(button.includes(`.onClick(() => this.${action}())`));
  }
});

test('recent-project settings are reactive and share destination selection keeps its explicit picker', async () => {
  const panel = await readFile(new URL('../entry/src/main/ets/components/SettingsPanel.ets', import.meta.url), 'utf8');
  assert.match(panel, /FormRow\(\{[\s\S]*label:\s*'使用最近项目'[\s\S]*kind:\s*'switch'[\s\S]*checked:\s*this\.useLastProject[\s\S]*onToggle:\s*\(\) => \{ void this\.changeUseLastProject\(\); \}/);
  const index = await readFile(new URL('../entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
  assert.match(index, /onChooseDestination: \(\) => \{[\s\S]*?this.openProjectPicker\(true\);/);
  const picker = index.slice(index.indexOf('  private openProjectPicker('), index.indexOf('  private pickerGroups('));
  const Page = new Function(compile('return class { ' + picker + ' }'))();
  const page = new Page();
  Object.assign(page, { keyboard: { reset() {} }, ready: false, environmentEntries: [], openPanel(name) { this.panel = name; } });
  page.openProjectPicker(true);
  assert.equal(page.page, 'choose-project');
  assert.equal(page.choosingShare, true);
  assert.equal(page.panel, undefined);
  page.openProjectPicker(false);
  assert.equal(page.panel, 'server');
  assert.match(index, /onNewTask: \(\) => \{ void this.startNewTask\(\); \}/);
  const shortcut = index.split('private async startNewTask()')[1].split('private rememberProject')[0];
  assert.match(shortcut, /if \(this.draftMode\) await this.persistDraft\(\);[\s\S]*this.pendingDraftId = '';[\s\S]*await this.beginDraft\(project.id\);/);
  assert.doesNotMatch(shortcut, /\b(?:send|launch)\(/);
});

test('diagnostic sharing sends only the displayed allowlist summary and handles failure without exposing details',async()=>{
 const source=await readFile(new URL('../entry/src/main/ets/components/SettingsPanel.ets',import.meta.url),'utf8');
 const method=source.slice(source.indexOf('  private async shareDiagnostics('),source.indexOf('  @Prop groupingMode:'));
 let release,calls=0,shared;
 const kit={SharedData:class{constructor(value){shared=value}},ShareController:class{async show(){calls++;await new Promise(r=>release=r)}}};
 const Page=new Function('systemShare',compile('return class { '+method+' }'))(kit);
 const summary=settings.diagnosticSummary('0.1.1',2,4,0);
 const p=Object.assign(new Page(),{summary:()=>summary,getUIContext:()=>({getHostContext:()=>({})})});
 const pending=p.shareDiagnostics();await p.shareDiagnostics();assert.equal(calls,1);assert.deepEqual(shared,{utd:'general.plain-text',content:summary});
 release();await pending;assert.equal(p.sharingDiagnostics,false);assert.match(p.notice,/打开/);
 p.summary=()=>{throw Error('credential=do-not-display')};await p.shareDiagnostics();assert.equal(calls,1);assert.match(p.notice,/复制/);assert.equal(p.notice.includes('credential'),false);
});

test('code appearance search keeps the compact decrease, increase, reset and wrap controls reachable', async () => {
  const source = await readFile(new URL('../entry/src/main/ets/components/SettingsPanel.ets', import.meta.url), 'utf8');
  const keywords = /const CODE_APPEARANCE_SEARCH = '([^']+)'/.exec(source)[1];
  for (const query of ['代码 字号', '差异', '自动换行', 'code font', 'word break']) {
    assert.equal(settings.settingsMatch(query, keywords), true);
  }
  assert.ok(source.includes('!settingsMatch(this.query, CODE_APPEARANCE_SEARCH)'));
  const block = source.split('if (settingsMatch(this.query, CODE_APPEARANCE_SEARCH))')[1]
    .split("if (settingsMatch(this.query, '帮助")[0];
  for (const label of ['减小代码字号', '放大代码字号', '恢复默认', '代码自动换行']) assert.ok(block.includes(label));
  assert.ok(block.includes('this.codeFontNotice'));
});
