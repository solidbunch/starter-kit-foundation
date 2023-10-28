#!/bin/bash

# Stop when error
set -e

# Colors
source ./sh/utils/colors

# Check .env.secret file exist
if [ -f ./config/environment/.env.secret ]; then
    echo -e "${CYAN}[Info]${NOCOLOR} .env.secret file already exist in ./config/environment/"; exit 0;
fi

# Check .env template file exist
if [ ! -f ./sh/env/.env.secret.template ]; then
    echo -e "${LIGHTRED}[Error]${NOCOLOR} .env.secret.template file not found in ./sh/env/"; exit 1;
fi

# Cross platform password generator. Creating Alpine container, running pass gen, removing container
echo -e "${CYAN}[Info]${NOCOLOR} Generating Secrets..."

docker run --name pass-gen-container -v "./sh:/shell:ro" -it alpine:latest sh /shell/env/pass_gen.sh
docker cp pass-gen-container:/.env.secret ./config/environment/.env.secret
docker rm -f pass-gen-container > /dev/null 2>&1

echo -e "${LIGHTGREEN}[Success]${NOCOLOR} Secrets done in ./config/environment/.env.secret"
