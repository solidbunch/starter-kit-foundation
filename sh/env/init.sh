#!/bin/bash

# Script path
SCRIPT_PATH=$(dirname "$(readlink -f "$0")")

# Project root directory
cd $(dirname "$(readlink -f "$0")")/../../ || exit 1

# Default values
ENVIRONMENT_TYPE=dev

# Parse environment type args
if [ "$1" ]; then
    ENVIRONMENT_TYPE="$1"
fi

# Check .env.${ENVIRONMENT_TYPE} file exist
if [ ! -f .env.type."${ENVIRONMENT_TYPE}" ]; then
    echo "[Error] .env.type.${ENVIRONMENT_TYPE} file not found in $PWD"; exit 1;
fi

# Run secrets generator and make .env.secret file
#bash sh/env/secret-gen.sh

cat .env.main <(echo) .env.type."${ENVIRONMENT_TYPE}" <(echo) .env.secret > .env
