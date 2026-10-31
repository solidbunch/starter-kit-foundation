#!/bin/bash

# Stop when error
set -e

# Colors
source ./sh/utils/colors.sh

# We have no root .env yet at this stage — connect main env directly (same as sh/env/init.sh)
source ./config/environment/.env.main

echo -e "------------------------------"
echo -e "Generate .env.secret"
echo -e "------------------------------"

# Check .env template file exist
if [ ! -f ./sh/env/.env.secret.template ]; then
    echo -e "${LIGHTRED}[Error]${RESET} .env.secret.template file not found in ./sh/env/"; exit 1;
fi

SECRET_FILE="./config/environment/.env.secret"
TEMPLATE_FILE="./sh/env/.env.secret.template"

# Check .env.secret file exist
if [ ! -f "$SECRET_FILE" ]; then
    # Fresh install — no existing secrets to protect. Cross platform password generator:
    # creating Alpine container, running pass gen, removing container.
    echo -e "${CYAN}[Info]${RESET} Generating Secrets..."

    # A previous crashed run can leave the fixed container name behind; clear it first.
    docker rm -f pass-gen-container >/dev/null 2>&1 || true

    docker run --name pass-gen-container -v "./sh:/shell:ro" "$APP_PASS_GEN_IMAGE" sh /shell/env/pass_gen.sh
    docker cp pass-gen-container:/.env.secret "$SECRET_FILE"
    docker rm -f pass-gen-container > /dev/null 2>&1 || true

    echo -e "${LIGHTGREEN}[Success]${RESET} Secrets done in $SECRET_FILE"
    exit 0
fi

# .env.secret already exists — this may be a live, already-provisioned server holding real
# production credentials (DB passwords, WP admin password, COMPOSER_AUTH token, etc).
# NEVER overwrite or regenerate an existing key's value here. Only APPEND variable names that
# are present in the template but genuinely absent from this file.
echo -e "${CYAN}[Info]${RESET} .env.secret file already exist in ./config/environment/ — checking for missing keys..."

# Existing key names (uncommented KEY=... lines). '|| true' avoids tripping `set -e` when
# the file has no matching lines (grep exits 1 on no match).
existing_keys="$(grep -oE '^[A-Za-z_][A-Za-z0-9_]*=' "$SECRET_FILE" | sed 's/=$//' || true)"

missing_lines=()
warn_keys=()

while IFS= read -r line || [ -n "$line" ]; do
    # Only consider active (uncommented) KEY=value lines from the template
    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]]; then
        key="${BASH_REMATCH[1]}"
        if ! grep -qx "$key" <<< "$existing_keys"; then
            missing_lines+=("$line")
            value="${line#*=}"
            if [ -z "$value" ]; then
                warn_keys+=("$key")
            fi
        fi
    fi
done < "$TEMPLATE_FILE"

if [ "${#missing_lines[@]}" -eq 0 ]; then
    echo -e "${LIGHTGREEN}[Success]${RESET} .env.secret already has every key from the template — nothing to add."
    exit 0
fi

# Generate values for the missing keys only, reusing the same Alpine password generator
# (pass_gen.sh), but pointed at an isolated temp copy containing ONLY the missing lines —
# so it can never read or write the real .env.secret / .env.secret.template files.
#
# The temp copy holds real generated secrets, so it lives under ./tmp: gitignored and excluded
# from the deploy rsync, and a bind-mountable path on every platform (macOS Docker Desktop only
# shares selected filesystem roots). The trap removes it on any exit, including a failed
# `docker run`/`docker cp`.
mkdir -p ./tmp
tmp_dir="$(cd "$(mktemp -d ./tmp/secret-gen.XXXXXX)" && pwd)"
trap 'rm -rf "$tmp_dir"' EXIT

# A previous crashed run can leave the fixed container name behind; clear it so the
# `docker run --name pass-gen-container` below does not fail with "name already in use".
docker rm -f pass-gen-container >/dev/null 2>&1 || true

mkdir -p "$tmp_dir/env"
cp ./sh/env/pass_gen.sh "$tmp_dir/env/pass_gen.sh"
printf '%s\n' "${missing_lines[@]}" > "$tmp_dir/env/.env.secret.template"

docker run --name pass-gen-container -v "$tmp_dir:/shell:ro" "$APP_PASS_GEN_IMAGE" sh /shell/env/pass_gen.sh
docker cp pass-gen-container:/.env.secret "$tmp_dir/generated.env.secret"
docker rm -f pass-gen-container > /dev/null 2>&1 || true

# Never append to a live secrets file without a recoverable copy. The backup sits in ./tmp
# (gitignored, rsync-excluded) and is readable by the current user only. `umask 077` closes the
# "created 0644, chmod later" window, and the existence check makes two runs inside the same
# second fail loudly instead of silently overwriting the first backup.
mkdir -p ./tmp/backups
backup_file="./tmp/backups/.env.secret.$(date -u +%Y%m%dT%H%M%SZ).bak"
if [ -e "$backup_file" ]; then
    echo -e "${RED}[Error]${RESET} Backup file $backup_file already exists — refusing to overwrite it." >&2
    exit 1
fi
old_umask="$(umask)"
umask 077
cp "$SECRET_FILE" "$backup_file"
umask "$old_umask"
# `cp` without -p creates the file with 0666 & ~umask (= 600); enforce it explicitly anyway.
chmod 600 "$backup_file"
echo -e "${CYAN}[Info]${RESET} Backup of the current .env.secret: ${backup_file}"

{
    echo ""
    echo "# --- Appended by secret-gen.sh on $(date -u +"%Y-%m-%dT%H:%M:%SZ") — keys missing from .env.secret ---"
    cat "$tmp_dir/generated.env.secret"
} >> "$SECRET_FILE"

echo -e "${LIGHTGREEN}[Success]${RESET} Added missing key(s) to $SECRET_FILE:"
for line in "${missing_lines[@]}"; do
    echo -e "  - ${line%%=*}"
done

if [ "${#warn_keys[@]}" -gt 0 ]; then
    echo -e "${LIGHTRED}[Warning]${RESET} The following key(s) have no default or generator in the template and were appended EMPTY — set a real value manually:"
    for key in "${warn_keys[@]}"; do
        echo -e "  - ${LIGHTRED}${key}${RESET}"
    done
fi
