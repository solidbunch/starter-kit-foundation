#
# Run from original node image
FROM node:18-alpine3.17

# Define the ARG variable with a default value
ARG CURRENT_GID=1000
ARG CURRENT_UID=1000

# Get current user UID and GID from params
ARG CURRENT_GID
ARG CURRENT_UID

# Create the current user and home directory
RUN deluser --remove-home node \
    && addgroup -S node -g 1000 \
    && adduser -S -G node -u $CURRENT_UID node

USER node

