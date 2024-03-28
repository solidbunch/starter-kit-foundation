#!/usr/bin/env bash

set -Eeuo pipefail

# Current file
ME=$(basename "$0")

entrypoint_log() {
    if [ -z "${PHP_ENTRYPOINT_QUIET_LOGS:-}" ]; then
        echo "$@"
    fi
}

# Recreate www-data user
# Fix www-data UID from 82 to ${CURRENT_UID} (Permission denied error)
# Deleting default user (with group)
deluser www-data
# 82 is the standard uid/gid for "www-data" in Alpine
# https://git.alpinelinux.org/aports/tree/main/apache2/apache2.pre-install?h=3.14-stable
# https://git.alpinelinux.org/aports/tree/main/lighttpd/lighttpd.pre-install?h=3.14-stable
# https://git.alpinelinux.org/aports/tree/main/nginx/nginx.pre-install?h=3.14-stable

addgroup -g "${CURRENT_GID}" "${DEFAULT_USER}"
adduser -u "${CURRENT_UID}" -D -G "${DEFAULT_USER}" "${DEFAULT_USER}"
chown "${DEFAULT_USER}":"${DEFAULT_USER}" /var/log/wordpress

echo "${DEFAULT_USER} user UID=${CURRENT_UID} updated"
