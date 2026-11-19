import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
const ts = createRequire(import.meta.url)((process.env.DEVECO_HOME || '/Applications/DevEco-Studio.app/Contents') + '/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = (await readFile(new URL('../entry/src/main/ets/protocol/Pairing.ets', import.meta.url), 'utf8'))
 .replace("import { url } from '@kit.ArkTS';", 'const url = { URL: class extends URL { get params() { return this.searchParams; } }, URLParams: URLSearchParams };')
 .replace("'./Wire'", JSON.stringify(new URL('../entry/src/main/ets/protocol/Wire.ts', import.meta.url).href));
const { pairingTarget } = await import('data:text/javascript;base64,' + Buffer.from(ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ES2022, target: ts.ScriptTarget.ES2022 } }).outputText).toString('base64'));
test('upstream IP, IPv6, hostname, tailnet, token and wrapper vectors', () => {
 for (const [input,base,code] of [
 ['192.168.1.100:3773','http://192.168.1.100:3773',''],
 ['[fd00::1]:3773','http://[fd00::1]:3773',''],
 ['remote.example.com','https://remote.example.com',''],
 ['https://desktop.tailnet.ts.net/path?token=query#token=hash','https://desktop.tailnet.ts.net','hash'],
 ['https://app.t3.codes/pair?host=https%3A%2F%2Fdesktop.tailnet.ts.net%2F#token=pairing-token','https://desktop.tailnet.ts.net','pairing-token'],
 ['t3code://pair?pairingUrl=https%3A%2F%2Fremote.example.com%2Fpair%23token%3Dpairing-token','https://remote.example.com','pairing-token'],
 ['wss://remote.example.com/path','https://remote.example.com',''],
 ['http://10.0.0.1:3773/#token=a%2Bb%26%E4%B8%AD','http://10.0.0.1:3773','a+b&中']
 ]) assert.deepEqual(pairingTarget(input), {base,code});
 assert.deepEqual(pairingTarget('remote.example.com',' code '),{base:'https://remote.example.com',code:'code'});
});
test('bad inputs and conflicting codes fail without exposing input', () => {
 for (const input of ['', 'javascript:alert(1)', 'ftp://test', 'https://user:secret@test', 'https://test:65536', 'http://[::zzz]', 't3code://else?pairingUrl=https://test', 't3code://pair?pairingUrl=t3code://pair', 'https://test/\\evil', 'https://test/#token=%00secret', 'https://app.t3.codes/?host=file:///tmp#token=secret']) {
  assert.throws(()=>pairingTarget(input), e=>!e.message.includes('secret'));
 }
 assert.throws(()=>pairingTarget('https://test/#token=a','b'));
});
