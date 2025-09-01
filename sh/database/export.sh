#!/bin/bash

# This script exports a database dump from the current database.

# Stop on any error and fail on pipe errors
set -e -o pipefail

# Load environment and colors
source ./sh/utils/colors.sh
source ./.env

# Database container name
DATABASE_CONTAINER="${APP_NAME}-mariadb"

# Define the table prefix, using a default value 'wp_' if MYSQL_DB_PREFIX is not set
DB_PREFIX="${MYSQL_DB_PREFIX:-wp_}"

# Default output file name
OUTPUT_DIR="./tmp"
OUTPUT_FILE="${OUTPUT_DIR}/${DATABASE_CONTAINER}-${MYSQL_DATABASE}-${WP_ENVIRONMENT_TYPE}-${APP_DOMAIN}-$(date +%Y-%m-%d).sql"

# Parse CLI arguments
while getopts "f:i:h" opt; do
  case $opt in
    f) OUTPUT_FILE="$OPTARG" ;;
    i) IGNORE_USERS="$OPTARG" ;;
    h) echo "Usage: $0 -f <output_file> -i <ignore_users_table>"; exit 0 ;;
    *) echo "Invalid option. Use -h for help"; exit 1 ;;
  esac
done

# Create output directory if it does not exist
mkdir -p "$(dirname "$OUTPUT_FILE")"

echo "Exporting database '${MYSQL_DATABASE}'. It can take more than a few minutes. Please wait."

# Check database health and wait for it to be ready
for i in {1..3}
do
    if (docker exec "${DATABASE_CONTAINER}" mariadb-admin -u "${MYSQL_USER}" -p"${MYSQL_PASSWORD}" ping > /dev/null 2>&1); then
        break
    fi
    sleep 3
    if [ "$i" = 3 ]; then
        echo -e "${LIGHTRED}[Error]${RESET} Database container '$DATABASE_CONTAINER' is down"; exit 1;
    fi
done

# Build mariadb-dump arguments as an array
DUMP_ARGS=(-u "${MYSQL_USER}" --password="${MYSQL_PASSWORD}")

# Add --ignore-table flags if IGNORE_USERS is not empty
if [ -n "${IGNORE_USERS}" ]; then
  # Exclude users and usermeta tables while exporting the database, if need to leave old password on import
   DUMP_ARGS+=("--ignore-table=${MYSQL_DATABASE}.${DB_PREFIX}users")
   DUMP_ARGS+=("--ignore-table=${MYSQL_DATABASE}.${DB_PREFIX}usermeta")
fi

# Append database name as the final argument
DUMP_ARGS+=("${MYSQL_DATABASE}")

# ToDo add pv progress bar
# Run the dump inside the container, redirect output to local file
docker exec "${DATABASE_CONTAINER}" mariadb-dump "${DUMP_ARGS[@]}" > "${OUTPUT_FILE}"


if [ -n "${IGNORE_USERS}" ]; then
  echo "The ${DB_PREFIX}users and ${DB_PREFIX}usermeta tables were excluded from the dump."
fi

echo -e "${LIGHTGREEN}[Success]${RESET} Database export done to '${BOLD}${OUTPUT_FILE}${RESET}'"
