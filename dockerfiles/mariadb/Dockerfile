# Run from original mariadb ubuntu
FROM mariadb:11.8.9-noble

# Install pv
RUN apt-get update; \
    apt-get install -y pv; \
    rm -rf /var/lib/apt/lists/*

# Prepare and run entrypoint: our scripts first (docker-entrypoint.d), then the original
# docker-entrypoint.sh of the official image. Setting ENTRYPOINT resets the inherited CMD.
COPY --chmod=755 docker-entrypoint.sh /docker-entrypoint.sh
COPY --chmod=755 docker-entrypoint.d/ /docker-entrypoint.d/

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["mariadbd"]
