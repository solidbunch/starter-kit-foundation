#!/bin/bash
# ============================================================
# Script: act-run.sh
# Purpose: The single mandatory entry point for every `act` invocation in the local CI/CD
#          provisioning emulation harness. Never call `act` directly — this wrapper is what makes
#          the crash-safety net (contract 7, sh/local-ci/harness-up.sh / harness-down.sh) survive
#          the real three-process sequence `harness-up.sh` -> act -> `harness-down.sh`, since a
#          `trap ... EXIT` inside harness-up.sh protects nothing once that process has exited.
# Usage:
#   bash ./sh/local-ci/act-run.sh -W <workflow-file> -j <job> [-e <inputs-json>] [-l <label>] [-- <extra act args>]
#   bash ./sh/local-ci/act-run.sh -h
# Description:
#   1. Refuses to run unless tmp/local-ci/harness-state.env (contract 7) is present and
#      LOCALCI_ACTIVE=1 — points the operator at harness-up.sh otherwise.
#   2. Runs `act workflow_dispatch -W <workflow-file> -j <job> [-e <inputs-json>] --bind
#      --container-daemon-socket /var/run/docker.sock <extra act args>`, always adding --bind and
#      --container-daemon-socket unless the caller's extra args already specify them.
#   3. Tees all act stdout/stderr to logs/local-ci/<label>.log (label defaults to a UTC timestamp).
#   4. Owns its own `trap ... EXIT` that re-reads the sentinel, re-computes kit-modules/basis's
#      current branch/HEAD sha/porcelain-status-sha256, and compares against the sentinel's
#      recorded BASIS_BRANCH/BASIS_HEAD/BASIS_PORCELAIN_SHA. A match is a no-op. A divergence
#      restores kit-modules/basis from the sentinel's LOCALCI_SNAPSHOT tar using the same
#      wipe-then-extract approach harness-down.sh uses (rm -rf then tar -xf fresh — overwrite in
#      place would leave Terraform-generated files behind), then re-verifies and loudly reports
#      what happened. This runs on normal exit, error exit, and signals (e.g. Ctrl-C / SIGINT).
#   5. Propagates act's own exit code as this script's exit code.
# ============================================================

# Stop on errors, unset vars, and fail pipelines; preserve ERR traps
set -Eeuo pipefail

# Resolve project root (this script is at: sh/local-ci/act-run.sh)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../" && pwd)"

# Colors
# shellcheck source=/dev/null
source "$PROJECT_ROOT/sh/utils/colors.sh"

BASIS_DIR="$PROJECT_ROOT/kit-modules/basis"
LOCALCI_TMP_DIR="$PROJECT_ROOT/tmp/local-ci"
SENTINEL="$LOCALCI_TMP_DIR/harness-state.env"
LOG_DIR="$PROJECT_ROOT/logs/local-ci"

# shellcheck disable=SC2329 # invoked from restore_verify(), which is itself only invoked via trap
sha256_of_stdin() {
    if command -v sha256sum > /dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    else
        shasum -a 256 | awk '{print $1}'
    fi
}

usage() {
    cat << EOF
Usage: bash ./sh/local-ci/act-run.sh -W <workflow-file> -j <job> [-e <inputs-json>] [-l <label>] [-- <extra act args>]
       bash ./sh/local-ci/act-run.sh -h

Mandatory single entry point for every 'act' invocation in the local CI/CD harness. Refuses to run
without an active harness sentinel (tmp/local-ci/harness-state.env, written by harness-up.sh).

Options:
  -W <workflow-file>  Path to the workflow YAML to run under act (repo-root relative or absolute).
                       Required.
  -j <job>            Job id inside the workflow to run. Required.
  -e <inputs-json>    Path to a workflow_dispatch inputs JSON file, passed to act as '-e'. Optional.
  -l <label>          Label used for the log file: logs/local-ci/<label>.log. Defaults to a UTC
                       timestamp (YYYYMMDDTHHMMSSZ).
  -h                  Show this help and exit 0.
  -- <extra act args> Everything after '--' is appended verbatim to the act invocation. Use this
                       to pass e.g. '-P ubuntu-24.04=catthehacker/ubuntu:act-latest'. If any extra
                       arg is '--bind' or '--container-daemon-socket'/'--container-daemon-socket=…',
                       this script's own default of the same flag is skipped instead of duplicated.

Always runs 'act workflow_dispatch' (the only trigger this harness's job-provision.yml emulation
uses) and always adds '--bind --container-daemon-socket /var/run/docker.sock' unless the caller's
extra args already override that pair (this exact combination is required).

Every act run's stdout/stderr is teed to logs/local-ci/<label>.log.

On exit — normal, error, or signal — this script restore-verifies kit-modules/basis against the
active sentinel and restores it from the sentinel's snapshot tar if it diverged.
EOF
}

