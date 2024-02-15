# Starter Kit foundation
<!--suppress HtmlDeprecatedAttribute -->

<p align="center">
  <a href="LICENSE.md">
    <img alt="GitHub" src="https://img.shields.io/github/license/solidbunch/starter-kit-foundation">
  </a>

  <a href="https://github.com/solidbunch/starter-kit-foundation/releases">
    <img alt="GitHub release (latest by date)" src="https://img.shields.io/github/v/release/solidbunch/starter-kit-foundation?color=blueviolet">
  </a>

</p>

<p align="center">
<strong>Starter Kit foundation - is a WordPress environment boilerplate for fast and easy start projects with docker containers, convenient credential settings, improved configuration.</strong>

</p>

## Requirements

1. [Docker Engine](https://docs.docker.com/engine/install/) v24+
2. [Docker Compose](https://docs.docker.com/compose/install/) v2.21+
3. [GitHub SSH key](https://docs.github.com/en/authentication/connecting-to-github-with-ssh)


## Creating new project

1. Create a new project directory and clone this repo into project folder.

2. Update environment variables in the `./config/environment/.env.main` file. Change `APP_NAME`, etc.

4. Update `./config/environment/.env.main|.env.type.local|.env.type.dev|.env.type.stage|.env.type.prod` - specific environment types for local, development, staging, and production. You can add any new environment type. For example, an additional production server for the use of multiply instances of the app. Change `APP_DOMAIN`, and other variables

5. Follow next [installation](#installation-of-existing-project) steps.

## Installation of existing project

1. Create a project folder and clone this repository if you haven't already done so

2. Run installation process:

```bash
make install [environment_type]
```
Where **environment_type** - any type that exist in ./config/environment/.env.type.*. `local` is the default. This will create a `.env.secrets` file with passwords, run PHP Composer, and NPM dependencies installation, build containers, set up the database, with WordPress tables, and create a wp-admin user. So, as a result, the project will be fully accessible in the browser with the domain you added to .env.type files.

For example, to use productions environment run:

```bash
make install prod
```

BTW: We recommend to use `/srv` folder instead `/var/www`. See [FHS](https://refspecs.linuxfoundation.org/FHS_3.0/fhs/ch03s17.html).


## Usage 🚀

The project is ready to use immediately after installation, but you can stop, recreate, launch the containers in different environments.

```bash
make up [environment_type]
```

Where `environment_type` - any type that exist in `./config/environment/.env.type.*`. `local` is the default.

**Examples:**

```bash
make up
make up stage
make up prod
```

Do not edit the automatically concatenated root `.env` file. It will be overwritten every time the app run.

After the installation, you can add your custom secrets 🔑 to `.env.secret`, but keep in mind that your secrets will not appear in the repository and will not be visible to other users. There is a `./sh/env/.env.secret.template` file for this. It has a template of secrets, without secret data.

You can add secret variables names there without secret data, just for structure. A password generator will replace the special word `generate_this_pass` with the real password when you run `make install` or `make secret` (`bash sh/env/secret-gen.sh`).


⚠️ **WARNING 📣 Do not define secrets (private keys, passwords, tokens, etc.) in committed files, it's not secure!**

## Run composer scripts

```bash
make run composer
```

```bash
composer install/update
```

## Run node scripts

```bash
make run node
```

```bash
npm install
```

## Production Launch with HTTPS

1. Put your certificate files in `./config/nginx/ssl/` with names <your-app-domain.com>.crt and <your-app-domain.com>.key
2. Change var `APP_PROTOCOL=https` in your `.env.type.[prod]`
3. Start containers with http > https redirect:

```bash
make up prod
```
The configuration file `/config/nginx/templates/config/https.conf.template`  will be used instead of `/config/nginx/templates/config/http.conf.template`

## Makefile commands

- `make install [environment_type]`
- `make secret`
- `make up [environment_type]` - `docker compose up -d --build`
- `make upd [environment_type]` - `docker compose up --build`
- `make down` - `docker compose down -v`
- `make restart` - `docker compose restart`
- `make recreate` - `docker compose up -d --build --force-recreate`
- `make pma`
- `make run [service_name]`
- `make exec [service_name]`

## Docker images
Use custom private packages storage for your project

## Structure
wp-content - docker mounted WordPress wp-content folder, it's your working directory. Add plugins and custom theme here.

```
backups/                  # Daily and weekly WordPress media and database backups
config/                   # Global config files
db-data/                  # Database docker mounted volume
docker/                   # Docker images (Dockerfiles) and additional scripts
logs/                     # System and wordpress logs
sh/                       # Bash scripts
├── env/                  # Operations with environment files
└── utils/                # Additional bash utils
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
make pma
```

3. Open the `your-app-domain.com:PMA_EXT_PORT` URL in the browser to access phpMyadmin. For example, we use `PMA_EXT_PORT=8801`. Open `your-app-domain.com:8801`


⚠️  **WARNING 📣 Do not use phpMyadmin on public (production or open stage), it's not secure!**


## Additional scripts
### Automatic backups
The system has automatic backups. Launched by a cronjob. By default, daily and weekly backups work. With a retention period of 7 and 31 days, respectively. You can customize the frequency and content of backups yourself.

To activate backups:

1. Edit `./config/environment/.env.type.[environment_type]` file - enable `APP_WP_BACKUP_ENABLE`


2. Check crontab file in `./config/crontabs` - change cronjob time if it needs.


3. If you have more than one database (maybe custom databases), check `mariadb-dump` command parameters in `./docker/cron/start-backup.sh`

Backups will appear in the `./backups` folder, logs in the docker cron container logs

## Contributing

Contributions are welcome from everyone. Developing with ❤️.
