FROM wordpress:5.7.2-php7.4-fpm-alpine

RUN apk update && apk add --no-cache docker

CMD ["crond", "-f"]
