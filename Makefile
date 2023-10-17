#!/usr/bin/make
.SILENT:

SHELL = /bin/sh

# Share current user and group ID with container
CURRENT_UID := $(shell id -u)
CURRENT_GID := $(shell id -g)

export CURRENT_UID
export CURRENT_GID

# Default values
LOGO_SH=bash ./sh/logo.sh

# https://stackoverflow.com/questions/6273608/how-to-pass-argument-to-makefile-from-command-line/6273809#6273809
# $(MAKECMDGOALS) is the list of targets passed to make
PARAMS = $(filter-out $@,$(MAKECMDGOALS))

# Go!
# Install project. Generate secrets, run composer and npm dependencies install
install:
	$(LOGO_SH)
	bash ./sh/env/secret-gen.sh
	bash ./sh/env/init.sh $(PARAMS)
	bash ./sh/install.sh $(PARAMS)

# Generate .env.secret file
secret:
	$(LOGO_SH)
	bash ./sh/env/secret-gen.sh

# Run composer install dev mode
composer:
	$(LOGO_SH)
	docker compose -f docker-compose.build.yml run --rm composer-container composer update-dev

# Run npm install dev mode
npm:
	$(LOGO_SH)
	docker compose -f docker-compose.build.yml run --rm node-container npm run install-dev

# Run mix watch with browserSync
watch:
	docker compose -f docker-compose.build.yml run --service-ports --rm node-container npm run watch

# Regular docker compose up with root .env file concatenation
up:
	$(LOGO_SH)
	docker compose up -d --build

# docker compose up with root .env file concatenation without `-d`
upd:
	$(LOGO_SH)
	docker compose up --build $(s)

# Just docker compose down
down:
	docker compose down -v

restart:
	docker compose restart

recreate:
	docker compose up -d --build --force-recreate

# Run database import script with first argument as file name and second as database name
import:
	bash ./sh/import_database.sh $(PARAMS)

# Run database export script with first argument as file name and second as database name
export:
	bash ./sh/export_database.sh $(PARAMS)

# Run database replacements script with first argument as search string and second as replace string
replace:
	docker compose -f docker-compose.build.yml run --rm wp-cli-container bash -c "bash /shell/database_replacements.sh $(PARAMS)"

# Run phpMyAdmin docker container
pma:
	docker compose -f docker-compose.build.yml run --service-ports --rm phpmyadmin

logs:
	docker compose logs -f

wlog:
	grc tail -f logs/wordpress/debug.log

ilog:
	grc tail -f logs/wordpress/info.log

# Full docker cleanup
docker-clean:
	docker container prune
	docker image prune -a
	docker volume prune
	docker network prune
	docker system prune

# This is a hack to allow passing arguments to the make command
# % is a wildcard. If no rule is matched (for arguments), this goal will be run
%:
# Do nothing
	@:
