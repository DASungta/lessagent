import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {r4Url} from './load-core.mjs';
const ts=createRequire(import.meta.url)((process.env.DEVECO_HOME || '/Applications/DevEco-Studio.app/Contents')+'/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const original=await readFile(new URL('../entry/src/main/ets/services/AttachmentPicker.ets',import.meta.url),'utf8');
async function setup(size=5, opts={}){
 let cursor=0,closed=0,sourceReleased=0,packerReleased=0;
 const uploads=[];
 let lastPhotoOptions=null;
 let lastPackingOptions=null;
 const client={
  captureAttachmentTarget:()=>()=>true,
  cancelUpload(){},
  thread:{threadId:'t'},
  recovery:{base:'https://test',environmentId:'env',threadId:'t'},
  upload:async(name,bytes,mimeType,type)=>uploads.push({name,bytes:[...new Uint8Array(bytes)],mimeType,type})
 };
 const photoUris = opts.photoUris ?? ['file://media/Photo/1/IMG_1/photo.png'];
 const fileNameMap = opts.fileNames ?? {};
 const packedBytes = opts.packedBytes ?? new Uint8Array([0xff, 0xd8, 0xff, 0xd9]).buffer;
 const kit={
  client,
  picker:{DocumentSelectOptions:class{},DocumentViewPicker:class{async select(){return ['file://selected']}}},
  photoAccessHelper:{
   PhotoViewMIMETypes:{IMAGE_TYPE:'image/*'},
   PhotoSelectOptions:class{},
   PhotoViewPicker:class{async select(options){lastPhotoOptions=options;return {photoUris};}}
  },
  image:{
   createImageSource:(fd)=>opts.nullImageSource ? undefined : {fd,release:async()=>{sourceReleased++;}},
   createImagePacker:()=>({
    packToData:async(_source,options)=>{lastPackingOptions=options;if(opts.packError)throw opts.packError;return packedBytes;},
    release:async()=>{packerReleased++;}
   })
  },
  fileUri:{FileUri:class{
   constructor(uri){this.uri=uri;}
   get name(){
    if(Object.prototype.hasOwnProperty.call(fileNameMap,this.uri))return fileNameMap[this.uri];
    const parts=this.uri.split('/');
    const tail=parts[parts.length-1];
    return tail==='selected'?'test.txt':tail;
   }
  }},
  fileIo:{
   OpenMode:{READ_ONLY:0},
   open:async()=>{cursor=0;return {fd:1}},
   stat:async()=>({size}),
   read:async(fd,buffer)=>{const n=Math.min(2,size-cursor);for(let i=0;i<n;i++)new Uint8Array(buffer)[i]=++cursor;return n},
   close:async()=>closed++
  }
 };
 globalThis.__pickerKit=kit;
 const source=original
  .replace("import { picker, fileIo, fileUri } from '@kit.CoreFileKit';",'const {picker,fileIo,fileUri}=globalThis.__pickerKit;')
  .replace("import { photoAccessHelper } from '@kit.MediaLibraryKit';",'const {photoAccessHelper}=globalThis.__pickerKit;')
  .replace("import { image } from '@kit.ImageKit';",'const {image}=globalThis.__pickerKit;')
  .replace("import { client, T3Client } from './T3Client';",'const {client}=globalThis.__pickerKit;')
  .replace("'../protocol/R4'", JSON.stringify(r4Url));
 const compiled=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.ES2022,target:ts.ScriptTarget.ES2022}}).outputText;
 const {AttachmentPicker}=await import('data:text/javascript;base64,'+Buffer.from(compiled+'\n//'+Math.random()).toString('base64'));
 return {
  picker:new AttachmentPicker(),client,uploads,
  closed:()=>closed,
  released:()=>({source:sourceReleased,packer:packerReleased}),
  lastPhotoOptions:()=>lastPhotoOptions,
  lastPackingOptions:()=>lastPackingOptions
 };
}
test('picker handles short reads and always closes the selected document',async()=>{
 const s=await setup();const ok=await s.picker.choose();assert.equal(ok,true);
 assert.deepEqual(s.uploads,[{name:'test.txt',bytes:[1,2,3,4,5],mimeType:'text/plain',type:'file'}]);assert.equal(s.closed(),1);
 const large=await setup(50*1024*1024+1);await assert.rejects(large.picker.choose(),/50 MiB/);assert.equal(large.closed(),1);assert.equal(large.uploads.length,0);
});
test('failed document upload is manually retryable only in its original server and thread',async()=>{
 const s=await setup();assert.equal(s.picker.canRetry(),false);
 s.client.upload=async()=>{throw Error('offline')};await assert.rejects(s.picker.choose(),/offline/);
 assert.equal(s.picker.canRetry(),true);
 s.client.recovery.environmentId='other';assert.equal(s.picker.canRetry(),false);
 await assert.rejects(s.picker.retry(),/重新选择/);assert.equal(s.closed(),1);
 s.client.recovery.environmentId='env';assert.equal(s.picker.canRetry(),true);
 s.picker.clear();assert.equal(s.picker.canRetry(),false);
 await assert.rejects(s.picker.retry(),/重新选择/);
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
 assert.equal(s.picker.canRetry(),true);
 await s.picker.retry();
 assert.equal(s.picker.canRetry(),false);
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

test('choosePhotos opens PhotoViewPicker for images and uploads gallery photos as image attachments', async () => {
 const s=await setup(5,{photoUris:['file://media/Photo/1/IMG_001/shot.jpg']});
 const uploaded=await s.picker.choosePhotos();
 assert.equal(uploaded,true);
 assert.equal(s.lastPhotoOptions().MIMEType,'image/*');
 assert.equal(s.lastPhotoOptions().maxSelectNumber,10);
 assert.deepEqual(s.uploads,[{name:'shot.jpg',bytes:[1,2,3,4,5],mimeType:'image/jpeg',type:'image'}]);
 assert.equal(s.closed(),1);
 assert.equal(s.picker.canRetry(),false);
});

test('choosePhotos returns false without uploading when cancelled', async () => {
 const s=await setup(5,{photoUris:[]});
 const uploaded=await s.picker.choosePhotos();
 assert.equal(uploaded,false);
 assert.equal(s.uploads.length,0);
 assert.equal(s.closed(),0);
 assert.equal(s.picker.canRetry(),false);
});

test('choosePhotos transcodes HEIC gallery photos to JPEG and always releases native handles', async () => {
 const s=await setup(12,{photoUris:['file://media/Photo/2/IMG_002/camera.heic']});
 const uploaded=await s.picker.choosePhotos();
 assert.equal(uploaded,true);
 assert.deepEqual(s.lastPackingOptions(),{format:'image/jpeg',quality:90});
 assert.deepEqual(s.uploads,[{name:'camera.jpg',bytes:[0xff,0xd8,0xff,0xd9],mimeType:'image/jpeg',type:'image'}]);
 assert.equal(s.closed(),1);
 assert.deepEqual(s.released(),{source:1,packer:1});

 const fail=await setup(12,{photoUris:['file://media/Photo/3/IMG_003/camera.heic'],packError:new Error('codec error')});
 await assert.rejects(fail.picker.choosePhotos(),/暂不支持/);
 assert.equal(fail.closed(),1);
 assert.deepEqual(fail.released(),{source:1,packer:1});
});

test('choosePhotos rejects if target thread changes while gallery picker is open', async () => {
 const s=await setup(5,{photoUris:['file://media/Photo/4/IMG_004/shot.png']});
 globalThis.__pickerKit.photoAccessHelper.PhotoViewPicker=class{
  async select(){s.client.recovery.threadId='other';return {photoUris:['file://media/Photo/4/IMG_004/shot.png']};}
 };
 await assert.rejects(s.picker.choosePhotos(),/附件目标已变化/);
 assert.equal(s.uploads.length,0);
 assert.equal(s.closed(),0);
});
