##
## Copy of official WordPress image https://hub.docker.com/_/wordpress
##
## Added some improvements.
## Combined all image layers into one
##

FROM php:8.1-fpm-alpine3.17

##################################
# Arguments from docker-compose  #
##################################
ARG WWW_DATA_GID
ARG WWW_DATA_UID

ARG XDEBUG_ENABLE

#
##################################
#     Persistent dependencies    #
##################################
RUN set -eux; \
    apk add --no-cache \
# in theory, docker-entrypoint.sh is POSIX-compliant, but priority is a working, consistent image
      bash \
# Ghostscript is required for rendering PDF previews
      ghostscript \
# Alpine package for "imagemagick" contains ~120 .so files, see: https://github.com/docker-library/wordpress/pull/497
      imagemagick \
# Use SMTP relay service
      ssmtp \
# ToDo - better to separate this to additional container (run, work and stop)
# Need envsubst for operate with env variables in config files
      gettext \
  ; \
#
##################################
#     Recreate www-data user     #
##################################
# Fix www-data UID from 82 to ${WWW_DATA_UID} (Permission denied error)
    deluser www-data; \
    addgroup -g $WWW_DATA_GID www-data; \
    adduser -u $WWW_DATA_UID -D -S -G www-data www-data; \
  \
#
##################################
#     install PHP extensions     #
##################################
# install the PHP extensions we need (https://make.wordpress.org/hosting/handbook/handbook/server-environment/#php-extensions)
    set -ex; \
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
      mysqli \
      zip \
    ; \
# Install Xdebug if XDEBUG_ENABLE is set to 1 \
# Install Xdebug see https://xdebug.org/docs/install
    if [ "$XDEBUG_ENABLE" = "1" ]; then \
      pecl install xdebug-3.1.4; \
      docker-php-ext-enable xdebug; \
    fi; \
#
# WARNING: imagick is likely not supported on Alpine: https://github.com/Imagick/imagick/issues/328
# https://pecl.php.net/package/imagick
    pecl install imagick-3.6.0; \
    docker-php-ext-enable imagick; \
    rm -r /tmp/pear; \
    \
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
    \
#
# Clear /tmp
    rm -rf /tmp/*; \
#
##################################
#      Set PHP.ini settings      #
##################################
# see https://secure.php.net/manual/en/opcache.installation.php
    \
    set -eux; \
    docker-php-ext-enable opcache; \
    { \
      echo 'opcache.memory_consumption=128'; \
      echo 'opcache.interned_strings_buffer=8'; \
      echo 'opcache.max_accelerated_files=4000'; \
      echo 'opcache.revalidate_freq=2'; \
    } > /usr/local/etc/php/conf.d/opcache-recommended.ini; \
# https://wordpress.org/support/article/editing-wp-config-php/#configure-error-logging
    { \
  # https://www.php.net/manual/en/errorfunc.constants.php
  # https://github.com/docker-library/wordpress/issues/420#issuecomment-517839670
      echo 'error_reporting = E_ERROR | E_WARNING | E_PARSE | E_CORE_ERROR | E_CORE_WARNING | E_COMPILE_ERROR | E_COMPILE_WARNING | E_RECOVERABLE_ERROR'; \
      echo 'display_errors = Off'; \
      echo 'display_startup_errors = Off'; \
      echo 'log_errors = On'; \
      echo 'error_log = /dev/stderr'; \
      echo 'log_errors_max_len = 1024'; \
      echo 'ignore_repeated_errors = On'; \
      echo 'ignore_repeated_source = Off'; \
      echo 'html_errors = Off'; \
    } > /usr/local/etc/php/conf.d/error-logging.ini; \
##
## set PHP.ini settings for sendmail
    { \
      #echo 'sendmail_path = /usr/sbin/ssmtp -t -i'; \
      echo 'sendmail_path = /usr/sbin/sendmail -t'; \
    } > /usr/local/etc/php/conf.d/sendmail.ini; \
##
## set custom PHP.ini settings
    { \
      # Resource Limits
      echo 'max_execution_time = 30'; \
      # Memory limits works across WP_MEMORY_LIMIT and WP_MAX_MEMORY_LIMIT constants that comes from .env file
      # echo 'memory_limit = 128M'; \
      # Data Handling
      echo 'post_max_size = 8M'; \
      # File uploads
      echo 'upload_max_filesize = 6M'; \
      echo 'max_file_uploads = 20'; \
    } > /usr/local/etc/php/conf.d/custom-php.ini

##################################
#     WordPress logs folder      #
##################################
RUN mkdir -p /var/log/wordpress; \
    chown www-data:www-data /var/log/wordpress

##################################
#   Prepare and run entrypoint   #
##################################
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["php-fpm"]
