#!/usr/bin/env bash
# Manage the dev infrastructure (postgres, solr, S3 emulator, mailpit) via
# devbox services (process-compose native processes from nixpkgs + flake.nix).
# Actions: up | down | clean | logs | ps
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVBOX_ROOT="${DEVBOX_ROOT:-${SCRIPT_DIR}/..}"
DEVBOX_ROOT="${DEVBOX_ROOT:?DEVBOX_ROOT must resolve}"
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
# Values may come from .devbox/ports.env (persisted by a previous `up`) or an
# explicit caller env var; explicit vars always win the `:-` defaults below.
export PG_PORT="${PG_PORT:-5432}"
export SOLR_PORT="${SOLR_PORT:-8983}"
export S3_PORT="${S3_PORT:-4566}"
export SMTP_PORT="${SMTP_PORT:-1025}"
export MAILPIT_UI_PORT="${MAILPIT_UI_PORT:-8025}"

# --- Auto-relocate ports: a busy fixed port would make the native service fail
# to bind and process-compose would restart it forever. Detect before launch
# and shift to a free port instead; the chosen values are persisted so every
# consumer (backend, UI, mail via env.sh) keeps using the same ports for the
# rest of the session.
port_in_use() {
  (exec 3<>"/dev/tcp/127.0.0.1/${1}") 2>/dev/null
}

free_port_after() {
  local base="$1" c port
  for c in $(seq 1 20); do
    port=$((base + c))
    if ! port_in_use "${port}"; then
      echo "${port}"
      return 0
    fi
  done
  echo "${base}"
}

resolve_ports() {
  local spec name label p new
  for spec in \
    PG_PORT:Postgres \
    SOLR_PORT:Solr \
    S3_PORT:S3 \
    SMTP_PORT:SMTP \
    MAILPIT_UI_PORT:Mailpit; do
    name="${spec%%:*}"
    label="${spec##*:}"
    p="${!name}"
    if port_in_use "${p}"; then
      new="$(free_port_after "${p}")"
      if [ "${new}" = "${p}" ]; then
        echo "[infra] WARNING: port ${p} (${label}) is busy and no nearby port is free; leaving it." >&2
      else
        echo "[infra] port ${p} (${label}) is busy -> using ${new} instead"
        printf -v "${name}" '%s' "${new}"
        export "${name}=${new}"
      fi
    fi
  done
}

persist_ports() {
  cat > "${DEVBOX_DIR}/ports.env" <<EOF
PG_PORT=${PG_PORT}
SOLR_PORT=${SOLR_PORT}
S3_PORT=${S3_PORT}
SMTP_PORT=${SMTP_PORT}
MAILPIT_UI_PORT=${MAILPIT_UI_PORT}
EOF
}

# --- Stop helpers: `devbox services stop` can leave native daemons alive when
# process-compose was started with -t=false (no child termination on signal).
# Target the daemon first by project path in cmdline, then individual native
# processes by port + DEVBOX_DIR cmdline guard.
stop_process_compose() {
  devbox services stop 2>/dev/null || true
  local pids
  pids="$(pgrep -f "process-compose.*-f.*${DEVBOX_ROOT}" 2>/dev/null || true)"
  if [ -n "${pids}" ]; then
    echo "${pids}" | xargs -r kill -TERM 2>/dev/null || true
    sleep 1
    pids="$(pgrep -f "process-compose.*-f.*${DEVBOX_ROOT}" 2>/dev/null || true)"
    if [ -n "${pids}" ]; then
      echo "${pids}" | xargs -r kill -9 2>/dev/null || true
    fi
  fi
}

stop_native_daemons() {
  local pid is_ours
  local solr_port="${SOLR_PORT}"
  [ -f "${DEVBOX_DIR}/solr-data/.port" ] && read -r solr_port < "${DEVBOX_DIR}/solr-data/.port" 2>/dev/null || true
  # Kill native daemons whose DEVBOX_DIR env var matches ours. Check both the
  # current (possibly shifted) ports AND the original defaults — a leftover
  # from a previous session may still be bound to the default.
  local ports=("${PG_PORT}" "${solr_port}" "${S3_PORT}" "${MAILPIT_UI_PORT}")
  for p in 5432 8983 4566 1025 8025; do
    local found=0
    for ep in "${ports[@]}"; do
      [ "${ep}" = "${p}" ] && found=1 && break
    done
    [ "${found}" -eq 0 ] && ports+=("${p}")
  done
  for port in "${ports[@]}"; do
    pid="$(ss -ltnp "sport = :${port}" 2>/dev/null | sed -nE 's/.*pid=([0-9]+).*/\1/p' | head -1)"
    [ -n "${pid}" ] || continue
    is_ours="$(tr '\0' '\n' < "/proc/${pid}/environ" 2>/dev/null | rg -c "^DEVBOX_DIR=${DEVBOX_DIR}$" || true)"
    if [ "${is_ours}" -gt 0 ]; then
      kill "${pid}" 2>/dev/null || true
    fi
  done
}

action="${1:-up}"
case "${action}" in
  up)
    resolve_ports
    persist_ports
    devbox services up -b
    ;;
  down)
    stop_process_compose
    stop_native_daemons
    rm -f "${DEVBOX_DIR}/ports.env" "${DEVBOX_DIR}/solr-data/.port"
    ;;
  clean)
    stop_process_compose
    stop_native_daemons
    rm -f "${DEVBOX_DIR}/ports.env" "${DEVBOX_DIR}/solr-data/.port"
    rm -rf "${DEVBOX_DIR}/pgdata" "${DEVBOX_DIR}/solr-data" "${DEVBOX_DIR}/s3"
    ;;
  logs)   devbox services logs "${2:-db}" ;;
  ps)     devbox services ls ;;
  *)
    echo "usage: infra.sh <up|down|clean|logs [service]|ps>" >&2
    exit 1
    ;;
esac
