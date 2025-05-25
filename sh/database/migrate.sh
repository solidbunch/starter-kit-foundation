#!/bin/bash
# migrate.sh - Transfer WordPress DB and uploads between environments.
#
# Usage:
#   sh/migrate.sh -s <source_env> -d <dest_env>
# Environments are auto-detected from config/environment/.env.type.*
#
# Requirements:
#   - SSH access set up via ~/.ssh/config for remote envs
#   - Existing helper scripts:
#       - sh/database/export.sh
#       - sh/database/import.sh
#       - sh/wp-cli/search-replace.sh
#   - .env.type.* files inside config/environment/

# Source the .env file
source ./.env

# Colors
source ./sh/utils/colors

set -o pipefail

ENV_DIR="./config/environment"
LOCAL_ENV="local"
TMP_DIR="./tmp"
REMOTE_TMP="/tmp/migrate"
DUMP_FILE="db.sql"
# Take database hostname from .env file
#DUMP_FILE="$MYSQL_HOST"-"$MYSQL_DATABASE"-"$ENVIRONMENT_TYPE"-"$APP_DOMAIN"-$(date +%Y-%m-%d).sql
UPLOADS_ARCHIVE="uploads.tar.gz"

# Discover available environments
AVAILABLE_ENVS=$(find "$ENV_DIR" -maxdepth 1 -type f -name '.env.type.*' ! -name '*.override' \
  -exec basename {} \; | sed 's/\.env\.type\.//' | tr '\n' ' ' | xargs)

if [[ -z "$AVAILABLE_ENVS" ]]; then
  echo -e "${LIGHTRED}[Error]${NOCOLOR} no .env.type.* files found in $ENV_DIR"; exit 1;
fi

# Parse CLI arguments
while getopts "s:d:h" opt; do
  case $opt in
    s) SRC="$OPTARG" ;;
    d) DST="$OPTARG" ;;
    h) echo "Usage: $0 -s <source_env> -d <dest_env>"; echo -e "Available environments: ${YELLOW}$AVAILABLE_ENVS${NOCOLOR}"; exit 0 ;;
    *) echo "Invalid option. Use -h for help"; exit 1 ;;
  esac
done

echo SRC: "$SRC"
#
#if [ "$1" != "" ]; then
#  SRC="$1"
#else
#  echo -e "${LIGHTRED}[Error]${NOCOLOR} Source environment not specified. Usage: $0 <source_env> <dest_env>"
#  echo -e "Available environments: ${YELLOW}$AVAILABLE_ENVS${NOCOLOR}"
#  exit 1;
#fi

#if [ "$2" != "" ]; then
#  DST="$2"
#else
#  echo -e "${LIGHTRED}[Error]${NOCOLOR} Destination environment not specified. Usage: $0 <source_env> <dest_env>"
#  echo -e "Available environments: ${YELLOW}$AVAILABLE_ENVS${NOCOLOR}"
#  exit 1;
#fi




# Validate source and destination
if [[ -z "$SRC" || -z "$DST" ]]; then
  echo -e "${LIGHTRED}[Error]${NOCOLOR} both -source and destination are required. Usage: $0 <source_env> <dest_env>"
  echo -e "Available environments: ${YELLOW}$AVAILABLE_ENVS${NOCOLOR}"
  exit 1;
fi

if ! echo "$AVAILABLE_ENVS" | grep -qw "$SRC"; then
  echo -e "${LIGHTRED}[Error]${NOCOLOR} Source environment '$SRC' not found"
  echo -e "Available environments: ${YELLOW}$AVAILABLE_ENVS${NOCOLOR}"
  exit 1;
fi
if ! echo "$AVAILABLE_ENVS" | grep -qw "$DST"; then
  echo -e "${LIGHTRED}[Error]${NOCOLOR} Destination environment '$DST' not found"
  echo -e "Available environments: ${YELLOW}$AVAILABLE_ENVS${NOCOLOR}"
  exit 1
fi

SRC_ENV="$ENV_DIR/.env.type.$SRC"
DST_ENV="$ENV_DIR/.env.type.$DST"

SRC_DOMAIN=$(grep ^APP_DOMAIN= "$SRC_ENV" | cut -d= -f2 | tr -d '"')
DST_DOMAIN=$(grep ^APP_DOMAIN= "$DST_ENV" | cut -d= -f2 | tr -d '"')

