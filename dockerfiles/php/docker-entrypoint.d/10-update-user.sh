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
# Fix www-data UID/GID from the image defaults to ${CURRENT_UID}/${CURRENT_GID}
# (Permission denied error on bind-mounted host files)
#
# On macOS/act hosts, ${CURRENT_GID}/${CURRENT_UID} can collide with an ID the Alpine base image
# already assigns to another user/group (e.g. macOS GID 20 -> "dialout", act's root UID/GID 0).
# addgroup/adduser fail hard on a collision and have no "reuse if exists" flag. php-fpm resolves
# its pool user/group BY NAME (php-fpm.d/www.conf: user = www-data / group = www-data), so a
# group/user must exist literally named "${DEFAULT_USER}" -- adopting the colliding entry's own
# name (e.g. "dialout") satisfies `su`/`id` but breaks php-fpm startup. The fix is therefore
# name-aliasing: when the ID is already taken, add a *second* name for it in /etc/group /
# /etc/passwd rather than adopting the existing name.
#
# 82 is the standard uid/gid for "www-data" in Alpine
# https://git.alpinelinux.org/aports/tree/main/apache2/apache2.pre-install?h=3.14-stable
# https://git.alpinelinux.org/aports/tree/main/lighttpd/lighttpd.pre-install?h=3.14-stable
# https://git.alpinelinux.org/aports/tree/main/nginx/nginx.pre-install?h=3.14-stable

# Best-effort delete the image's own default user/group by name.
deluser www-data || true

# --- Group: guarantee a group NAMED ${DEFAULT_USER} resolves to ${CURRENT_GID} ---
if [ -z "$(getent group "${CURRENT_GID}" || true)" ]; then
    # GID is free -- create the group normally.
    addgroup -g "${CURRENT_GID}" "${DEFAULT_USER}"
else
    # GID already taken by another group -- alias, do NOT adopt that group's own name.
    echo "${DEFAULT_USER}:x:${CURRENT_GID}:" >> /etc/group
fi

# --- User: guarantee a user NAMED ${DEFAULT_USER} resolves to ${CURRENT_UID}/${CURRENT_GID} ---
EXISTING_USER="$(getent passwd "${CURRENT_UID}" | cut -d: -f1 || true)"
if [ -z "${EXISTING_USER}" ]; then
    # UID is free -- create the user normally, in the group created/aliased above.
    adduser -u "${CURRENT_UID}" -D -G "${DEFAULT_USER}" "${DEFAULT_USER}"
elif [ "${EXISTING_USER}" = "${DEFAULT_USER}" ]; then
    # Already the user we want -- nothing to do.
    :
else
    # UID already taken by another user -- alias, do NOT adopt that user's own name.
    echo "${DEFAULT_USER}:x:${CURRENT_UID}:${CURRENT_GID}::/home/${DEFAULT_USER}:/bin/sh" >> /etc/passwd
fi

chown "${CURRENT_UID}:${CURRENT_GID}" /var/log/wordpress

echo "${DEFAULT_USER} user UID=${CURRENT_UID} updated"
