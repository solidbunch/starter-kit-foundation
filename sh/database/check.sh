#!/bin/bash

# Stop when error
set -e

# Colors
source ./sh/utils/colors.sh

source ./.env

# Take database hostname from .env file
DATABASE_CONTAINER="$MYSQL_HOST"

# Wait 10 times per 5 sec
echo -e "Waiting till database in container '${DATABASE_CONTAINER}' will be ready."
for i in {1..20}
do
    echo -e "Waiting 5 sec ${i} time "
    sleep 5
    if (docker compose exec "${DATABASE_CONTAINER}" mariadb-admin ping > /dev/null 2>&1); then
      break
    fi
    if [ "$i" = 10 ]; then
        echo -e "${LIGHTRED}[Error]${RESET} Database container '${DATABASE_CONTAINER}' is down"; exit 1;
    fi
done
