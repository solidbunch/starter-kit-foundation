# Taking current project PHP image
ARG APP_PHP_IMAGE
FROM ${APP_PHP_IMAGE}

##################################
#    Installing PHP Composer     #
##################################
# https://hub.docker.com/_/composer
COPY --from=composer:2.8 /usr/bin/composer /usr/bin/composer

##################################
#      Composer dependencies     #
##################################
RUN set -eux ; \
  apk add --no-cache --virtual .composer-rundeps \
    bash \
    coreutils \
    git \
    make \
    openssh-client \
    patch \
    subversion \
    tini \
    unzip \
    zip \
    $([ "$(apk --print-arch)" != "x86" ] && echo mercurial) \
    $([ "$(apk --print-arch)" != "armhf" ] && echo p7zip)

##################################
#       Prepare entrypoint       #
##################################
COPY ./docker-entrypoint.d/* /docker-entrypoint.d
RUN chmod +x /docker-entrypoint.d/*.sh

CMD ["composer"]
