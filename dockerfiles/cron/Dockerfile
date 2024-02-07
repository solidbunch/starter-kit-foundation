# Based on https://habr.com/ru/company/redmadrobot/blog/305364/
# https://github.com/renskiy/cron-docker-image
# Thanks to renskiy

FROM alpine:3.18

RUN set -ex \
# Install bash
    && apk add --no-cache \
    bash \
# Install docker-cli only. We need just run `docker exec` command, we do not need 'Docker-in-Docker'
# https://jpetazzo.github.io/2015/09/03/do-not-use-docker-in-docker-for-ci/
    docker-cli \
# Add GNU tar
    tar \
# WordPress backups dir
    && mkdir -p  /srv/wordpress/backups \
# Cron log dir used to send logs into container logs
    && mkdir -p /var/log/cron \
# making logging pipe
    && mkfifo -m 0666 /var/log/cron.log \
    && ln -s /var/log/cron.log /var/log/crond.log

# Copy current crontab into container
COPY crontabs/root /etc/crontabs/root

# Copy main cron script
COPY start-cron.sh /usr/local/bin
RUN chmod +x /usr/local/bin/start-cron.sh

# Prepare backup script
COPY start-backup.sh /usr/local/bin
RUN chmod +x /usr/local/bin/start-backup.sh

CMD ["start-cron.sh"]