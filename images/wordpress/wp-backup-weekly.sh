#!/usr/bin/env bash
tar -zcf /srv/rsync/backup/uploads-backup-weekly-$(date +%Y%m%d).tar.gz -C /var/www/html/wp-content/ uploads
find /srv/rsync/backup/uploads-backup-weekly-* -mtime +31 -delete