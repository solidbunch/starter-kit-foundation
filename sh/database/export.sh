#!/bin/bash

# This script exports a database dump from the current database.

# Source the .env file
source ./.env

# Colors
source ./sh/utils/colors

# Take database hostname from .env file
DATABASE_CONTAINER="$MYSQL_HOST"

# Stop when error
set -e

# Read parameter 2, using $MYSQL_DATABASE from .env file by default
if [ "$2" != "" ]; then
  MYSQL_DATABASE="$2"
fi

if [ "$1" != "" ]; then
  OUTPUT_FILE="$1"
else
  OUTPUT_FILE="$DATABASE_CONTAINER"-"$MYSQL_DATABASE"-"$ENVIRONMENT_TYPE"-"$APP_DOMAIN"-$(date +%Y-%m-%d).sql
fi

echo "Exporting local database to '${OUTPUT_FILE}'. It can take more than a few minutes. Please wait."

# Export data to sql file
docker compose exec "${DATABASE_CONTAINER}" bash -c "mariadb-dump -u ${MYSQL_USER} -p${MYSQL_PASSWORD} ${MYSQL_DATABASE} > /tmp/${OUTPUT_FILE}"

# Copy dump from container
docker compose cp "${DATABASE_CONTAINER}":/tmp/"${OUTPUT_FILE}" "${OUTPUT_FILE}"

echo -e "${LIGHTGREEN}[Success]${NOCOLOR} Database export done"
