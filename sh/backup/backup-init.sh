#!/bin/bash

# Stop when error
set -e

# Script path
SCRIPT_PATH=$(dirname "$(readlink -f "$0")")

# Project root directory
cd $(dirname "$(readlink -f "$0")")/../../ || exit 1
PROJECT_ROOT_DIR=$PWD

# Check .env file exist
if [ ! -f .env ]; then
    echo "[Error] .env file not found in $PWD"; exit 1;
fi

# Load environment variables
source .env

# Check is backup enable
if [ ! "$APP_WP_BACKUP_ENABLE" ] || [ "$APP_WP_BACKUP_ENABLE" == 0 ]; then
    echo "[Fail] Backup is disabled in .env file"; exit 1;
fi

# Go to the script directory 
cd "$SCRIPT_PATH" || exit

# Copy crontab template to system cron directory and replace current project path
sed 's|PATH_TO_PROJECT_ROOT|'"$PROJECT_ROOT_DIR"'|g' ./backup-crontab.template > "$APP_HOST_SYSTEM_CRON_DIR"/"${APP_NAME,,}"-backup

echo "[Success] Backup init done"