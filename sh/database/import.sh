#!/bin/bash

# This script imports a database dump into the current database.

# Load environment and colors
source ./.env
source ./sh/utils/colors.sh

# Stop on any error and fail on pipe errors
set -e -o pipefail

DATABASE_CONTAINER="${APP_NAME}-mariadb"

# Defaults
DUMP_FILE=""
CONFIRM=true

# Parse args
while getopts "f:d:yh" opt; do
  case $opt in
    f) DUMP_FILE="$OPTARG" ;;
    d) MYSQL_DATABASE="$OPTARG" ;; # override database
    y) CONFIRM=false ;;            # skip confirmation
    h)
      echo "Usage: $0 -f <dump_file.sql> [-d <database>] [-y (skip confirm)]"
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

#docker exec -i "$DATABASE_CONTAINER" sh -c "pv | mariadb -u \"$MYSQL_USER\" -p\"$MYSQL_PASSWORD\" \"$MYSQL_DATABASE\"" < "$DUMP_FILE"

DUMP_BASENAME=$(basename "$DUMP_FILE")

docker cp "$DUMP_FILE" "$DATABASE_CONTAINER":/tmp/"$DUMP_BASENAME"

docker exec -it "$DATABASE_CONTAINER" bash -c "pv /tmp/$DUMP_BASENAME | mariadb -u \"$MYSQL_USER\" -p\"$MYSQL_PASSWORD\" \"$MYSQL_DATABASE\""

docker exec "$DATABASE_CONTAINER" rm -f /tmp/"$DUMP_BASENAME"



# Import data from sql file with pv
#if docker exec "$DATABASE_CONTAINER" command -v pv >/dev/null 2>&1; then

#else
#  docker exec -i "$DATABASE_CONTAINER" mariadb -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" < "$DUMP_FILE"
#fi


echo -e "${LIGHTGREEN}[Success]${RESET} Database import done"



# Run database domains replacement
#docker compose exec "${WP_CONTAINER}" su -c "bash /shell/wp-cli/search-replace.sh" "${DEFAULT_USER}"


