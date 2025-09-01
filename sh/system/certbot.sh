#!/bin/bash
# certbot.sh - Manage SSL certificates using Certbot
# This script creates or renews SSL certificates using Certbot in a Docker environment.

# Stop on any error and fail on pipe errors
set -e -o pipefail

# Load environment and colors
source ./sh/utils/colors.sh
source ./.env

# Paths to SSL files
CERT_PATH="./config/ssl/live/${APP_DOMAIN}/fullchain.pem"
KEY_PATH="./config/ssl/live/${APP_DOMAIN}/privkey.pem"
SSL_DIR="./config/ssl/live/${APP_DOMAIN}"

# Check if the SSL files exist
if [ -f "$CERT_PATH" ] && [ -f "$KEY_PATH" ]; then
  echo -e "${CYAN}[Info]${RESET} SSL certificate files already exist. Skipping Certbot run."
  exit 0
fi

echo -e "${LIGHTYELLOW}[Warning]${RESET} SSL certificate files not found. Starting initial setup..."

# 1. Create dummy self-signed certificates to allow Nginx to start
echo -e "${CYAN}[Info]${RESET} Generating dummy certificates for ${APP_DOMAIN}..."
mkdir -p "$SSL_DIR"

# Run openssl as the default user to ensure correct file permissions on the host
docker compose -f docker-compose.build.yml run --rm certbot su -c "\
    openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
      -keyout '/etc/letsencrypt/live/${APP_DOMAIN}/privkey.pem' \
      -out '/etc/letsencrypt/live/${APP_DOMAIN}/fullchain.pem' \
      -subj '/CN=${APP_DOMAIN}'" \
  "${DEFAULT_USER}"

# 2. Start Nginx with the dummy certificates
echo -e "${CYAN}[Info]${RESET} Starting Nginx with dummy certificates..."
docker compose up -d nginx

# 3. Request real certificates from Let's Encrypt
echo -e "${CYAN}[Info]${RESET} Requesting Let's Encrypt certificate for ${APP_DOMAIN}..."

# Check if APP_DOMAIN is a subdomain
if [[ "$APP_DOMAIN" == *.*.* ]]; then
  DOMAIN_ARGS="-d ${APP_DOMAIN}"
else
  DOMAIN_ARGS="-d ${APP_DOMAIN} -d www.${APP_DOMAIN}"
fi

# Delete dummy certificates before requesting real ones
docker compose -f docker-compose.build.yml run --rm certbot su -c "\
    rm -rf /etc/letsencrypt/live/${APP_DOMAIN} /etc/letsencrypt/archive/${APP_DOMAIN} /etc/letsencrypt/renewal/${APP_DOMAIN}.conf" \
  "${DEFAULT_USER}"

# Run Certbot as the default user. It will use the webroot authenticator from cli.ini
docker compose -f docker-compose.build.yml run --rm certbot su -c "\
    certbot certonly --no-eff-email --email admin@${APP_DOMAIN} ${DOMAIN_ARGS}" \
  "${DEFAULT_USER}"

# 4. Restart Nginx to load the new, real certificates
echo -e "${CYAN}[Info]${RESET} Restarting Nginx to apply the new certificate..."
docker compose restart nginx

echo -e "${LIGHTGREEN}[Success]${RESET} SSL certificate ready in ${SSL_DIR}"
