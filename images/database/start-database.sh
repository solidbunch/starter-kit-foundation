#!/bin/bash

crontab -u root /etc/cron.d/root
cron
mysqld --user=mysql