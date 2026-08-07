#!/usr/bin/make
.SILENT:

include ./config/environment/.env.main

# Multi-instance (reverse proxy) support. All logic lives in the solidbunch/proxy kit module;
# this line is the only hook. Expands to nothing when the module is absent or the mode is off.
# $$ is deliberate: it survives make's expansion and is evaluated by the recipe shell, so it reads
# .env.runtime as refreshed by `sh/env/init.sh` earlier in the same recipe — not a stale parse-time
# value. Verified on GNU Make 3.81 and 4.3.
COMPOSE_OVERRIDE = $$(test -f ./kit-modules/proxy/bin/compose-flags.sh && bash ./kit-modules/proxy/bin/compose-flags.sh)

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

# Share current project folder path
WORKING_DIR := $(CURDIR)

export CURRENT_UID
export CURRENT_GID
export WORKING_DIR

export DOCKER_BUILDKIT=1

# Default values
LOGO_SH=bash ./sh/utils/logo.sh

# https://stackoverflow.com/questions/6273608/how-to-pass-argument-to-makefile-from-command-line/6273809#6273809
# $(MAKECMDGOALS) is the list of targets passed to make
PARAMS = $(filter-out $@,$(MAKECMDGOALS))
GOAL := $(word 1, $(PARAMS))
PARAM1 := $(word 2, $(PARAMS))
PARAM2 := $(word 3, $(PARAMS))
PARAM3 := $(word 4, $(PARAMS))
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
	bash ./sh/system/install.sh
	# Run main project docker containers
	docker compose $(COMPOSE_OVERRIDE) up -d
	# Check database is up
	bash ./sh/database/check.sh
	# Setup WordPress database
	docker compose $(COMPOSE_OVERRIDE) exec php su -c "bash /shell/wp-cli/core-install.sh" $(DEFAULT_USER)

i:
	$(MAKE) install

# Generate .env.secret file
secret:
	$(LOGO_SH)
	bash ./sh/env/secret-gen.sh

env:
	$(LOGO_SH)
	bash ./sh/env/init.sh $(PARAMS)

ssl:
	bash ./sh/system/certbot.sh $(PARAMS)

core-install:
	docker compose $(COMPOSE_OVERRIDE) exec php su -c "bash /shell/wp-cli/core-install.sh" $(DEFAULT_USER)

# Run mix watch with browserSync
watch:
	$(LOGO_SH)
	bash ./sh/dev/npm-watch.sh $(PARAMS)

# Regular docker compose up with root .env file concatenation
up:
	$(LOGO_SH)
	bash ./sh/env/init.sh $(PARAMS)
	docker compose $(COMPOSE_OVERRIDE) up -d

# docker compose up with root .env file concatenation without `-d`
upd:
	$(LOGO_SH)
	bash ./sh/env/init.sh $(PARAMS)
	docker compose $(COMPOSE_OVERRIDE) up

# Just docker compose down
down:
	docker compose $(COMPOSE_OVERRIDE) down -v

restart:
	bash ./sh/env/init.sh $(PARAMS)
	docker compose $(COMPOSE_OVERRIDE) restart

recreate:
	bash ./sh/env/init.sh $(PARAMS)
	docker compose $(COMPOSE_OVERRIDE) up -d --force-recreate

# Run database import script with first argument as file name and second as database name
import:
	bash ./sh/database/import.sh -f $(PARAM1) -t
	docker compose $(COMPOSE_OVERRIDE) exec php su -c "bash /shell/wp-cli/search-replace.sh" $(DEFAULT_USER)

# Run database export script with first argument as file name and second as database name
export:
	bash ./sh/database/export.sh

# Run database replacements script with first argument as search string and second as replace string
replace:
	docker compose $(COMPOSE_OVERRIDE) run --rm php su -c "bash /shell/wp-cli/search-replace.sh $(PARAMS)" $(DEFAULT_USER)

migrate:
	bash ./sh/system/migrate.sh -s $(PARAM1) -d $(PARAM2) -t

# Run phpMyAdmin docker container
pma:
	docker compose -f docker-compose.toolkit.yml run --service-ports --rm phpmyadmin

mailhog:
	docker-compose -f docker-compose.toolkit.yml run --service-ports --rm --name mailhog mailhog

log:
	docker compose logs -f $(PARAMS)

run:
	$(LOGO_SH)
	bash ./sh/dev/run.sh run $(PARAMS)

exec:
	$(LOGO_SH)
	bash ./sh/dev/run.sh exec $(PARAMS)

lint:
	docker compose -f docker-compose.toolkit.yml run -it --rm composer su -c "cd web/wp-content/themes/${WP_DEFAULT_THEME} && composer lint" $(DEFAULT_USER)
	docker compose -f docker-compose.toolkit.yml run -it --rm node su -c "cd wp-content/themes/${WP_DEFAULT_THEME} && npm run lint" $(DEFAULT_USER)

# IasC
basis:
	docker compose -f docker-compose.toolkit.yml run --rm -it iac su -c "cd /srv/kit-modules/basis && bash" $(DEFAULT_USER)

# Terraform unified command (flags-based)
# Usage examples:
# make tf dev init        -> bash ... -e dev -c init
# make tf prod apply      -> bash ... -e prod -c apply
tf:
	bash ./kit-modules/basis/sh/terraform.sh -e $(PARAM1) -c $(PARAM2)

# Ansible unified command (flags-based)
# Usage examples:
# make ansible dev inventory        -> bash ... -e dev -a inventory
# make ansible dev playbook         -> bash ... -e dev -a playbook
# make ansible dev playbook static  -> bash ... -e dev -a playbook -s
ansible:
	bash ./kit-modules/basis/sh/ansible.sh -e $(PARAM1) -a $(PARAM2) $(if $(filter static,$(PARAM3)),-s)

# docker build|docker push|docker clean|docker login
docker:
	bash ./sh/system/docker.sh $(PARAMS)

# Login to GitHub Container Registry only (no build/push)
docker-login:
	bash ./sh/system/docker.sh login

# Run monitoring scenario
monitoring:
	if [ -f ./kit-modules/monitoring-client/sh/monitoring.sh ]; then \
		bash ./kit-modules/monitoring-client/sh/monitoring.sh -m $(PARAM1); \
	else \
		echo "Monitoring script not found, skipping..."; \
	fi

mon:
	$(MAKE) monitoring $(PARAMS)

# Reverse proxy for multi-instance mode — requires the solidbunch/proxy kit module.
# `make proxy start|stop|logs`, and `make proxy deploy <env>` (used by CI).
proxy:
	if [ -f ./kit-modules/proxy/bin/proxy.sh ]; then \
		bash ./kit-modules/proxy/bin/proxy.sh $(PARAMS); \
	elif [ "$${APP_MULTI_INSTANCE:-0}" = "1" ]; then \
		echo "[Error] APP_MULTI_INSTANCE=1 but kit-modules/proxy is not installed. Run: composer require solidbunch/proxy"; \
		exit 1; \
	else \
		echo "Proxy module not found, skipping..."; \
	fi

# This is a hack to allow passing arguments to the make command
# % is a wildcard. If no rule is matched (for arguments), this goal will be run
%:
# Do nothing
	@:
