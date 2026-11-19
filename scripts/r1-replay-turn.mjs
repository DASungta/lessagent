// One disposable Replay(dev) turn, isolated from collision fixtures and real providers.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {RpcClient,socketUrl,createThread,sendMessage} from '../entry/src/main/ets/protocol/Wire.ts';
const state=JSON.parse(await readFile(new URL('../docs/evidence/r1/lab-state.json',import.meta.url),'utf8'));
assert.ok(state.labRoot.includes('t3-harmony-r1-real-'));
const session=JSON.parse(await readFile(state.labRoot+'/replay-session-private.json','utf8'));
assert.equal(session.base,'http://127.0.0.1:47847');assert.ok(session.expiresAt>Date.now());
async function request(path,method='GET',body){
 const response=await fetch(session.base+path,{method,redirect:'error',headers:{'x-t3-orchestration-protocol':'2',Authorization:'Bearer '+session.token,...(body?{'Content-Type':'application/json'}:{})},body});
 if(!response.ok)throw Error('Replay fixture HTTP '+response.status+' at '+path);return response.json();
}
const descriptor=await request('/.well-known/t3/environment');assert.equal(descriptor.environmentId,session.environmentId);
const ticket=await request('/api/auth/websocket-ticket/rpc','POST');const socket=new WebSocket(socketUrl(session.base,ticket.ticket));
const rpc=new RpcClient({async send(frame){socket.send(frame)}});socket.addEventListener('message',event=>rpc.receive(event.data));
try{
 await new Promise((resolve,reject)=>{socket.addEventListener('open',resolve,{once:true});socket.addEventListener('error',()=>reject(Error('Replay socket failed')),{once:true})});
 let config=await rpc.request('server.getConfig',{});
 const instanceId='r1ReplayLink';
 if(!config.providers.some(p=>p.instanceId===instanceId)){
  const executable=spawnSync('fnm',['exec','--using','26.13.1','node','-p','process.execPath'],{encoding:'utf8'});assert.equal(executable.status,0);
  await rpc.request('server.updateSettings',{patch:{linkedEnvironmentsEnabled:true},providerInstanceMutation:{operation:'create',instanceId,instance:{driver:'acpRegistry',displayName:'R1 free Replay MCP fixture',enabled:true,config:{source:'local',commandPath:executable.stdout.trim(),commandArgs:[fileURLToPath(new URL('./r1-replay-link-agent.mjs',import.meta.url))]}}}});
  config=await rpc.request('server.getConfig',{});
 }
 const provider=config.providers.find(p=>p.instanceId===instanceId);
 assert.ok(provider?.installed&&provider.models.some(m=>m.slug==='question'),'Only the free, known Replay scenario is allowed');
 for(const threadId of ['r1-c05-replay-source','r1-c05-replay-source-2','r1-c05-replay-source-3','r1-c05-replay-source-4'])await rpc.request('orchestration.dispatchCommand',{type:'thread.stop',commandId:randomUUID(),threadId});
 const projectId='r1-c05-replay-project',threadId='r1-c05-replay-source-5',messageId='r1-c05-replay-prompt-5';
 const workspace=state.labRoot+'/replay-source/c05-workspace';await mkdir(workspace,{recursive:true});
 const projects=await request('/api/projects');
 if(!projects.projects.some(p=>p.id===projectId))await request('/api/projects/mutate','POST',JSON.stringify({type:'project.create',commandId:randomUUID(),projectId,title:'R1 free Replay only',workspaceRoot:workspace}));
 let response=await fetch(session.base+'/api/orchestration/threads/'+threadId,{headers:{'x-t3-orchestration-protocol':'2',Authorization:'Bearer '+session.token}});
 if(response.status===404){const command=createThread(randomUUID(),threadId,projectId,instanceId,'question');command.runtimeMode='full-access';await rpc.request('orchestration.dispatchCommand',command)}
 else assert.equal(response.status,200);
 let snapshot=await request('/api/orchestration/threads/'+threadId);assert.equal(snapshot.projection.thread.modelSelection.instanceId,instanceId);
 const intentPath=state.labRoot+'/replay-turn-intent-5.json';let intent;
 try{intent=JSON.parse(await readFile(intentPath,'utf8'))}catch(error){if(error.code!=='ENOENT')throw error}
 if(!snapshot.projection.messages.some(m=>m.id===messageId)){
  assert.equal(intent,undefined,'Previous Replay dispatch is unconfirmed: inspect instead of resending');
  intent={commandId:randomUUID(),threadId,messageId,acknowledged:false};await writeFile(intentPath,JSON.stringify(intent),{mode:0o600});
  await rpc.request('orchestration.dispatchCommand',sendMessage(intent.commandId,threadId,messageId,'R1 controlled free replay fixture. No real provider or business task.'));
  intent.acknowledged=true;await writeFile(intentPath,JSON.stringify(intent),{mode:0o600});
 }
 snapshot=await request('/api/orchestration/threads/'+threadId);
 const result={environmentId:session.environmentId,projectId,threadId,messageId,provider:instanceId,scenario:'question',paidModelsUsed:false,runs:snapshot.projection.runs.map(r=>({id:r.id,status:r.status})),pendingRequests:snapshot.projection.runtimeRequests.filter(r=>r.status==='pending').map(r=>({id:r.id,kind:r.kind}))};
 await writeFile(new URL('../docs/evidence/r1/replay-turn.json',import.meta.url),JSON.stringify(result,null,2)+'\n');
 console.log('PASS controlled Replay turn dispatched through real orchestration; no paid model');
}finally{rpc.fail('Replay fixture client finished');socket.close()}
