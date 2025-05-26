#!/bin/bash

# This script exports a database dump from the current database.

# Source the .env file
source ./.env

# Colors
source ./sh/utils/colors

# Stop when error
set -e

# Define the table prefix, using a default value 'wp_' if MYSQL_DB_PREFIX is not set
DB_PREFIX=${MYSQL_DB_PREFIX:-wp_}

# Set IGNORED_TABLES based on the first argument
IGNORED_TABLES=""

# Take database hostname from .env file
DATABASE_CONTAINER="$MYSQL_HOST"

# Default output file name
OUTPUT_FILE="$DATABASE_CONTAINER"-"$MYSQL_DATABASE"-"$WP_ENVIRONMENT_TYPE"-"$APP_DOMAIN"-$(date +%Y-%m-%d).sql

# Parse CLI arguments
while getopts "f:i:h" opt; do
  case $opt in
    f) OUTPUT_FILE="$OPTARG" ;;
    i) IGNORE_USERS="$OPTARG" ;;
    h) echo "Usage: $0 -f <output_file> -i <ignore_users_table>"; exit 0 ;;
    *) echo "Invalid option. Use -h for help"; exit 1 ;;
  esac
done

# File name inside database container
CONTAINER_OUTPUT_FILE="/tmp/db.sql"
echo $IGNORE_USERS
# Exclude users and usermeta tables while exporting the database, if need to leave old password on import
if [ "$IGNORE_USERS" == "true" ]; then
  IGNORED_TABLES="--ignore-table=${MYSQL_DATABASE}.${DB_PREFIX}users --ignore-table=${MYSQL_DATABASE}.${DB_PREFIX}usermeta"
fi
echo $IGNORED_TABLES

echo "Exporting local database to '${OUTPUT_FILE}'. It can take more than a few minutes. Please wait."

# Export data to sql file
docker compose exec "${DATABASE_CONTAINER}" bash -c "mariadb-dump -u ${MYSQL_USER} -p${MYSQL_PASSWORD} ${IGNORED_TABLES} ${MYSQL_DATABASE} > ${CONTAINER_OUTPUT_FILE}"

# Copy dump from container
docker compose cp "${DATABASE_CONTAINER}":"${CONTAINER_OUTPUT_FILE}" "${OUTPUT_FILE}"

if [ -n "${IGNORED_TABLES}" ]; then
  echo "The ${DB_PREFIX}users and ${DB_PREFIX}usermeta tables were excluded from the dump."
fi

echo -e "${LIGHTGREEN}[Success]${NOCOLOR} Database export done"
