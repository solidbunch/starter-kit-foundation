#!/bin/bash

# This script imports a database dump into the current database.

# Source the .env file
source ./.env

# Colors
source ./sh/utils/colors

# Take database hostname from .env file
DATABASE_CONTAINER="$MYSQL_HOST"
PHP_WP_CONTAINER="php"

# Stop when error
set -e

if [ "$1" != "" ]; then
  DUMP_FILE="$1"
else
  echo "ERROR: Enter dump file name as the first parameter"
  exit 1
fi

# Read parameter 2, using $MYSQL_DATABASE from .env file by default
if [ "$2" != "" ]; then
  MYSQL_DATABASE="$2"
fi

echo -e "${LIGHTYELLOW}[Warning]${NOCOLOR} Current database '${MYSQL_DATABASE}' data will be replaced"
read -p "Are you sure? (y/n): " choice
if [[ ! $choice =~ ^[Yy]$ ]]; then
  echo "Not confirmed. Exiting."
  exit 0
fi

echo "Importing '${DUMP_FILE}' to local database '${MYSQL_DATABASE}'. It can take more than few minutes. Pls wait."

# Copy dump to container
docker compose cp "${DUMP_FILE}" "${DATABASE_CONTAINER}":/tmp/"${DUMP_FILE}"

# ToDo Create database if not exists
#echo "Creating database '${MYSQL_DATABASE}' if not exists"
#docker compose exec "${DATABASE_CONTAINER}" mysql -e "CREATE DATABASE IF NOT EXISTS ${MYSQL_DATABASE};"
#wp-cli db create

# Install pv if not installed
docker compose exec "${DATABASE_CONTAINER}" bash -c "command -v pv >/dev/null 2>&1 || { apt-get update >/dev/null 2>&1 || apt-get install -y pv; }"

# Import data from sql file with pv
docker compose exec "${DATABASE_CONTAINER}" bash -c "pv /tmp/${DUMP_FILE} | mysql -u ${MYSQL_USER} -p${MYSQL_PASSWORD} ${MYSQL_DATABASE}"

echo -e "${LIGHTGREEN}[Success]${NOCOLOR} Database import done"

# Run database domains replacement
docker compose exec "${PHP_WP_CONTAINER}" bash /shell/database_replacements.sh


