#!/usr/bin/env python3
"""Drive only the two owned empty collision threads; never press Send."""
import datetime
import json
from pathlib import Path
import re
import sqlite3
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
evidence = root / 'docs/evidence/r1'
state_path = evidence / 'lab-state.json'
state = json.loads(state_path.read_text())
lab = Path(state['labRoot'])
hdc = '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc'
bundle = 'com.dasungta.t3code.harmony'

def device(*args):
    result = subprocess.run([hdc, '-t', state['device'], *args], capture_output=True, text=True)
    if result.returncode or '[Fail]' in result.stdout:
        raise RuntimeError('Owned native UI action failed; arguments omitted')
    return result.stdout

assert device('shell', 'param', 'get', 'const.product.model').strip() == 'ALN-AL80'

def rows():
    remote = '/data/local/tmp/r1-dual-owned-ui.json'
    with tempfile.TemporaryDirectory(dir=lab) as temporary:
        local = Path(temporary) / 'ui.json'
        device('shell', 'uitest', 'dumpLayout', '-p', remote)
        device('file', 'recv', remote, str(local))
        tree = json.loads(local.read_text())
    device('shell', 'rm', '-f', remote)
    def nodes(node):
        yield node.get('attributes', {})
        for child in node.get('children', []):
            yield from nodes(child)
    return list(nodes(tree))

def point(node):
    x1, y1, x2, y2 = map(int, re.findall(r'-?\d+', node['bounds']))
    return str((x1+x2)//2), str((y1+y2)//2)

def tap(text, scoped=False):
    # Reconnection repopulates the shell asynchronously; observe it without retrying any action.
    for _ in range(20):
        matches = [node for node in rows() if node.get('text') == text or (scoped and node.get('text', '').startswith(text+' · '))]
        if matches:
            device('shell', 'uitest', 'uiInput', 'click', *point(matches[0]))
            return
    raise AssertionError('Expected owned native control did not appear')

def directory():
    with tempfile.TemporaryDirectory(dir=lab) as temporary:
        local = Path(temporary) / 'directory.json'
        device('file', 'recv', '-b', bundle, '/data/storage/el2/base/haps/entry/files/environments-v2.json', str(local))
        return json.loads(local.read_text())

def zero_business():
    result = {}
    for service in state['services']:
        database = Path(service['baseDir']) / 'userdata/statev2.sqlite'
        with sqlite3.connect(database.as_uri()+'?mode=ro', uri=True) as connection:
            counts = {table: connection.execute('select count(*) from '+table).fetchone()[0] for table in ['orchestration_v2_projection_messages', 'orchestration_v2_projection_runs', 'orchestration_v2_projection_provider_sessions']}
        assert all(value == 0 for value in counts.values())
        result[service['name']] = counts
    return result

zero_business()
before = directory()
assert len(before['entries']) == 2
entries = {entry['environmentId']: entry for entry in before['entries']}
assert set(entries) == {service['environmentId'] for service in state['services']}
assert len({entry['credentialRef'] for entry in entries.values()}) == 2
if not any(row.get('text') == '环境' for row in rows()):
    tap('T3 Code')
for _ in range(20):
    if sum(row.get('text') in ['已连接', '会话已同步'] for row in rows()) >= 3:
        break
else:
    raise AssertionError('Both connection rows and active client must be connected')
tap('×')
home = rows()
assert sum(row.get('text') == 'Harmony 新会话' for row in home) == 2
assert all(any(row.get('text') == label or row.get('text', '').startswith(label+' · ') for row in home) for label in ['R1 isolated A', 'R1 isolated B'])

drafts = {'a': 'R1_A_UNSENT_NATIVE_109', 'b': 'R1_B_UNSENT_NATIVE_109'}
for name in ['a', 'b', 'a', 'b']:
    tap('R1 isolated '+name.upper(), scoped=True)
    snapshot = rows()
    area = next(row for row in snapshot if row.get('type') == 'TextArea')
    if not area.get('text'):
        device('shell', 'uitest', 'uiInput', 'inputText', *point(area), drafts[name])
        device('shell', 'uitest', 'uiInput', 'keyEvent', 'Back')
    assert any(row.get('type') == 'TextArea' and row.get('text') == drafts[name] for row in rows()), 'Draft crossed an environment boundary'
    active = directory()
    service = next(service for service in state['services'] if service['name'] == name)
    entry = next(entry for entry in active['entries'] if entry['environmentId'] == service['environmentId'])
    assert active['selectedLocalId'] == entry['localId']
    assert entry['recovery'][0]['threadId'] == 'r1-collision-thread'
    device('shell', 'uitest', 'uiInput', 'keyEvent', 'Back')

tap('T3 Code')
toggles = [row for row in rows() if row.get('type') == 'Toggle']
assert len(toggles) == 2
device('shell', 'uitest', 'uiInput', 'click', *point(toggles[0]))
disabled = directory()
a_id, b_id = [service['environmentId'] for service in state['services']]
assert next(entry for entry in disabled['entries'] if entry['environmentId'] == a_id)['enabled'] is False
assert next(entry for entry in disabled['entries'] if entry['environmentId'] == b_id)['enabled'] is True
tap('×');tap('R1 isolated B', scoped=True)
assert any(row.get('type') == 'TextArea' and row.get('text') == drafts['b'] for row in rows())
device('shell', 'uitest', 'uiInput', 'keyEvent', 'Back');tap('T3 Code')
toggles = [row for row in rows() if row.get('type') == 'Toggle']
device('shell', 'uitest', 'uiInput', 'click', *point(toggles[0]))
assert all(entry['enabled'] for entry in directory()['entries'])
tap('×');tap('R1 isolated A', scoped=True)
assert any(row.get('type') == 'TextArea' and row.get('text') == drafts['a'] for row in rows())
device('shell', 'uitest', 'uiInput', 'keyEvent', 'Back')

after = directory()
assert len({entry['recovery'][0]['alias'] for entry in after['entries']}) == 2
assert {entry['credentialRef'] for entry in after['entries']} == {entry['credentialRef'] for entry in before['entries']}
counts = zero_business()
record = {'device': state['device'], 'checkedAt': datetime.datetime.now().astimezone().isoformat(), 'ordinaryProductTestEpoch': 109, 'bothConnected': True, 'homeShowsTwoIdenticalThreadIds': True, 'sameProjectAndThreadIds': True, 'aToBToAToBDraftIsolation': True, 'aDisabledWithoutLosingBDraft': True, 'aReenabledWithoutCodeAndADraftPreserved': True, 'distinctCredentialAndRecoveryReferences': True, 'messageSendClicked': False, 'serverCounts': counts, 'pairingEntry': 'manual explicit confirmation after implicit URI prefill; camera recognition not proven'}
(evidence / 'dual-product-ui-native.json').write_text(json.dumps(record, ensure_ascii=False, indent=2)+'\n')
state['unsentDraftA'] = drafts['a'];state['unsentDraftB'] = drafts['b'];state['dualProductDraftIsolationNative'] = True
state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2)+'\n')
print('PASS two real product environments: both ready, identical IDs, A-B-A-B drafts and references isolated; zero messages or runs')
