import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { readFile } from 'node:fs/promises';
import { compile, data } from './load-core.mjs';

const wireUrl = data(compile(await readFile(new URL('../entry/src/main/ets/protocol/Wire.ts', import.meta.url), 'utf8')));
const wire = await import(wireUrl);

test('optionalRecord and configEnvironmentId safely handle unconnected or malformed configs', () => {
  assert.equal(wire.optionalRecord(undefined), undefined);
  assert.equal(wire.optionalRecord(null), undefined);
  assert.equal(wire.optionalRecord([]), undefined);
  assert.equal(wire.optionalRecord('text'), undefined);
  assert.deepEqual(wire.optionalRecord({ environmentId: 'env-1' }), { environmentId: 'env-1' });

  assert.equal(wire.configEnvironmentId(undefined), '');
  assert.equal(wire.configEnvironmentId({}), '');
  assert.equal(wire.configEnvironmentId({ environment: undefined }), '');
  assert.equal(wire.configEnvironmentId({ environment: null }), '');
  assert.equal(wire.configEnvironmentId({ environment: [] }), '');
  assert.equal(wire.configEnvironmentId({ environment: { environmentId: 123 } }), '');
  assert.equal(wire.configEnvironmentId({ environment: { environmentId: 'env-1' } }), 'env-1');
});

test('UI components and pages do not call unguarded record(...config.environment)', () => {
  const roots = [
    path.resolve('entry/src/main/ets/components'),
    path.resolve('entry/src/main/ets/pages')
  ];
  const violations = [];
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.name.endsWith('.ets')) {
        const text = fs.readFileSync(full, 'utf8');
        if (/record\([^)]*config\.environment\b/.test(text)) {
          violations.push(path.relative(process.cwd(), full));
        }
      }
    }
  };
  roots.forEach(walk);
  assert.deepEqual(violations, []);
});
