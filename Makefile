#!/usr/bin/make
.SILENT:

include ./sh/utils/colors

include ./config/environment/.env.main

SHELL = /bin/sh

# Share current user and group ID with container
CURRENT_UID := $(shell id -u)
CURRENT_GID := $(shell id -g)

# Check if CURRENT_UID and CURRENT_GID are less than 1000 (Fix Mac users ID)
ifeq ($(shell expr $(CURRENT_UID) \< 1000), 1)
	CURRENT_UID := 1000
endif

ifeq ($(shell expr $(CURRENT_GID) \< 1000), 1)
	CURRENT_GID := 1000
endif

#if [ ! "${CURRENT_GID}" ] || [ ! "${CURRENT_UID}" ]; then
#  CURRENT_GID="${DEFAULT_GID}"
#  CURRENT_UID="${DEFAULT_UID}"
#fi


export CURRENT_UID
export CURRENT_GID

export DOCKER_BUILDKIT=1

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
	# Generate .env.secret
	bash ./sh/env/secret-gen.sh
	# Init root .env file
	bash ./sh/env/init.sh $(PARAMS)
	# Composer and npm build
	bash ./sh/install.sh $(PARAMS)
	# Check WordPress installed correctly
	docker compose run -it --rm php su -c "wp core verify-checksums" $(DEFAULT_USER)
	# Run main project docker containers
	docker compose up -d
	# Check database is up
	bash ./sh/database/check.sh
	# Setup WordPress database
	docker compose exec php su -c "bash /shell/wp-cli/core-install.sh" $(DEFAULT_USER)

# Generate .env.secret file
secret:
	$(LOGO_SH)
	bash ./sh/env/secret-gen.sh

init:
	$(LOGO_SH)
	bash ./sh/env/init.sh $(PARAMS)

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
import:
	bash ./sh/database/import.sh $(PARAMS)

# Run database export script with first argument as file name and second as database name
export:
	bash ./sh/database/export.sh $(PARAMS)

# Run database replacements script with first argument as search string and second as replace string
replace:
	docker compose run --rm --build php su -c "bash /shell/wp-cli/search-replace.sh $(PARAMS)" $(DEFAULT_USER)

# Run phpMyAdmin docker container
pma:
	docker compose -f docker-compose.build.yml run --service-ports --rm --build phpmyadmin

log:
	docker compose logs -f

run:
	$(LOGO_SH)
	bash ./sh/run.sh run $(PARAMS)

exec:
	$(LOGO_SH)
	bash ./sh/run.sh exec $(PARAMS)

lint:
	docker compose -f docker-compose.build.yml run -it --rm --build composer su -c "cd web/wp-content/themes/${WP_DEFAULT_THEME} && composer lint" $(DEFAULT_USER)
	docker compose -f docker-compose.build.yml run -it --rm --build node su -c "cd wp-content/themes/${WP_DEFAULT_THEME} && npm run lint" $(DEFAULT_USER)

# IasC
terraform:
	terraform -chdir=iasc/terraform $(PARAMS)

ansible:
	ansible-playbook -i iasc/ansible/inventory.ini iasc/ansible/prepare-servers.yml $(PARAMS)

# docker build|docker push|docker clean
docker:
	bash ./sh/docker.sh $(PARAMS)

# This is a hack to allow passing arguments to the make command
# % is a wildcard. If no rule is matched (for arguments), this goal will be run
%:
# Do nothing
	@:
