<p align="center">

  <img alt="Starter Kit Foundation" src="https://starter-kit.io/images/logo1.png" height="100">

</p>

<p align="center">

  <a href="LICENSE.md">
    <img alt="GitHub" src="https://img.shields.io/github/license/solidbunch/starter-kit-foundation">
  </a>

  <a href="https://github.com/solidbunch/starter-kit-foundation/releases">
    <img alt="GitHub downloads" src="https://img.shields.io/github/downloads/solidbunch/starter-kit-foundation/total?color=green">
  </a>

  <a href="https://github.com/solidbunch/starter-kit-foundation/releases">
    <img alt="GitHub release (latest by date)" src="https://img.shields.io/github/v/release/solidbunch/starter-kit-foundation?color=blueviolet">
  </a>

</p>

<p align="center">
<strong>Starter Kit Foundation - is a WordPress environment boilerplate for fast and easy start projects with docker containers, convenient credential settings, improved configuration.</strong>

</p>

## What's inside the containers
<p align="center">

  <a href="https://hub.docker.com/_/php">
    <img alt="PHP" src="https://img.shields.io/badge/PHP%20fpm-7.4-8892bf">
  </a>

  <a href="https://hub.docker.com/_/mariadb">
    <img alt="MariaDB" src="https://img.shields.io/badge/MariaDB-10.5-c0765a">
  </a>

  <a href="https://hub.docker.com/_/wordpress">
    <img alt="WordPress" src="https://img.shields.io/badge/WordPress-5.8-lightgrey">
  </a>

  <a href="https://hub.docker.com/_/nginx">
    <img alt="Nginx" src="https://img.shields.io/badge/Nginx-1.20-00a652">
  </a>

  <a href="https://hub.docker.com/_/redis">
    <img alt="Redis" src="https://img.shields.io/badge/Redis-6.2-d82c20">
  </a>

  <a href="https://hub.docker.com/_/phpmyadmin">
    <img alt="phpMyAdmin" src="https://img.shields.io/badge/phpMyAdmin-5.1-f99d0f">
  </a>

</p>

## Requirements

1. [Docker Engine](https://docs.docker.com/engine/install/) v20.10+
   and [Docker Compose](https://docs.docker.com/compose/install/) v1.29+
2. To run few instances on 80 port need [Nginx-proxy](https://hub.docker.com/r/jwilder/nginx-proxy) (optional), or you can
   use [Traefik](https://traefik.io/) (optional)

## How to use

### Development mode

1. make project folder `mkdir you-project-dir-name`
2. clone repo `git clone git@github.com:solidbunch/starter-kit-foundation.git you-project-dir-name`
3. copy `.env.dev.sample` to  `.env`
4. edit `.env` file - change options, url and port, passwords, etc
5. run `docker-compose up -d`

### Staging mode

1. clone repo
2. copy `.env.stage.sample` to  `.env`
3. edit `.env` file - change options, url and port, passwords, etc
4. run `docker-compose up -d`

### Production mode

1. clone repo
2. copy `.env.prod.sample` to  `.env`
3. edit `.env` file - change options, url and port, passwords, etc
4. run `docker-compose up -d`

### Proxy mode

1. start nginx-proxy container

<details>
  <summary>Nginx-proxy docker-compose.yml file</summary>

  ```
version: '3.9'
services:
  nginx-proxy:
    image: jwilder/nginx-proxy:alpine
    container_name: nginx-proxy
    ports:
      - "8080:80"
      - "80:80"
      - "8443:443"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/tmp/docker.sock:ro
    restart: always

networks:
  default:
    external:
      name: nginx-proxy

```
</details>

[Docker hub Nginx-proxy details](https://hub.docker.com/r/jwilder/nginx-proxy)

2. clone repo, copy `.env` file the same as already described for the dev, stage or prod mode
3. run `docker-compose -f docker-compose.yml -f docker-compose.proxy.yml up -d`

### Init backup script

1. edit .env file - enable APP_WP_BACKUP_ENABLE and check APP_HOST_SYSTEM_CRON_DIR
2. check ./sh/backup/backup-crontab.template - change cronjob time if need
3. run `bash ./sh/backup/backup-init.sh`
4. backups will appear in ./backups folder, logs in ./logs/cron/backup.log

## Structure

```
backups/                  # Daily and weekly WordPress media and database backups 
config/                   # Global config files
db-data/                  # Database docker mounted volume
docker/                   # Docker images (Dockerfiles) and additional scripts
logs/                     # System and wordpress logs
sh/                       # Bash scripts
└── backup/               # Backup scripts (crontab, backup-init, start-backup)
wp-content/               # Docker mounted volume WordPress wp-content folder
├── mu-plugins/           # Must use plugins
├── plugins/              # Plugins folder. Add your plugins here
├── themes/               # Themes folder. Add your theme here
│   └── twenty*/          # Standard themes added to .gitignore
├── .../                  # Everything else in the wp-content folder is gitignored
└── uploads/              # Media uploads folder. All subfolders content is gitignored
wp-core/                  # WordPress core files, docker mounted volume. Gitignored
```

## Sending emails

Current docker containers do not have a custom SMTP server. We use an SMTP relay service. You can set up an SMTP server
like Gmail, AWS, Sendinblue, Mailgun, etc, or use another server you like. Just edit sSMTP config block in your .env
file.

See an example https://www.wordpressdocker.com/mailgun-ssmtp/

## Database management
### SSH tunnel options
You can use an SSH tunnel to connect to database from an external app (for example [HeidiSQL](https://www.heidisql.com/))
Uncomment ports directive in database service in docker-compose.yml and use constant `SSH_TUNNEL_EXT_PORT` to set up an external app port.


### phpMyadmin options
To use phpMyadmin need to run phpMyadmin container first. It's not running by default. 
1. edit `.env` file, find `PMA_EXT_PORT` - make sure that the port is unique. If you are using multiple instances, change the port value
2. run `docker-compose -f docker-compose.phpmyadmin.yml up -d`
3. open your-app-domain.com:PMA_EXT_PORT URL in the browser to access phpMyadmin

> :warning: **WARNING Do not run phpMyadmin on production, it's not secure!**


To stop phpMyadmin container run `docker-compose -f docker-compose.phpmyadmin.yml down -v`





