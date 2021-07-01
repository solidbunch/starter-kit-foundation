FROM mariadb:10.5

# Install cron
RUN apt-get update -y \
 && apt-get install -y --no-install-recommends cron \
 && rm -rf /var/lib/apt/lists/* \
 && apt-get clean

# COPY cp backup-daily.sh /usr/local/bin/
COPY ./crontabs/* /etc/cron.d/

COPY start-database.sh /usr/local/bin/

CMD ["start-database.sh"]
#CMD ["mysqld"]