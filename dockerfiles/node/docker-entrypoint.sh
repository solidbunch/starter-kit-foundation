#!/usr/bin/env bash

# Stop when error
set -e

# Run command with node if the first argument contains a "-" or is not a system command. The last
# part inside the "{}" is a workaround for the following bug in ash/dash:
# https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=874264
if [ "${1#-}" != "${1}" ] || [ -z "$(command -v "${1}")" ] || { [ -f "${1}" ] && ! [ -x "${1}" ]; }; then
  set -- node "$@"
fi

# Recreate node user
# Fix Permission denied error
deluser --remove-home node
addgroup -g "${CURRENT_GID}" node
adduser -u "${CURRENT_UID}" -D -G node node

echo "node user UID=${CURRENT_UID} updated"

## exec command (added as parameter in Dockerfile CMD)
exec "$@"
