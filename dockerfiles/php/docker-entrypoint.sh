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
deluser www-data; \
addgroup -g "${CURRENT_GID}" www-data; \
adduser -u "${CURRENT_UID}" -D -G www-data www-data

echo "www-data user UID=${CURRENT_UID} updated"

# Replace env variables with values in sSMTP config using gettext app
replace_env_vars "/etc/ssmtp/templates/ssmtp.conf.template" "/etc/ssmtp/ssmtp.conf"
replace_env_vars "/etc/ssmtp/templates/revaliases.template" "/etc/ssmtp/revaliases"

## exec php-fpm (added as parameter in Dockerfile CMD ["php-fpm"])
exec "$@"
