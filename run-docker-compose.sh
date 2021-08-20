#!/bin/bash

# Project bootstrap control file

# bash run-docker-compose.sh [-e <.env-file>] [-t type] [-m proxy] []

# Check package availability
#command -v docker-compose >/dev/null 2>&1 || { echo "[Error] Please install docker-compose"; exit 1; }
#command -v gzip >/dev/null 2>&1 || { echo "[Error] Please install gzip"; exit 1; }

# Default values
ENVIRONMENT_TYPE=development
BASH_RESULT_CL="docker-compose"

# Parse arguments

ENV_FILES=()
DOCKER_COMPOSE_FILES=()
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  key="$1"

  if [ $key == "-e" ] || [ $key == "--env-file" ]; then
      ENV_FILES+=("$2")
      shift # past argument
      shift # past value
  elif [ $key == "-f" ] || [ $key == "--docker-compose-file" ]; then
      DOCKER_COMPOSE_FILES+=("$2")
      shift # past argument
      shift # past value
  else
      POSITIONAL+=("$1") # save it in an array for later
      shift # past argument
  fi
done


set -a

WP_ENVIRONMENT_TYPE=$ENVIRONMENT_TYPE

for value in "${ENV_FILES[@]}"
do
     source $value
done

echo $MYSQL_HOST

set +a

# Iterate the loop to read and print each array element

for value in "${DOCKER_COMPOSE_FILES[@]}"
do
     BASH_RESULT_CL+=" -f ${value}"
done

for value in "${POSITIONAL[@]}"
do
     BASH_RESULT_CL+=" ${value}"
done

echo $BASH_RESULT_CL

$BASH_RESULT_CL




