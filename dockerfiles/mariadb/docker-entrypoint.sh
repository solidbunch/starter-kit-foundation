#!/usr/bin/env bash

set -Eeuo pipefail

entrypoint_log() {
    if [ -z "${MARIADB_ENTRYPOINT_QUIET_LOGS:-}" ]; then
        echo "$@"
    fi
}

# Run our own scripts first; a failing script aborts the start (set -e), the server never launches.
for f in /docker-entrypoint.d/*.sh; do
    if [ -x "$f" ]; then
        entrypoint_log "$0: Launching $f"
        "$f"
    else
        entrypoint_log "$0: Ignoring $f, not executable"
    fi
done

# Hand over to the original entrypoint of the official image (init, MARIADB_AUTO_UPGRADE, user switch)
exec docker-entrypoint.sh "$@"
