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

1. Check your GitHub SSH connection `ssh -T git@github.com`

2. Create a new project directory and clone this repository into the project folder.

3. Update environment variables in the `./config/environment/.env.main` file. Change `APP_NAME`, etc.

4. Update `./config/environment/.env.type.local`, `.env.type.dev`, `.env.type.stage`, `.env.type.prod` - specific environment types for local, development, staging, and production. You can add any new environment type. Change `APP_DOMAIN`, and other variables

5. Follow next [installation](#installation-of-existing-project) steps.

## Installation of existing project

1. Create a project folder and clone this repository if you haven't already done so

2. Run installation process:

```bash
make install [environment_type]
```
Where `environment_type` - any type that exist in `./config/environment/.env.type.*.` `local` is the default. This will create a `.env.secrets` file with passwords, run PHP Composer, and NPM dependencies installation, build containers, set up the database, with WordPress tables, and create a wp-admin user. So, as a result, the project will be fully accessible in the browser with the domain you added to `.env.type` files.

For example, to use production environment run:

```bash
make install prod
```
And `.env.type.prod` will be used with defined APP_DOMAIN, APP_PROTOCOL, and other settings.


BTW: We recommend using the `/srv` folder instead of `/var/www` for your web content. This recommendation is based on the [Filesystem Hierarchy Standard (FHS)](https://refspecs.linuxfoundation.org/FHS_3.0/fhs/ch03s17.html), which suggests /srv for site-specific data served by the system.


## Usage 🚀

The project is ready to use immediately after installation, but you can stop, recreate, launch the containers in different environments. To run containers use command:

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

Do not edit the automatically concatenated root `.env` file. It will be overwritten every time the app runs.

After the installation, you can add your custom secrets 🔑 to `.env.secret`, but keep in mind that your secrets will not appear in the repository and will not be visible to other users. There is a `./sh/env/.env.secret.template` file for this. It has a template of secrets, without secret data.

You can add secret variables names there without secret data, just for structure. A password generator will replace the special word `generate_this_pass` with the real password when you run `make install` or `make secret` (`bash sh/env/secret-gen.sh`).


⚠️ **WARNING 📣 Do not define secrets (private keys, passwords, tokens, etc.) in committed files, it's not secure!**

## Run composer scripts
To run PHP Composer, you need to run the `composer` container and enter it:
```bash
make run composer
```
Command `make run <service_name>` will run bash inside selected service (container).

Inside the container, you can use the command line to run any command you need in any folder of your project. For example, to install packages defined in the main composer.json file, in default folder `/srv` use:
```bash
composer install
```
or
```bash
composer update
```

## Run node scripts
To use watch with BrowserSync run:
```bash
make watch
```

To run other npm scripts need to run `node` container and enter it:
```bash
make run node
```
It has another default folder `/srv/web` - root WordPress folder. Use `cd` command to go to your theme and run any command.

## Production Launch with HTTPS

1. Place your certificate files in `./config/nginx/ssl/` with the names `<your-app-domain.com>.crt` and `<your-app-domain.com>.key`.
2. Update the variable `APP_PROTOCOL=https` in your `.env.type.prod` file to enable HTTPS.
3. Start containers with HTTP to HTTPS redirect:

```bash
make up prod
```
The configuration file `/config/nginx/templates/config/https.conf.template` will be used instead of `/config/nginx/templates/config/http.conf.template`

## Makefile commands

- `make install [environment_type]`
- `make secret`
- `make watch` - run node watcher
- `make up [environment_type]` - `docker compose up -d --build`
- `make upd [environment_type]` - `docker compose up --build`
- `make down` - `docker compose down -v`
- `make restart` - `docker compose restart`
- `make recreate` - `docker compose up -d --build --force-recreate`
- `make import <sql_file_name>` - import sql file to WordPress database
- `make export` - will export current database to sql file
- `make replace [search_domain] [replace_domain]` -  search replace domain in the database
- `make pma`
- `make run <service_name>` - `docker compose run -it --rm .... <service_name> ...`
- `make exec <service_name>` - `docker compose exec -it .... <service_name> ...`
- `make lint` - run php, js, and css linters
- `make docker clean` - remove all built containers, images, volumes, etc

## Docker images
Use custom containers registry for your project docker containers. [GitHub Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry) or [Docker Hub](https://docs.docker.com/guides/walkthroughs/publish-your-image/).
Use these commands to build and push images to the registry:
```bash
make docker build
```
```bash
make docker push
```

## Structure
```
├── backups/                  # Daily and weekly WordPress media, and database backups
├── config/                   # Global config files
├── db-data/                  # Database docker mounted volume
├── dockerfiles/              # Docker images (Dockerfiles). Need just for build
├── iasc/                     # IaC Terraform and Ansible configuration for server setup
├── logs/                     # System and WordPress logs
├── sh/                       # Bash scripts
│   ├── cron/                 # Cron scripts
│   ├── database/             # Database management
│   ├── env/                  # Operations with environment files
│   ├── utils/                # Additional bash utils
│   └── wp-cli/               # Scripts that used WP-CLI commands
├── web/                      # Web application folder
│   ├── wp-config/            # wp-config.php & files that should be copied to web root dir
│   ├── wp-content/           # wp-content folder
│   │   ├── mu-plugins/       # Must use plugins
│   │   ├── plugins/          # Plugins folder. Add your plugins here
│   │   ├── themes/           # Themes folder. Add your theme here
│   │   └── uploads/          # Media uploads folder. All subfolders content is gitignored
│   └── wp-core/              # WordPress core files, docker mounted volume
├── composer.json             # Manage version of WordPress, plugins & dependencies
├── docker-compose.build.yml  # Docker compose configuration file with utility services
├── docker-compose.yml        # Main docker compose file
└── Makefile                  # Make commands configuration
```
`wp-config` folder contents will copy to `wp-core` folder every time composer update/install runs.

`wp-content` - docker mounted WordPress folder. Add plugins and custom theme here.

`wp-core` - web public directory. WordPress core files. Do not edit files in the `wp-core` folder, it installs by composer.


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

### Reset database root password
1. In `docker-compose.yml` file uncomment `command: --skip-grant-tables` in mariadb service
2. Restart containers:
```bash
make restart
```
3. Enter inside mariadb container:
```bash
make exec mariadb
```
4. Inside container run:

```bash
mariadb> FLUSH PRIVILEGES; ALTER USER 'root'@'%' IDENTIFIED BY 'new_password';
```
Where 'new_password' - new root password

5. Revert back changes in `docker-compose.yml`

6. Restart containers:
```bash
make restart
```

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
