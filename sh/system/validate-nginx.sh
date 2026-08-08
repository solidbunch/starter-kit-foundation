#!/bin/bash
# validate-nginx.sh - Validate this project's nginx config syntax (`nginx -t`) in a throwaway
# container, without starting the app stack (no MariaDB, no PHP-FPM). Fast pre-deploy check for
# config/nginx/*.template changes.
#
# Usage:
#   validate-nginx.sh
#
# Requires:
#   - Docker daemon running
#   - ./.env.runtime (run `make env` first) — supplies the same variables the nginx templates
#     reference in the running stack (APP_BA, APP_DOMAIN, APP_PROTOCOL, APP_NGINX_*, ...) plus
#     APP_NGINX_IMAGE
#
# What it does:
#   Runs `docker run --rm ... "$APP_NGINX_IMAGE" nginx -t`. The base nginx image's own
#   /docker-entrypoint.sh runs /docker-entrypoint.d/* (including this project's own
#   15-setup-basic-auth.sh and the stock 20-envsubst-on-templates.sh) before `exec`-ing `nginx -t`,
#   so this exercises the real, env-substituted config — no custom envsubst logic needed here.
#
# --add-host php:127.0.0.1 (REQUIRED, do not remove):
#   config/nginx/config/partials/php.conf.template resolves `fastcgi_pass php:9000;` as a literal
#   (non-variable) upstream hostname, and nginx resolves upstream hostnames at config-parse time —
#   `nginx -t` fails with "host not found in upstream" without this, even though the config itself
#   is syntactically valid. The mapping target is irrelevant (nothing ever connects to it), it only
#   has to resolve. `docker compose run` cannot be used instead because it has no --add-host flag
#   and the compose nginx service defines no extra_hosts.
#
# Deliberately NOT mounted (deviation from docker-compose.yml):
#   - ./logs/nginx: mounting it would let a root-owned throwaway container create host log files
#     as a side effect of a read-only check. All environments set APP_NGINX_ERROR_LOG=/dev/stderr,
#     so nothing is written to /var/log/nginx by this check anyway.
#   - ./web/wp-core, ./web/wp-content: `nginx -t` does not stat `root /srv/web;` at config-test
#     time, verified empirically — the web roots are not needed to pass.
#
# Exit codes:
#   0 - config is valid
#   1 - nginx config syntax error (propagated from `nginx -t`)
#   2 - preflight failure (missing .env.runtime, docker daemon unreachable, APP_NGINX_IMAGE unset)
set -e -o pipefail

source ./sh/utils/colors.sh

ENV_RUNTIME="./.env.runtime"
if [ ! -f "$ENV_RUNTIME" ]; then
  echo -e "${RED}[Error]${RESET} $ENV_RUNTIME not found. Run 'make env' first." >&2
  exit 2
fi

if ! docker info >/dev/null 2>&1; then
  echo -e "${RED}[Error]${RESET} Docker daemon is not reachable. Start Docker and try again." >&2
  exit 2
fi

APP_NGINX_IMAGE="$(sed -n 's/^[[:space:]]*APP_NGINX_IMAGE=\([^#[:space:]]*\).*/\1/p' "$ENV_RUNTIME" | tail -n1)"

if [ -z "$APP_NGINX_IMAGE" ]; then
  echo -e "${RED}[Error]${RESET} APP_NGINX_IMAGE is not set in $ENV_RUNTIME." >&2
  exit 2
fi

if ! docker image inspect "$APP_NGINX_IMAGE" >/dev/null 2>&1; then
  echo -e "${CYAN}[Info]${RESET} $APP_NGINX_IMAGE is not present locally — docker run will pull it. For an offline fallback, run: make docker build nginx"
fi

# Last occurrence wins, mirroring the env system's own merge semantics. Do NOT source ./.env.
APP_BA_USER="$(sed -n 's/^[[:space:]]*APP_BA_USER=\([^#[:space:]]*\).*/\1/p' ./.env | tail -n1)"
APP_BA_PASS="$(sed -n 's/^[[:space:]]*APP_BA_PASS=\([^#[:space:]]*\).*/\1/p' ./.env | tail -n1)"

APP_PROTOCOL="$(sed -n 's/^[[:space:]]*APP_PROTOCOL=\([^#[:space:]]*\).*/\1/p' "$ENV_RUNTIME" | tail -n1)"
APP_DOMAIN="$(sed -n 's/^[[:space:]]*APP_DOMAIN=\([^#[:space:]]*\).*/\1/p' "$ENV_RUNTIME" | tail -n1)"
APP_BA="$(sed -n 's/^[[:space:]]*APP_BA=\([^#[:space:]]*\).*/\1/p' "$ENV_RUNTIME" | tail -n1)"

echo -e "${CYAN}[Info]${RESET} Validating nginx config for APP_PROTOCOL=${APP_PROTOCOL} APP_DOMAIN=${APP_DOMAIN} APP_BA=${APP_BA}"

DOCKER_ARGS=(
  run --rm
  --add-host php:127.0.0.1
  --env-file "$ENV_RUNTIME"
)

if [ -n "$APP_BA_USER" ]; then
  DOCKER_ARGS+=(-e "APP_BA_USER=${APP_BA_USER}")
fi

if [ -n "$APP_BA_PASS" ]; then
  DOCKER_ARGS+=(-e "APP_BA_PASS=${APP_BA_PASS}")
fi

DOCKER_ARGS+=(
  -v "$PWD/config/nginx:/etc/nginx/templates:ro"
  -v "$PWD/config/ssl:/etc/nginx/ssl:ro"
  "$APP_NGINX_IMAGE" nginx -t
)

if ! OUTPUT="$(docker "${DOCKER_ARGS[@]}" 2>&1)"; then
  echo "$OUTPUT"
  echo -e "${RED}[Error]${RESET} nginx config syntax check failed." >&2
  exit 1
fi

echo "$OUTPUT"
echo -e "${LIGHTGREEN}[Success]${RESET} nginx config syntax is valid."
