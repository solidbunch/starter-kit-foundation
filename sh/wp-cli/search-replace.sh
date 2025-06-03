#!/bin/bash

# Colors
source /shell/utils/colors.sh

# Stop when error
set -e

if [ "$1" != "" ]; then
  SEARCH_SITEURL="$1"
else
  # Get Site URL from database
  SEARCH_SITEURL=$(wp db query "SELECT option_value FROM wp_options WHERE option_name = 'siteurl' LIMIT 1" --skip-plugins --skip-themes --quiet --skip-column-names | awk '{$1=$1};1')
fi

if [ "$2" != "" ]; then
  REPLACE_SITEURL="$2"
else
  # Get Site URL from .env file
  REPLACE_SITEURL=$(wp config get WP_SITEURL)
fi

# Remove trailing slash
SEARCH_SITEURL=$(echo "$SEARCH_SITEURL" | sed 's/\/$//')
REPLACE_SITEURL=$(echo "$REPLACE_SITEURL" | sed 's/\/$//')

echo -e "${CYAN}[Info]${RESET} Database search replacing ${SEARCH_SITEURL} to ${REPLACE_SITEURL}"

# Check if SEARCH_SITEURL and REPLACE_SITEURL are not empty and not equal
if [ -n "${SEARCH_SITEURL}" ] && [ -n "${REPLACE_SITEURL}" ] && [ "${SEARCH_SITEURL}" != "${REPLACE_SITEURL}" ]; then

  wp search-replace --all-tables-with-prefix --report-changed-only=true "${SEARCH_SITEURL}" "${REPLACE_SITEURL}"
else
  echo -e "${YELLOW}[Warning]${RESET} SEARCH_SITEURL and REPLACE_SITEURL are either empty or equal. Skipping search-replace."
fi
