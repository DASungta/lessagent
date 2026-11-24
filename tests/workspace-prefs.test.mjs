import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { DEFAULT_TERMINAL_FONT_SIZE } from '../entry/src/main/ets/protocol/Terminal.ts';
import { composerUrl, r5Url } from './load-core.mjs';
import { createRequire } from 'node:module';
const ts = createRequire(import.meta.url)((process.env.DEVECO_HOME || '/Applications/DevEco-Studio.app/Contents') +
  '/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const published = new Map();
globalThis.AppStorage = { setOrCreate: (key, value) => published.set(key, value) };
const source = (await readFile(new URL('../entry/src/main/ets/services/WorkspacePrefs.ets', import.meta.url), 'utf8'))
  .replace("import { fileIo } from '@kit.CoreFileKit';", 'const fileIo = {};')
  .replace("import { BusinessError } from '@kit.BasicServicesKit';", '')
  .replace("'../protocol/Composer'", JSON.stringify(composerUrl))
  .replace("'../protocol/R5'", JSON.stringify(r5Url))
  .replace("'../protocol/Terminal'", JSON.stringify(new URL('../entry/src/main/ets/protocol/Terminal.ts', import.meta.url).href));
const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ES2022, target: ts.ScriptTarget.ES2022 } }).outputText;
const P = await import('data:text/javascript;base64,' + Buffer.from(compiled).toString('base64'));

test('R3 preferences validate grouping, sort, filter bounds and default omitted booleans', () => {
  assert.deepEqual(P.workspacePreferences({ schemaVersion: 1, projectGroupingMode: 'repository_path',
    environmentFilter: 'a', projectFilterKey: 'repo', threadSortOrder: 'created_at', archivedSortOrder: 'oldest',
    settledShelfExpanded: false }), {
    schemaVersion: 1, projectGroupingMode: 'repository_path', environmentFilter: 'a', projectFilterKey: 'repo',
    projectFilterGroupingMode: 'repository_path',
    threadSortOrder: 'created_at', archivedSortOrder: 'oldest', workingShelfEnabled: true,
    useLastProjectForNewThreads: true, lastThreadProject: undefined,
    workingShelfExpanded: false, snoozedShelfExpanded: false, settledShelfExpanded: false, followUpBehavior: 'steer', terminalFontSize: DEFAULT_TERMINAL_FONT_SIZE, codeFontSize: null, codeWordBreak: false, pullRequestHideTestFiles: false, sideThreadOpenTarget: 'panel', modelFavorites: [], pullRequestSavedViews: []
  });
  assert.throws(() => P.workspacePreferences({ schemaVersion: 2 }), /版本/);
  assert.throws(() => P.workspacePreferences({ schemaVersion: 1, projectGroupingMode: 'bad',
    threadSortOrder: 'updated_at', archivedSortOrder: 'newest' }), /分组/);
  assert.throws(() => P.workspacePreferences({ schemaVersion: 1, projectGroupingMode: 'repository',
    threadSortOrder: 'bad', archivedSortOrder: 'newest' }), /排序/);
});

test('saved filter keeps its original grouping mode across layout changes and restart', () => {
  const saved = { ...P.defaultWorkspacePreferences(), projectGroupingMode: 'repository_path',
    projectFilterKey: 'repo', projectFilterGroupingMode: 'repository', environmentFilter: 'environment-a' };
  assert.equal(P.workspacePreferences(JSON.parse(JSON.stringify(saved))).projectFilterGroupingMode, 'repository');
  assert.equal(P.workspacePreferences({ ...saved, projectFilterKey: '' }).projectFilterGroupingMode, undefined);
});

test('follow-up preference migrates old records and rejects unknown sending modes',()=>{
 const before=P.defaultWorkspacePreferences();assert.equal(before.followUpBehavior,'steer');
 assert.equal(P.workspacePreferences({...before,followUpBehavior:'queue'}).followUpBehavior,'queue');
 assert.throws(()=>P.workspacePreferences({...before,followUpBehavior:'invalid'}),/后续/);
});

