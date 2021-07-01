#!/bin/bash
tar -zcf /srv/rsync/backup/db-backup-weekly-$(date +%Y%m%d).tar.gz -C /var/lib/ mysql
find /srv/rsync/backup/db-backup-weekly-* -mtime +31 -delete