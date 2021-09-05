FROM alpine:3.14

RUN set -ex \
# Install bash
    && apk add --no-cache \
    bash \
# Install docker-cli only. We need just run `docker exec` command, we do not need 'Docker-in-Docker'
# https://jpetazzo.github.io/2015/09/03/do-not-use-docker-in-docker-for-ci/
    docker-cli \
# making logging pipe
    && mkdir -p /var/log/cron \
    && mkfifo -m 0666 /var/log/cron.log \
    && ln -s /var/log/cron.log /var/log/crond.log

COPY start-cron.sh /usr/sbin
RUN chmod +x /usr/sbin/start-cron.sh

CMD ["start-cron.sh"]