# ------------------------------------------------------------------
# 0. Parse CLI
# ------------------------------------------------------------------
WORKFLOW_FILE=""
JOB_NAME=""
INPUTS_FILE=""
LABEL=""

while getopts ":W:j:e:l:h" opt; do
    case "$opt" in
        W) WORKFLOW_FILE="$OPTARG" ;;
        j) JOB_NAME="$OPTARG" ;;
        e) INPUTS_FILE="$OPTARG" ;;
        l) LABEL="$OPTARG" ;;
        h)
            usage
            exit 0
            ;;
        :)
            echo -e "${LIGHTRED}[Error]${RESET} Option -$OPTARG requires an argument." >&2
            usage
            exit 1
            ;;
        \?)
            echo -e "${LIGHTRED}[Error]${RESET} Unknown option: -$OPTARG" >&2
            usage
            exit 1
            ;;
    esac
done
shift $((OPTIND - 1))
EXTRA_ACT_ARGS=("$@")

if [ -z "$WORKFLOW_FILE" ]; then
    echo -e "${LIGHTRED}[Error]${RESET} -W <workflow-file> is required." >&2
    usage
    exit 1
fi

if [ -z "$JOB_NAME" ]; then
    echo -e "${LIGHTRED}[Error]${RESET} -j <job> is required." >&2
    usage
    exit 1
fi

if [ ! -f "$WORKFLOW_FILE" ]; then
    echo -e "${LIGHTRED}[Error]${RESET} Workflow file not found: $WORKFLOW_FILE" >&2
    exit 1
fi

if [ -n "$INPUTS_FILE" ] && [ ! -f "$INPUTS_FILE" ]; then
    echo -e "${LIGHTRED}[Error]${RESET} Inputs file not found: $INPUTS_FILE" >&2
    exit 1
fi

if [ -z "$LABEL" ]; then
    LABEL="$(date -u +%Y%m%dT%H%M%SZ)"
fi

echo -e "------------------------------"
echo -e "Local CI/CD harness — act-run"
echo -e "------------------------------"

# ------------------------------------------------------------------
# 1. Require an active sentinel (contract 7)
# ------------------------------------------------------------------
if [ ! -f "$SENTINEL" ]; then
    echo -e "${LIGHTRED}[Error]${RESET} No harness sentinel found at $SENTINEL"
    echo -e "${LIGHTRED}[Error]${RESET} Run 'bash ./sh/local-ci/harness-up.sh' first — act-run.sh refuses to run without an active harness."
    exit 1
fi

# shellcheck source=/dev/null
source "$SENTINEL"

if [ "${LOCALCI_ACTIVE:-0}" != "1" ]; then
    echo -e "${LIGHTRED}[Error]${RESET} Sentinel at $SENTINEL is present but not active (LOCALCI_ACTIVE=${LOCALCI_ACTIVE:-unset})."
    echo -e "${LIGHTRED}[Error]${RESET} Run 'bash ./sh/local-ci/harness-up.sh' first — act-run.sh refuses to run without an active harness."
    exit 1
fi

: "${LOCALCI_SNAPSHOT:?Sentinel is missing LOCALCI_SNAPSHOT — cannot restore-verify, refusing to run}"
: "${BASIS_BRANCH:?Sentinel is missing BASIS_BRANCH — cannot restore-verify, refusing to run}"
: "${BASIS_HEAD:?Sentinel is missing BASIS_HEAD — cannot restore-verify, refusing to run}"
: "${BASIS_PORCELAIN_SHA:?Sentinel is missing BASIS_PORCELAIN_SHA — cannot restore-verify, refusing to run}"

echo -e "${LIGHTGREEN}[Info]${RESET} Active harness sentinel found: $SENTINEL"
echo -e "${LIGHTGREEN}[Info]${RESET}   LOCALCI_STARTED_AT=${LOCALCI_STARTED_AT:-unknown}"
echo -e "${LIGHTGREEN}[Info]${RESET}   BASIS_BRANCH=$BASIS_BRANCH BASIS_HEAD=$BASIS_HEAD"

