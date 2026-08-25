#!/bin/bash
# ============================================================
# Script: harness-up.sh
# Purpose: Bring up the local CI/CD provisioning emulation harness (LocalStack + LocalStack
#          Terraform overrides) so job-provision.yml's Terraform steps can run for real against
#          LocalStack instead of real AWS, without ever touching a tracked file in
#          kit-modules/basis or leaking real .env/.env.secret content.
# Usage:
#   bash ./sh/local-ci/harness-up.sh
#   LOCALCI_BASIS_ALLOWED_BRANCH=my-branch bash ./sh/local-ci/harness-up.sh
# Description:
#   1. Refuses if a previous run's sentinel is still active (crash/interrupted run) — points at
#      harness-down.sh / harness-down.sh --force-restore.
#   2. Applies the guard table for kit-modules/basis's state (see .claude/plans/
#      architect-plan-provisioning-epic.md, "Harness guard rails"): dirty/ahead is allowed only on
#      BASIS_ALLOWED_BRANCH, allowed anywhere else only when clean and not ahead of upstream,
#      refused otherwise. An unverifiable snapshot is refused unconditionally, no override.
#   3. Snapshots kit-modules/basis, .env, .env.runtime, config/environment/.env.secret into
#      tmp/local-ci/ (tar, never cp — see sh/local-ci/EVIDENCE.md).
#   4. Writes tmp/local-ci/harness-state.env (the crash-safety sentinel).
#   5. Generates a throwaway SSH keypair for the harness (public key into kit-modules/basis's own
#      git-ignored terraform/public_keys/, private key only ever under tmp/local-ci/).
#   6. Writes config/environment/.env.type.dev.override (LocalStack endpoint env vars, including
#      LOCALCI_LOCALSTACK_ENDPOINT — read by terraform/root.hcl to point every Terragrunt-managed
#      layer's generated backend/provider at LocalStack).
#   7. Writes the `state` layer's LocalStack Terraform override (the one layer outside the
#      Terragrunt graph — sh/local-ci/tf-localstack-override.sh -m write).
#   8. Brings up docker-compose.localci.yml's services.
# ============================================================

# Stop on errors, unset vars, and fail pipelines; preserve ERR traps
set -Eeuo pipefail

# Resolve project root (this script is at: sh/local-ci/harness-up.sh)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../" && pwd)"

# Colors
# shellcheck source=/dev/null
source "$PROJECT_ROOT/sh/utils/colors.sh"

# ------------------------------------------------------------------
# Contract 8: this name must equal the branch created in the basis repo. Overridable so an
# operator override is explicit and visible in shell history, never a silent code edit.
# ------------------------------------------------------------------
BASIS_ALLOWED_BRANCH="${LOCALCI_BASIS_ALLOWED_BRANCH:-fix/provisioning-epic}"

BASIS_DIR="$PROJECT_ROOT/kit-modules/basis"
LOCALCI_TMP_DIR="$PROJECT_ROOT/tmp/local-ci"
SENTINEL="$LOCALCI_TMP_DIR/harness-state.env"
OVERRIDE_ENV_FILE="$PROJECT_ROOT/config/environment/.env.type.dev.override"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.localci.yml"

# AMI override values recorded empirically against LocalStack's mock AMI catalogue — see
# sh/local-ci/EVIDENCE.md. basis's real filter (owners=["136693071363"],
# name=debian-12-arm64-*) matches nothing in LocalStack's mock catalogue.
LOCALCI_AMI_OWNERS='["099720109477"]'
LOCALCI_AMI_NAME_PATTERN='ubuntu/images/hvm-ssd/ubuntu-*'

sha256_of_stdin() {
    if command -v sha256sum > /dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    else
        shasum -a 256 | awk '{print $1}'
    fi
}

echo -e "------------------------------"
echo -e "Local CI/CD harness — up"
echo -e "------------------------------"

