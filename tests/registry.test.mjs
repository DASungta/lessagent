import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {coreUrl} from './load-core.mjs';
const ts=createRequire(import.meta.url)((process.env.DEVECO_HOME || '/Applications/DevEco-Studio.app/Contents')+'/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const compile=s=>ts.transpileModule(s,{compilerOptions:{module:ts.ModuleKind.ES2022,target:ts.ScriptTarget.ES2022}}).outputText;
const data=s=>'data:text/javascript;base64,'+Buffer.from(s).toString('base64');
const environment=data(compile((await readFile(new URL('../entry/src/main/ets/protocol/Environment.ts',import.meta.url),'utf8')).replace("'./Core'",JSON.stringify(coreUrl)).replace("'./Wire'",JSON.stringify(new URL('../entry/src/main/ets/protocol/Wire.ts',import.meta.url).href))));
const environmentModule=await import(environment);
const hosts=data(compile(await readFile(new URL('../entry/src/main/ets/protocol/Hosts.ts',import.meta.url),'utf8')));
const original=await readFile(new URL('../entry/src/main/ets/services/EnvironmentRegistry.ets',import.meta.url),'utf8');
async function setup(){
 const records=new Map(),offline=new Set(),slowRoutes=new Map(),attempts=[],probes=[],backgrounds=[];
 let directory,failCommit=false,serial=0,shellCacheData={};let identity='env-a';
 class Store {constructor(alias){this.alias=alias}async load(){return structuredClone(records.get(this.alias))}async save(v){records.set(this.alias,structuredClone(v))}async clear(){records.delete(this.alias)}}
 class Directory {async load(){return structuredClone(directory)}async save(v){if(failCommit)throw Error('disk');directory=structuredClone(v)}}
 class ShellCache {async loadAll(){return structuredClone(shellCacheData)}async saveAll(v){shellCacheData=structuredClone(v)}}
 class Assets{session(alias){return new Store(alias)}recovery(alias){return new Store(alias)}}
 class Client {
  ready=false;mutationPending=false;status='offline';server='test';validateIdentity=()=>{};
  shell={projects:[],threads:[],archived:[],hasSnapshot:false,liveSynced:false};
  shellSynced=false;
  onShellUpdated=undefined;
  hydratedCache=undefined;
  async probeRoute(base,expectedEnvironmentId){
   probes.push(base);
   const delay=slowRoutes.get(base)||0;
   if(delay>0)await new Promise(r=>setTimeout(r,delay));
   if(offline.has(base))return {ok:false,base,error:'offline',checkedAt:Date.now()};
   if(expectedEnvironmentId&&expectedEnvironmentId!==identity)return {ok:false,base,error:'identity',checkedAt:Date.now()};
   return {ok:true,base,descriptor:{environmentId:identity,label:'Test',serverVersion:'test',orchestrationProtocolVersion:2},checkedAt:Date.now()};
  }
  async connect(base,code){attempts.push(base);try{if(offline.has(base))throw Error('offline');if(this.expectedEnvironmentId&&this.expectedEnvironmentId!==identity)throw Error('identity');this.validateIdentity(identity);if(code==='bad')throw Error('invalid');const saved=code?{base,environmentId:identity,token:'synthetic-'+identity,expiresAt:1}:await this.store.load(base);if(!saved)throw Error('missing');await this.store.save(saved);this.connectedBase=base;this.ready=true}catch(e){this.ready=false;this.status=e.message}}
  async verifyIdentity(){if(this.expectedEnvironmentId!==identity)throw Error('identity')}
  enterBackground(){backgrounds.push(this.connectedBase||this.expectedEnvironmentId||'unknown')}
  async resume(){}
  hydrateShellCache(cached){this.hydratedCache=structuredClone(cached);this.shell.projects=cached.projects.slice();this.shell.threads=cached.threads.slice();this.shell.hasSnapshot=true}
  exportShellCache(){if(!this.shellSynced)return undefined;return {environmentId:this.expectedEnvironmentId||identity,savedAt:Date.now(),scratchWorkspaceRoot:'',capabilities:{threadSettlement:true},projects:this.shell.projects.slice(),threads:this.shell.threads.slice()}}
  disconnect(msg,recover,clearShell){this.ready=false;if(msg)this.status=msg;if(clearShell){this.shell.projects=[];this.shell.threads=[];this.shell.hasSnapshot=false;this.shell.liveSynced=false;this.shellSynced=false}}
 }
 globalThis.__registryKit={T3Client:Client,SessionStore:Store,EnvironmentStore:Directory,ShellCacheStore:ShellCache,ProtectedEnvironmentAssets:Assets,url:{URL},util:{generateRandomUUID:()=>String(++serial)},pairingTarget:(base,code)=>({base,code})};
 const source=original.replace(/^import .*? from .*?;\n/gm,line=>line.includes("'../protocol/Environment'")?line.replace("'../protocol/Environment'",JSON.stringify(environment)):line.includes("'../protocol/Core'")?line.replace("'../protocol/Core'",JSON.stringify(coreUrl)):line.includes("'../protocol/Hosts'")?line.replace("'../protocol/Hosts'",JSON.stringify(hosts)):'')
 .replace('class ScopedRecovery','const {T3Client,SessionStore,EnvironmentStore,ShellCacheStore,ProtectedEnvironmentAssets,util,url,pairingTarget}=globalThis.__registryKit;\nclass ScopedRecovery');
 const {EnvironmentRegistry}=await import(data(compile(source)+'\n//'+Math.random()));
 const registry=new EnvironmentRegistry('/synthetic');await registry.initialize();
 return {registry,records,Store,Assets,Directory,offline,slowRoutes,attempts,probes,backgrounds,getShellCache:()=>structuredClone(shellCacheData),setShellCache:v=>shellCacheData=structuredClone(v),getDirectory:()=>structuredClone(directory),setIdentity:v=>identity=v,fail:v=>failCommit=v};
}
test('directory reuses known addresses, rejects duplicate identities at new addresses, and survives initialization',async()=>{
 const s=await setup();const a=await s.registry.add('https://a','code');
 assert.equal(await s.registry.add('https://a','code'),a);assert.equal(s.registry.clients.size,1);
 await assert.rejects(s.registry.add('https://unknown-address','code'),/已添加/);assert.equal(s.registry.clients.size,1);
 s.setIdentity('env-b');const b=await s.registry.add('https://b','code');
 assert.notEqual(a,b);assert.equal(s.getDirectory().entries.length,2);
 await s.registry.select(a);assert.equal(s.getDirectory().selectedLocalId,a);
 await s.registry.setEnabled(a,false);assert.equal(s.registry.clients.get(b).ready,true);
 assert.equal(s.registry.clients.get(a).ready,false);await assert.rejects(s.registry.reconnect(a),/启用/);
});
test('failed add commit leaves no active directory entry, client or orphan credential',async()=>{
 const s=await setup();s.fail(true);await assert.rejects(s.registry.add('https://a','code'),/disk/);
 assert.equal(s.registry.directory.entries.length,0);assert.equal(s.registry.clients.size,0);
 assert.equal([...s.records.keys()].filter(x=>x.endsWith('-session')).length,0);
});
test('failed re-pair reports failure and preserves directory, credential and unknown recovery',async()=>{
 const s=await setup();const id=await s.registry.add('https://a','code');
 await s.registry.saveRecovery(id,{base:'https://a',environmentId:'env-a',threadId:'t',pendingId:'unknown',pendingKind:'message'});
 const before=structuredClone([...s.records]),directory=s.getDirectory();
 await assert.rejects(s.registry.reconnect(id,'bad'),/invalid/);
 assert.deepEqual([...s.records],before);assert.deepEqual(s.getDirectory(),directory);
 await s.registry.reconnect(id,'replacement');
 assert.deepEqual(s.getDirectory(),directory);assert.equal(s.registry.entry(id).recovery.length,1);
 assert.equal(s.records.get(s.registry.entry(id).recovery[0].alias).pendingId,'unknown');
});
test('adding a known address refreshes the same environment without replacing unknown recovery or another environment',async()=>{
 const s=await setup();const a=await s.registry.add('https://a','code');
 await s.registry.saveRecovery(a,{base:'https://a',environmentId:'env-a',threadId:'t',pendingId:'unknown',pendingKind:'message'});
 const client=s.registry.clients.get(a),entry=structuredClone(s.registry.entry(a));
 s.setIdentity('env-b');const b=await s.registry.add('https://b','code');await s.registry.setEnabled(a,false);
 const before=s.getDirectory(),records=structuredClone([...s.records]);s.setIdentity('env-a');
 await assert.rejects(s.registry.add('https://a','bad'),/invalid/);assert.deepEqual(s.getDirectory(),before);assert.deepEqual([...s.records],records);
 assert.equal(await s.registry.add('https://a','replacement'),a);assert.equal(s.registry.clients.get(a),client);
 assert.equal(s.registry.entry(a).credentialRef,entry.credentialRef);assert.deepEqual(s.registry.entry(a).recovery,entry.recovery);
 assert.equal(s.registry.entry(a).enabled,true);assert.equal(s.registry.directory.selectedLocalId,a);assert.equal(s.registry.clients.get(b).ready,true);
 assert.equal(s.records.get(entry.recovery[0].alias).pendingId,'unknown');
 const refreshed=structuredClone([...s.records]);s.setIdentity('different-machine');
 await assert.rejects(s.registry.add('https://a','replacement'),/identity/);assert.deepEqual([...s.records],refreshed);
});
test('per-thread recovery references persist independently and unknown state blocks removal',async()=>{
 const s=await setup();const a=await s.registry.add('https://a','code');
 const state={base:'https://a',environmentId:'env-a',threadId:'one',pendingId:'unknown',pendingKind:'message'};
 await s.registry.saveRecovery(a,state);
 await s.registry.saveRecovery(a,{...state,threadId:'two',pendingId:'',pendingKind:''});
 assert.equal(s.registry.entry(a).recovery.length,2);await assert.rejects(s.registry.remove(a),/未知/);
 assert.equal(s.registry.entry(a).recovery.length,2);
 await s.registry.saveRecovery(a,{...state,pendingId:'',pendingKind:''});
 await s.registry.remove(a);assert.equal(s.registry.directory.entries.length,0);
 assert.equal([...s.records.keys()].filter(x=>x.startsWith('t3-v2-')).length,0);
});
test('removal refuses active mutations and leaves a resumable tombstone on interrupted cleanup',async()=>{
 const s=await setup();const a=await s.registry.add('https://a','code');const c=s.registry.clients.get(a);
 c.mutationPending=true;await assert.rejects(s.registry.remove(a),/提交/);assert.equal(c.ready,true);c.mutationPending=false;
 const old=s.registry.assets.session;s.registry.assets.session=()=>({clear:async()=>{throw Error('locked')}});
 await assert.rejects(s.registry.remove(a),/locked/);assert.equal(s.getDirectory().entries[0].deleting,true);
 s.registry.assets.session=old;await s.registry.reload();assert.equal(s.registry.directory.entries.length,0);
});
test('address update checks identity before moving credentials, and resumes an interrupted protected write',async()=>{
 const s=await setup();const id=await s.registry.add('https://a','code');
 const entry=s.registry.entry(id);
 await s.registry.saveRecovery(id,{base:'https://a',environmentId:'env-a',threadId:'t',pendingId:'',pendingKind:''});
 s.setIdentity('env-other');await assert.rejects(s.registry.edit(id,'new','https://changed'),/identity/);
 assert.equal(s.registry.entry(id).base,'https://a');assert.equal(s.records.get(entry.credentialRef).base,'https://a');
 s.setIdentity('env-a');const session=s.registry.assets.session.bind(s.registry.assets);let once=true;
 s.registry.assets.session=alias=>{const store=session(alias),save=store.save.bind(store);store.save=async v=>{if(once&&v.base==='https://changed'){once=false;throw Error('locked')}await save(v)};return store};
 await assert.rejects(s.registry.edit(id,'new','https://changed'),/locked/);
 assert.equal(s.getDirectory().entries[0].pendingBase,'https://changed');
 await s.registry.reload();assert.equal(s.registry.entry(id).base,'https://changed');
 assert.equal(s.registry.entry(id).pendingBase,undefined);assert.equal(s.records.get(entry.credentialRef).base,'https://changed');
 const alias=s.registry.entry(id).recovery[0].alias;assert.equal(s.records.get(alias).base,'https://a');assert.equal(s.registry.entry(id).recoveryBase,'https://a');
});
test('selecting the already selected environment does not rewrite the directory',async()=>{
 const s=await setup();const id=await s.registry.add('https://a','code');const before=s.getDirectory();
 await s.registry.select(id);assert.deepEqual(s.getDirectory(),before);
});
test('PR trust persists per saved endpoint, requires both sides, and is revoked before an address update',async()=>{
 const s=await setup();const a=await s.registry.add('https://a','code');s.setIdentity('env-b');const b=await s.registry.add('https://b','code');
 assert.equal(s.registry.canRoutePullRequest(a,b,false),false);await s.registry.setPullRequestRouting(a,'read');assert.equal(s.registry.canRoutePullRequest(a,b,false),false);
 await s.registry.setPullRequestRouting(b,'read');assert.equal(s.registry.canRoutePullRequest(a,b,false),true);assert.equal(s.registry.canRoutePullRequest(a,b,true),false);
 await s.registry.setPullRequestRouting(a,'read-write');await s.registry.setPullRequestRouting(b,'read-write');assert.equal(s.registry.canRoutePullRequest(a,b,true),true);
 await s.registry.setEnabled(a,false);assert.equal(s.registry.canRoutePullRequest(a,b,false),false);
 await s.registry.edit(b,'renamed','https://b-new');assert.equal(s.registry.entry(b).prRouting,undefined);assert.equal(s.registry.canRoutePullRequest(a,b,true),false);
 await assert.rejects(s.registry.setPullRequestRouting(b,'all'),/无效/);await s.registry.remove(b);assert.equal(s.getDirectory().entries.some(e=>e.localId===b),false);
});

test('explicit routes scope credentials and preserve unknown recovery through priority changes',async()=>{
 const s=await setup(),id=await s.registry.add('https://a','code'),client=s.registry.clients.get(id),first=s.registry.entry(id).credentialRef;
 const pending={base:'https://a',environmentId:'env-a',threadId:'t',pendingId:'unknown',pendingKind:'message'};await s.registry.saveRecovery(id,pending);
 await s.registry.setPullRequestRouting(id,'read');await s.registry.addRoute(id,'https://peer.ts.net','route-code');
 let e=s.registry.entry(id);assert.equal(e.prRouting,undefined);assert.equal(e.alternateRoutes.length,1);const second=e.alternateRoutes[0].credentialRef;assert.notEqual(first,second);
 assert.equal((await client.store.load('https://a')).base,'https://a');assert.equal((await client.store.load('https://peer.ts.net')).base,'https://peer.ts.net');await assert.rejects(client.store.load('https://unregistered'),/路径已移除/);
 await s.registry.setPullRequestRouting(id,'read');await s.registry.reorderRoutes(id,[second,first]);e=s.registry.entry(id);
 assert.equal(e.base,'https://peer.ts.net');assert.equal(e.recoveryBase,'https://a');assert.equal(e.prRouting,'read');assert.deepEqual(s.records.get(e.recovery[0].alias),pending);
 assert.equal(client.recoveryBase,'https://a');await assert.rejects(s.registry.reorderRoutes(id,[first,first]),/每条路径/);
});
test('wrong route identity and failed route commit preserve existing credentials and recovery',async()=>{
 const s=await setup(),id=await s.registry.add('https://a','code'),before=s.getDirectory(),records=structuredClone([...s.records]);
 s.setIdentity('other');await assert.rejects(s.registry.addRoute(id,'https://other','code'),/identity/);assert.deepEqual(s.getDirectory(),before);assert.deepEqual([...s.records],records);
 s.setIdentity('env-a');s.fail(true);await assert.rejects(s.registry.addRoute(id,'https://new','code'),/disk/);assert.deepEqual(s.getDirectory(),before);assert.deepEqual([...s.records],records);
});
test('a failed credential cleanup leaves a route tombstone and restart removes only its alias',async()=>{
 const s=await setup(),id=await s.registry.add('https://a','code'),retired=s.registry.entry(id).credentialRef;await s.registry.addRoute(id,'https://b','code');
 const live=s.registry.entry(id).credentialRef;assert.notEqual(live,retired);const original=s.registry.assets.session.bind(s.registry.assets);let fail=true;
 s.registry.assets.session=alias=>{const store=original(alias),clear=store.clear.bind(store);store.clear=async()=>{if(alias===retired&&fail){fail=false;throw Error('locked')}await clear()};return store};
 await assert.rejects(s.registry.removeRoute(id,retired),/locked/);assert.deepEqual(s.getDirectory().entries[0].retiredCredentialRefs,[retired]);assert.ok(s.records.has(live));assert.ok(s.records.has(retired));
 await s.registry.reload();assert.equal(s.registry.entry(id).retiredCredentialRefs,undefined);assert.equal(s.records.has(retired),false);assert.ok(s.records.has(live));
 await s.registry.removeRoute(id,live);assert.equal(s.registry.directory.entries.length,0);
});
test('reconnect probes saved routes concurrently in priority order with head-start fallback and per-route credentials',async()=>{
 const s=await setup(),id=await s.registry.add('https://a','code');await s.registry.addRoute(id,'https://peer.ts.net','code');
 // Fast offline primary immediately yields to reachable alternate without waiting for full connect timeout
 s.offline.add('https://a');s.attempts.length=0;s.probes.length=0;
 await s.registry.reconnect(id);
 assert.deepEqual(s.probes,['https://a','https://peer.ts.net']);
 assert.deepEqual(s.attempts,['https://peer.ts.net']);
 assert.equal(s.registry.clients.get(id).connectedBase,'https://peer.ts.net');

 // Slow hanging primary (>500ms head start) falls over to fast alternate without waiting for primary to settle
 s.offline.clear();
 s.slowRoutes.set('https://a', 1500);
 s.attempts.length=0;s.probes.length=0;
 const started=Date.now();
 await s.registry.reconnect(id);
 const elapsed=Date.now()-started;
 assert.equal(s.registry.clients.get(id).connectedBase,'https://peer.ts.net');
 assert.ok(elapsed < 1100, `expected head-start failover <1100ms, got ${elapsed}ms`);

 // Fast reachable primary still wins over fast reachable alternate
 s.slowRoutes.clear();
 s.attempts.length=0;s.probes.length=0;
 await s.registry.reconnect(id);
 assert.equal(s.registry.clients.get(id).connectedBase,'https://a');
 assert.deepEqual(s.attempts,['https://a']);
});

test('shell cache persists on live updates, hydrates immediately on reload, and respects disable/remove/background lifecycle',async()=>{
 const s=await setup(),id=await s.registry.add('https://a','code');
 const client=s.registry.clients.get(id);
 client.shell.projects=[{id:'p1',label:'Repo',projectId:'p1',workspaceRoot:'/repo'}];
 client.shell.threads=[{id:'t1',label:'Cached thread',projectId:'p1'}];
 client.shellSynced=true;
 client.onShellUpdated();
 await s.registry.flushShellCache();
 assert.equal(s.getShellCache()[id].threads[0].id,'t1');

 // Background keeps client alive via enterBackground and foreground passes duration to resume
 let receivedDuration=-1;
 client.resume=async(ms)=>{receivedDuration=ms};
 s.registry.suspend();
 assert.equal(client.ready,true);
 assert.equal(s.backgrounds.length,1);
 await s.registry.resume();
 assert.ok(receivedDuration >= 0);

 // Reload hydrates cached shell before reconnect
 await s.registry.reload();
 const reloaded=s.registry.clients.get(id);
 assert.equal(reloaded.ready,false);
 assert.equal(reloaded.shell.hasSnapshot,true);
 assert.equal(reloaded.shell.threads[0].label,'Cached thread');

 // Disable clears in-memory shell and drops cache entry
 await s.registry.setEnabled(id,false);
 await s.registry.flushShellCache();
 assert.equal(reloaded.shell.threads.length,0);
 assert.equal(s.getShellCache()[id],undefined);
});
test('one environment resume failure does not stop another environment from resuming',async()=>{
 const s=await setup(),a=await s.registry.add('https://a','code');s.setIdentity('env-b');const b=await s.registry.add('https://b','code');let resumed=false;
 s.registry.clients.get(a).resume=async()=>{throw Error('A offline')};s.registry.clients.get(b).resume=async()=>{resumed=true};await s.registry.resume();assert.equal(resumed,true);assert.equal(s.registry.clients.get(a).status,'A offline');
});

test('cloud environments stay account-scoped, coexist with bearer environments and do not read session assets',async()=>{
 const s=await setup();const direct=await s.registry.add('https://direct','code');
 let factoryCalls=0;
 await s.registry.setCloudAccount('user-a',entry=>{factoryCalls++;return {environmentId:entry.environmentId}});
 const session=s.registry.assets.session.bind(s.registry.assets);
 s.registry.assets.session=alias=>{if(alias.startsWith('t3-cloud-'))throw Error('cloud read session');return session(alias)};
 const cloud=await s.registry.addCloud('env-cloud','Cloud','https://env-cloud.example.test','user-a');
 assert.equal(s.registry.directory.entries.length,2);assert.equal(s.registry.entryVisible(s.registry.entry(cloud)),true);
 assert.deepEqual(environmentModule.environmentRoutes(s.registry.entry(cloud)),[]);
 assert.equal(await s.registry.addCloud('env-cloud','Cloud','https://env-cloud.example.test','user-a'),cloud);
 await s.registry.setCloudAccount('user-b',entry=>({environmentId:entry.environmentId}));
 assert.equal(s.registry.entryVisible(s.registry.entry(cloud)),false);assert.equal(s.registry.clients.has(cloud),false);
 assert.equal(s.registry.entryVisible(s.registry.entry(direct)),true);
 await s.registry.setCloudAccount('user-a',entry=>({environmentId:entry.environmentId}));
 assert.equal(s.registry.clients.has(cloud),true);
 assert.equal(s.registry.clients.get(cloud).cloud.environmentId,'env-cloud');
 assert.ok(factoryCalls>=1);
 await s.registry.removeCloudAccount('user-a');assert.equal(s.registry.directory.entries.some(entry=>entry.localId===cloud),false);
 assert.equal(s.registry.directory.entries.some(entry=>entry.localId===direct),true);
});

test('cloud cleanup blocks on unknown submission and preserves the directory until reconciliation',async()=>{
 const s=await setup();
 await s.registry.setCloudAccount('user-a',entry=>({environmentId:entry.environmentId}));
 const cloud=await s.registry.addCloud('env-cloud','Cloud','https://env-cloud.example.test','user-a');
 await s.registry.saveRecovery(cloud,{base:'https://env-cloud.example.test',environmentId:'env-cloud',
  threadId:'t',pendingId:'unknown',pendingKind:'message'});
 await assert.rejects(s.registry.removeCloudAccount('user-a'),/未知/);
 assert.equal(s.registry.entry(cloud).recovery.length,1);
});

test('cloud endpoint rotation keeps the original recovery anchor and unknown submission readable',async()=>{
 const s=await setup();
 await s.registry.setCloudAccount('user-a',entry=>({environmentId:entry.environmentId}));
 const cloud=await s.registry.addCloud('env-cloud','Cloud','https://old.example.test','user-a');
 const pending={base:'https://old.example.test',environmentId:'env-cloud',threadId:'t',pendingId:'unknown',pendingKind:'message'};
 await s.registry.saveRecovery(cloud,pending);
 await s.registry.syncCloudEndpoint('env-cloud','user-a','Renamed','https://new.example.test');
 const entry=s.registry.entry(cloud);
 assert.equal(entry.base,'https://new.example.test');assert.equal(entry.recoveryBase,'https://old.example.test');
 assert.equal(s.registry.clients.get(cloud).recoveryBase,'https://old.example.test');
 assert.equal(s.records.get(entry.recovery[0].alias).pendingId,'unknown');
 await s.registry.reload();
 assert.equal(s.registry.entry(cloud).recoveryBase,'https://old.example.test');
});
