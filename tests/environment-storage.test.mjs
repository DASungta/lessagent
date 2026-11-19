import test from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';
const ts=createRequire(import.meta.url)((process.env.DEVECO_HOME || '/Applications/DevEco-Studio.app/Contents')+'/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source=fs.readFileSync(new URL('../entry/src/main/ets/storage/EnvironmentStore.ets',import.meta.url),'utf8');
// Run the actual file adapter against a private host temp directory, with file faults injected.
const body=source.slice(source.indexOf('export class EnvironmentStore'),source.indexOf('export class ProtectedEnvironmentAssets'));
const compiled=ts.transpileModule(body.replace('export class','class')+'\nreturn EnvironmentStore;', {compilerOptions:{target:ts.ScriptTarget.ES2022}}).outputText;
test('atomic directory replacement survives interrupted writes, readback and rename; missing differs from corrupt',async()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'t3-env-'));
 let fault='';
 const kit={OpenMode:{CREATE:1,READ_WRITE:2,TRUNC:4},
  readTextSync:p=>{try {const text=fs.readFileSync(p,'utf8');return fault==='readback'&&p.endsWith('.tmp')?'{}':text}catch(e){if(e.code==='ENOENT')throw {code:13900002};throw e}},
  openSync:p=>({fd:fs.openSync(p,'w',0o600)}),
  writeSync:(fd,v)=>{if(fault==='write')throw Error('write');return fs.writeSync(fd,v)},
  fsyncSync:fd=>fs.fsyncSync(fd),closeSync:f=>fs.closeSync(f.fd),
  renameSync:(a,b)=>{if(fault==='rename')throw Error('rename');fs.renameSync(a,b)}};
 const validate=value=>{assert.equal(value.schemaVersion,2);assert.ok(Array.isArray(value.entries));return value};
 const Store=new Function('fileIo','environmentDirectory',compiled)(kit,validate);
 try {
  const store=new Store(root);assert.equal(await store.load(),undefined);
  const old={schemaVersion:2,generation:1,selectedLocalId:'',entries:[]};await store.save(old);
  for(const injected of ['write','readback','rename']){
   fault=injected;await assert.rejects(store.save({...old,generation:2}));fault='';assert.deepEqual(await store.load(),old);
  }
  await store.clear();assert.equal((await store.load()).generation,2);
  fs.writeFileSync(path.join(root,'environments-v2.json'),'broken');await assert.rejects(store.load(),/损坏/);
  assert.equal(fs.readFileSync(path.join(root,'environments-v2.json'),'utf8'),'broken');
 } finally {fs.rmSync(root,{recursive:true,force:true})}
});
