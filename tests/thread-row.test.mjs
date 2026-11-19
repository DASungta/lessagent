import test from 'node:test';
import assert from 'node:assert/strict';
import {threadTone,compactTime,providerGlyph,threadSubline} from '../entry/src/main/ets/protocol/ThreadRow.ts';

test('status maps to tone; empty status is neutral',()=>{
 assert.equal(threadTone('运行中'),'run');
 for(const s of ['等待批准','等待回答','访客消息','等待']) assert.equal(threadTone(s),'wait');
 assert.equal(threadTone('失败'),'danger');assert.equal(threadTone('用量受限'),'danger');
 assert.equal(threadTone('暂缓 明天 09:00'),'neutral');assert.equal(threadTone(''),'neutral');
});

test('compact relative time',()=>{
 const now=Date.parse('2026-11-19T12:00:00Z');
 assert.equal(compactTime('2026-11-19T11:59:30Z',now),'刚刚');
 assert.equal(compactTime('2026-11-19T11:52:00Z',now),'8分钟');
 assert.equal(compactTime('2026-11-19T10:00:00Z',now),'2小时');
 assert.equal(compactTime('2026-11-16T12:00:00Z',now),'3天');
 assert.match(compactTime('2026-11-02T12:00:00Z',now),/^11月2日$/);
 assert.match(compactTime('2025-03-02T12:00:00Z',now),/^2025年3月2日$/);
 assert.equal(compactTime('',now),'');assert.equal(compactTime('2026-11-19T13:00:00Z',now),'刚刚');
});

test('provider glyph never exposes model names',()=>{
 assert.equal(providerGlyph('claudeAgent'),'claude');
 assert.equal(providerGlyph('codex'),'openai');
 assert.equal(providerGlyph('Antigravity'),'gemini');
 assert.equal(providerGlyph('cursor'),'cursor');
 assert.equal(providerGlyph('my-custom'),'generic');
 assert.equal(providerGlyph(''),'none');
});

test('subline shows error only for failed threads',()=>{
 assert.deepEqual(threadSubline('失败','Rate  limit\nreached','Mac'),{text:'Rate limit reached',error:true});
 assert.deepEqual(threadSubline('失败','','Mac'),{text:'Mac',error:false});
 assert.deepEqual(threadSubline('运行中','old error','Mac'),{text:'Mac',error:false});
});