test('follow-up save failure keeps the prior effective setting',async()=>{
 await P.prepareWorkspacePreferences('/synthetic');let saves=0;
 P.workspacePrefsStore.save=async()=>{saves++;throw Error('disk')};
 await assert.rejects(P.setFollowUpBehavior('queue'),/disk/);assert.equal(P.workspacePrefs.followUpBehavior,'steer');
 await assert.rejects(P.setFollowUpBehavior('invalid'));assert.equal(saves,1);
 P.workspacePrefsStore.save=async value=>{assert.equal(value.followUpBehavior,'queue');saves++};
 await P.setFollowUpBehavior('queue');assert.equal(P.workspacePrefs.followUpBehavior,'queue');assert.equal(saves,2);
});

test('Working preference persists independently of expansion and leaves the previous setting on write failure', async () => {
  await P.prepareWorkspacePreferences('/synthetic');
  P.workspacePrefs.workingShelfExpanded = true;
  P.workspacePrefsStore.save = async () => { throw Error('disk'); };
  await assert.rejects(P.setWorkingShelfEnabled(false), /disk/);
  assert.equal(P.workspacePrefs.workingShelfEnabled, true);
  P.workspacePrefsStore.save = async value => {
    assert.equal(value.workingShelfEnabled, false);
    assert.equal(value.workingShelfExpanded, true);
    assert.equal(P.workspacePreferences(value).workingShelfEnabled, false);
  };
  await P.setWorkingShelfEnabled(false);
  assert.equal(P.workspacePrefs.workingShelfEnabled, false);
  assert.equal(P.workspacePrefs.workingShelfExpanded, true);
});

test('recent project defaults on, preserves the exact environment identity and ignores invalid saved references', async () => {
  const initial = P.defaultWorkspacePreferences();
  assert.equal(initial.useLastProjectForNewThreads, true);
  const last = { environmentId: 'e-b', projectId: 'same' };
  const parsed = P.workspacePreferences({ ...initial, useLastProjectForNewThreads: false, lastThreadProject: last });
  assert.deepEqual(parsed.lastThreadProject, last);
  assert.equal(parsed.useLastProjectForNewThreads, false);
  for (const invalid of [null, 'same', {}, { ...last, environmentId: '' }, { ...last, projectId: ' '.repeat(257) }]) {
    assert.equal(P.workspacePreferences({ ...initial, lastThreadProject: invalid }).lastThreadProject, undefined);
  }
  await P.prepareWorkspacePreferences('/synthetic');
  P.workspacePrefsStore.save = async () => { throw Error('disk'); };
  await assert.rejects(P.setUseLastProjectForNewThreads(false), /disk/);
  assert.equal(P.workspacePrefs.useLastProjectForNewThreads, true);
  const writes = [];
  P.workspacePrefsStore.save = async value => { writes.push(P.workspacePreferences(value)); };
  P.rememberThreadProject(last);
  P.rememberThreadProject(last);
  await P.setUseLastProjectForNewThreads(false);
  assert.equal(writes.length, 2);
  assert.equal(writes[1].useLastProjectForNewThreads, false);
  assert.deepEqual(writes[1].lastThreadProject, last);
});

test('terminal font retains the existing default and persists a valid size only after a successful save', async () => {
  const initial = P.defaultWorkspacePreferences();
  assert.equal(initial.terminalFontSize, 14);
  assert.equal(P.workspacePreferences({ ...initial, terminalFontSize: 20 }).terminalFontSize, 20);
  assert.equal(P.workspacePreferences({ ...initial, terminalFontSize: 100 }).terminalFontSize, 14);
  await P.prepareWorkspacePreferences('/synthetic');
  P.workspacePrefsStore.save = async () => { throw Error('disk'); };
  await assert.rejects(P.setTerminalFontSize(18), /disk/);
  assert.equal(P.workspacePrefs.terminalFontSize, 14);
  P.workspacePrefsStore.save = async value => { assert.equal(value.terminalFontSize, 18); };
  await P.setTerminalFontSize(18);
  assert.equal(P.workspacePrefs.terminalFontSize, 18);
});

test('code appearance migrates older preferences and uses the upstream range and default-off wrap', () => {
  const base = P.defaultWorkspacePreferences();
  assert.equal(base.codeFontSize, null);
  assert.equal(base.codeWordBreak, false);
  assert.equal(P.workspacePreferences({ ...base, codeFontSize: 17.6 }).codeFontSize, 18);
  assert.equal(P.workspacePreferences({ ...base, codeFontSize: 7 }).codeFontSize, 8);
  assert.equal(P.workspacePreferences({ ...base, codeFontSize: NaN }).codeFontSize, null);
  assert.equal(P.workspacePreferences({ ...base, codeWordBreak: true }).codeWordBreak, true);
  assert.equal(P.workspacePreferences({ ...base, codeWordBreak: 'true' }).codeWordBreak, false);
});

