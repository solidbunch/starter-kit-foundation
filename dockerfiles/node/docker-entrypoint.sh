#!/usr/bin/env bash

# Stop when error
set -e

# Recreate node user
# Fix Permission denied error
# Deleting default node user (with group)
deluser node
# Deleting default user group
delgroup www-data
# 82 is the standard uid/gid for "www-data" in Alpine
# https://git.alpinelinux.org/aports/tree/main/apache2/apache2.pre-install?h=3.14-stable
# https://git.alpinelinux.org/aports/tree/main/lighttpd/lighttpd.pre-install?h=3.14-stable
# https://git.alpinelinux.org/aports/tree/main/nginx/nginx.pre-install?h=3.14-stable

addgroup -g "${CURRENT_GID}" "${DEFAULT_USER}"
adduser -u "${CURRENT_UID}" -D -G "${DEFAULT_USER}" "${DEFAULT_USER}"

echo "${DEFAULT_USER} user UID=${CURRENT_UID} updated"

# Run command with node if the first argument contains a "-" or is not a system command. The last
# part inside the "{}" is a workaround for the following bug in ash/dash:
# https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=874264
if [ "${1#-}" != "${1}" ] || [ -z "$(command -v "${1}")" ] || { [ -f "${1}" ] && ! [ -x "${1}" ]; }; then
  set -- node "$@"
fi

## exec command (added as parameter in Dockerfile CMD)
exec "$@"
