#!/usr/bin/env bash
# ============================================================
# Local CI/CD provisioning-emulation harness only (sh/local-ci/*). Never used outside
# docker-compose.localci.yml's ansible-target service.
#
# Installs the harness's throwaway SSH public key(s) into admin's authorized_keys at container
# START, never baked into the image (see dockerfiles/ansible-target/Dockerfile header comment).
# The key is bind-mounted read-only from kit-modules/basis/terraform/public_keys/ (contract 5 —
# .claude/plans/architect-plan-provisioning-epic.md), which sh/local-ci/harness-up.sh generates
# fresh on every run, before `docker compose up`.
# ============================================================

# Stop on errors, unset vars, and fail pipelines; preserve ERR traps
set -Eeuo pipefail

HARNESS_PUBKEY_DIR="/harness-keys"
AUTHORIZED_KEYS="/home/admin/.ssh/authorized_keys"

: > "$AUTHORIZED_KEYS"

if [ -d "$HARNESS_PUBKEY_DIR" ]; then
    found=0
    for pub in "$HARNESS_PUBKEY_DIR"/*.pub; do
        [ -e "$pub" ] || continue
        cat "$pub" >> "$AUTHORIZED_KEYS"
        found=1
    done
    if [ "$found" = "1" ]; then
        echo "docker-entrypoint: installed $(wc -l < "$AUTHORIZED_KEYS" | tr -d ' ') harness SSH public key(s) into $AUTHORIZED_KEYS"
    else
        echo "docker-entrypoint: WARNING no *.pub file found under $HARNESS_PUBKEY_DIR — admin will have no authorized_keys (run sh/local-ci/harness-up.sh first)"
    fi
else
    echo "docker-entrypoint: WARNING $HARNESS_PUBKEY_DIR is not mounted — admin will have no authorized_keys"
fi

chmod 600 "$AUTHORIZED_KEYS"
chown admin:admin "$AUTHORIZED_KEYS"

# Exec the requested command (systemd as PID 1, per docker-compose.localci.yml's `command:`)
exec "$@"
