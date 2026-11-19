// Synthetic negative cases only. Never handles real pairing grants or modifies T3 services.
import http from 'node:http';
import https from 'node:https';
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,renameSync,chmodSync,existsSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {X509Certificate} from 'node:crypto';
import {join} from 'node:path';
const state=JSON.parse(readFileSync(new URL('../docs/evidence/r1/lab-state.json',import.meta.url),'utf8'));
assert.ok(state.labRoot.includes('t3-harmony-r1-real-'));
const root=state.labRoot,metricsPath=join(root,'network-negative-metrics.json');
const keyPath=join(root,'negative-tls-private.key'),certPath=join(root,'negative-tls.cert');
if(!existsSync(keyPath)){
 const cfg=join(root,'negative-tls-config.cnf');
 writeFileSync(cfg,'[req]\ndistinguished_name=dn\nx509_extensions=v3\nprompt=no\n[dn]\nCN=r1-negative.invalid\n[v3]\nsubjectAltName=IP:192.168.10.75,DNS:r1-negative.invalid\n',{mode:0o600});
 const generated=spawnSync('openssl',['req','-x509','-newkey','rsa:2048','-nodes','-keyout',keyPath,'-out',certPath,'-days','1','-config',cfg],{stdio:'ignore'});
 assert.equal(generated.status,0,'private test certificate generation failed');chmodSync(keyPath,0o600);
}
const certificate=new X509Certificate(readFileSync(certPath));
const stats={pid:process.pid,startedAt:Date.now(),selfCheck:false,redirect:{descriptor:0,oauth:0},capture:{requests:0},protocol:{descriptor:0,oauth:0},tls:{httpRequests:0,errors:[]},certificate:{validFrom:certificate.validFrom,validTo:certificate.validTo,fingerprint256:certificate.fingerprint256,subjectAltName:certificate.subjectAltName}};
const persist=()=>{writeFileSync(metricsPath+'.tmp',JSON.stringify(stats,null,2),{mode:0o600});renameSync(metricsPath+'.tmp',metricsPath)};
const descriptor=version=>({environmentId:'r1-synthetic-negative',label:'R1 negative fixture',serverVersion:'fixture',orchestrationProtocolVersion:version});
const reply=(res,status,body)=>{res.writeHead(status,{'Content-Type':'application/json'});res.end(JSON.stringify(body))};
const servers=[];
async function listen(server,port){servers.push(server);await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(port,'0.0.0.0',resolve)})}
try{
 await listen(http.createServer((req,res)=>{
  const own=req.headers['x-r1-selfcheck']==='1';
  if(req.url==='/.well-known/t3/environment'){if(!own)stats.redirect.descriptor++;reply(res,200,descriptor(2))}
  else if(req.url==='/oauth/token'){if(!own)stats.redirect.oauth++;req.resume();res.writeHead(302,{Location:'http://192.168.10.75:47842/should-never-receive'});res.end()}
  else reply(res,404,{});
  persist();
 }),47841);
 await listen(http.createServer((req,res)=>{stats.capture.requests++;req.resume();reply(res,401,{});persist()}),47842);
 const tls=https.createServer({key:readFileSync(keyPath),cert:readFileSync(certPath)},(req,res)=>{stats.tls.httpRequests++;req.resume();reply(res,200,descriptor(2));persist()});
 tls.on('tlsClientError',error=>{stats.tls.errors.push(error.code||'TLS_CLIENT_ERROR');persist()});await listen(tls,47843);
 await listen(http.createServer((req,res)=>{
  const own=req.headers['x-r1-selfcheck']==='1';
  if(req.url==='/.well-known/t3/environment'){if(!own)stats.protocol.descriptor++;reply(res,200,descriptor(3))}
  else {if(req.url==='/oauth/token'&&!own)stats.protocol.oauth++;req.resume();reply(res,400,{})}
  persist();
 }),47845);
 const headers={'x-r1-selfcheck':'1'};
 assert.equal((await fetch('http://127.0.0.1:47841/.well-known/t3/environment',{headers})).status,200);
 const redirect=await fetch('http://127.0.0.1:47841/oauth/token',{method:'POST',body:'SYNTHETIC_ONLY',redirect:'manual',headers});assert.equal(redirect.status,302);
 assert.equal((await (await fetch('http://127.0.0.1:47845/.well-known/t3/environment',{headers})).json()).orchestrationProtocolVersion,3);
 await new Promise((resolve,reject)=>{https.get('https://127.0.0.1:47843',()=>reject(Error('unexpected test certificate trust'))).on('error',error=>{if(!['DEPTH_ZERO_SELF_SIGNED_CERT','ERR_TLS_CERT_ALTNAME_INVALID'].includes(error.code))return reject(Error('TLS fixture selfcheck failed'));resolve()})});
 stats.selfCheck=true;persist();console.log('READY synthetic redirect/TLS/protocol negative fixtures; host selfcheck passed');
 process.on('SIGTERM',()=>{for(const server of servers){server.close();server.closeAllConnections?.()}persist();process.exit(0)});
}catch(error){for(const server of servers){server.close();server.closeAllConnections?.()}throw error}
