ARG FLUENT_BIT_VERSION=4.0.3

# Temporary build image with shell and envsubst
FROM debian:bookworm-slim AS build-image

RUN apt-get update && \
    apt-get install -y --no-install-recommends gettext busybox && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Final distroless-based Fluent Bit image
FROM fluent/fluent-bit:${FLUENT_BIT_VERSION}

# Add envsubst and minimal shell (from busybox)
COPY --from=build-image /usr/bin/envsubst /usr/bin/envsubst
COPY --from=build-image /bin/busybox /bin/sh
COPY --from=build-image /usr/local/bin/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# Set entrypoint (will use /bin/sh because script uses #!/bin/sh)
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/fluent-bit/bin/fluent-bit", "-c", "/fluent-bit/etc/fluent-bit.conf"]
