#!/bin/bash

# Stop when error
set -e

# Script path
SCRIPT_PATH=$(dirname "$(readlink -f "$0")")

# Project root directory
cd $(dirname "$(readlink -f "$0")")/../../ || exit 1
PROJECT_ROOT_DIR=$PWD

# Default values
ENVIRONMENT_TYPE=dev

# Parse environment type args
if [ "$1" ]; then
    ENVIRONMENT_TYPE="$1"
fi

# Check .env.type.${ENVIRONMENT_TYPE} file exist
if [ ! -f ./config/environment/.env.type."${ENVIRONMENT_TYPE}" ]; then
    echo "[Error] .env.type.${ENVIRONMENT_TYPE} file not found in ./config/environment/"; exit 1;
fi

# Compile root .env file
cat ./config/environment/.env.main <(echo) ./config/environment/.env.type."${ENVIRONMENT_TYPE}" <(echo) ./config/environment/.env.secret > .env

echo "[Success] root .env ready"