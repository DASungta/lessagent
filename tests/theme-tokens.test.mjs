import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname, '..');
const LIGHT_COLOR_PATH = path.join(ROOT, 'entry/src/main/resources/base/element/color.json');
const DARK_COLOR_PATH = path.join(ROOT, 'entry/src/main/resources/dark/element/color.json');
const ETS_DIR = path.join(ROOT, 'entry/src/main/ets');
const MODULE_JSON = path.join(ROOT, 'entry/src/main/module.json5');

function loadTokens(filePath) {
  const raw = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  const map = new Map();
  for (const entry of raw.color) {
    assert.equal(typeof entry.name, 'string');
    assert.equal(typeof entry.value, 'string');
    assert.ok(!map.has(entry.name), `duplicate token ${entry.name} in ${filePath}`);
    map.set(entry.name, entry.value);
  }
  return map;
}

function collectFiles(dir, exts) {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      out.push(...collectFiles(full, exts));
    } else if (exts.some((ext) => entry.name.endsWith(ext))) {
      out.push(full);
    }
  }
  return out.sort();
}

function parseHex(hex) {
  const h = hex.replace(/^#/, '');
  if (h.length === 8) {
    return [
      parseInt(h.slice(2, 4), 16),
      parseInt(h.slice(4, 6), 16),
      parseInt(h.slice(6, 8), 16),
      parseInt(h.slice(0, 2), 16) / 255
    ];
  }
  if (h.length === 6) {
    return [
      parseInt(h.slice(0, 2), 16),
      parseInt(h.slice(2, 4), 16),
      parseInt(h.slice(4, 6), 16),
      1
    ];
  }
  throw new Error(`Unsupported color format: ${hex}`);
}

function luminance(rgb) {
  const channel = (c) => {
    const s = c / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * channel(rgb[0]) + 0.7152 * channel(rgb[1]) + 0.0722 * channel(rgb[2]);
}

function contrastRatio(fgHex, bgHex) {
  const fg = parseHex(fgHex);
  const bg = parseHex(bgHex);
  assert.equal(fg[3], 1, `foreground color must be opaque: ${fgHex}`);
  assert.equal(bg[3], 1, `background color must be opaque: ${bgHex}`);
  const l1 = luminance(fg);
  const l2 = luminance(bg);
  return (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05);
}

test('base and dark color tables match symmetrically and drop all removed legacy tokens', () => {
  const light = loadTokens(LIGHT_COLOR_PATH);
  const dark = loadTokens(DARK_COLOR_PATH);

  assert.deepEqual([...light.keys()].sort(), [...dark.keys()].sort());
  assert.equal(light.size, 75);

  const legacyTokens = ['canvas', 'surface', 'selected', 'composer', 'on_primary'];
  for (const name of legacyTokens) {
    assert.ok(!light.has(name), `legacy token ${name} must be removed from base color.json`);
    assert.ok(!dark.has(name), `legacy token ${name} must be removed from dark color.json`);
  }

  const etsFiles = collectFiles(ETS_DIR, ['.ets', '.ts']);
  for (const file of [...etsFiles, MODULE_JSON]) {
    const src = fs.readFileSync(file, 'utf8');
    for (const name of legacyTokens) {
      assert.equal(
        new RegExp(`(?:app\\.color\\.|\\$color:)${name}\\b`).test(src),
        false,
        `${path.relative(ROOT, file)} still references removed legacy token ${name}`
      );
    }
  }
});

test('ets components avoid primary as fontColor and danger as solid background', () => {
  const etsFiles = collectFiles(ETS_DIR, ['.ets']);
  for (const file of etsFiles) {
    const src = fs.readFileSync(file, 'utf8');
    const rel = path.relative(ROOT, file);
    assert.equal(
      /\.fontColor\((?:[^()\n]|\([^()\n]*\))*app\.color\.primary\b/.test(src),
      false,
      `${rel} uses app.color.primary for text; use app.color.primary_text instead`
    );
    assert.equal(
      /\.backgroundColor\((?:[^()\n]|\([^()\n]*\))*app\.color\.danger\b/.test(src),
      false,
      `${rel} uses app.color.danger as background; use app.color.danger_bg + danger instead`
    );
  }
});

test('all critical text/fill pairs meet WCAG AA contrast (>= 4.5:1) in both light and dark themes', () => {
  const light = loadTokens(LIGHT_COLOR_PATH);
  const dark = loadTokens(DARK_COLOR_PATH);

  const pairs = [
    ['ink', 'screen'],
    ['ink', 'card'],
    ['ink', 'group'],
    ['muted', 'screen'],
    ['muted', 'card'],
    ['muted', 'group'],
    ['placeholder', 'screen'],
    ['placeholder', 'card'],
    ['placeholder', 'group'],
    ['on_prominent', 'prominent'],
    ['on_primary_fill', 'primary'],
    ['primary_text', 'screen'],
    ['primary_text', 'card'],
    ['primary_text', 'group'],
    ['primary_text', 'info_bg'],
    ['danger', 'card'],
    ['danger', 'danger_bg'],
    ['warning', 'card'],
    ['warning', 'warning_bg'],
    ['success', 'card'],
    ['success', 'success_bg'],
    ['info', 'card'],
    ['info', 'info_bg'],
    ['bubble_ink', 'bubble'],
    ['diff_add_ink', 'diff_add'],
    ['diff_del_ink', 'diff_del']
  ];

  for (const [themeName, tokens] of [['light', light], ['dark', dark]]) {
    for (const [fg, bg] of pairs) {
      const ratio = contrastRatio(tokens.get(fg), tokens.get(bg));
      assert.ok(
        ratio >= 4.5,
        `${themeName} ${fg} (${tokens.get(fg)}) on ${bg} (${tokens.get(bg)}) contrast ${ratio.toFixed(2)}:1 < 4.5:1`
      );
    }
  }
});
