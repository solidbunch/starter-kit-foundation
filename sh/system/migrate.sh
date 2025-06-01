#!/bin/bash
# migrate.sh - Transfer WordPress DB and uploads between environments.
#
# Usage:
#   sh/system/migrate.sh -s <source_env> -d <dest_env>
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
source ./sh/utils/colors.sh

set -o pipefail

ENV_DIR="./config/environment"
LOCAL_ENV="local"
CURRENT_DATE=$(date +%Y-%m-%d)

TMP_DIR=$(mktemp -d "./tmp/migration-${CURRENT_DATE}-XXXXXXXX")

REMOTE_TMP="/tmp/migrate"

DUMP_FILE="${MYSQL_HOST}-${MYSQL_DATABASE}-${CURRENT_DATE}.sql"
MEDIA_ARCHIVE="media-${CURRENT_DATE}.tar"

# Discover available environments
AVAILABLE_ENVS=$(find "$ENV_DIR" -maxdepth 1 -type f -name '.env.type.*' ! -name '*.override' \
  -exec basename {} \; | sed 's/\.env\.type\.//' | tr '\n' ' ' | xargs)

if [[ -z "$AVAILABLE_ENVS" ]]; then
  echo -e "${LIGHTRED}[Error]${RESET} no .env.type.* files found in $ENV_DIR"; exit 1;
fi

# Parse CLI arguments
while getopts "s:d:h" opt; do
  case $opt in
    s) SRC="$OPTARG" ;;
    d) DST="$OPTARG" ;;
    h) echo "Usage: $0 -s <source_env> -d <dest_env>"; echo -e "Available environments: ${YELLOW}$AVAILABLE_ENVS${RESET}"; exit 0 ;;
    *) echo "Invalid option. Use -h for help"; exit 1 ;;
  esac
done

# Validate source and destination
if [[ -z "$SRC" || -z "$DST" ]]; then
  echo -e "${LIGHTRED}[Error]${RESET} both -source and destination are required. Usage: $0 <source_env> <dest_env>"
  echo -e "Available environments: ${YELLOW}$AVAILABLE_ENVS${RESET}"
  exit 1;
fi

if ! echo "$AVAILABLE_ENVS" | grep -qw "$SRC"; then
  echo -e "${LIGHTRED}[Error]${RESET} Source environment '$SRC' not found"
  echo -e "Available environments: ${YELLOW}$AVAILABLE_ENVS${RESET}"
  exit 1;
fi
if ! echo "$AVAILABLE_ENVS" | grep -qw "$DST"; then
  echo -e "${LIGHTRED}[Error]${RESET} Destination environment '$DST' not found"
  echo -e "Available environments: ${YELLOW}$AVAILABLE_ENVS${RESET}"
  exit 1
fi

SRC_ENV="$ENV_DIR/.env.type.$SRC"
DST_ENV="$ENV_DIR/.env.type.$DST"

SRC_DOMAIN=$(grep ^APP_DOMAIN= "$SRC_ENV" | cut -d= -f2 | tr -d '"')
DST_DOMAIN=$(grep ^APP_DOMAIN= "$DST_ENV" | cut -d= -f2 | tr -d '"')

if [[ -z "$SRC_DOMAIN" || -z "$DST_DOMAIN" ]]; then
  echo -e "${LIGHTRED}[Error]${RESET} APP_DOMAIN not found in env files"
  exit 1
fi

# User confirmation
echo -e "${LIGHTYELLOW}[Warning]${RESET} This will transfer the database and uploads from ${YELLOW}$SRC_DOMAIN ($SRC)${RESET} to ${YELLOW}$DST_DOMAIN ($DST)${RESET}. Existing data in the destination environment will be replaced."
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
  rm -f "$TMP_DIR/$DUMP_FILE" "$TMP_DIR/$MEDIA_ARCHIVE"
}
#trap cleanup EXIT

echo -e "${CYAN}[Info]${RESET} Migrating from ${YELLOW} $SRC_DOMAIN ($SRC)${RESET} to ${YELLOW}$DST_DOMAIN ($DST)${RESET}"

# Step 1: Export from source
echo "📤 Exporting from source ($SRC)..."
echo "Using temp dir: $TMP_DIR"

if [[ "$SRC" == "$LOCAL_ENV" ]]; then
  # Step 1: Export database dump without users and usermeta tables
  bash sh/database/export.sh -f "${TMP_DIR}/${DUMP_FILE}" -i true

  # Step 2: Export media files without compression (uploads and languages)
  bash ./sh/media/export.sh -f "${TMP_DIR}/${MEDIA_ARCHIVE}" -n

  # Step 3: Combine into one .tar archive
  tar -cf "${TMP_DIR}/migration-${SRC}-${CURRENT_DATE}.tar" -C "${TMP_DIR}" "$(basename "$MEDIA_ARCHIVE")" "$(basename "$DUMP_FILE")"

  # Step 4: Remove individual files
  rm "${TMP_DIR}/${DUMP_FILE}" "${TMP_DIR}/${MEDIA_ARCHIVE}"

  # Step 5: Compress the final archive
  gzip -f "${TMP_DIR}/migration-${SRC}-${CURRENT_DATE}.tar"

else
  ssh "$SRC_DOMAIN" "mkdir -p $REMOTE_TMP && cd /app && bash sh/database/export.sh -f "$REMOTE_TMP/$DUMP_FILE" -i true && tar -czf $REMOTE_TMP/$UPLOADS_ARCHIVE -C web/wp-content uploads"
  scp "$SRC:$REMOTE_TMP/$DUMP_FILE" "$TMP_DIR/"
  scp "$SRC:$REMOTE_TMP/$UPLOADS_ARCHIVE" "$TMP_DIR/"
fi

exit 0

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

echo -e "${LIGHTGREEN}[Success]${RESET} ✅ Migration complete!"
