#!/usr/bin/env python3
"""Build the archived v1 writer in a private temporary project; never replace the working tree."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import tarfile
import tempfile

root = Path(__file__).resolve().parent.parent
output = Path('/tmp/r1-legacy-v1-signed.hap')
archive = root / 'docs/evidence/r1/pre-r1-source.tar.gz'
with tempfile.TemporaryDirectory(prefix='t3-harmony-v1-build-') as temporary:
    sandbox = Path(temporary)
    for name in ['AppScope', 'entry', 'hvigor']:
        shutil.copytree(root / name, sandbox / name, ignore=shutil.ignore_patterns('build', '.hvigor'))
    for name in ['build-profile.json5', 'hvigorfile.ts', 'oh-package.json5']:
        shutil.copy2(root / name, sandbox / name)
    (sandbox / 'scripts').mkdir()
    shutil.copy2(root / 'scripts/build.sh', sandbox / 'scripts/build.sh')
    shutil.rmtree(sandbox / 'entry/src/main/ets')
    with tarfile.open(archive) as source:
        members = [member for member in source.getmembers() if member.name.startswith('entry/src/main/ets/')]
        assert members and all(member.isfile() or member.isdir() for member in members)
        source.extractall(sandbox, members=members, filter='data')
    entry = (sandbox / 'entry/src/main/ets/entryability/EntryAbility.ets').read_text()
    assert 'new SessionStore()' in entry and 'prepareEnvironments' not in entry
    assert 't3-harmony-recovery-v1' in entry
    entry = "import { hilog } from '@kit.PerformanceAnalysisKit';\n" + entry
    original = 'stage.getMainWindowSync().getUIContext()'
    replacement = "void stage.getMainWindowSync().setWindowKeepScreenOn(true).then(() => hilog.info(0x0000, 'R1KeepAwake', 'legacyWindowKeepScreenOn=%{public}s', String(stage.getMainWindowSync().getWindowProperties().isKeepScreenOn)));\n      " + original
    assert entry.count(original) == 1
    (sandbox / 'entry/src/main/ets/entryability/EntryAbility.ets').write_text(entry.replace(original, replacement))
    shutil.copy2(root / 'docs/evidence/r1/pre-upgrade-app.json', sandbox / 'AppScope/app.json5')
    module = sandbox / 'entry/src/main/module.json5'
    manifest = json.loads(module.read_text())
    manifest['module']['requestPermissions'] = [{'name': 'ohos.permission.INTERNET'}]
    manifest['module']['abilities'][0]['skills'] = [{'entities': ['entity.system.home'], 'actions': ['action.system.home']}]
    module.write_text(json.dumps(manifest, indent=2) + '\n')
    subprocess.run([str(sandbox / 'scripts/build.sh')], cwd=sandbox, check=True)
    shutil.copyfile(sandbox / 'entry/build/default/outputs/default/entry-default-signed.hap', output)
    assert output.is_file() and output.stat().st_size > 0
    record = {'sourceArchiveSha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
              'artifactSha256': hashlib.sha256(output.read_bytes()).hexdigest(),
              'artifactPath': str(output), 'kind': 'archived actual v1 startup and UI',
              'productionSourceChanged': False, 'temporaryForegroundKeepScreenOn': True}
    (root / 'docs/evidence/r1/legacy-build.json').write_text(json.dumps(record, indent=2) + '\n')
