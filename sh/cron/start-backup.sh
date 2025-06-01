#!/bin/bash

# Script to backup WordPress database and media files

# Load environment and colors
source ./.env
source ./sh/utils/colors.sh

# Stop when error
set -e

# Check package availability
command -v gzip >/dev/null 2>&1 || { echo "[Cron][Error] Please install gzip"; exit 1; }

# Check app name
if [ -z "$APP_NAME" ]; then
    echo "[Cron][Fail] APP_NAME not found in .env"; exit 1;
fi

# Default values
MODE="daily"
MODE_TIMER=6
BACKUPS_DIR=./backups
CURRENT_DATE=$(date +%Y-%m-%d)

# Parse args
if [ "$1" ] && { [ "$1" == "daily" ] || [ "$1" == "weekly" ]; }; then
    MODE="$1"
fi

if [ "$MODE" == "weekly" ]; then
    MODE_TIMER=30
fi

# Check if backup is enabled
if [ -z "$APP_WP_BACKUP_ENABLE" ] || [ "$APP_WP_BACKUP_ENABLE" = 0 ]; then
    echo "[Cron][Fail] Backup is disabled in .env file"; exit 1
fi

# Create backup directory
mkdir -p "$BACKUPS_DIR/$MODE"

DB_DUMP="$BACKUPS_DIR/$MODE/database-$CURRENT_DATE.sql"
MEDIA_ARCHIVE="$BACKUPS_DIR/$MODE/media-$CURRENT_DATE.tar"

# Step 1: Export database
bash ./sh/database/export.sh -f "$DB_DUMP"
# ToDo add all databases with mysql, information_schema, performance_schema, sys to backup

# Step 2: Export media files (without compression)
bash ./sh/media/export.sh -f "$MEDIA_ARCHIVE" -n

# Step 3: Combine into one .tar archive
tar -cf "$BACKUPS_DIR/$MODE/$MODE-$CURRENT_DATE.tar" -C "$BACKUPS_DIR/$MODE" "$(basename "$MEDIA_ARCHIVE")" "$(basename "$DB_DUMP")"

# Step 4: Remove individual files
rm "$DB_DUMP" "$MEDIA_ARCHIVE"

# Step 5: Compress the final archive
gzip -f "$BACKUPS_DIR/$MODE/$MODE-$CURRENT_DATE.tar"

# Step 6: Cleanup old backups
find "$BACKUPS_DIR/$MODE" -name "$MODE-*" -mtime +$MODE_TIMER -delete

# Done
echo -e "${LIGHTGREEN}[Success]${RESET} [$MODE] Backup done $(date +%Y'-'%m'-'%d' '%H':'%M)"
