#!/usr/bin/env bash
# Manage the dev infrastructure (postgres, solr, floci S3, mailpit) via
# `devbox services` (process-compose). The single `compose` process runs
# `docker compose up -d` on docker-compose.devbox.yml, which declares the
# whole stack; shutdown runs `docker compose down`.
# Actions: up | down | clean | logs | ps
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVBOX_ROOT="${SCRIPT_DIR}/.."
DEVBOX_DIR="${DEVBOX_ROOT}/.devbox"
export DEVBOX_ROOT DEVBOX_DIR
COMPOSE_FILE="${DEVBOX_ROOT}/docker-compose.devbox.yml"

# Source env.sh so DDEV_* defaults and ports are consistent.
# shellcheck source=lib/env.sh
source "${SCRIPT_DIR}/lib/env.sh" >/dev/null 2>&1 || true

# Per-worktree compose project tag + fixed default ports. These are passed
# to the `compose` process (and interpolated by docker-compose.devbox.yml).
export COMPOSE_TAG="${COMPOSE_TAG:-$(basename "${DEVBOX_ROOT}")}"
export DDEV_DBS="${DDEV_DBS:-dspace}"
export DDEV_CORES="${DDEV_CORES:-search,statistics,authority,oai,qaevent,suggestion,audit}"
export PG_PORT="${PG_PORT:-5432}"
export SOLR_PORT="${SOLR_PORT:-8983}"
export S3_PORT="${S3_PORT:-4566}"
export SMTP_PORT="${SMTP_PORT:-1025}"
export MAILPIT_UI_PORT="${MAILPIT_UI_PORT:-8025}"

action="${1:-up}"
case "${action}" in
  up)
    devbox services up -b
    ;;
  down)   devbox services stop ;;
  clean)
    devbox services stop
    docker compose -f "${COMPOSE_FILE}" down -v --remove-orphans
    ;;
  logs)   docker compose -f "${COMPOSE_FILE}" logs -f --tail=100 "${2:-db}" ;;
  ps)     docker compose -f "${COMPOSE_FILE}" ps ;;
  *)
    echo "usage: infra.sh <up|down|clean|logs|ps>" >&2
    exit 1
    ;;
esac
