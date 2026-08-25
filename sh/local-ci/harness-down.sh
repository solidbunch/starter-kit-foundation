#!/bin/bash
# ============================================================
# Script: harness-down.sh
# Purpose: Tear down the local CI/CD provisioning emulation harness started by harness-up.sh and
#          restore kit-modules/basis, .env, .env.runtime, config/environment/.env.secret to their
#          pre-run snapshot, byte-verified.
# Usage:
#   bash ./sh/local-ci/harness-down.sh
#   bash ./sh/local-ci/harness-down.sh --force-restore
# Description:
#   1. Stops docker-compose.localci.yml's services.
#   2. Removes the LocalStack Terraform overrides (sh/local-ci/tf-localstack-override.sh -m clean).
#   3. Removes the generated config/environment/.env.type.dev.override.
#   4. Removes the generated throwaway SSH keypair (both the repo-tree public key and the
#      tmp/local-ci/ private key).
#   5. Restores the tar snapshot recorded by harness-up.sh's sentinel over kit-modules/basis,
#      .env, .env.runtime, config/environment/.env.secret, and byte-verifies the restore with
#      `diff -r` against the snapshot's own content. The sentinel is cleared only once that
#      verification passes.
#   --force-restore: the stale-sentinel recovery path after a hard kill (SIGKILL / machine crash)
#      that escaped every trap. Non-critical teardown steps (compose down, override cleanup,
#      generated-file removal) become best-effort instead of hard failures, but the tar-restore +
#      diff-verify + sentinel-clear sequence stays exactly as strict as the normal path — a
#      mismatch is still a loud failure that leaves the snapshot and sentinel in place.
# ============================================================

# Stop on errors, unset vars, and fail pipelines; preserve ERR traps
set -Eeuo pipefail

# Resolve project root (this script is at: sh/local-ci/harness-down.sh)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../" && pwd)"

# Colors
# shellcheck source=/dev/null
source "$PROJECT_ROOT/sh/utils/colors.sh"

BASIS_DIR="$PROJECT_ROOT/kit-modules/basis"
LOCALCI_TMP_DIR="$PROJECT_ROOT/tmp/local-ci"
SENTINEL="$LOCALCI_TMP_DIR/harness-state.env"
OVERRIDE_ENV_FILE="$PROJECT_ROOT/config/environment/.env.type.dev.override"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.localci.yml"

FORCE_RESTORE=false
for arg in "$@"; do
    case "$arg" in
        --force-restore)
            FORCE_RESTORE=true
            ;;
        *)
            echo -e "${LIGHTRED}[Error]${RESET} Unknown argument: $arg"
            echo "Usage: bash ./sh/local-ci/harness-down.sh [--force-restore]"
            exit 1
            ;;
    esac
done

echo -e "------------------------------"
echo -e "Local CI/CD harness — down"
echo -e "------------------------------"

# Run a teardown step; in --force-restore mode, log and continue past a failure instead of
# aborting the whole teardown, since the whole point of --force-restore is recovering from a run
# that may already be in a partially-torn-down state.
run_step() {
    local description="$1"
    shift
    if "$@"; then
        return 0
    fi
    if [ "$FORCE_RESTORE" = "true" ]; then
        echo -e "${YELLOW}[Warning]${RESET} $description failed — continuing (--force-restore)"
        return 0
    fi
    echo -e "${LIGHTRED}[Error]${RESET} $description failed"
    exit 1
}

# ------------------------------------------------------------------
# 1. Stop docker-compose.localci.yml's services
#
# IMPORTANT: docker-compose.localci.yml deliberately shares its Compose project name with
# docker-compose.toolkit.yml/docker-compose.yml (so `localstack` is reachable from the `iac`
# service's network — see docker-compose.localci.yml's own header comment). That means a plain
# `docker compose -f docker-compose.localci.yml down --remove-orphans` treats the user's own
# main dev stack (nginx/php/mariadb/cron, started separately e.g. via `make up`) as "orphan
# containers" of this project and DESTROYS them too — verified live during harness development,
# see sh/local-ci/EVIDENCE.md. Never use `down`/`--remove-orphans` here. Stop and remove ONLY the
# services this file actually defines, by explicit service name.
# ------------------------------------------------------------------
if [ -f "$COMPOSE_FILE" ]; then
    run_step "Stopping local CI services" docker compose -f "$COMPOSE_FILE" stop localstack ansible-target
    run_step "Removing local CI service containers" docker compose -f "$COMPOSE_FILE" rm -f localstack ansible-target
