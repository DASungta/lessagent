// Isolated real-server data only: same project/thread IDs, no messages or agent tasks.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import {RpcClient,bootstrapForm,createThread,socketUrl} from '../entry/src/main/ets/protocol/Wire.ts';
const state=JSON.parse(await readFile(new URL('../docs/evidence/r1/lab-state.json',import.meta.url),'utf8'));
assert.equal(state.services.length,2);assert.ok(state.labRoot.includes('t3-harmony-r1-real-'));
const projectId='r1-collision-project',threadId='r1-collision-thread';const results=[];
for(const service of state.services){
 assert.ok(service.baseDir.startsWith(state.labRoot+'/'));assert.ok([47831,47832].includes(service.port));
 const issued=spawnSync('t3',['auth','pairing','create','--base-dir',service.baseDir,'--scope','orchestration:read','--scope','orchestration:operate','--ttl','30m','--label','harmony-r1-fixture-setup','--json'],{env:{...process.env,T3CODE_HOME:service.baseDir},encoding:'utf8'});
 assert.equal(issued.status,0,'private test grant creation failed');const grant=JSON.parse(issued.stdout);
 const base='http://127.0.0.1:'+service.port;
 async function request(path,method='GET',body,token=''){
  const response=await fetch(base+path,{method,redirect:'error',headers:{...(token?{Authorization:'Bearer '+token}:{}),...(path.startsWith('/api/orchestration/')?{'x-t3-orchestration-protocol':'2'}:{}),...(body?{'Content-Type':path==='/oauth/token'?'application/x-www-form-urlencoded':'application/json'}:{})},body});
  if(!response.ok)throw Error('isolated HTTP failure '+response.status+' at '+path);
  return response.status===204?undefined:response.json();
 }
 const auth=await request('/oauth/token','POST',bootstrapForm(grant.credential));assert.equal(auth.token_type,'Bearer');const token=auth.access_token;
 const descriptor=await request('/.well-known/t3/environment');assert.equal(descriptor.environmentId,service.environmentId);
 const workspace=service.baseDir+'/empty-workspace';await mkdir(workspace,{recursive:true});
 let projects=await request('/api/projects','GET',undefined,token);
 const existing=projects.projects.find(p=>p.id===projectId);
 if(existing)assert.equal(existing.workspaceRoot,workspace);
 else await request('/api/projects/mutate','POST',JSON.stringify({type:'project.create',commandId:randomUUID(),projectId,title:'R1 isolated '+service.name.toUpperCase(),workspaceRoot:workspace}),token);
 projects=await request('/api/projects','GET',undefined,token);assert.ok(projects.projects.some(p=>p.id===projectId&&p.workspaceRoot===workspace));
 const ticket=await request('/api/auth/websocket-ticket/rpc','POST',undefined,token);
 const socket=new WebSocket(socketUrl(base,ticket.ticket));const rpc=new RpcClient({async send(frame){socket.send(frame)}});
 socket.addEventListener('message',event=>rpc.receive(event.data));
 try {
  await new Promise((resolve,reject)=>{socket.addEventListener('open',resolve,{once:true});socket.addEventListener('error',()=>reject(Error('isolated socket failed')),{once:true})});
  const config=await rpc.request('server.getConfig',{});
  const provider=config.providers.find(p=>p.enabled!==false&&p.installed!==false&&p.models?.length);
  // Empty thread metadata only; an unconfigured selection never receives a message or starts a provider.
  const selection=provider?{instanceId:provider.instanceId,model:provider.models[0].slug}:{instanceId:'r1-unconfigured-provider',model:'r1-metadata-only'};
  const snapshotResponse=await fetch(base+'/api/orchestration/threads/'+threadId,{headers:{Authorization:'Bearer '+token,'x-t3-orchestration-protocol':'2'}});
  if(snapshotResponse.status===404)await rpc.request('orchestration.dispatchCommand',createThread(randomUUID(),threadId,projectId,selection.instanceId,selection.model));
  else if(snapshotResponse.status!==200)throw Error('isolated snapshot rejected '+snapshotResponse.status+' '+(await snapshotResponse.text()).replaceAll(token,'<redacted>'));
  const snapshot=await request('/api/orchestration/threads/'+threadId,'GET',undefined,token);
  const projection=snapshot.projection ?? snapshot;
  assert.equal(projection.thread.id,threadId);assert.equal(projection.thread.projectId,projectId);assert.equal(projection.messages.length,0);assert.equal(projection.providerTurns.length,0);assert.equal(projection.runs.length,0);assert.equal(projection.providerSessions.length,0);
  results.push({environmentId:service.environmentId,projectId,threadId,workspaceRoot:workspace,messages:0,providerTurns:0,runs:0,providerSessions:0,providerVerified:false});
 } finally {rpc.fail('isolated fixture finished');socket.close()}
}
assert.notEqual(results[0].environmentId,results[1].environmentId);
await writeFile(new URL('../docs/evidence/r1/real-collision-fixtures.json',import.meta.url),JSON.stringify({results,noMessageCommandsSent:true},null,2)+'\n');
console.log('PASS two real environments contain identical project/thread IDs; zero messages and turns');
