import test from 'node:test';
import assert from 'node:assert/strict';
import {
  projectInitials,
  stableHash,
  monogramTone,
  MONOGRAM_TONE_COUNT,
  resolveLucideIconSlug,
  projectIconColorKey,
  projectIconSignature
} from '../entry/src/main/ets/protocol/Monogram.ts';

test('project initials take first letters of the first two words', () => {
  assert.equal(projectInitials('t3code-harmony'), 'TH');
  assert.equal(projectInitials('r5-round2'), 'RR');
  assert.equal(projectInitials('hello world again'), 'HW');
  assert.equal(projectInitials('my_project.name'), 'MP');
  assert.equal(projectInitials('@scope/pkg'), 'SP');
  assert.equal(projectInitials('über cool'), 'ÜC');
});

test('project initials split camelCase but keep digit-led words together', () => {
  assert.equal(projectInitials('myProject'), 'MP');
  assert.equal(projectInitials('T3Code'), 'T3');
  assert.equal(projectInitials('t3code'), 'T3');
  assert.equal(projectInitials('omarchy'), 'OM');
  assert.equal(projectInitials('r5'), 'R5');
  assert.equal(projectInitials('x'), 'X');
});

test('project initials use a single CJK or symbol character', () => {
  assert.equal(projectInitials('拉文克劳'), '拉');
  assert.equal(projectInitials('中文 project'), '中');
  assert.equal(projectInitials('x 中文'), 'X');
  assert.equal(projectInitials('プロジェクト'), 'プ');
  assert.equal(projectInitials('🚀 launch'), '🚀');
  assert.equal(projectInitials('𠀀字'), '𠀀');
});

test('project initials fall back to ? for empty input', () => {
  assert.equal(projectInitials(''), '?');
  assert.equal(projectInitials('   '), '?');
  assert.equal(projectInitials('---'), '?');
  assert.equal(projectInitials(undefined), '?');
  assert.equal(projectInitials(null), '?');
});

test('stable hash is deterministic FNV-1a', () => {
  assert.equal(stableHash(''), 0x811c9dc5);
  assert.equal(stableHash('a'), 0xe40c292c);
  assert.equal(stableHash('foobar'), 0xbf9cf968);
  assert.equal(stableHash('project-1'), stableHash('project-1'));
  assert.notEqual(stableHash('project-1'), stableHash('project-2'));
});

test('monogram tone stays in range, is stable and spreads across tones', () => {
  assert.equal(MONOGRAM_TONE_COUNT, 8);
  const seen = new Set();
  for (let i = 0; i < 200; i++) {
    const tone = monogramTone('project-' + i);
    assert.ok(Number.isInteger(tone) && tone >= 0 && tone < MONOGRAM_TONE_COUNT);
    assert.equal(monogramTone('project-' + i), tone);
    seen.add(tone);
  }
  assert.equal(seen.size, MONOGRAM_TONE_COUNT);
  assert.equal(monogramTone(undefined), monogramTone(''));
  assert.equal(monogramTone('abc', 1), 0);
  assert.equal(monogramTone('abc', 0), 0);
  assert.ok(monogramTone('abc', 3) < 3);
});

test('project icon helpers resolve bundled Lucide slugs, aliases, colors, and signatures', () => {
  assert.equal(resolveLucideIconSlug('globe-2'), 'globe-2');
  assert.equal(resolveLucideIconSlug('WRENCH'), 'wrench');
  assert.equal(resolveLucideIconSlug('earth'), 'globe-2');
  assert.equal(resolveLucideIconSlug('code-xml'), 'code-2');
  assert.equal(resolveLucideIconSlug('layers'), 'layers-3');
  assert.equal(resolveLucideIconSlug('message-square-dashed'), 'message-square-dashed');
  assert.equal(resolveLucideIconSlug('unknown-future-icon'), '');
  assert.equal(resolveLucideIconSlug(undefined), '');

  assert.equal(projectIconColorKey('indigo'), 'indigo');
  assert.equal(projectIconColorKey('Fuchsia'), 'fuchsia');
  assert.equal(projectIconColorKey('not-a-color'), '');
  assert.equal(projectIconColorKey(null), '');

  assert.equal(projectIconSignature(undefined), '');
  assert.equal(
    projectIconSignature({ kind: 'lucide', name: 'globe-2', color: 'indigo', emoji: '', text: '' }),
    'lucide:globe-2:indigo::'
  );
});
