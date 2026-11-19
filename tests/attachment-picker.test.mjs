import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
const ts=createRequire(import.meta.url)((process.env.DEVECO_HOME || '/Applications/DevEco-Studio.app/Contents')+'/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const original=await readFile(new URL('../entry/src/main/ets/services/AttachmentPicker.ets',import.meta.url),'utf8');
async function setup(size=5){
 let cursor=0,closed=0;const uploads=[];
 const client={captureAttachmentTarget:()=>()=>true,thread:{threadId:'t'},recovery:{base:'https://test',environmentId:'env',threadId:'t'},upload:async(name,bytes)=>uploads.push({name,bytes:[...new Uint8Array(bytes)]})};
 const kit={client,picker:{DocumentSelectOptions:class{},DocumentViewPicker:class{async select(){return ['file://selected']}}},
 fileUri:{FileUri:class{get name(){return 'test.txt'}}},fileIo:{OpenMode:{READ_ONLY:0},open:async()=>{cursor=0;return {fd:1}},stat:async()=>({size}),
 read:async(fd,buffer)=>{const n=Math.min(2,size-cursor);for(let i=0;i<n;i++)new Uint8Array(buffer)[i]=++cursor;return n},close:async()=>closed++}};
 globalThis.__pickerKit=kit;
 const source=original.replace("import { picker, fileIo, fileUri } from '@kit.CoreFileKit';",'const {picker,fileIo,fileUri}=globalThis.__pickerKit;').replace("import { client, T3Client } from './T3Client';",'const {client}=globalThis.__pickerKit;');
 const compiled=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.ES2022,target:ts.ScriptTarget.ES2022}}).outputText;
 const {AttachmentPicker}=await import('data:text/javascript;base64,'+Buffer.from(compiled+'\n//'+Math.random()).toString('base64'));
 return {picker:new AttachmentPicker(),client,uploads,closed:()=>closed};
}
test('picker handles short reads and always closes the selected document',async()=>{
 const s=await setup();await s.picker.choose();assert.deepEqual(s.uploads,[{name:'test.txt',bytes:[1,2,3,4,5]}]);assert.equal(s.closed(),1);
 const large=await setup(50*1024*1024+1);await assert.rejects(large.picker.choose(),/50 MiB/);assert.equal(large.closed(),1);assert.equal(large.uploads.length,0);
});
test('failed document upload is manually retryable only in its original server and thread',async()=>{
 const s=await setup();s.client.upload=async()=>{throw Error('offline')};await assert.rejects(s.picker.choose(),/offline/);
 s.client.recovery.environmentId='other';await assert.rejects(s.picker.retry(),/重新选择/);assert.equal(s.closed(),1);
 s.picker.clear();await assert.rejects(s.picker.retry(),/重新选择/);
});
test('thread changes while reading a file cannot upload it into the new thread',async()=>{
 const s=await setup();const read=globalThis.__pickerKit.fileIo.read;
 globalThis.__pickerKit.fileIo.read=async(...args)=>{const n=await read(...args);s.client.recovery.threadId='other';return n};
 await assert.rejects(s.picker.choose(),/重新选择/);assert.equal(s.uploads.length,0);assert.equal(s.closed(),1);
});

test('older upload completion cannot remove the newer picker selection from the retry queue', async () => {
 const s=await setup();
 let finish,ready;
 let attempts=0;
 const gate=new Promise(resolve=>finish=resolve);
 const entered=new Promise(resolve=>ready=resolve);
 s.client.upload=async()=>{
  attempts++;
  if(attempts===1){ready();await gate;}
  else if(attempts===2)throw Error('new upload failed');
 };
 const stale=assert.rejects(s.picker.choose(),/重新选择/);
 await entered;s.picker.clear();
 await assert.rejects(s.picker.choose(),/new upload failed/);
 finish();await stale;
 await s.picker.retry();
 assert.equal(attempts,3);
 assert.equal(s.closed(),3);
});

test('returning from the native picker may reconnect as long as the attachment scope stayed the same', async () => {
 const s=await setup();
 let generation=1;
 s.client.captureAttachmentTarget=(requireLiveConnection=true)=>{
  const captured=generation;
  return ()=>!requireLiveConnection||captured===generation;
 };
 globalThis.__pickerKit.picker.DocumentViewPicker=class{async select(){generation++;return ['file://selected'];}};
 await s.picker.choose();
 assert.equal(s.uploads.length,1);
});
