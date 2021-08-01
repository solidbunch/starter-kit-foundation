#!/usr/bin/env bash
##
## Copy of official WordPress docker-entrypoint.sh https://hub.docker.com/_/wordpress
##
## Added cron run and some improvements.
##

set -Eeuo pipefail

## Removed apache check (we are using nginx only)
uid="$(id -u)"
gid="$(id -g)"
if [ "$uid" = '0' ]; then
  user='www-data'
  group='www-data'
else
  user="$uid"
  group="$gid"
fi

if [ ! -e index.php ] && [ ! -e wp-includes/version.php ]; then
  # if the directory exists and WordPress doesn't appear to be installed AND the permissions of it are root:root, let's chown it (likely a Docker-created directory)
  if [ "$uid" = '0' ] && [ "$(stat -c '%u:%g' .)" = '0:0' ]; then
    chown "$user:$group" .
  fi

  echo >&2 "WordPress not found in $PWD - copying now..."
  if [ -n "$(find -mindepth 1 -maxdepth 1 -not -name wp-content)" ]; then
    echo >&2 "WARNING: $PWD is not empty! (copying anyhow)"
  fi
  sourceTarArgs=(
    --create
    --file -
    --directory /usr/src/wordpress
    --owner "$user" --group "$group"
  )
  targetTarArgs=(
    --extract
    --file -
  )
  if [ "$uid" != '0' ]; then
    # avoid "tar: .: Cannot utime: Operation not permitted" and "tar: .: Cannot change mode to rwxr-xr-x: Operation not permitted"
    targetTarArgs+=( --no-overwrite-dir )
  fi
  # loop over "pluggable" content in the source, and if it already exists in the destination, skip it
  # https://github.com/docker-library/wordpress/issues/506 ("wp-content" persisted, "akismet" updated, WordPress container restarted/recreated, "akismet" downgraded)
  for contentPath in \
    /usr/src/wordpress/wp-content/*/*/ \
  ; do
    contentPath="${contentPath%/}"
    [ -e "$contentPath" ] || continue
    contentPath="${contentPath#/usr/src/wordpress/}" # "wp-content/plugins/akismet", etc.
    ##
    ## Remove akismet
    if [ "$contentPath" = "wp-content/plugins/akismet" ]; then
      echo "INFO: '$PWD/$contentPath' not copying"
      sourceTarArgs+=( --exclude "./$contentPath" )
    fi
    ##
    ##
    if [ -e "$PWD/$contentPath" ]; then
      echo >&2 "WARNING: '$PWD/$contentPath' exists! (not copying the WordPress version)"
      sourceTarArgs+=( --exclude "./$contentPath" )
    fi
  done
  tar "${sourceTarArgs[@]}" . | tar "${targetTarArgs[@]}"
  ## WordPress logs folder make writable
  mkdir -p /var/log/wordpress
  chown "$user:$group" /var/log/wordpress
  echo >&2 "Complete! WordPress has been successfully copied to $PWD"
fi

wpEnvs=( "${!WORDPRESS_@}" )
if [ ! -s wp-config.php ] && [ "${#wpEnvs[@]}" -gt 0 ]; then
  for wpConfigDocker in \
    wp-config-docker.php \
    /usr/src/wordpress/wp-config-docker.php \
  ; do
    if [ -s "$wpConfigDocker" ]; then
      echo >&2 "No 'wp-config.php' found in $PWD, but 'WORDPRESS_...' variables supplied; copying '$wpConfigDocker' (${wpEnvs[*]})"
      # using "awk" to replace all instances of "put your unique phrase here" with a properly unique string (for AUTH_KEY and friends to have safe defaults if they aren't specified with environment variables)
      awk '
        /put your unique phrase here/ {
          cmd = "head -c1m /dev/urandom | sha1sum | cut -d\\  -f1"
          cmd | getline str
          close(cmd)
          gsub("put your unique phrase here", str)
        }
        { print }
      ' "$wpConfigDocker" > wp-config.php
      if [ "$uid" = '0' ]; then
        # attempt to ensure that wp-config.php is owned by the run user
        # could be on a filesystem that doesn't allow chown (like some NFS setups)
        chown "$user:$group" wp-config.php || true
      fi
      break
    fi
  done
fi

## Remove wp-config-docker.php
rm -f wp-config-docker.php

# Replace env variables with values in sSMTP config
envsubst < /etc/ssmtp/ssmtp.conf.template > /etc/ssmtp/ssmtp.conf
envsubst < /etc/ssmtp/revaliases.template > /etc/ssmtp/revaliases
echo "sSMTP config ready"

## Add owner www-data to all wp-content files
## ToDo sync users id with host and sync files permissions
chown "$user:$group" -R wp-content

## Added Cron
mkdir -p /var/log/cron
chown "$user:$group" /var/log/cron
crond -b
echo "Cron started"

## exec php-fpm (added as paramener in Dockerfile CMD ["php-fpm"])
exec "$@"