test('code appearance publishes only successfully saved state and reset restores the Harmony default', async () => {
  await P.prepareWorkspacePreferences('/synthetic');
  const seen = [];
  P.workspacePrefsStore.save = async value => { seen.push([value.codeFontSize, value.codeWordBreak]); };
  assert.equal(published.get('t3CodeFontSize'), 13);
  assert.equal(published.get('t3CodeWordBreak'), false);
  await P.setCodeFontSize(17);
  await P.setCodeWordBreak(true);
  assert.equal(published.get('t3CodeFontSize'), 17);
  assert.equal(published.get('t3CodeWordBreak'), true);
  const save = P.workspacePrefsStore.save;
  P.workspacePrefsStore.save = async () => { throw Error('disk'); };
  await assert.rejects(P.setCodeFontSize(18), /disk/);
  await assert.rejects(P.setCodeWordBreak(false), /disk/);
  assert.equal(P.workspacePrefs.codeFontSize, 17);
  assert.equal(P.workspacePrefs.codeWordBreak, true);
  assert.equal(published.get('t3CodeFontSize'), 17);
  assert.equal(published.get('t3CodeWordBreak'), true);
  P.workspacePrefsStore.save = save;
  await assert.rejects(P.setCodeFontSize(19), /无效/);
  await P.setCodeFontSize(null);
  assert.deepEqual(seen, [[17, false], [17, true], [null, true]]);
  assert.equal(P.effectiveCodeFontSize(), 13);
  assert.equal(published.get('t3CodeFontSize'), 13);
});

test('U3: pullRequestHideTestFiles defaults false, migrates safely, persists and publishes t3HideTestFiles', async () => {
  const base = P.defaultWorkspacePreferences();
  assert.equal(base.pullRequestHideTestFiles, false);
  assert.equal(P.workspacePreferences({ ...base, pullRequestHideTestFiles: true }).pullRequestHideTestFiles, true);
  assert.equal(P.workspacePreferences({ ...base, pullRequestHideTestFiles: 'yes' }).pullRequestHideTestFiles, false);

  await P.prepareWorkspacePreferences('/synthetic');
  assert.equal(published.get('t3HideTestFiles'), false);
  const saved = [];
  P.workspacePrefsStore.save = async value => { saved.push(value.pullRequestHideTestFiles); };
  await P.setPullRequestHideTestFiles(true);
  assert.equal(P.workspacePrefs.pullRequestHideTestFiles, true);
  assert.equal(published.get('t3HideTestFiles'), true);
  assert.deepEqual(saved, [true]);

  P.workspacePrefsStore.save = async () => { throw Error('disk'); };
  await assert.rejects(P.setPullRequestHideTestFiles(false), /disk/);
  assert.equal(P.workspacePrefs.pullRequestHideTestFiles, true);
  assert.equal(published.get('t3HideTestFiles'), true);
});

test('L3: sideThreadOpenTarget defaults panel, migrates legacy records, validates and persists atomically', async () => {
  const base = P.defaultWorkspacePreferences();
  assert.equal(base.sideThreadOpenTarget, 'panel');
  const legacy = { ...base };
  delete legacy.sideThreadOpenTarget;
  assert.equal(P.workspacePreferences(legacy).sideThreadOpenTarget, 'panel');
  assert.equal(P.workspacePreferences({ ...base, sideThreadOpenTarget: 'main' }).sideThreadOpenTarget, 'main');
  assert.throws(() => P.workspacePreferences({ ...base, sideThreadOpenTarget: 'invalid' }), /打开方式无效/);

  await P.prepareWorkspacePreferences('/synthetic');
  const saved = [];
  P.workspacePrefsStore.save = async value => { saved.push(value.sideThreadOpenTarget); };
  await P.setSideThreadOpenTarget('main');
  assert.equal(P.workspacePrefs.sideThreadOpenTarget, 'main');
  assert.deepEqual(saved, ['main']);
  await assert.rejects(P.setSideThreadOpenTarget('bogus'), /无效/);

  P.workspacePrefsStore.save = async () => { throw Error('disk'); };
  await assert.rejects(P.setSideThreadOpenTarget('panel'), /disk/);
  assert.equal(P.workspacePrefs.sideThreadOpenTarget, 'main');
});
