#!/usr/bin/env bash

set -Eeuo pipefail

# Current file
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

# Replace env variables with values in sSMTP config using gettext app
replace_env_vars "/etc/ssmtp/templates" "/etc/ssmtp"
