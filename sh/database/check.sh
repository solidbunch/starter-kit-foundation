#!/bin/bash

# Stop when error
set -e

# Colors
source ./sh/utils/colors.sh

echo -e "------------------------------"
echo -e "Check database is up"
echo -e "------------------------------"

source ./.env

# Take database hostname from .env file
DATABASE_CONTAINER="$MYSQL_HOST"

# Wait 10 times per 5 sec
echo -e "Waiting till database in container '${DATABASE_CONTAINER}' will be ready."
DATABASE_READY=false
for i in {1..10}
do
    echo -e "Waiting 5 sec ${i} time "
    sleep 5
    if (docker compose exec "${DATABASE_CONTAINER}" mariadb-admin ping > /dev/null 2>&1); then
      DATABASE_READY=true
      break
    fi
done

if [ "$DATABASE_READY" = false ]; then
    echo -e "${LIGHTRED}[Error]${RESET} Database container '${DATABASE_CONTAINER}' is down"; exit 1;
fi
