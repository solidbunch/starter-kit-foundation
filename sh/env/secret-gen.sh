#!/bin/bash

# Stop when error
set -e

# Script path
SCRIPT_PATH=$(dirname "$(readlink -f "$0")")

# Project root directory
cd $(dirname "$(readlink -f "$0")")/../../ || exit 1
PROJECT_ROOT_DIR=$PWD

# Colors
source ./sh/utils/colors

# Check .env.secret file exist
if [ -f ./config/environment/.env.secret ]; then
    echo -e "${CYAN}[Info]${WHITE} .env.secret file already exist in ./config/environment/${NOCOLOR}"; exit;
fi

# Go to the script directory
cd "$SCRIPT_PATH" || exit 1

# Check .env template file exist
if [ ! -f .env.secret.template ]; then
    echo -e "${LIGHTRED}[Error]${WHITE} .env.secret.template file not found in ${PWD}${NOCOLOR}"; exit 1;
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
' .env.secret.template > "${PROJECT_ROOT_DIR}"/config/environment/.env.secret

echo -e "${LIGHTGREEN}[Success]${WHITE} Secrets done in ./config/environment/.env.secret${NOCOLOR}"
