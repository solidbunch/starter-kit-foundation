#!/bin/bash
# migrate.sh - Transfer WordPress DB and uploads between environments.
#
# Usage:
#   sh/system/migrate.sh -s <source_env> -d <dest_env> [-t]
# Options:
#   -s <source_env>  Source environment (e.g., local, staging, production)
#   -d <dest_env>    Destination environment (e.g., local, staging, production)
#   -t                Use TTY for progress visualization (requires pv)
#   -h                Show this help message
#
# Environments are auto-detected from config/environment/.env.type.*
#
# Requirements:
#   - SSH access set up via ~/.ssh/config for remote envs
#   - Existing helper scripts:
#       - sh/database/export.sh
#       - sh/database/import.sh
#       - sh/wp-cli/search-replace.sh
#   - .env.type.* files inside config/environment/

# Load environment and colors
source ./.env
source ./sh/utils/colors.sh

# Stop on any error and fail on pipe errors
set -e -o pipefail

ENV_DIR="./config/environment"
LOCAL_ENV="local"
CURRENT_DATE=$(date +%Y-%m-%d)

# Attention: relative path to the tmp directory used on local and remote servers
TMP_DIR=$(mktemp -d "tmp/migration-${CURRENT_DATE}-XXXXXXXX")

DUMP_FILE="${MYSQL_HOST}-${MYSQL_DATABASE}-${CURRENT_DATE}.sql"
MEDIA_ARCHIVE="media-${CURRENT_DATE}.tar"

# Use TTY for pv progress visualization
USE_TTY=false
TTY_FLAG=""

# Discover available environments
AVAILABLE_ENVS=$(find "$ENV_DIR" -maxdepth 1 -type f -name '.env.type.*' ! -name '*.override' \
  -exec basename {} \; | sed 's/\.env\.type\.//' | tr '\n' ' ' | xargs)

if [[ -z "$AVAILABLE_ENVS" ]]; then
  echo -e "${LIGHTRED}[Error]${RESET} no .env.type.* files found in $ENV_DIR"; exit 1;
fi

# Parse CLI arguments
while getopts "s:d:th" opt; do
  case $opt in
    s) SRC="$OPTARG" ;;            # source environment
    d) DST="$OPTARG" ;;            # destination environment
    t)
      USE_TTY=true                 # use TTY for pv
      TTY_FLAG="-t"
      ;;
    h)
      echo "Usage: $0 -s <source_env> -d <dest_env> [-t]";
      echo "Options:";
      echo "  -s <source_env>  : Source environment (e.g., local, staging, production)"
      echo "  -d <dest_env>    : Destination environment (e.g., local, staging, production)"
      echo "  -t               : Use TTY for progress visualization (requires pv)"
      echo "  -h               : Show this help message"
      echo -e "Available environments: ${YELLOW}$AVAILABLE_ENVS${RESET}"
      exit 0
      ;;
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

# Cleanup on exit
cleanup() {
  echo "🧹 Cleaning up..."
  [[ "$SRC" != "$LOCAL_ENV" ]] && ssh "$SRC" "rm -rf $REMOTE_TMP"
  [[ "$DST" != "$LOCAL_ENV" ]] && ssh "$DST" "rm -rf $REMOTE_TMP"
  rm -f "$TMP_DIR/$DUMP_FILE" "$TMP_DIR/$MEDIA_ARCHIVE"
}
#trap cleanup EXIT

echo -e "${CYAN}[Info]${RESET} Migrating from ${YELLOW}$SRC_DOMAIN ($SRC)${RESET} to ${YELLOW}$DST_DOMAIN ($DST)${RESET}"

