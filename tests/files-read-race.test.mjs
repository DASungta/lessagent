import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { compile, data, filesUrl } from './load-core.mjs';

const source = await readFile(new URL('../entry/src/main/ets/components/FilesPanel.ets', import.meta.url), 'utf8');
const reads = source.slice(source.indexOf('  private generation:'), source.indexOf('  private async openFile('));
const { FilesHarness } = await import(data(compile(`
  import { directEntries } from ${JSON.stringify(filesUrl)};
  export class FilesHarness {
    cacheScope = 'local-a'; cwd = '/work/a'; threadId = 'thread';
    currentDir = ''; entries = []; loading = false; error = ''; query = '';
    searchMode = 'entries'; searchEntries = []; matches = []; selectedPath = '';
    closeFile() { this.invalidateReads(); this.selectedPath = ''; }
    ${reads}
  }
`)));
const wait = () => new Promise(setImmediate);
const entry = path => ({ path, name: path.split('/').at(-1), kind: 'file', ignored: false, depth: 0 });
const match = path => ({ path, lineNumber: 1, line: path });
function fixture() {
  const panel = new FilesHarness();
  panel.alive = true;
  let generation = 1;
  const calls = [];
  const pending = [];
  const defer = (type, cwd, value) => {
    calls.push([type, cwd, value]);
    return new Promise((resolve, reject) => pending.push({ resolve, reject }));
  };
  panel.connection = {
    generationValue: () => generation,
    listWorkspaceEntries: (cwd, path) => defer('directory', cwd, path),
    searchFiles: (cwd, value) => defer('entries', cwd, value),
    searchWorkspaceContents: (cwd, value) => defer('contents', cwd, value)
  };
  return { panel, calls, pending, reconnect: () => { generation++; } };
}

test('typing A→B→A ignores the first A and its error while the latest search is pending', async () => {
  const { panel, pending } = fixture();
  panel.setQuery('a');
  const first = panel.runSearch();
  panel.setQuery('b');
  const second = panel.runSearch();
  panel.setQuery('a');
  const latest = panel.runSearch();
  pending[0].resolve(['stale-a']); await first;
  pending[1].reject(Error('stale error')); await second;
  assert.deepEqual(panel.searchEntries, []);
  assert.equal(panel.error, '');
  assert.equal(panel.loading, true);
  pending[2].resolve(['latest-a']); await latest;
  assert.deepEqual(panel.searchEntries.map(row => row.path), ['latest-a']);
  assert.equal(panel.loading, false);
});

test('directory and different search mode responses cannot cover the active search', async () => {
  const { panel, calls, pending } = fixture();
  const directory = panel.loadDirectory('obsolete');
  panel.setQuery('needle');
  const entries = panel.runSearch();
  panel.setSearchMode('contents');
  panel.setSearchMode('contents');
  panel.setSearchMode('unsupported');
  assert.deepEqual(calls, [['directory', '/work/a', 'obsolete'], ['entries', '/work/a', 'needle'], ['contents', '/work/a', 'needle']]);
  pending[0].resolve([entry('obsolete/file')]); await directory;
  pending[1].resolve(['stale']); await entries;
  assert.equal(panel.currentDir, '');
  assert.deepEqual(panel.entries, []);
  assert.deepEqual(panel.searchEntries, []);
  assert.equal(panel.loading, true);
  pending[2].resolve([match('found')]); await wait();
  assert.deepEqual(panel.matches.map(row => row.path), ['found']);
  assert.equal(panel.loading, false);
});

test('clearing after a superseded directory loads the current directory again', async () => {
  const { panel, calls, pending } = fixture();
  const initial = panel.loadDirectory('');
  panel.setQuery('draft');
  const search = panel.runSearch();
  panel.setQuery('');
  assert.deepEqual(calls, [['directory', '/work/a', ''], ['entries', '/work/a', 'draft'], ['directory', '/work/a', '']]);
  pending[0].resolve([entry('obsolete')]); await initial;
  pending[1].resolve(['stale search']); await search;
  assert.deepEqual(panel.entries, []);
  assert.equal(panel.loading, true);
  pending[2].resolve([entry('current')]); await wait();
  assert.deepEqual(panel.entries.map(row => row.path), ['current']);
  assert.deepEqual(panel.searchEntries, []);
});

test('workspace changes and reconnects keep results scoped and stale reads do not hold loading', async () => {
  const { panel, pending, calls, reconnect } = fixture();
  panel.setQuery('test');
  const a = panel.runSearch();
  panel.cwd = '/work/b'; panel.cacheScope = 'local-b';
  panel.workspaceChanged();
  pending[0].resolve(['a-only']); await a;
  assert.deepEqual(panel.searchEntries, []);
  assert.equal(panel.loading, true);
  assert.deepEqual(calls[1], ['directory', '/work/b', '']);
  pending[1].resolve([entry('b-only')]); await wait();
  panel.setQuery('test');
  const stale = panel.runSearch();
  reconnect();
  pending[2].resolve(['before-reconnect']); await stale;
  assert.deepEqual(panel.searchEntries, []);
  assert.equal(panel.loading, false);
  const leaving = panel.runSearch();
  panel.aboutToDisappear();
  pending[3].reject(Error('left')); await leaving;
  assert.equal(panel.error, '');
  assert.equal(panel.loading, false);
});
