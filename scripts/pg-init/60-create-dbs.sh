#!/usr/bin/env bash
# Create one PostgreSQL database per DSpace dev instance (idempotent).
set -e
set -u

IFS=',' read -ra DBS <<< "${DDEV_DBS:-dspace1,dspace2}"

for db in "${DBS[@]}"; do
    dbname="$(echo "${db}" | xargs)"
    [ -n "${dbname}" ] || continue
    if psql -v ON_ERROR_STOP=1 -U "${POSTGRES_USER}" -d postgres -tAc \
           "SELECT 1 FROM pg_database WHERE datname='${dbname}'" | grep -q 1; then
        echo "database ${dbname} already exists"
    else
        echo "creating database ${dbname} (owner ${POSTGRES_USER})"
        psql -v ON_ERROR_STOP=1 -U "${POSTGRES_USER}" -d postgres \
             -c "CREATE DATABASE ${dbname} OWNER ${POSTGRES_USER};"
    fi
done