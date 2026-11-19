import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { compile, data } from './load-core.mjs';

const repoFile = path => new URL('../entry/src/main/ets/' + path, import.meta.url);
const wireUrl = JSON.stringify(repoFile('protocol/Wire.ts').href);
const defaults = (await readFile(repoFile('protocol/WorktreeSettings.ts'), 'utf8')).replace("'./Wire'", wireUrl);
const protocol = (await readFile(repoFile('protocol/ProjectWorktreeSettings.ts'), 'utf8'))
  .replace("'./Wire'", wireUrl).replace("'./WorktreeSettings'", JSON.stringify(data(compile(defaults))));
const panelSource = await readFile(repoFile('components/ProjectWorktreeSettingsPanel.ets'), 'utf8');
const panelCode = panelSource.split('  @Builder')[0] + '}';
const { ProjectWorktreeSettingsPanel } = await import(data(compile(panelCode
  .replace("'../protocol/ProjectWorktreeSettings'", JSON.stringify(data(compile(protocol))))
  .replace(/^import (?:\{ EnvironmentEntry \}|\{ ScopedProject \}|\{ T3Client \}).*;\n/gm, '')
  .replace(/@(?:Prop|State)\s+|@(?:StorageLink|Watch)\([^)]*\)\s*/g, '')
  .replace('@Component\nexport struct', 'export class'))));

const config = (id, supported = true) => ({
  environment: { environmentId: id, capabilities: { projectSettingsOverrides: supported } },
  settings: { newWorktreesStartFromOrigin: true, branchNamePrefix: 'prefix',
    projectSettingsOverrides: { same: { branchNamePrefix: '' } } },
});
const setup = () => {
  const panel = new ProjectWorktreeSettingsPanel();
  panel.environments = ['a', 'b'].map(localId => ({ localId, enabled: true }));
  panel.projects = ['a', 'b'].map(localId => ({ localId, environmentId: 'env-' + localId, id: 'same' }));
  const clients = {};
  for (const id of ['a', 'b']) {
    clients[id] = { ready: true, generation: 1, write: true,
      generationValue() { return this.generation; }, canScope() { return this.write; },
      async refreshSessionAccess() {}, async rpcRequest() { return config('env-' + id); } };
  }
  panel.connectionFor = id => clients[id];
  return { panel, clients };
};
const finish = () => new Promise(resolve => setImmediate(resolve));

test('project settings discard a read for the same project id from a previously selected environment', async () => {
  const { panel, clients } = setup();
  let complete;
  clients.a.rpcRequest = () => new Promise(resolve => { complete = resolve; });
  panel.selectEnvironment(0); panel.selectProject(0);
  await finish();
  panel.selectEnvironment(1); panel.selectProject(0);
  await finish();
  assert.equal(panel.snapshot.environmentId, 'env-b');
  assert.equal(panel.field('branchNamePrefix').source, 'project');
  assert.equal(panel.field('branchNamePrefix').value, '');
  complete(config('env-a'));
  await finish();
  assert.equal(panel.snapshot.environmentId, 'env-b');
  panel.foreground = false; panel.foregroundChanged();
  assert.equal(panel.snapshot, undefined);
  assert.equal(panel.canEdit('branchNamePrefix'), false);
});

test('project write controls require a matching connection generation, supported service and live permission', async () => {
  const { panel, clients } = setup();
  panel.selectEnvironment(0); panel.selectProject(0);
  await finish();
  assert.equal(panel.canEdit('branchNamePrefix'), true);
  clients.a.generation++;
  assert.equal(panel.canEdit('branchNamePrefix'), false);
  clients.a.write = false;
  assert.equal(panel.canEdit('branchNamePrefix'), false);
  clients.a.canScope = scope => scope !== 'settings:write';
  await panel.refresh();
  assert.equal(panel.canEdit('branchNamePrefix'), false);
  clients.a.canScope = () => true;
  clients.a.rpcRequest = async () => ({
    ...config('env-a'), managedPolicy: { lockedSettings: ['projectSettingsOverrides.same.branchNamePrefix'] },
  });
  await panel.refresh();
  assert.equal(panel.field('branchNamePrefix').locked, true);
  assert.equal(panel.canEdit('branchNamePrefix'), false);
  assert.equal(panel.canRestoreAll(), false);
  clients.a.rpcRequest = async () => config('env-a', false);
  await panel.refresh();
  assert.equal(panel.snapshot.supported, false);
  assert.equal(panel.canEdit('branchNamePrefix'), false);
});
