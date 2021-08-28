##
## Copy of official WordPress image https://hub.docker.com/_/wordpress
##
## Added phpredis extension and some improvements.
##

FROM php:7.4-fpm-alpine

## Combine all official WordPress image layers into one
# persistent dependencies
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
# install the PHP extensions we need (https://make.wordpress.org/hosting/handbook/handbook/server-environment/#php-extensions)
    set -ex; \
	\
	apk add --no-cache --virtual .build-deps \
		$PHPIZE_DEPS \
		freetype-dev \
		imagemagick-dev \
		libjpeg-turbo-dev \
		libpng-dev \
		libzip-dev \
	; \
	\
	docker-php-ext-configure gd \
		--with-freetype \
		--with-jpeg \
	; \
	docker-php-ext-install -j "$(nproc)" \
		bcmath \
		exif \
		gd \
		mysqli \
		zip \
	; \
# WARNING: imagick is likely not supported on Alpine: https://github.com/Imagick/imagick/issues/328
# https://pecl.php.net/package/imagick
	pecl install imagick-3.5.0; \
	docker-php-ext-enable imagick; \
	rm -r /tmp/pear; \
	\
	runDeps="$( \
		scanelf --needed --nobanner --format '%n#p' --recursive /usr/local/lib/php/extensions \
			| tr ',' '\n' \
			| sort -u \
			| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
	)"; \
	apk add --no-network --virtual .wordpress-phpexts-rundeps $runDeps; \
	apk del --no-network .build-deps; \
    \
## Add Redis ext
## ToDo add phpRedis version to .env $PHPREDIS_VERSION
    docker-php-source extract; \
    curl -L -o /tmp/redis.tar.gz https://github.com/phpredis/phpredis/archive/5.3.4.tar.gz; \
    tar xfz /tmp/redis.tar.gz; \
    mv phpredis-5.3.4 /usr/src/php/ext/redis; \
    docker-php-ext-install redis; \
    docker-php-source delete; \
##
# set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
    \
    set -eux; \
	docker-php-ext-enable opcache; \
	{ \
		echo 'opcache.memory_consumption=128'; \
		echo 'opcache.interned_strings_buffer=8'; \
		echo 'opcache.max_accelerated_files=4000'; \
		echo 'opcache.revalidate_freq=2'; \
		echo 'opcache.fast_shutdown=1'; \
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
    set -eux; \
    ## ToDo WordPress version to .env
	version='5.8'; \
	sha1='6476e69305ba557694424b04b9dea7352d988110'; \
	\
	curl -o wordpress.tar.gz -fL "https://wordpress.org/wordpress-$version.tar.gz"; \
	echo "$sha1 *wordpress.tar.gz" | sha1sum -c -; \
	\
# upstream tarballs include ./wordpress/ so this gives us /usr/src/wordpress
	tar -xzf wordpress.tar.gz -C /usr/src/; \
	rm wordpress.tar.gz; \
	\
# https://wordpress.org/support/article/htaccess/
## Removed .htaccess, we are using nginx
	#[ ! -e /usr/src/wordpress/.htaccess ]; \
	#{ \
	#	echo '# BEGIN WordPress'; \
	#	echo ''; \
	#	echo 'RewriteEngine On'; \
	#	echo 'RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]'; \
	#	echo 'RewriteBase /'; \
	#	echo 'RewriteRule ^index\.php$ - [L]'; \
	#	echo 'RewriteCond %{REQUEST_FILENAME} !-f'; \
	#	echo 'RewriteCond %{REQUEST_FILENAME} !-d'; \
	#	echo 'RewriteRule . /index.php [L]'; \
	#	echo ''; \
	#	echo '# END WordPress'; \
	#} > /usr/src/wordpress/.htaccess; \
	\
	chown -R www-data:www-data /usr/src/wordpress; \
# pre-create wp-content (and single-level children) for folks who want to bind-mount themes, etc so permissions are pre-created properly instead of root:root
# wp-content/cache: https://github.com/docker-library/wordpress/issues/534#issuecomment-705733507
	mkdir wp-content; \
	for dir in /usr/src/wordpress/wp-content/*/ cache; do \
		dir="$(basename "${dir%/}")"; \
		mkdir "wp-content/$dir"; \
	done; \
	chown -R www-data:www-data wp-content; \
	chmod -R 777 wp-content

## We do not need this volume
#VOLUME /var/www/html

COPY ./config/ssmtp.conf.template /etc/ssmtp/
COPY ./config/revaliases.template /etc/ssmtp/

COPY --chown=www-data:www-data ./config/wp-config-docker.php /usr/src/wordpress/
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["php-fpm"]
