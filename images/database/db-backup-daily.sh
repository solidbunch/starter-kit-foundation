#!/bin/bash
tar -zcf /srv/rsync/backup/db-backup-daily-$(date +%Y%m%d).tar.gz -C /var/lib/ mysql
find /srv/rsync/backup/db-backup-daily-* -mtime +7 -delete