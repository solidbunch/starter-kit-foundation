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

# Define the services and images
SERVICES=("mariadb"             "php"              "nginx"              "cron")
IMAGES=("${APP_DATABASE_IMAGE}" "${APP_PHP_IMAGE}" "${APP_NGINX_IMAGE}" "${APP_CRON_IMAGE}")

# Get the length of the arrays
ARRAY_LENGTH=${#SERVICES[@]}

if [ "$MODE" == "build" ]; then

  # Detect the architecture
  ARCHITECTURE=$(uname -m)

  # Map architecture to Docker's platform format
  case $ARCHITECTURE in
    x86_64)
      PLATFORM="linux/amd64"
      ;;
    aarch64)
      PLATFORM="linux/arm64"
      ;;
    arm64)
      PLATFORM="linux/arm64"
      ;;
    *)
      echo "Unsupported architecture: $ARCHITECTURE"
      exit 1
      ;;
  esac

  #docker compose -f docker-compose.yml build
  #docker compose -f docker-compose.build.yml build

  # Step 1: Login to GitHub Container Registry (GHCR)

  #echo $CR_PAT | docker login ghcr.io -u USERNAME --password-stdin

  # Step 2: Create a New Builder Instance

  #docker buildx create --name starter-kit-builder --bootstrap --use

  # Name of the builder
  BUILDER_NAME="starter-kit-builder"

  # Check if the builder already exists
  if ! docker buildx ls | grep -q $BUILDER_NAME; then
    # Builder does not exist, so create it
    echo -e "${CYAN}[Info]${NOCOLOR} Creating new builder instance named $BUILDER_NAME..."
    docker buildx create --name $BUILDER_NAME --bootstrap --use
  else
    # Builder exists, no action needed
    echo -e "${CYAN}[Info]${NOCOLOR} Builder $BUILDER_NAME already exists."
  fi

  # Step 3: Build the Image Locally

# Define parallel arrays for Dockerfile directories and their corresponding image names


  # Loop through the arrays
  for (( i=0; i<ARRAY_LENGTH; i++ )); do
    echo -e "${CYAN}[Info]${YELLOW} Building ${SERVICES[i]} [${PLATFORM}]${NOCOLOR}"
    docker buildx build --platform ${PLATFORM} -t "${IMAGES[i]}" "./dockerfiles/${SERVICES[i]}" --load
    echo -e "${LIGHTGREEN}[Success]${YELLOW} Build done for ${SERVICES[i]} ${IMAGES[i]} [${PLATFORM}]${NOCOLOR}"
    echo -e "-----------------------------------------------------------------"
    echo ""
  done

fi

## Push
# Step 4: Push the Image to the Registry

if [ "$MODE" == "push" ]; then

  for (( i=0; i<ARRAY_LENGTH; i++ )); do
    # Ask for user confirmation before building
    echo -e "Do you want to push ${LIGHTYELLOW}${SERVICES[i]}${NOCOLOR} image (${LIGHTYELLOW}${IMAGES[i]}${NOCOLOR})? (y/n)"
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
      echo -e "${CYAN}[Info]${NOCOLOR} Pushing ${SERVICES[i]} [linux/amd64,linux/arm64]${NOCOLOR}"
      docker buildx build --platform linux/amd64,linux/arm64 -t "${IMAGES[i]}" "./dockerfiles/${SERVICES[i]}"
      echo -e "${LIGHTGREEN}[Success]${YELLOW} Push done for ${SERVICES[i]} ${IMAGES[i]} [linux/amd64,linux/arm64]${NOCOLOR}"
      echo -e "-----------------------------------------------------------------"
      echo ""
    else
      echo -e "${LIGHTGREEN}Skipping push for ${SERVICES[i]}${NOCOLOR}"
      echo -e "-----------------------------------------------------------------"
      echo ""
    fi
  done

fi

#docker buildx build --platform linux/amd64,linux/arm64 -t ghcr.io/solidbunch/starter-kit-mariadb:11.2.2-jammy --push .


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
