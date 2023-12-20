#!/usr/bin/env bash

# Based on https://habr.com/ru/company/redmadrobot/blog/305364/
# https://github.com/renskiy/cron-docker-image
# Thanks to renskiy

# Stop when error
set -e

# start cron
chown "root:root" /etc/crontabs/root

crond -L /var/log/cron.log -c /etc/crontabs

# trap SIGINT and SIGTERM signals and gracefully exit
trap "echo \"stopping cron\"; kill \$!; exit" SIGINT SIGTERM

# start "daemon"
while true
do
    cat /var/log/cron.log & wait $!
done
