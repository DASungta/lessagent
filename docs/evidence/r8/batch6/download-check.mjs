// Isolated read-only API validation; credentials stay in memory and the test session is revoked.
import assert from 'node:assert/strict';
import {readFile,writeFile,realpath} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {createHash,randomUUID} from 'node:crypto';
import {RpcClient,bootstrapForm,socketUrl} from '../../../../entry/src/main/ets/protocol/Wire.ts';
import {filesUrl} from '../../../../tests/load-core.mjs';
const {workspaceAssetResource}=await import(filesUrl);
const state=JSON.parse(await readFile(new URL('../../r5/service-round2.json',import.meta.url),'utf8'));
const baseDir=state.server.baseDir;assert.equal(baseDir,'/tmp/t3-r5-accept-00fcea');assert.equal(state.server.listen,'127.0.0.1:47895');
assert.ok((await realpath(baseDir)).startsWith('/private/tmp/t3-r5-accept-'));
const base='http://127.0.0.1:47895', label='harmony-download-check-'+randomUUID();
const cli=(args)=>{const r=spawnSync('t3',['auth',...args,'--base-dir',baseDir],{encoding:'utf8',env:{...process.env,T3CODE_HOME:baseDir}});assert.equal(r.status,0,'isolated auth command failed');return r.stdout};
const descriptor=await (await fetch(base+'/.well-known/t3/environment')).json();
assert.equal(descriptor.environmentId,(await readFile(baseDir+'/userdata/environment-id','utf8')).trim());
const grant=JSON.parse(cli(['pairing','create','--scope','orchestration:read','--scope','filesystem:read','--ttl','5m','--label',label,'--json']));
let sessionId,rpc,socket,result;
try {
 const body=bootstrapForm(grant.credential).replace('&client_label=T3%20Harmony','&client_label='+encodeURIComponent(label));
 const authResponse=await fetch(base+'/oauth/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body,redirect:'error'});assert.equal(authResponse.status,200);
 const auth=await authResponse.json();assert.equal(auth.token_type,'Bearer');
 const sessions=JSON.parse(cli(['session','list','--json']));const session=sessions.find(x=>x.client?.label===label);assert.ok(session,'own test session missing');sessionId=session.sessionId;
 const ticketResponse=await fetch(base+'/api/auth/websocket-ticket/rpc',{method:'POST',headers:{Authorization:'Bearer '+auth.access_token},redirect:'error'});assert.equal(ticketResponse.status,200);const ticket=await ticketResponse.json();
 socket=new WebSocket(socketUrl(base,ticket.ticket));rpc=new RpcClient({async send(frame){socket.send(frame)}});socket.addEventListener('message',event=>rpc.receive(event.data));
 await new Promise((resolve,reject)=>{socket.addEventListener('open',resolve,{once:true});socket.addEventListener('error',()=>reject(Error('isolated socket failed')),{once:true})});
 const query=spawnSync('sqlite3',[baseDir+'/userdata/statev2.sqlite',"SELECT thread_id FROM orchestration_v2_projection_threads WHERE project_id='"+state.project.id+"' LIMIT 1;"],{encoding:'utf8'});assert.equal(query.status,0);const threadId=query.stdout.trim();assert.ok(threadId);
 const resource=workspaceAssetResource(threadId,state.project.workspaceRoot,'README.md',true);
 const asset=await rpc.request('assets.createUrl',{resource});assert.ok(asset.relativeUrl.startsWith('/'));assert.ok(asset.expiresAt>Date.now());
 const response=await fetch(base+asset.relativeUrl,{redirect:'error'});assert.equal(response.status,200);const bytes=Buffer.from(await response.arrayBuffer());const expected=await readFile(state.project.workspaceRoot+'/README.md');assert.deepEqual(bytes,expected);
 assert.match(response.headers.get('content-disposition')||'',/^attachment/);
 result={status:response.status,bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex'),resourceTag:resource._tag,attachmentDisposition:true,exactBytes:true};
} finally {
 if(rpc)rpc.fail('verification finished');if(socket)socket.close();
 if(sessionId){cli(['session','revoke',sessionId]);const active=JSON.parse(cli(['session','list','--json']));assert.ok(!active.some(x=>x.sessionId===sessionId),'test session still active');if(result)result.sessionRevoked=true;}
}
assert.ok(result?.sessionRevoked);await writeFile(new URL('download-readback.json',import.meta.url),JSON.stringify(result,null,2)+'\n');console.log('PASS isolated file download exact bytes; temporary session revoked');
