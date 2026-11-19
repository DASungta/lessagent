#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
DEVECO_HOME="${DEVECO_HOME:-/Applications/DevEco-Studio.app/Contents}"
export DEVECO_SDK_HOME="$DEVECO_HOME/sdk"
export JAVA_HOME="$DEVECO_HOME/jbr/Contents/Home"
export PATH="$DEVECO_HOME/tools/node/bin:$DEVECO_HOME/tools/ohpm/bin:$JAVA_HOME/bin:$PATH"
exec "$DEVECO_HOME/tools/hvigor/bin/hvigorw" --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap --no-daemon "$@"
