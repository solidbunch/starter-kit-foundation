#
# Run from original composer image
FROM composer:2.5

# Define the ARG variable with a default value
ARG CURRENT_GID=1000
ARG CURRENT_UID=1000

# Get current user UID and GID from params
ARG CURRENT_GID
ARG CURRENT_UID

# Create the current user and home directory
RUN addgroup -S user -g 1000 \
    && adduser -S -G user -u $CURRENT_UID user

USER user

