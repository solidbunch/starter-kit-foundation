FROM alpine:3.20

RUN apk update && \
    apk add --no-cache bash certbot openssl

##################################
#   Prepare and run entrypoint   #
##################################
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["certbot"]
