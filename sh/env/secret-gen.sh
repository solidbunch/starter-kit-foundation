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

# Check pass-gen.sh file exist
if [ ! -f ./sh/env/pass-gen.sh ]; then
    echo -e "${LIGHTRED}[Error]${WHITE} pass-gen.sh file not found in ./sh/env/${NOCOLOR}"; exit 1;
fi

# Cross platform password generator. Creating Alpine container, running awk, removing container
echo -e "${CYAN}[Info]${WHITE} Creating Alpine container, running awk, removing container${NOCOLOR}"

docker run -it --name pass-gen-container -d alpine
docker cp ./sh/env/.env.secret.template pass-gen-container:/.env.secret.template
docker cp ./sh/env/pass-gen.sh pass-gen-container:/pass-gen.sh
docker exec -it pass-gen-container sh /pass-gen.sh
docker cp pass-gen-container:/.env.secret ./config/environment/.env.secret
docker rm -f pass-gen-container


echo -e "${LIGHTGREEN}[Success]${WHITE} Secrets done in ./config/environment/.env.secret${NOCOLOR}"
