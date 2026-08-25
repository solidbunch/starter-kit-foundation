#!/usr/bin/env bash

# Stop on errors, unset vars, and fail pipelines; preserve ERR traps
set -Eeuo pipefail

# Align with existing pattern in other images (recreate user/group with host UID/GID)
#
# On the act path (root UID/GID 0) and on hosts whose UID/GID already collides with an ID the
# Debian base image assigns to another user/group, addgroup/adduser fail hard on a collision and
# have no "reuse if exists" flag (see dockerfiles/php/docker-entrypoint.d/10-update-user.sh for
# the identical Alpine-side problem and rationale). The fix is name-aliasing: when the ID is
# already taken, add a *second* name for it in /etc/group / /etc/passwd rather than adopting the
# existing name. Debian additionally requires a matching /etc/shadow entry for `su` to succeed
# against an aliased user -- a passwd entry alone is not enough (verified live: without it, `su`
# fails with "Authentication failure").
if [ -n "${CURRENT_UID}" ] && [ -n "${CURRENT_GID}" ] && [ -n "${DEFAULT_USER}" ]; then
    # Best-effort delete the image's own default user/group by name.
    deluser "${DEFAULT_USER}" 2>/dev/null || true
    delgroup "${DEFAULT_USER}" 2>/dev/null || true

    # --- Group: guarantee a group NAMED ${DEFAULT_USER} resolves to ${CURRENT_GID} ---
    if [ -z "$(getent group "${CURRENT_GID}" || true)" ]; then
        # GID is free -- create the group normally.
        addgroup --gid "${CURRENT_GID}" "${DEFAULT_USER}"
    else
        # GID already taken by another group -- alias, do NOT adopt that group's own name.
        echo "${DEFAULT_USER}:x:${CURRENT_GID}:" >> /etc/group
    fi

    # --- User: guarantee a user NAMED ${DEFAULT_USER} resolves to ${CURRENT_UID}/${CURRENT_GID} ---
    EXISTING_USER="$(getent passwd "${CURRENT_UID}" | cut -d: -f1 || true)"
    if [ -z "${EXISTING_USER}" ]; then
        # UID is free -- create the user normally, in the group created/aliased above.
        adduser --uid "${CURRENT_UID}" --ingroup "${DEFAULT_USER}" --disabled-password --no-create-home --gecos "" "${DEFAULT_USER}"
    elif [ "${EXISTING_USER}" = "${DEFAULT_USER}" ]; then
        # Already the user we want -- nothing to do.
        :
    else
        # UID already taken by another user -- alias, do NOT adopt that user's own name.
        echo "${DEFAULT_USER}:x:${CURRENT_UID}:${CURRENT_GID}::/home/${DEFAULT_USER}:/bin/bash" >> /etc/passwd
        # Debian requires a matching /etc/shadow entry, else `su` fails with "Authentication failure".
        echo "${DEFAULT_USER}:*:20000:0:99999:7:::" >> /etc/shadow
    fi

    echo "${DEFAULT_USER} user UID=${CURRENT_UID} updated"
fi

# Exec the requested command (same as other images)
exec "$@"


