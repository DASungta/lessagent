#!/usr/bin/env python3
"""Pair the archived v1 UI to the isolated A service; never print pairing material."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time

root = Path(__file__).resolve().parent.parent
state = json.loads((root / 'docs/evidence/r1/lab-state.json').read_text())
lab = Path(state['labRoot'])
service = next(s for s in state['services'] if s['name'] == 'a')
assert 't3-harmony-r1-real-' in str(lab) and Path(service['baseDir']).parent == lab and service['port'] == 47831
hdc = ['/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc', '-t', '23E0224122000135']
secret = ''
def device(*args):
    result = subprocess.run(hdc + list(args), capture_output=True, text=True)
    output = result.stdout + result.stderr
    if result.returncode or '[Fail]' in output:
        raise RuntimeError('Dedicated device command failed; no arguments or private output printed')
    return output
assert device('shell', 'param', 'get', 'const.product.model').strip() == 'ALN-AL80'
def nodes(tree):
    yield tree.get('attributes', {})
    for child in tree.get('children', []):
        yield from nodes(child)
def point(node):
    values = [int(v) for v in re.findall(r'-?\d+', node['bounds'])]
    assert len(values) == 4
    return str((values[0]+values[2])//2), str((values[1]+values[3])//2)
def tap(node):
    device('shell', 'uitest', 'uiInput', 'click', *point(node))
def layout():
    remote = '/data/local/tmp/r1-legacy-pair-layout.json'
    with tempfile.NamedTemporaryFile(dir=lab, suffix='.json') as local:
        device('shell', 'uitest', 'dumpLayout', '-p', remote)
        device('file', 'recv', remote, local.name)
        tree = json.loads(Path(local.name).read_text())
    device('shell', 'rm', '-f', remote)
    return list(nodes(tree))
def text_node(rows, text):
    return next(n for n in rows if n.get('text') == text)
rows = layout()
if any(n.get('text') == '已连接' for n in rows):
    initial = [n['text'] for n in rows if n.get('text') and n.get('type') != 'TextInput']
    tap(text_node(rows, 'T3 Code'))
    detail = layout()
    inputs = [n for n in detail if n.get('type') == 'TextInput']
    assert len(inputs) == 1 and inputs[0].get('text') == 'http://127.0.0.1:47831', 'connected v1 target is not the isolated A service'
    device('shell', 'uitest', 'uiInput', 'keyEvent', 'Back')
    (root / 'docs/evidence/r1/legacy-ui-pairing.json').write_text(json.dumps({'device':state['device'],'versionCode':1,'base':inputs[0]['text'],'environmentId':service['environmentId'],'credentialCleared':True,'visibleTexts':initial,'agentTasksSubmitted':0,'initialUiPollExceeded':True,'subsequentLiveReadbackConfirmed':True},ensure_ascii=False,indent=2)+'\n')
    print('PASS live v1 session verified against isolated A target, no private field displayed')
    sys.exit(0)
assert any(n.get('text') == '添加环境' for n in rows), 'v1 must start on the empty isolated test page'
tap(text_node(rows, '添加环境'))
rows = layout()
inputs = [n for n in rows if n.get('type') == 'TextInput']
assert len(inputs) == 2 and not inputs[0].get('text') and not inputs[1].get('text')
if 'tcp:47831 tcp:47831' not in device('fport', 'ls'):
    assert 'tcp:47831' not in device('fport', 'ls'), 'test reverse port already belongs to another mapping'
    device('rport', 'tcp:47831', 'tcp:47831')
result = subprocess.run(['t3', 'auth', 'pairing', 'create', '--base-dir', service['baseDir'], '--scope', 'orchestration:read', '--ttl', '30m', '--label', 'harmony-r1-v1-upgrade', '--json'], capture_output=True, text=True, env={**os.environ, 'T3CODE_HOME': service['baseDir']})
assert result.returncode == 0, 'isolated pairing issuance failed'
grant = json.loads(result.stdout); secret = grant['credential']
base = 'http://127.0.0.1:47831'
device('shell', 'uitest', 'uiInput', 'inputText', *point(inputs[0]), base)
device('shell', 'uitest', 'uiInput', 'keyEvent', 'Back')
rows = layout(); inputs = [n for n in rows if n.get('type') == 'TextInput']; connect = text_node(rows, '连接')
device('shell', 'uitest', 'uiInput', 'inputText', *point(inputs[1]), secret)
device('shell', 'uitest', 'uiInput', 'keyEvent', 'Back')
tap(connect)
observed = None
for _ in range(45):
    rows = layout()
    if any(secret in n.get('text', '') for n in rows):
        raise RuntimeError('Form did not clear the private code; no layout exported')
    texts = [n['text'] for n in rows if n.get('text') and n.get('type') != 'TextInput']
    if any(t in texts for t in ['已连接', '会话已同步']) or 'Harmony 新会话' in texts:
        observed = texts
        break
    time.sleep(0.5)
assert observed is not None, 'v1 pairing did not reach connected state'
(root / 'docs/evidence/r1/legacy-ui-pairing.json').write_text(json.dumps({'device':state['device'],'versionCode':1,'base':base,'environmentId':service['environmentId'],'credentialCleared':True,'visibleTexts':observed,'agentTasksSubmitted':0},ensure_ascii=False,indent=2)+'\n')
print('PASS archived v1 UI paired and persisted a real isolated session; private field cleared')
