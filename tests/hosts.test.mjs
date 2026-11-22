import test from 'node:test';
import assert from 'node:assert/strict';
import {directHostKind,urlHostname,shouldBypassSystemProxy} from '../entry/src/main/ets/protocol/Hosts.ts';
test('direct route kinds preserve pinned upstream network distinctions',()=>{
 for(const [host,kind] of [['localhost.','loopback'],['127.1.2.3','loopback'],['[::1]','loopback'],['box.local','lan'],['192.168.1.2','lan'],['172.16.1.1','lan'],['198.18.1.1','lan'],['[fe80::1]','lan'],['[fd00::1]','lan'],['[::ffff:c0a8:1]','lan'],['100.64.1.1','vpn'],['100.127.2.2','vpn'],['100.128.2.2','public'],['box.ts.net','tailnet'],['[FD7A:115C:A1E0::1]','tailnet'],['example.com','public'],['8.8.8.8','public']])assert.equal(directHostKind(host),kind,host);
});
test('urlHostname and shouldBypassSystemProxy distinguish private/direct endpoints from public hosts',()=>{
 for(const [target,host,bypass] of [
  ['http://192.168.2.97:3773/.well-known/t3/environment','192.168.2.97',true],
  ['ws://192.168.2.97:3773/ws','192.168.2.97',true],
  ['http://127.0.0.1:3773','127.0.0.1',true],
  ['http://[::1]:3773','[::1]',true],
  ['http://localhost:3773','localhost',true],
  ['https://box.ts.net/api','box.ts.net',true],
  ['http://100.64.1.2:3773','100.64.1.2',true],
  ['https://example.com/.well-known/t3/environment','example.com',false],
  ['wss://relay.t3.codes/ws','relay.t3.codes',false],
  ['','',false],
  ['not-a-url','',false],
 ]){
  assert.equal(urlHostname(target),host,target);
  assert.equal(shouldBypassSystemProxy(target),bypass,target);
 }
});
