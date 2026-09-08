#!/usr/bin/env bash
# Combined dev launcher (stateless): runs backend + UI together on random,
# non-overlapping ports. One command, Ctrl-C stops both. No state files.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/env.sh"

mkdir -p "${DEVBOX_DIR}"
BACK_LOG="${DEVBOX_DIR}/backend-${INSTANCE}.log"
UI_LOG="${DEVBOX_DIR}/ui-${INSTANCE}.log"

bash "${SCRIPT_DIR}/backend.sh" > "${BACK_LOG}" 2>&1 &
BACKEND_PID=$!

bash "${SCRIPT_DIR}/ui.sh" > "${UI_LOG}" 2>&1 &
UI_PID=$!

echo "[dev] backend http://localhost:${BACKEND_PORT}/server   (pid ${BACKEND_PID})"
echo "[dev] ui      http://localhost:${UI_PORT}               (pid ${UI_PID})"
echo "[dev] Ctrl-C stops both. Logs: ${BACK_LOG} and ${UI_LOG}"

cleanup() { kill "${BACKEND_PID}" "${UI_PID}" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

# Wait until the backend starts accepting connections (up to 120s)
for _ in $(seq 1 120); do
    if (exec 3<>"/dev/tcp/127.0.0.1/${BACKEND_PORT}") 2>/dev/null; then
        exec 3>&- 3<&- || true
        break
    fi
    sleep 1
done

tail -F "${BACK_LOG}" "${UI_LOG}" &
TAIL_PID=$!
wait "${BACKEND_PID}" "${UI_PID}"
kill "${TAIL_PID}" 2>/dev/null || true