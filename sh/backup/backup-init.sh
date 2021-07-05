#!/bin/bash

# Script path
SCRIPT_PATH=$(dirname "$(readlink -f "$0")")

# Project root directory
cd $(dirname "$(readlink -f "$0")")/../../
PROJECT_ROOT_DIR=$PWD

# Check .env file exist
if [ ! -f .env ]; then
    echo "[Error] .env file not found in $PWD"; exit 1;
fi

# Load enviroment variables
source .env

# Go to the script directory 
cd $SCRIPT_PATH

# Copy crontab template to system cron directory and replace current project path
sed 's|PATH_TO_PROJECT_ROOT|'$PROJECT_ROOT_DIR'|g' ./backup-crontab.template > $APP_HOST_SYSTEM_CRON_DIR/${APP_NAME,,}-backup 

echo "Backup init done"