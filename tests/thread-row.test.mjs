import test from 'node:test';
import assert from 'node:assert/strict';
import {
  threadTone,
  compactTime,
  providerGlyph,
  providerLogoKind,
  shortModelDisplayName,
  threadSubline
} from '../entry/src/main/ets/protocol/ThreadRow.ts';

test('status maps to tone; empty status is neutral',()=>{
 assert.equal(threadTone('运行中'),'run');
 assert.equal(threadTone('已回复'),'done');
 assert.equal(threadTone('已完成'),'done');
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

test('providerLogoKind resolves official driver logos and model-name fallbacks cleanly',()=>{
 assert.equal(providerLogoKind('antigravity'),'antigravity');
 assert.equal(providerLogoKind('claudeAgent'),'claude');
 assert.equal(providerLogoKind('anthropic'),'claude');
 assert.equal(providerLogoKind('codex'),'openai');
 assert.equal(providerLogoKind('openai'),'openai');
 assert.equal(providerLogoKind('cursor'),'cursor');
 assert.equal(providerLogoKind('grok'),'grok');
 assert.equal(providerLogoKind('opencode'),'opencode');
 assert.equal(providerLogoKind('kiro'),'kiro');
 assert.equal(providerLogoKind('muse'),'muse');
 assert.equal(providerLogoKind('pi'),'pi');
 assert.equal(providerLogoKind('pi-coding'),'pi');
 assert.equal(providerLogoKind('fx'),'fx');
 assert.equal(providerLogoKind('openrouter'),'openrouter');
 assert.equal(providerLogoKind('acpRegistry'),'acp');
 assert.equal(providerLogoKind('google-gemini'),'gemini');
 assert.equal(providerLogoKind('custom-api'),'generic');
 assert.equal(providerLogoKind('custom-api','claude-opus-4-8'),'claude');
 assert.equal(providerLogoKind('custom-api','gpt-5.4'),'openai');
 assert.equal(providerLogoKind('custom-api','auto/gpt-6-sol'),'openai');
 assert.equal(providerLogoKind('custom-api','o3-mini'),'openai');
 assert.equal(providerLogoKind('custom-api','gemini-4-neon'),'antigravity');
 assert.equal(providerLogoKind('custom-api','grok-4.6'),'grok');
 assert.equal(providerLogoKind('custom-api','composer-2.5'),'cursor');
 assert.equal(providerLogoKind('',''),'none');
});

test('shortModelDisplayName trims vendor prefixes and routing suffixes cleanly',()=>{
 assert.equal(shortModelDisplayName('Claude Opus 4.8','claude-opus-4-8'),'Opus 4.8');
 assert.equal(shortModelDisplayName('Gemini 4 Neon','gemini-4-neon'),'Gemini 4 Neon');
 assert.equal(shortModelDisplayName('Grok 4.6 · routing group','auto/grok-4.6'),'Grok 4.6');
 assert.equal(shortModelDisplayName('codex / GPT-6.2-Sol','codex/gpt-6.2-sol'),'GPT-6.2-Sol');
 assert.equal(shortModelDisplayName('OpenAI: GPT-5.4','gpt-5.4'),'GPT-5.4');
 assert.equal(shortModelDisplayName('','codex/gpt-5.4'),'gpt-5.4');
 assert.equal(shortModelDisplayName('',''),'');
});

test('subline shows error only for failed threads',()=>{
 assert.deepEqual(threadSubline('失败','Rate  limit\nreached','Mac'),{text:'Rate limit reached',error:true});
 assert.deepEqual(threadSubline('失败','','Mac'),{text:'Mac',error:false});
 assert.deepEqual(threadSubline('运行中','old error','Mac'),{text:'Mac',error:false});
});
