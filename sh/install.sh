#!/bin/bash

# Stop when error
set -e

# Colors
source ./sh/utils/colors

source ./.env

echo -e "${CYAN}[Info]${NOCOLOR} Installing project with \
WP_DEFAULT_THEME ${LIGHTYELLOW}'${WP_DEFAULT_THEME}'${NOCOLOR}, \
WP_ENVIRONMENT_TYPE ${LIGHTYELLOW}'${WP_ENVIRONMENT_TYPE}'${NOCOLOR}, \
and APP_BUILD_MODE ${LIGHTYELLOW}'${APP_BUILD_MODE}'${NOCOLOR}";

read -rp "Are you sure? (y/n): " choice
if [[ ! $choice =~ ^[Yy]$ ]]; then
  echo "Not confirmed. Exiting."
  exit 0
fi

# Build main docker images
docker compose build

# Build service docker images
docker compose -f docker-compose.build.yml build

# Run composer scripts
# Use composer update for update to last changes without lock file if we are using custom dependency. For example custom theme or plugin with 'dev-branch-name' version
docker compose -f docker-compose.build.yml run -it --rm --build composer su -c "composer update-${APP_BUILD_MODE}" "${DEFAULT_USER}"

# Use composer install for install from lock file for regular cases
docker compose -f docker-compose.build.yml run -it --rm --build composer su -c "cd web/wp-content/themes/${WP_DEFAULT_THEME} && composer install-${APP_BUILD_MODE}" "${DEFAULT_USER}"

# Run node scripts
docker compose -f docker-compose.build.yml run -it --rm --build node su -c "npm run install-${APP_BUILD_MODE} --prefix ./wp-content/themes/${WP_DEFAULT_THEME}" "${DEFAULT_USER}"
