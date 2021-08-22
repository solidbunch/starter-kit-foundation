#!/bin/bash

# Script path
SCRIPT_PATH=$(dirname "$(readlink -f "$0")")

# Project root directory
cd $(dirname "$(readlink -f "$0")")/../../ || exit 1
PROJECT_ROOT_DIR=$PWD

# Go to the script directory
cd "$SCRIPT_PATH" || exit 1

# Check .env template file exist
if [ ! -f .env.secret.template ]; then
    echo "[Error] .env.secret.template file not found in $PWD"; exit 1;
fi

# Generate secrets, copy .env.secret template to .env.secret and replace generated secrets
awk '
  /generatepass/ {
    cmd = "< /dev/urandom tr -dc A-Za-z0-9_%* | head -c 20"
    cmd | getline str
    close(cmd)
    gsub("generatepass", str)
  }
  { print }
' .env.secret.template > "$PROJECT_ROOT_DIR"/.env.secret

echo "Secrets done"
