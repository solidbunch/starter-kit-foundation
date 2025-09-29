#!/bin/bash

# Stop when error
set -e

# Colors
source ./sh/utils/colors.sh

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
    echo -e "${LIGHTRED}[Error]${RESET} .env.type.${ENVIRONMENT_TYPE} file not found in ./config/environment/"; exit 1;
fi

# 1) Build non-secret runtime env first (main + type [+ override])
RUNTIME_ENV=".env.runtime"
cat ./config/environment/.env.main <(echo) ./config/environment/.env.type."${ENVIRONMENT_TYPE}" > "$RUNTIME_ENV"

# Check .env.type.${ENVIRONMENT_TYPE}.override file exist
if [ -f ./config/environment/.env.type."${ENVIRONMENT_TYPE}".override ]; then
    cat <(echo) ./config/environment/.env.type."${ENVIRONMENT_TYPE}".override >> "$RUNTIME_ENV"
fi

# 2) Concatenate root .env file
cat "$RUNTIME_ENV" <(echo) ./config/environment/.env.secret > .env

echo -e "${LIGHTGREEN}[Success]${RESET} .env.runtime ready"
echo -e "${LIGHTGREEN}[Success]${RESET} root .env ready for '${ENVIRONMENT_TYPE}'"
