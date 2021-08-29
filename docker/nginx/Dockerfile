#
# Supplement to original file
#
FROM nginx:1.20-alpine

COPY 40-setup-basic-auth.sh /docker-entrypoint.d
RUN chmod +x /usr/local/bin/40-setup-basic-auth.sh
