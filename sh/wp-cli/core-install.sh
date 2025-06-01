#!/bin/bash

# Colors
set +e
source /shell/utils/colors.sh

# Stop when error
set -e

wp core verify-checksums

if wp core is-installed; then
  wp cache flush
  wp rewrite flush
  echo -e "${CYAN}[Info]${RESET} WordPress is already installed"; exit 0;
fi

# Get WP_HOME from wp-config.php
WP_HOME=$(wp config get WP_HOME)

if [ -z "$WP_HOME" ]; then
  echo -e "${LIGHTRED}[Error]${RESET} WP_HOME is not defined in wp-config.php"; exit 1;
fi

# Using WP_HOME, WP_ADMIN_USER, WP_ADMIN_EMAIL, WP_ADMIN_PASSWORD from .env.secret file
# Run the wp core install command and capture its output in a variable
wp core install \
  --url="$WP_HOME" \
  --title="$APP_TITLE" \
  --admin_user="$WP_ADMIN_USER" \
  --admin_password="$WP_ADMIN_PASSWORD" \
  --admin_email="$WP_ADMIN_EMAIL"

wp plugin activate --all

wp rewrite structure '/%postname%/'

echo -e "${LIGHTGREEN}[Success]${RESET} Admin username: ${LIGHTYELLOW}$WP_ADMIN_USER${RESET}"
echo -e "${LIGHTGREEN}[Success]${RESET} Admin password: ${LIGHTYELLOW}$WP_ADMIN_PASSWORD${RESET}"
echo -e "${CYAN}[Info]${RESET} You can find this credentials in 'config/environment/.env.secret' file"
echo -e "${LIGHTYELLOW}[Warning]${RESET} Store your password in safe place"