else
    echo -e "${CYAN}[Info]${RESET} $COMPOSE_FILE not found, skipping compose down"
fi

# ------------------------------------------------------------------
# 2. Remove the LocalStack Terraform overrides
# ------------------------------------------------------------------
if [ -d "$BASIS_DIR" ]; then
    run_step "Cleaning LocalStack Terraform overrides" bash "$SCRIPT_DIR/tf-localstack-override.sh" -m clean
else
    echo -e "${CYAN}[Info]${RESET} kit-modules/basis not present, skipping Terraform override cleanup"
fi

# ------------------------------------------------------------------
# 3. Remove the generated .env.type.dev.override
# ------------------------------------------------------------------
if [ -f "$OVERRIDE_ENV_FILE" ]; then
    rm -f "$OVERRIDE_ENV_FILE"
    echo -e "${LIGHTGREEN}[Info]${RESET} Removed $OVERRIDE_ENV_FILE"
else
    echo -e "${CYAN}[Info]${RESET} $OVERRIDE_ENV_FILE not present, nothing to remove"
fi

# ------------------------------------------------------------------
# 4. Remove the generated throwaway SSH keypair
# ------------------------------------------------------------------
# shellcheck source=/dev/null
source "$PROJECT_ROOT/config/environment/.env.main"

if [ -n "${TF_VAR_sk_ssh_key_name:-}" ]; then
    PUBLIC_KEY_PATH="$BASIS_DIR/terraform/public_keys/${TF_VAR_sk_ssh_key_name}.pub"
    PRIVATE_KEY_PATH="$LOCALCI_TMP_DIR/${TF_VAR_sk_ssh_key_name}"

    if [ -f "$PUBLIC_KEY_PATH" ]; then
        rm -f "$PUBLIC_KEY_PATH"
        echo -e "${LIGHTGREEN}[Info]${RESET} Removed $PUBLIC_KEY_PATH"
    fi
    if [ -f "$PRIVATE_KEY_PATH" ]; then
        rm -f "$PRIVATE_KEY_PATH"
        echo -e "${LIGHTGREEN}[Info]${RESET} Removed $PRIVATE_KEY_PATH"
    fi
else
    echo -e "${YELLOW}[Warning]${RESET} TF_VAR_sk_ssh_key_name is not set — cannot locate the generated keypair to remove it"
fi

# ------------------------------------------------------------------
# 5. Restore the snapshot and byte-verify, then clear the sentinel
# ------------------------------------------------------------------
if [ ! -f "$SENTINEL" ]; then
    echo -e "${CYAN}[Info]${RESET} No active sentinel at $SENTINEL — nothing to restore."
    echo -e "${LIGHTGREEN}[Success]${RESET} Local CI/CD harness teardown complete (no snapshot restore needed)."
    exit 0
fi

# shellcheck source=/dev/null
source "$SENTINEL"

if [ -z "${LOCALCI_SNAPSHOT:-}" ]; then
    echo -e "${LIGHTRED}[Error]${RESET} Sentinel $SENTINEL has no LOCALCI_SNAPSHOT recorded. Refusing to restore blind."
    exit 1
fi

SNAPSHOT_TAR="$PROJECT_ROOT/$LOCALCI_SNAPSHOT"

if [ ! -f "$SNAPSHOT_TAR" ]; then
    echo -e "${LIGHTRED}[Error]${RESET} Snapshot referenced by the sentinel is missing: $SNAPSHOT_TAR"
    echo -e "${LIGHTRED}[Error]${RESET} Refusing to clear the sentinel — nothing was restored."
    exit 1
fi

echo -e "${LIGHTGREEN}[Info]${RESET} Restoring snapshot: $SNAPSHOT_TAR"

