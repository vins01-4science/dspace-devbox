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

echo "[solr] starting Solr on port ${SOLR_PORT} with cores: ${DDEV_CORES}"
export SOLR_OPTS="${SOLR_OPTS:--Dsolr.config.lib.enabled=true}"
exec solr start -f -p "${SOLR_PORT}" -s "${SOLR_HOME}" --host 127.0.0.1
