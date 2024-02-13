#!/usr/bin/env bash
##
## Copy of official WordPress docker-entrypoint.sh https://hub.docker.com/_/wordpress
##
## Added some config improvements.
##

set -Eeuo pipefail

# Function to replace env variables in a file if the file exists
replace_env_vars() {
    local template_file=$1
    local output_file=$2

    if [ -f "$template_file" ]; then
        envsubst < "$template_file" > "$output_file"
        echo "sSMTP processed $template_file"
    else
        echo "Warning: File $template_file does not exist. Skipping."
    fi
}

# Recreate www-data user
# Fix www-data UID from 82 to ${CURRENT_UID} (Permission denied error)
# Deleting default user (with group)
deluser www-data
# 82 is the standard uid/gid for "www-data" in Alpine
# https://git.alpinelinux.org/aports/tree/main/apache2/apache2.pre-install?h=3.14-stable
# https://git.alpinelinux.org/aports/tree/main/lighttpd/lighttpd.pre-install?h=3.14-stable
# https://git.alpinelinux.org/aports/tree/main/nginx/nginx.pre-install?h=3.14-stable

addgroup -g "${CURRENT_GID}" "${DEFAULT_USER}"
adduser -u "${CURRENT_UID}" -D -G "${DEFAULT_USER}" "${DEFAULT_USER}"
chown "${DEFAULT_USER}":"${DEFAULT_USER}" /var/log/wordpress

echo "${DEFAULT_USER} user UID=${CURRENT_UID} updated"

# Replace env variables with values in sSMTP config using gettext app
replace_env_vars "/etc/ssmtp/templates/ssmtp.conf.template" "/etc/ssmtp/ssmtp.conf"
replace_env_vars "/etc/ssmtp/templates/revaliases.template" "/etc/ssmtp/revaliases"

## exec php-fpm (added as parameter in Dockerfile CMD ["php-fpm"])
exec "$@"
