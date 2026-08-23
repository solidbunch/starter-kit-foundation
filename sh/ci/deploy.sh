#!/bin/sh
# Runner-side deploy: resolves the deploy target, rsyncs the workspace to the target server, then
# runs the remote `make` chain over SSH.
#
# Inputs:
#   $1 - environment type (required)
#   APP_MULTI_INSTANCE (env var, optional, default empty) - pass-through value for the remote
#     `make proxy deploy` invocation
#
# Preconditions owned by the caller: `ssh` and `rsync` on PATH, `~/.ssh/id_rsa` + `~/.ssh/config`
# already written (by sh/ci/setup-ssh.sh).
#
# Usage: sh ./sh/ci/deploy.sh <environment-type>

set -e

if [ -z "$1" ]; then
  echo "Error: environment type argument is required"
  exit 1
fi

ENVIRONMENT_TYPE="$1"
export ENVIRONMENT_TYPE

# shellcheck source=sh/ci/resolve-deploy-target.sh
# shellcheck disable=SC1091  # only resolves with -x, which shellcheck -s sh alone doesn't pass;
# the target file exists at runtime (repo root CWD) and is proven by sh -n / execution, not by
# this static check
. ./sh/ci/resolve-deploy-target.sh

echo "Deploying to $DEPLOY_PATH"
ssh "$APP_DOMAIN" mkdir -p "$DEPLOY_PATH"
rsync -og \
  --chmod=Dug=rwx,Fug=rw \
  --checksum \
  --recursive \
  --verbose \
  --compress \
  --links \
  --delete-after \
  --exclude ".git*" \
  --exclude "*/node_modules/" \
  --exclude "backups/" \
  --exclude "tmp/" \
  --exclude "**/db-*/" \
  --exclude="**/tail-db/" \
  --exclude "logs/" \
  --exclude ".env" \
  --exclude ".env.*override" \
  --exclude ".env.*runtime" \
  --exclude ".env.*secret" \
  --exclude "config/ssl/" \
  --exclude "web/wp-content/languages" \
  --exclude "web/wp-content/uploads" \
  --include "web/wp-content/cache" \
  ./ "$APP_DOMAIN:$DEPLOY_PATH"
# shellcheck disable=SC2029  # $DEPLOY_PATH/$APP_MULTI_INSTANCE/$ENVIRONMENT_TYPE are meant to
# expand locally into the remote command string, matching today's behaviour verbatim.
ssh "$APP_DOMAIN" "
  set -e -o pipefail;
  cd $DEPLOY_PATH;
  make secret;
  make APP_MULTI_INSTANCE='$APP_MULTI_INSTANCE' proxy deploy '$ENVIRONMENT_TYPE';
  bash ./sh/env/init.sh '$ENVIRONMENT_TYPE';
  make ssl;
  make recreate '$ENVIRONMENT_TYPE';
  make monitoring off;
  make monitoring on;
  bash ./sh/database/check.sh;
  make core-install"
