#!/bin/bash

# Project bootstrap control file

# bash run.sh <up> [-t type] [-m proxy] []

# Check package availability
#command -v docker-compose >/dev/null 2>&1 || { echo "[Error] Please install docker-compose"; exit 1; }
#command -v gzip >/dev/null 2>&1 || { echo "[Error] Please install gzip"; exit 1; }

# Default values
ENVIRONMENT_TYPE=development
#USE_PROXY=0
DIRECTION=$1

# Parse arguments
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  key="$2"

  case $key in
    -t|--type)
      ENVIRONMENT_TYPE="$3"
      shift # past argument
      shift # past value
      ;;
    -m|--mode)
      USE_PROXY="$3"
      shift # past argument
      shift # past value
      ;;
    *)    # unknown option
      POSITIONAL+=("$2") # save it in an array for later
      shift # past argument
      ;;
  esac
done

set -- "${POSITIONAL[@]}" # restore positional parameters

echo "ENVIRONMENT_TYPE  = ${ENVIRONMENT_TYPE}"
echo "USE_PROXY     = ${USE_PROXY}"

set -a # automatically export all variables

WP_ENVIRONMENT_TYPE=$ENVIRONMENT_TYPE

echo "$WP_ENVIRONMENT_TYPE"

source .env
source .env."$WP_ENVIRONMENT_TYPE"
source .env.local

echo $APP_DOMAIN
set +a

if [ $DIRECTION == "up" ]; then
  if [ "$USE_PROXY" ]; then
    docker-compose -f docker-compose.yml -f docker-compose.proxy.yml up -d
  else
    docker-compose up -d
  fi
else
  docker-compose down
fi




