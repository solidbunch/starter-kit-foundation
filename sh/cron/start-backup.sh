#!/bin/bash

# Source the .env file
source ./.env

# Colors
source ./sh/utils/colors.sh

# Stop when error
set -e

# Check package availability
command -v gzip >/dev/null 2>&1 || { echo "[Cron][Error] Please install gzip"; exit 1; }

# Check app name
if [ ! "$APP_NAME" ]; then
    echo "[Cron][Fail] APP_NAME not found in .env"; exit 1;
fi

# Default values
WORDPRESS_CONTAINER="${APP_NAME}-php"
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


# Check is backup enable
if [ ! "$APP_WP_BACKUP_ENABLE" ] || [ "$APP_WP_BACKUP_ENABLE" == 0 ]; then
    echo "[Cron][Fail] Backup is disabled in .env file"; exit 1;
fi

# Create backups directory (if not exist)
mkdir -p "$BACKUPS_DIR"
mkdir -p "$BACKUPS_DIR"/"$MODE"

bash ./sh/database/export.sh -f "$BACKUPS_DIR"/"$MODE"/database-"$CURRENT_DATE".sql
# ToDo add all databases with mysql, information_schema, performance_schema, sys to backup

# Make uploads and languages folders archive
#docker exec "$WORDPRESS_CONTAINER" \
#  tar -cf - -C /srv/web/wp-content/ uploads languages > "$BACKUPS_DIR/$MODE/$MODE-$CURRENT_DATE.tar"
docker exec "$WORDPRESS_CONTAINER" sh -c '\
  cd /srv/web/wp-content && \
  tar -cf - $(ls -d uploads languages 2>/dev/null)' \
  > "$BACKUPS_DIR/$MODE/$MODE-$CURRENT_DATE.tar"

# Combine all in one archive
tar -rf "$BACKUPS_DIR"/"$MODE"/"$MODE"-"$CURRENT_DATE".tar "$BACKUPS_DIR"/"$MODE"/database-"$CURRENT_DATE".sql

rm "$BACKUPS_DIR"/"$MODE"/database-"$CURRENT_DATE".sql

gzip -f "$BACKUPS_DIR"/"$MODE"/"$MODE"-"$CURRENT_DATE".tar


# Check old files to delete
find "$BACKUPS_DIR"/"$MODE"/"$MODE"-* -mtime +$MODE_TIMER -delete

echo "[Cron][Success] [$MODE] Backup done $(date +%Y'-'%m'-'%d' '%H':'%M)"
