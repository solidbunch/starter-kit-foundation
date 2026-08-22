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
#
# On macOS/act hosts, ${CURRENT_GID}/${CURRENT_UID} can collide with an ID the Alpine base image
# already assigns to another user/group (e.g. macOS GID 20, act's root UID/GID 0). addgroup/adduser
# fail hard on a collision and have no "reuse if exists" flag. The fix is name-aliasing: when the
# ID is already taken, add a *second* name for it in /etc/group / /etc/passwd rather than adopting
# the colliding entry's own name — same pattern used by dockerfiles/php and dockerfiles/iac.

# --- Group: guarantee a group NAMED ${DEFAULT_USER} resolves to ${CURRENT_GID} ---
if [ -z "$(getent group "${CURRENT_GID}" || true)" ]; then
  addgroup -g "${CURRENT_GID}" "${DEFAULT_USER}"
else
  echo "${DEFAULT_USER}:x:${CURRENT_GID}:" >> /etc/group
fi

# --- User: guarantee a user NAMED ${DEFAULT_USER} resolves to ${CURRENT_UID}/${CURRENT_GID} ---
EXISTING_USER="$(getent passwd "${CURRENT_UID}" | cut -d: -f1 || true)"
if [ -z "${EXISTING_USER}" ]; then
  adduser -u "${CURRENT_UID}" -D -G "${DEFAULT_USER}" "${DEFAULT_USER}"
elif [ "${EXISTING_USER}" != "${DEFAULT_USER}" ]; then
  echo "${DEFAULT_USER}:x:${CURRENT_UID}:${CURRENT_GID}::/home/${DEFAULT_USER}:/bin/sh" >> /etc/passwd
fi

echo "${DEFAULT_USER} user UID=${CURRENT_UID} updated"

# Run command with node if the first argument contains a "-" or is not a system command. The last
# part inside the "{}" is a workaround for the following bug in ash/dash:
# https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=874264
if [ "${1#-}" != "${1}" ] || [ -z "$(command -v "${1}")" ] || { [ -f "${1}" ] && ! [ -x "${1}" ]; }; then
  set -- node "$@"
fi

## exec command (added as parameter in Dockerfile CMD)
exec "$@"
