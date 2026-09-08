#!/usr/bin/env bash
# Create the per-instance Solr cores from the DSpace configsets, then hand
# over to solr-foreground as user 'solr' (mirrors DSpace's solr image flow).
set -e
set -u

init-var-solr

IFS=',' read -ra CORES <<< "${DDEV_CORES:-}"
if [ "${#CORES[@]}" -eq 0 ]; then
    echo "ERROR: DDEV_CORES is empty" >&2
    exit 1
fi

for core in "${CORES[@]}"; do
    [ -n "${core}" ] || continue
    # core name is '<instance>-<name>'; strip the prefix to find the configset dir
    name="${core#*-}"
    configset="/opt/solr/server/solr/configsets/${name}"
    if [ ! -d "${configset}/conf" ]; then
        echo "WARNING: configset ${configset}/conf not found, skipping core ${core}" >&2
        continue
    fi
    if [ -d "${PWD}/${core}" ]; then
        echo "core ${core} already exists, skipping"
    else
        echo "creating core ${core} from configset '${name}'"
        precreate-core "${core}" "${configset}"
        cp -r "${configset}/"* "${core}/"
        chown -R solr:solr "${core}"
    fi
done

chown -R solr:solr /var/solr || true

echo "starting Solr with cores: ${DDEV_CORES}"
exec runuser -u solr -- solr-foreground