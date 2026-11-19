#!/bin/bash
set -euo pipefail
umask 077
fixture_dir="$(cd "$(dirname "$0")" && pwd)"
sdk="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
build_tools="$sdk/build-tools/${BUILD_TOOLS_VERSION:-36.0.0}"
android_jar="$sdk/platforms/${ANDROID_PLATFORM:-android-37.0}/android.jar"
export JAVA_HOME="${JAVA_HOME:-$(/usr/libexec/java_home)}"
export PATH="$JAVA_HOME/bin:$PATH"
for tool in aapt2 d8 zipalign apksigner; do test -x "$build_tools/$tool"; done
test -f "$android_jar"
python3 - "$fixture_dir" <<'PY'
import pathlib, sys, xml.etree.ElementTree as ET
base = pathlib.Path(sys.argv[1])
manifest = ET.parse(base / 'AndroidManifest.xml').getroot()
assert manifest.attrib['package'] == 'com.dasungta.harmony.previewfixture'
assert not list(manifest.iter('uses-permission'))
ns = '{http://schemas.android.com/apk/res/android}'
assert manifest.find('application').attrib[ns + 'allowBackup'] == 'false'
assert manifest.find('uses-sdk').attrib[ns + 'minSdkVersion'] == '23'
source = (base / 'src/com/dasungta/harmony/previewfixture/MainActivity.java').read_text()
for required in ['handler.removeCallbacks(tick)', 'SCREEN_ORIENTATION_PORTRAIT',
                 'SCREEN_ORIENTATION_LANDSCAPE', 'new EditText(this)', 'onSaveInstanceState']:
    assert required in source, required
print('Source/manifest self-check passed (not a runtime test).')
PY
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/harmony-preview-fixture.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
mkdir "$build_dir/classes" "$build_dir/dex"
javac --release 8 -classpath "$android_jar" -d "$build_dir/classes" \
    "$fixture_dir/src/com/dasungta/harmony/previewfixture/MainActivity.java"
class_files=("$build_dir/classes/com/dasungta/harmony/previewfixture/"*.class)
"$build_tools/d8" --min-api 23 --lib "$android_jar" --output "$build_dir/dex" "${class_files[@]}"
"$build_tools/aapt2" link -I "$android_jar" --manifest "$fixture_dir/AndroidManifest.xml" -o "$build_dir/unsigned.apk"
(cd "$build_dir/dex" && zip -q "$build_dir/unsigned.apk" classes.dex)
"$build_tools/zipalign" -f 4 "$build_dir/unsigned.apk" "$build_dir/aligned.apk"
# A fresh disposable signing key makes each build installable without using any existing identity.
export FIXTURE_KEY_PASSWORD="$(openssl rand -hex 24)"
keytool -genkeypair -keystore "$build_dir/test-key.p12" -storetype PKCS12 \
    -storepass:env FIXTURE_KEY_PASSWORD -keypass:env FIXTURE_KEY_PASSWORD \
    -alias fixture -keyalg RSA -keysize 2048 -validity 2 \
    -dname 'CN=Disposable Harmony Preview Test' >/dev/null 2>&1
"$build_tools/apksigner" sign --ks "$build_dir/test-key.p12" --ks-key-alias fixture \
    --ks-pass env:FIXTURE_KEY_PASSWORD --key-pass env:FIXTURE_KEY_PASSWORD \
    --out "$build_dir/preview-fixture.apk" "$build_dir/aligned.apk"
unset FIXTURE_KEY_PASSWORD
"$build_tools/apksigner" verify --verbose "$build_dir/preview-fixture.apk"
"$build_tools/zipalign" -c 4 "$build_dir/preview-fixture.apk"
"$build_tools/aapt2" dump badging "$build_dir/preview-fixture.apk" > "$build_dir/badging.txt"
python3 - "$build_dir" <<'PY'
import pathlib, sys, zipfile
base = pathlib.Path(sys.argv[1])
badging = (base / 'badging.txt').read_text()
assert "package: name='com.dasungta.harmony.previewfixture'" in badging
assert "launchable-activity: name='com.dasungta.harmony.previewfixture.MainActivity'" in badging
assert 'uses-permission:' not in badging
with zipfile.ZipFile(base / 'preview-fixture.apk') as apk:
    assert apk.testzip() is None
    assert {'AndroidManifest.xml', 'classes.dex'} <= set(apk.namelist())
    assert not any(name.endswith(('.p12', '.jks', '.pem', '.key')) for name in apk.namelist())
print('APK package, launcher, permissions, contents and ZIP self-check passed.')
PY
cp "$build_dir/preview-fixture.apk" "$fixture_dir/preview-fixture.apk"
shasum -a 256 "$fixture_dir/preview-fixture.apk"
printf 'Built: %s\n' "$fixture_dir/preview-fixture.apk"
