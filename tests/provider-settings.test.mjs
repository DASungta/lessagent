import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { compile, data } from './load-core.mjs';
const source=(await readFile(new URL('../entry/src/main/ets/protocol/ProviderSettings.ts',import.meta.url),'utf8'))
  .replace("'./Wire'",JSON.stringify(new URL('../entry/src/main/ets/protocol/Wire.ts',import.meta.url).href));
const api=await import(data(compile(source)));
const provider={instanceId:'p',driver:'codex',displayName:'Codex',enabled:true,installed:true,status:'ready',auth:{status:'unknown'},setup:{canAuthenticate:true},models:[{slug:'m',name:'Model'}]};
const config={environment:{environmentId:'e'},providers:[provider]};
const state={instanceId:'p',phase:'waiting',flowId:'f',expiresAt:null,authorizationUrl:null,interaction:{type:'browser',id:'i',url:'https://auth.example/login',requiresConsent:true}};
test('provider catalog is environment scoped and never labels unknown auth as signed in',()=>{
  const [row]=api.providerCatalog(config,'e');
  assert.equal(row.models[0].id,'m');assert.equal(api.providerStatus(row),'就绪 · 登录状态未知');
  assert.equal(api.providerStatus({...row,authStatus:'authenticated'}),'已登录');
  const locked=api.providerCatalog({...config,managedPolicy:{limits:{providers:{allowedDrivers:['other']}}}},'e')[0];
  assert.equal(api.providerStatus(locked),'组织策略不可用');
  assert.throws(()=>api.providerCatalog(config,'other'));
  assert.throws(()=>api.providerCatalog({...config,providers:[provider,provider]},'e'));
  assert.throws(()=>api.providerCatalog({...config,providers:[{...provider,instanceId:'x'.repeat(257)}]},'e'));
});
test('authentication challenges retain flow/interaction and enforce identity, phase and safe URLs',()=>{
  const parsed=api.providerAuthView(state,'p');assert.equal(parsed.requiresConsent,true);assert.equal(parsed.flowId,'f');assert.equal(parsed.interactionId,'i');assert.equal(api.providerAuthActive(parsed),true);
  assert.throws(()=>api.providerAuthView(state,'other'));
  assert.throws(()=>api.providerAuthView({...state,phase:'unknown'},'p'));
  assert.throws(()=>api.providerAuthView({...state,flowId:'f'.repeat(257)},'p'));
  for(const url of ['javascript:alert(1)','file:///secret','https://name:password@example.org','https://example.org\\@evil.test','https://example.org\nsecret']) assert.throws(()=>api.providerSignInUrl(url));
  const device=api.providerAuthView({...state,interaction:{type:'deviceCode',id:'i',url:'https://auth.example',userCode:'ABC-123'}},'p');assert.equal(device.code,'ABC-123');
  const terminal=api.providerAuthView({...state,authorizationUrl:'https://auth.example',interaction:{type:'terminal',id:'i',output:'secret'}},'p');assert.equal(terminal.url,'');assert.equal(terminal.code,'');assert.ok(!JSON.stringify(terminal).includes('secret'));
});
test('cancelled, failed, succeeded and expired flows are not active login',()=>{
  for(const phase of ['cancelled','failed','succeeded']){
    const parsed=api.providerAuthView({...state,phase},'p');assert.equal(api.providerAuthActive(parsed),false);
  }
  const expired=api.providerAuthView({...state,expiresAt:'2020-01-01T00:00:00Z'},'p');assert.equal(api.providerAuthActive(expired),false);assert.match(api.providerAuthLabel(expired),/过期/);
  assert.throws(()=>api.providerAuthView({...state,expiresAt:'bad'},'p'));
});
