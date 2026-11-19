#!/usr/bin/env python3
"""Dedicated-phone checks after the actual upgrade, using only the owned lab fixture."""
import json
import argparse
parser=argparse.ArgumentParser()
parser.add_argument("--continue-after-ack",action="store_true")
args=parser.parse_args()
from pathlib import Path
import re
import subprocess
import tempfile
import time
root=Path(__file__).resolve().parent.parent
evidence=root/'docs/evidence/r1';state=json.loads((evidence/'lab-state.json').read_text());lab=Path(state['labRoot'])
hdc=['/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc','-t','23E0224122000135']
def device(*args):
 r=subprocess.run(hdc+list(args),capture_output=True,text=True)
 if r.returncode or '[Fail]' in r.stdout:raise RuntimeError('Dedicated device UI check failed; arguments omitted')
 return r.stdout
def tree_nodes(tree):
 yield tree.get('attributes',{})
 for child in tree.get('children',[]):yield from tree_nodes(child)
def layout():
 with tempfile.NamedTemporaryFile(dir=lab,suffix='.json') as local:
  device('shell','uitest','dumpLayout','-p','/data/local/tmp/r1-owned-ui.json');device('file','recv','/data/local/tmp/r1-owned-ui.json',local.name)
  rows=list(tree_nodes(json.loads(Path(local.name).read_text())))
 device('shell','rm','-f','/data/local/tmp/r1-owned-ui.json');return rows
def tap(name,last=False):
 rows=layout();matches=[n for n in rows if n.get('text')==name or n.get('description')==name];assert matches,'expected native control missing'
 n=matches[-1] if last else matches[0];a=list(map(int,re.findall(r'-?\d+',n['bounds'])));device('shell','uitest','uiInput','click',str((a[0]+a[2])//2),str((a[1]+a[3])//2))
def directory():
 with tempfile.NamedTemporaryFile(dir=lab,suffix='.json') as local:
  device('file','recv','-b','com.dasungta.t3code.harmony','/data/storage/el2/base/haps/entry/files/environments-v2.json',local.name)
  return json.loads(Path(local.name).read_text())
def texts(rows):return [n['text'] for n in rows if n.get('text') and n.get('type')!='TextInput']
assert device('shell','param','get','const.product.model').strip()=='ALN-AL80'
audit=json.loads((evidence/'upgrade-protected-audit.json').read_text());assert audit['pendingId']=='r1-synthetic-unconfirmed'
fixtures=json.loads((evidence/'real-collision-fixtures.json').read_text());assert all(x['messages']==0 and x['providerTurns']==0 and x['runs']==0 and x['providerSessions']==0 for x in fixtures['results'])
for _ in range(30):
 rows=layout();display=texts(rows)
 if 'Harmony 新会话' in display and (args.continue_after_ack or any('上次提交结果未知' in t for t in display)):break
 time.sleep(.5)
else:raise RuntimeError('upgraded session did not restore its owned pending marker')
assert '所有项目' in display,'active thread project leaked into the home filter'
before=directory();assert len(before['entries'])==1 and before['entries'][0]['localId']=='legacy-v1'
if not args.continue_after_ack:
 tap('T3 Code');tap(before['entries'][0]['label']);tap('移除');tap('移除',last=True)
 blocked=texts(layout());assert any('正在提交或结果未知' in t for t in blocked);assert directory()==before
 (evidence/'upgrade-unknown-remove-exact.json').write_text(json.dumps({'directoryExactlyUnchanged':True,'texts':blocked},ensure_ascii=False,indent=2)+'\n')
 device('shell','uitest','uiInput','keyEvent','Back');tap('Harmony 新会话');tap('已核对提交结果')
 rows=layout();assert '核对上次提交' not in texts(rows);after=directory();assert after['generation']==before['generation']+1
else:
 assert json.loads((evidence/'upgrade-ack-and-draft.json').read_text())['ownedSyntheticMarkerAcknowledged']
 assert not any('上次提交结果未知' in t for t in display)
 tap('Harmony 新会话');rows=layout();after=directory()
area=next(n for n in rows if n.get('type')=='TextArea');a=list(map(int,re.findall(r'-?\d+',area['bounds'])))
device('shell','uitest','uiInput','inputText',str((a[0]+a[2])//2),str((a[1]+a[3])//2),'R1_A_UNSENT_ONLY')
device('shell','uitest','uiInput','keyEvent','Back');rows=layout();assert any(n.get('type')=='TextArea' and n.get('text')=='R1_A_UNSENT_ONLY' for n in rows)
(evidence/'upgrade-ack-and-draft.json').write_text(json.dumps({'ownedSyntheticMarkerAcknowledged':True,'draft':'R1_A_UNSENT_ONLY','messageSent':False,'generationAfterAck':after['generation']},indent=2)+'\n')
device('shell','uitest','uiInput','keyEvent','Back');tap('T3 Code');tap('+')
rows=layout();assert '添加环境' in texts(rows) and '允许相机扫码' in texts(rows)
print('PASS exact unknown-removal protection, owned marker acknowledgement, scoped unsent draft; add page ready')
