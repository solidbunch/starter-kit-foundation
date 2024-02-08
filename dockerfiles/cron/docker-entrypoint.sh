#!/usr/bin/env bash

set -Eeuo pipefail

# Prepare root crontab file
cp /tmp/crontabs/root /etc/crontabs/root
chown "root:root" /etc/crontabs/root

# Set the file permissions to -rw-r--r--
chmod 644 /etc/crontabs/root

## exec cron (added as parameter in Dockerfile CMD ["start-cron.sh"])
exec "$@"
