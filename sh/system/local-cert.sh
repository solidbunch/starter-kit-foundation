#!/bin/bash
# local-cert.sh - Generate a locally-trusted (mkcert) HTTPS certificate for APP_DOMAIN and drop
# it where the active serving mode expects it, so local HTTPS shows a valid padlock instead of a
# self-signed/browser-warning certificate.
#
# Usage:
#   local-cert.sh [force]   # force regenerates even if a valid cert already exists
#
# Requires:
#   - ./.env.runtime (run `make env` first) with WP_ENVIRONMENT_TYPE=local
#   - `mkcert` on the host PATH (not installed by this script)
#
# Local-only by design: this target writes into the same directories `make ssl`/certbot manages
# (config/ssl/live/<APP_DOMAIN>/ for nginx mode), which on a server are symlinks into
# config/ssl/archive/. Overwriting them with a mkcert certificate would break the live
# Let's Encrypt chain until it is reissued, so the script refuses to run unless
# WP_ENVIRONMENT_TYPE is exactly `local` and refuses to write through a symlink. Real hosts must
# use `make ssl`. Exit codes: 0 success/skip, 1 runtime failure, 2 preflight refusal.
#
# Target paths, chosen from APP_MULTI_INSTANCE in ./.env.runtime:
#   APP_MULTI_INSTANCE=0 (default, nginx) -> config/ssl/live/<APP_DOMAIN>/{fullchain,privkey}.pem
#   APP_MULTI_INSTANCE=1 (Traefik)        -> kit-modules/proxy/certs/local/{fullchain,privkey}.pem
#                                             + kit-modules/proxy/config/dynamic/local-tls.yml
# In multi-instance mode, skips cleanly (exit 0) if kit-modules/proxy/ is absent, mirroring the
# `make proxy` target's own skip branch (Makefile).
#
# The certificate always covers both <APP_DOMAIN> and www.<APP_DOMAIN>: mkcert has no ACME
# validation to satisfy, and asking for both avoids a second certificate when a www host is
# used. This is intentionally independent of the apex/subdomain decision `make ssl` makes.
#
# Idempotent: if both cert files already exist, `openssl x509 -checkend 2592000 -noout` passes
# (not expiring within 30 days), and the SAN list covers every requested name, this is a no-op
# unless `force` is passed. SANs are parsed from `openssl x509 -text` rather than `-ext`, because
# macOS ships LibreSSL, where `-ext` is unsupported; degrades to an existence-only check if
# `openssl` itself is unavailable.
set -e -o pipefail

source ./sh/utils/colors.sh

FORCE="${1:-}"
case "$FORCE" in
  ""|force) ;;
  *)
    echo -e "${RED}[Error]${RESET} Unknown argument '${FORCE}'. Usage: local-cert.sh [force]" >&2
    exit 2
    ;;
esac

ENV_RUNTIME="./.env.runtime"
if [ ! -f "$ENV_RUNTIME" ]; then
  echo -e "${RED}[Error]${RESET} $ENV_RUNTIME not found. Run 'make env' first." >&2
  exit 2
fi

# Last occurrence wins, mirroring the env system's own merge semantics. Do NOT source the file.
APP_DOMAIN="$(sed -n 's/^[[:space:]]*APP_DOMAIN=\([^#[:space:]]*\).*/\1/p' "$ENV_RUNTIME" | tail -n1)"
APP_MULTI_INSTANCE="$(sed -n 's/^[[:space:]]*APP_MULTI_INSTANCE=\([^#[:space:]]*\).*/\1/p' "$ENV_RUNTIME" | tail -n1)"
WP_ENVIRONMENT_TYPE="$(sed -n 's/^[[:space:]]*WP_ENVIRONMENT_TYPE=\([^#[:space:]]*\).*/\1/p' "$ENV_RUNTIME" | tail -n1)"

if [ "$WP_ENVIRONMENT_TYPE" != "local" ]; then
  echo -e "${RED}[Error]${RESET} WP_ENVIRONMENT_TYPE is '${WP_ENVIRONMENT_TYPE}', not 'local'." >&2
  echo -e "${RED}[Error]${RESET} local-cert.sh writes into the same paths certbot manages and refuses to run outside local. Use 'make ssl' on real hosts." >&2
  exit 2
fi

if [ -z "$APP_DOMAIN" ]; then
  echo -e "${RED}[Error]${RESET} APP_DOMAIN is not set in $ENV_RUNTIME." >&2
  exit 2
fi

SAN_LIST=("$APP_DOMAIN" "www.${APP_DOMAIN}")

# Determine target paths for the active mode.
if [ "$APP_MULTI_INSTANCE" = "1" ]; then
  PROXY_DIR="./kit-modules/proxy"

  if [ ! -d "$PROXY_DIR" ]; then
    echo -e "${CYAN}[Info]${RESET} APP_MULTI_INSTANCE=1 but $PROXY_DIR is not installed. Configure a valid SolidBunch license (COMPOSER_AUTH) and run: composer update solidbunch/proxy. Skipping."
    exit 0
  fi

  CERT_DIR="${PROXY_DIR}/certs/local"
  DYNAMIC_FILE="${PROXY_DIR}/config/dynamic/local-tls.yml"