# Extract into a scratch dir first so we can byte-diff against the live tree before touching it,
# and so a corrupt archive is caught before anything is overwritten in place.
RESTORE_SCRATCH="$LOCALCI_TMP_DIR/restore-verify-$$"
rm -rf "$RESTORE_SCRATCH"
mkdir -p "$RESTORE_SCRATCH"

if ! tar -xf "$SNAPSHOT_TAR" -C "$RESTORE_SCRATCH"; then
    echo -e "${LIGHTRED}[Error]${RESET} Snapshot archive could not be extracted: $SNAPSHOT_TAR"
    echo -e "${LIGHTRED}[Error]${RESET} Refusing to clear the sentinel — nothing was restored."
    rm -rf "$RESTORE_SCRATCH"
    exit 1
fi

# kit-modules/basis is a directory tree that a real `terraform init`/`apply` run populates with
# extra files not present in the pre-run snapshot (.terraform/, .terraform.lock.hcl, and, for the
# local-state "state" layer, terraform.tfstate). Extracting the snapshot tar on top of the live
# tree only overwrites/adds files — it never deletes ones that don't exist in the archive — so
# those Terraform-generated files would survive the restore and the diff -r verify below would
# then correctly (but unhelpfully) refuse to clear the sentinel forever. Wipe the directory first
# so extraction reconstructs it byte-identical to the snapshot. This is safe here because the
# scratch-dir extraction above already proved the archive is readable before we touch the live
# tree.
# (.env, .env.runtime, config/environment/.env.secret are plain files, not directories: tar
# extraction fully truncates-and-rewrites a single regular file's content, so there is no
# equivalent "leftover sibling" case for them — no wipe needed for those three.)
if [ -e "$BASIS_DIR" ]; then
    rm -rf "$BASIS_DIR"
fi

# Extract the snapshot fresh into the live tree: kit-modules/basis is rebuilt from nothing, and
# the three env files are overwritten in place.
if ! tar -xf "$SNAPSHOT_TAR" -C "$PROJECT_ROOT"; then
    echo -e "${LIGHTRED}[Error]${RESET} Snapshot restore (extraction into the live tree) failed: $SNAPSHOT_TAR"
    echo -e "${LIGHTRED}[Error]${RESET} Refusing to clear the sentinel. Tree may be partially restored — inspect before retrying."
    rm -rf "$RESTORE_SCRATCH"
    exit 1
fi

# Byte-level verify: each of the four possible snapshot targets that was actually archived (see
# harness-up.sh step 3 — not all of them are guaranteed to exist on every run) must now diff clean
# against the live tree at the same relative path.
SNAPSHOT_CANDIDATE_TARGETS=("kit-modules/basis" ".env" ".env.runtime" "config/environment/.env.secret")
RESTORE_OK=true
for rel_path in "${SNAPSHOT_CANDIDATE_TARGETS[@]}"; do
    if [ -e "$RESTORE_SCRATCH/$rel_path" ]; then
        if ! diff -r "$RESTORE_SCRATCH/$rel_path" "$PROJECT_ROOT/$rel_path" > /dev/null 2>&1; then
            echo -e "${LIGHTRED}[Error]${RESET} Restore verification MISMATCH at: $rel_path"
            diff -r "$RESTORE_SCRATCH/$rel_path" "$PROJECT_ROOT/$rel_path" || true
            RESTORE_OK=false
        fi
    fi
done

rm -rf "$RESTORE_SCRATCH"

if [ "$RESTORE_OK" != "true" ]; then
    echo -e "${LIGHTRED}[Error]${RESET} Restore verification failed. Snapshot and sentinel left in place."
    echo -e "${LIGHTRED}[Error]${RESET} Snapshot: $SNAPSHOT_TAR"
    echo -e "${LIGHTRED}[Error]${RESET} Sentinel: $SENTINEL"
    exit 1
fi

echo -e "${LIGHTGREEN}[Success]${RESET} Restore verified byte-identical against the snapshot (diff -r clean)."

rm -f "$SENTINEL"
echo -e "${LIGHTGREEN}[Success]${RESET} Sentinel cleared: $SENTINEL"
echo -e "${LIGHTGREEN}[Info]${RESET} Snapshot left on disk for reference: $SNAPSHOT_TAR"

echo -e "${LIGHTGREEN}[Success]${RESET} Local CI/CD harness teardown complete."
