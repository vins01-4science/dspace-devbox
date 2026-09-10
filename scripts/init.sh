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

# Apply DB migrations when the infra DB is reachable: on a clean PGDATA the
# first backend boot would otherwise fail with Flyway "missing table".
# Flyway migrate is idempotent (only pending migrations are applied).
if pg_isready -h 127.0.0.1 -p "${PG_PORT:-5432}" >/dev/null 2>&1; then
    echo "[init] applying DB migrations (Flyway) ..."
    bash "${SCRIPT_DIR}/dspace-cli.sh" database migrate
else
    echo "[init] DB not reachable - skipping migrate (run 'devbox run infra-up' first, then 'bash scripts/dspace-cli.sh database migrate')"
fi

echo "[init] done. Next: 'devbox run infra-up' then 'devbox run backend' and 'devbox run ui'."