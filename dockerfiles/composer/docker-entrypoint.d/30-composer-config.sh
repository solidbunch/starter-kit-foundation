#!/usr/bin/env bash

set -Eeuo pipefail

# Current file
ME=$(basename "$0")

entrypoint_log() {
    if [ -z "${PHP_ENTRYPOINT_QUIET_LOGS:-}" ]; then
        echo "$@"
    fi
}

# Using COMPOSER_AUTH JSON object for Composer authentication
if [ ! -z "${COMPOSER_AUTH:-}" ]; then
  entrypoint_log "$ME: Used COMPOSER_AUTH JSON object for Composer authentication"
fi
