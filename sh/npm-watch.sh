#!/bin/bash

# Stop when error
set -e

# Colors
source ./sh/utils/colors

source ./.env

# Run watch in theme folder
docker compose -f docker-compose.build.yml run --service-ports --rm --build node npm run watch --prefix ./wp-content/themes/"${WP_DEFAULT_THEME}"
