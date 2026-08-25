#!/bin/sh
# Sourced, not executed — this header is here only for shellcheck/editors.
#
# Resolves the deploy target from ENVIRONMENT_TYPE (env var, required — set and exported by the
# caller) against ./config/environment/.env.type.$ENVIRONMENT_TYPE, then exports APP_DOMAIN and
# DEPLOY_PATH for the caller (sh/ci/deploy.sh).
#
# Usage: ENVIRONMENT_TYPE=dev; export ENVIRONMENT_TYPE; . ./sh/ci/resolve-deploy-target.sh

set -e

ENV_FILE="./config/environment/.env.type.${ENVIRONMENT_TYPE}"

if [ ! -f "$ENV_FILE" ]; then
  echo "Error: $ENV_FILE not found (build cache/artifact restore may have failed)"
  exit 1
fi

APP_DOMAIN=$(grep '^APP_DOMAIN=' "$ENV_FILE" | cut -d '=' -f2)

if [ -z "$APP_DOMAIN" ]; then
  echo "Error: APP_DOMAIN is not set in $ENV_FILE"
  exit 1
fi

DEPLOY_PATH="/srv/$APP_DOMAIN"

export APP_DOMAIN
export DEPLOY_PATH

echo "Deploy target: $APP_DOMAIN:$DEPLOY_PATH"