# ------------------------------------------------------------------
# 1. Refuse if a previous run's sentinel is still active
# ------------------------------------------------------------------
if [ -f "$SENTINEL" ]; then
    # shellcheck source=/dev/null
    source "$SENTINEL"
    if [ "${LOCALCI_ACTIVE:-0}" = "1" ]; then
        echo -e "${LIGHTRED}[Error]${RESET} A harness run is already active (sentinel: $SENTINEL)"
        echo -e "${LIGHTRED}[Error]${RESET}   LOCALCI_STARTED_AT=${LOCALCI_STARTED_AT:-unknown}"
        echo -e "${LIGHTRED}[Error]${RESET}   BASIS_BRANCH=${BASIS_BRANCH:-unknown} BASIS_HEAD=${BASIS_HEAD:-unknown}"
        echo -e "${LIGHTRED}[Error]${RESET} Run 'bash ./sh/local-ci/harness-down.sh' first to tear it down and restore."
        echo -e "${LIGHTRED}[Error]${RESET} If that run crashed (hard kill), use 'bash ./sh/local-ci/harness-down.sh --force-restore'."
        exit 1
    fi
fi

# ------------------------------------------------------------------
# 2. Guard table for kit-modules/basis's state
# ------------------------------------------------------------------
if [ ! -d "$BASIS_DIR" ]; then
    echo -e "${LIGHTRED}[Error]${RESET} kit-modules/basis is not installed at $BASIS_DIR"
    echo -e "${LIGHTRED}[Error]${RESET} The snapshot cannot be taken/verified without it. Refusing to run."
    exit 1
fi

if ! git -C "$BASIS_DIR" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo -e "${LIGHTRED}[Error]${RESET} kit-modules/basis is not a git checkout — snapshot cannot be verified. Refusing to run."
    exit 1
fi

BASIS_BRANCH="$(git -C "$BASIS_DIR" rev-parse --abbrev-ref HEAD)"
BASIS_HEAD="$(git -C "$BASIS_DIR" rev-parse HEAD)"
BASIS_PORCELAIN="$(git -C "$BASIS_DIR" status --porcelain)"

IS_DIRTY=false
if [ -n "$BASIS_PORCELAIN" ]; then
    IS_DIRTY=true
fi

BASIS_AHEAD="no-upstream"
IS_AHEAD=false
if git -C "$BASIS_DIR" rev-parse --abbrev-ref '@{u}' > /dev/null 2>&1; then
    BASIS_AHEAD="$(git -C "$BASIS_DIR" rev-list --count '@{u}..HEAD')"
    if [ "$BASIS_AHEAD" -gt 0 ]; then
        IS_AHEAD=true
    fi
fi

print_basis_banner() {
    echo -e "${YELLOW}[Warning]${RESET} =============================================="
    echo -e "${YELLOW}[Warning]${RESET} kit-modules/basis is not in a clean, at-origin state"
    echo -e "${YELLOW}[Warning]${RESET}   Branch: $BASIS_BRANCH"
    echo -e "${YELLOW}[Warning]${RESET}   HEAD:   $BASIS_HEAD"
    echo -e "${YELLOW}[Warning]${RESET}   Ahead of upstream: $BASIS_AHEAD"
    if [ "$IS_DIRTY" = "true" ]; then
        echo -e "${YELLOW}[Warning]${RESET}   Dirty paths:"
        while IFS= read -r line; do
            echo -e "${YELLOW}[Warning]${RESET}     $line"
        done <<< "$BASIS_PORCELAIN"
    fi
    echo -e "${YELLOW}[Warning]${RESET} =============================================="
}

if [ "$BASIS_BRANCH" = "$BASIS_ALLOWED_BRANCH" ]; then
    echo -e "${LIGHTGREEN}[Info]${RESET} kit-modules/basis is on the allow-listed branch ($BASIS_ALLOWED_BRANCH) — allowed regardless of dirty/ahead state."
    print_basis_banner
