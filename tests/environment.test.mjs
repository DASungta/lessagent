import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { coreUrl } from './load-core.mjs';
const ts = createRequire(import.meta.url)((process.env.DEVECO_HOME || '/Applications/DevEco-Studio.app/Contents') + '/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = (await readFile(new URL('../entry/src/main/ets/protocol/Environment.ts', import.meta.url), 'utf8'))
 .replace("'./Core'", JSON.stringify(coreUrl)).replace("'./Wire'", JSON.stringify(new URL('../entry/src/main/ets/protocol/Wire.ts', import.meta.url).href));
const { environmentDirectory, environmentRouteKey, savedSession, migrateLegacy } = await import('data:text/javascript;base64,' + Buffer.from(ts.transpileModule(source, {compilerOptions:{module:ts.ModuleKind.ES2022,target:ts.ScriptTarget.ES2022}}).outputText).toString('base64'));
const session = {base:'https://test',environmentId:'env',token:'SYNTHETIC',expiresAt:1};
const recovery = {base:session.base,environmentId:'env',threadId:'same-thread',pendingId:'unknown',pendingKind:'message'};
function store(value) { return {value, async load(){return structuredClone(this.value)}, async save(v){this.value=structuredClone(v)},async clear(){this.value=undefined}}; }
function setup(){
 const directory=store(),legacy=store(session),oldRecovery=store(recovery),records=new Map();
 const asset=alias=>{if(!records.has(alias))records.set(alias,store());return records.get(alias)};
 return {directory,legacy,oldRecovery,records,assets:{session:asset,recovery:asset},run(){return migrateLegacy(directory,this.assets,legacy,oldRecovery)}};
}
test('expired legacy session and unknown marker survive commit and idempotent restart',async()=>{
 const s=setup();const result=await s.run();assert.equal(result.entries.length,1);
 assert.deepEqual(s.legacy.value,session);assert.deepEqual(s.oldRecovery.value,recovery);
 assert.deepEqual(s.records.get(result.entries[0].credentialRef).value,session);
 assert.deepEqual(s.records.get(result.entries[0].recovery[0].alias).value,recovery);
 assert.deepEqual(await s.run(),result);assert.equal(s.records.size,2);
});
for(const point of ['directory-read','legacy-read','recovery-read','session-write','session-readback','recovery-write','recovery-readback','commit']) {
 test(`migration failure at ${point} preserves v1, retry commits one entry`,async()=>{
  const s=setup();let restore;
  function fail(target,method){const original=target[method];target[method]=async()=>{throw Error('injected')};restore=()=>target[method]=original;}
  if(point==='directory-read')fail(s.directory,'load');
  if(point==='legacy-read')fail(s.legacy,'load');
  if(point==='recovery-read')fail(s.oldRecovery,'load');
  if(point==='session-write')fail(s.assets.session('t3-v2-legacy-v1-session'),'save');
  if(point==='session-readback')fail(s.assets.session('t3-v2-legacy-v1-session'),'load');
  if(point==='recovery-write')fail(s.assets.recovery('t3-v2-legacy-v1-recovery-initial'),'save');
  if(point==='recovery-readback')fail(s.assets.recovery('t3-v2-legacy-v1-recovery-initial'),'load');
  if(point==='commit')fail(s.directory,'save');
  await assert.rejects(s.run());assert.equal(s.directory.value,undefined);
  assert.deepEqual(s.legacy.value,session);assert.deepEqual(s.oldRecovery.value,recovery);
  restore();const result=await s.run();assert.equal(result.entries.length,1);assert.equal(s.records.size,2);
 });
}
test('mismatched, orphan and malformed legacy records remain quarantined without activation',async()=>{
 for(const value of [{...recovery,environmentId:'other'},{...recovery,pendingKind:'future'}, {...recovery,threadId:''}]){
  const s=setup();s.oldRecovery.value=value;await assert.rejects(s.run());assert.equal(s.directory.value,undefined);assert.deepEqual(s.oldRecovery.value,value);
 }
 const s=setup();s.legacy.value=undefined;await assert.rejects(s.run());assert.deepEqual(s.oldRecovery.value,recovery);
 for(const value of [{...session,token:''},{...session,expiresAt:Infinity},{...session,base:'https://test/#token=secret'}])assert.throws(()=>savedSession(value));
});
test('incorrect readback cannot commit, including lost pending marker',async()=>{
 const s=setup();s.assets.recovery('t3-v2-legacy-v1-recovery-initial').load=async()=>({...recovery,pendingId:'',pendingKind:''});
 await assert.rejects(s.run(),/回读/);assert.equal(s.directory.value,undefined);assert.deepEqual(s.oldRecovery.value,recovery);
});
test('schema rejects secrets, duplicate identities, bad references, scope and selection',async()=>{
 const s=setup();const d=await s.run();const entry=d.entries[0];
 const bad=[{...d,token:'secret'},{...d,schemaVersion:3},{...d,generation:-1},{...d,selectedLocalId:'missing'},
 {...d,entries:[entry,entry]}, {...d,entries:[{...entry,credentialRef:'t3-harmony-session-v1'}]},
 {...d,entries:[{...entry,recovery:[{threadId:'t',alias:'t3-v2-other-recovery-x'}]}]},
 {...d,entries:[{...entry,base:'https://user:secret@test'}]}];
 for(const value of bad)assert.throws(()=>environmentDirectory(value));
 const other={...entry,localId:'other',environmentId:'other-env',credentialRef:'t3-v2-other-session',recovery:[{threadId:'same-thread',alias:'t3-v2-other-recovery-uuid'}]};
 assert.equal(environmentDirectory({...d,entries:[entry,other]}).entries.length,2);
});
test('empty committed directory suppresses legacy resurrection',async()=>{
 const s=setup();s.directory.value={schemaVersion:2,generation:2,selectedLocalId:'',entries:[]};
 assert.deepEqual(await s.run(),s.directory.value);assert.equal(s.records.size,0);
});
test('existing directory checks every protected reference; lock or missing records fail closed',async()=>{
 const s=setup();const d=await s.run();
 const r=s.assets.recovery(d.entries[0].recovery[0].alias);
 r.value={...recovery,pendingId:17};await assert.rejects(s.run());
 r.value=recovery;r.load=async()=>{throw Error('locked')};await assert.rejects(s.run(),/locked/);
 const a=s.assets.session(d.entries[0].credentialRef);a.value=undefined;await assert.rejects(s.run(),/缺失/);
 assert.deepEqual(s.directory.value,d);
});
test('JSON null and scalar corruption are never interpreted as missing records',async()=>{
 for(const value of [null, false, 0, '']) {
  const s=setup();s.legacy.value=value;await assert.rejects(s.run());assert.equal(s.directory.value,undefined);
  const r=setup();r.oldRecovery.value=value;await assert.rejects(r.run());assert.equal(r.directory.value,undefined);
  const d=setup();d.directory.value=value;await assert.rejects(d.run());assert.equal(d.directory.value,value);
 }
});
test('alternate credentials validate independently while recovery retains the original environment anchor',async()=>{
 const s=setup(),d=await s.run(),entry=d.entries[0];const original={base:entry.base,credentialRef:entry.credentialRef};
 const ref='t3-v2-legacy-v1-route-lan-session';s.assets.session(ref).value={...session,base:'http://192.168.1.2:4000',token:'OTHER_SYNTHETIC'};
 entry.base='http://192.168.1.2:4000';entry.credentialRef=ref;entry.alternateRoutes=[original];entry.recoveryBase=session.base;
 s.directory.value=d;assert.deepEqual(await s.run(),d);assert.deepEqual(s.oldRecovery.value,recovery);
 s.assets.session(ref).value={...session,base:entry.base,environmentId:'other'};await assert.rejects(s.run(),/凭据身份不一致/);
});
test('route schema rejects foreign aliases, repeated origins, secret metadata and retiring live aliases',async()=>{
 const s=setup(),d=await s.run(),e=d.entries[0],route={base:'https://alternate',credentialRef:'t3-v2-legacy-v1-route-alt-session'};
 for(const entry of [{...e,alternateRoutes:[{...route,credentialRef:'t3-v2-other-route-alt-session'}]}, {...e,alternateRoutes:[{...route,base:e.base}]}, {...e,alternateRoutes:[{...route,token:'secret'}]}, {...e,alternateRoutes:[route,route]}, {...e,retiredCredentialRefs:[e.credentialRef]}, {...e,recoveryBase:'https://test/#token=secret'}])assert.throws(()=>environmentDirectory({...d,entries:[entry]}));
 const retired={...e,retiredCredentialRefs:[route.credentialRef]};assert.equal(environmentDirectory({...d,entries:[retired]}).entries[0].retiredCredentialRefs.length,1);
});
test('route identity changes with each scoped credential so ArkUI never reuses a stale route row',()=>{
 const entry={localId:'a',base:'https://a',credentialRef:'t3-v2-a-session',alternateRoutes:[{base:'https://b',credentialRef:'t3-v2-a-route-b-session'}]};
 const first=environmentRouteKey(entry);assert.match(first,/t3-v2-a-session/);assert.match(first,/t3-v2-a-route-b-session/);
 assert.equal(environmentRouteKey({...entry,alternateRoutes:[entry.alternateRoutes[0],{base:'https://c',credentialRef:'t3-v2-a-route-c-session'}]})===first,false);
 assert.equal(environmentRouteKey({...entry,alternateRoutes:[{...entry.alternateRoutes[0]}]}),first);
});
test('deletion tombstone survives validation so interrupted cleanup can resume before credentials load',async()=>{
 const s=setup();const d=await s.run();d.entries[0].deleting=true;d.entries[0].enabled=false;
 const checked=environmentDirectory(d);assert.equal(checked.entries[0].deleting,true);
 s.directory.value=d;s.assets.session(d.entries[0].credentialRef).load=async()=>{throw Error('already deleted')};
 assert.equal((await s.run()).entries[0].deleting,true);
 assert.throws(()=>environmentDirectory({...d,entries:[{...d.entries[0],deleting:'yes'}]}));
});
test('savedSession accepts direct DPoP sessions alongside legacy Bearer sessions without data loss',async()=>{
 const legacy=savedSession(session);
 assert.deepEqual(legacy,session);
 assert.equal(Object.prototype.hasOwnProperty.call(legacy,'kind'),false);
 const dpop=savedSession({...session,kind:'dpop'});
 assert.deepEqual(dpop,{...session,kind:'dpop'});
 const explicitBearer=savedSession({...session,kind:'bearer'});
 assert.deepEqual(explicitBearer,{...session,kind:'bearer'});
 for(const invalid of [{...session,kind:'cloud'},{...session,kind:''},{...session,kind:123},{...session,kind:null},{...session,kind:'dpop',extra:true}]){
  assert.throws(()=>savedSession(invalid));
 }
 const s=setup();
 const d=await s.run();
 const ref=d.entries[0].credentialRef;
 s.assets.session(ref).value={...session,kind:'dpop'};
 assert.deepEqual(await s.run(),d);
 assert.deepEqual(s.assets.session(ref).value,{...session,kind:'dpop'});
});
