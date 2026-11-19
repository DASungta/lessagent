import test from 'node:test';
import assert from 'node:assert/strict';
import {directHostKind} from '../entry/src/main/ets/protocol/Hosts.ts';
test('direct route kinds preserve pinned upstream network distinctions',()=>{
 for(const [host,kind] of [['localhost.','loopback'],['127.1.2.3','loopback'],['[::1]','loopback'],['box.local','lan'],['192.168.1.2','lan'],['172.16.1.1','lan'],['198.18.1.1','lan'],['[fe80::1]','lan'],['[fd00::1]','lan'],['[::ffff:c0a8:1]','lan'],['100.64.1.1','vpn'],['100.127.2.2','vpn'],['100.128.2.2','public'],['box.ts.net','tailnet'],['[FD7A:115C:A1E0::1]','tailnet'],['example.com','public'],['8.8.8.8','public']])assert.equal(directHostKind(host),kind,host);
});
