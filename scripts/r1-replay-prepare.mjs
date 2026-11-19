// Prepare only this goal's isolated source backend. Never print auth material.
import {spawnSync} from 'node:child_process';
import {readFile,writeFile,chmod,mkdir} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
import {RpcClient,bootstrapForm,socketUrl} from '../entry/src/main/ets/protocol/Wire.ts';
const statePath=new URL('../docs/evidence/r1/lab-state.json',import.meta.url);
const state=JSON.parse(await readFile(statePath,'utf8'));assert.ok(state.labRoot.includes('t3-harmony-r1-real-'));
const home=state.labRoot+'/replay-source',base='http://127.0.0.1:47847';
const issued=spawnSync('fnm',['exec','--using','26.13.1','node','apps/server/src/bin.ts','auth','pairing','create','--base-dir',home,'--scope','orchestration:read','--scope','orchestration:operate','--scope','access:read','--scope','access:write','--scope','settings:write','--scope','providers:manage','--ttl','2h','--label','harmony-r1-replay-setup','--json'],{cwd:'/tmp/t3code-harmony-upstream',env:{...process.env,T3CODE_HOME:home},encoding:'utf8'});
assert.equal(issued.status,0,'isolated source grant setup failed');const grant=JSON.parse(issued.stdout);
async function request(path,method='GET',body,token=''){
 const response=await fetch(base+path,{method,redirect:'error',headers:{...(token?{Authorization:'Bearer '+token}:{}),...(body?{'Content-Type':path==='/oauth/token'?'application/x-www-form-urlencoded':'application/json'}:{})},body});
 if(!response.ok)throw Error('isolated source API '+response.status+' at '+path);
 return response.json();
}
const descriptor=await request('/.well-known/t3/environment');const auth=await request('/oauth/token','POST',bootstrapForm(grant.credential));assert.equal(auth.token_type,'Bearer');
const token=auth.access_token;
const sessionPath=state.labRoot+'/replay-session-private.json';await writeFile(sessionPath,JSON.stringify({base,environmentId:descriptor.environmentId,token,expiresAt:Date.now()+auth.expires_in*1000}),{mode:0o600});await chmod(sessionPath,0o600);
const ticket=await request('/api/auth/websocket-ticket/rpc','POST',undefined,token);
const socket=new WebSocket(socketUrl(base,ticket.ticket));const rpc=new RpcClient({async send(frame){socket.send(frame)}});
socket.addEventListener('message',event=>rpc.receive(event.data));
try {
 await new Promise((resolve,reject)=>{socket.addEventListener('open',resolve,{once:true});socket.addEventListener('error',()=>reject(Error('source socket failed')),{once:true})});
 const config=await rpc.request('server.getConfig',{});
 const providers=config.providers.map(p=>({instanceId:p.instanceId,kind:p.kind,enabled:p.enabled,installed:p.installed,models:p.models?.map(m=>({slug:m.slug,name:m.name}))}));
 const replay=providers.find(p=>p.instanceId==='devReplay');assert.ok(replay?.installed&&replay.models.some(m=>m.slug==='showcase'),'free replay metadata not available');
 const workspace=home+'/replay-workspace';await mkdir(workspace,{recursive:true});
 const projectId='r1-replay-project';const projects=await request('/api/projects','GET',undefined,token);
 if(!projects.projects.some(p=>p.id===projectId))await request('/api/projects/mutate','POST',JSON.stringify({type:'project.create',commandId:randomUUID(),projectId,title:'R1 C05 Replay',workspaceRoot:workspace}),token);
 const result={environmentId:descriptor.environmentId,base,home,projectId,providers,realProviderUsed:false,agentTurnStarted:false};
 await writeFile(new URL('../docs/evidence/r1/replay-backend-ready.json',import.meta.url),JSON.stringify(result,null,2)+'\n');
 state.replaySource={environmentId:descriptor.environmentId,base,home,port:47847,projectId,sessionPath,processSession:21458};await writeFile(statePath,JSON.stringify(state,null,2)+'\n');
 console.log('PASS isolated source backend has Replay dev provider and project; no turn started');
}finally{rpc.fail('source preparation done');socket.close()}