if [[ -z "$SRC_DOMAIN" || -z "$DST_DOMAIN" ]]; then
  echo -e "${LIGHTRED}[Error]${NOCOLOR} APP_DOMAIN not found in env files"
  exit 1
fi

# User confirmation
echo -e "${LIGHTYELLOW}[Warning]${NOCOLOR} This will transfer the database and uploads from ${YELLOW}$SRC_DOMAIN ($SRC)${NOCOLOR} to ${YELLOW}$DST_DOMAIN ($DST)${NOCOLOR}. Existing data in the destination environment will be replaced."
read -rp "Are you sure? (y/n): " choice
if [[ ! $choice =~ ^[Yy](es)?$ ]]; then
  echo "Not confirmed. Exiting."
  exit 0
fi

## Start migration process

# Create temporary directory
mkdir -p "$TMP_DIR"

# Cleanup on exit
cleanup() {
  echo "🧹 Cleaning up..."
  [[ "$SRC" != "$LOCAL_ENV" ]] && ssh "$SRC" "rm -rf $REMOTE_TMP"
  [[ "$DST" != "$LOCAL_ENV" ]] && ssh "$DST" "rm -rf $REMOTE_TMP"
  rm -f "$TMP_DIR/$DUMP_FILE" "$TMP_DIR/$UPLOADS_ARCHIVE"
}
#trap cleanup EXIT

echo -e "${CYAN}[Info]${NOCOLOR} Migrating from ${YELLOW} $SRC_DOMAIN ($SRC)${NOCOLOR} to ${YELLOW}$DST_DOMAIN ($DST)${NOCOLOR}"

# Step 1: Export from source
echo "📤 Exporting from source ($SRC)..."

DUMP_FILE="$MYSQL_HOST"-"$MYSQL_DATABASE"-"$SRC"-"$APP_DOMAIN"-migration-$(date +%Y-%m-%d).sql

if [[ "$SRC" == "$LOCAL_ENV" ]]; then
  mkdir -p "$REMOTE_TMP"
  # shellcheck source=config/environment/.env.type.ENV_NAME
  source "$SRC_ENV"
  bash sh/database/export.sh "$TMP_DIR/$DUMP_FILE"
  tar -czf "$TMP_DIR/$UPLOADS_ARCHIVE" -C web/wp-content uploads
else
  ssh "$SRC" "mkdir -p $REMOTE_TMP && cd /app && source $SRC_ENV && sh sh/database/export.sh > $REMOTE_TMP/$DUMP_FILE && tar -czf $REMOTE_TMP/$UPLOADS_ARCHIVE -C web/wp-content uploads"
  scp "$SRC:$REMOTE_TMP/$DUMP_FILE" "$TMP_DIR/"
  scp "$SRC:$REMOTE_TMP/$UPLOADS_ARCHIVE" "$TMP_DIR/"
fi

# Step 2: Import into destination
echo "📥 Importing into destination ($DST)..."

if [[ "$DST" == "$LOCAL_ENV" ]]; then
  source "$DST_ENV"
  sh sh/database/import.sh < "$TMP_DIR/$DUMP_FILE"
  rm -rf web/wp-content/uploads
  tar -xzf "$TMP_DIR/$UPLOADS_ARCHIVE" -C web/wp-content
  sh sh/wp-cli/search-replace.sh "$SRC_DOMAIN" "$DST_DOMAIN"
else
  ssh "$DST" "mkdir -p $REMOTE_TMP"
  scp "$TMP_DIR/$DUMP_FILE" "$DST:$REMOTE_TMP/"
  scp "$TMP_DIR/$UPLOADS_ARCHIVE" "$DST:$REMOTE_TMP/"
  ssh "$DST" "cd /app && source $DST_ENV && sh sh/database/import.sh < $REMOTE_TMP/$DUMP_FILE"
  ssh "$DST" "rm -rf /app/web/wp-content/uploads && tar -xzf $REMOTE_TMP/$UPLOADS_ARCHIVE -C /app/web/wp-content"
  ssh "$DST" "cd /app && source $DST_ENV && sh sh/wp-cli/search-replace.sh '$SRC_DOMAIN' '$DST_DOMAIN'"
fi

echo -e "${LIGHTGREEN}[Success]${NOCOLOR} ✅ Migration complete!"
