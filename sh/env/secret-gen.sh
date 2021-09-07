#!/bin/bash

# Stop when error
set -e

# Colors
source ./sh/utils/colors

# Check .env.secret file exist
if [ -f ./config/environment/.env.secret ]; then
    echo -e "${CYAN}[Info]${WHITE} .env.secret file already exist in ./config/environment/${NOCOLOR}"; exit;
fi

# Check .env template file exist
if [ ! -f ./sh/env/.env.secret.template ]; then
    echo -e "${LIGHTRED}[Error]${WHITE} .env.secret.template file not found in ./sh/env/${NOCOLOR}"; exit 1;
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
' ./sh/env/.env.secret.template > ./config/environment/.env.secret

echo -e "${LIGHTGREEN}[Success]${WHITE} Secrets done in ./config/environment/.env.secret${NOCOLOR}"
