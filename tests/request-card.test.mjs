import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {compile,coreUrl} from './load-core.mjs';
const {inputAnswers,secretRequestErrorMessage,secretValuesFromMap}=await import(coreUrl);
const source=await readFile(new URL('../entry/src/main/ets/components/RequestCard.ets',import.meta.url),'utf8');
const clearMethod=source.slice(source.indexOf('  private clearPrivateInput('),source.indexOf('  @Prop card:'));
const helper=source.slice(source.indexOf('  private finalAnswers('),source.indexOf('  private async submit('));
const method=source.slice(source.indexOf('  private async submit('),source.indexOf('  build()'));
const Card=new Function('inputAnswers','secretRequestErrorMessage','secretValuesFromMap',
  compile('return class { '+clearMethod+helper+method+' }'))(inputAnswers,secretRequestErrorMessage,secretValuesFromMap);
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
test('input question options render as multi-line selectable cards without single-line Button truncation',()=>{
 assert.ok(source.includes('questionDisplays(this.card.questions)'));
 assert.ok(source.includes('ForEach(display.question.optionItems'));
 assert.ok(source.includes('Text(opt.label)'));
 assert.ok(!source.includes('ForEach(q.options'));
 assert.ok(!source.includes("Button((this.selected(q"));
});
test('multi-field secret cards require all fields, submit values, forbid reference, clear on background, and show plural file note',async()=>{
 const fields=[
  {name:'email',label:'Email',placeholder:'name@example.com',secret:false},
  {name:'password',label:'Password',placeholder:'',secret:true}
 ];
 let sentValues;
 let declined=false;
 let refCalls=0;
 const card=Object.assign(new Card(),{
  foreground:true,
  card:{id:'sec-1',kind:'secret',secretDelivery:'file',secretReference:false,secretFields:fields,questions:[]},
  secretValue:'',secretValues:new Map([['email',' a@example.com ']]),secretVisible:false,fieldVisible:new Map([['password',true]]),
  answers:new Map(),customAnswers:new Map(),busy:false,submitted:false,referenceMode:true,referenceProvider:'vault',referencePath:'op://x',
  connection:{
   async secretValues(_id,values){sentValues=values;},
   async secret(_id,_val,decline){declined=decline;},
   async secretReference(){refCalls++;}
  }
 });
 assert.equal(card.allSecretFieldsFilled(),false);
 assert.match(card.secretDeliveryNote(),/保存在私密文件中/);
 card.setSecretFieldText('password',' top-secret ');
 assert.equal(card.allSecretFieldsFilled(),true);
 await card.submit('');
 assert.equal(refCalls,0);
 assert.deepEqual(sentValues,{email:' a@example.com ',password:' top-secret '});
 assert.equal(card.submitted,true);
 assert.equal(card.secretValues.size,0);
 assert.equal(card.fieldVisible.size,0);

 // Backgrounding clears both single and multi-field values and resets password visibility
 card.submitted=false;
 card.secretValue='single';
 card.secretVisible=true;
 card.setSecretFieldText('email','x@y.com');
 card.setFieldVisible('password',true);
 card.foreground=false;
 card.clearPrivateInput();
 assert.equal(card.secretValue,'');
 assert.equal(card.secretVisible,false);
 assert.equal(card.secretValues.size,0);
 assert.equal(card.fieldVisible.size,0);

 // Decline works even when referenceMode was toggled
 await card.submit('decline');
 assert.equal(declined,true);

 // fields_mismatch failure maps to the expected Chinese message
 const failing=Object.assign(new Card(),{
  card:{id:'sec-2',kind:'secret',secretDelivery:'',secretReference:false,secretFields:fields,questions:[]},
  secretValue:'',secretValues:new Map([['email','a@b'],['password','p']]),secretVisible:false,fieldVisible:new Map(),
  answers:new Map(),customAnswers:new Map(),busy:false,submitted:false,referenceMode:false,
  connection:{async secretValues(){throw {errorTag:'SecretRequestError',errorReason:'fields_mismatch'};}}
 });
 await failing.submit('');
 assert.equal(failing.submitted,false);
 assert.equal(failing.status,'此请求需要的字段与当前版本不一致，请更新应用后重试');

 // Single-value card and secret fields both expose password show/hide toggle
 assert.ok(source.includes('.showPasswordIcon(true)'));
 assert.ok(source.includes('.showPassword(this.secretVisible)'));
 assert.ok(source.includes('.showPassword(this.isFieldVisible(field.name))'));
 assert.ok(source.includes('.type(InputType.Normal)'));
});
