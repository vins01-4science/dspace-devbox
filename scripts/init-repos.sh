#!/usr/bin/env bash
# Initialize / reconfigure the DSpace backend + UI submodules.
#
# Reads repos.conf (defaults: custom DSpace fork branch + upstream angular),
# then for each submodule it:
#   1. makes sure it's checked out (git submodule init/update)
#   2. re-points the 'origin' remote at the configured REPO
#   3. fetches, checks out the configured BRANCH and pulls the latest tip
#
# Run after cloning the template (git clone --recursive) or after editing
# repos.conf to switch forks/branches.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONF="${ROOT}/repos.conf"

[ -f "${CONF}" ] || { echo "[init-repos] ERROR: ${CONF} not found" >&2; exit 1; }
# shellcheck disable=SC1090
source "${CONF}"

sync_repo() {
    local path="$1" url="$2" branch="$3"
    echo "== ${path} =="
    if [ ! -d "${ROOT}/${path}/.git" ]; then
        echo "  submodule not initialized, running git submodule update --init --recursive"
        git -C "${ROOT}" submodule update --init --recursive -- "${path}"
    fi
    echo "  setting origin -> ${url}"
    git -C "${ROOT}/${path}" remote set-url origin "${url}"
    echo "  fetching origin"
    git -C "${ROOT}/${path}" fetch origin
    echo "  checking out ${branch}"
    git -C "${ROOT}/${path}" checkout "${branch}" 2>/dev/null || {
        echo "  local branch ${branch} not found, tracking origin/${branch}"
        git -C "${ROOT}/${path}" checkout -b "${branch}" --track "origin/${branch}"
    }
    echo "  pulling latest origin/${branch}"
    git -C "${ROOT}/${path}" pull --ff-only origin "${branch}"
}

sync_repo "DSpace"            "${DSPACE_REPO}"          "${DSPACE_BRANCH}"
sync_repo "dspace-angular"    "${DSPACE_ANGULAR_REPO}"  "${DSPACE_ANGULAR_BRANCH}"

echo "[init-repos] done. Repos at:"
echo "  DSpace         -> ${DSPACE_REPO} (${DSPACE_BRANCH})"
echo "  dspace-angular -> ${DSPACE_ANGULAR_REPO} (${DSPACE_ANGULAR_BRANCH})"
