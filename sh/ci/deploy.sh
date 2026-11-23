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
# The remote chain records its current stage in $STAGE_FILE so that, on failure, the runner can
# say WHICH step broke (and show database diagnostics when it is a database-related one) instead
# of surfacing a bare "exit code 1" from ssh.
STAGE_FILE="$DEPLOY_PATH/tmp/deploy-stage"
REMOTE_RC=0
# shellcheck disable=SC2029  # $DEPLOY_PATH/$APP_MULTI_INSTANCE/$ENVIRONMENT_TYPE are meant to
# expand locally into the remote command string, matching today's behaviour verbatim.
ssh "$APP_DOMAIN" "
  set -e -o pipefail;
  cd $DEPLOY_PATH;
  mkdir -p tmp;
  rm -f '$STAGE_FILE';
  stage() { echo \"\$1\" > '$STAGE_FILE'; echo \"=== Deploy stage: \$1\"; };
  stage 'secret generation';
  make secret;
  stage 'proxy deploy';
  make APP_MULTI_INSTANCE='$APP_MULTI_INSTANCE' proxy deploy '$ENVIRONMENT_TYPE';
  stage 'env init';
  bash ./sh/env/init.sh '$ENVIRONMENT_TYPE';
  stage 'ssl';
  make ssl;
  stage 'containers recreate (incl. database container)';
  make recreate '$ENVIRONMENT_TYPE' || { echo '--- recreate failed, container status and last log lines:'; docker compose ps -a; docker compose logs --tail 20; exit 1; };
  stage 'monitoring';
  make monitoring off;
  make monitoring on;
  stage 'database health check';
  bash ./sh/database/check.sh;
  stage 'WordPress core install / database access (wp-cli)';
  make core-install;
  rm -f '$STAGE_FILE'" || REMOTE_RC=$?

if [ "$REMOTE_RC" -ne 0 ]; then
  FAILED_STAGE=$(ssh "$APP_DOMAIN" "cat '$STAGE_FILE' 2>/dev/null" || true)
  [ -n "$FAILED_STAGE" ] || FAILED_STAGE="unknown (ssh/connection failure before or between stages)"

  case "$FAILED_STAGE" in
    *database*)
      HINT="This stage touches the database and may be database-related. Container status and last MariaDB log lines are printed below."
      echo "--- Database diagnostics from $APP_DOMAIN:"
      # shellcheck disable=SC2029
      ssh "$APP_DOMAIN" "
        cd $DEPLOY_PATH;
        . ./.env 2>/dev/null;
        docker compose ps -a;
        docker compose logs --tail 50 \"\${MYSQL_HOST:-mariadb}\"" || true
      ;;
    *)
      HINT="See the log above for the failing command's output."
      ;;
  esac

  echo "=========================================================="
  echo "DEPLOY FAILED at stage: $FAILED_STAGE (exit code $REMOTE_RC)"
  echo "$HINT"
  echo "=========================================================="
  # GitHub Actions: annotation + job summary. Harmless no-ops on other runners.
  echo "::error title=Deploy failed: $FAILED_STAGE::$HINT (exit code $REMOTE_RC, target $APP_DOMAIN)"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      echo "### Deploy failed"
      echo "- **Stage:** $FAILED_STAGE"
      echo "- **Target:** $APP_DOMAIN ($ENVIRONMENT_TYPE)"
      echo "- **Exit code:** $REMOTE_RC"
      echo "- $HINT"
    } >> "$GITHUB_STEP_SUMMARY"
  fi
  exit "$REMOTE_RC"
fi
