#!/bin/bash

# Script path
SCRIPT_PATH=$(dirname "$(readlink -f "$0")")

# Project root directory
cd $(dirname "$(readlink -f "$0")")/../../ || exit 1
PROJECT_ROOT_DIR=$PWD

# Check .env.secret file exist
if [ -f ./config/environment/.env.secret ]; then
    echo "[Info] .env.secret file already exist in ./config/environment/"; exit;
fi

# Go to the script directory
cd "$SCRIPT_PATH" || exit 1

# Check .env template file exist
if [ ! -f .env.secret.template ]; then
    echo "[Error] .env.secret.template file not found in $PWD"; exit 1;
fi

# Generate secrets, copy .env.secret template to .env.secret and replace generated secrets
awk '
  /generatethispass/ {
    cmd = "< /dev/urandom tr -dc A-Za-z0-9_ | head -c 20"
    cmd | getline str
    close(cmd)
    gsub("generatethispass", str)
  }
  { print }
' .env.secret.template > "$PROJECT_ROOT_DIR"/config/environment/.env.secret

echo "[Info] Secrets done in ./config/environment/.env.secret"
