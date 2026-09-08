#!/usr/bin/env bash
# One-time setup: frontend node_modules + backend classpath.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
mkdir -p "${ROOT}/.devbox"

if [ ! -d "${ROOT}/dspace-angular/node_modules" ]; then
    echo "[init] npm ci in dspace-angular ..."
    (cd "${ROOT}/dspace-angular" && npm ci)
else
    echo "[init] angular node_modules present, skipping npm ci"
fi

echo "[init] compiling backend + building classpath ..."
bash "${SCRIPT_DIR}/lib/classpath.sh"

echo "[init] done. Next: 'devbox run infra:up' then 'devbox run backend' and 'devbox run ui'."