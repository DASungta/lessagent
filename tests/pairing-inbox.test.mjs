import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
const ts=createRequire(import.meta.url)((process.env.DEVECO_HOME || '/Applications/DevEco-Studio.app/Contents')+'/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const storage=new Map();globalThis.AppStorage={get:k=>storage.get(k),setOrCreate:(k,v)=>storage.set(k,v)};
const source=(await readFile(new URL('../entry/src/main/ets/services/PairingInbox.ets',import.meta.url),'utf8')).replace("import { pairingTarget, PairingTarget } from '../protocol/Pairing';", "const pairingTarget=value=>{const wrapper=new URL(value);const target=new URL(wrapper.searchParams.get('pairingUrl'));if(!/^https?:$/.test(target.protocol))throw Error('bad');return {base:target.origin,code:target.hash.slice(1)}};");
const compiled=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.ES2022,target:ts.ScriptTarget.ES2022}}).outputText;
const {acceptPairingLink,takePairingLink}=await import('data:text/javascript;base64,'+Buffer.from(compiled).toString('base64'));
test('cold/warm links only stage an in-memory target and are consumed once',()=>{
 const link='t3code://pair?pairingUrl='+encodeURIComponent('https://synthetic.invalid/#SYNTHETIC');acceptPairingLink(link);
 assert.deepEqual(takePairingLink(),{base:'https://synthetic.invalid',code:'SYNTHETIC'});assert.equal(takePairingLink(),undefined);
 assert.equal(storage.get('t3PairingRevision'),1);assert.ok(!JSON.stringify([...storage.values()]).includes('SYNTHETIC'));
 acceptPairingLink(link);assert.ok(takePairingLink());
});
test('malicious and unrelated links clear pending content with a generic error',()=>{
 for(const link of ['javascript:alert(1)','t3code://else?pairingUrl=https://x','t3code://pair?pairingUrl=file:///tmp/secret']){
  acceptPairingLink(link);assert.equal(takePairingLink(),undefined);assert.equal(storage.get('t3PairingError'),'配对链接无效，请检查后重新打开');
 }
});
