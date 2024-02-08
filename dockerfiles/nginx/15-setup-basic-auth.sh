#!/bin/sh

# Stop when error
set -e

# Current file
ME=$( basename "$0" )

# Check is basic auth enable
if [ ! "$APP_BA" ] || [ "$APP_BA" != "enable" ]; then
  if [ ! "$APP_BA_WP_LOGIN" ] || [ "$APP_BA_WP_LOGIN" != "enable" ]; then
      echo "$ME: [Info] wp-login Basic Auth is disabled in .env file"; exit;
  fi
fi

mkdir -p /etc/nginx/auth/

# Generate htpasswd file
printf "%s:%s\n" "$APP_BA_USER" "$(openssl passwd -apr1 "$APP_BA_PASSWORD")" >> /etc/nginx/auth/.wplogin

echo "$ME: [Success] Auth file ready in /etc/nginx/auth/.wplogin"
