#!/usr/bin/env bash
# Manage the dev infrastructure (postgres, solr, floci S3, mailpit) via
# devbox services (process-compose native processes from nixpkgs + flake.nix).
# Actions: up | down | clean | logs | ps
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVBOX_ROOT="${SCRIPT_DIR}/.."
DEVBOX_DIR="${DEVBOX_ROOT}/.devbox"
export DEVBOX_ROOT DEVBOX_DIR

# Source env.sh so DDEV_* defaults and ports are consistent.
# shellcheck source=lib/env.sh
source "${SCRIPT_DIR}/lib/env.sh" >/dev/null 2>&1 || true

# Single shared database + the 7 main solr cores (search, statistics, authority,
# oai, qaevent, suggestion, audit). Override via env to expose ports on a range.
export DDEV_DBS="${DDEV_DBS:-dspace}"
export DDEV_CORES="${DDEV_CORES:-search,statistics,authority,oai,qaevent,suggestion,audit}"

# Choose fixed default ports for the native services (no random compose ports now).
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
  clean)  devbox services stop && rm -rf "${DEVBOX_DIR}/pgdata" "${DEVBOX_DIR}/solr-data" "${DEVBOX_DIR}/floci" ;;
  logs)   devbox services attach db ;;
  ps)     devbox services ls ;;
  *)
    echo "usage: infra.sh <up|down|clean|logs|ps>" >&2
    exit 1
    ;;
esac
