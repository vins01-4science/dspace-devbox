#!/usr/bin/env bash
# Run a DSpace CLI command (ScriptLauncher) inside the selected instance env.
# Examples:
#   devbox run cli -- create-administrator -e admin@dspace.org -f Admin -l User -p admin123 -c en
#   devbox run cli -- help
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTANCE="${INSTANCE:-1}"
export INSTANCE
source "${SCRIPT_DIR}/lib/env.sh"
source "${SCRIPT_DIR}/lib/classpath.sh"

[ -f "${DEVBOX_DIR}/full-cp.txt" ] || {
    echo "[cli] classpath missing - run 'devbox run init' first" >&2
    exit 1
}

exec java \
    -XX:TieredStopAtLevel=1 \
    -XX:+UseSerialGC \
    -Xms128m \
    -Xmx1536m \
    -XX:MaxMetaspaceSize=512m \
    -XX:ReservedCodeCacheSize=128m \
    -Djava.net.preferIPv4Stack=true \
    -Dfile.encoding=UTF-8 \
    -Ddspace.dir="${DEVBOX_ROOT}/DSpace/dspace" \
    -cp "$(cat "${DEVBOX_DIR}/full-cp.txt")" \
    org.dspace.app.launcher.ScriptLauncher "$@"