#!/bin/bash
# certbot.sh - Manage SSL certificates using Certbot
# This script creates or renews SSL certificates using Certbot in a Docker environment.

# Stop on any error and fail on pipe errors
set -e -o pipefail

# Load environment and colors
source ./sh/utils/colors.sh
source ./.env.runtime

if [ "${APP_MULTI_INSTANCE}" = "1" ]; then
  echo -e "${CYAN}[Info]${RESET} APP_MULTI_INSTANCE=1: skipping Certbot, TLS is handled by Traefik."
  exit 0
fi

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
docker compose -f docker-compose.toolkit.yml run --rm certbot su -c "\
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

# Detect apex vs subdomain via the Public Suffix List (psl) — no dot-count/heuristic
# fallback. Mirrors BASIS kit-modules/basis/sh/dns.sh's own PSL check (that script's
# "PSL-based apex/www expansion" section): same rule (reg_domain == FQDN => apex =>
# also update www.<fqdn>), duplicated here rather than shared because the two scripts
# live in different repos and run in different container images (Debian iac vs Alpine
# certbot) — see the dns-provider-update plan's Architecture notes §1/§2.
#
# The certbot entrypoint (dockerfiles/certbot/docker-entrypoint.sh) echoes a banner
# line ("${DEFAULT_USER} user UID=... updated") to stdout before exec-ing the command,
# so the raw capture below is filtered per-line rather than trusting the last line
# blindly on faith alone — the banner contains spaces/"=" and can never match the
# domain-shape regex, so it is naturally excluded.
DOMAIN_REGEX='^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$'

RAW_REG_DOMAIN="$(docker compose -f docker-compose.toolkit.yml run --rm certbot su -c "\
    psl -b --print-reg-domain '${APP_DOMAIN}'" \
  "${DEFAULT_USER}")"

REG_DOMAIN="$(printf '%s\n' "$RAW_REG_DOMAIN" | tr -d '\r' | grep -E "$DOMAIN_REGEX" | tail -n 1 || true)"

if [ -z "$REG_DOMAIN" ]; then
  echo -e "${LIGHTRED}[Error]${RESET} psl lookup failed or returned no usable value for '${APP_DOMAIN}'." >&2
  echo -e "${LIGHTRED}[Error]${RESET} Ensure the 'libpsl-utils' package is installed in the certbot image (dockerfiles/certbot/Dockerfile)." >&2
  exit 1
fi

if [ "$REG_DOMAIN" = "$APP_DOMAIN" ]; then
  DOMAIN_ARGS="-d ${APP_DOMAIN} -d www.${APP_DOMAIN}"
else
  DOMAIN_ARGS="-d ${APP_DOMAIN}"
fi

# Delete dummy certificates before requesting real ones
docker compose -f docker-compose.toolkit.yml run --rm certbot su -c "\
    rm -rf /etc/letsencrypt/live/${APP_DOMAIN} /etc/letsencrypt/archive/${APP_DOMAIN} /etc/letsencrypt/renewal/${APP_DOMAIN}.conf" \
  "${DEFAULT_USER}"

# Run Certbot as the default user. It will use the webroot authenticator from cli.ini
docker compose -f docker-compose.toolkit.yml run --rm certbot su -c "\
    certbot certonly --no-eff-email --email admin@${APP_DOMAIN} ${DOMAIN_ARGS}" \
  "${DEFAULT_USER}"

# 4. Restart Nginx to load the new, real certificates
echo -e "${CYAN}[Info]${RESET} Restarting Nginx to apply the new certificate..."
docker compose restart nginx

echo -e "${LIGHTGREEN}[Success]${RESET} SSL certificate ready in ${SSL_DIR}"