elif [ "$IS_DIRTY" = "true" ] || [ "$IS_AHEAD" = "true" ]; then
    echo -e "${LIGHTRED}[Error]${RESET} kit-modules/basis is on branch '$BASIS_BRANCH' (not the allow-listed '$BASIS_ALLOWED_BRANCH') and is dirty and/or ahead of its upstream."
    echo -e "${LIGHTRED}[Error]${RESET}   HEAD: $BASIS_HEAD   Ahead of upstream: $BASIS_AHEAD"
    if [ "$IS_DIRTY" = "true" ]; then
        echo -e "${LIGHTRED}[Error]${RESET}   Dirty paths:"
        while IFS= read -r line; do
            echo -e "${LIGHTRED}[Error]${RESET}     $line"
        done <<< "$BASIS_PORCELAIN"
    fi
    echo -e "${LIGHTRED}[Error]${RESET} Commit this work onto '$BASIS_ALLOWED_BRANCH', or set LOCALCI_BASIS_ALLOWED_BRANCH='$BASIS_BRANCH' deliberately if this state is intentional."
    exit 1
else
    echo -e "${LIGHTGREEN}[Info]${RESET} kit-modules/basis is on branch '$BASIS_BRANCH', clean and not ahead of upstream — allowed."
fi

# ------------------------------------------------------------------
# 3. Snapshot kit-modules/basis, .env, .env.runtime, config/environment/.env.secret
#    Uses tar, never cp — see sh/local-ci/EVIDENCE.md for why.
# ------------------------------------------------------------------
mkdir -p "$LOCALCI_TMP_DIR"

SNAPSHOT_TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
SNAPSHOT_TAR="$LOCALCI_TMP_DIR/snapshot-$SNAPSHOT_TIMESTAMP.tar"

SNAPSHOT_TARGETS=()
[ -d "$BASIS_DIR" ] && SNAPSHOT_TARGETS+=("kit-modules/basis")
[ -f "$PROJECT_ROOT/.env" ] && SNAPSHOT_TARGETS+=(".env")
[ -f "$PROJECT_ROOT/.env.runtime" ] && SNAPSHOT_TARGETS+=(".env.runtime")
[ -f "$PROJECT_ROOT/config/environment/.env.secret" ] && SNAPSHOT_TARGETS+=("config/environment/.env.secret")

