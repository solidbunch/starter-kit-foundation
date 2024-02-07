#
# Run from original node image
FROM node:18-alpine3.18

# Define the ARG variable with a default value
ARG CURRENT_GID=1000
ARG CURRENT_UID=1000

# Create the current user and home directory
RUN deluser --remove-home node \
    && addgroup -g $CURRENT_GID node\
    && adduser -u $CURRENT_UID -D -G node node

RUN apk add --no-cache \
    bash
