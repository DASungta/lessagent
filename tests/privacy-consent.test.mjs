import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';

const ts = createRequire(import.meta.url)(
  (process.env.DEVECO_HOME || '/Applications/DevEco-Studio.app/Contents') +
  '/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'
);

const nextFdMap = new Map();
let fdSeq = 10;

const mockFileIo = {
  OpenMode: {
    CREATE: 0o100,
    READ_WRITE: 0o2,
    TRUNC: 0o1000
  },
  readTextSync(filePath) {
    try {
      return fs.readFileSync(filePath, 'utf8');
    } catch (err) {
      if (err && err.code === 'ENOENT') {
        const e = new Error('ENOENT');
        e.code = 13900002;
        throw e;
      }
      throw err;
    }
  },
  openSync(filePath) {
    const fd = fdSeq++;
    const realFd = fs.openSync(filePath, 'w+');
    nextFdMap.set(fd, realFd);
    return { fd };
  },
  writeSync(fd, content) {
    return fs.writeSync(nextFdMap.get(fd), content);
  },
  fsyncSync(fd) {
    fs.fsyncSync(nextFdMap.get(fd));
  },
  closeSync(file) {
    const realFd = nextFdMap.get(file.fd);
    if (realFd !== undefined) {
      nextFdMap.delete(file.fd);
      fs.closeSync(realFd);
    }
  },
  renameSync(from, to) {
    fs.renameSync(from, to);
  }
};

globalThis.__mockPrivacyFileIo = mockFileIo;

const source = (await readFile(new URL('../entry/src/main/ets/services/PrivacyConsent.ets', import.meta.url), 'utf8'))
  .replace("import { fileIo } from '@kit.CoreFileKit';", 'const fileIo = globalThis.__mockPrivacyFileIo;')
  .replace("import { BusinessError } from '@kit.BasicServicesKit';", '');
const compiled = ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.ES2022, target: ts.ScriptTarget.ES2022 }
}).outputText;
const Privacy = await import('data:text/javascript;base64,' + Buffer.from(compiled).toString('base64'));

test('privacy consent defaults to false, persists atomically on accept, and rejects stale or corrupt files', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 't3-privacy-'));
  try {
    assert.equal(Privacy.preparePrivacyConsent(dir), false);
    assert.equal(Privacy.isPrivacyConsentAccepted(), false);

    Privacy.acceptPrivacyConsent();
    assert.equal(Privacy.isPrivacyConsentAccepted(), true);

    const savedPath = path.join(dir, 'privacy-consent-v1.json');
    const saved = JSON.parse(fs.readFileSync(savedPath, 'utf8'));
    assert.equal(saved.schemaVersion, 1);
    assert.equal(saved.acceptedVersion, Privacy.PRIVACY_CONSENT_VERSION);
    assert.ok(typeof saved.acceptedAt === 'string' && saved.acceptedAt.length > 0);

    // Reloading in a fresh session preserves acceptance
    assert.equal(Privacy.preparePrivacyConsent(dir), true);
    assert.equal(Privacy.isPrivacyConsentAccepted(), true);

    // Older version forces re-consent
    fs.writeFileSync(savedPath, JSON.stringify({ schemaVersion: 1, acceptedVersion: 0, acceptedAt: '2025-01-01T00:00:00Z' }));
    assert.equal(Privacy.preparePrivacyConsent(dir), false);
    assert.equal(Privacy.isPrivacyConsentAccepted(), false);

    // Corrupt JSON fails closed
    fs.writeFileSync(savedPath, '{not-json');
    assert.equal(Privacy.preparePrivacyConsent(dir), false);
    assert.equal(Privacy.isPrivacyConsentAccepted(), false);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
