import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, access } from 'node:fs/promises';
import { compile, data } from './load-core.mjs';

const root = new URL('../', import.meta.url);
const read = path => readFile(new URL(path, root), 'utf8');
const source = (await read('entry/src/main/ets/services/ShortcutInbox.ets'))
  .replace("import { Want } from '@kit.AbilityKit';", '');
const inbox = await import(data(compile(source)));
const notify = [];
globalThis.AppStorage = { setOrCreate: (key, generation) => notify.push({ key, generation }) };
const want = action => ({ parameters: { t3ShortcutAction: action } });

test('the manifest advertises both static shortcuts and the real launches use their string action', async () => {
  const module = JSON.parse(await read('entry/src/main/module.json5')).module;
  const app = JSON.parse(await read('AppScope/app.json5')).app;
  const profile = JSON.parse(await read('entry/src/main/resources/base/profile/shortcuts_config.json'));
  const strings = JSON.parse(await read('entry/src/main/resources/base/element/string.json')).string;
  const entry = module.abilities.find(ability => ability.name === module.mainElement);
  assert.deepEqual(entry.metadata.find(item => item.name === 'ohos.ability.shortcuts'),
    { name: 'ohos.ability.shortcuts', resource: '$profile:shortcuts_config' });
  assert.deepEqual(profile.shortcuts.map(item => item.shortcutId), ['new-task', 'sessions']);
  for (const shortcut of profile.shortcuts) {
    assert.ok(strings.some(item => '$string:' + item.name === shortcut.label));
    await access(new URL('entry/src/main/resources/base/media/' + shortcut.icon.replace('$media:', '') + '.svg', root));
    assert.deepEqual(shortcut.wants, [{
      bundleName: app.bundleName, moduleName: module.name, abilityName: entry.name,
      parameters: { t3ShortcutAction: shortcut.shortcutId }
    }]);
  }
  const ability = await read('entry/src/main/ets/entryability/EntryAbility.ets');
  assert.match(ability, /onCreate\(want: Want\): void \{\s*if \(acceptShortcutWant\(want\)\) return;/);
  assert.match(ability, /onNewWant\(want: Want\): void \{\s*if \(acceptShortcutWant\(want\)\) return;/);
});

test('cold and warm Want delivery is bounded, explicit and consumed once', () => {
  assert.equal(inbox.acceptShortcutWant({}), false);
  assert.equal(inbox.peekShortcut(), undefined);
  for (const request of [want('open-url'), want(null), want(true), { ...want('sessions'), uri: 'https://example.test' },
    { ...want('new-task'), action: 'ohos.want.action.sendData' }]) {
    assert.equal(inbox.acceptShortcutWant(request), true);
    assert.equal(inbox.peekShortcut(), undefined);
  }
  assert.equal(notify.length, 0);
  assert.equal(inbox.acceptShortcutWant(want('new-task')), true);
  const first = inbox.peekShortcut();
  assert.equal(first.action, 'new-task');
  assert.equal(inbox.acceptShortcutWant(want('sessions')), true);
  const second = inbox.peekShortcut();
  assert.equal(second.action, 'sessions');
  assert.ok(second.id > first.id);
  assert.equal(inbox.consumeShortcut(first.id), false);
  assert.equal(inbox.consumeShortcut(second.id), true);
  assert.equal(inbox.consumeShortcut(second.id), false);
  assert.deepEqual(notify, [
    { key: 't3ShortcutGeneration', generation: first.id }, { key: 't3ShortcutGeneration', generation: second.id }
  ]);
});

test('a request expires while navigation is blocked and cannot execute later', t => {
  let now = 100;
  t.mock.method(Date, 'now', () => now);
  assert.equal(inbox.acceptShortcutWant(want('new-task')), true);
  const request = inbox.peekShortcut();
  now += 30000;
  assert.equal(inbox.peekShortcut(), undefined);
  assert.equal(inbox.consumeShortcut(request.id), false);
  now++;
  assert.equal(inbox.acceptShortcutWant(want('sessions')), true);
  now--;
  assert.equal(inbox.peekShortcut(), undefined);
});

test('the static 2×2 card offers only two foreground routes with empty binding data', async () => {
  const module = JSON.parse(await read('entry/src/main/module.json5')).module;
  const profile = JSON.parse(await read('entry/src/main/resources/base/profile/form_config.json'));
  const extension = module.extensionAbilities.find(item => item.name === 'ShortcutFormAbility');
  assert.equal(extension.type, 'form');
  assert.deepEqual(extension.metadata, [{ name: 'ohos.extension.form', resource: '$profile:form_config' }]);
  const [form] = profile.forms;
  assert.equal(profile.forms.length, 1);
  assert.equal(form.uiSyntax, 'arkts');
  assert.equal(form.isDynamic, false);
  assert.equal(form.updateEnabled, false);
  assert.equal(form.defaultDimension, '2*2');
  assert.deepEqual(form.supportDimensions, ['2*2']);
  const ability = await read('entry/src/main/' + extension.srcEntry.slice(2));
  assert.match(ability, /onAddForm\(_want: Want\): formBindingData.FormBindingData \{\s*return formBindingData.createFormBindingData\(\);/);
  const card = await read('entry/src/main/' + form.src.slice(2));
  assert.match(card, /app.string.app_name/);
  assert.equal([...card.matchAll(/\.height\(44\)/g)].length, 2);
  assert.deepEqual([...card.matchAll(/FormLink\(\{ action: 'router', moduleName: 'entry', abilityName: 'EntryAbility', params: \{ t3ShortcutAction: '([^']+)' \} \}\)/g)]
    .map(match => match[1]), ['new-task', 'sessions']);
  assert.doesNotMatch(card, /postCardAction|\.onClick\(|uri:|action: '(?:call|message)'/);
});

test('FormLink Want parameters share the shortcut inbox and reject mixed or malformed payloads', () => {
  const form = value => ({ parameters: { params: JSON.stringify(value) } });
  assert.equal(inbox.acceptShortcutWant(form({ t3ShortcutAction: 'new-task' })), true);
  assert.equal(inbox.peekShortcut().action, 'new-task');
  assert.equal(inbox.consumeShortcut(inbox.peekShortcut().id), true);
  assert.equal(inbox.acceptShortcutWant(form({ t3ShortcutAction: 'sessions' })), true);
  assert.equal(inbox.peekShortcut().action, 'sessions');
  assert.equal(inbox.consumeShortcut(inbox.peekShortcut().id), true);
  inbox.acceptShortcutWant({ parameters: { t3ShortcutAction: 'new-task', params: JSON.stringify({ t3ShortcutAction: 'new-task' }) } });
  const duplicated = inbox.peekShortcut();
  assert.equal(duplicated.action, 'new-task');
  assert.equal(inbox.consumeShortcut(duplicated.id), true);
  assert.equal(inbox.consumeShortcut(duplicated.id), false);
  for (const mixed of [
    { ...form({ t3ShortcutAction: 'sessions' }), uri: 't3code://pair' },
    { ...form({ t3ShortcutAction: 'sessions' }), action: 'ohos.want.action.sendData' },
    { parameters: { t3ShortcutAction: 'new-task', params: '{"t3ShortcutAction":"sessions"}' } },
    form({ t3ShortcutAction: 'sessions', uri: 'https://example.test' }),
    form({ t3ShortcutAction: 'unknown' }), form({ t3ShortcutAction: true })
  ]) {
    assert.equal(inbox.acceptShortcutWant(mixed), true);
    assert.equal(inbox.peekShortcut(), undefined);
  }
  for (const params of ['{', '[]', 'null', '{"anotherAction":"sessions"}', ' '.repeat(256) + '{"t3ShortcutAction":"sessions"}']) {
    assert.equal(inbox.acceptShortcutWant({ parameters: { params } }), false);
    assert.equal(inbox.peekShortcut(), undefined);
  }
});
