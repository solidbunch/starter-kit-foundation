#!/bin/bash

# Change to the script's directory
cd $(dirname "$(readlink -f "$0")")

docker-compose exec database sh -c 'exec mysqldump --all-databases -uroot -p"$MYSQL_ROOT_PASSWORD"' > ./backup/all-databases.sql
tar -zcf ../../backups/daily-$(date +%Y%m%d).tar.gz -C ../../web/app/ uploads

find ../../backups/daily-* -mtime +7 -delete