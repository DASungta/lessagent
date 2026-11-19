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
const base='http://127.0.0.1:47895', label='harmony-preview-measure-'+randomUUID();
const cli=(args)=>{const r=spawnSync('t3',['auth',...args,'--base-dir',baseDir],{encoding:'utf8',env:{...process.env,T3CODE_HOME:baseDir}});assert.equal(r.status,0,'isolated auth command failed');return r.stdout};
const descriptor=await (await fetch(base+'/.well-known/t3/environment')).json();
assert.equal(descriptor.environmentId,(await readFile(baseDir+'/userdata/environment-id','utf8')).trim());
const grant=JSON.parse(cli(['pairing','create','--scope','orchestration:read','--scope','preview:operate','--ttl','5m','--label',label,'--json']));
let sessionId,rpc,socket,result,tabId,threadId,media;
try {
 const body=bootstrapForm(grant.credential).replace('&client_label=T3%20Harmony','&client_label='+encodeURIComponent(label));
 const authResponse=await fetch(base+'/oauth/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body,redirect:'error'});assert.equal(authResponse.status,200);
 const auth=await authResponse.json();assert.equal(auth.token_type,'Bearer');
 const sessions=JSON.parse(cli(['session','list','--json']));const session=sessions.find(x=>x.client?.label===label);assert.ok(session,'own test session missing');sessionId=session.sessionId;
 const ticketResponse=await fetch(base+'/api/auth/websocket-ticket/rpc',{method:'POST',headers:{Authorization:'Bearer '+auth.access_token},redirect:'error'});assert.equal(ticketResponse.status,200);const ticket=await ticketResponse.json();
 socket=new WebSocket(socketUrl(base,ticket.ticket));rpc=new RpcClient({async send(frame){socket.send(frame)}});socket.addEventListener('message',event=>rpc.receive(event.data));
 await new Promise((resolve,reject)=>{socket.addEventListener('open',resolve,{once:true});socket.addEventListener('error',()=>reject(Error('isolated socket failed')),{once:true})});
 const query=spawnSync('sqlite3',[baseDir+'/userdata/statev2.sqlite',"SELECT thread_id FROM orchestration_v2_projection_threads WHERE project_id='"+state.project.id+"' LIMIT 1;"],{encoding:'utf8'});assert.equal(query.status,0);threadId=query.stdout.trim();assert.ok(threadId);
 const opened=await rpc.request('preview.open',{threadId,url:'http://127.0.0.1:47897/viewport-fixture.html',runtime:'server',viewport:{_tag:'freeform',width:768,height:1024}});tabId=opened.tabId;assert.ok(tabId);
 function size(bytes){const b=Buffer.from(bytes);assert.equal(b.readUInt16BE(0),0xffd8);let i=2;while(i+8<b.length){if(b[i++]!==255)continue;let marker=b[i++];while(marker===255)marker=b[i++];if(marker===0xd9||marker===0xda)break;const length=b.readUInt16BE(i);if([0xc0,0xc1,0xc2].includes(marker))return {width:b.readUInt16BE(i+5),height:b.readUInt16BE(i+3),bytes:b.length};if(length<2)break;i+=length;}throw Error('JPEG size missing');}
 const rows=[];
 for(const viewport of [{width:768,height:1024},{width:1280,height:800}]){
  await rpc.request('preview.resize',{threadId,tabId,viewport:{_tag:'freeform',...viewport}});
  const mt=await (await fetch(base+'/api/auth/websocket-ticket/media',{method:'POST',headers:{Authorization:'Bearer '+auth.access_token}})).json();
  const target=base.replace(/^http/,'ws')+'/api/preview-stream/ws?threadId='+encodeURIComponent(threadId)+'&tabId='+encodeURIComponent(tabId)+'&maxWidth=720&maxHeight=1280&wsTicket='+encodeURIComponent(mt.ticket);
  const frames=[];const stream=media=new WebSocket(target);media.binaryType='arraybuffer';
  media.addEventListener('message',e=>{if(typeof e.data!=='string'){frames.push(size(e.data));if(stream.readyState===1)stream.send('{"type":"ack"}')}});
  await new Promise((resolve,reject)=>{media.addEventListener('open',resolve,{once:true});media.addEventListener('error',()=>reject(Error('media failed')),{once:true})});
  await new Promise(r=>setTimeout(r,5000));media.close();media=undefined;assert.ok(frames.length);rows.push({viewport,frames});
 }
 result={measurements:rows};

} finally {
 if(media)media.close();
 if(tabId&&rpc){await rpc.request('preview.close',{threadId,tabId});if(result)result.tabClosed=true;}
 if(rpc)rpc.fail('verification finished');if(socket)socket.close();
 if(sessionId){cli(['session','revoke',sessionId]);const active=JSON.parse(cli(['session','list','--json']));assert.ok(!active.some(x=>x.sessionId===sessionId),'test session still active');if(result)result.sessionRevoked=true;}
}
assert.ok(result?.sessionRevoked);await writeFile(new URL('source-frame-readback.json',import.meta.url),JSON.stringify(result,null,2)+'\n');console.log('PASS preview frame metadata measured; tab closed and session revoked');
