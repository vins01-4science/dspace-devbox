#!/usr/bin/env bash
# Builds the runtime classpath for the DSpace backend out of EXPLODED classes
# (each module's target/classes) plus external jar dependencies already in
# ~/.m2. NEVER packages, installs or copies any jar into the project.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEVBOX_DIR="${ROOT}/.devbox"
DS="${ROOT}/DSpace"
CP_RAW="${DEVBOX_DIR}/cp.txt"
CP_EXTERNAL="${DEVBOX_DIR}/cp-external.txt"
FULL_CP="${DEVBOX_DIR}/full-cp.txt"

mkdir -p "${DEVBOX_DIR}"
cd "${DS}"

# 1) Spring Boot version -> devtools must match exactly
SB_VERSION="$(node -e "
const s = require('fs').readFileSync('pom.xml', 'utf8');
const m = s.match(/<spring-boot.version>([^<]+)<\\/spring-boot.version>/);
if (!m) { process.stderr.write('spring-boot.version not found in pom.xml\n'); process.exit(1); }
console.log(m[1]);
")"
DEVTOOLS_JAR="${HOME}/.m2/repository/org/springframework/boot/spring-boot-devtools/${SB_VERSION}/spring-boot-devtools-${SB_VERSION}.jar"

# 2) Fetch devtools into ~/.m2 once (it stays there; never copied into the repo)
if [ ! -f "${DEVTOOLS_JAR}" ]; then
    echo "[classpath] pulling spring-boot-devtools:${SB_VERSION} into ~/.m2 ..."
    mvn -q dependency:get -Dartifact="org.springframework.boot:spring-boot-devtools:${SB_VERSION}"
fi
[ -f "${DEVTOOLS_JAR}" ] || {
    echo "[classpath] ERROR: devtools jar not found after dependency:get: ${DEVTOOLS_JAR}" >&2
    exit 1
}

# 3) Compile DSpace classes (incremental; stops at `compile`, classes only).
#    Use mvnd (Maven Daemon) when available for warm parallel builds; fall back to mvn.
MVN="mvnd"
command -v "${MVN}" >/dev/null 2>&1 || MVN="mvn"
echo "[classpath] compiling DSpace classes (no packaging, no install) via ${MVN} ..."
time "${MVN}" -q -pl :server-boot -am -DskipTests -Dmaven.test.skip=true -Dmaven.install.skip=true compile

# 4) External deps from ~/.m2 (reactor modules are dropped by filter-cp.js).
#    Regenerated only when any DSpace pom.xml is newer than the cached result.
STALE=""
if [ -f "${CP_RAW}" ] && [ -z "$(find . -name pom.xml -newer "${CP_RAW}" -print -quit)" ]; then
    STALE="0"
fi
if [ -z "${STALE}" ]; then
    echo "[classpath] resolving external dependencies from ~/.m2 ..."
    "${MVN}" -q -pl :server-boot -am -DskipTests dependency:build-classpath \
        -Dmdep.outputFile="${CP_RAW}" -Dmdep.includeScope=runtime
    node "${ROOT}/scripts/lib/filter-cp.js" "${CP_RAW}" > "${CP_EXTERNAL}"
fi
[ -s "${CP_EXTERNAL}" ] || {
    echo "[classpath] ERROR: no external dependencies resolved" >&2
    exit 1
}

# 5) Assemble the final classpath: devtools + exploded classes + external jars
CLASS_DIRS="$(find "${DS}" -path '*/target/classes' -type d | sort | paste -sd: -)"
[ -n "${CLASS_DIRS}" ] || {
    echo "[classpath] ERROR: no target/classes dirs found after compile" >&2
    exit 1
}

printf '%s\n' "${DEVTOOLS_JAR}:${CLASS_DIRS}:$(cat "${CP_EXTERNAL}")" > "${FULL_CP}"
N_ENTRIES="$(tr ':' '\n' < "${FULL_CP}" | grep -c .)"
echo "[classpath] ready: ${N_ENTRIES} entries, $(wc -c < "${FULL_CP}") bytes -> ${FULL_CP}"