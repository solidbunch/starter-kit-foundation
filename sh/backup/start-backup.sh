#!/bin/bash

# Check package availability
command -v docker-compose >/dev/null 2>&1 || { echo "[Error] Please install docker-compose"; exit 1; }
command -v gzip >/dev/null 2>&1 || { echo "[Error] Please install gzip"; exit 1; }

# Default values
DATABASE_CONTAINER="database"
MODE="daily"
MODE_TIMER=7

# Parce args
if [ $1 ] && ([ $1 == "daily" ] || [ $1 == "weekly" ]); then
    MODE="$1"
fi

if [ $MODE == "weekly" ]; then
    MODE_TIMER=31
fi




# Go to the project root directory & create backups directory (if not exist)
cd $(dirname "$(readlink -f "$0")")/../../
mkdir -p ./backups

# Check .env file exist
if [ ! -f .env ]; then
    echo "[Error] .env file not found in $PWD"; exit 1;
fi


# Load enviroment variables
source .env

# Check is backup enable
if [ ! $APP_WP_BACKUP_ENABLE ] || [ $APP_WP_BACKUP_ENABLE == 0 ]; then
    echo "[Fail] Backup is disabled in .env file"; exit 1;
fi

# Wait 5 times
for i in {1..5}
do
    if (docker-compose exec -T $DATABASE_CONTAINER mysqladmin -u $MYSQL_ROOT_USER --password=${MYSQL_ROOT_PASSWORD} ping --silent); then
        break
    fi
    sleep 3
    if [ $i = 5 ]; then
        echo "[Fail] Database container '$DATABASE_CONTAINER' is down"; exit 1;
    fi
done


# Make database backup
docker-compose exec -T $DATABASE_CONTAINER mysqldump -u $MYSQL_ROOT_USER --password=$MYSQL_ROOT_PASSWORD $MYSQL_DATABASE | gzip --rsyncable > ./backups/$MODE-$MYSQL_DATABASE-$(date +%Y%m%d).sql.gz

# You can add more databases or use --all-databases parameter to archive all databases in one file
#docker-compose exec -T $DATABASE_CONTAINER mysqldump -u $MYSQL_ROOT_USER --password=$MYSQL_ROOT_PASSWORD <database_name> | gzip --rsyncable > ./backups/$MODE-<database_name>-$(date +%Y%m%d).sql.gz
#docker-compose exec -T $DATABASE_CONTAINER mysqldump -u $MYSQL_ROOT_USER --password=$MYSQL_ROOT_PASSWORD --all-databases | gzip --rsyncable > ./backups/$MODE-all-databases-$(date +%Y%m%d).sql.gz

# Make uploads folder archive
tar -zcf ./backups/$MODE-media-$(date +%Y%m%d).tar.gz -C ./web/app/ uploads

# Check old files to delete
find ./backups/$MODE-* -mtime +$MODE_TIMER -delete

echo "[Success] Backup done $(date +%Y'-'%m'-'%d' '%H':'%M)"