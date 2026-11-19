"""Prepare a temporary same-bundle sender build for a multi-record ShareKit smoke test."""
import shutil
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[4]
stage = Path(tempfile.mkdtemp(prefix='t3-share-sender-'))
for name in ('build-profile.json5', 'oh-package.json5', 'hvigorfile.ts', 'oh_modules'):
    (stage / name).symlink_to(root / name)
for name in ('hvigor', 'AppScope'):
    shutil.copytree(root / name, stage / name)
shutil.copytree(root / 'entry', stage / 'entry', ignore=shutil.ignore_patterns('build', '.cxx', 'oh_modules'))
(stage / 'entry/oh_modules').mkdir()
(stage / 'entry/oh_modules/libt3device.so').symlink_to('../src/main/cpp/types/libt3device')
(stage / 'scripts').mkdir()
shutil.copy2(root / 'scripts/build.sh', stage / 'scripts/build.sh')
page = stage / 'entry/src/main/ets/pages/Index.ets'
source = page.read_text()
original = "const data = new systemShare.SharedData({ utd: 'general.plain-text', content: value });"
assert source.count(original) == 1
page.write_text(source.replace(original, """const data = new systemShare.SharedData({ utd: 'general.plain-text', content: 'B37 first note' });
      data.addRecord({ utd: 'general.hyperlink', content: 'https://example.org/b37-target' });
      data.addRecord({ utd: 'general.plain-text', content: 'B37 first note' });"""))
print(stage)
