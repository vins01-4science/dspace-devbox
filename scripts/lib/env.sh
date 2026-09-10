#!/usr/bin/env bash
# DSpace dev environment. Source me, then run the backend/UI/CLI scripts.
# Set INSTANCE=<n> (default 1) to run multiple backend/UI pairs in parallel.
#
# PORT MODEL:
#  - Infra (postgres/solr/s3/mailpit) uses canonical host ports (5432, 8983,
#    4566, 1025/8025). `infra.sh up` auto-detects a busy port and shifts to a
#    free one, persisting the chosen values to .devbox/ports.env (reloaded
#    below) so run scripts keep using the same ports for the session; an
#    explicit env var (PG_PORT, SOLR_PORT, S3_PORT, SMTP_PORT,
#    MAILPIT_UI_PORT) always wins.
#  - Solr additionally self-relocates at process start if its port is taken and
#    records the actual port in .devbox/solr-data/.port; that value overrides
#    SOLR_PORT below so the backend follows the running Solr.
#  - Backend/UI get random free OS ports bound at startup (fallback). No state
#    files are ever written or read: everything resolves at runtime.
set -euo pipefail

DEVBOX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEVBOX_DIR="${DEVBOX_ROOT}/.devbox"
export DEVBOX_ROOT DEVBOX_DIR

# Reload infra port state persisted by `infra.sh up` (auto-ports picked when a
# fixed port was busy). Explicit caller env vars still win: loading here only
# fills the unset ones via the `:-default` expressions below.
if [ -f "${DEVBOX_DIR}/ports.env" ]; then
    # shellcheck disable=SC1090
    . "${DEVBOX_DIR}/ports.env" >/dev/null 2>&1 || true
fi

# The Solr process self-relocates to a free port when its default is taken
# (another Solr/app on this host) and records the actual port in
# .devbox/solr-data/.port. Prefer that value so consumers always talk to the
# running Solr, no matter how the services were started.
if [ -f "${DEVBOX_DIR}/solr-data/.port" ]; then
    # shellcheck disable=SC2162
    IFS= read -r SOLR_PORT < "${DEVBOX_DIR}/solr-data/.port" || true
    case "${SOLR_PORT}" in
        ''|*[!0-9]*) : ;; # ignore garbage; keep the default derived below
        *) export SOLR_PORT ;;
    esac
fi

# --- free host port (bind :0, read, release) ---
free_port() {
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()'
    else
        node -e 'const s=require("net").createServer();s.listen(0,"127.0.0.1",()=>{console.log(s.address().port);s.close()})'
    fi
}

INSTANCE="${INSTANCE:-1}"
if ! [[ "${INSTANCE}" =~ ^[0-9]+$ ]] || (( INSTANCE < 1 )); then
    echo "[env] INSTANCE must be a positive integer, got '${INSTANCE}'" >&2
    exit 1
fi
export INSTANCE

# --- instance ports: random free OS ports (unique per run, never overlap) ---
BACKEND_PORT="${BACKEND_PORT:-$(free_port)}"
[[ "${BACKEND_PORT}" =~ ^[0-9]+$ ]] || BACKEND_PORT="$(free_port)"
UI_PORT="${UI_PORT:-$(free_port)}"
[[ "${UI_PORT}" =~ ^[0-9]+$ ]] || UI_PORT="$(free_port)"
export BACKEND_PORT UI_PORT

# --- infra: native services use fixed host ports (set via env if needed) ---
# An explicit PG_PORT/SOLR_PORT/... from the caller must survive this sourcing,
# hence the export-if-unset pattern.
PG_PORT="${PG_PORT:-${POSTGRES_PORT:-5432}}"
SOLR_PORT="${SOLR_PORT:-8983}"
S3_PORT="${S3_PORT:-${MINISTACK_PORT:-4566}}"
SMTP_PORT="${SMTP_PORT:-${MAIL_PORT:-1025}}"
MAILPIT_UI_PORT="${MAILPIT_UI_PORT:-${SMTP_UI_PORT:-8025}}"

