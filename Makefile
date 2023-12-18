#!/usr/bin/make
.SILENT:

include ./sh/utils/colors

include .env

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
# `make install dev composer` - will run only composer update
# `make install dev npm` - will run only npm install and run dev mode
install:
	$(LOGO_SH)
	bash ./sh/env/secret-gen.sh
	bash ./sh/env/init.sh $(PARAMS)
	bash ./sh/install.sh $(PARAMS)

# Generate .env.secret file
secret:
	$(LOGO_SH)
	bash ./sh/env/secret-gen.sh

# Run mix watch with browserSync
watch:
	$(LOGO_SH)
	bash ./sh/npm-watch.sh $(PARAMS)

# Regular docker compose up with root .env file concatenation
up:
	$(LOGO_SH)
	bash ./sh/env/init.sh $(PARAMS)
	docker compose up -d --build

# docker compose up with root .env file concatenation without `-d`
upd:
	$(LOGO_SH)
	bash ./sh/env/init.sh $(PARAMS)
	docker compose up --build

# Just docker compose down
down:
	docker compose down -v

restart:
	bash ./sh/env/init.sh $(PARAMS)
	docker compose restart

recreate:
	bash ./sh/env/init.sh $(PARAMS)
	docker compose up -d --build --force-recreate

# Run database import script with first argument as file name and second as database name
db-import:
	bash ./sh/import_database.sh $(PARAMS)

# Run database export script with first argument as file name and second as database name
db-export:
	bash ./sh/export_database.sh $(PARAMS)

# Run database replacements script with first argument as search string and second as replace string
replace:
	docker compose -f docker-compose.build.yml run --rm wp-cli-container bash -c "bash /shell/database_replacements.sh $(PARAMS)"

# Run phpMyAdmin docker container
pma:
	docker compose -f docker-compose.build.yml run --service-ports --rm phpmyadmin

# run WP-CLI container for custom commands
wp:
	docker compose -f docker-compose.build.yml run --rm wp-cli-container bash 2> /dev/null

log:
	docker compose logs -f

wlog:
	grc tail -f logs/wordpress/debug.log

ilog:
	grc tail -f logs/wordpress/info.log

# Run container and bash inside container
run:
	$(LOGO_SH)
	docker compose -f docker-compose.build.yml run -it --rm $(PARAMS) sh -c "echo -e 'You are inside $(PARAMS) container' && sh" 2> /dev/null

lint:
	docker compose -f docker-compose.build.yml run -it --rm composer-container sh -c "cd app/wp-content/themes/${WP_DEFAULT_THEME} && composer lint"
	docker compose -f docker-compose.build.yml run -it --rm node-container sh -c "cd app/wp-content/themes/${WP_DEFAULT_THEME} && npm run lint"

# IasC
terraform:
	terraform -chdir=iasc/terraform $(PARAMS)

ansible:
	ansible-playbook iasc/ansible/prepare-servers.yml $(PARAMS)

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
