#!/usr/bin/env bash

crontab -u root /etc/crontabs/root
crontab -u www-data /etc/crontabs/www-data
crond -b
php-fpm