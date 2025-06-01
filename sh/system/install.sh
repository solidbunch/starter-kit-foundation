#!/bin/bash

# Stop when error
set -e

# Colors
source ./sh/utils/colors.sh

source ./.env

if [ "$1" ]; then
    CONFIRMED="$1"
fi

echo -e "${CYAN}[Info]${RESET} Installing project with \
WP_DEFAULT_THEME ${LIGHTYELLOW}'$WP_DEFAULT_THEME'${RESET}, \
WP_ENVIRONMENT_TYPE ${LIGHTYELLOW}'$WP_ENVIRONMENT_TYPE'${RESET}, \
and APP_BUILD_MODE ${LIGHTYELLOW}'$APP_BUILD_MODE'${RESET}";

if [ "$CONFIRMED" != "yes" ]; then
  read -rp "Are you sure? (y/n): " choice
  if [[ ! $choice =~ ^[Yy](es)?$ ]]; then
    echo "Not confirmed. Exiting."
    exit 1
  fi
fi

# Run composer scripts
# Use composer update for update to last changes without lock file
# Use composer install for install from lock file for regular cases for theme or plugin
docker compose -f docker-compose.build.yml run --rm composer su -c "\
    composer install-${APP_BUILD_MODE} && \
    cd /srv/web/wp-content/themes/${WP_DEFAULT_THEME} && \
    composer install-${APP_BUILD_MODE}" \
  "${DEFAULT_USER}"

# Run Node scripts
docker compose -f docker-compose.build.yml run --rm node su -c "\
    npm run install-${APP_BUILD_MODE} --prefix ./wp-content/themes/${WP_DEFAULT_THEME}" \
  "${DEFAULT_USER}"
