#!/usr/bin/env bash
# Start PostgreSQL natively for devbox. Initializes the data dir on first run
# (superuser 'dspace', trust auth for local dev) and ensures the 'dspace' DB
# exists. Runs postgres in the foreground.
set -euo pipefail

DEVBOX_DIR="${DEVBOX_DIR:?DEVBOX_DIR must be set}"
PG_PORT="${PG_PORT:-5432}"
PGDATA="${DEVBOX_DIR}/pgdata"
export PGHOST=127.0.0.1
export PGPORT="${PG_PORT}"
PGDATABASE="dspace"
PGUSER="dspace"

mkdir -p "${DEVBOX_DIR}"

# Initialize if needed
if [ ! -f "${PGDATA}/PG_VERSION" ]; then
    echo "[db] Initializing PostgreSQL data directory at ${PGDATA}"
    initdb -D "${PGDATA}" --username="${PGUSER}" --auth=trust --encoding=UTF8 --locale=C
fi

# Ensure listen_addresses / port / unix_socket_directories are set (idempotent:
# conf survives restarts, so only append what's missing)
ensure_conf() {
    local key="$1" value="$2"
    if ! grep -qE "^${key}[[:space:]]*=" "${PGDATA}/postgresql.conf" 2>/dev/null; then
        echo "${key} = ${value}" >> "${PGDATA}/postgresql.conf"
    fi
}
ensure_conf "listen_addresses" "'127.0.0.1'"
ensure_conf "port" "${PG_PORT}"
ensure_conf "unix_socket_directories" "'/tmp'"

# Ensure the application database exists (postgres must be up for this; start a
# throwaway instance if it's not already running)
started_marker="${PGDATA}/.db-started"
if [ ! -f "${started_marker}" ]; then
    echo "[db] booting throwaway postgres to provision database(s)..."
    pg_ctl -D "${PGDATA}" -o "-c listen_addresses=127.0.0.1 -c port=${PG_PORT}" -w start
    IFS=',' read -ra DBS <<< "${DDEV_DBS:-dspace}"
    for db in "${DBS[@]}"; do
        dbname="$(echo "${db}" | xargs)"
        [ -n "${dbname}" ] || continue
        if ! psql -h 127.0.0.1 -p "${PG_PORT}" -U "${PGUSER}" -d postgres -tAc \
             "SELECT 1 FROM pg_database WHERE datname='${dbname}'" | grep -q 1; then
            echo "[db] creating database ${dbname}"
            createdb -h 127.0.0.1 -p "${PG_PORT}" -U "${PGUSER}" "${dbname}"
        fi
    done
    pg_ctl -D "${PGDATA}" stop -m fast
    touch "${started_marker}"
fi

# Run postgres in the foreground
exec postgres -D "${PGDATA}" -c "listen_addresses=127.0.0.1" -c "port=${PG_PORT}"
