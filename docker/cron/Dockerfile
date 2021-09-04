FROM alpine:3.14

RUN set -ex \
# install bash
    && apk add --no-cache \
    bash \
    mc\
# making logging pipe
    && mkfifo -m 0666 /var/log/cron.log \
    && ln -s /var/log/cron.log /var/log/crond.log

COPY start-cron /usr/sbin
RUN chmod +x /usr/sbin/start-cron

CMD ["start-cron"]
