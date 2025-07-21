#!/bin/bash

# This script exports files (e.g., uploads, languages) from a Docker container to a local archive.

# Stop on any error and fail on pipe errors
set -e -o pipefail

# Load environment and colors
source ./sh/utils/colors.sh
source ./.env

WEB_CONTAINER="${APP_NAME}-php"
OUTPUT_DIR="./tmp"
OUTPUT_FILE="${OUTPUT_DIR}/${APP_NAME}-media-${WP_ENVIRONMENT_TYPE}-${APP_DOMAIN}-$(date +%Y-%m-%d).tar.gz"
COMPRESS=true

# Parse CLI arguments
while getopts "f:nh" opt; do
  case $opt in
    f) OUTPUT_FILE="$OPTARG" ;;
    n) COMPRESS=false ;;
    h) echo "Usage: $0 [-f <output_file>] [-n (no compression)]"; exit 0 ;;
    *) echo "Invalid option. Use -h for help"; exit 1 ;;
  esac
done

# Create output directory if it does not exist
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Updating the archive file name if it does not end with .tar or .tar.gz
if [ "$COMPRESS" = true ]; then
  TAR_FLAGS="czf"
  [[ "$OUTPUT_FILE" != *.tar.gz ]] && OUTPUT_FILE="${OUTPUT_FILE%.tar}.tar.gz"
else
  TAR_FLAGS="cf"
  OUTPUT_FILE="${OUTPUT_FILE%.gz}"
fi

echo "Exporting files from '${WEB_CONTAINER}' ..."

# Perform export with fallback if some folders don't exist
docker exec "$WEB_CONTAINER" sh -c "\
  cd /srv/web/wp-content && \
  tar $TAR_FLAGS - \$(ls -d uploads languages 2>/dev/null)" > "$OUTPUT_FILE"

echo -e "${LIGHTGREEN}[Success]${RESET} Files exported to: '${BOLD}${OUTPUT_FILE}${RESET}'"
