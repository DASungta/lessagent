import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {readFile} from 'node:fs/promises';
import {compile,data} from './load-core.mjs';
const bridge={OpenMode:{CREATE:1,READ_WRITE:2,TRUNC:4},openSync:p=>({fd:fs.openSync(p,'w+')}),writeSync:fs.writeSync,fsyncSync:fs.fsyncSync,closeSync:fs.closeSync,renameSync:fs.renameSync,
 readTextSync(p){try{return fs.readFileSync(p,'utf8')}catch(e){if(e.code==='ENOENT')throw {code:13900002};throw e}},listFileSync:fs.readdirSync,lstatSync(p){try{return fs.lstatSync(p)}catch(e){if(e.code==='ENOENT')throw {code:13900002};throw e}},accessSync:fs.existsSync,unlinkSync:fs.unlinkSync};
globalThis.__shareCacheFs=bridge;
const source=(await readFile(new URL('../entry/src/main/ets/services/ShareCache.ets',import.meta.url),'utf8')).replace("import { fileIo } from '@kit.CoreFileKit';",'const fileIo=globalThis.__shareCacheFs;').replace("import { BusinessError } from '@kit.BasicServicesKit';",'');
const C=await import(data(compile(source)));
function fixture(){const root=fs.mkdtempSync(path.join(os.tmpdir(),'t3-cache-test-'));const cache=path.join(root,'cache');fs.mkdirSync(cache);return{root,cache,done:()=>fs.rmSync(root,{recursive:true,force:true})}}
test('cache cleanup respects environment, recent shares and unrelated files',()=>{
 const f=fixture(),now=Date.now(),old=now-7200000;
 try{
  for(const name of [`share-${old}-a.txt`,`share-${old}-b.txt`,`share-${now}-recent.txt`,'credentials.json','r4-drafts-v1.json'])fs.writeFileSync(path.join(f.cache,name),'keep');
  C.registerSharedFile(f.cache,`share-${old}-a.txt`,'a');C.registerSharedFile(f.cache,`share-${old}-b.txt`,'b');C.registerSharedFile(f.cache,`share-${now}-recent.txt`,'a');
  assert.equal(C.inspectShareCache(f.cache).length,3);assert.deepEqual(C.clearShareCache(f.cache,'a',now),{removed:1,failed:0});
  for(const name of [`share-${old}-b.txt`,`share-${now}-recent.txt`,'credentials.json','r4-drafts-v1.json'])assert.ok(fs.existsSync(path.join(f.cache,name)));
  assert.equal(C.inspectShareCache(f.cache).length,2);
 }finally{f.done()}
});
test('legacy unknown cache is separate and symlinks cannot escape the cache',()=>{
 const f=fixture(),now=Date.now(),old=now-7200000;
 try{
  const outside=path.join(f.root,'secret');fs.writeFileSync(outside,'untouched');fs.symlinkSync(outside,path.join(f.cache,`share-${old}-link`));
  fs.writeFileSync(path.join(f.cache,`share-${old}-legacy`),'legacy');assert.equal(C.inspectShareCache(f.cache).length,1);
  assert.deepEqual(C.clearShareCache(f.cache,'',now),{removed:1,failed:0});assert.equal(fs.readFileSync(outside,'utf8'),'untouched');
  fs.writeFileSync(path.join(f.cache,'t3-share-index.json'),JSON.stringify({version:1,files:[{name:'../secret',localId:'a'}]}));
  assert.throws(()=>C.clearShareCache(f.cache,undefined,now));assert.equal(fs.readFileSync(outside,'utf8'),'untouched');
 }finally{f.done()}
});
test('partial unlink failure is reported and its ownership stays recorded',()=>{
 const f=fixture(),now=Date.now(),old=now-7200000;const original=bridge.unlinkSync;
 try{
  const name=`share-${old}-failed`;fs.writeFileSync(path.join(f.cache,name),'keep');C.registerSharedFile(f.cache,name,'a');bridge.unlinkSync=()=>{throw Error('denied')};
  assert.deepEqual(C.clearShareCache(f.cache,'a',now),{removed:0,failed:1});assert.equal(C.inspectShareCache(f.cache)[0].localId,'a');
 }finally{bridge.unlinkSync=original;f.done()}
});

test('index paths cannot read or overwrite a symlink target',()=>{
 const f=fixture(),now=Date.now();try{
  const outside=path.join(f.root,'outside');fs.writeFileSync(outside,'untouched');
  fs.symlinkSync(outside,path.join(f.cache,'t3-share-index.json'));assert.throws(()=>C.inspectShareCache(f.cache));
  fs.unlinkSync(path.join(f.cache,'t3-share-index.json'));fs.symlinkSync(outside,path.join(f.cache,'t3-share-index.json.tmp'));
  assert.throws(()=>C.registerSharedFile(f.cache,`share-${now}-a`,'a'));assert.equal(fs.readFileSync(outside,'utf8'),'untouched');
  fs.unlinkSync(path.join(f.cache,'t3-share-index.json.tmp'));const absent=path.join(f.root,'absent');fs.symlinkSync(absent,path.join(f.cache,'t3-share-index.json.tmp'));
  assert.throws(()=>C.registerSharedFile(f.cache,`share-${now}-a`,'a'));assert.equal(fs.existsSync(absent),false);
 }finally{f.done()}
});