# Single shared infra (not per-instance)
DB_NAME="${DDEV_DB:-dspace}"
SOLR_PREFIX=""            # main cores only (search, statistics, ...)
S3_BUCKET="${DDEV_S3_BUCKET:-dspace-assets}"
export PG_PORT SOLR_PORT S3_PORT SMTP_PORT MAILPIT_UI_PORT DB_NAME SOLR_PREFIX S3_BUCKET

# --- DSpace config overrides (env -> dspace property; "__P__"='.', "__D__"='-') ---
# 127.0.0.1 is the canonical dev host: `localhost` resolves to ::1 first on many
# hosts while ng serve binds only 127.0.0.1 (IPv4) -> the UI would hang.
DEV_HOST="${DEV_HOST:-localhost}"
export dspace__P__dir="${DEVBOX_ROOT}/DSpace/dspace"
export dspace__P__name="DSpace Dev ${INSTANCE}"
export dspace__P__hostname="${UI_HOST:-${DEV_HOST}}"
export dspace__P__host="${UI_HOST:-${DEV_HOST}}"
export dspace__P__server__P__url="http://${BACKEND_HOST:-${DEV_HOST}}:${BACKEND_PORT}/server"
export dspace__P__server__P__ssr__P__url="http://${BACKEND_HOST:-${DEV_HOST}}:${BACKEND_PORT}/server"
export dspace__P__ui__P__url="http://${UI_HOST:-${DEV_HOST}}:${UI_PORT}"
export dspace__P__ui__P__host="${UI_HOST:-${DEV_HOST}}"
export dspace__P__ui__P__port="${UI_PORT}"
export dspace__P__ui__P__ssl="${UI_SSL:-false}"

# --- Database (single shared database on the infra postgres) ---
export db__P__url="jdbc:postgresql://${DB_HOST:-localhost}:${PG_PORT}/${DB_NAME}"
export db__P__username="${DB_USER:-dspace}"
export db__P__password="${DB_PASS:-dspace}"
export db__P__driver="org.postgresql.Driver"

# --- Discovery (shared Solr, main cores only -> empty multicorePrefix) ---
export solr__P__server="http://${SOLR_HOST:-localhost}:${SOLR_PORT}/solr"
export solr__P__multicorePrefix="${SOLR_PREFIX}"

# --- Asset store: S3 via Ministack, path-style, creds test/test ---
export assetstore__P__index__P__primary="1"
export assetstore__P__s3__P__enabled="true"
export assetstore__P__s3__P__endpoint="http://${S3_HOST:-localhost}:${S3_PORT}"
export assetstore__P__s3__P__awsAccessKey="${S3_KEY:-test}"
export assetstore__P__s3__P__awsSecretKey="${S3_SECRET:-test}"
export assetstore__P__s3__P__awsRegionName="${S3_REGION:-us-east-1}"
export assetstore__P__s3__P__bucketName="${S3_BUCKET}"

# --- Mail through Mailpit ---
export mail__P__server="${MAIL_HOST:-localhost}"
export mail__P__server__P__port="${SMTP_PORT}"
export mail__P__from__P__address="${MAIL_FROM:-dspace@localhost}"
export mail__P__admin="${MAIL_ADMIN:-dspace-admin@localhost}"

# --- Trusted proxies (Angular UI hits the REST API cross-origin) ---
export proxies__P__trusted__P__ipranges="127.0.0.1"

# --- Spring Boot / JVM ---
export SERVER_PORT="${BACKEND_PORT}"

echo "[env] instance ${INSTANCE}:"
echo "  backend  http://${DEV_HOST}:${BACKEND_PORT}/server"
echo "  ui       http://${DEV_HOST}:${UI_PORT}"
echo "  db       ${DB_NAME} -> localhost:${PG_PORT} (single, shared)"
echo "  solr     main cores -> localhost:${SOLR_PORT} (shared)"
echo "  s3       ${S3_BUCKET} -> localhost:${S3_PORT} (ministack)"
echo "  mail     smtp localhost:${SMTP_PORT} / ui http://localhost:${MAILPIT_UI_PORT} (mailpit)"