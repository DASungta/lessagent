import test from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';
import { coreUrl } from './load-core.mjs';

const ts = createRequire(import.meta.url)((process.env.DEVECO_HOME || '/Applications/DevEco-Studio.app/Contents') + '/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const { cachedShellEntry } = await import(coreUrl);
const { record } = await import('../entry/src/main/ets/protocol/Wire.ts');
const source = fs.readFileSync(new URL('../entry/src/main/ets/storage/ShellCacheStore.ets', import.meta.url), 'utf8');
const body = source.slice(source.indexOf('const SHELL_CACHE_VERSION'));
const compiled = ts.transpileModule(
  body.replace('export class ShellCacheStore implements ShellCacheStorage', 'class ShellCacheStore') + '\nreturn ShellCacheStore;',
  { compilerOptions: { target: ts.ScriptTarget.ES2022 } }
).outputText;

test('ShellCacheStore persists atomically, drops expired or malformed records, and recovers from corrupt JSON', async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 't3-shell-cache-'));
  const kit = {
    OpenMode: { CREATE: 1, READ_WRITE: 2, TRUNC: 4 },
    readTextSync: (p) => {
      try { return fs.readFileSync(p, 'utf8'); }
      catch (e) { if (e.code === 'ENOENT') throw { code: 13900002 }; throw e; }
    },
    openSync: (p) => ({ fd: fs.openSync(p, 'w', 0o600) }),
    writeSync: (fd, v) => fs.writeSync(fd, v),
    fsyncSync: (fd) => fs.fsyncSync(fd),
    closeSync: (f) => fs.closeSync(f.fd),
    renameSync: (a, b) => fs.renameSync(a, b),
    unlinkSync: (p) => fs.unlinkSync(p)
  };
  const Store = new Function('fileIo', 'cachedShellEntry', 'record', compiled)(kit, cachedShellEntry, record);
  try {
    const store = new Store(root);
    assert.deepEqual(await store.loadAll(), {});

    const now = Date.now();
    await store.saveAll({
      'env-local-1': {
        environmentId: 'env-1',
        savedAt: now,
        scratchWorkspaceRoot: '/scratch',
        capabilities: { threadSettlement: true, threadPinning: true },
        projects: [{ id: 'p1', label: 'Project One', projectId: 'p1', workspaceRoot: '/p1' }],
        threads: [
          {
            id: 't1', label: 'Active Thread', projectId: 'p1', status: 'completed',
            interactionMode: 'plan', creationSource: 'web', blockedOnThreadWait: true,
            activityRunStartedAt: '2026-01-01T00:00:00.000Z', pendingUserOnly: true,
            delegatedFromEnvironmentId: 'env-parent', delegatedFromThreadId: 'parent-1',
            lineageWorkflowStep: true,
            pendingBackgroundTasks: [{ taskId: 'bg-1', kind: 'subagent', childThreadId: 'c1' }]
          },
          { id: 't-deleted', label: 'Removed', projectId: 'p1', deletedAt: '2026-01-01T00:00:00Z' }
        ]
      }
    });

    const loaded = await store.loadAll();
    assert.equal(Object.keys(loaded).length, 1);
    assert.equal(loaded['env-local-1'].environmentId, 'env-1');
    assert.equal(loaded['env-local-1'].threads.length, 1);
    assert.equal(loaded['env-local-1'].threads[0].id, 't1');
    assert.equal(loaded['env-local-1'].threads[0].interactionMode, 'plan');
    assert.equal(loaded['env-local-1'].threads[0].creationSource, 'web');
    assert.equal(loaded['env-local-1'].threads[0].blockedOnThreadWait, true);
    assert.equal(loaded['env-local-1'].threads[0].activityRunStartedAt, '2026-01-01T00:00:00.000Z');
    assert.equal(loaded['env-local-1'].threads[0].pendingUserOnly, true);
    assert.equal(loaded['env-local-1'].threads[0].delegatedFromEnvironmentId, 'env-parent');
    assert.equal(loaded['env-local-1'].threads[0].lineageWorkflowStep, true);
    assert.deepEqual(loaded['env-local-1'].threads[0].pendingBackgroundTasks, [{ taskId: 'bg-1', kind: 'subagent', childThreadId: 'c1' }]);
    assert.equal(loaded['env-local-1'].capabilities.threadSettlement, true);

    // Expired entry is filtered while fresh sibling survives
    const raw = JSON.parse(fs.readFileSync(path.join(root, 'shell-cache-v1.json'), 'utf8'));
    raw.entries['env-old'] = {
      environmentId: 'env-old',
      savedAt: now - 10 * 24 * 60 * 60 * 1000,
      scratchWorkspaceRoot: '',
      capabilities: {},
      projects: [],
      threads: []
    };
    raw.entries['env-bad'] = { broken: true };
    fs.writeFileSync(path.join(root, 'shell-cache-v1.json'), JSON.stringify(raw));

    const filtered = await store.loadAll();
    assert.deepEqual(Object.keys(filtered), ['env-local-1']);

    // Corrupt file is quietly unlinked and returns empty object without breaking startup
    fs.writeFileSync(path.join(root, 'shell-cache-v1.json'), '{not-valid-json');
    assert.deepEqual(await store.loadAll(), {});
    assert.equal(fs.existsSync(path.join(root, 'shell-cache-v1.json')), false);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});
