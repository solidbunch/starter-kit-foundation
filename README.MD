<!--suppress HtmlDeprecatedAttribute -->
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
2. To run few instances on port 80 need [Nginx-proxy](https://hub.docker.com/r/jwilder/nginx-proxy) (optional), or you can
   use [Traefik](https://traefik.io/) (optional)

## How to use

### Installation

1. Create a new project directory<sup>[1](#footnote_fhs)</sup>:

```bash
mkdir you-project.com && cd you-project.com
```

2. Install Starter Kit Foundation:

```bash
git clone --depth=1 git@github.com:solidbunch/starter-kit-foundation.git . && rm -rf .git
```

3. Generate secrets env file:

```bash
make secret
```

4. Update environment variables in the `./config/environment/.env.main` file. Change your App name, etc.


5. Update `./config/environment/.env.type.dev|.env.type.stage|.env.type.prod` - specific environment types for development, staging, and production. Change App domain variable to yours. You can add any new environment type. For example, an additional production server for the use of multiply instances of the app.

<a name="footnote_fhs"></a>[1]: We recommend to use `/srv` folder instead `/var/www`. Create `/srv/apps` folder for your web apps. See [FHS](https://refspecs.linuxfoundation.org/FHS_3.0/fhs/ch03s17.html).

### Launch

1. Build the root `.env` file and run docker-compose:

```bash
make [t=<environment_type>] up
```

Where `environment_type` - any type that exist in `./config/environment/.env.type.*`. `dev` is the default.

**Examples:**

```bash
make up
make t=stage up
make t=prod up
```

Do not edit the automatically concatenated root `.env` file. It will be overwritten every time the app run.

After the installation, you can add your custom secrets to `.env.secret`, but keep in mind that your secrets will not appear in the repository and will not be visible to other users. There is a `./sh/env/.env.secret.template` file for this. It has a template of secrets, without secret data. 

You can add secret variables names there without secret data, just for structure. A password generator will replace the special word `generatethispass` with the real password when you run `make secret` (`bash sh/env/secret-gen.sh`).


:warning: **WARNING Do not define secrets (private keys, passwords, tokens, etc.) in committed files, it's not secure!**

### Launch in proxy mode
A proxy mode is useful when you are launching multiply web applications on port 80.

1. Start the nginx-proxy container

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

2. [Install](#installation) and use the Makefile command to run the proxy mode:

``` bash 
make [t=<environment_type>] upp
```

**Examples:**

```bash
make upp
make t=stage upp
make t=prod upp
```

### Production Launch with HTTPS

1. Put your certificate files in `./config/nginx/ssl/` with names <your-app-domain.com>.crt and <your-app-domain.com>.key
2. Change var APP_PROTOCOL=https in your .env.type.[environment_type]
3. Start containers with http > https redirect:

```bash
make up-prod
```
It will up special file `docker-compose.prod.yml` with 80 and your port (most likely 443). The configuration file `/config/nginx/templates/partials/https.conf.template`  will also be used instead of `/config/nginx/templates/partials/http.conf.template`

### Makefile commands

- `make secret`
- `make [t=<environment_type>] [s=<command>] up`
- `make [t=<environment_type>] [s=<command>] upd`
- `make [t=<environment_type>] [s=<command>] upp` - `make t=stage s=--build upp`
- `make [s=<command>] up-prod` - production launch with http > https redirect
- `make down` - `docker-compose down -v`
- `make start` - `docker-compose start`
- `make stop` - `docker-compose stop`
- `make pause` - `docker-compose pause`
- `make pma-up`
- `make pma-down`
- `make backup-init`

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

Docker containers do not have a custom SMTP server. We use an SMTP relay service. You can set up an SMTP server
like Gmail, AWS, Sendinblue, Mailgun, etc, or use another server you like. 

Just edit sSMTP config block in your `.env.secret` file.

sSMTP config files `./docker/wordpress/config/ssmtp.conf.template` and `./docker/wordpress/config/revaliases.template` automatically loaded into the WordPress container

See [an example](https://www.wordpressdocker.com/mailgun-ssmtp/) of ssmtp.conf

## Database management
### SSH tunnel options
You can use an SSH tunnel to connect to database from an external app (for example [MySQL Workbench](https://www.mysql.com/products/workbench/), [HeidiSQL](https://www.heidisql.com/) or [PHPStorm](https://www.jetbrains.com/help/phpstorm/configuring-ssh-and-ssl.html))
1. Uncomment ports directive in database service in `docker-compose.yml`

```
ports:
  - 127.0.0.1:${SSH_TUNNEL_EXT_PORT}:3306
```

2. Edit the `.env.main` file, find `SSH_TUNNEL_EXT_PORT` - make sure that the port is unique. If you are using multiple instances, change the port value.


3. Open your database management app and configure SSH tunnel, database connection 


### phpMyadmin options
To use phpMyadmin need to run the phpMyadmin container first. It's not running by default.

1. Edit the `.env.main` file, find `PMA_EXT_PORT` - make sure that the port is unique. If you are using multiple instances, change the port value.


2. Run phpMyadmin container:

```bash
make pma-up
```

3. Open the `your-app-domain.com:PMA_EXT_PORT` URL in the browser to access phpMyadmin. For example, we use `PMA_EXT_PORT=8801`. Open `your-app-domain.com:8801`


:warning: **WARNING Do not use phpMyadmin on public (production or open stage), it's not secure!**


To stop the phpMyadmin container run command:

```bash
make pma-down
```

## Additional scripts
### Automatic backups
The system has automatic backups. Launched by a cronjob. By default, daily and weekly backups work. With a retention period of 7 and 31 days, respectively. You can customize the frequency and content of backups yourself.

To activate backups:

1. Edit `./config/environment/.env.type.[environment_type]` file - enable `APP_WP_BACKUP_ENABLE` and check `APP_HOST_SYSTEM_CRON_DIR`


2. Check `./sh/backup/backup-crontab.template` - change cronjob time if it needs.


3. Run backups init script<sup>[2](#footnote_backup)</sup>:

```bash
make backup-init
```

Backups will appear in the `./backups` folder, logs in `./logs/cron/backup.log`

<a name="footnote_backup"></a>[2] Need sudo access