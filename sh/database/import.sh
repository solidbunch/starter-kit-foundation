#!/bin/bash
# import.sh - Import a database dump into the current database
#
# Usage: ./sh/database/import.sh -f <dump_file.sql> [-d <database_name>] [-y] [-t]
# Options:
#   -f <dump_file.sql>  : Path to the SQL dump file to import
#   -d <database_name>  : Database to import into (default: ${MYSQL_DATABASE})
#   -y                  : Skip confirmation prompt
#   -t                  : Use TTY for pv (useful for large files)
#   -h                  : Show this help message
#
# Requirements:
#   - Docker with a running MariaDB container
#   - pv (pipe viewer) installed in the container
#   - mariadb-dump utility available in the container
# Note: This script assumes that the database container is named as per the APP_NAME and uses the environment variables defined in .env.

# Load environment and colors
source ./.env
source ./sh/utils/colors.sh

# Stop on any error and fail on pipe errors
set -e -o pipefail

DATABASE_CONTAINER="${APP_NAME}-mariadb"

# Defaults
DUMP_FILE=""
CONFIRM=true
USE_TTY=false

# Parse args
while getopts "f:d:yth" opt; do
  case $opt in
    f) DUMP_FILE="$OPTARG" ;;
    d) MYSQL_DATABASE="$OPTARG" ;; # override database
    y) CONFIRM=false ;;            # skip confirmation
    t) USE_TTY=true ;;             # use TTY for pv
    h)
      echo "Usage: $0 -f <dump_file.sql> [-d <database_name>] [-y] [-t]"
      echo "  -f <dump_file.sql>  : Path to the SQL dump file to import"
      echo "  -d <database_name>  : Database to import into (default: '${MYSQL_DATABASE}')"
      echo "  -y                  : Skip confirmation prompt"
      echo "  -t                  : Use TTY for pv (useful for large files)"
      exit 0
      ;;
    *) echo "Invalid option. Use -h for help"; exit 1 ;;
  esac
done

if [ -z "$DUMP_FILE" ]; then
  echo -e "${LIGHTRED}[Error]${RESET} Missing dump file (-f <dump_file.sql>)"; exit 1
fi

if [ ! -f "$DUMP_FILE" ]; then
  echo -e "${LIGHTRED}[Error]${RESET} File '$DUMP_FILE' does not exist"; exit 1
fi

echo -e "${LIGHTYELLOW}[Warning]${RESET} This will replace data in database '${MYSQL_DATABASE}'"

if [ "$CONFIRM" = true ]; then
  read -rp "Are you sure? (y/n): " choice
  if [[ ! $choice =~ ^[Yy](es)?$ ]]; then
    echo "Cancelled."
    exit 0
  fi
fi

echo "Importing '$DUMP_FILE' into '${MYSQL_DATABASE}'..."

# ToDo Create database if not exists
#echo "Creating database '${MYSQL_DATABASE}' if not exists"
#docker compose exec "${DATABASE_CONTAINER}" mariadb -e "CREATE DATABASE IF NOT EXISTS ${MYSQL_DATABASE};"
#wp-cli db create

# Copy dump file into container
DUMP_BASENAME=$(basename "$DUMP_FILE")
docker cp "$DUMP_FILE" "$DATABASE_CONTAINER":/tmp/"$DUMP_BASENAME"

# Check if pv is available
HAS_PV=$(docker exec "$DATABASE_CONTAINER" sh -c 'command -v pv >/dev/null && echo true || echo false')

# Import with or without pv
if [ "$USE_TTY" = true ] && [ "$HAS_PV" = true ]; then
  docker exec -t "$DATABASE_CONTAINER" bash -c "pv /tmp/$DUMP_BASENAME | mariadb -u \"$MYSQL_USER\" -p\"$MYSQL_PASSWORD\" \"$MYSQL_DATABASE\""
else
  docker exec "$DATABASE_CONTAINER" bash -c "mariadb -u \"$MYSQL_USER\" -p\"$MYSQL_PASSWORD\" \"$MYSQL_DATABASE\" < /tmp/$DUMP_BASENAME"
fi

# Clean up: remove the dump file from the container
docker exec "$DATABASE_CONTAINER" rm -f /tmp/"$DUMP_BASENAME"

echo -e "${LIGHTGREEN}[Success]${RESET} Database import done"
