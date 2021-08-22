<p align="center">

  <img alt="Starter Kit Foundation" src="https://starter-kit.io/images/logo1.png" height="100">

</p>

<p align="center">

  <a href="LICENSE.md">
    <img alt="GitHub" src="https://img.shields.io/github/license/solidbunch/starter-kit-foundation">
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

### First run

1. make project folder

```bash
mkdir you-project-dir-name
```
2. clone repo to your project dir 
```bash
cd you-project-dir-name
```

```bash
git clone git@github.com:solidbunch/starter-kit-foundation.git .
```   
3. generate secrets env - run `bash sh/env/secret-gen.sh`
4. edit `.env.main` file - change your App name, etc
5. edit `.env.type.dev|.env.type.stage|.env.type.prod` - specific environment types for development, staging and production (you can add any new environment type)
6. run `bash sh/env/init.sh dev` to put together environment files development mode. You can run

```bash
bash sh/env/init.sh [environment_type]
```
`environment_type` - any type that exist, like `.env.[environment_type]` `dev` mode is default

7. run `docker-compose up -d`

Do not edit the automatically compiled `.env` file. It will be overwritten every time the app run.
After the first run, you can add secrets to `.env.secret`, but keep in mind that your secrets will not go to the repository and will not be visible to other users. There is a `./sh/env/.env.secret.template` file for this. It has a template of secrets, without secret data. 

You can add secret variables names there without secret data, just for structure. A password generator will replace the special word `generatepass`   real password when you run `bash sh/env/secret-gen.sh`.

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
    environment:
      DISABLE_ACCESS_LOGS: 1
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/tmp/docker.sock:ro
      - ./logs:/var/log/nginx
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

## Structure
wp-content - docker mounted WordPress wp-content folder, it's your working directory. Add plugins and custom theme here.

```
backups/                  # Daily and weekly WordPress media and database backups 
config/                   # Global config files
db-data/                  # Database docker mounted volume
docker/                   # Docker images (Dockerfiles) and additional scripts
logs/                     # System and wordpress logs
sh/                       # Bash scripts
└── backup/               # Backup scripts (crontab, backup-init, start-backup)
wp-content/               # Docker mounted volume, WordPress wp-content folder
├── mu-plugins/           # Must use plugins
├── plugins/              # Plugins folder. Add your plugins here
├── themes/               # Themes folder. Add your theme here
│   └── twenty*/          # Standard themes added to .gitignore
├── .../                  # Everything else in the wp-content folder is gitignored
└── uploads/              # Media uploads folder. All subfolders content is gitignored
wp-core/                  # WordPress core files, docker mounted volume. Gitignored
```

Do not edit files in the wp-core folder, it builds automatically.

## Sending emails

Current docker containers do not have a custom SMTP server. We use an SMTP relay service. You can set up an SMTP server
like Gmail, AWS, Sendinblue, Mailgun, etc, or use another server you like. 

Just edit sSMTP config block in your `.env` file.

sSMTP config files `./docker/wordpress/config/ssmtp.conf.template` and `./docker/wordpress/config/revaliases.template` automatically loaded into the WordPress container

See [an example](https://www.wordpressdocker.com/mailgun-ssmtp/) of ssmtp.conf

## Database management
### SSH tunnel options
You can use an SSH tunnel to connect to database from an external app (for example [MySQL Workbench](https://www.mysql.com/products/workbench/), [HeidiSQL](https://www.heidisql.com/) or [PHPStorm](https://www.jetbrains.com/help/phpstorm/configuring-ssh-and-ssl.html))
1. uncomment ports directive in database service in `docker-compose.yml`
```
ports:
  - 127.0.0.1:${SSH_TUNNEL_EXT_PORT}:3306
```
2. edit the `.env` file, find `SSH_TUNNEL_EXT_PORT` - make sure that the port is unique. If you are using multiple instances, change the port value
3. open your database management app and configure SSH tunnel, database connection 


### phpMyadmin options
To use phpMyadmin need to run the phpMyadmin container first. It's not running by default.
1. edit the `.env` file, find `PMA_EXT_PORT` - make sure that the port is unique. If you are using multiple instances, change the port value
2. run `docker-compose -f docker-compose.phpmyadmin.yml up -d`
3. open the `your-app-domain.com:PMA_EXT_PORT` URL in the browser to access phpMyadmin. For example, we use `PMA_EXT_PORT=8801`. Open `your-app-domain.com:8801`

> :warning: **WARNING Do not use phpMyadmin on public (production or open stage), it's not secure!**


To stop the phpMyadmin container run command `docker-compose -f docker-compose.phpmyadmin.yml down -v`

## Additional scripts
### Init backup script
The system has automatic backups. Launched by a cronjob. By default, daily and weekly backups work. With a retention period of 7 and 31 days, respectively. You can customize the frequency and content of backups yourself. To activate backups:

1. edit `.env` file - enable `APP_WP_BACKUP_ENABLE` and check `APP_HOST_SYSTEM_CRON_DIR`
2. check `./sh/backup/backup-crontab.template` - change cronjob time if need
3. run `bash ./sh/backup/backup-init.sh`

Backups will appear in the `./backups` folder, logs in `./logs/cron/backup.log`