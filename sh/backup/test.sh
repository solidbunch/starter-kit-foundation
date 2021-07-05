#!/bin/bash

# Check package availability
command -v docker-compose >/dev/null 2>&1 || { echo "[Error] Please install docker-compose"; exit 1; }
command -v gzip >/dev/null 2>&1 || { echo "[Error] Please install gzip"; exit 1; }

# Go to the project root directory & create backups directory (if not exist)
cd $(dirname "$(readlink -f "$0")")/../../
mkdir -p ./backups

# Check .env file exist
command -f test .env >/dev/null 2>&1 || { echo "[Error] .env file not found in $PWD"; exit 1; }

# Load enviroment variables
source .env

# Make database backup
docker-compose exec -T database /usr/bin/mysqldump -u $MYSQL_ROOT_USER --password=$MYSQL_ROOT_PASSWORD $MYSQL_DATABASE | gzip --rsyncable > ./backups/daily-$MYSQL_DATABASE-$(date +%Y%m%d).sql.gz

# You can add more databases or use --all-databases parameter to archive all databases in one file
#docker-compose exec -T database /usr/bin/mysqldump -u $MYSQL_ROOT_USER --password=$MYSQL_ROOT_PASSWORD <database_name> | gzip --rsyncable > ./backups/daily-<database_name>-$(date +%Y%m%d).sql.gz
#docker-compose exec -T database /usr/bin/mysqldump -u $MYSQL_ROOT_USER --password=$MYSQL_ROOT_PASSWORD --all-databases | gzip --rsyncable > ./backups/daily-all-databases-$(date +%Y%m%d).sql.gz

# Make uploads folder archive
tar -zcf ./backups/daily-media-$(date +%Y%m%d).tar.gz -C ./web/app/ uploads

# Check old files to delete
find ./backups/daily-* -mtime +7 -delete