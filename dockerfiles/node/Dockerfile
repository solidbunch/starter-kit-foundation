# Run from original node image
FROM node:18-alpine3.18

RUN apk add --no-cache \
    bash

ENTRYPOINT ["docker-entrypoint.sh"]
CMD [ "node" ]
