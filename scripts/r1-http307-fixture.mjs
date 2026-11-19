// 307 preserves POST bodies; the native test must stop before the capture endpoint.
import http from 'node:http';
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,renameSync} from 'node:fs';
import {join} from 'node:path';
const state=JSON.parse(readFileSync(new URL('../docs/evidence/r1/lab-state.json',import.meta.url),'utf8'));
assert.ok(state.labRoot.includes('t3-harmony-r1-real-'));
const path=join(state.labRoot,'http307-metrics.json'),metrics={pid:process.pid,descriptor:0,oauth:0,selfCheck:false};
function save(){writeFileSync(path+'.tmp',JSON.stringify(metrics),{mode:0o600});renameSync(path+'.tmp',path)}
const server=http.createServer((req,res)=>{
 const native=req.headers['x-r1-selfcheck']!=='1';
 if(req.url==='/.well-known/t3/environment'){
  if(native)metrics.descriptor++;res.writeHead(200,{'Content-Type':'application/json'});
  res.end(JSON.stringify({environmentId:'r1-http307-fixture',label:'Synthetic 307 fixture',serverVersion:'fixture',orchestrationProtocolVersion:2}));
 }else if(req.url==='/oauth/token'){
  if(native)metrics.oauth++;req.resume();res.writeHead(307,{Location:'http://192.168.10.75:47842/should-never-receive'});res.end();
 }else{req.resume();res.writeHead(404);res.end()}
 save();
});
await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(47846,'0.0.0.0',resolve)});
const response=await fetch('http://127.0.0.1:47846/oauth/token',{method:'POST',body:'SYNTHETIC_ONLY',headers:{'x-r1-selfcheck':'1'},redirect:'manual'});
assert.equal(response.status,307);metrics.selfCheck=true;save();console.log('READY synthetic 307 fixture; manual-redirect selfcheck passed');
process.on('SIGTERM',()=>{server.close();server.closeAllConnections?.();save();process.exit(0)});
