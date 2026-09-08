#!/usr/bin/env bash
# Start a DSpace backend instance with mvn spring-boot:run (no jar packaging).
# Devtools is an (optional) dependency of dspace/modules/server-boot, so `mvn
# compile` = real Spring-Boot-DevTools restart. Upstream modules: fresh
# target/classes dirs are put in FRONT of the resolved .m2 dependency jars, so
# edits in dspace-api/webapp hot reload too.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTANCE="${INSTANCE:-1}"
export INSTANCE
source "${SCRIPT_DIR}/lib/env.sh"

DS="${DEVBOX_ROOT}/DSpace"

CLASS_DIRS="$(find "${DS}" -path '*/target/classes' -type d | paste -sd, -)"

# DevTools restart needs the FULL launch classpath as its restart world, which
# happens automatically because devtools is a real dependency of server-boot
# (NOT injected via additional-classpath-elements). DEVTOOLS_RESTART=true gives
# true hot reload; false = plain boot.
DEVTOOLS_RESTART="${DEVTOOLS_RESTART:-false}"
if [ "${DEVTOOLS_RESTART}" = "true" ]; then
    DEVTOOLS_ARGS="-Dspring.devtools.restart.enabled=true -Dspring.devtools.restart.poll-interval=300ms -Dspring.devtools.restart.quiet-period=150ms"
else
    DEVTOOLS_ARGS="-Dspring.devtools.restart.enabled=false"
fi

JVM_ARGS="-XX:TieredStopAtLevel=1 -XX:+UseSerialGC \
-Xms128m -Xmx1536m -XX:MaxMetaspaceSize=512m -XX:ReservedCodeCacheSize=128m \
-Djava.net.preferIPv4Stack=true -Dfile.encoding=UTF-8 \
-Ddspace.dir=${DS}/dspace ${DEVTOOLS_ARGS}"

echo "[backend] instance ${INSTANCE} -> http://localhost:${BACKEND_PORT}/server (mvn spring-boot:run, no jar)"
echo "[backend] hot reload: keep this running, edit code, then run 'devbox run compile'"
cd "${DS}"
export JAVA_TOOL_OPTIONS="-Ddspace.dir=${DS}/dspace"
exec mvn -Denforcer.skip=true -pl dspace/modules/server-boot spring-boot:run \
    -Dspring-boot.run.main-class=org.dspace.app.ServerBootApplication \
    -Dspring-boot.run.arguments="--dspace.dir=${DS}/dspace --logging.config=${DEVBOX_DIR}/log4j2-dev.xml" \
    -Dspring-boot.run.additional-classpath-elements="${CLASS_DIRS}" \
    -Dspring-boot.run.jvmArguments="${JVM_ARGS}"