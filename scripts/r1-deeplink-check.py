#!/usr/bin/env python3
"""Verify native cold/warm URI prefill using an owned, unconsumed read-only test grant."""
import datetime
import json
from pathlib import Path
import re
import sqlite3
import subprocess
import tempfile
from urllib.parse import quote

root = Path(__file__).resolve().parent.parent
evidence = root / 'docs/evidence/r1'
state = json.loads((evidence / 'lab-state.json').read_text())
lab = Path(state['labRoot'])
assert lab.name.startswith('t3-harmony-r1-real-')
device_id = '23E0224122000135'
assert state['device'] == device_id
bundle = 'com.dasungta.t3code.harmony'
hdc = '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc'

def device(*args):
    result = subprocess.run([hdc, '-t', device_id, *args], capture_output=True, text=True)
    if result.returncode or '[Fail]' in result.stdout:
        raise RuntimeError('Native action failed; arguments omitted')
    return result.stdout

assert device('shell', 'param', 'get', 'const.product.model').strip() == 'ALN-AL80'
grant = json.loads((lab / 'deeplink-grant-private.json').read_text())
assert grant['scopes'] == ['orchestration:read']
base = 'http://192.168.10.75:47832'
uri = 't3code://pair?pairingUrl=' + quote(base + '/#token=' + grant['credential'], safe='')

def rows():
    remote = '/data/local/tmp/r1-deeplink-owned.json'
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

def directory():
    with tempfile.TemporaryDirectory(dir=lab) as temporary:
        local = Path(temporary) / 'directory.json'
        device('file', 'recv', '-b', bundle, '/data/storage/el2/base/haps/entry/files/environments-v2.json', str(local))
        return local.read_bytes()

def unconsumed():
    database = Path(state['services'][1]['baseDir']) / 'userdata/statev2.sqlite'
    with sqlite3.connect(database.as_uri() + '?mode=ro', uri=True) as connection:
        row = connection.execute('select consumed_at, revoked_at from auth_pairing_links where id=?', (grant['id'],)).fetchone()
    assert row == (None, None), 'The dedicated URI test grant must remain unused'

def open_uri(value):
    result = device('shell', 'aa', 'start', '-A', 'ohos.want.action.viewData', '-e', 'entity.system.browsable', '-U', value, '--pb', 'r1KeepAwake', 'true')
    assert 'start ability successfully' in result, 'The registered native URI must resolve'

before = directory()
unconsumed()
results = []
for mode in ['warm', 'cold']:
    previous_pid = device('shell', 'pidof', bundle).strip()
    if mode == 'cold':
        device('shell', 'aa', 'force-stop', bundle)
    open_uri(uri)
    device('shell', 'uitest', 'uiInput', 'swipe', '900', '2360', '900', '1530')
    snapshot = rows()
    inputs = [row for row in snapshot if row.get('type') == 'TextInput']
    assert len(inputs) == 2 and any(row.get('text') == base for row in inputs), 'Pairing address was not staged'
    assert any(row.get('text') == '请确认目标后添加环境' for row in snapshot), 'Explicit confirmation prompt missing'
    assert directory() == before
    unconsumed()
    current_pid = device('shell', 'pidof', bundle).strip()
    assert (current_pid != previous_pid) == (mode == 'cold')
    results.append({'mode': mode, 'systemUriResolved': True, 'addressStaged': True, 'confirmationVisible': True, 'directoryUnchanged': True, 'grantUnconsumed': True, 'newProcess': mode == 'cold'})

open_uri('t3code://pair?pairingUrl=javascript%3Aalert%281%29')
snapshot = rows()
assert any(row.get('text') == '配对链接无效，请检查后重新打开' for row in snapshot)
assert directory() == before
unconsumed()
record = {'device': device_id, 'checkedAt': datetime.datetime.now().astimezone().isoformat(), 'ordinaryProductTestEpoch': 109, 'results': results, 'maliciousInnerUrlRejected': True, 'noAutomaticPairing': True, 'cameraRecognitionProven': False}
(evidence / 'deeplink-native.json').write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n')
print('PASS native warm/cold implicit URI prefill and malicious URL rejection; grant unconsumed, directory unchanged')