if [ ${#SNAPSHOT_TARGETS[@]} -eq 0 ]; then
    echo -e "${LIGHTRED}[Error]${RESET} Nothing found to snapshot (kit-modules/basis / .env / .env.runtime / .env.secret all absent). Refusing to run."
    exit 1
fi

echo -e "${LIGHTGREEN}[Info]${RESET} Snapshotting: ${SNAPSHOT_TARGETS[*]}"
if ! tar -cf "$SNAPSHOT_TAR" -C "$PROJECT_ROOT" "${SNAPSHOT_TARGETS[@]}"; then
    echo -e "${LIGHTRED}[Error]${RESET} Snapshot creation failed. Refusing to run."
    rm -f "$SNAPSHOT_TAR"
    exit 1
fi

if ! tar -tf "$SNAPSHOT_TAR" > /dev/null 2>&1; then
    echo -e "${LIGHTRED}[Error]${RESET} Snapshot at $SNAPSHOT_TAR could not be verified (unreadable archive). Refusing to run."
    exit 1
fi

echo -e "${LIGHTGREEN}[Success]${RESET} Snapshot verified: $SNAPSHOT_TAR"

# ------------------------------------------------------------------
# 4. Write the crash-safety sentinel (contract 7)
# ------------------------------------------------------------------
BASIS_PORCELAIN_SHA="$(printf '%s' "$BASIS_PORCELAIN" | sha256_of_stdin)"
LOCALCI_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

SENTINEL_TMP="$SENTINEL.tmp"
{
    echo "LOCALCI_ACTIVE=1"
    echo "LOCALCI_STARTED_AT=$LOCALCI_STARTED_AT"
    echo "LOCALCI_SNAPSHOT=tmp/local-ci/snapshot-$SNAPSHOT_TIMESTAMP.tar"
    echo "BASIS_BRANCH=$BASIS_BRANCH"
    echo "BASIS_HEAD=$BASIS_HEAD"
    echo "BASIS_PORCELAIN_SHA=$BASIS_PORCELAIN_SHA"
    echo "BASIS_AHEAD=$BASIS_AHEAD"
} > "$SENTINEL_TMP"
mv "$SENTINEL_TMP" "$SENTINEL"

echo -e "${LIGHTGREEN}[Success]${RESET} Sentinel written: $SENTINEL"

# ------------------------------------------------------------------
# 5. Throwaway SSH keypair — public key into basis's git-ignored public_keys/, private key only
#    ever under tmp/local-ci/ (never into the repo tree).
# ------------------------------------------------------------------
# shellcheck source=/dev/null
source "$PROJECT_ROOT/config/environment/.env.main"

if [ -z "${TF_VAR_sk_ssh_key_name:-}" ]; then
    echo -e "${LIGHTRED}[Error]${RESET} TF_VAR_sk_ssh_key_name is not set in config/environment/.env.main"
    exit 1
fi

PUBLIC_KEYS_DIR="$BASIS_DIR/terraform/public_keys"
PRIVATE_KEY_PATH="$LOCALCI_TMP_DIR/${TF_VAR_sk_ssh_key_name}"
PUBLIC_KEY_PATH="$PUBLIC_KEYS_DIR/${TF_VAR_sk_ssh_key_name}.pub"

mkdir -p "$PUBLIC_KEYS_DIR"
rm -f "$PRIVATE_KEY_PATH" "$PRIVATE_KEY_PATH.pub"
ssh-keygen -t ed25519 -N "" -C "local-ci-harness" -f "$PRIVATE_KEY_PATH" -q
mv "$PRIVATE_KEY_PATH.pub" "$PUBLIC_KEY_PATH"
chmod 600 "$PRIVATE_KEY_PATH"

echo -e "${LIGHTGREEN}[Success]${RESET} Throwaway SSH keypair generated"
echo -e "${LIGHTGREEN}[Info]${RESET}   Public key:  $PUBLIC_KEY_PATH (git-ignored by basis's own /terraform/public_keys/*)"
echo -e "${LIGHTGREEN}[Info]${RESET}   Private key: $PRIVATE_KEY_PATH (tmp/local-ci/, never in the repo tree)"

# ------------------------------------------------------------------
# 6. Write config/environment/.env.type.dev.override (contract 3)
# ------------------------------------------------------------------
cat > "$OVERRIDE_ENV_FILE" << EOF
# LOCAL EMULATION HARNESS ONLY — generated by sh/local-ci/harness-up.sh — do not commit
AWS_ENDPOINT_URL=http://localstack:4566
AWS_ENDPOINT_URL_S3=http://localstack:4566
AWS_ENDPOINT_URL_STS=http://localstack:4566
AWS_ENDPOINT_URL_EC2=http://localstack:4566
AWS_EC2_METADATA_DISABLED=true
LOCALCI_LOCALSTACK_ENDPOINT=http://localstack:4566
AWS_ACCESS_KEY_ID=test
AWS_SECRET_ACCESS_KEY=test
AWS_DEFAULT_REGION=eu-west-1
TF_VAR_aws_region=eu-west-1
TF_VAR_tf_backend_bucket=localci-terraform-state
TF_VAR_aws_ami_owners=$LOCALCI_AMI_OWNERS
TF_VAR_aws_ami_name_pattern=$LOCALCI_AMI_NAME_PATTERN
APP_DOMAIN=localci.starter-kit.loc
EOF

echo -e "${LIGHTGREEN}[Success]${RESET} Wrote $OVERRIDE_ENV_FILE"
echo -e "${LIGHTGREEN}[Info]${RESET} Run 'bash ./sh/env/init.sh dev' (or 'make env dev') to fold it into .env.runtime/.env."

# ------------------------------------------------------------------
# 7. Write the LocalStack Terraform overrides (contract 4)
# ------------------------------------------------------------------
bash "$SCRIPT_DIR/tf-localstack-override.sh" -m write

# ------------------------------------------------------------------
# 8. Bring up docker-compose.localci.yml's services
# ------------------------------------------------------------------
echo -e "${LIGHTGREEN}[Info]${RESET} Starting local CI services (docker-compose.localci.yml)..."
docker compose -f "$COMPOSE_FILE" up -d

echo -e "${LIGHTGREEN}[Success]${RESET} Local CI/CD harness is up."
echo -e "${LIGHTGREEN}[Info]${RESET} Tear it down with: bash ./sh/local-ci/harness-down.sh"
