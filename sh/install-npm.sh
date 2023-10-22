#!/bin/bash

# Stop when error
set -e

# Colors
source ./sh/utils/colors

source ./.env

# Get environment type ENVIRONMENT_TYPE var from args
# Default values
ENVIRONMENT_TYPE=dev

# Parse environment type args
if [ "$1" ]; then
    ENVIRONMENT_TYPE="$1"
fi

# Run npm install in theme folder
docker compose -f docker-compose.build.yml run --rm node-container npm run install-"${ENVIRONMENT_TYPE}" --prefix ./app/wp-content/themes/"${WP_DEFAULT_THEME}"
