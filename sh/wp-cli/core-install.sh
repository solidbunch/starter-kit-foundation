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

echo -e "------------------------------"
echo -e "Running wp core install"
echo -e "------------------------------"

if [ -z "$WP_ADMIN_USER" ]; then
  echo -e "${LIGHTRED}[Error]${RESET} WP_ADMIN_USER is not defined"; exit 1;
fi

if [ -z "$WP_ADMIN_PASSWORD" ]; then
  echo -e "${LIGHTRED}[Error]${RESET} WP_ADMIN_PASSWORD is not defined"; exit 1;
fi

if [ -z "$WP_ADMIN_EMAIL" ]; then
  echo -e "${LIGHTRED}[Error]${RESET} WP_ADMIN_EMAIL is not defined"; exit 1;
fi

wp core install \
  --url="$WP_HOME" \
  --title="$APP_TITLE" \
  --admin_user="$WP_ADMIN_USER" \
  --admin_password="$WP_ADMIN_PASSWORD" \
  --admin_email="$WP_ADMIN_EMAIL"

echo -e "${LIGHTGREEN}[Success]${RESET} wp core installed, admin user added"
echo -e "${LIGHTGREEN}[Success]${RESET} Admin username: ${LIGHTYELLOW}$WP_ADMIN_USER${RESET}"
echo -e "${LIGHTGREEN}[Success]${RESET} Admin password: ${LIGHTYELLOW}$WP_ADMIN_PASSWORD${RESET}"
echo -e "${CYAN}[Info]${RESET} You can find this credentials in 'config/environment/.env.secret' file"
echo -e "${LIGHTYELLOW}[Warning]${RESET} Store your password in safe place"

echo -e "------------------------------"
echo -e "Running wp plugin activate"
echo -e "------------------------------"

wp plugin activate --all

echo -e "------------------------------"
echo -e "Running wp rewrite structure"
echo -e "------------------------------"

wp rewrite structure '/%postname%/'
