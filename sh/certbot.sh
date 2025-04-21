#!/bin/bash

# Stop when error
set -e

# Colors
source ./sh/utils/colors

source ./.env

# Paths to SSL files
CERT_PATH="./config/ssl/live/${APP_DOMAIN}/fullchain.pem"
KEY_PATH="./config/ssl/live/${APP_DOMAIN}/privkey.pem"

# Check if the SSL files exist
if [ -f "$CERT_PATH" ] && [ -f "$KEY_PATH" ]; then
  echo -e "${CYAN}[Info]${NOCOLOR} SSL certificate files already exist. Skipping Certbot run."
else
  echo -e "${LIGHTYELLOW}[Warning]${NOCOLOR} SSL certificate files not found. Running Certbot..."

  # Check if APP_DOMAIN is a subdomain
  if [[ "$APP_DOMAIN" == *.*.* ]]; then
    DOMAIN_ARGS="-d ${APP_DOMAIN}"
  else
    DOMAIN_ARGS="-d ${APP_DOMAIN},www.${APP_DOMAIN}"
  fi

  docker compose stop nginx
  docker compose -f docker-compose.build.yml run --rm -p 80:80 certbot su -c "\
      certbot certonly --standalone --agree-tos --no-eff-email --email admin@${APP_DOMAIN} ${DOMAIN_ARGS}" \
    "${DEFAULT_USER}"
  docker compose up -d --force-recreate nginx
  echo -e "${LIGHTGREEN}[Success]${NOCOLOR} SSL certificate ready in ./config/ssl/live/${APP_DOMAIN}/"
fi
