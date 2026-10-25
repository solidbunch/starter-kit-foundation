#!/usr/bin/env bash

# Refuse to start the server when the data directory was last upgraded by a different release
# series (major.minor), so a changed image tag never runs a new series on old data silently.
# Patch bumps within a series need no mariadb-upgrade and only the official entrypoint's
# mariadb-upgrade rewrites mariadb_upgrade_info, so comparing x.y.z would block every start after
# a patch bump; the official entrypoint compares major.minor too.
# The upgrade is an explicit opt-in: MARIADB_AUTO_UPGRADE=1 (the official entrypoint backs up first).

set -Eeuo pipefail

DATADIR=/var/lib/mysql
VERSION_RE='[0-9]+\.[0-9]+\.[0-9]+'

AUTO_UPGRADE=${MARIADB_AUTO_UPGRADE:-}

# No data directory yet = fresh install, nothing to protect. An explicit opt-in skips the guard;
# empty and 0 mean "off", exactly as in the official entrypoint.
if { [ -n "$AUTO_UPGRADE" ] && [ "$AUTO_UPGRADE" != 0 ]; } || [ ! -d "$DATADIR/mysql" ]; then
    exit 0
fi

CUR=$(mariadbd --version | grep -oE "$VERSION_RE" | head -1)
OLD=$(grep -oE "$VERSION_RE" "$DATADIR/mariadb_upgrade_info" 2>/dev/null | head -1 || true)
CUR_SERIES=${CUR%.*}
OLD_SERIES=${OLD%.*}

if [ -z "$OLD" ] || [ "$CUR_SERIES" != "$OLD_SERIES" ]; then
    echo "[version-guard] ERROR: MariaDB server NOT started." >&2
    echo "[version-guard]   image version:    $CUR" >&2
    echo "[version-guard]   data directory:   ${OLD:-unknown (mariadb_upgrade_info missing)}" >&2
    echo "[version-guard] The data was written by another release series. Back up db-data, then start once" >&2
    echo "[version-guard] with MARIADB_AUTO_UPGRADE=1, or switch the image back to the old version." >&2
    exit 1
fi
