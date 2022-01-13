#
# Supplement to original file
#
FROM nginx:1.21-alpine

RUN apk add --no-cache openssl

COPY 15-setup-basic-auth.sh /docker-entrypoint.d
RUN chmod +x /docker-entrypoint.d/15-setup-basic-auth.sh
