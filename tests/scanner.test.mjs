import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
const ts=createRequire(import.meta.url)((process.env.DEVECO_HOME || '/Applications/DevEco-Studio.app/Contents')+'/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source=await readFile(new URL('../entry/src/main/ets/services/PairingScanner.ets',import.meta.url),'utf8');
async function setup(fail=false){
 const callbacks=[],events=[],targets=[],errors=[];
 const customScan={init:()=>{events.push('init');if(fail)throw Error('native init')},start:(view,callback)=>{assert.equal(view.surfaceId,'test');events.push('start');callbacks.push(callback)},stop:async()=>events.push('stop'),release:async()=>events.push('release')};
 globalThis.__scanKit={customScan,scanCore:{ScanType:{QR_CODE:11}},pairingTarget:value=>{if(value==='bad')throw Error('invalid');return {base:'https://synthetic.invalid',code:value}}};
 const code=source.replace("import { customScan, scanCore } from '@kit.ScanKit';",'const {customScan,scanCore,pairingTarget}=globalThis.__scanKit;').replace("import { pairingTarget, PairingTarget } from '../protocol/Pairing';",'');
 const compiled=ts.transpileModule(code,{compilerOptions:{module:ts.ModuleKind.ES2022,target:ts.ScriptTarget.ES2022}}).outputText;
 const {PairingScanner}=await import('data:text/javascript;base64,'+Buffer.from(compiled+'\n//'+Math.random()).toString('base64'));
 const scanner=new PairingScanner();const start=()=>scanner.start({width:300,height:220,surfaceId:'test'},v=>targets.push(v),e=>errors.push(e));
 return {scanner,start,callbacks,events,targets,errors,PairingScanner};
}
test('scan fills once, releases camera, and ignores late native callbacks',async()=>{
 const s=await setup();await s.start();const callback=s.callbacks[0];callback(null,[{originalValue:'synthetic'}]);callback(null,[{originalValue:'duplicate'}]);
 await s.scanner.stop();callback(null,[{originalValue:'late'}]);assert.deepEqual(s.targets,[{base:'https://synthetic.invalid',code:'synthetic'}]);
 assert.deepEqual(s.events,['init','start','stop','release']);assert.deepEqual(s.errors,[]);
});
test('cancel prevents stale scan delivery and a new scan owns a new generation',async()=>{
 const s=await setup();await s.start();await s.scanner.stop();await s.start();
 s.callbacks[0](null,[{originalValue:'stale'}]);s.callbacks[1](null,[{originalValue:'new'}]);await s.scanner.stop();assert.equal(s.targets.length,1);assert.equal(s.targets[0].code,'new');
});
test('invalid payload and native init failures surface errors without connecting',async()=>{
 const s=await setup();await s.start();s.callbacks[0](null,[{originalValue:'bad'}]);await s.scanner.stop();assert.equal(s.targets.length,0);assert.equal(s.errors.length,1);
 const f=await setup(true);await f.start();await f.scanner.stop();assert.equal(f.targets.length,0);assert.equal(f.errors.length,1);assert.deepEqual(f.events,['init']);
});
test('camera denial distinguishes an available retry from settings recovery without connecting',async()=>{
 const source=await readFile(new URL('../entry/src/main/ets/components/PairingScanCard.ets',import.meta.url),'utf8');
 const method=source.slice(source.indexOf('  private async permission('),source.indexOf('  build()'));
 const code=ts.transpileModule('return class { '+method+' }',{compilerOptions:{target:ts.ScriptTarget.ES2022}}).outputText;
 let response={authResults:[-1],dialogShownResults:[true]};
 const manager={requestPermissionsFromUser:async()=>response,requestPermissionOnSetting:async()=>[0]};
 const Page=new Function('abilityAccessCtrl',code)({createAtManager:()=>manager,GrantStatus:{PERMISSION_GRANTED:0}});
 const page=new Page();page.context=()=>({});await page.permission();assert.equal(page.permitted,false);assert.equal(page.settingsNeeded,false);
 response={authResults:[-1],dialogShownResults:[false]};await page.permission();assert.equal(page.settingsNeeded,true);
 await page.permission(true);assert.equal(page.permitted,true);assert.equal(page.settingsNeeded,false);assert.equal(page.complete,false);
});
test('a replacement scan view invalidates old callbacks and cannot be stopped by old-view cleanup',async()=>{
 const s=await setup();await s.start();const newer=new s.PairingScanner();const values=[];
 await newer.start({width:300,height:220,surfaceId:'test'},v=>values.push(v),()=>{});
 s.callbacks[0](null,[{originalValue:'stale-old-view'}]);assert.equal(s.targets.length,0);
 await s.scanner.stop();s.callbacks[1](null,[{originalValue:'new-view'}]);await newer.stop();
 assert.equal(values.length,1);assert.equal(values[0].code,'new-view');assert.equal(s.events.filter(v=>v==='release').length,2);
});
