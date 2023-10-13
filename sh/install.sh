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

echo "${WP_DEFAULT_THEME}"
echo "${WP_ENVIRONMENT_TYPE}"

docker compose -f docker-compose.build.yml run --rm composer-container composer update-"${ENVIRONMENT_TYPE}"
docker compose -f docker-compose.build.yml run --rm node-container npm run install-"${ENVIRONMENT_TYPE}" --prefix ./app/wp-content/themes/"${WP_DEFAULT_THEME}"

# run all containers
# run wp cli wordpress install database

wp core install --url=$WP_HOME \
  --title=$APP_NAME \
  --admin_user=$WP_ADMIN_USER \
  --admin_email=$WP_ADMIN_EMAIL \
  --admin_password=$WP_ADMIN_PASSWORD


wp core verify-checksums
