#!/bin/bash
# certbot.sh - Manage SSL certificates using Certbot
# This script creates or renews SSL certificates using Certbot in a Docker environment.
#
# Usage:
#   ./certbot.sh [-c|-r|-h]
# Options:
#   -c    : Create certificate (first run)
#   -a    : Renew existing certificate
#   -h    : Show this help message
# Run without options to check existing certificates and decide action automatically.

# Stop on any error and fail on pipe errors
set -e -o pipefail

# Load environment and colors
source ./sh/utils/colors.sh
source ./.env

# Paths to SSL files
CERT_PATH="./config/ssl/live/${APP_DOMAIN}/fullchain.pem"
KEY_PATH="./config/ssl/live/${APP_DOMAIN}/privkey.pem"

# Default action is empty
ACTION=""

# Parse CLI arguments
while getopts "cr h" opt; do
  case $opt in
    c)
      ACTION="create"
      ;;
    r)
      ACTION="renew"
      ;;
    h)
      echo "Usage: $0 [-c|-r]"
      echo "Options:"
      echo "  -c    : Create certificate (first run)"
      echo "  -r    : Renew existing certificate"
      echo "  -h    : Show this help message"
      exit 0
      ;;
    *)
      echo "Invalid option. Use -h for help"
      exit 1
      ;;
  esac
done

# Function to create certificate
create_cert() {
  echo -e "${CYAN}[Info]${RESET} Creating SSL certificate..."

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

  echo -e "${LIGHTGREEN}[Success]${RESET} SSL certificate created at ./config/ssl/live/${APP_DOMAIN}/"
}

# Function to renew certificate
renew_cert() {
  echo -e "${CYAN}[Info]${RESET} Renewing SSL certificate..."

  docker compose -f docker-compose.build.yml run --rm certbot su -c "\
      certbot renew" \
    "${DEFAULT_USER}"

  docker compose up -d --force-recreate nginx

  echo -e "${LIGHTGREEN}[Success]${RESET} SSL certificate renewed."
}

# Determine action if not specified
if [ -z "$ACTION" ]; then
  if [ -f "$CERT_PATH" ] && [ -f "$KEY_PATH" ]; then
    ACTION="renew"
  else
    ACTION="create"
  fi
fi

# Execute action
if [ "$ACTION" == "create" ]; then
  if [ -f "$CERT_PATH" ] && [ -f "$KEY_PATH" ]; then
    echo -e "${LIGHTYELLOW}[Warning]${RESET} SSL certificate files already exist at ${CERT_PATH}."
    echo -e "Use -r option to renew."
    exit 0
  else
    create_cert
  fi

elif [ "$ACTION" == "renew" ]; then
  if [ -f "$CERT_PATH" ] && [ -f "$KEY_PATH" ]; then
    renew_cert
  else
    echo -e "${LIGHTRED}[Error]${RESET} SSL certificate files not found. Run creation first."
    exit 0
  fi
fi
