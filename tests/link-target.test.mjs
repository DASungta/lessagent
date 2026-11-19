import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
const ts=createRequire(import.meta.url)((process.env.DEVECO_HOME || '/Applications/DevEco-Studio.app/Contents')+'/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const compile=s=>ts.transpileModule(s,{compilerOptions:{module:ts.ModuleKind.ES2022,target:ts.ScriptTarget.ES2022}}).outputText;
const data=s=>'data:text/javascript;base64,'+Buffer.from(s).toString('base64');
const shim="const url={URL:class extends URL {get params(){return this.searchParams}},URLParams:URLSearchParams};";
const pairing=data(compile((await readFile(new URL('../entry/src/main/ets/protocol/Pairing.ets',import.meta.url),'utf8')).replace("import { url } from '@kit.ArkTS';",shim).replace("'./Wire'",JSON.stringify(new URL('../entry/src/main/ets/protocol/Wire.ts',import.meta.url).href))));
const source=(await readFile(new URL('../entry/src/main/ets/protocol/LinkTarget.ets',import.meta.url),'utf8')).replace("import { url } from '@kit.ArkTS';",shim).replace("'./Pairing'",JSON.stringify(pairing));
const {resolveLinkTarget,linkReachableAddresses,initialLinkMachine}=await import(data(compile(source)));
const request={id:'r',threadId:'t',status:'pending',url:'',environmentId:'',hint:'',access:'approval-required'};
const machine={localId:'local',environmentId:'known',label:'My box',urls:['https://known'],connected:true,linked:false};
test('an agent claimed identity cannot make its arbitrary or ambiguous address trusted',()=>{
 assert.equal(resolveLinkTarget({...request,url:'https://evil',environmentId:'known'},[machine],'').kind,'address');
 const target=resolveLinkTarget({...request,url:'https://known/path?token=untrusted',environmentId:'fake'},[machine],'');assert.equal(target.environmentId,'known');assert.deepEqual(target.urls,['https://known']);
 assert.equal(resolveLinkTarget({...request,url:'https://known',environmentId:'known'},[machine,{...machine,environmentId:'another'}],'').kind,'address');
});
test('machine hints and reachable addresses preserve explicit choice and omit loopback routes',()=>{
 assert.equal(initialLinkMachine({...request,hint:'my box'},[machine]),'known');
 assert.equal(initialLinkMachine({...request,hint:'unmatched'},[machine]),'');
 assert.deepEqual(linkReachableAddresses(['http://127.0.0.1:1','http://[::1]:2','https://known/','https://known','ftp://bad']),['https://known']);
 assert.equal(resolveLinkTarget(request,[machine],'another-address').kind,'address');
});
