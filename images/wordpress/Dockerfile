FROM wordpress:5.7.2-php7.4-fpm-alpine

# Install rsync
RUN apk update \
 && apk add --no-cache rsync \
 && rm -rf /var/cache/apk/*

COPY ./crontabs/* /etc/crontabs/

COPY wp-backup-daily.sh /usr/local/bin/

COPY start-wordpress.sh /usr/local/bin/

CMD ["start-wordpress.sh"]