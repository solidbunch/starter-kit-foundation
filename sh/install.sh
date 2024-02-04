#!/bin/bash

# Stop when error
set -e

# Colors
source ./sh/utils/colors

source ./.env

# Take database hostname from .env file
DATABASE_CONTAINER="$MYSQL_HOST"

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
docker compose -f docker-compose.build.yml run --rm --build php-extra composer update-"${APP_BUILD_MODE}"

# Use composer install for install from lock file for regular cases
docker compose -f docker-compose.build.yml run --rm --build php-extra bash -c "cd web/wp-content/themes/${WP_DEFAULT_THEME} && composer install-${APP_BUILD_MODE}"

# Run node scripts
docker compose -f docker-compose.build.yml run --rm --build node npm run install-"${APP_BUILD_MODE}" --prefix ./wp-content/themes/"${WP_DEFAULT_THEME}"

# Run main project docker containers
docker compose up -d

# Wait 20 times per 5 sec
echo -e "Waiting till database in container '${DATABASE_CONTAINER}' will be ready."
for i in {1..20}
do
    echo -e "Waiting 5 sec ${i} time "
    sleep 5
    if (docker compose exec "${DATABASE_CONTAINER}" mariadb-admin ping > /dev/null 2>&1); then
      break
    fi
    if [ "$i" = 20 ]; then
        echo -e "${LIGHTRED}[Error]${NOCOLOR} Database container '${DATABASE_CONTAINER}' is down"; exit 1;
    fi
done

# Run wp cli wordpress install database
# Should be last command in installation
docker compose -f docker-compose.build.yml run --rm --build wp-cli-container bash /shell/wp-cli/core-install.sh 2> /dev/null
