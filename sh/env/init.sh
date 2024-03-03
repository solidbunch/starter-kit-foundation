#!/bin/bash

# Stop when error
set -e

# Colors
source ./sh/utils/colors

# We have no root .env yet, need to connect main env to generate root .env file
source ./config/environment/.env.main

# Get environment type ENVIRONMENT_TYPE var from args
# Default values
ENVIRONMENT_TYPE="$APP_DEFAULT_ENV_TYPE"

# Parse environment type args
if [ "$1" ]; then
    ENVIRONMENT_TYPE="$1"
fi

# Check .env.type.${ENVIRONMENT_TYPE} file exist
if [ ! -f ./config/environment/.env.type."${ENVIRONMENT_TYPE}" ]; then
    echo -e "${LIGHTRED}[Error]${NOCOLOR} .env.type.${ENVIRONMENT_TYPE} file not found in ./config/environment/"; exit 1;
fi

# Concatenate root .env file
cat ./config/environment/.env.main <(echo) ./config/environment/.env.type."${ENVIRONMENT_TYPE}" <(echo) ./config/environment/.env.secret > .env

# Check .env.type.${ENVIRONMENT_TYPE}.override file exist
if [ -f ./config/environment/.env.type."${ENVIRONMENT_TYPE}".override ]; then
    # Concatenate root .env file
    cat <(echo) ./config/environment/.env.type."${ENVIRONMENT_TYPE}".override >> .env

fi

echo -e "${LIGHTGREEN}[Success]${NOCOLOR} root .env ready for '${ENVIRONMENT_TYPE}'"
