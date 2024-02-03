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
        echo "Processed $template_file"
    else
        echo "Warning: File $template_file does not exist. Skipping."
    fi
}

# Replace env variables with values in sSMTP config using gettext app
replace_env_vars "/etc/ssmtp/templates/ssmtp.conf.template" "/etc/ssmtp/ssmtp.conf"
replace_env_vars "/etc/ssmtp/templates/revaliases.template" "/etc/ssmtp/revaliases"

echo "sSMTP config processing complete"

## exec php-fpm (added as parameter in Dockerfile CMD ["php-fpm"])
exec "$@"
