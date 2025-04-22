#!/bin/bash
# Operations with local dockerfiles
# Build, publish to cloud storage, and clear local images
# Check your credentials before push
# https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry
# https://docs.docker.com/guides/walkthroughs/publish-your-image/

# Stop when error
set -e

# Colors
source ./sh/utils/colors

source ./.env

# Default values
MODE="build"

if [ "$1" ]; then
    MODE="$1"
fi

if [ "$2" ]; then
    BUILD_SERVICE="$2"
fi

# Define the services and images arrays
SERVICES=("mariadb"             "php"              "nginx"              "cron"              "composer"              "node"              "certbot")
IMAGES=("${APP_DATABASE_IMAGE}" "${APP_PHP_IMAGE}" "${APP_NGINX_IMAGE}" "${APP_CRON_IMAGE}" "${APP_COMPOSER_IMAGE}" "${APP_NODE_IMAGE}" "${APP_CERTBOT_IMAGE}")

PLATFORMS=linux/amd64,linux/arm64

# Get the length of the arrays
ARRAY_LENGTH=${#SERVICES[@]}

CreateBuilder() {
    # Name of the builder
    BUILDER_NAME="starter-kit-builder"

    # Check if the builder already exists
    if ! docker buildx ls | grep -q $BUILDER_NAME; then
      # Builder does not exist, so create it
      echo -e "${CYAN}[Info]${NOCOLOR} Creating new builder instance named $BUILDER_NAME..."
      docker buildx create --name $BUILDER_NAME --bootstrap --use
    else
      # Builder exists, no action needed
      docker buildx use ${BUILDER_NAME}
      echo -e "${CYAN}[Info]${NOCOLOR} Builder $BUILDER_NAME already exists."
    fi
}

## Build
# Build the images with defined names
if [ "$MODE" == "build" ]; then

  # Loop through the arrays
  for (( i=0; i<ARRAY_LENGTH; i++ )); do

    # Check if $BUILD_SERVICE parameter exist for build only selected service
    if [[ -n "$BUILD_SERVICE" && "$BUILD_SERVICE" != "${SERVICES[i]}" ]]; then
      continue
    fi

    echo -e "${CYAN}[Info]${NOCOLOR} Building ${YELLOW}${SERVICES[i]}${NOCOLOR}"

    docker build \
      --build-arg \
        APP_PHP_IMAGE="${APP_PHP_IMAGE}" \
      -t "${IMAGES[i]}" \
      "./dockerfiles/${SERVICES[i]}" \

    echo -e "${LIGHTGREEN}[Success]${NOCOLOR} Build done for ${YELLOW}${SERVICES[i]} ${IMAGES[i]}${NOCOLOR}"
    echo -e "-----------------------------------------------------------------"
    echo ""
  done

fi

## Push
# Build and Push the Images to the Registry
if [ "$MODE" == "push" ]; then

  # Step 1: Login to Container Registry (CR)

  echo -e "${CYAN}[Info]${NOCOLOR} Use your PAT (CR_TOKEN var) and 'USERNAME' placeholder to login to Container Registry ${NOCOLOR} "
  export "$(grep -v '^#' .env | xargs)"
  echo "$CR_TOKEN" | docker login ghcr.io -u USERNAME --password-stdin
  #docker login ghcr.io
  #echo "$CR_TOKEN" | docker login registry.gitlab.com -u USERNAME --password-stdin

  # Step 2: Create a New Builder Instance

  CreateBuilder

  # Step 3: Build and Push to Container Registry (CR)
  for (( i=0; i<ARRAY_LENGTH; i++ )); do

    # Check if $BUILD_SERVICE parameter exist for push only selected service
    if [[ -n "$BUILD_SERVICE" && "$BUILD_SERVICE" != "${SERVICES[i]}" ]]; then
      continue
    fi

    # Ask for user confirmation before building
    echo -e "Do you want to push ${LIGHTYELLOW}${SERVICES[i]}${NOCOLOR} image (${YELLOW}${IMAGES[i]}${NOCOLOR})? (y/n)"
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
      echo -e "${CYAN}[Info]${NOCOLOR} Building and Pushing ${YELLOW}${SERVICES[i]}${NOCOLOR} [${PLATFORMS}]"

      # Building image and pushing it into registry
      # APP_PHP_IMAGE needed for composer image only
      docker buildx build \
        --build-arg \
          APP_PHP_IMAGE="${APP_PHP_IMAGE}" \
        --platform linux/amd64,linux/arm64 \
        -t "${IMAGES[i]}" \
        "./dockerfiles/${SERVICES[i]}" \
        --output "type=image,name=target,annotation-index.org.opencontainers.image.description=Docker ${SERVICES[i]} [linux/amd64;linux/arm64] image,annotation-index.org.opencontainers.image.licenses=MIT License" \
        --push

      echo -e "${LIGHTGREEN}[Success]${NOCOLOR} Push done for ${YELLOW}${SERVICES[i]} ${IMAGES[i]}${NOCOLOR} [${PLATFORMS}]"
      echo -e "-----------------------------------------------------------------"
      echo ""
    else
      echo -e "${CYAN}[Info]${NOCOLOR} Skipping push for ${YELLOW}${SERVICES[i]}${NOCOLOR}"
      echo -e "-----------------------------------------------------------------"
      echo ""
    fi
  done

fi

## Clean
# Full docker cleanup
if [ "$MODE" == "clean" ]; then
  docker container prune
  docker image prune -a
  docker volume prune
  docker network prune
  docker system prune
  docker buildx prune
fi
