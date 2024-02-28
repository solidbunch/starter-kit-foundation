#!/usr/bin/env bash

set -Eeuo pipefail

ME=$(basename "$0")

entrypoint_log() {
    if [ -z "${PHP_ENTRYPOINT_QUIET_LOGS:-}" ]; then
        echo "$@"
    fi
}

replace_env_vars() {
  local template_dir="$1"
  local output_dir="$2"
  local suffix="${PHP_ENVSUBST_TEMPLATE_SUFFIX:-.template}"
  local filter="${PHP_ENVSUBST_FILTER:-}"

  local template defined_envs relative_path output_path subdir
  defined_envs=$(printf '${%s} ' $(awk "END { for (name in ENVIRON) { print ( name ~ /${filter}/ ) ? name : \"\" } }" < /dev/null ))
  [ -d "$template_dir" ] || return 0
  if [ ! -w "$output_dir" ]; then
    entrypoint_log "$ME: ERROR: $template_dir exists, but $output_dir is not writable"
    return 0
  fi
  find "$template_dir" -follow -type f -name "*$suffix" -print | while read -r template; do
    relative_path="${template#"$template_dir/"}"
    output_path="$output_dir/${relative_path%"$suffix"}"
    subdir=$(dirname "$relative_path")
    # create a subdirectory where the template file exists
    mkdir -p "$output_dir/$subdir"
    entrypoint_log "$ME: Running envsubst on $template to $output_path"
    envsubst "$defined_envs" < "$template" > "$output_path"
  done
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

# Move all conf.d/*.ini files to the disabled directory
# We use only manually connected ini files to control all extensions and settings
entrypoint_log "$ME: Disabling automatically added ini files"
mkdir -p "/usr/local/etc/php/conf.d/disabled"
mv "/usr/local/etc/php/conf.d/"*.ini "/usr/local/etc/php/conf.d/disabled/" 2>/dev/null || true

# Replace env variables with values in PHP config using gettext app
# And move ini files into config folder
replace_env_vars "/usr/local/etc/php/templates" "/usr/local/etc/php/conf.d"

# Replace env variables with values in sSMTP config using gettext app
replace_env_vars "/etc/ssmtp/templates" "/etc/ssmtp"


## exec php-fpm (added as parameter in Dockerfile CMD ["php-fpm"])
exec "$@"