else
  CERT_DIR="./config/ssl/live/${APP_DOMAIN}"
fi

CERT_PATH="${CERT_DIR}/fullchain.pem"
KEY_PATH="${CERT_DIR}/privkey.pem"

# Never write through a symlink: on a real host these paths are certbot's
# live/<domain>/*.pem -> ../../archive/<domain>/*.pem links, and mkcert would truncate the
# archived certificate behind the link.
for target in "$CERT_PATH" "$KEY_PATH"; do
  if [ -L "$target" ]; then
    echo -e "${RED}[Error]${RESET} ${target} is a symlink (certbot-managed). Refusing to overwrite it." >&2
    echo -e "${RED}[Error]${RESET} local-cert.sh only manages standalone local files; use 'make ssl' on real hosts." >&2
    exit 2
  fi
done

# Idempotency check.
should_generate() {
  if [ "$FORCE" = "force" ]; then
    return 0
  fi

  if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
    return 0
  fi

  if ! command -v openssl >/dev/null 2>&1; then
    echo -e "${CYAN}[Info]${RESET} openssl not found — degrading to existence-only check."
    return 1
  fi

  if ! openssl x509 -checkend 2592000 -noout -in "$CERT_PATH" >/dev/null 2>&1; then
    echo -e "${CYAN}[Info]${RESET} Existing certificate is missing or expiring within 30 days — regenerating."
    return 0
  fi

  # `-text` works with both OpenSSL and macOS LibreSSL (`-ext` is OpenSSL-only). The SAN block
  # is the line after the "Subject Alternative Name" header.
  SAN_TEXT="$(openssl x509 -noout -text -in "$CERT_PATH" 2>/dev/null \
    | sed -n '/X509v3 Subject Alternative Name/{n;p;}' || true)"
  for SAN in "${SAN_LIST[@]}"; do
    if ! printf '%s\n' "$SAN_TEXT" | tr ',' '\n' | sed 's/^[[:space:]]*//' | grep -qx "DNS:${SAN}"; then
      echo -e "${CYAN}[Info]${RESET} Existing certificate does not cover ${SAN} — regenerating."
      return 0
    fi
  done

  return 1
}

if ! should_generate; then
  echo -e "${CYAN}[Info]${RESET} Valid local certificate already exists at ${CERT_DIR}. Skipping (pass 'force' to regenerate)."
else
  # Checked only when a certificate is actually about to be issued: a still-valid existing
  # certificate should skip cleanly even on a host that has since lost mkcert.
  if ! command -v mkcert >/dev/null 2>&1; then
    echo -e "${RED}[Error]${RESET} mkcert is not installed on this host." >&2
    echo "Install it first (https://github.com/FiloSottile/mkcert), e.g.:" >&2
    echo "  macOS:   brew install mkcert" >&2
    echo "  Linux:   see the mkcert README for your distro's package" >&2
    echo "Then re-run this script — it installs the local CA itself when none exists yet." >&2
    exit 2
  fi

  # mkcert -install is interactive (system trust store). Only run it when a certificate is
  # actually about to be issued and the local CA is missing.
  CAROOT_DIR="$(mkcert -CAROOT 2>/dev/null || true)"
  if [ -n "$CAROOT_DIR" ] && [ ! -f "${CAROOT_DIR}/rootCA.pem" ]; then
    echo -e "${YELLOW}[Warning]${RESET} No local mkcert root CA found — running 'mkcert -install' (may prompt for your password)."
    mkcert -install
  fi

  mkdir -p "$CERT_DIR"

  echo -e "${CYAN}[Info]${RESET} Generating locally-trusted certificate for ${SAN_LIST[*]}..."
  mkcert -cert-file "$CERT_PATH" -key-file "$KEY_PATH" "${SAN_LIST[@]}"

  chmod 600 "$KEY_PATH"
  chmod 644 "$CERT_PATH"

  if [ "$APP_MULTI_INSTANCE" = "1" ]; then
    cat > "$DYNAMIC_FILE" <<EOF
# Generated by sh/system/local-cert.sh (make local-cert) — do not edit by hand, gitignored.
tls:
  certificates:
    - certFile: /local-certs/fullchain.pem
      keyFile: /local-certs/privkey.pem
EOF
  fi

  echo -e "${LIGHTGREEN}[Success]${RESET} Local certificate ready at ${CERT_DIR}"
fi

echo ""
if [ "$APP_MULTI_INSTANCE" = "1" ]; then
  echo -e "${CYAN}[Info]${RESET} Next steps (multi-instance / Traefik mode):"
  echo "  1. make recreate local   # Traefik's file provider hot-reloads certs/local and local-tls.yml"
else
  echo -e "${CYAN}[Info]${RESET} Next steps (single-instance / nginx mode):"
  echo "  1. Set APP_PROTOCOL=https in config/environment/.env.type.local.override"
  echo "  2. make recreate local"
fi
