import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {compile,coreUrl} from './load-core.mjs';
const {inputAnswers}=await import(coreUrl);
const source=await readFile(new URL('../entry/src/main/ets/components/RequestCard.ets',import.meta.url),'utf8');
const helper=source.slice(source.indexOf('  private finalAnswers('),source.indexOf('  private async submit('));
const method=source.slice(source.indexOf('  private async submit('),source.indexOf('  build()'));
const Card=new Function('inputAnswers',compile('return class { '+helper+method+' }'))(inputAnswers);
test('required input validation preserves other choices and permits correcting the response',async()=>{
 for(const missing of ['', '   ', [], ['  ']]){
  let calls=0;
  const card=Object.assign(new Card(),{card:{kind:'input',requestId:'request',questions:[{id:'first',required:true},{id:'second',required:true}]},secretValue:'',answers:new Map([['first','keep me'],['second',missing]]),customAnswers:new Map(),busy:false,submitted:false,connection:{async respond(){calls++}}});
  await card.submit('');assert.equal(calls,0);assert.equal(card.answers.get('first'),'keep me');assert.equal(card.submitted,false);assert.equal(card.busy,false);
  card.answers.set('second','corrected');await card.submit('');assert.equal(calls,1);assert.equal(card.submitted,true);assert.equal(card.answers.size,0);
 }
});
test('a custom answer wins over multi-select values and is submitted as text',async()=>{
 let submitted;
 const card=Object.assign(new Card(),{card:{kind:'input',requestId:'request',questions:[{id:'q',required:true,multi:true,options:['A'],values:['a']}]},secretValue:'',answers:new Map([['q',['a']]]),customAnswers:new Map([['q','written answer']]),busy:false,submitted:false,connection:{async respond(_request,_decision,answers){submitted=answers;}}});
 await card.submit('');
 assert.deepEqual(submitted,{q:'written answer'});
});
