#!/usr/bin/env bash

# Stop on errors, unset vars, and fail pipelines; preserve ERR traps
set -Eeuo pipefail

# Align with existing pattern in other images (recreate user/group with host UID/GID)
if [ -n "${CURRENT_UID}" ] && [ -n "${CURRENT_GID}" ] && [ -n "${DEFAULT_USER}" ]; then
    # Delete existing user/group if present (ignore errors)
    deluser "${DEFAULT_USER}" 2>/dev/null || true
    delgroup "${DEFAULT_USER}" 2>/dev/null || true

    # Recreate group and user with host IDs
    addgroup --gid "${CURRENT_GID}" "${DEFAULT_USER}"
    adduser  --uid "${CURRENT_UID}" --ingroup "${DEFAULT_USER}" --disabled-password --no-create-home --gecos "" "${DEFAULT_USER}"

    echo "${DEFAULT_USER} user UID=${CURRENT_UID} updated"
fi

# Exec the requested command (same as other images)
exec "$@"