# ------------------------------------------------------------------
# 2. Restore-verify trap — fires on normal exit, error exit, and signals.
#    This is the mechanism that survives the fact that harness-up.sh's own EXIT trap has already
#    fired and returned by the time this script (and the act run it wraps) executes.
# ------------------------------------------------------------------
# shellcheck disable=SC2329 # invoked indirectly via `trap restore_verify EXIT` below
restore_verify() {
    local exit_code=$?

    echo -e "${LIGHTGREEN}[Info]${RESET} act-run.sh exiting (code $exit_code) — restore-verifying kit-modules/basis against the sentinel..."

    if [ ! -f "$SENTINEL" ]; then
        echo -e "${YELLOW}[Warning]${RESET} Sentinel $SENTINEL is gone (harness-down.sh already ran?) — skipping restore-verify."
        return
    fi

    local cur_branch cur_head cur_porcelain cur_porcelain_sha
    if [ -d "$BASIS_DIR" ] && git -C "$BASIS_DIR" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        cur_branch="$(git -C "$BASIS_DIR" rev-parse --abbrev-ref HEAD)"
        cur_head="$(git -C "$BASIS_DIR" rev-parse HEAD)"
        cur_porcelain="$(git -C "$BASIS_DIR" status --porcelain)"
        cur_porcelain_sha="$(printf '%s' "$cur_porcelain" | sha256_of_stdin)"
    else
        cur_branch="MISSING"
        cur_head="MISSING"
        cur_porcelain_sha="MISSING"
    fi

    if [ "$cur_branch" = "$BASIS_BRANCH" ] && [ "$cur_head" = "$BASIS_HEAD" ] && [ "$cur_porcelain_sha" = "$BASIS_PORCELAIN_SHA" ]; then
        echo -e "${LIGHTGREEN}[Success]${RESET} kit-modules/basis unchanged (branch=$cur_branch head=$cur_head) — nothing to restore."
        return
    fi

    echo -e "${LIGHTRED}[Warning]${RESET} =============================================="
    echo -e "${LIGHTRED}[Warning]${RESET} kit-modules/basis DIVERGED from the sentinel during this act run — restoring from snapshot."
    echo -e "${LIGHTRED}[Warning]${RESET}   Sentinel:  branch=$BASIS_BRANCH head=$BASIS_HEAD porcelain_sha=$BASIS_PORCELAIN_SHA"
    echo -e "${LIGHTRED}[Warning]${RESET}   Observed:  branch=$cur_branch head=$cur_head porcelain_sha=$cur_porcelain_sha"
    echo -e "${LIGHTRED}[Warning]${RESET} =============================================="

    local snapshot_tar="$PROJECT_ROOT/$LOCALCI_SNAPSHOT"
    if [ ! -f "$snapshot_tar" ]; then
        echo -e "${LIGHTRED}[Error]${RESET} Snapshot referenced by the sentinel is missing: $snapshot_tar"
        echo -e "${LIGHTRED}[Error]${RESET} Cannot restore kit-modules/basis. Manual recovery required — do NOT run harness-up.sh again blind."
        return
    fi

    # Extract into a scratch dir first, matching harness-down.sh's step 5 pattern: prove the
    # archive is readable before touching the live tree, and diff against it afterwards.
    local restore_scratch="$LOCALCI_TMP_DIR/act-run-restore-verify-$$"
    rm -rf "$restore_scratch"
    mkdir -p "$restore_scratch"

    if ! tar -xf "$snapshot_tar" -C "$restore_scratch"; then
        echo -e "${LIGHTRED}[Error]${RESET} Snapshot archive could not be extracted: $snapshot_tar"
        echo -e "${LIGHTRED}[Error]${RESET} kit-modules/basis was NOT restored. Manual recovery required."
        rm -rf "$restore_scratch"
        return
    fi

    if [ ! -e "$restore_scratch/kit-modules/basis" ]; then
        echo -e "${LIGHTRED}[Error]${RESET} Snapshot $snapshot_tar does not contain kit-modules/basis — nothing to restore it from."
        rm -rf "$restore_scratch"
        return
    fi

    # Same wipe-then-extract approach harness-down.sh uses: a real terraform init/apply run
    # populates .terraform/, .terraform.lock.hcl, terraform.tfstate etc that the snapshot never
    # had — extracting on top would only add/overwrite, never delete, leaving those behind.
    echo -e "${LIGHTGREEN}[Info]${RESET} Wiping kit-modules/basis and re-extracting from snapshot: $snapshot_tar"
    rm -rf "$BASIS_DIR"

    if ! tar -xf "$snapshot_tar" -C "$PROJECT_ROOT" "kit-modules/basis"; then
        echo -e "${LIGHTRED}[Error]${RESET} Restore extraction failed: $snapshot_tar"
        echo -e "${LIGHTRED}[Error]${RESET} kit-modules/basis may be partially restored — inspect before retrying."
        rm -rf "$restore_scratch"
        return
    fi

    local restore_ok=true
    if ! diff -r "$restore_scratch/kit-modules/basis" "$BASIS_DIR" > /dev/null 2>&1; then
        echo -e "${LIGHTRED}[Error]${RESET} Restore verification MISMATCH for kit-modules/basis:"
        diff -r "$restore_scratch/kit-modules/basis" "$BASIS_DIR" || true
        restore_ok=false
    fi
    rm -rf "$restore_scratch"

    if [ "$restore_ok" != "true" ]; then
        echo -e "${LIGHTRED}[Error]${RESET} kit-modules/basis restore could NOT be verified byte-identical. Snapshot left in place: $snapshot_tar"
        echo -e "${LIGHTRED}[Error]${RESET} Do not trust the current kit-modules/basis tree — inspect manually."
        return
    fi

    local new_branch new_head
    new_branch="$(git -C "$BASIS_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "MISSING")"
    new_head="$(git -C "$BASIS_DIR" rev-parse HEAD 2>/dev/null || echo "MISSING")"

    if [ "$new_branch" = "$BASIS_BRANCH" ] && [ "$new_head" = "$BASIS_HEAD" ]; then
        echo -e "${LIGHTGREEN}[Success]${RESET} kit-modules/basis RESTORED and re-verified: branch=$new_branch head=$new_head (byte-identical to snapshot)."
    else
        echo -e "${LIGHTRED}[Error]${RESET} kit-modules/basis was restored from the snapshot but branch/HEAD still do not match the sentinel."
        echo -e "${LIGHTRED}[Error]${RESET}   Expected: branch=$BASIS_BRANCH head=$BASIS_HEAD"
        echo -e "${LIGHTRED}[Error]${RESET}   Observed: branch=$new_branch head=$new_head"
    fi
}