# Step 1: Export from source
echo "----------------------------------------------------------------------------"
echo -e "${CYAN}[Info]${RESET} Using $SRC environment for source export (${SRC_DOMAIN})"
echo "----------------------------------------------------------------------------"

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
  # Remote source export
  ssh ${TTY_FLAG} "$SRC_DOMAIN" "
    set -e
    cd /srv/${SRC_DOMAIN}
    mkdir -p ${TMP_DIR}
    bash sh/database/export.sh -f ${TMP_DIR}/${DUMP_FILE} -i true
    bash sh/media/export.sh -f ${TMP_DIR}/${MEDIA_ARCHIVE} -n
    tar -cf ${TMP_DIR}/migration-${SRC}-${CURRENT_DATE}.tar -C ${TMP_DIR} $(basename $MEDIA_ARCHIVE) $(basename $DUMP_FILE)
    rm ${TMP_DIR}/${DUMP_FILE} ${TMP_DIR}/${MEDIA_ARCHIVE}
    gzip -f ${TMP_DIR}/migration-${SRC}-${CURRENT_DATE}.tar
  "

  echo -e "${CYAN}[Info]${RESET} Transferring migration archive from source (${SRC_DOMAIN}) to local..."

  # Transfer archive to local
  scp "${SRC_DOMAIN}:/srv/${SRC_DOMAIN}/${TMP_DIR}/migration-${SRC}-${CURRENT_DATE}.tar.gz" "${TMP_DIR}/"

fi

echo "----------------------------------------------------------------------------"
echo -e "${LIGHTGREEN}[Success]${RESET} ✅ Source $SRC export complete! Archive saved to: ${BOLD}${TMP_DIR}/migration-${SRC}-${CURRENT_DATE}.tar.gz${RESET}"
echo "----------------------------------------------------------------------------"
echo -e "${CYAN}[Info]${RESET} Connecting to $DST environment (${DST_DOMAIN}) and preparing for import..."
echo "----------------------------------------------------------------------------"

# Step 2: Import into destination
if [[ "$DST" == "$LOCAL_ENV" ]]; then

  # Extract full migration archive
  tar -xzf "${TMP_DIR}/migration-${SRC}-${CURRENT_DATE}.tar.gz" -C "${TMP_DIR}"

  # Import database
  bash sh/database/import.sh -f "${TMP_DIR}/${DUMP_FILE}" -y ${TTY_FLAG}

  # Replace wp-content/uploads with extracted media
  rm -rf web/wp-content/uploads
  rm -rf web/wp-content/languages
  tar -xf "${TMP_DIR}/${MEDIA_ARCHIVE}" -C web/wp-content

  # Run search-replace
  docker compose exec php su -c "bash /shell/wp-cli/search-replace.sh" "${DEFAULT_USER}"

else

  ssh ${TTY_FLAG} "$DST_DOMAIN" "
    set -e
    mkdir -p /srv/${DST_DOMAIN}/${TMP_DIR}
  "

  echo -e "${CYAN}[Info]${RESET} Transferring migration archive to destination (${DST_DOMAIN})..."

  # Transfer archive to remote
  scp "${TMP_DIR}/migration-${SRC}-${CURRENT_DATE}.tar.gz" "${DST_DOMAIN}:/srv/${DST_DOMAIN}/${TMP_DIR}/"

  # Remote execution
  ssh ${TTY_FLAG} "$DST_DOMAIN" "
    set -e
    cd /srv/${DST_DOMAIN}

    # Extract archive contents
    tar -xzf \"${TMP_DIR}/migration-${SRC}-${CURRENT_DATE}.tar.gz\" -C \"${TMP_DIR}\"

    # Import database
    bash sh/database/import.sh -f \"${TMP_DIR}/${DUMP_FILE}\" -y ${TTY_FLAG}

    # Replace wp-content/uploads with extracted media
    rm -rf web/wp-content/uploads
    rm -rf web/wp-content/languages
    tar -xf \"${TMP_DIR}/${MEDIA_ARCHIVE}\" -C web/wp-content

    # Run search-replace
    docker compose exec php su -c \"bash /shell/wp-cli/search-replace.sh\" \"${DEFAULT_USER}\"
  "
fi

echo "----------------------------------------------------------------------------"
echo -e "${LIGHTGREEN}[Success]${RESET} ✅ Migration complete!"
echo "----------------------------------------------------------------------------"
