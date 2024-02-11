# Run from original node image
FROM node:18-alpine3.18

RUN apk add --no-cache \
    bash

##################################
#   Prepare and run entrypoint   #
##################################
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["docker-entrypoint.sh"]
CMD [ "node" ]