trap restore_verify EXIT

# ------------------------------------------------------------------
# 3. Build the act invocation
# ------------------------------------------------------------------
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$LABEL.log"

ADD_BIND=true
ADD_SOCKET=true
for extra_arg in "${EXTRA_ACT_ARGS[@]+"${EXTRA_ACT_ARGS[@]}"}"; do
    case "$extra_arg" in
        --bind)
            ADD_BIND=false
            ;;
        --container-daemon-socket | --container-daemon-socket=*)
            ADD_SOCKET=false
            ;;
    esac
done

ACT_ARGS=(workflow_dispatch -W "$WORKFLOW_FILE" -j "$JOB_NAME")

if [ -n "$INPUTS_FILE" ]; then
    ACT_ARGS+=(-e "$INPUTS_FILE")
fi

if [ "$ADD_BIND" = "true" ]; then
    ACT_ARGS+=(--bind)
fi
if [ "$ADD_SOCKET" = "true" ]; then
    ACT_ARGS+=(--container-daemon-socket /var/run/docker.sock)
fi

if [ "${#EXTRA_ACT_ARGS[@]}" -gt 0 ]; then
    ACT_ARGS+=("${EXTRA_ACT_ARGS[@]}")
fi

echo -e "${LIGHTGREEN}[Info]${RESET} Running: act ${ACT_ARGS[*]}"
echo -e "${LIGHTGREEN}[Info]${RESET} Log: $LOG_FILE"

# ------------------------------------------------------------------
# 4. Run act, tee output, propagate its exit code
# ------------------------------------------------------------------
ACT_EXIT=0
(cd "$PROJECT_ROOT" && act "${ACT_ARGS[@]}") 2>&1 | tee "$LOG_FILE" || ACT_EXIT=$?

if [ "$ACT_EXIT" -eq 0 ]; then
    echo -e "${LIGHTGREEN}[Success]${RESET} act run finished (exit 0)."
else
    echo -e "${LIGHTRED}[Error]${RESET} act run finished with exit code $ACT_EXIT."
fi

exit "$ACT_EXIT"
