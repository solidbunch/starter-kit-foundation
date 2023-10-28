#!/usr/bin/env bash
##
## Copy of official WordPress docker-entrypoint.sh https://hub.docker.com/_/wordpress
##
## Added some config improvements.
##

set -Eeuo pipefail

# Replace env variables with values in sSMTP config
envsubst < /etc/ssmtp/ssmtp.conf.template > /etc/ssmtp/ssmtp.conf
envsubst < /etc/ssmtp/revaliases.template > /etc/ssmtp/revaliases
echo "sSMTP config ready"

## exec php-fpm (added as parameter in Dockerfile CMD ["php-fpm"])
exec "$@"
