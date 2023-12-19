#
# Run from original composer image
FROM composer:2.6

# Define the ARG variable with a default value
ARG CURRENT_GID=1000
ARG CURRENT_UID=1000

# Create the current user and home directory
RUN addgroup -S user -g $CURRENT_GID \
    && adduser -S -G user -u $CURRENT_UID user

USER user

