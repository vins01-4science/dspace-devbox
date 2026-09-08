#!/usr/bin/env bash
# Start the dspace-angular frontend (ng serve, hot reload) against the
# backend of the selected instance. Angular picks up the DSPACE_* vars below
# on top of config/config.dev.yml.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/env.sh"

cd "${DEVBOX_ROOT}/dspace-angular"

DEV_HOST="${DEV_HOST:-localhost}"
export NODE_ENV=development
export DSPACE_REST_HOST="${BACKEND_HOST:-${DEV_HOST}}"
export DSPACE_REST_PORT="${BACKEND_PORT}"
export DSPACE_REST_NAMESPACE="/server"
export DSPACE_REST_SSL="false"
export DSPACE_UI_HOST="${UI_HOST:-${DEV_HOST}}"
export DSPACE_UI_PORT="${UI_PORT}"
export DSPACE_UI_NAMESPACE="/"
export DSPACE_UI_SSL="false"

[ -d node_modules ] || {
    echo "[ui] node_modules missing - run 'devbox run init' first" >&2
    exit 1
}

echo "[ui] starting dspace-angular on http://${DEV_HOST}:${UI_PORT}/home -> REST http://${DEV_HOST}:${BACKEND_PORT}/server"
exec npm run start:dev