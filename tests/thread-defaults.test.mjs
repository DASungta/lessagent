import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { compile, data } from './load-core.mjs';
const source = (await readFile(new URL('../entry/src/main/ets/protocol/ThreadDefaults.ts', import.meta.url), 'utf8'))
  .replace("'./Wire'", JSON.stringify(new URL('../entry/src/main/ets/protocol/Wire.ts', import.meta.url).href));
const api = await import(data(compile(source)));
const config = () => ({environment:{environmentId:'a'},settings:{defaultRuntimeMode:'approval-required',defaultThreadEnvMode:null,responseStreamingMode:'paragraph',enableAgentBrowserAccess:true}});

test('thread defaults preserve inheritance and reject identity; missing and future fields stay unavailable', () => {
  const snapshot = api.threadDefaults(config(),'a');
  assert.equal(api.threadDefaultField(snapshot,'defaultThreadEnvMode').value,'inherit');
  assert.throws(()=>api.threadDefaults(config(),'b'));
  const partial = api.threadDefaults({...config(),settings:{defaultRuntimeMode:'future',enableAgentBrowserAccess:'true'}},'a');
  assert.equal(partial.fields.some(f=>f.supported),false);
  assert.throws(()=>api.threadDefaultsPatch(partial,'enableAgentBrowserAccess','false'));
  assert.throws(()=>api.threadDefaultsPatch(snapshot,'providers','false'));
  const badInheritance = api.threadDefaults({...config(),settings:{...config().settings,defaultThreadEnvMode:'inherit'}},'a');
  assert.equal(api.threadDefaultField(badInheritance,'defaultThreadEnvMode').supported,false);
});
test('single-field patches enforce native types, organization paths and runtime ceiling', () => {
  const snapshot = api.threadDefaults(config(),'a');
  assert.deepEqual(api.threadDefaultsPatch(snapshot,'defaultThreadEnvMode','inherit'),{defaultThreadEnvMode:null});
  assert.deepEqual(api.threadDefaultsPatch(snapshot,'enableAgentBrowserAccess','false'),{enableAgentBrowserAccess:false});
  assert.deepEqual(api.threadDefaultsPatch(snapshot,'responseStreamingMode','turn'),{responseStreamingMode:'turn'});
  for(const value of ['full','', 'TRUE']) assert.throws(()=>api.threadDefaultsPatch(snapshot,'defaultRuntimeMode',value));
  const locked = api.threadDefaults({...config(),managedPolicy:{organization:'Team',lockedSettings:['responseStreamingMode.child'],limits:{maxRuntimeMode:'auto-accept-edits'}}},'a');
  assert.equal(locked.managedBy,'Team');
  assert.throws(()=>api.threadDefaultsPatch(locked,'responseStreamingMode','turn'));
  assert.throws(()=>api.threadDefaultsPatch(locked,'defaultRuntimeMode','auto'));
  assert.deepEqual(api.threadDefaultsPatch(locked,'defaultRuntimeMode','auto-accept-edits'),{defaultRuntimeMode:'auto-accept-edits'});
  const unknown = api.threadDefaults({...config(),managedPolicy:{limits:{maxRuntimeMode:'future'}}},'a');
  assert.throws(()=>api.threadDefaultsPatch(unknown,'defaultRuntimeMode','approval-required'));
});
test('write reads fresh policy, changes one field then verifies the returned value', async()=>{
  const state=config(),calls=[];
  const connection={ready:true,canScope:()=>true,rpcRequest:async(method,payload)=>{
    calls.push({method,payload});
    if(method==='server.updateSettings') Object.assign(state.settings,payload.patch);
    return state;
  }};
  const result=await api.writeThreadDefault(connection,'a','responseStreamingMode','turn');
  assert.equal(api.threadDefaultField(result,'responseStreamingMode').value,'turn');
  assert.deepEqual(calls.map(c=>c.method),['server.getConfig','server.updateSettings','server.getConfig']);
  assert.deepEqual(calls[1].payload,{patch:{responseStreamingMode:'turn'}});
  connection.canScope=()=>false;
  await assert.rejects(api.writeThreadDefault(connection,'a','responseStreamingMode','paragraph'));
  assert.equal(calls.length,3);
});
test('timeout, mismatched readback and policy change never cause a mutation replay',async()=>{
  let writes=0;
  const connection={ready:true,canScope:()=>true,rpcRequest:async(method)=>{
    if(method==='server.updateSettings'){writes++;throw Error('timeout');}return config();
  }};
  await assert.rejects(api.writeThreadDefault(connection,'a','responseStreamingMode','turn'));
  assert.equal(writes,1);
  connection.rpcRequest=async method=>{if(method==='server.updateSettings')writes++;return config();};
  await assert.rejects(api.writeThreadDefault(connection,'a','responseStreamingMode','turn'),/回读/);
  assert.equal(writes,2);
  connection.rpcRequest=async()=>({...config(),managedPolicy:{lockedSettings:['responseStreamingMode']}});
  await assert.rejects(api.writeThreadDefault(connection,'a','responseStreamingMode','turn'));
  assert.equal(writes,2);
});
test('disconnect or scope revocation during pre-read prevents writing',async()=>{
  let writes=0,allowed=true;
  const connection={ready:true,canScope:()=>allowed,rpcRequest:async method=>{
    if(method==='server.updateSettings')writes++;
    allowed=false;return config();
  }};
  await assert.rejects(api.writeThreadDefault(connection,'a','responseStreamingMode','turn'));
  assert.equal(writes,0);
  allowed=true;
  connection.rpcRequest=async()=>{connection.ready=false;return config();};
  await assert.rejects(api.writeThreadDefault(connection,'a','responseStreamingMode','turn'));
  assert.equal(writes,0);
});
