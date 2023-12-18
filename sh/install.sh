#!/bin/bash

# Stop when error
set -e

# Colors
source ./sh/utils/colors

source ./.env

# Get environment type ENVIRONMENT_TYPE var from args
# Default values
ENVIRONMENT_TYPE=local
MODE=all
# Take database hostname from .env file
DATABASE_CONTAINER="$MYSQL_HOST"

# Parse environment type args
if [ "$1" ]; then
  ENVIRONMENT_TYPE="$1"
fi

# Parse mode args
if [ "$2" ]; then
  MODE="$2"
fi

echo -e "${CYAN}[Info]${NOCOLOR} Installing project with WP_DEFAULT_THEME '${WP_DEFAULT_THEME}' and ENVIRONMENT_TYPE '${ENVIRONMENT_TYPE}' ";

if [[ "$MODE" == "all" || "$MODE" == "composer" ]]; then
  docker compose -f docker-compose.build.yml run --rm composer-container composer update-"${ENVIRONMENT_TYPE}"
fi

if [[ "$MODE" == "all" || "$MODE" == "npm" ]]; then
  docker compose -f docker-compose.build.yml run --rm node-container npm run install-"${ENVIRONMENT_TYPE}" --prefix ./app/wp-content/themes/"${WP_DEFAULT_THEME}"
fi

if [ "$MODE" != "all" ]; then
  exit 0
fi

# Build and run docker images
docker compose up -d --build

# Wait 20 times per 5 sec
echo -e "Waiting till database in container '${DATABASE_CONTAINER}' will be ready."
for i in {1..20}
do
    echo -e "Waiting 5 sec ${i} time "
    sleep 5
    if (docker compose exec "${DATABASE_CONTAINER}" mysqladmin ping > /dev/null 2>&1); then
      break
    fi
    if [ "$i" = 20 ]; then
        echo -e "${LIGHTRED}[Error]${NOCOLOR} Database container '${DATABASE_CONTAINER}' is down"; exit 1;
    fi
done

# Run wp cli wordpress install database
# Should be last command in installation
docker compose -f docker-compose.build.yml run --rm wp-cli-container bash /shell/wp-cli/core-install.sh 2> /dev/null
