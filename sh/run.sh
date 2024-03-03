#!/bin/bash

# Stop when error
set -e

# Colors
source ./sh/utils/colors

source ./.env

# Default values

if [ "$1" != "" ]; then
  MODE="$1"
else
  echo -e "${LIGHTRED}[Error]${NOCOLOR} Mode parameter not defined"; exit 1;
fi

if [ "$2" != "" ]; then
  SERVICE="$2"
else
  echo -e "${LIGHTRED}[Error]${NOCOLOR} Service parameter not defined"; exit 1;
fi

if [ "$SERVICE" == "wp" ]; then
  SERVICE="php"
fi

# Default values
USER=${DEFAULT_USER}

if [ "$3" ]; then
    USER="$3"
fi

if [ "$MODE" == "run" ]; then
  docker compose \
    -f docker-compose.yml \
    -f docker-compose.build.yml \
    run \
      -it \
      --rm \
      --build \
    "${SERVICE}" \
    su -c "echo -e 'You are ${USER} user inside ${SERVICE} container' && bash" \
    "${USER}"
fi

if [ "$MODE" == "exec" ]; then
  docker compose \
    -f docker-compose.yml \
    -f docker-compose.build.yml \
    exec \
      -u "${USER}" \
    "${SERVICE}" \
    bash -c "echo -e 'You are ${USER} user inside ${SERVICE} container' && bash"
fi
