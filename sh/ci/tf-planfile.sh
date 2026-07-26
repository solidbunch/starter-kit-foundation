#!/bin/bash
# ============================================================
# Script: tf-planfile.sh
# Purpose: Save or apply a pinned Terraform plan file for StarterKit provisioning CI.
# Usage:
#   bash ./sh/ci/tf-planfile.sh -e <layer> -m <save|apply> -f <path-relative-to-repo-root>
# Examples:
#   bash ./sh/ci/tf-planfile.sh -e shared -m save -f tfplans/shared.tfplan
#   bash ./sh/ci/tf-planfile.sh -e shared -m apply -f tfplans/shared.tfplan
# Description:
#   Foundation-side helper that mirrors kit-modules/basis/sh/terraform.sh's container
#   invocation (same docker compose service, same five -e AWS/SSH flags, same
#   `su -c "..." "${DEFAULT_USER}"` pattern, same layer→dir mapping) but adds the
#   plan-file argument terraform.sh has no passthrough for. Does not modify terraform.sh.
#   `-e state|shared|dev|stage|prod -c init` (terraform.sh) must be run before `-m save`.
# ============================================================

# Stop on errors, unset vars, and fail pipelines; preserve ERR traps
set -Eeuo pipefail

# Resolve project root (this script is at: sh/ci/tf-planfile.sh)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../" && pwd)"

# Colors
# shellcheck source=/dev/null
source "$PROJECT_ROOT/sh/utils/colors.sh"

# Load environment variables
# shellcheck source=/dev/null
source "$PROJECT_ROOT/.env"

usage() {
  echo "Usage: bash ./sh/ci/tf-planfile.sh -e <layer> -m <save|apply> -f <path-relative-to-repo-root>"
  echo "  layer: state|shared|dev|stage|prod"
  echo "  mode:  save  -> terraform plan -out=<file>"
  echo "         apply -> terraform apply -auto-approve <file>"
  echo "  file:  repo-root-relative path, e.g. tfplans/shared.tfplan"
}

TF_LAYER=""
TF_MODE=""
PLAN_FILE=""

while getopts ":e:m:f:h" opt; do
  case $opt in
    e)
      TF_LAYER="$OPTARG"
      ;;
    m)
      TF_MODE="$OPTARG"
      ;;
    f)
      PLAN_FILE="$OPTARG"
      ;;
    h)
      usage
      exit 0
      ;;
    \?)
      echo -e "${LIGHTRED}[Error]${RESET} Invalid option: -$OPTARG"; usage; exit 1;
      ;;
    :)
      echo -e "${LIGHTRED}[Error]${RESET} Option -$OPTARG requires an argument"; usage; exit 1;
      ;;
  esac
done

# Validate required args
if [ -z "$TF_LAYER" ]; then
  echo -e "${LIGHTRED}[Error]${RESET} layer is required (use -e state|shared|dev|stage|prod)"; usage; exit 1;
fi
if [ -z "$TF_MODE" ]; then
  echo -e "${LIGHTRED}[Error]${RESET} mode is required (use -m save|apply)"; usage; exit 1;
fi
if [ -z "$PLAN_FILE" ]; then
  echo -e "${LIGHTRED}[Error]${RESET} plan file path is required (use -f <path-relative-to-repo-root>)"; usage; exit 1;
fi

case "$TF_LAYER" in
  state|shared|dev|stage|prod) ;;
  *)
    echo -e "${LIGHTRED}[Error]${RESET} Unknown layer: $TF_LAYER (expected state|shared|dev|stage|prod)"; exit 1;
    ;;
esac

case "$TF_MODE" in
  save|apply) ;;
  *)
    echo -e "${LIGHTRED}[Error]${RESET} Unknown mode: $TF_MODE (expected save|apply)"; exit 1;
    ;;
esac

# Determine target path within basis module (mirrors terraform.sh:75-79)
if [ "$TF_LAYER" = "state" ]; then
  ENV_PATH="terraform/state"
else
  ENV_PATH="terraform/envs/$TF_LAYER"
fi

# Container-absolute plan path — the `iac` service mounts ./:/srv, working_dir: /srv
CONTAINER_PLAN_FILE="/srv/$PLAN_FILE"

if [ "$TF_MODE" = "apply" ]; then
  if [ ! -f "$PROJECT_ROOT/$PLAN_FILE" ]; then
    echo -e "${LIGHTRED}[Error]${RESET} Plan file not found: $PLAN_FILE"; exit 1;
  fi
else
  # save mode: Terraform's -out does not create parent directories itself —
  # the plan file's directory must exist on the host before the container writes to it.
  mkdir -p "$PROJECT_ROOT/$(dirname "$PLAN_FILE")"
fi

echo -e "${LIGHTGREEN}[Info]${RESET} Running Terraform plan-file operation for layer: ${TF_LAYER}"
echo -e "${LIGHTGREEN}[Info]${RESET} Mode: ${TF_MODE}"
echo -e "${LIGHTGREEN}[Info]${RESET} Plan file: ${PLAN_FILE}"

if [ "$TF_MODE" = "save" ]; then
  docker compose -f "$PROJECT_ROOT/docker-compose.toolkit.yml" run --rm \
    -e AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}" \
    -e AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}" \
    -e AWS_SESSION_TOKEN="${AWS_SESSION_TOKEN:-}" \
    -e AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-}" \
    -e SSH_AUTH_SOCK="${SSH_AUTH_SOCK:-}" \
    iac su -c "
    cd \"./kit-modules/basis/$ENV_PATH\" && \
    terraform plan -out=\"$CONTAINER_PLAN_FILE\"
  " "${DEFAULT_USER}"
else
  docker compose -f "$PROJECT_ROOT/docker-compose.toolkit.yml" run --rm \
    -e AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}" \
    -e AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}" \
    -e AWS_SESSION_TOKEN="${AWS_SESSION_TOKEN:-}" \
    -e AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-}" \
    -e SSH_AUTH_SOCK="${SSH_AUTH_SOCK:-}" \
    iac su -c "
    cd \"./kit-modules/basis/$ENV_PATH\" && \
    terraform apply -auto-approve \"$CONTAINER_PLAN_FILE\"
  " "${DEFAULT_USER}"
fi

echo -e "${LIGHTGREEN}[Success]${RESET} Terraform plan-file operation completed"
