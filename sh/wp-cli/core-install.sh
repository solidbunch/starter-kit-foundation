#!/bin/bash

# Colors
set +e
source /shell/utils/colors

# Stop when error
set -e

if wp core is-installed; then
  echo -e "${CYAN}[Info]${NOCOLOR} WordPress is already installed"; exit 0;
fi

# Get WP_HOME from wp-config.php
WP_HOME=$(wp config get WP_HOME)

if [ -z "$WP_HOME" ]; then
  echo -e "${LIGHTRED}[Error]${NOCOLOR} WP_HOME is not defined in wp-config.php"; exit 1;
fi

WP_ADMIN_PASSWORD=$(tr -dc 'A-Za-z0-9_' </dev/urandom | head -c 25)

# Use WP_HOME, WP_ADMIN_USER, WP_ADMIN_EMAIL from .env
# Run the wp core install command and capture its output in a variable
wp core install \
  --url="$WP_HOME" \
  --title="$APP_NAME" \
  --admin_user="$WP_ADMIN_USER" \
  --admin_password="$WP_ADMIN_PASSWORD" \
  --admin_email="$WP_ADMIN_EMAIL"

wp rewrite structure '/%postname%/' --hard

echo -e "${LIGHTGREEN}[Success]${NOCOLOR} Admin username: ${LIGHTYELLOW}$WP_ADMIN_USER${NOCOLOR}"
echo -e "${LIGHTGREEN}[Success]${NOCOLOR} Admin password: ${LIGHTYELLOW}$WP_ADMIN_PASSWORD${NOCOLOR}"
echo -e "${LIGHTYELLOW}[Warning]${NOCOLOR} Store your password in safe place"
