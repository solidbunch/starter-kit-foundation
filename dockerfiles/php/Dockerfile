FROM php:8.1-fpm-alpine3.20

ENV XDEBUG_VERSION=3.1.4
ENV IMAGICK_VERSION=3.7.0

##################################
#         Adding WP-CLI          #
##################################
# https://hub.docker.com/_/wordpress
COPY --from=wordpress:cli-2.10-php8.1 /usr/local/bin/wp /usr/local/bin/wp

##################################
#     Persistent dependencies    #
##################################
RUN set -eux; \
    apk add --no-cache \
      bash \
# Ghostscript is required for rendering PDF previews
      ghostscript \
# Alpine package for "imagemagick" contains ~120 .so files, see: https://github.com/docker-library/wordpress/pull/497
      imagemagick \
# Envsubst for operate with env variables in config files
      gettext \
# Install wp-cli dependencies
      less \
      mysql-client

##################################
#     install PHP extensions     #
##################################
# install the PHP extensions we need (https://make.wordpress.org/hosting/handbook/handbook/server-environment/#php-extensions)
RUN set -ex; \
    \
    apk add --no-cache --virtual .build-deps \
      $PHPIZE_DEPS \
      freetype-dev \
      icu-dev \
      imagemagick-dev \
      libjpeg-turbo-dev \
      libpng-dev \
      libwebp-dev \
      libzip-dev \
    ; \
    \
    docker-php-ext-configure gd \
      --with-freetype \
      --with-jpeg \
      --with-webp \
    ; \
    docker-php-ext-install -j "$(nproc)" \
      bcmath \
      exif \
      gd \
      intl \
      mysqli \
      zip \
    ; \
# Install Xdebug see https://xdebug.org/docs/install
    pecl install xdebug-${XDEBUG_VERSION}; \
#
# WARNING: imagick is likely not supported on Alpine: https://github.com/Imagick/imagick/issues/328
# https://pecl.php.net/package/imagick
    pecl install imagick-${IMAGICK_VERSION}; \
#
# some misbehaving extensions end up outputting to stdout 🙈 (https://github.com/docker-library/wordpress/issues/669#issuecomment-993945967)
    out="$(php -r 'exit(0);')"; \
    [ -z "$out" ]; \
    err="$(php -r 'exit(0);' 3>&1 1>&2 2>&3)"; \
    [ -z "$err" ]; \
    \
    extDir="$(php -r 'echo ini_get("extension_dir");')"; \
    [ -d "$extDir" ]; \
    runDeps="$( \
      scanelf --needed --nobanner --format '%n#p' --recursive "$extDir" \
        | tr ',' '\n' \
        | sort -u \
        | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
    )"; \
    apk add --no-network --virtual .wordpress-phpexts-rundeps $runDeps; \
    apk del --no-network .build-deps; \
    \
    ! { ldd "$extDir"/*.so | grep 'not found'; }; \
  # check for output like "PHP Warning:  PHP Startup: Unable to load dynamic library 'foo' (tried: ...)
    err="$(php --version 3>&1 1>&2 2>&3)"; \
    [ -z "$err" ]; \
#
# Clear /tmp
    rm -rf /tmp/*

##################################
#     WordPress logs folder      #
##################################
RUN mkdir -p /var/log/wordpress

##################################
#   Prepare and run entrypoint   #
##################################
RUN mkdir /docker-entrypoint.d

COPY docker-entrypoint.sh /
COPY ./docker-entrypoint.d/* /docker-entrypoint.d

RUN chmod +x /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.d/*.sh

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["php-fpm"]
