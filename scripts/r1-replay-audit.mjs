// Read back only the controlled free Replay request; never export its session credential.
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
const state=JSON.parse(await readFile(new URL('../docs/evidence/r1/lab-state.json',import.meta.url),'utf8'));
const session=JSON.parse(await readFile(state.labRoot+'/replay-session-private.json','utf8'));
assert.equal(session.base,'http://127.0.0.1:47847');
const threadId='r1-c05-replay-source-5';
const response=await fetch(session.base+'/api/orchestration/threads/'+threadId,{redirect:'error',headers:{Authorization:'Bearer '+session.token,'x-t3-orchestration-protocol':'2'}});
assert.equal(response.status,200);const projection=(await response.json()).projection;
assert.equal(projection.thread.modelSelection.instanceId,'r1ReplayLink');
assert.equal(projection.thread.modelSelection.model,'question');
const pending=projection.turnItems.filter(item=>item.type==='link_request'&&item.linkStatus==='pending');
assert.equal(pending.length,1);const item=pending[0];
assert.equal(item.threadId,threadId);assert.equal(item.hint,'R1 isolated B');assert.equal(item.requestedAccess,'read-only');
assert.equal(item.url,undefined);assert.equal(item.environmentId,undefined);
const card={id:item.id,threadId:item.threadId,type:item.type,reason:item.reason,linkStatus:item.linkStatus,hint:item.hint,requestedAccess:item.requestedAccess};
const fixture={upstream:'ad1b1365999c92c3fc7a054e7f3af84623f74fee',environmentId:session.environmentId,threadId,provider:'r1ReplayLink',scenario:'question',paidModelsUsed:false,source:'real MCP request through isolated source backend',card,runStatuses:projection.runs.map(run=>run.status),nativeVerified:false};
await writeFile(new URL('../docs/evidence/r1/replay-link-request.json',import.meta.url),JSON.stringify(fixture,null,2)+'\n');
console.log('PASS real pending link request read back; no pairing credential in exported fixture');
