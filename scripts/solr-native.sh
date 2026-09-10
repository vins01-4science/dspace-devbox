#!/usr/bin/env bash
# Create the DSpace Solr cores from the DSpace configsets (native Solr install),
# then start Solr in the foreground. Replaces the former Docker-only
# scripts/solr-entrypoint.sh (removed together with docker-compose.devbox.yml).
set -euo pipefail

DEVBOX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVBOX_DIR="${DEVBOX_ROOT}/.devbox"
SOLR_HOME="${DEVBOX_DIR}/solr-data"
SOLR_PORT="${SOLR_PORT:-8983}"
SOLR_OPTS="${SOLR_OPTS:--Dsolr.config.lib.enabled=true}"
DDEV_CORES="${DDEV_CORES:-search,statistics,authority,oai,qaevent,suggestion,audit}"

mkdir -p "${SOLR_HOME}"

# Writable dirs for pid/console logs (the install dir is the read-only nix store)
export SOLR_PID_DIR="${SOLR_HOME}"
export SOLR_LOGS_DIR="${SOLR_HOME}/logs"
mkdir -p "${SOLR_PID_DIR}" "${SOLR_LOGS_DIR}"

# Copy DSpace configsets into the Solr home configsets/lib area if missing
CONFIGSETS_SRC="${DEVBOX_ROOT}/DSpace/dspace/solr"
if [ -d "${CONFIGSETS_SRC}" ] && [ ! -e "${SOLR_HOME}/configsets" ]; then
    echo "[solr] copying configsets into ${SOLR_HOME}/configsets"
    cp -r "${CONFIGSETS_SRC}" "${SOLR_HOME}/configsets"
fi

# The DSpace configsets ship a core.properties each; core auto-discovery scans
# the whole solr home, so those would register as duplicate cores. Remove them
# (idempotent, runs on every start).
find "${SOLR_HOME}/configsets" -name core.properties -delete 2>/dev/null || true

# Create one core per name, copying conf from the matching configset
IFS=',' read -ra CORES <<< "${DDEV_CORES}"
for core in "${CORES[@]}"; do
    [ -n "${core}" ] || continue
    name="${core#*-}"
    configset="${SOLR_HOME}/configsets/${name}"
    if [ ! -d "${configset}/conf" ]; then
        echo "WARNING: configset ${configset}/conf not found, skipping core ${core}" >&2
        continue
    fi
    if [ -d "${SOLR_HOME}/${core}" ]; then
        echo "core ${core} already exists, skipping"
        continue
    fi
    echo "creating core ${core} from configset '${name}'"
    mkdir -p "${SOLR_HOME}/${core}/conf"
    cp -r "${configset}/conf/." "${SOLR_HOME}/${core}/conf/"
    touch "${SOLR_HOME}/${core}/core.properties"
    echo "name=${core}" > "${SOLR_HOME}/${core}/core.properties"
done

# Auto-relocate when the configured port is already taken (another Solr/app on
# this host). The `solr` start script would otherwise fail to bind and die, and
# process-compose `restart: always` would loop it forever. The chosen port is
# recorded in .port so this script's consumers (readiness probe, shutdown,
# backend wiring in lib/env.sh) can follow it regardless of entrypoint.
port_in_use() {
  (exec 3<>"/dev/tcp/127.0.0.1/${1}") 2>/dev/null
}
if port_in_use "${SOLR_PORT}"; then
  NEW_SOLR_PORT="${SOLR_PORT}"
  for c in $(seq 1 20); do
    if ! port_in_use $((SOLR_PORT + c)); then
      NEW_SOLR_PORT=$((SOLR_PORT + c))
      break
    fi
  done
  if [ "${NEW_SOLR_PORT}" = "${SOLR_PORT}" ]; then
    echo "[solr] ERROR: port ${SOLR_PORT} is busy and no free port in +1..+20 was found; aborting." >&2
    exit 1
  fi
  echo "[solr] port ${SOLR_PORT} is busy -> using ${NEW_SOLR_PORT} instead"
  SOLR_PORT="${NEW_SOLR_PORT}"
fi
echo "${SOLR_PORT}" > "${SOLR_HOME}/.port"

# Keep .devbox/ports.env (persisted by `infra.sh up`) in sync so the two port
# sources never diverge when Solr relocates under a bare `devbox services up`.
if [ -f "${DEVBOX_ROOT}/.devbox/ports.env" ]; then
    sed -i "s|^SOLR_PORT=.*|SOLR_PORT=${SOLR_PORT}|" "${DEVBOX_ROOT}/.devbox/ports.env" 2>/dev/null || true
fi

echo "[solr] starting Solr on port ${SOLR_PORT} with cores: ${DDEV_CORES}"
export SOLR_OPTS="${SOLR_OPTS:--Dsolr.config.lib.enabled=true}"
exec solr start -f -p "${SOLR_PORT}" -s "${SOLR_HOME}" --host 127.0.0.1
