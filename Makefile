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

# `make localci <up|down|tf|ansible|act> ...` reuses the words up/down/tf/ansible as its
# subcommand names, which happen to collide with this Makefile's own `up`/`down`/`tf`/`ansible`
# targets: `make localci up` lists BOTH `localci` and `up` as goals, so make would otherwise also
# build the real `up:` target (bringing up the whole app stack) alongside `localci`'s own recipe —
# same problem for `down` (destructive `docker compose down -v`), `tf`, `ansible`. Guard those four
# targets to no-op whenever `localci` is also one of the goals, deferring entirely to `localci`'s
# own recipe for that invocation. Does not change their normal (non-`localci`) behaviour at all.
LOCALCI_GOAL := $(filter localci,$(MAKECMDGOALS))
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

# Locally-trusted (mkcert) HTTPS certificate for local dev, single- or multi-instance mode.
# `make local-cert` / `make local-cert force` (force regenerates even if a valid cert exists).
local-cert:
	bash ./sh/system/local-cert.sh $(PARAMS)

core-install:
	docker compose $(COMPOSE_OVERRIDE) exec php su -c "bash /shell/wp-cli/core-install.sh" $(DEFAULT_USER)

# Run mix watch with browserSync
watch:
	$(LOGO_SH)
	bash ./sh/dev/npm-watch.sh $(PARAMS)

# Regular docker compose up with root .env file concatenation
# Guarded no-op when invoked alongside `localci` (see LOCALCI_GOAL above) — `make localci up`
# must only run the harness, never the app stack.
up:
ifeq ($(LOCALCI_GOAL),)
	$(LOGO_SH)
	bash ./sh/env/init.sh $(PARAMS)
	docker compose $(COMPOSE_OVERRIDE) up -d
endif

# docker compose up with root .env file concatenation without `-d`
upd:
	$(LOGO_SH)
	bash ./sh/env/init.sh $(PARAMS)
	docker compose $(COMPOSE_OVERRIDE) up

# Just docker compose down
# Guarded no-op when invoked alongside `localci` (see LOCALCI_GOAL above) — `make localci down`
# must only tear down the harness, never the app stack.
down:
ifeq ($(LOCALCI_GOAL),)
	docker compose $(COMPOSE_OVERRIDE) down -v
endif

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
# Guarded no-op when invoked alongside `localci` (see LOCALCI_GOAL above) — `make localci tf`
# only prints the reminder from the `localci` target itself, it does not also run real Terraform.
tf:
ifeq ($(LOCALCI_GOAL),)
	bash ./kit-modules/basis/sh/terraform.sh -e $(PARAM1) -c $(PARAM2)
endif

# Ansible unified command (flags-based)
# Usage examples:
# make ansible dev inventory        -> bash ... -e dev -a inventory
# make ansible dev playbook         -> bash ... -e dev -a playbook
# make ansible dev playbook static  -> bash ... -e dev -a playbook -s
# Guarded no-op when invoked alongside `localci` (see LOCALCI_GOAL above) — same reasoning as `tf`.
ansible:
ifeq ($(LOCALCI_GOAL),)
	bash ./kit-modules/basis/sh/ansible.sh -e $(PARAM1) -a $(PARAM2) $(if $(filter static,$(PARAM3)),-s)
endif

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
		echo "[Error] APP_MULTI_INSTANCE=1 but kit-modules/proxy is not installed. Configure a valid SolidBunch license (COMPOSER_AUTH) and run: composer update solidbunch/proxy"; \
		exit 1; \
	else \
		echo "Proxy module not found, skipping..."; \
	fi

# Local TCP tunnel to an instance's MariaDB when APP_MULTI_INSTANCE=1 hides the host port.
# Foundation utility, independent of the proxy module. `make db-tunnel start|stop|status [port]`.
db-tunnel:
	bash ./sh/system/db-tunnel.sh $(PARAMS)

# Local CI/CD provisioning emulation harness (sh/local-ci/*) — see sh/local-ci/README.md.
# `make localci up`     -> bash ./sh/local-ci/harness-up.sh
# `make localci down`   -> bash ./sh/local-ci/harness-down.sh
# `make localci tf`     -> reminder: real Terraform runs go through
#                          kit-modules/basis/sh/terraform.sh directly, once the harness is up. No
#                          parallel abstraction here.
# `make localci ansible`-> reminder: real Ansible runs go through kit-modules/basis/sh/ansible.sh
#                          directly, once the harness is up.
# `make localci act -- <act-run.sh args>` -> bash ./sh/local-ci/act-run.sh <args> — the only
#                          allowed entry point for `act`; never call `act` directly (see
#                          sh/local-ci/README.md, "Data-loss guard rails").
localci:
	if [ "$(PARAM1)" = "up" ]; then \
		bash ./sh/local-ci/harness-up.sh; \
	elif [ "$(PARAM1)" = "down" ]; then \
		bash ./sh/local-ci/harness-down.sh $(if $(filter --force-restore,$(PARAM2)),--force-restore); \
	elif [ "$(PARAM1)" = "tf" ]; then \
		echo "Bring the harness up first: make localci up"; \
		echo "Then run Terraform for real, per layer (state -> shared -> dev), e.g.:"; \
		echo "  bash kit-modules/basis/sh/terraform.sh -e state -c init"; \
		echo "  bash kit-modules/basis/sh/terraform.sh -e state -c plan -f tfplans/state.tfplan"; \
		echo "  bash kit-modules/basis/sh/terraform.sh -e state -c apply -f tfplans/state.tfplan"; \
		echo "See sh/local-ci/README.md for the full walkthrough."; \
	elif [ "$(PARAM1)" = "ansible" ]; then \
		echo "Bring the harness up first: make localci up"; \
		echo "Then run Ansible for real, e.g.:"; \
		echo "  bash kit-modules/basis/sh/ansible.sh -e dev -a inventory"; \
		echo "  bash kit-modules/basis/sh/ansible.sh -e dev -a playbook"; \
		echo "See sh/local-ci/README.md for the full walkthrough."; \
	elif [ "$(PARAM1)" = "act" ]; then \
		bash ./sh/local-ci/act-run.sh $(wordlist 2,$(words $(PARAMS)),$(PARAMS)); \
	else \
		echo "Usage: make localci [up|down|tf|ansible|act]"; \
		echo "See sh/local-ci/README.md."; \
		exit 1; \
	fi

# Validate nginx config syntax (`nginx -t`) in a throwaway container, no app stack needed.
validate-nginx:
	bash ./sh/system/validate-nginx.sh $(PARAMS)

# This is a hack to allow passing arguments to the make command
# % is a wildcard. If no rule is matched (for arguments), this goal will be run
%:
# Do nothing
	@:
