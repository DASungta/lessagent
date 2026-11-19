import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { compile, data } from './load-core.mjs';

const repo = file => new URL('../entry/src/main/ets/' + file, import.meta.url);
const wire = JSON.stringify(repo('protocol/Wire.ts').href);
const protocol = JSON.stringify(data(`
  export const sourceControlField = (snapshot, key) => snapshot.fields.find(field => field.key === key);
  export const readSourceControlSettings = (connection, id) => connection.readSettings(id);
  export const writeSourceControlSetting = (connection, snapshot, key, value, current) =>
    connection.saveSettings(snapshot, key, value, current);
`));
const source = await readFile(repo('components/SourceControlSettingsPanel.ets'), 'utf8');
const { SourceControlSettingsPanel } = await import(data(compile((source.split('  @Builder')[0] + '}')
  .replace("'../protocol/Wire'", wire)
  .replace("'../protocol/SourceControlSettings'", protocol)
  .replace(/^import \{ T3Client \}.*;\n/m, '')
  .replace(/@(?:State|Prop)\s+|@(?:StorageLink|Watch)\([^)]*\)\s*/g, '')
  .replace('@Component\nexport struct', 'export class'))));

const directory = 'addProjectBaseDirectory';
const setup = () => {
  const panel = new SourceControlSettingsPanel();
  const writes = [];
  const connection = {
    ready: true, generation: 1, writable: true,
    config: { environment: { environmentId: 'environment-a' } },
    generationValue() { return this.generation; }, canScope() { return this.writable; },
    async refreshSessionAccess() {},
    async readSettings(environmentId) {
      return { environmentId, generation: this.generation, fields: [{ key: directory, value: '/work', locked: false }] };
    },
    async saveSettings(snapshot, key, value, stillSelected) {
      assert.equal(stillSelected(), true);
      writes.push([key, value]);
      return { ...snapshot, fields: [{ key, value, locked: false }] };
    },
  };
  Object.assign(panel, { connection, settingsWriteAllowed: true, alive: true });
  return { panel, connection, writes };
};

test('source control settings retain live permission and reject writes from an old connection generation', async () => {
  const { panel, connection, writes } = setup();
  await panel.refresh();
  assert.equal(panel.canEdit(directory), true);
  connection.generation++;
  await panel.save(directory, '');
  assert.deepEqual(writes, []);
  await panel.refresh();
  connection.writable = false;
  await panel.save(directory, '');
  assert.deepEqual(writes, []);
  connection.writable = true;
  panel.snapshot.fields[0].locked = true;
  await panel.save(directory, '');
  assert.deepEqual(writes, []);
  panel.snapshot.fields[0].locked = false;
  await panel.save(directory, '');
  assert.deepEqual(writes, [[directory, '']]);
  assert.equal(panel.field(directory).value, '');
});

test('backgrounding discards the previous settings snapshot and ignores a late save result', async () => {
  const { panel, connection } = setup();
  await panel.refresh();
  let finish, stillSelected;
  connection.saveSettings = (snapshot, _key, _value, current) => {
    stillSelected = current;
    return new Promise(resolve => { finish = () => resolve(snapshot); });
  };
  const pending = panel.save(directory, '');
  assert.equal(stillSelected(), true);
  panel.foreground = false;
  panel.foregroundChanged();
  assert.equal(stillSelected(), false);
  finish();
  await pending;
  assert.equal(panel.snapshot, undefined);
  assert.equal(panel.notice, '');
});

test('foreground recovery reads a new snapshot when the transport becomes ready later', async () => {
  const { panel, connection } = setup();
  await panel.refresh();
  connection.generation++;
  connection.ready = false;
  panel.connectionReady = false;
  panel.foregroundChanged();
  assert.equal(panel.snapshot, undefined);
  connection.ready = true;
  panel.connectionReady = true;
  panel.foregroundChanged();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(panel.snapshot.generation, connection.generation);
  assert.equal(panel.canEdit(directory), true);
});
