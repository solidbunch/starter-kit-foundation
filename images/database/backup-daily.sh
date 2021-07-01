#!/usr/bin/env bash
tar -zcf /srv/rsync/backup/backup-daily-$(date +%Y%m%d).tar.gz -C /var/www/ html
find /srv/rsync/backup/backup-daily-* -mtime +7 -delete