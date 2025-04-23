#!/usr/bin/env bash

# Stop when error
set -e

# Deleting default user group
delgroup www-data
# 82 is the standard uid/gid for "www-data" in Alpine
# https://git.alpinelinux.org/aports/tree/main/apache2/apache2.pre-install?h=3.14-stable
# https://git.alpinelinux.org/aports/tree/main/lighttpd/lighttpd.pre-install?h=3.14-stable
# https://git.alpinelinux.org/aports/tree/main/nginx/nginx.pre-install?h=3.14-stable

addgroup -g "${CURRENT_GID}" "${DEFAULT_USER}"
adduser -u "${CURRENT_UID}" -D -G "${DEFAULT_USER}" "${DEFAULT_USER}"

echo "${DEFAULT_USER} user UID=${CURRENT_UID} updated"

mkdir -p /etc/letsencrypt /var/lib/letsencrypt /var/log/letsencrypt
chown -R "${DEFAULT_USER}":"${DEFAULT_USER}" /etc/letsencrypt /var/lib/letsencrypt /var/log/letsencrypt

## exec command (added as parameter in Dockerfile CMD)
exec "$@"
