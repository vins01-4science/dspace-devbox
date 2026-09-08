#!/usr/bin/env bash
# Manage the dev infrastructure (postgres, solr, floci S3, mailpit).
# Actions: up | down | clean | logs | ps
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE="${SCRIPT_DIR}/../docker-compose.devbox.yml"

# Single shared database + the 7 main solr cores (search, statistics, authority,
# oai, qaevent, suggestion, audit). All backend instances share these; only the
# backend/UI ports differ. Override via env to expose ports on a range.
export DDEV_DBS="${DDEV_DBS:-dspace}"
export DDEV_CORES="${DDEV_CORES:-search,statistics,authority,oai,qaevent,suggestion,audit}"

action="${1:-up}"
case "${action}" in
  up)
    docker compose -f "${COMPOSE}" up -d --wait
    docker compose -f "${COMPOSE}" ps
    ;;
  down)   docker compose -f "${COMPOSE}" down ;;
  clean)  docker compose -f "${COMPOSE}" down -v ;;
  logs)   docker compose -f "${COMPOSE}" logs -f ;;
  ps)     docker compose -f "${COMPOSE}" ps ;;
  *)
    echo "usage: infra.sh <up|down|clean|logs|ps>" >&2
    exit 1
    ;;
esac