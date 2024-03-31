#!/bin/bash

# Stop when error
set -e

# Colors
source ./sh/utils/colors

source ./.env

# Run Node scripts
docker compose -f docker-compose.build.yml run --rm node su -c "\
    npm run install-${APP_BUILD_MODE} --prefix ./wp-content/themes/${WP_DEFAULT_THEME}" \
  "${DEFAULT_USER}"
