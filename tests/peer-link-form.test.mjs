import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
const ts=createRequire(import.meta.url)((process.env.DEVECO_HOME || '/Applications/DevEco-Studio.app/Contents')+'/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source=await readFile(new URL('../entry/src/main/ets/components/PeerLinkForm.ets',import.meta.url),'utf8');
const method=source.slice(source.indexOf('  private async submit()'),source.indexOf('  build()'));
const code=ts.transpileModule('return class { '+method+' }',{compilerOptions:{target:ts.ScriptTarget.ES2022}}).outputText;
function page(connection,registry={clients:new Map()}){
 const Form=new Function('environments','linkOrigin',code)(registry,value=>new URL(value).origin);
 const form=new Form(),busy=[];let closed=0;
 Object.assign(form,{connection,busy:false,canMint:false,error:'',code:'SYNTHETIC_CODE',access:'read-only',address:'https://peer/path',request:{id:'request'},failedMint:[],canSubmit:()=>true,target:()=>({kind:'address',localId:'',urls:[]}),needsAddress:()=>true,useExisting:()=>false,onBusy:value=>busy.push(value),onClose:()=>closed++});
 return {form,busy,closed:()=>closed};
}
test('double submit stays single-flight until the actual answer completes',async()=>{
 let complete;const gate=new Promise(resolve=>complete=resolve);let calls=0;
 const p=page({async answerLinkRequest(id,answer){calls++;assert.equal(id,'request');assert.deepEqual(answer.urls,['https://peer']);await gate}});
 const first=p.form.submit();await p.form.submit();assert.equal(calls,1);assert.equal(p.form.busy,true);
 complete();await first;assert.deepEqual(p.busy,[true,false]);assert.equal(p.closed(),1);assert.equal(p.form.code,'');
});
test('transport errors cannot echo a pairing code into the user-facing error',async()=>{
 const p=page({async answerLinkRequest(){throw Error('transport echoed SYNTHETIC_CODE')}});await p.form.submit();
 assert.ok(!p.form.error.includes('SYNTHETIC_CODE'));assert.equal(p.closed(),0);assert.equal(p.form.busy,false);
});
test('failed automatic mint requires manual input instead of silently minting or answering again',async()=>{
 let mints=0,answers=0;const registry={clients:new Map([['target',{async mintPeerPairingCode(){mints++;throw Error('private internal cause')}}]])};
 const p=page({async answerLinkRequest(){answers++}},registry);Object.assign(p.form,{canMint:true,target:()=>({kind:'machine',localId:'target',environmentId:'target-env',label:'Peer',urls:['https://peer']}),needsAddress:()=>false});
 await p.form.submit();assert.equal(mints,1);assert.equal(answers,0);assert.equal(p.form.canMint,false);assert.deepEqual(p.form.failedMint,['target']);assert.ok(!p.form.error.includes('private internal cause'));
});
test('offline, unknown-result and access-denied sources cannot mint or submit from the sheet',()=>{
 const method=source.slice(source.indexOf('  private canSubmit()'),source.indexOf('  private needsAddress()'));
 const code=ts.transpileModule('return class { '+method+' }',{compilerOptions:{target:ts.ScriptTarget.ES2022}}).outputText;
 const Form=new Function(code)();const form=new Form();let permitted=true;
 Object.assign(form,{connection:{ready:true,mutationPending:false,canManagePeerAccess:()=>permitted},target:()=>({kind:'machine'}),useExisting:()=>false,needsAddress:()=>false,canMint:true,code:''});
 assert.equal(form.canSubmit(),true);form.connection.mutationPending=true;assert.equal(form.canSubmit(),false);form.connection.mutationPending=false;form.connection.ready=false;assert.equal(form.canSubmit(),false);form.connection.ready=true;permitted=false;assert.equal(form.canSubmit(),false);
});
