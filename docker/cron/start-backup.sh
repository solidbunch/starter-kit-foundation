#!/bin/bash

# Stop when error
set -e

# Check package availability
command -v gzip >/dev/null 2>&1 || { echo "[Error] Please install gzip"; exit 1; }

# Check app name
if [ ! "$APP_NAME" ]; then
    echo "[Fail] APP_NAME not found in .env"; exit 1;
fi

# Default values
DATABASE_CONTAINER="${APP_NAME}_database"
WORDPRESS_CONTAINER="${APP_NAME}_wordpress"
MODE="daily"
MODE_TIMER=6
BACKUPS_DIR=/srv/wordpress/backups

# Parse args
if [ "$1" ] && ([ "$1" == "daily" ] || [ "$1" == "weekly" ]); then
    MODE="$1"
fi

if [ "$MODE" == "weekly" ]; then
    MODE_TIMER=30
fi




# Create backups directory (if not exist)
mkdir -p "$BACKUPS_DIR"
mkdir -p "$BACKUPS_DIR"/"$MODE"

# Check is backup enable
if [ ! "$APP_WP_BACKUP_ENABLE" ] || [ "$APP_WP_BACKUP_ENABLE" == 0 ]; then
    echo "[Fail] Backup is disabled in .env file"; exit 1;
fi

# Wait 3 times
for i in {1..3}
do
#    if (docker exec "$DATABASE_CONTAINER" mysqladmin -u "$MYSQL_ROOT_USER" --password="${MYSQL_ROOT_PASSWORD}" ping --silent); then
        break
#    fi
    sleep 3
    if [ "$i" = 3 ]; then
        echo "[Fail] Database container '$DATABASE_CONTAINER' is down"; exit 1;
    fi
done


# Make database backup
docker exec "$DATABASE_CONTAINER" \
  mysqldump -u "$MYSQL_ROOT_USER" --password="$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" \
  > "$BACKUPS_DIR"/"$MODE"/database-$(date +%Y-%m-%d).sql

# You can add more databases or use --all-databases parameter to archive all databases in one file
#docker exec "$DATABASE_CONTAINER" \
#  mysqldump -u "$MYSQL_ROOT_USER" --password="$MYSQL_ROOT_PASSWORD" <database_name> \
#  > "$BACKUPS_DIR"/"$MODE"/database-$(date +%Y-%m-%d).sql
#
#docker exec "$DATABASE_CONTAINER" \
#  mysqldump -u "$MYSQL_ROOT_USER" --password="$MYSQL_ROOT_PASSWORD" --all-databases \
#  > "$BACKUPS_DIR"/"$MODE"/database-$(date +%Y-%m-%d).sql


# Make uploads folder archive
docker exec "$WORDPRESS_CONTAINER" tar -cf - -C /var/www/html/wp-content/ uploads > "$BACKUPS_DIR"/"$MODE"/data-$(date +%Y-%m-%d).tar

cd "$BACKUPS_DIR"/"$MODE"/

tar -rf data-$(date +%Y-%m-%d).tar database-$(date +%Y-%m-%d).sql

rm database-$(date +%Y-%m-%d).sql

gzip -f data-$(date +%Y-%m-%d).tar


# Check old files to delete
find "$BACKUPS_DIR"/"$MODE"/data-* -mtime +$MODE_TIMER -delete

echo "[Success] [$MODE] Backup done $(date +%Y'-'%m'-'%d' '%H':'%M)"