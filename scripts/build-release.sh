#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
DEVECO_HOME="${DEVECO_HOME:-/Applications/DevEco-Studio.app/Contents}"
RELEASE_ENV="${T3_RELEASE_ENV:-${HOME}/.ohos/release/com.dasungta.t3codebridge/release.env}"
if [ -f "$RELEASE_ENV" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$RELEASE_ENV"
  set +a
fi
for required in "${T3_RELEASE_STORE_FILE:-}" "${T3_RELEASE_CERT_PATH:-}" "${T3_RELEASE_PROFILE_PATH:-}"; do
  if [ -z "$required" ] || [ ! -f "$required" ]; then
    echo "Missing release signing artifact: ${required:-<unset>}" >&2
    exit 1
  fi
done
export DEVECO_SDK_HOME="$DEVECO_HOME/sdk"
export JAVA_HOME="$DEVECO_HOME/jbr/Contents/Home"
export PATH="$DEVECO_HOME/tools/node/bin:$DEVECO_HOME/tools/ohpm/bin:$JAVA_HOME/bin:$PATH"
"$DEVECO_HOME/tools/hvigor/bin/hvigorw" --mode project -p product=release -p buildMode=release assembleApp --no-daemon "$@"
echo "=== Release artifacts ==="
ls -lh build/outputs/release/*.app 2>/dev/null || find build -name "*.app" -exec ls -lh {} +
