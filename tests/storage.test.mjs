import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
const ts=createRequire(import.meta.url)((process.env.DEVECO_HOME || '/Applications/DevEco-Studio.app/Contents')+'/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source=await readFile(new URL('../entry/src/main/ets/storage/SessionStore.ets',import.meta.url),'utf8');
async function setup(){
 let entry;let locked=false;const entries=new Map();
 const key=map=>Buffer.from(map.get(1)).toString('hex');
 const Tag={ALIAS:1,SECRET:2,RETURN_TYPE:3,ACCESSIBILITY:4,CONFLICT_RESOLUTION:5};
 const asset={Tag,ReturnType:{ALL:0},Accessibility:{DEVICE_UNLOCKED:2},ConflictResolution:{OVERWRITE:1},
 query:async map=>{if(locked)throw {code:24000005};if(!entries.has(key(map)))throw {code:24000002};return [entries.get(key(map))]},
 add:async map=>{assert.equal(map.get(Tag.ACCESSIBILITY),2);entry=map;entries.set(key(map),map)},remove:async map=>{entries.delete(key(map));entry=undefined}};
 globalThis.__storageKit={asset,screenLock:{isScreenLocked:async()=>locked},util:{TextEncoder:class{encodeInto(s){return new TextEncoder().encode(s)}},TextDecoder:class{decodeToString(v){return new TextDecoder().decode(v)}}}};
 const compiled=ts.transpileModule(source.replace("import { BusinessError, screenLock } from '@kit.BasicServicesKit';",'const {screenLock}=globalThis.__storageKit;').replace("import { asset } from '@kit.AssetStoreKit';",'const {asset}=globalThis.__storageKit;').replace("import { util } from '@kit.ArkTS';",'const {util}=globalThis.__storageKit;'),{compilerOptions:{module:ts.ModuleKind.ES2022,target:ts.ScriptTarget.ES2022}}).outputText;
 const {SessionStore}=await import('data:text/javascript;base64,'+Buffer.from(compiled+'\n//'+Math.random()).toString('base64'));
 return {store:new SessionStore(),recovery:new SessionStore('t3-harmony-recovery-v1'),asset,lock:()=>{locked=true},unlock:()=>{locked=false},entry:()=>entry};
}
test('Asset storage roundtrip, replacement, delete and locked-device fail closed',async()=>{
 const {store,lock}=await setup();assert.equal(await store.load(),undefined);
 const session={base:'https://test',environmentId:'e',token:'synthetic',expiresAt:123};
 await store.save(session);assert.deepEqual(await store.load(),session);
 await store.save({...session,token:'replacement'});assert.equal((await store.load()).token,'replacement');
 await assert.rejects(store.save({...session,token:'x'.repeat(1025)}),/大小限制/);
 await store.clear();assert.equal(await store.load(),undefined);
 lock();await assert.rejects(store.load(),/安全存储/);
});

test('recovery alias stays separate from credentials and contains metadata only',async()=>{
 const {store,recovery}=await setup();
 const session={base:'https://a',environmentId:'a',token:'synthetic',expiresAt:123};
 const state={base:'https://a',environmentId:'a',threadId:'t',pendingId:'m',pendingKind:'message'};
 await store.save(session);await recovery.save(state);
 assert.deepEqual(await store.load(),session);assert.deepEqual(await recovery.load(),state);
 await recovery.clear();assert.equal(await recovery.load(),undefined);assert.deepEqual(await store.load(),session);
});
test('Asset write acknowledgement alone cannot advance a credential or recovery reference',async()=>{
 const {store,recovery,asset}=await setup();
 const session={base:'https://test',environmentId:'e',token:'synthetic',expiresAt:123};
 await store.save(session);const add=asset.add;asset.add=async()=>{};
 await assert.rejects(store.save({...session,token:'replacement'}),/回读校验/);
 assert.deepEqual(await store.load(),session);
 await assert.rejects(recovery.save({base:'https://test',environmentId:'e',threadId:'t',pendingId:'unknown',pendingKind:'message'}),/回读校验/);
 assert.equal(await recovery.load(),undefined);asset.add=add;
});
test('explicit device lock guard rejects read, overwrite and delete without losing the original record',async()=>{
 const {store,lock,unlock}=await setup();const value={base:'https://synthetic.invalid',environmentId:'test',token:'SYNTHETIC_ONLY',expiresAt:1};
 await store.save(value);lock();
 await assert.rejects(store.load(),/解锁/);await assert.rejects(store.save({...value,token:'changed'}),/解锁/);await assert.rejects(store.clear(),/解锁/);
 unlock();assert.deepEqual(await store.load(),value);
});
test('a lock arriving during Asset query prevents the value from leaving the store',async()=>{
 const {store}=await setup();const value={base:'https://synthetic.invalid',environmentId:'test',token:'SYNTHETIC_ONLY',expiresAt:1};
 await store.save(value);let checks=0;globalThis.__storageKit.screenLock.isScreenLocked=async()=>++checks>1;
 await assert.rejects(store.load(),/安全存储/);
 globalThis.__storageKit.screenLock.isScreenLocked=async()=>false;assert.deepEqual(await store.load(),value);
});
