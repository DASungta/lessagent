#!/usr/bin/env python3
"""Build a temporary on-device test HAP, restoring production entry points even on failure."""
from pathlib import Path
import shutil
import subprocess
import argparse
parser = argparse.ArgumentParser()
parser.add_argument("--source", default="scripts/device-checks/DeviceCheck.ets")
parser.add_argument("--app-version-file")
parser.add_argument("--output", default="docs/evidence/r1/device-check-signed.hap")
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
ability = root / 'entry/src/main/ets/entryability/EntryAbility.ets'
pages = root / 'entry/src/main/resources/base/profile/main_pages.json'
target = root / 'entry/src/main/ets/pages/DeviceCheck.ets'
if target.exists():
    raise SystemExit('DeviceCheck target already exists; refusing overwrite')
files = [ability, pages]
if args.app_version_file:
    files.append(root / 'AppScope/app.json5')
original = {p: p.read_bytes() for p in files}
try:
    if args.app_version_file:
        (root / 'AppScope/app.json5').write_bytes((root / args.app_version_file).read_bytes())
    target.write_bytes((root / args.source).read_bytes())
    pages.write_text('{"src":["pages/DeviceCheck"]}\n')
    ability.write_text("""import { UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
export default class EntryAbility extends UIAbility {
  onWindowStageCreate(stage: window.WindowStage): void {
    void stage.loadContent('pages/DeviceCheck').then(() => stage.getMainWindowSync().setWindowKeepScreenOn(true));
  }
}
""")
    subprocess.run([str(root / 'scripts/build.sh')], cwd=root, check=True)
    shutil.copyfile(root / 'entry/build/default/outputs/default/entry-default-signed.hap', root / args.output)
finally:
    for p, data in original.items():
        p.write_bytes(data)
        assert p.read_bytes() == data, f"Failed to restore {p}"
    target.unlink(missing_ok=True)
    assert not target.exists()
