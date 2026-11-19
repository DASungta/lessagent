// Test provider: preserve the upstream free Replay ACP stream, then request one real MCP card.
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {writeFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {resolve} from 'node:path';
const original='/tmp/t3code-harmony-upstream/apps/server/scripts/dev-replay-agent.ts';
function decodeReply(body){
 try{return JSON.parse(body)}catch{}
 const frames=body.split(/\r?\n/).filter(line=>line.startsWith('data:')).map(line=>JSON.parse(line.slice(5).trim()));
 const reply=frames.find(frame=>frame.id!==undefined);if(!reply)throw Error('MCP response missing');return reply;
}
function allowOrigin(value){const target=new URL(value);return target.protocol==='http:'&&target.port==='47847'&&['127.0.0.1','localhost','0.0.0.0','192.168.10.75'].includes(target.hostname)}
if(process.argv.includes('--selfcheck')){
 assert.equal(decodeReply('data: {"jsonrpc":"2.0","id":1,"result":{}}\n\n').id,1);assert.equal(decodeReply('{"id":2,"result":{}}').id,2);
 assert.equal(allowOrigin('http://127.0.0.1:47847/mcp'),true);assert.equal(allowOrigin('http://127.0.0.1:3773/mcp'),false);assert.equal(allowOrigin('https://evil.invalid:47847/mcp'),false);
 console.log('PASS replay bridge response parsing and owned-origin boundaries');process.exit(0);
}
const evidence=resolve(process.cwd(),'.r1-mcp-fixture.json');let servers=[],initializeId,requested=false;
function record(value){writeFileSync(evidence,JSON.stringify(value),{mode:0o600})}
async function requestCard(){
 const injected=process.env.T3_ACP_MCP_ENDPOINT&&process.env.T3_ACP_MCP_AUTHORIZATION?{type:'http',url:process.env.T3_ACP_MCP_ENDPOINT,headers:[{name:'Authorization',value:process.env.T3_ACP_MCP_AUTHORIZATION}]}:undefined;
 const server=servers.find(candidate=>candidate.type==='http'&&typeof candidate.url==='string')||injected;
 if(!server){record({stage:'missing-http-mcp',serverTypes:servers.map(s=>s.type||'stdio')});return}
 const origin=new URL(server.url).origin;if(!allowOrigin(server.url)){record({stage:'unapproved-mcp-origin',origin});return}
 let sessionId;let id=0;let protocolVersion;const headers=Object.fromEntries((server.headers||[]).map(header=>[header.name,header.value]));
 async function post(method,params,notification=false){
  const body={jsonrpc:'2.0',...(notification?{}:{id:++id}),method,...(params?{params}:{})};
  record({stage:'mcp-post',method,paidModelsUsed:false});
  const response=await fetch(server.url,{method:'POST',redirect:'error',headers:{...headers,Accept:'application/json, text/event-stream','Content-Type':'application/json',...(protocolVersion?{'MCP-Protocol-Version':protocolVersion}:{}),...(sessionId?{'Mcp-Session-Id':sessionId}:{})},body:JSON.stringify(body)});
  if(!response.ok){record({stage:'mcp-http-failed',method,status:response.status});return Promise.reject(Error('MCP HTTP failure'))}sessionId=response.headers.get('mcp-session-id')||sessionId;
  const text=await response.text();if(notification)return undefined;const result=decodeReply(text);if(result.error){record({stage:'mcp-rpc-failed',method,code:result.error.code});throw Error('MCP RPC failure')}protocolVersion=result.result?.protocolVersion||protocolVersion;return result.result;
 }
 await post('initialize',{protocolVersion:'2025-06-18',capabilities:{},clientInfo:{name:'r1-replay-link-fixture',version:'1'}});
 await post('notifications/initialized',undefined,true);
 const list=await post('tools/list',{});const tool=list.tools.find(tool=>/(^|_)environment_link$/.test(tool.name));
 if(!tool){record({stage:'missing-environment-link-tool',origin,toolNames:list.tools.map(t=>t.name)});return}
 const result=await post('tools/call',{name:tool.name,arguments:{hint:'R1 isolated B',reason:'R1 controlled link-request fixture; no real model.',requestedAccess:'read-only',clientRequestId:'r1-link-fixture-once'}});
 record({stage:result.isError?'tool-rejected':'card-requested',origin,paidModelsUsed:false});
}
const child=spawn(process.execPath,[original],{stdio:['pipe','pipe','inherit']});
createInterface({input:process.stdin}).on('line',line=>{
 try{const message=JSON.parse(line);if(message.method==='initialize')initializeId=message.id;if(['session/new','session/load','session/resume'].includes(message.method))servers=message.params?.mcpServers||[]}catch{}
 child.stdin.write(line+'\n');
});
createInterface({input:child.stdout}).on('line',line=>{
 try{
  const message=JSON.parse(line);
  if(message.id===initializeId&&message.result?.agentCapabilities){message.result.agentCapabilities.mcpCapabilities={http:true};line=JSON.stringify(message)}
  if(!requested&&['session/request_permission','elicitation/create'].includes(message.method)){
   requested=true;record({stage:'requesting-card',paidModelsUsed:false});
   void requestCard().catch(()=>{process.stderr.write('R1 MCP fixture failed; inspect safe phase evidence\n')}).finally(()=>process.stdout.write(line+'\n'));
  }else{process.stdout.write(line+'\n')}
 }catch{process.stdout.write(line+'\n')}
});
process.stdin.on('end',()=>child.stdin.end());
process.on('SIGTERM',()=>{child.kill('SIGTERM')});
child.on('exit',code=>process.exit(code??0));
child.stdin.on('error',()=>{});
