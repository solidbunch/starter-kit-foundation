#!/bin/bash

# Stop when error
set -e

# Check package availability
command -v gzip >/dev/null 2>&1 || { echo "[Cron][Error] Please install gzip"; exit 1; }

# Check app name
if [ ! "$APP_NAME" ]; then
    echo "[Cron][Fail] APP_NAME not found in .env"; exit 1;
fi

# Default values
DATABASE_CONTAINER="${APP_NAME}-mariadb"
WORDPRESS_CONTAINER="${APP_NAME}-php"
MODE="daily"
MODE_TIMER=6
BACKUPS_DIR=/srv/backups
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

# Wait 3 times
for i in {1..3}
do
    if (docker exec "$DATABASE_CONTAINER" mariadb-admin -u "$MYSQL_ROOT_USER" --password="${MYSQL_ROOT_PASSWORD}" ping > /dev/null 2>&1); then
        break
    fi
    sleep 3
    if [ "$i" = 3 ]; then
        echo "[Cron][Fail] Database container '$DATABASE_CONTAINER' is down"; exit 1;
    fi
done

# Make database backup
docker exec "$DATABASE_CONTAINER" \
  mariadb-dump -u "$MYSQL_ROOT_USER" --password="$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" \
  > "$BACKUPS_DIR"/"$MODE"/database-"$CURRENT_DATE".sql

# You can add more databases or use --all-databases parameter to archive all databases in one file
#docker exec "$DATABASE_CONTAINER" \
#  mariadb-dump -u "$MYSQL_ROOT_USER" --password="$MYSQL_ROOT_PASSWORD" <database_name> \
#  > "$BACKUPS_DIR"/"$MODE"/database-"$CURRENT_DATE".sql
#
#docker exec "$DATABASE_CONTAINER" \
#  mariadb-dump -u "$MYSQL_ROOT_USER" --password="$MYSQL_ROOT_PASSWORD" --all-databases \
#  > "$BACKUPS_DIR"/"$MODE"/database-"$CURRENT_DATE".sql


# Make uploads and languages folders archive
#docker exec "$WORDPRESS_CONTAINER" \
#  tar -cf - -C /srv/web/wp-content/ uploads languages > "$BACKUPS_DIR/$MODE/$MODE-$CURRENT_DATE.tar"

docker exec "$WORDPRESS_CONTAINER" sh -c "\
  if [ -d /srv/web/wp-content/uploads ] && [ -d /srv/web/wp-content/languages ]; then \
    tar -cf - -C /srv/web/wp-content/ uploads languages; \
  elif [ -d /srv/web/wp-content/uploads ]; then \
    tar -cf - -C /srv/web/wp-content/ uploads; \
  elif [ -d /srv/web/wp-content/languages ]; then \
    tar -cf - -C /srv/web/wp-content/ languages; \
  else \
    echo 'Neither uploads nor languages directory exists'; \
  fi" > "$BACKUPS_DIR/$MODE/$MODE-$CURRENT_DATE.tar"

# Combine all in one archive
cd "$BACKUPS_DIR"/"$MODE"/

tar -rf "$MODE"-"$CURRENT_DATE".tar database-"$CURRENT_DATE".sql

rm database-"$CURRENT_DATE".sql

gzip -f "$MODE"-"$CURRENT_DATE".tar


# Check old files to delete
find "$BACKUPS_DIR"/"$MODE"/"$MODE"-* -mtime +$MODE_TIMER -delete

echo "[Cron][Success] [$MODE] Backup done $(date +%Y'-'%m'-'%d' '%H':'%M)"
